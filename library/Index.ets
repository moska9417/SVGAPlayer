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

export class SvgaNative {
  static protobufVersion(): string {
    return nativeSvga.protobufVersion();
  }

  static parse(data: Uint8Array): Promise<SvgaMovieEntity> {
    return nativeSvga.parse(data);
  }
}
