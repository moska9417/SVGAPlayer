import { LengthMetricsUnit } from '@kit.ArkUI';
import { SvgaMovieEntity } from 'libsvgaplayer.so';
import {
  SvgaCanvasRenderer,
  SvgaContentMode,
  SvgaRenderResult
} from './SvgaCanvasRenderer';

export type SvgaRenderCallback = (result: SvgaRenderResult) => void;

@Component
export struct SvgaCanvas {
  @Prop @Watch('onMovieChange') movie: SvgaMovieEntity | undefined = undefined;
  @Prop @Watch('onRenderInputChange') frame: number = 0;
  @Prop @Watch('onRenderInputChange') contentMode: number = SvgaContentMode.ASPECT_FIT;
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
