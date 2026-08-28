import { image } from '@kit.ImageKit';

/** SVGA 动画画布与时间轴参数。 */
export interface SvgaMovieParams {
  /** 动画设计画布宽度，单位为设计像素。 */
  viewBoxWidth: number;
  /** 动画设计画布高度，单位为设计像素。 */
  viewBoxHeight: number;
  /** 动画原始帧率。 */
  fps: number;
  /** 动画总帧数。 */
  frames: number;
}

/** 精灵在设计画布中的布局区域。 */
export interface SvgaLayout {
  /** 左上角横坐标。 */
  x: number;
  /** 左上角纵坐标。 */
  y: number;
  /** 布局宽度。 */
  width: number;
  /** 布局高度。 */
  height: number;
}

/** 二维仿射变换矩阵。 */
export interface SvgaTransform {
  /** 水平缩放与旋转分量。 */
  a: number;
  /** 垂直倾斜与旋转分量。 */
  b: number;
  /** 水平倾斜与旋转分量。 */
  c: number;
  /** 垂直缩放与旋转分量。 */
  d: number;
  /** 水平平移量。 */
  tx: number;
  /** 垂直平移量。 */
  ty: number;
}

/** 归一化 RGBA 颜色，各通道推荐取值范围为 0 到 1。 */
export interface SvgaColor {
  /** 红色通道。 */
  r: number;
  /** 绿色通道。 */
  g: number;
  /** 蓝色通道。 */
  b: number;
  /** 透明度通道。 */
  a: number;
}

/** 矢量图形的填充与描边样式。 */
export interface SvgaShapeStyle {
  /** 可选的填充颜色。 */
  fill?: SvgaColor;
  /** 可选的描边颜色。 */
  stroke?: SvgaColor;
  /** 描边宽度。 */
  strokeWidth: number;
  /** 线帽类型，使用 {@link SvgaLineCap} 中的值。 */
  lineCap: number;
  /** 线段连接类型，使用 {@link SvgaLineJoin} 中的值。 */
  lineJoin: number;
  /** 斜接限制。 */
  miterLimit: number;
  /** 虚线第一段长度。 */
  lineDashI: number;
  /** 虚线第二段长度。 */
  lineDashII: number;
  /** 虚线起始偏移。 */
  lineDashIII: number;
}

/** SVG Path 图形参数。 */
export interface SvgaShapeArgs {
  /** SVG PathData 字符串。 */
  d: string;
}

/** 矩形图形参数。 */
export interface SvgaRectArgs {
  /** 左上角横坐标。 */
  x: number;
  /** 左上角纵坐标。 */
  y: number;
  /** 矩形宽度。 */
  width: number;
  /** 矩形高度。 */
  height: number;
  /** 圆角半径。 */
  cornerRadius: number;
}

/** 椭圆图形参数。 */
export interface SvgaEllipseArgs {
  /** 椭圆中心横坐标。 */
  x: number;
  /** 椭圆中心纵坐标。 */
  y: number;
  /** 水平半径。 */
  radiusX: number;
  /** 垂直半径。 */
  radiusY: number;
}

/** 单个矢量图形实体。 */
export interface SvgaShapeEntity {
  /** 图形类型，使用 {@link SvgaShapeType} 中的值。 */
  type: number;
  /** Path 图形参数，仅在类型为 SHAPE 时存在。 */
  shape?: SvgaShapeArgs;
  /** 矩形参数，仅在类型为 RECT 时存在。 */
  rect?: SvgaRectArgs;
  /** 椭圆参数，仅在类型为 ELLIPSE 时存在。 */
  ellipse?: SvgaEllipseArgs;
  /** 可选的绘制样式。 */
  styles?: SvgaShapeStyle;
  /** 可选的局部仿射变换。 */
  transform?: SvgaTransform;
}

/** 精灵在单帧中的绘制数据。 */
export interface SvgaFrameEntity {
  /** 帧透明度，通常取值范围为 0 到 1。 */
  alpha: number;
  /** 可选的图片布局区域。 */
  layout?: SvgaLayout;
  /** 可选的精灵仿射变换。 */
  transform?: SvgaTransform;
  /** 可选的 SVG Path 裁剪路径。 */
  clipPath?: string;
  /** 可选的矢量图形列表。 */
  shapes?: Array<SvgaShapeEntity>;
}

/** SVGA 精灵及其逐帧数据。 */
export interface SvgaSpriteEntity {
  /** 关联的图片键；纯矢量精灵可为空字符串。 */
  imageKey: string;
  /** 精灵的逐帧数据。 */
  frames: Array<SvgaFrameEntity>;
  /** 可选的遮罩精灵键；当前版本暂不执行 matte 合成。 */
  matteKey?: string;
}

/** SVGA 音频时间轴信息。当前播放器暂不播放音频。 */
export interface SvgaAudioEntity {
  /** 关联的音频资源键。 */
  audioKey: string;
  /** 音频开始帧。 */
  startFrame: number;
  /** 音频结束帧。 */
  endFrame: number;
  /** 音频起始时间。 */
  startTime: number;
  /** 音频总时长。 */
  totalTime: number;
}

/** 动画中内嵌的图片或音频二进制数据。 */
export interface SvgaImageData {
  /** 资源唯一键。 */
  key: string;
  /** 原始编码数据；启用丢弃策略后可能被清空。 */
  data?: ArrayBuffer;
  /** 解码后的图片对象；使用结束后必须释放。 */
  pixelMap?: image.PixelMap;
}

/** Native 解析后的完整 SVGA 动画实体。 */
export interface SvgaMovieEntity {
  /** SVGA 文件声明的格式版本。 */
  version: string;
  /** 可选的画布和时间轴参数。 */
  params?: SvgaMovieParams;
  /** 动画内嵌资源列表。 */
  images: Array<SvgaImageData>;
  /** 动画精灵列表。 */
  sprites: Array<SvgaSpriteEntity>;
  /** 动画音频时间轴列表。 */
  audios: Array<SvgaAudioEntity>;
}

/**
 * 获取 Native 解析器链接的 protobuf 版本。
 *
 * @returns protobuf 语义化版本字符串。
 */
export const protobufVersion: () => string;

/**
 * 在 Native 工作线程中解析 SVGA 2.x 二进制数据。
 *
 * @param data 完整的 SVGA 文件字节。
 * @returns 解析后的动画实体；图片仍为编码数据，尚未转换为 PixelMap。
 * @throws 输入为空、不是受支持的 SVGA 2.x 数据或 Native 解析失败时拒绝 Promise。
 */
export const parse: (data: Uint8Array) => Promise<SvgaMovieEntity>;
