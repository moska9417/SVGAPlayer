import { image } from '@kit.ImageKit';
import {
  SvgaImageData,
  SvgaMovieEntity
} from 'libsvgaplayer.so';

/** SVGA 内嵌图片的解码选项。 */
export class SvgaImageDecodeOptions {
  /**
   * 同时执行的图片解码任务数，最终会被限制在 1 到 8 之间。
   *
   * @defaultValue 4
   */
  concurrency: number = 4;
  /**
   * 图片成功转换为 PixelMap 后是否丢弃原始编码数据，以降低内存占用。
   *
   * @defaultValue true
   */
  discardEncodedData: boolean = true;
}

/** 单张 SVGA 内嵌图片解码失败时抛出的错误。 */
export class SvgaImageDecodeError extends Error {
  /** 稳定的错误码。 */
  readonly code: string = 'SVGA_IMAGE_DECODE_FAILED';
  /** 解码失败的 SVGA 图片键。 */
  readonly imageKey: string;
  /** Native 或底层解码错误码；当前 Image Kit 错误通常为 0。 */
  readonly nativeCode: number;

  /**
   * 创建图片解码错误。
   *
   * @param imageKey 解码失败的图片键。
   * @param nativeCode Native 或底层解码错误码。
   * @param detail 便于诊断的错误详情。
   */
  constructor(imageKey: string, nativeCode: number, detail: string) {
    super('Failed to decode SVGA image "' + imageKey + '": ' + detail);
    this.imageKey = imageKey;
    this.nativeCode = nativeCode;
  }
}

class SvgaImageDecodeResult {
  pixelMap: image.PixelMap | undefined = undefined;
  error: SvgaImageDecodeError | undefined = undefined;
}

class SvgaImageDecodeState {
  readonly images: Array<SvgaImageData>;
  private nextIndex: number = 0;
  private cancelled: boolean = false;
  error: SvgaImageDecodeError | undefined = undefined;

  constructor(images: Array<SvgaImageData>) {
    this.images = images;
  }

  takeNextIndex(): number {
    if (this.cancelled || this.nextIndex >= this.images.length) {
      return -1;
    }
    const index: number = this.nextIndex;
    this.nextIndex += 1;
    return index;
  }

  fail(error: SvgaImageDecodeError): void {
    if (this.error === undefined) {
      this.error = error;
    }
    this.cancelled = true;
  }
}

class SvgaImageDecodeWorker {
  private readonly state: SvgaImageDecodeState;

  constructor(state: SvgaImageDecodeState) {
    this.state = state;
  }

  async run(): Promise<void> {
    let index: number = this.state.takeNextIndex();
    while (index >= 0) {
      const imageData: SvgaImageData = this.state.images[index];
      const result: SvgaImageDecodeResult = await this.decodeImage(imageData);
      if (result.error !== undefined) {
        this.state.fail(result.error);
        return;
      }
      if (result.pixelMap !== undefined) {
        imageData.pixelMap = result.pixelMap;
      }
      index = this.state.takeNextIndex();
    }
  }

  private async decodeImage(imageData: SvgaImageData): Promise<SvgaImageDecodeResult> {
    const result: SvgaImageDecodeResult = new SvgaImageDecodeResult();
    if (imageData.data === undefined) {
      result.error = new SvgaImageDecodeError(imageData.key, 0, 'encoded image data is missing');
      return result;
    }

    let imageSource: image.ImageSource | undefined = undefined;
    try {
      imageSource = image.createImageSource(imageData.data);
      if (imageSource === undefined) {
        result.error = new SvgaImageDecodeError(imageData.key, 0, 'ImageSource creation failed');
        return result;
      }
      const decodingOptions: image.DecodingOptions = {
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      result.pixelMap = await imageSource.createPixelMap(decodingOptions);
    } catch {
      result.error = new SvgaImageDecodeError(imageData.key, 0, 'Image Kit decode failed');
    } finally {
      if (imageSource !== undefined) {
        try {
          await imageSource.release();
        } catch {
        }
      }
    }
    return result;
  }
}

/** 将动画实体中的编码图片批量转换为 PixelMap，并负责释放图片资源。 */
export class SvgaImageDecoder {
  /**
   * 解码动画中的全部非音频图片。
   *
   * @param movie Native 解析得到的动画实体。
   * @param options 并发数和编码数据保留策略。
   * @returns 原动画实体；成功解码的图片会写入各自的 `pixelMap` 字段。
   * @throws 任意图片缺失编码数据或 Image Kit 解码失败时抛出 {@link SvgaImageDecodeError}。
   */
  static async decode(movie: SvgaMovieEntity,
    options: SvgaImageDecodeOptions = new SvgaImageDecodeOptions()): Promise<SvgaMovieEntity> {
    const targets: Array<SvgaImageData> = SvgaImageDecoder.collectDecodeTargets(movie);
    if (targets.length > 0) {
      const state: SvgaImageDecodeState = new SvgaImageDecodeState(targets);
      const workerCount: number = Math.min(SvgaImageDecoder.normalizeConcurrency(options.concurrency), targets.length);
      const tasks: Array<Promise<void>> = [];
      for (let index: number = 0; index < workerCount; index++) {
        const worker: SvgaImageDecodeWorker = new SvgaImageDecodeWorker(state);
        tasks.push(worker.run());
      }
      await Promise.all(tasks);

      if (state.error !== undefined) {
        await SvgaImageDecoder.releaseImages(targets);
        throw state.error;
      }
    }

    if (options.discardEncodedData) {
      SvgaImageDecoder.discardDecodedImageData(movie);
    }
    return movie;
  }

  /**
   * 释放动画实体持有的全部 PixelMap，并清空对应引用。
   *
   * @param movie 不再参与解析或渲染的动画实体。
   * @remarks 调用前应停止所有使用该实体的播放器和渲染器。重复调用是安全的。
   */
  static async release(movie: SvgaMovieEntity): Promise<void> {
    await SvgaImageDecoder.releaseImages(movie.images);
  }

  private static collectDecodeTargets(movie: SvgaMovieEntity): Array<SvgaImageData> {
    const targets: Array<SvgaImageData> = [];
    for (let index: number = 0; index < movie.images.length; index++) {
      const imageData: SvgaImageData = movie.images[index];
      if (imageData.pixelMap === undefined && !SvgaImageDecoder.isAudioKey(movie, imageData.key)) {
        targets.push(imageData);
      }
    }
    return targets;
  }

  private static isAudioKey(movie: SvgaMovieEntity, key: string): boolean {
    for (let index: number = 0; index < movie.audios.length; index++) {
      if (movie.audios[index].audioKey === key) {
        return true;
      }
    }
    return false;
  }

  private static normalizeConcurrency(concurrency: number): number {
    if (!Number.isFinite(concurrency)) {
      return 4;
    }
    return Math.max(1, Math.min(8, Math.floor(concurrency)));
  }

  private static discardDecodedImageData(movie: SvgaMovieEntity): void {
    for (let index: number = 0; index < movie.images.length; index++) {
      const imageData: SvgaImageData = movie.images[index];
      if (imageData.pixelMap !== undefined) {
        imageData.data = undefined;
      }
    }
  }

  private static async releaseImages(images: Array<SvgaImageData>): Promise<void> {
    for (let index: number = 0; index < images.length; index++) {
      const imageData: SvgaImageData = images[index];
      if (imageData.pixelMap !== undefined) {
        try {
          await imageData.pixelMap.release();
        } catch {
        }
        imageData.pixelMap = undefined;
      }
    }
  }
}
