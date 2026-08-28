import { UIContext } from '@kit.ArkUI';
import { SvgaMovieEntity, SvgaSpriteEntity } from 'libsvgaplayer.so';
import { SvgaRenderResult } from '../render/SvgaCanvasRenderer';
import {
  SvgaDisplayLinkContext,
  SvgaDisplayLinkManager,
  SvgaDisplayLinkSubscriber
} from './SvgaDisplayLink';

/** 播放器状态常量。 */
export class SvgaPlaybackState {
  /** 已绑定但尚未开始播放，或已从组件解绑。 */
  static readonly IDLE: number = 0;
  /** 正在播放。 */
  static readonly PLAYING: number = 1;
  /** 已暂停并保留当前帧。 */
  static readonly PAUSED: number = 2;
  /** 已停止。 */
  static readonly STOPPED: number = 3;
  /** 已完成配置的循环次数。 */
  static readonly FINISHED: number = 4;
  /** 控制器已释放，不再绑定播放器。 */
  static readonly RELEASED: number = 5;
}

/** 根据帧序号执行渲染并返回渲染统计的回调。 */
export type SvgaPlayerRenderCallback = (frame: number) => SvgaRenderResult;
/** 清空播放器画布的回调。 */
export type SvgaPlayerClearCallback = () => void;
/** 每次实际渲染新帧后触发的回调。 */
export type SvgaPlayerFrameCallback = (frame: number, result: SvgaRenderResult) => void;
/** 完成有限循环播放后触发的回调。 */
export type SvgaPlayerFinishedCallback = () => void;

/**
 * SVGA 播放控制器。
 *
 * @remarks 控制器可在组件外长期持有，但同一时间只应绑定一个 {@link SvgaPlayer}。
 */
export class SvgaPlayerController implements SvgaDisplayLinkSubscriber {
  private static readonly MAX_DISPLAY_GAP_NS: number = 250000000;

  private movie: SvgaMovieEntity | undefined = undefined;
  private uiContext: UIContext | undefined = undefined;
  private renderCallback: SvgaPlayerRenderCallback | undefined = undefined;
  private clearCallback: SvgaPlayerClearCallback | undefined = undefined;
  private frameCallback: SvgaPlayerFrameCallback | undefined = undefined;
  private finishedCallback: SvgaPlayerFinishedCallback | undefined = undefined;
  private subscriptionId: number = -1;
  private playbackState: number = SvgaPlaybackState.IDLE;
  private loops: number = 1;
  private completedLoops: number = 0;
  private framesPerSecondOverride: number = 0;
  private clearsAfterStop: boolean = false;
  private currentFrame: number = 0;
  private lastRenderedFrame: number = -1;
  private timelineStartTimestamp: number = 0;
  private lastTickTimestamp: number = 0;
  private elapsedBeforePause: number = 0;

  /**
   * 绑定动画、ArkUI 上下文和渲染回调，并立即渲染第 0 帧。
   *
   * @param movie 已完成图片解码的动画实体。
   * @param uiContext 播放器所属的 ArkUI 上下文。
   * @param renderCallback 按帧执行绘制的回调。
   * @param clearCallback 清空画布的回调。
   * @remarks 该方法主要供 {@link SvgaPlayer} 内部使用；重复绑定会先取消旧的刷新订阅。
   */
  attach(movie: SvgaMovieEntity, uiContext: UIContext,
    renderCallback: SvgaPlayerRenderCallback, clearCallback: SvgaPlayerClearCallback): void {
    this.unsubscribeDisplayLink();
    this.movie = movie;
    this.uiContext = uiContext;
    this.renderCallback = renderCallback;
    this.clearCallback = clearCallback;
    this.playbackState = SvgaPlaybackState.IDLE;
    this.resetTimeline();
    this.renderFrame(0, true);
  }

  /**
   * 从当前播放器解绑并恢复 IDLE 状态，不清除业务侧注册的帧回调和完成回调。
   */
  detach(): void {
    this.unsubscribeDisplayLink();
    this.movie = undefined;
    this.uiContext = undefined;
    this.renderCallback = undefined;
    this.clearCallback = undefined;
    this.playbackState = SvgaPlaybackState.IDLE;
    this.resetTimeline();
  }

