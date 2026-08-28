import { displaySync } from '@kit.ArkGraphics2D';
import { UIContext } from '@kit.ArkUI';

/** 单次屏幕刷新回调携带的时间信息，所有时间值单位均为纳秒。 */
export class SvgaDisplayLinkContext {
  /** 当前刷新与上一有效刷新之间的时长。 */
  readonly duration: number;
  /** 当前刷新时间戳。 */
  readonly timestamp: number;
  /** 系统预测的目标刷新时间戳。 */
  readonly targetTimestamp: number;

  /**
   * 创建屏幕刷新上下文。
   *
   * @param duration 帧间隔，单位为纳秒。
   * @param timestamp 当前时间戳，单位为纳秒。
   * @param targetTimestamp 目标时间戳，单位为纳秒。
   */
  constructor(duration: number, timestamp: number, targetTimestamp: number) {
    this.duration = duration;
    this.timestamp = timestamp;
    this.targetTimestamp = targetTimestamp;
  }
}

/** 可订阅共享屏幕刷新时钟的对象。 */
export interface SvgaDisplayLinkSubscriber {
  /**
   * 在屏幕刷新时调用。
   *
   * @param context 当前刷新周期的时间信息。
   */
  onDisplayLink(context: SvgaDisplayLinkContext): void;
  /**
   * 返回订阅者期望的刷新率。
   *
   * @returns 期望帧率；管理器最终会限制在 1 到 120 FPS。
   */
  preferredFrameRate(): number;
}

/** 多播放器共享的 DisplaySync 调度器。通常无需由业务代码直接管理。 */
export class SvgaDisplayLinkManager {
  /** 全局共享实例。 */
  static readonly shared: SvgaDisplayLinkManager = new SvgaDisplayLinkManager();

  private readonly displayLink: displaySync.DisplaySync = displaySync.create();
  private readonly subscribers: Map<number, SvgaDisplayLinkSubscriber> =
    new Map<number, SvgaDisplayLinkSubscriber>();
  private nextSubscriberId: number = 1;
  private running: boolean = false;
  private lastTimestamp: number = 0;
  private readonly frameCallback = (frameInfo: displaySync.IntervalInfo): void => {
    this.dispatchFrame(frameInfo);
  };

  private constructor() {
    this.displayLink.on('frame', this.frameCallback);
  }

  /**
   * 订阅屏幕刷新事件；首个订阅者会启动 DisplaySync。
   *
   * @param subscriber 接收刷新事件的订阅者。
   * @param uiContext 用于在正确 ArkUI 作用域内启动 DisplaySync。
   * @returns 正数订阅标识，取消订阅和更新帧率时需要传回。
   */
  subscribe(subscriber: SvgaDisplayLinkSubscriber, uiContext: UIContext): number {
    const subscriberId: number = this.nextSubscriberId;
    this.nextSubscriberId += 1;
    this.subscribers.set(subscriberId, subscriber);
    this.updateExpectedFrameRate();
    if (!this.running) {
      this.running = true;
      this.lastTimestamp = 0;
      uiContext.runScopedTask(() => {
        this.displayLink.start();
      });
    }
    return subscriberId;
  }

  /**
   * 取消指定订阅；最后一个订阅移除后会停止 DisplaySync。
   *
   * @param subscriberId {@link subscribe} 返回的订阅标识；负数会被忽略。
   */
  unsubscribe(subscriberId: number): void {
    if (subscriberId < 0) {
      return;
    }
    this.subscribers.delete(subscriberId);
    if (this.subscribers.size === 0) {
      if (this.running) {
        this.displayLink.stop();
      }
      this.running = false;
      this.lastTimestamp = 0;
      return;
    }
    this.updateExpectedFrameRate();
  }

  /**
   * 通知管理器某个订阅者的期望帧率发生变化。
   *
   * @param subscriberId 已注册的订阅标识；未知标识会被忽略。
   */
  subscriberFrameRateDidChange(subscriberId: number): void {
    if (this.subscribers.has(subscriberId)) {
      this.updateExpectedFrameRate();
    }
  }

  /**
   * 获取当前活动订阅者数量。
   *
   * @returns 活动订阅者数量。
   */
  subscriberCount(): number {
    return this.subscribers.size;
  }

  private dispatchFrame(frameInfo: displaySync.IntervalInfo): void {
    let duration: number = frameInfo.targetTimestamp - frameInfo.timestamp;
    if (this.lastTimestamp > 0 && frameInfo.timestamp > this.lastTimestamp) {
      duration = frameInfo.timestamp - this.lastTimestamp;
    }
    const context: SvgaDisplayLinkContext = new SvgaDisplayLinkContext(
      Math.max(0, duration), frameInfo.timestamp, frameInfo.targetTimestamp);
    this.lastTimestamp = frameInfo.timestamp;

    const snapshot: Array<SvgaDisplayLinkSubscriber> = [];
    this.subscribers.forEach((subscriber: SvgaDisplayLinkSubscriber) => {
      snapshot.push(subscriber);
    });
    for (let index: number = 0; index < snapshot.length; index++) {
      snapshot[index].onDisplayLink(context);
    }
  }

  private updateExpectedFrameRate(): void {
    let expectedFrameRate: number = 1;
    this.subscribers.forEach((subscriber: SvgaDisplayLinkSubscriber) => {
      expectedFrameRate = Math.max(expectedFrameRate, subscriber.preferredFrameRate());
    });
    expectedFrameRate = Math.max(1, Math.min(120, Math.round(expectedFrameRate)));
    const range: ExpectedFrameRateRange = {
      min: 0,
      max: 120,
      expected: expectedFrameRate
    };
    this.displayLink.setExpectedFrameRateRange(range);
  }
}
