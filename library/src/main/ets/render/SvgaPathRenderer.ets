import { LengthMetricsUnit } from '@kit.ArkUI';
import {
  SvgaColor,
  SvgaShapeEntity,
  SvgaShapeStyle,
  SvgaTransform
} from 'libsvgaplayer.so';
import {
  SvgaLineCap,
  SvgaLineJoin,
  SvgaShapeType
} from '../model/SvgaModel';

/** 一组矢量图形的绘制统计。 */
export class SvgaShapeRenderStats {
  /** 成功绘制的图形数量。 */
  drawnShapes: number = 0;
  /** 因参数无效或 Path 构造失败而跳过的图形数量。 */
  skippedShapes: number = 0;
}

/** 负责解析、缓存和绘制 SVGA 矢量 Path 与裁剪 Path。 */
export class SvgaPathRenderer {
  private readonly clipPathMap: Map<string, Path2D> = new Map<string, Path2D>();
  private readonly shapePathMap: Map<SvgaShapeEntity, Path2D> = new Map<SvgaShapeEntity, Path2D>();

  /** 清空裁剪路径和图形路径缓存；切换动画实体后应调用。 */
  clearCache(): void {
    this.clipPathMap.clear();
    this.shapePathMap.clear();
  }

  /**
   * 解析并应用 SVG PathData 裁剪路径。
   *
   * @param context 目标 Canvas 2D 上下文。
   * @param description SVG PathData 字符串。
   * @returns 路径非空且成功应用时返回 true，否则返回 false。
   */
  applyClipPath(context: CanvasRenderingContext2D, description: string): boolean {
    if (description.length === 0) {
      return false;
    }
    let path: Path2D | undefined = this.clipPathMap.get(description);
    if (path === undefined) {
      try {
        path = new Path2D(description, LengthMetricsUnit.PX);
        this.clipPathMap.set(description, path);
      } catch {
        return false;
      }
    }
    context.clip(path);
    return true;
  }

  /**
   * 按数组顺序绘制一组 SVGA 矢量图形。
   *
   * @param context 目标 Canvas 2D 上下文。
   * @param shapes 当前帧的图形实体列表；KEEP 项会被忽略。
   * @returns 成功和跳过的图形数量。
   */
  drawShapes(context: CanvasRenderingContext2D,
    shapes: Array<SvgaShapeEntity>): SvgaShapeRenderStats {
    const stats: SvgaShapeRenderStats = new SvgaShapeRenderStats();
    for (let index: number = 0; index < shapes.length; index++) {
      const shape: SvgaShapeEntity = shapes[index];
      if (shape.type === SvgaShapeType.KEEP) {
        continue;
      }
      const path: Path2D | undefined = this.resolveShapePath(shape);
      if (path === undefined) {
        stats.skippedShapes += 1;
        continue;
      }
      this.drawShape(context, path, shape);
      stats.drawnShapes += 1;
    }
    return stats;
  }

  private resolveShapePath(shape: SvgaShapeEntity): Path2D | undefined {
    let path: Path2D | undefined = this.shapePathMap.get(shape);
    if (path !== undefined) {
      return path;
    }
    try {
      if (shape.type === SvgaShapeType.SHAPE && shape.shape !== undefined && shape.shape.d.length > 0) {
        path = new Path2D(shape.shape.d, LengthMetricsUnit.PX);
      } else if (shape.type === SvgaShapeType.RECT && shape.rect !== undefined &&
        shape.rect.width > 0 && shape.rect.height > 0) {
        path = this.createRectPath(shape);
      } else if (shape.type === SvgaShapeType.ELLIPSE && shape.ellipse !== undefined &&
        shape.ellipse.radiusX > 0 && shape.ellipse.radiusY > 0) {
        path = this.createEllipsePath(shape);
      }
    } catch {
      return undefined;
    }
    if (path !== undefined) {
      this.shapePathMap.set(shape, path);
    }
    return path;
  }

