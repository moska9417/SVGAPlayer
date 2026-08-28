import { image } from '@kit.ImageKit';
import {
  SvgaFrameEntity,
  SvgaImageData,
  SvgaLayout,
  SvgaMovieEntity,
  SvgaShapeEntity,
  SvgaSpriteEntity,
  SvgaTransform
} from 'libsvgaplayer.so';
import { SvgaShapeType } from '../model/SvgaModel';
import {
  SvgaPathRenderer,
  SvgaShapeRenderStats
} from './SvgaPathRenderer';

export class SvgaContentMode {
  static readonly SCALE_TO_FILL: number = 0;
  static readonly ASPECT_FIT: number = 1;
  static readonly ASPECT_FILL: number = 2;
}

class SvgaCanvasTransform {
  a: number = 1;
  b: number = 0;
  c: number = 0;
  d: number = 1;
  tx: number = 0;
  ty: number = 0;
}

export class SvgaRenderResult {
  success: boolean = true;
  frame: number = 0;
  drawnSprites: number = 0;
  drawnImages: number = 0;
  drawnShapes: number = 0;
  appliedClipPaths: number = 0;
  skippedImages: number = 0;
  skippedShapes: number = 0;
  skippedClipPaths: number = 0;
  skippedMattes: number = 0;
  errorCode: string = '';
  errorMessage: string = '';

  fail(code: string, message: string): void {
    this.success = false;
    this.errorCode = code;
    this.errorMessage = message;
  }
}

export class SvgaCanvasRenderer {
  private movie: SvgaMovieEntity;
  private readonly imageMap: Map<string, image.PixelMap> = new Map<string, image.PixelMap>();
  private readonly pathRenderer: SvgaPathRenderer = new SvgaPathRenderer();
  private shapeFrameIndices: Array<Array<number>> = [];

  constructor(movie: SvgaMovieEntity) {
    this.movie = movie;
    this.reloadImages();
    this.rebuildShapeFrameIndices();
  }

  setMovie(movie: SvgaMovieEntity): void {
    this.movie = movie;
    this.pathRenderer.clearCache();
    this.reloadImages();
    this.rebuildShapeFrameIndices();
  }

  reloadImages(): void {
    this.imageMap.clear();
    for (let index: number = 0; index < this.movie.images.length; index++) {
      const imageData: SvgaImageData = this.movie.images[index];
      if (imageData.pixelMap !== undefined) {
        this.imageMap.set(imageData.key, imageData.pixelMap);
      }
    }
  }

  clear(context: CanvasRenderingContext2D): void {
    context.reset();
  }

  drawFrame(context: CanvasRenderingContext2D, requestedFrame: number,
    contentMode: number = SvgaContentMode.ASPECT_FIT): SvgaRenderResult {
    const result: SvgaRenderResult = new SvgaRenderResult();
    const frame: number = Math.floor(requestedFrame);
    result.frame = frame;
    context.reset();

    if (this.movie.params === undefined || this.movie.params.viewBoxWidth <= 0 ||
      this.movie.params.viewBoxHeight <= 0) {
      result.fail('SVGA_RENDER_INVALID_MOVIE', 'SVGA viewBox is missing or invalid');
      return result;
    }

    const frameCount: number = this.resolveFrameCount();
    if (!Number.isFinite(requestedFrame) || frame < 0 || frame >= frameCount) {
      result.fail('SVGA_RENDER_FRAME_OUT_OF_RANGE', 'SVGA frame is outside the movie range');
      return result;
    }
    // context.width/height 返回单位为 vp，而本 context 的绘制单位为 px（LengthMetricsUnit.PX），
    // 需要转换为 px，否则高分屏上绘制内容会按 density 缩小。
    const canvasWidth: number = vp2px(context.width);
    const canvasHeight: number = vp2px(context.height);
    if (canvasWidth <= 0 || canvasHeight <= 0) {
      result.fail('SVGA_RENDER_INVALID_CANVAS', 'Canvas width or height is zero');
      return result;
    }

    try {
      context.imageSmoothingEnabled = true;
      const canvasTransform: SvgaCanvasTransform = this.resolveCanvasTransform(contentMode,
        this.movie.params.viewBoxWidth, this.movie.params.viewBoxHeight, canvasWidth, canvasHeight);
      for (let index: number = 0; index < this.movie.sprites.length; index++) {
        this.drawSprite(context, this.movie.sprites[index], index, frame, canvasTransform, result);
      }
    } catch {
      context.reset();
      result.fail('SVGA_RENDER_FAILED', 'Canvas failed while drawing the SVGA frame');
    }
    return result;
  }

  private resolveFrameCount(): number {
    if (this.movie.params !== undefined && this.movie.params.frames > 0) {
      return this.movie.params.frames;
    }
    let frameCount: number = 0;
    for (let index: number = 0; index < this.movie.sprites.length; index++) {
      frameCount = Math.max(frameCount, this.movie.sprites[index].frames.length);
    }
    return frameCount;
  }

  private resolveCanvasTransform(contentMode: number, viewBoxWidth: number, viewBoxHeight: number,
    canvasWidth: number, canvasHeight: number): SvgaCanvasTransform {
    let scaleX: number = canvasWidth / viewBoxWidth;
    let scaleY: number = canvasHeight / viewBoxHeight;
    if (contentMode === SvgaContentMode.ASPECT_FILL) {
      const scale: number = Math.max(scaleX, scaleY);
      scaleX = scale;
      scaleY = scale;
    } else if (contentMode !== SvgaContentMode.SCALE_TO_FILL) {
      const scale: number = Math.min(scaleX, scaleY);
      scaleX = scale;
      scaleY = scale;
    }

    const transform: SvgaCanvasTransform = new SvgaCanvasTransform();
    transform.a = scaleX;
    transform.d = scaleY;
    transform.tx = (canvasWidth - viewBoxWidth * scaleX) / 2;
    transform.ty = (canvasHeight - viewBoxHeight * scaleY) / 2;
    return transform;
  }

