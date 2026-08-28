import { image } from '@kit.ImageKit';
import {
  SvgaImageData,
  SvgaMovieEntity
} from 'libsvgaplayer.so';

export class SvgaImageDecodeOptions {
  concurrency: number = 4;
  discardEncodedData: boolean = true;
}

export class SvgaImageDecodeError extends Error {
  readonly code: string = 'SVGA_IMAGE_DECODE_FAILED';
  readonly imageKey: string;
  readonly nativeCode: number;

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

export class SvgaImageDecoder {
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
