# SVGAPlayer

SVGAPlayer is an open-source SVGA 2.x parser and player for HarmonyOS. It combines an asynchronous Native C++ parser with ArkTS image decoding, ArkUI Canvas rendering, and a shared DisplaySync playback clock.

## Features

- SVGA 2.x zlib + protobuf parsing on a Node-API worker thread
- PNG image decoding to `PixelMap` with bounded concurrency
- Static and animated ArkUI Canvas components
- `SCALE_TO_FILL`, `ASPECT_FIT`, and `ASPECT_FILL` content modes
- Clip paths, vector shapes, transforms, alpha, line styles, and KEEP frames
- Shared DisplaySync timeline for synchronized players
- Loop, play, pause, stop, frame callback, and completion callback support
- Explicit release of decoded `PixelMap` resources

## Requirements

- HarmonyOS SDK API 12 or later
- `arm64-v8a`
- SVGA 2.x assets

> The bundled protobuf HNP currently provides ARM64 HarmonyOS libraries only. SVGA 1.x ZIP assets, remote URL downloading, audio playback, and matte compositing are not currently supported.

## Installation

After the first public release:

```shell
ohpm install @moska9417/svgaplayer
```

Before publication, consume the source module locally:

```json5
{
  "dependencies": {
    "@moska9417/svgaplayer": "file:../SVGAPlayer/library"
  }
}
```

## Quick start

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
    this.controller.setLoops(2);
    this.controller.onFinished(() => {
      console.info('SVGA playback finished');
    });
  }

  build() {
    Column() {
      SvgaPlayer({
        source: $r('app.media.example_svga'),
        controller: this.controller,
        playing: true,
        contentMode: SvgaContentMode.ASPECT_FIT
      })
        .width('100%')
        .aspectRatio(1)

      Row() {
        Button('Play').onClick(() => this.controller.play())
        Button('Pause').onClick(() => this.controller.pause())
        Button('Stop').onClick(() => this.controller.stop(true))
      }
    }
  }
}
```

`SvgaPlayer.source` accepts a media `Resource`, local file path, `Uint8Array`, or an already parsed `SvgaMovieEntity`.

## Parsing without the player

```typescript
import { SvgaParser } from '@moska9417/svgaplayer';

const movie = await SvgaParser.parse(data, {
  concurrency: 4,
  discardEncodedData: true
});

// Stop all rendering before releasing the movie.
await SvgaParser.release(movie);
```

## Main APIs

- `SvgaNative`: native parse and protobuf version APIs
- `SvgaParser`: parse, image decode, and resource release facade
- `SvgaCanvas`: static frame rendering component
- `SvgaPlayer`: animated player component
- `SvgaPlayerController`: imperative playback controller
- `SvgaCanvasRenderer`: low-level frame renderer
- `SvgaDisplayLinkManager`: shared DisplaySync broadcaster

## Build

From this repository root:

```shell
devecocli build --modules svgaplayer
```

Release build:

```shell
devecocli build --modules svgaplayer --build-mode release
python3 scripts/check_release.py library/build/default/outputs/default/svgaplayer.har
```

## Native dependency

`library/src/main/cpp/third_party/protobuf.hnp` is unpacked by CMake during the native build. Its SHA-256 is:

```text
711079526bf5556bc1b4d08dbf9073128bdc4b6c991d7c32d076b7b79dbfc4c8
```

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution and [library/src/main/proto/README.md](library/src/main/proto/README.md) for schema generation constraints.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT License. See [LICENSE](LICENSE).
