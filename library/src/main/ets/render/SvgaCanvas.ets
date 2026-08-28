import { LengthMetricsUnit } from '@kit.ArkUI';
import { SvgaMovieEntity } from 'libsvgaplayer.so';
import {
  SvgaCanvasRenderer,
  SvgaContentMode,
  SvgaRenderResult
} from './SvgaCanvasRenderer';

/** 静态帧绘制完成后触发的回调。 */
export type SvgaRenderCallback = (result: SvgaRenderResult) => void;

/**
 * 在 ArkUI Canvas 上绘制指定 SVGA 帧的无时间轴组件。
 *
 * @remarks 组件不拥有 `movie`，不会自动释放其中的 PixelMap。适用于封面、缩略图和业务自定义时间轴。
 */
@Component
export struct SvgaCanvas {
  /** 已完成图片解码的动画实体。 */
  @Prop @Watch('onMovieChange') movie: SvgaMovieEntity | undefined = undefined;
  /** 要绘制的从 0 开始的帧序号，默认为 0。 */
  @Prop @Watch('onRenderInputChange') frame: number = 0;
  /** 缩放模式，使用 {@link SvgaContentMode} 中的值，默认为 ASPECT_FIT。 */
  @Prop @Watch('onRenderInputChange') contentMode: number = SvgaContentMode.ASPECT_FIT;
  /** 每次尝试绘制后触发，返回绘制统计或错误信息。 */
  onRendered?: SvgaRenderCallback;

  private readonly settings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly context: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private renderer: SvgaCanvasRenderer | undefined = undefined;
  private renderedMovie: SvgaMovieEntity | undefined = undefined;
  private canvasReady: boolean = false;

  aboutToDisappear(): void {
    this.canvasReady = false;
    this.renderer = undefined;
    this.renderedMovie = undefined;
    this.context.reset();
  }

  private onMovieChange(): void {
    this.renderer = undefined;
    this.renderedMovie = undefined;
    this.redraw();
  }

  private onRenderInputChange(): void {
    this.redraw();
  }

  private redraw(): void {
    if (!this.canvasReady) {
      return;
    }
    if (this.movie === undefined) {
      this.context.reset();
      return;
    }
    if (this.renderer === undefined || this.renderedMovie !== this.movie) {
      this.renderer = new SvgaCanvasRenderer(this.movie);
      this.renderedMovie = this.movie;
    }
    const result: SvgaRenderResult = this.renderer.drawFrame(this.context, this.frame, this.contentMode);
    if (this.onRendered !== undefined) {
      this.onRendered(result);
    }
  }

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.canvasReady = true;
        this.redraw();
      })
  }
}