  private drawSprite(context: CanvasRenderingContext2D, sprite: SvgaSpriteEntity,
    spriteIndex: number, frameIndex: number, canvasTransform: SvgaCanvasTransform,
    result: SvgaRenderResult): void {
    if (frameIndex >= sprite.frames.length) {
      return;
    }
    const frame: SvgaFrameEntity = sprite.frames[frameIndex];
    if (!Number.isFinite(frame.alpha) || frame.alpha <= 0) {
      return;
    }
    if (sprite.matteKey !== undefined && sprite.matteKey.length > 0) {
      result.skippedMattes += 1;
    }

    let drewContent: boolean = false;
    context.save();
    context.globalAlpha = Math.max(0, Math.min(1, frame.alpha));
    this.applySpriteTransform(context, canvasTransform, frame.transform);
    if (frame.clipPath !== undefined && frame.clipPath.length > 0) {
      if (this.pathRenderer.applyClipPath(context, frame.clipPath)) {
        result.appliedClipPaths += 1;
      } else {
        result.skippedClipPaths += 1;
      }
    }

    const pixelMap: image.PixelMap | undefined = this.imageMap.get(sprite.imageKey);
    if (pixelMap !== undefined) {
      if (frame.layout !== undefined && frame.layout.width > 0 && frame.layout.height > 0) {
        this.drawImageInLayout(context, pixelMap, frame.layout);
      } else {
        context.drawImage(pixelMap, 0, 0);
      }
      result.drawnImages += 1;
      drewContent = true;
    } else if (sprite.imageKey.length > 0) {
      result.skippedImages += 1;
    }

    const shapes: Array<SvgaShapeEntity> | undefined = this.resolveShapes(spriteIndex, frameIndex);
    if (shapes !== undefined) {
      const shapeStats: SvgaShapeRenderStats = this.pathRenderer.drawShapes(context, shapes);
      result.drawnShapes += shapeStats.drawnShapes;
      result.skippedShapes += shapeStats.skippedShapes;
      if (shapeStats.drawnShapes > 0) {
        drewContent = true;
      }
    }
    context.restore();
    if (drewContent) {
      result.drawnSprites += 1;
    }
  }

  private rebuildShapeFrameIndices(): void {
    this.shapeFrameIndices = [];
    for (let spriteIndex: number = 0; spriteIndex < this.movie.sprites.length; spriteIndex++) {
      const sprite: SvgaSpriteEntity = this.movie.sprites[spriteIndex];
      const indices: Array<number> = [];
      let lastShapeFrame: number = -1;
      for (let frameIndex: number = 0; frameIndex < sprite.frames.length; frameIndex++) {
        const shapes: Array<SvgaShapeEntity> | undefined = sprite.frames[frameIndex].shapes;
        const isKeep: boolean = shapes !== undefined && shapes.length > 0 &&
          shapes[0].type === SvgaShapeType.KEEP;
        if (!isKeep) {
          lastShapeFrame = frameIndex;
        }
        indices.push(lastShapeFrame);
      }
      this.shapeFrameIndices.push(indices);
    }
  }

  private resolveShapes(spriteIndex: number, frameIndex: number): Array<SvgaShapeEntity> | undefined {
    if (spriteIndex >= this.shapeFrameIndices.length ||
      frameIndex >= this.shapeFrameIndices[spriteIndex].length) {
      return undefined;
    }
    const shapeFrameIndex: number = this.shapeFrameIndices[spriteIndex][frameIndex];
    if (shapeFrameIndex < 0) {
      return undefined;
    }
    return this.movie.sprites[spriteIndex].frames[shapeFrameIndex].shapes;
  }

  private applySpriteTransform(context: CanvasRenderingContext2D, canvasTransform: SvgaCanvasTransform,
    frameTransform: SvgaTransform | undefined): void {
    if (frameTransform === undefined) {
      context.setTransform(canvasTransform.a, canvasTransform.b, canvasTransform.c, canvasTransform.d,
        canvasTransform.tx, canvasTransform.ty);
      return;
    }

    const a: number = canvasTransform.a * frameTransform.a + canvasTransform.c * frameTransform.b;
    const b: number = canvasTransform.b * frameTransform.a + canvasTransform.d * frameTransform.b;
    const c: number = canvasTransform.a * frameTransform.c + canvasTransform.c * frameTransform.d;
    const d: number = canvasTransform.b * frameTransform.c + canvasTransform.d * frameTransform.d;
    const tx: number = canvasTransform.a * frameTransform.tx + canvasTransform.c * frameTransform.ty +
      canvasTransform.tx;
    const ty: number = canvasTransform.b * frameTransform.tx + canvasTransform.d * frameTransform.ty +
      canvasTransform.ty;
    context.setTransform(a, b, c, d, tx, ty);
  }

  private drawImageInLayout(context: CanvasRenderingContext2D, pixelMap: image.PixelMap,
    layout: SvgaLayout): void {
    context.drawImage(pixelMap, layout.x, layout.y, layout.width, layout.height);
  }
}