  /**
   * 开始或恢复播放。
   *
   * @returns 动画和渲染环境已就绪时返回 true；未绑定或动画无有效帧时返回 false。
   * @remarks 从 STOPPED 或 FINISHED 状态重新播放时会从第 0 帧开始。
   */
  play(): boolean {
    if (this.movie === undefined || this.uiContext === undefined || this.renderCallback === undefined ||
      this.resolveFrameCount() <= 0) {
      return false;
    }
    if (this.playbackState === SvgaPlaybackState.PLAYING) {
      return true;
    }
    if (this.playbackState !== SvgaPlaybackState.PAUSED &&
      this.playbackState !== SvgaPlaybackState.IDLE) {
      this.resetTimeline();
      this.renderFrame(0, true);
    }
    this.playbackState = SvgaPlaybackState.PLAYING;
    this.timelineStartTimestamp = 0;
    this.lastTickTimestamp = 0;
    this.subscriptionId = SvgaDisplayLinkManager.shared.subscribe(this, this.uiContext);
    return true;
  }

  /** 暂停播放并保留当前帧；尚未开始播放时会进入 PAUSED 状态。 */
  pause(): void {
    if (this.playbackState === SvgaPlaybackState.IDLE) {
      this.playbackState = SvgaPlaybackState.PAUSED;
      return;
    }
    if (this.playbackState !== SvgaPlaybackState.PLAYING) {
      return;
    }
    if (this.timelineStartTimestamp > 0 && this.lastTickTimestamp >= this.timelineStartTimestamp) {
      this.elapsedBeforePause = this.lastTickTimestamp - this.timelineStartTimestamp;
    }
    this.playbackState = SvgaPlaybackState.PAUSED;
    this.unsubscribeDisplayLink();
    this.timelineStartTimestamp = 0;
    this.lastTickTimestamp = 0;
  }

  /**
   * 停止播放并重置时间轴。
   *
   * @param clear 是否立即清空画布；未传入时使用 {@link setClearsAfterStop} 配置。
   */
  stop(clear: boolean | undefined = undefined): void {
    if (this.playbackState === SvgaPlaybackState.RELEASED) {
      return;
    }
    this.unsubscribeDisplayLink();
    this.timelineStartTimestamp = 0;
    this.lastTickTimestamp = 0;
    this.elapsedBeforePause = 0;
    this.completedLoops = 0;
    this.playbackState = SvgaPlaybackState.STOPPED;
    const shouldClear: boolean = clear === undefined ? this.clearsAfterStop : clear;
    if (shouldClear && this.clearCallback !== undefined) {
      this.clearCallback();
      this.lastRenderedFrame = -1;
    }
  }

  /**
   * 释放控制器与播放器的绑定和业务回调，并进入 RELEASED 状态。
   *
   * @remarks 该方法不释放动画实体的 PixelMap；资源所有者仍需调用 {@link SvgaParser.release}。
   */
  release(): void {
    this.detach();
    this.frameCallback = undefined;
    this.finishedCallback = undefined;
    this.playbackState = SvgaPlaybackState.RELEASED;
  }

  /**
   * 设置播放循环次数。
   *
   * @param loops 正整数表示有限循环次数；0、负数或非有限数表示无限循环。
   */
  setLoops(loops: number): void {
    if (!Number.isFinite(loops) || loops <= 0) {
      this.loops = 0;
    } else {
      this.loops = Math.max(1, Math.floor(loops));
    }
  }

  /**
   * 覆盖动画文件声明的帧率。
   *
   * @param framesPerSecond 1 到 120 之间的目标帧率；0、负数或非有限数恢复使用动画原始帧率。
   */
  setFramesPerSecond(framesPerSecond: number): void {
    if (!Number.isFinite(framesPerSecond) || framesPerSecond <= 0) {
      this.framesPerSecondOverride = 0;
    } else {
      this.framesPerSecondOverride = Math.max(1, Math.min(120, framesPerSecond));
    }
    SvgaDisplayLinkManager.shared.subscriberFrameRateDidChange(this.subscriptionId);
  }

  /**
   * 设置停止或自然播放完成后是否清空画布。
   *
   * @param clearsAfterStop true 表示清空，false 表示保留最后绘制帧。
   */
  setClearsAfterStop(clearsAfterStop: boolean): void {
    this.clearsAfterStop = clearsAfterStop;
  }

  /**
   * 注册或移除帧渲染回调。
   *
   * @param callback 回调函数；传入 undefined 表示移除。
   */
  onFrame(callback: SvgaPlayerFrameCallback | undefined): void {
    this.frameCallback = callback;
  }

  /**
   * 注册或移除有限循环播放完成回调。
   *
   * @param callback 回调函数；传入 undefined 表示移除。无限循环不会触发该回调。
   */
  onFinished(callback: SvgaPlayerFinishedCallback | undefined): void {
    this.finishedCallback = callback;
  }

  /**
   * 获取当前播放状态。
   *
   * @returns {@link SvgaPlaybackState} 中的状态值。
   */
  state(): number {
    return this.playbackState;
  }

  /**
   * 获取最近一次成功请求渲染的帧序号。
   *
   * @returns 从 0 开始的帧序号。
   */
  frame(): number {
    return this.currentFrame;
  }

