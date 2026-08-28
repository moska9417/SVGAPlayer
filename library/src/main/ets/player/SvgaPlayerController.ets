import { UIContext } from '@kit.ArkUI';
import { SvgaMovieEntity, SvgaSpriteEntity } from 'libsvgaplayer.so';
import { SvgaRenderResult } from '../render/SvgaCanvasRenderer';
import {
  SvgaDisplayLinkContext,
  SvgaDisplayLinkManager,
  SvgaDisplayLinkSubscriber
} from './SvgaDisplayLink';

export class SvgaPlaybackState {
  static readonly IDLE: number = 0;
  static readonly PLAYING: number = 1;
  static readonly PAUSED: number = 2;
  static readonly STOPPED: number = 3;
  static readonly FINISHED: number = 4;
  static readonly RELEASED: number = 5;
}

export type SvgaPlayerRenderCallback = (frame: number) => SvgaRenderResult;
export type SvgaPlayerClearCallback = () => void;
export type SvgaPlayerFrameCallback = (frame: number, result: SvgaRenderResult) => void;
export type SvgaPlayerFinishedCallback = () => void;

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

  detach(): void {
    this.unsubscribeDisplayLink();
    this.movie = undefined;
    this.uiContext = undefined;
    this.renderCallback = undefined;
    this.clearCallback = undefined;
    this.playbackState = SvgaPlaybackState.IDLE;
    this.resetTimeline();
  }

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

  release(): void {
    this.detach();
    this.frameCallback = undefined;
    this.finishedCallback = undefined;
    this.playbackState = SvgaPlaybackState.RELEASED;
  }

  setLoops(loops: number): void {
    if (!Number.isFinite(loops) || loops <= 0) {
      this.loops = 0;
    } else {
      this.loops = Math.max(1, Math.floor(loops));
    }
  }

  setFramesPerSecond(framesPerSecond: number): void {
    if (!Number.isFinite(framesPerSecond) || framesPerSecond <= 0) {
      this.framesPerSecondOverride = 0;
    } else {
      this.framesPerSecondOverride = Math.max(1, Math.min(120, framesPerSecond));
    }
    SvgaDisplayLinkManager.shared.subscriberFrameRateDidChange(this.subscriptionId);
  }

  setClearsAfterStop(clearsAfterStop: boolean): void {
    this.clearsAfterStop = clearsAfterStop;
  }

  onFrame(callback: SvgaPlayerFrameCallback | undefined): void {
    this.frameCallback = callback;
  }

  onFinished(callback: SvgaPlayerFinishedCallback | undefined): void {
    this.finishedCallback = callback;
  }

  state(): number {
    return this.playbackState;
  }

  frame(): number {
    return this.currentFrame;
  }

  loopCount(): number {
    return this.completedLoops;
  }

  isPlaying(): boolean {
    return this.playbackState === SvgaPlaybackState.PLAYING;
  }

  preferredFrameRate(): number {
    return this.resolveFramesPerSecond();
  }

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
