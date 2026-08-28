import { image } from '@kit.ImageKit';

export interface SvgaMovieParams {
  viewBoxWidth: number;
  viewBoxHeight: number;
  fps: number;
  frames: number;
}

export interface SvgaLayout {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface SvgaTransform {
  a: number;
  b: number;
  c: number;
  d: number;
  tx: number;
  ty: number;
}

export interface SvgaColor {
  r: number;
  g: number;
  b: number;
  a: number;
}

export interface SvgaShapeStyle {
  fill?: SvgaColor;
  stroke?: SvgaColor;
  strokeWidth: number;
  lineCap: number;
  lineJoin: number;
  miterLimit: number;
  lineDashI: number;
  lineDashII: number;
  lineDashIII: number;
}

export interface SvgaShapeArgs {
  d: string;
}

export interface SvgaRectArgs {
  x: number;
  y: number;
  width: number;
  height: number;
  cornerRadius: number;
}

export interface SvgaEllipseArgs {
  x: number;
  y: number;
  radiusX: number;
  radiusY: number;
}

export interface SvgaShapeEntity {
  type: number;
  shape?: SvgaShapeArgs;
  rect?: SvgaRectArgs;
  ellipse?: SvgaEllipseArgs;
  styles?: SvgaShapeStyle;
  transform?: SvgaTransform;
}

export interface SvgaFrameEntity {
  alpha: number;
  layout?: SvgaLayout;
  transform?: SvgaTransform;
  clipPath?: string;
  shapes?: Array<SvgaShapeEntity>;
}

export interface SvgaSpriteEntity {
  imageKey: string;
  frames: Array<SvgaFrameEntity>;
  matteKey?: string;
}

export interface SvgaAudioEntity {
  audioKey: string;
  startFrame: number;
  endFrame: number;
  startTime: number;
  totalTime: number;
}

export interface SvgaImageData {
  key: string;
  data?: ArrayBuffer;
  pixelMap?: image.PixelMap;
}

export interface SvgaMovieEntity {
  version: string;
  params?: SvgaMovieParams;
  images: Array<SvgaImageData>;
  sprites: Array<SvgaSpriteEntity>;
  audios: Array<SvgaAudioEntity>;
}

export const protobufVersion: () => string;
export const parse: (data: Uint8Array) => Promise<SvgaMovieEntity>;
