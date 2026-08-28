# Publishing checklist

This project is prepared for an open-source OHPM release but is not published automatically.

## One-time repository setup

- [ ] Confirm that `@moska9417/svgaplayer` is available in the target OHPM registry.
- [x] Create the public `SVGAPlayer` source repository: https://github.com/moska9417/SVGAPlayer.
- [x] Add valid `homepage` and `repository` URLs to `library/oh-package.json5`.
- [x] Configure private vulnerability reporting guidance in `SECURITY.md`.
- [ ] Confirm that `moska9417` is the intended public repository owner and package author.
- [ ] Complete an internal legal review of `LICENSE`, `THIRD_PARTY_NOTICES.md`, the reconstructed SVGA schema, generated protobuf code, and `protobuf.hnp` redistribution.
- [ ] Enable issues, private vulnerability reporting, and branch protection in the public repository.
- [ ] Create an OHPM account/organization, generate the publishing key pair, upload the public key, and configure the publishing code and private-key path in `.ohpmrc`.

Do not commit `.ohpmrc`, private keys, publishing codes, signing material, or local SDK paths.

## Release preparation

1. Update the version in:
   - `library/oh-package.json5`
   - `library/src/main/cpp/types/libsvgaplayer/oh-package.json5`
   - `library/BuildProfile.ets`, if that compatibility file remains versioned
2. Move release notes from `Unreleased` to a dated version in `CHANGELOG.md`.
3. Synchronize the package documents:

```shell
cp README.md API.zh-CN.md LICENSE CHANGELOG.md THIRD_PARTY_NOTICES.md library/
```

4. Build the open-source HAR:

```shell
devecocli build clean
devecocli build --modules svgaplayer --build-mode release
```

5. Validate the artifact:

```shell
python3 scripts/check_release.py library/build/default/outputs/default/svgaplayer.har
```

6. Test the HAR in a clean sample application on an ARM64 device.
7. Inspect the package to ensure it contains no credentials, private URLs, absolute local paths, build caches, or unrelated application resources.

## Publish

The official OHPM client publishes a HAR with:

```shell
ohpm publish library/build/default/outputs/default/svgaplayer.har --source_type open
```

Add `--publish_registry`, `--publish_id`, or `--key_path` only when they are not already configured in `.ohpmrc`. Never reuse a published name/version combination; OHPM permanently reserves it after approval.

## Post-release

- [ ] Create and push the matching Git tag, for example `v1.0.0`.
- [ ] Create repository release notes and attach the validated HAR checksum.
- [ ] Verify installation from a clean project with `ohpm install @moska9417/svgaplayer@<version>`.
- [ ] Keep the next development changes under `Unreleased`.
