import { displaySync } from '@kit.ArkGraphics2D';
import { UIContext } from '@kit.ArkUI';

export class SvgaDisplayLinkContext {
  readonly duration: number;
  readonly timestamp: number;
  readonly targetTimestamp: number;

  constructor(duration: number, timestamp: number, targetTimestamp: number) {
    this.duration = duration;
    this.timestamp = timestamp;
    this.targetTimestamp = targetTimestamp;
  }
}

export interface SvgaDisplayLinkSubscriber {
  onDisplayLink(context: SvgaDisplayLinkContext): void;
  preferredFrameRate(): number;
}

export class SvgaDisplayLinkManager {
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

  subscriberFrameRateDidChange(subscriberId: number): void {
    if (this.subscribers.has(subscriberId)) {
      this.updateExpectedFrameRate();
    }
  }

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
