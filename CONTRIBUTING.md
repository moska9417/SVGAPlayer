# Contributing

Contributions are welcome.

## Development setup

1. Install DevEco Studio and HarmonyOS SDK API 12 or later.
2. Clone the repository.
3. Open the repository root in DevEco Studio, or build from the command line:

```shell
devecocli build --modules svgaplayer
```

## Pull requests

- Keep changes focused and describe their user-visible impact.
- Preserve the public exports in `library/Index.ets` unless the change is intentionally breaking.
- Add or update documentation for public API changes.
- Run the schema verifier when changing `svga.proto` or generated protobuf files.
- Run a release build and `scripts/check_release.py` before requesting review.
- Add an entry under `Unreleased` in `CHANGELOG.md`.

## Generated protobuf code

Do not regenerate `svga.pb.cc` or `svga.pb.h` with an arbitrary host `protoc`. The bundled HNP uses a specific pre-release protobuf ABI. Follow `library/src/main/proto/README.md` and use `library/tools/generate_proto.sh`.

## License

By contributing, you agree that your contributions are licensed under the MIT License.
