import { fileIo as fs } from '@kit.CoreFileKit';
import nativeSvga, { SvgaMovieEntity } from 'libsvgaplayer.so';
import {
  SvgaImageDecodeOptions,
  SvgaImageDecoder
} from '../image/SvgaImageDecoder';

export class SvgaParser {
  static async parse(data: Uint8Array,
    options: SvgaImageDecodeOptions = new SvgaImageDecodeOptions()): Promise<SvgaMovieEntity> {
    const movie: SvgaMovieEntity = await nativeSvga.parse(data);
    return SvgaImageDecoder.decode(movie, options);
  }

  static async parseSource(source: ResourceStr | Uint8Array, context: Context,
    options: SvgaImageDecodeOptions = new SvgaImageDecodeOptions()): Promise<SvgaMovieEntity> {
    const data: Uint8Array = await SvgaParser.readSource(source, context);
    return SvgaParser.parse(data, options);
  }

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
