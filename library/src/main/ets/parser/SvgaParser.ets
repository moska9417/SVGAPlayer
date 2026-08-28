import { fileIo as fs } from '@kit.CoreFileKit';
import nativeSvga, { SvgaMovieEntity } from 'libsvgaplayer.so';
import {
  SvgaImageDecodeOptions,
  SvgaImageDecoder
} from '../image/SvgaImageDecoder';

/** 提供 SVGA 2.x 数据读取、Native 解析、图片解码和资源释放能力。 */
export class SvgaParser {
  /**
   * 解析完整的 SVGA 二进制数据，并解码其中的图片。
   *
   * @param data 完整的 SVGA 2.x 文件字节。
   * @param options 图片解码选项。
   * @returns 可直接用于播放器或 Canvas 渲染的动画实体。
   * @throws 数据为空、格式不受支持、Native 解析失败或图片解码失败时拒绝 Promise。
   */
  static async parse(data: Uint8Array,
    options: SvgaImageDecodeOptions = new SvgaImageDecodeOptions()): Promise<SvgaMovieEntity> {
    const movie: SvgaMovieEntity = await nativeSvga.parse(data);
    return SvgaImageDecoder.decode(movie, options);
  }

  /**
   * 从媒体资源、本地文件路径或内存字节读取并解析 SVGA。
   *
   * @param source `$r('app.media.xxx')` 媒体资源、本地路径、`file://` 路径或完整字节。
   * @param context 用于读取应用媒体资源的宿主 Context。
   * @param options 图片解码选项。
   * @returns 可直接用于播放器或 Canvas 渲染的动画实体。
   * @throws 路径为空、远程 URL、资源读取失败、文件读取失败、解析失败或图片解码失败时拒绝 Promise。
   * @remarks 本方法不负责网络下载；HTTP 或 HTTPS 地址必须由调用方先下载为本地文件或字节。
   */
  static async parseSource(source: ResourceStr | Uint8Array, context: Context,
    options: SvgaImageDecodeOptions = new SvgaImageDecodeOptions()): Promise<SvgaMovieEntity> {
    const data: Uint8Array = await SvgaParser.readSource(source, context);
    return SvgaParser.parse(data, options);
  }

  /**
   * 释放动画实体持有的全部 PixelMap。
   *
   * @param movie 不再参与播放或渲染的动画实体。
   * @remarks 调用前必须停止所有使用该实体的播放器；重复调用是安全的。
   */
  static async release(movie: SvgaMovieEntity): Promise<void> {
    await SvgaImageDecoder.release(movie);
  }

  private static async readSource(source: ResourceStr | Uint8Array, context: Context): Promise<Uint8Array> {
    if (source instanceof Uint8Array) {
      return source;
    }
    if (typeof source === 'string') {
      if (source.length === 0) {
        throw new Error('SVGA source is empty');
      }
      if (source.startsWith('http://') || source.startsWith('https://')) {
        throw new Error('Remote SVGA source must be downloaded before parsing');
      }
      return SvgaParser.readFile(source);
    }
    try {
      return await context.resourceManager.getMediaContent(source.id);
    } catch {
      throw new Error('Failed to read SVGA media resource');
    }
  }

  private static async readFile(path: string): Promise<Uint8Array> {
    const realPath: string = path.startsWith('file://') ? path.substring(7) : path;
    let file: fs.File | undefined = undefined;
    try {
      file = await fs.open(realPath, fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = await fs.stat(file.fd);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, buffer);
      return new Uint8Array(buffer);
    } catch {
      throw new Error('Failed to read local SVGA file');
    } finally {
      if (file !== undefined) {
        try {
          await fs.close(file.fd);
        } catch {
        }
      }
    }
  }
}
