/**
 * SVGAPlayer for HarmonyOS 公共导出入口。
 *
 * 提供 SVGA 2.x Native 解析、图片解码、ArkUI Canvas 渲染和 DisplaySync 播放能力。
 */
import nativeSvga, { SvgaMovieEntity } from 'libsvgaplayer.so';

export {
  SvgaAudioEntity,
  SvgaColor,
  SvgaEllipseArgs,
  SvgaFrameEntity,
  SvgaImageData,
  SvgaLayout,
  SvgaMovieEntity,
  SvgaMovieParams,
  SvgaRectArgs,
  SvgaShapeArgs,
  SvgaShapeEntity,
  SvgaShapeStyle,
  SvgaSpriteEntity,
  SvgaTransform
} from 'libsvgaplayer.so';

export {
  SvgaLineCap,
  SvgaLineJoin,
  SvgaShapeType
} from './src/main/ets/model/SvgaModel';

export {
  SvgaImageDecodeError,
  SvgaImageDecodeOptions,
  SvgaImageDecoder
} from './src/main/ets/image/SvgaImageDecoder';

export { SvgaParser } from './src/main/ets/parser/SvgaParser';

export { SvgaCanvas, SvgaRenderCallback } from './src/main/ets/render/SvgaCanvas';

export {
  SvgaCanvasRenderer,
  SvgaContentMode,
  SvgaRenderResult
} from './src/main/ets/render/SvgaCanvasRenderer';

export {
  SvgaPathRenderer,
  SvgaShapeRenderStats
} from './src/main/ets/render/SvgaPathRenderer';

export {
  SvgaDisplayLinkContext,
  SvgaDisplayLinkManager,
  SvgaDisplayLinkSubscriber
} from './src/main/ets/player/SvgaDisplayLink';

export {
  SvgaPlaybackState,
  SvgaPlayerClearCallback,
  SvgaPlayerController,
  SvgaPlayerFinishedCallback,
  SvgaPlayerFrameCallback,
  SvgaPlayerRenderCallback
} from './src/main/ets/player/SvgaPlayerController';

export {
  SvgaPlayer,
  SvgaPlayerErrorCallback,
  SvgaPlayerReadyCallback
} from './src/main/ets/player/SvgaPlayer';

/** Native SVGA 解析器的低级直通接口。通常优先使用 {@link SvgaParser}。 */
export class SvgaNative {
  /**
   * 获取 Native 解析器链接的 protobuf 版本。
   *
   * @returns protobuf 语义化版本字符串。
   */
  static protobufVersion(): string {
    return nativeSvga.protobufVersion();
  }

  /**
   * 在 Native 工作线程中解析 SVGA 2.x 二进制数据。
   *
   * @param data 完整的 SVGA 文件字节。
   * @returns Native 解析后的动画实体；其中图片尚未转换为 PixelMap。
   * @throws 输入为空、格式不受支持或 Native 解析失败时拒绝 Promise。
   * @remarks 如需直接渲染，请继续调用 {@link SvgaImageDecoder.decode}，或改用 {@link SvgaParser.parse}。
   */
  static parse(data: Uint8Array): Promise<SvgaMovieEntity> {
    return nativeSvga.parse(data);
  }
}