  private createRectPath(shape: SvgaShapeEntity): Path2D {
    const path: Path2D = new Path2D(LengthMetricsUnit.PX);
    if (shape.rect === undefined) {
      return path;
    }
    const x: number = shape.rect.x;
    const y: number = shape.rect.y;
    const width: number = shape.rect.width;
    const height: number = shape.rect.height;
    const radius: number = Math.max(0, Math.min(shape.rect.cornerRadius, width / 2, height / 2));
    if (radius <= 0) {
      path.rect(x, y, width, height);
      return path;
    }
    path.moveTo(x + radius, y);
    path.lineTo(x + width - radius, y);
    path.arcTo(x + width, y, x + width, y + radius, radius);
    path.lineTo(x + width, y + height - radius);
    path.arcTo(x + width, y + height, x + width - radius, y + height, radius);
    path.lineTo(x + radius, y + height);
    path.arcTo(x, y + height, x, y + height - radius, radius);
    path.lineTo(x, y + radius);
    path.arcTo(x, y, x + radius, y, radius);
    path.closePath();
    return path;
  }

  private createEllipsePath(shape: SvgaShapeEntity): Path2D {
    const path: Path2D = new Path2D(LengthMetricsUnit.PX);
    if (shape.ellipse === undefined) {
      return path;
    }
    path.ellipse(shape.ellipse.x, shape.ellipse.y, shape.ellipse.radiusX,
      shape.ellipse.radiusY, 0, 0, Math.PI * 2, false);
    path.closePath();
    return path;
  }

  private drawShape(context: CanvasRenderingContext2D, path: Path2D,
    shape: SvgaShapeEntity): void {
    context.save();
    if (shape.transform !== undefined) {
      this.applyTransform(context, shape.transform);
    }
    if (shape.styles === undefined) {
      context.fillStyle = '#000000';
      context.fill(path);
      context.restore();
      return;
    }
    this.applyStrokeStyle(context, shape.styles);
    if (shape.styles.fill !== undefined) {
      context.fillStyle = this.colorToRgba(shape.styles.fill);
      context.fill(path);
    }
    if (shape.styles.stroke !== undefined) {
      context.strokeStyle = this.colorToRgba(shape.styles.stroke);
      context.stroke(path);
    }
    context.restore();
  }

  private applyStrokeStyle(context: CanvasRenderingContext2D, style: SvgaShapeStyle): void {
    context.lineWidth = Math.max(0, style.strokeWidth);
    if (style.lineCap === SvgaLineCap.ROUND) {
      context.lineCap = 'round';
    } else if (style.lineCap === SvgaLineCap.SQUARE) {
      context.lineCap = 'square';
    } else {
      context.lineCap = 'butt';
    }
    if (style.lineJoin === SvgaLineJoin.ROUND) {
      context.lineJoin = 'round';
    } else if (style.lineJoin === SvgaLineJoin.BEVEL) {
      context.lineJoin = 'bevel';
    } else {
      context.lineJoin = 'miter';
    }
    context.miterLimit = Math.max(0, style.miterLimit);
    context.setLineDash([
      Math.max(1, style.lineDashI),
      Math.max(0.1, style.lineDashII)
    ]);
    context.lineDashOffset = style.lineDashIII;
  }

  private applyTransform(context: CanvasRenderingContext2D, transform: SvgaTransform): void {
    context.transform(transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty);
  }

  private colorToRgba(color: SvgaColor): string {
    const red: number = Math.round(Math.max(0, Math.min(1, color.r)) * 255);
    const green: number = Math.round(Math.max(0, Math.min(1, color.g)) * 255);
    const blue: number = Math.round(Math.max(0, Math.min(1, color.b)) * 255);
    const alpha: number = Math.max(0, Math.min(1, color.a));
    return 'rgba(' + red.toString() + ',' + green.toString() + ',' + blue.toString() + ',' +
      alpha.toString() + ')';
  }
}
