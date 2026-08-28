import { LengthMetricsUnit } from '@kit.ArkUI';
import { SvgaMovieEntity } from 'libsvgaplayer.so';
import { SvgaParser } from '../parser/SvgaParser';
import {
  SvgaCanvasRenderer, SvgaContentMode, SvgaRenderResult
} from '../render/SvgaCanvasRenderer';
import { SvgaPlayerController } from './SvgaPlayerController';

export type SvgaPlayerReadyCallback = (movie: SvgaMovieEntity) => void;

export type SvgaPlayerErrorCallback = (message: string) => void;

@Component
export struct SvgaPlayer {
  @Prop @Watch('onInputChange') source: ResourceStr | Uint8Array | undefined = undefined;
  @Prop @Watch('onInputChange') movie: SvgaMovieEntity | undefined = undefined;
  @Prop @Watch('onContentModeChange') contentMode: number = SvgaContentMode.ASPECT_FIT;
  @Prop @Watch('onPlayingChange') playing: boolean = true;
  @Prop autoRelease: boolean = true;
  controller: SvgaPlayerController = new SvgaPlayerController();
  onReady?: SvgaPlayerReadyCallback;
  onError?: SvgaPlayerErrorCallback;
  private readonly settings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly context: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(this.settings, LengthMetricsUnit.PX);
  private renderer: SvgaCanvasRenderer | undefined = undefined;
  private activeMovie: SvgaMovieEntity | undefined = undefined;
  private ownsActiveMovie: boolean = false;
  private canvasReady: boolean = false;
  private loadGeneration: number = 0;
  private inputSnapshotReady: boolean = false;
  private inputSourceSnapshot: ResourceStr | Uint8Array | undefined = undefined;
  private inputMovieSnapshot: SvgaMovieEntity | undefined = undefined;

  aboutToAppear(): void {
    this.reloadInput();
  }

  aboutToDisappear(): void {
    this.loadGeneration += 1;
    this.inputSnapshotReady = false;
    this.inputSourceSnapshot = undefined;
    this.inputMovieSnapshot = undefined;
    this.canvasReady = false;
    this.controller.detach();
    this.renderer = undefined;
    this.context.reset();
    this.releaseActiveMovie();
  }

  private onInputChange(): void {
    this.reloadInput();
  }

  private onContentModeChange(): void {
    if (this.canvasReady && this.renderer !== undefined) {
      this.renderFrame(this.controller.frame());
    }
  }

  private onPlayingChange(): void {
    if (!this.canvasReady || this.activeMovie === undefined) {
      return;
    }
    if (this.playing) {
      this.controller.play();
    } else {
      this.controller.pause();
    }
  }

  private async reloadInput(): Promise<void> {
    if (this.isInputUnchanged()) {
      return;
    }
    this.captureInputSnapshot();
    const generation: number = this.loadGeneration + 1;
    this.loadGeneration = generation;
    this.controller.detach();
    this.renderer = undefined;
    this.context.reset();
    await this.releaseActiveMovie();

    if (this.movie !== undefined) {
      if (generation !== this.loadGeneration) {
        return;
      }
      this.activeMovie = this.movie;
      this.ownsActiveMovie = false;
      this.bindActiveMovie();
      return;
    }
    if (this.source === undefined || (typeof this.source === 'string' && this.source.length === 0)) {
      return;
    }
    const hostContext: Context | undefined = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.notifyError('SVGA player has no host context');
      return;
    }

    try {
      const parsedMovie: SvgaMovieEntity = await SvgaParser.parseSource(this.source, hostContext);
      if (generation !== this.loadGeneration) {
        await SvgaParser.release(parsedMovie);
        return;
      }
      this.activeMovie = parsedMovie;
      this.ownsActiveMovie = true;
      this.bindActiveMovie();
    } catch {
      if (generation === this.loadGeneration) {
        this.notifyError('SVGA source loading or parsing failed');
      }
    }
  }

  private isInputUnchanged(): boolean {
    if (!this.inputSnapshotReady) {
      return false;
    }
    if (this.movie !== undefined || this.inputMovieSnapshot !== undefined) {
      return this.movie === this.inputMovieSnapshot;
    }
    return this.isSourceUnchanged(this.source, this.inputSourceSnapshot);
  }

  private isSourceUnchanged(left: ResourceStr | Uint8Array | undefined,
    right: ResourceStr | Uint8Array | undefined): boolean {
    if (left === undefined || right === undefined) {
      return left === undefined && right === undefined;
    }
    if (left instanceof Uint8Array) {
      return right instanceof Uint8Array && left === right;
    }
    if (right instanceof Uint8Array) {
      return false;
    }
    if (typeof left === 'string') {
      return typeof right === 'string' && left === right;
    }
    if (typeof right === 'string') {
      return false;
    }
    return left.id === right.id;
  }

  private captureInputSnapshot(): void {
    this.inputSnapshotReady = true;
    this.inputSourceSnapshot = this.source;
    this.inputMovieSnapshot = this.movie;
  }

  private bindActiveMovie(): void {
    if (!this.canvasReady || this.activeMovie === undefined) {
      return;
    }
    this.renderer = new SvgaCanvasRenderer(this.activeMovie);
    this.controller.attach(this.activeMovie, this.getUIContext(),
      (frame: number): SvgaRenderResult => this.renderFrame(frame),
      (): void => this.clearCanvas());
    if (this.playing) {
      this.controller.play();
    } else {
      this.controller.pause();
    }
    if (this.onReady !== undefined) {
      this.onReady(this.activeMovie);
    }
  }

  private async releaseActiveMovie(): Promise<void> {
    const movieToRelease: SvgaMovieEntity | undefined = this.activeMovie;
    const shouldRelease: boolean = this.ownsActiveMovie && this.autoRelease;
    this.activeMovie = undefined;
    this.ownsActiveMovie = false;
    if (movieToRelease !== undefined && shouldRelease) {
      await SvgaParser.release(movieToRelease);
    }
  }

  private renderFrame(frame: number): SvgaRenderResult {
    if (this.renderer === undefined) {
      const result: SvgaRenderResult = new SvgaRenderResult();
      result.frame = frame;
      result.fail('SVGA_RENDER_NOT_READY', 'SVGA player renderer is not ready');
      return result;
    }
    return this.renderer.drawFrame(this.context, frame, this.contentMode);
  }

  private clearCanvas(): void {
    this.context.reset();
  }

  private notifyError(message: string): void {
    if (this.onError !== undefined) {
      this.onError(message);
    }
  }

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.canvasReady = true;
        if (this.renderer === undefined) {
          this.bindActiveMovie();
        } else {
          this.renderFrame(this.controller.frame());
        }
      })
  }
}
