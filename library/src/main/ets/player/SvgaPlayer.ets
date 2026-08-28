import { LengthMetricsUnit } from '@kit.ArkUI';
import { SvgaMovieEntity } from 'libsvgaplayer.so';
import { SvgaParser } from '../parser/SvgaParser';
import {
  SvgaCanvasRenderer, SvgaContentMode, SvgaRenderResult
} from '../render/SvgaCanvasRenderer';
import { SvgaPlayerController } from './SvgaPlayerController';

/** 动画解析完成并绑定到播放器后触发的回调。 */
export type SvgaPlayerReadyCallback = (movie: SvgaMovieEntity) => void;

/** 动画读取、解析或图片解码失败时触发的回调。 */
export type SvgaPlayerErrorCallback = (message: string) => void;

/**
 * 可自动读取、解析、渲染和播放 SVGA 2.x 动画的 ArkUI 组件。
 *
 * @remarks `source` 与 `movie` 同时提供时优先使用 `movie`。组件只自动释放由 `source` 解析得到且
 * `autoRelease` 为 true 的动画；外部传入的 `movie` 始终由调用方负责释放。
 */
@Component
export struct SvgaPlayer {
  /**
   * 动画来源，可传媒体 Resource、本地文件路径、`file://` 路径或完整文件字节。
   *
   * @remarks 不支持直接传入 HTTP 或 HTTPS 地址，远程文件必须先由业务侧下载。
   */
  @Prop @Watch('onInputChange') source: ResourceStr | Uint8Array | undefined = undefined;
  /** 已完成解析和图片解码的动画实体；设置后优先于 `source`。 */
  @Prop @Watch('onInputChange') movie: SvgaMovieEntity | undefined = undefined;
  /** 缩放模式，使用 {@link SvgaContentMode} 中的值，默认为 ASPECT_FIT。 */
  @Prop @Watch('onContentModeChange') contentMode: number = SvgaContentMode.ASPECT_FIT;
  /** 是否自动播放；运行时修改会相应地继续或暂停播放。 */
  @Prop @Watch('onPlayingChange') playing: boolean = true;
  /** 组件消失或输入切换时，是否自动释放由 `source` 创建的 PixelMap，默认为 true。 */
  @Prop autoRelease: boolean = true;
  /** 播放控制器；不传入时组件会创建独立控制器。 */
  controller: SvgaPlayerController = new SvgaPlayerController();
  /** 动画成功绑定且 Canvas 已就绪时触发。 */
  onReady?: SvgaPlayerReadyCallback;
  /** 动画来源读取、解析或图片解码失败时触发。 */
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