  /**
   * 获取当前播放周期中已经完成的循环次数。
   *
   * @returns 非负循环次数。
   */
  loopCount(): number {
    return this.completedLoops;
  }

  /** @returns 当前是否处于 PLAYING 状态。 */
  isPlaying(): boolean {
    return this.playbackState === SvgaPlaybackState.PLAYING;
  }

  /**
   * 返回 DisplaySync 使用的期望刷新率。
   *
   * @returns 帧率覆盖值、动画声明帧率或默认 20 FPS。
   */
  preferredFrameRate(): number {
    return this.resolveFramesPerSecond();
  }

  /**
   * 接收共享 DisplaySync 的刷新事件并推进播放时间轴。
   *
   * @param context 当前刷新周期的纳秒级时间信息。
   * @remarks 该方法由 {@link SvgaDisplayLinkManager} 调用，业务代码不应手动调用。
   */
  onDisplayLink(context: SvgaDisplayLinkContext): void {
    if (this.playbackState !== SvgaPlaybackState.PLAYING) {
      return;
    }
    if (this.timelineStartTimestamp <= 0) {
      this.timelineStartTimestamp = context.timestamp - this.elapsedBeforePause;
      this.lastTickTimestamp = context.timestamp;
    } else {
      const tickDuration: number = context.timestamp - this.lastTickTimestamp;
      if (tickDuration <= 0) {
        return;
      }
      if (tickDuration > SvgaPlayerController.MAX_DISPLAY_GAP_NS) {
        this.timelineStartTimestamp += tickDuration;
      }
      this.lastTickTimestamp = context.timestamp;
    }
    this.updateFrameForTimestamp(context.timestamp);
  }

  private updateFrameForTimestamp(timestamp: number): void {
    const frameCount: number = this.resolveFrameCount();
    const framesPerSecond: number = this.resolveFramesPerSecond();
    if (frameCount <= 0 || framesPerSecond <= 0) {
      return;
    }
    const elapsed: number = Math.max(0, timestamp - this.timelineStartTimestamp);
    const absoluteFrame: number = Math.floor(elapsed * framesPerSecond / 1000000000);
    if (this.loops > 0) {
      const totalFrames: number = frameCount * this.loops;
      if (absoluteFrame >= totalFrames) {
        this.completedLoops = this.loops;
        this.renderFrame(frameCount - 1, false);
        this.finishPlayback();
        return;
      }
    }
    this.completedLoops = Math.floor(absoluteFrame / frameCount);
    this.renderFrame(absoluteFrame % frameCount, false);
  }

  private finishPlayback(): void {
    this.unsubscribeDisplayLink();
    this.playbackState = SvgaPlaybackState.FINISHED;
    if (this.clearsAfterStop && this.clearCallback !== undefined) {
      this.clearCallback();
      this.lastRenderedFrame = -1;
    }
    if (this.finishedCallback !== undefined) {
      this.finishedCallback();
    }
  }

  private renderFrame(frame: number, force: boolean): void {
    if (!force && frame === this.lastRenderedFrame) {
      return;
    }
    if (this.renderCallback === undefined) {
      return;
    }
    const result: SvgaRenderResult = this.renderCallback(frame);
    this.currentFrame = frame;
    this.lastRenderedFrame = frame;
    if (this.frameCallback !== undefined) {
      this.frameCallback(frame, result);
    }
  }

  private resolveFramesPerSecond(): number {
    if (this.framesPerSecondOverride > 0) {
      return this.framesPerSecondOverride;
    }
    if (this.movie !== undefined && this.movie.params !== undefined && this.movie.params.fps > 0) {
      return Math.max(1, Math.min(120, this.movie.params.fps));
    }
    return 20;
  }

  private resolveFrameCount(): number {
    if (this.movie === undefined) {
      return 0;
    }
    if (this.movie.params !== undefined && this.movie.params.frames > 0) {
      return this.movie.params.frames;
    }
    let frameCount: number = 0;
    for (let index: number = 0; index < this.movie.sprites.length; index++) {
      const sprite: SvgaSpriteEntity = this.movie.sprites[index];
      frameCount = Math.max(frameCount, sprite.frames.length);
    }
    return frameCount;
  }

  private unsubscribeDisplayLink(): void {
    if (this.subscriptionId >= 0) {
      SvgaDisplayLinkManager.shared.unsubscribe(this.subscriptionId);
      this.subscriptionId = -1;
    }
  }

  private resetTimeline(): void {
    this.currentFrame = 0;
    this.lastRenderedFrame = -1;
    this.completedLoops = 0;
    this.timelineStartTimestamp = 0;
    this.lastTickTimestamp = 0;
    this.elapsedBeforePause = 0;
  }
}
