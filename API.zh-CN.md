# SVGAPlayer 中文 API 文档

## 1. 环境要求

- HarmonyOS SDK API 12 或更高版本
- `arm64-v8a` 设备
- SVGA 2.x 动画文件

当前版本不支持 SVGA 1.x ZIP、直接下载远程 URL、音频播放和 matte 合成。

## 2. 快速使用

```typescript
import {
  SvgaContentMode,
  SvgaPlayer,
  SvgaPlayerController
} from '@moska9417/svgaplayer';

@Entry
@Component
struct Index {
  private readonly controller: SvgaPlayerController = new SvgaPlayerController();

  aboutToAppear(): void {
    // 播放两次后停止，并保留最后一帧。
    this.controller.setLoops(2);
    this.controller.setClearsAfterStop(false);
    this.controller.onFinished((): void => {
      console.info('SVGA 播放完成');
    });
  }

  build() {
    SvgaPlayer({
      source: $r('app.media.example_svga'),
      controller: this.controller,
      playing: true,
      contentMode: SvgaContentMode.ASPECT_FIT,
      onError: (message: string): void => {
        console.error('SVGA 播放失败：' + message);
      }
    })
      .width('100%')
      .aspectRatio(1)
  }
}
```

## 3. SvgaPlayer

自动完成数据读取、Native 解析、图片解码、Canvas 渲染和时间轴播放的 ArkUI 组件。

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `source` | `ResourceStr \| Uint8Array \| undefined` | `undefined` | 媒体资源、本地路径、`file://` 路径或完整 SVGA 字节。 |
| `movie` | `SvgaMovieEntity \| undefined` | `undefined` | 已解析动画；与 `source` 同时提供时优先使用。 |
| `contentMode` | `number` | `ASPECT_FIT` | 画布缩放模式。 |
| `playing` | `boolean` | `true` | 是否播放；运行时修改可继续或暂停。 |
| `autoRelease` | `boolean` | `true` | 是否自动释放由 `source` 解析得到的 PixelMap。 |
| `controller` | `SvgaPlayerController` | 新实例 | 外部播放控制器。 |
| `onReady` | `SvgaPlayerReadyCallback` | `undefined` | 动画解析并绑定成功回调。 |
| `onError` | `SvgaPlayerErrorCallback` | `undefined` | 读取、解析或图片解码失败回调。 |

资源所有权规则：

- 组件只会自动释放自己通过 `source` 创建的动画。
- 外部传入的 `movie` 始终由调用方负责释放。
- `autoRelease` 为 `false` 时，调用方必须保存动画引用并主动释放。

## 4. SvgaPlayerController

| 方法 | 说明 |
| --- | --- |
| `play()` | 开始或恢复播放；环境未就绪时返回 `false`。 |
| `pause()` | 暂停并保留当前帧。 |
| `stop(clear?)` | 停止并重置时间轴，可指定是否清空画布。 |
| `release()` | 解绑播放器和业务回调；不释放动画 PixelMap。 |
| `setLoops(loops)` | 正整数为有限循环次数；小于等于 0 或非有限数表示无限循环。 |
| `setFramesPerSecond(fps)` | 覆盖原始帧率，范围限制为 1 到 120；无效值恢复原始帧率。 |
| `setClearsAfterStop(clear)` | 设置停止或自然完成后是否清空画布。 |
| `onFrame(callback)` | 注册逐帧回调；传入 `undefined` 移除。 |
| `onFinished(callback)` | 注册有限循环完成回调；无限循环不会触发。 |
| `state()` | 返回 `SvgaPlaybackState` 状态值。 |
| `frame()` | 返回当前帧序号。 |
| `loopCount()` | 返回当前播放周期已完成的循环次数。 |
| `isPlaying()` | 返回是否正在播放。 |

`SvgaPlaybackState` 包含：`IDLE`、`PLAYING`、`PAUSED`、`STOPPED`、`FINISHED` 和 `RELEASED`。

## 5. 数据解析与释放

### SvgaParser.parse

解析内存中的完整 SVGA 文件字节，并解码内嵌图片：

```typescript
import { SvgaMovieEntity, SvgaParser } from '@moska9417/svgaplayer';

const movie: SvgaMovieEntity = await SvgaParser.parse(data);
// 停止所有使用 movie 的渲染后再释放。
await SvgaParser.release(movie);
```

### SvgaParser.parseSource

支持以下数据源：

- `$r('app.media.xxx')` 媒体资源
- 本地绝对路径
- `file://` 路径
- `Uint8Array`

不支持直接传入 HTTP 或 HTTPS 地址，远程文件应由业务侧先下载。

### SvgaImageDecodeOptions

| 属性 | 默认值 | 说明 |
| --- | --- | --- |
| `concurrency` | `4` | 图片解码并发数，最终限制为 1 到 8。 |
| `discardEncodedData` | `true` | PixelMap 创建成功后丢弃原始编码数据。 |

图片解码失败时抛出 `SvgaImageDecodeError`，可读取 `code`、`imageKey` 和 `nativeCode`。

## 6. 静态帧与低级渲染

### SvgaCanvas

无播放时间轴的 ArkUI 组件，适合绘制封面、缩略图或由业务侧控制帧序号。

| 属性 | 说明 |
| --- | --- |
| `movie` | 已完成图片解码的动画实体。 |
| `frame` | 从 0 开始的目标帧序号。 |
| `contentMode` | 画布缩放模式。 |
| `onRendered` | 每次绘制后的结果回调。 |

### SvgaContentMode

- `SCALE_TO_FILL`：拉伸填满，可能改变宽高比。
- `ASPECT_FIT`：保持宽高比完整显示，可能留白。
- `ASPECT_FILL`：保持宽高比填满，可能裁切。

### SvgaCanvasRenderer

低级同步逐帧渲染器。调用方需要提供使用像素单位创建的 `CanvasRenderingContext2D`，并负责动画与 PixelMap 生命周期。

`drawFrame()` 返回 `SvgaRenderResult`，其中包含：

- `success`、`errorCode`、`errorMessage`
- 实际帧序号
- 已绘制精灵、图片、图形和裁剪路径数量
- 被跳过的图片、图形、裁剪路径和 matte 数量

## 7. Native 低级接口

`SvgaNative.protobufVersion()` 返回 Native 解析器链接的 protobuf 版本。

`SvgaNative.parse()` 只执行 Native protobuf 解析，不会把图片转换为 PixelMap。业务通常应优先使用 `SvgaParser.parse()`。

## 8. 资源生命周期建议

1. 页面或组件消失时先停止播放并解绑控制器。
2. 确认没有 Canvas 或播放器继续使用动画实体。
3. 对外部持有的动画调用 `SvgaParser.release(movie)`。
4. 不要在释放后继续绘制同一个 `SvgaMovieEntity`。
5. 长时间或重复播放场景应复用已解析动画，避免频繁解析和创建 PixelMap。
