/** SVGA 矢量图形类型常量。 */
export class SvgaShapeType {
  /** SVG Path 图形。 */
  static readonly SHAPE: number = 0;
  /** 矩形。 */
  static readonly RECT: number = 1;
  /** 椭圆。 */
  static readonly ELLIPSE: number = 2;
  /** 复用上一有效帧的图形数据。 */
  static readonly KEEP: number = 3;
}

/** SVGA 描边线帽类型常量。 */
export class SvgaLineCap {
  /** 平直线帽。 */
  static readonly BUTT: number = 0;
  /** 圆形线帽。 */
  static readonly ROUND: number = 1;
  /** 方形线帽。 */
  static readonly SQUARE: number = 2;
}

/** SVGA 描边连接类型常量。 */
export class SvgaLineJoin {
  /** 斜接连接。 */
  static readonly MITER: number = 0;
  /** 圆角连接。 */
  static readonly ROUND: number = 1;
  /** 斜角连接。 */
  static readonly BEVEL: number = 2;
}
