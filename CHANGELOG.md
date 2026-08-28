# Changelog

All notable changes to this project are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Compose the Canvas content transform with each SVGA frame transform before drawing, so AspectFill and explicit component dimensions are applied directly to every rendered sprite.
- Render the Canvas context, clip paths, and vector paths consistently in physical pixels, preventing SVGA frame coordinates from being scaled twice on high-density displays.

### Changed

- Extracted SVGAPlayer into a standalone open-source HarmonyOS project.
- Renamed the package to `@moska9417/svgaplayer` and the native library to `libsvgaplayer.so`.
- Added release metadata, licensing, contribution guidance, and package validation tooling.

## [1.0.0] - 2026-08-28

### Added

- Asynchronous Native C++ SVGA 2.x parser.
- ArkTS image decoding and resource release.
- Static Canvas rendering for bitmap and vector content.
- Shared DisplaySync playback with declarative and imperative controls.
