# SVGA protobuf schema

`svga.proto` is the wire-format source of truth for SVGAPlayer.

## Verification

Use the dependency-free verifier with a host `protoc`, an optional Apache-2.0-compatible SVGA Objective-C generated header, and one or more SVGA resource directories:

```shell
python3 library/tools/verify_svga_schema.py \
  --protoc /path/to/protoc \
  --ios-header /path/to/Svga.pbobjc.h \
  --resource-root /path/to/svga/resources
```

The verifier checks schema field numbers and can decode every `.svga` file under the supplied resource roots.

## C++ generation constraint

Do not regenerate the HarmonyOS C++ files with an arbitrary host `protoc`:

- `protoc` 3.21 is older than the bundled HNP runtime.
- Official `protoc` 34.0 generates C++ runtime 7.34 code.
- `protobuf.hnp` uses a pre-release C++ runtime identified as `6.34.0-dev`.

The HNP headers match upstream protobuf commit `49d04b36aea28de3a4546b7264bedac229a79aad`. Build the host compiler from that commit and run the guarded generator:

```shell
git init /tmp/protobuf-hnp-host
cd /tmp/protobuf-hnp-host
git fetch --depth 1 https://github.com/protocolbuffers/protobuf.git \
  49d04b36aea28de3a4546b7264bedac229a79aad
git checkout FETCH_HEAD
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -Dprotobuf_BUILD_TESTS=OFF \
  -Dprotobuf_BUILD_SHARED_LIBS=OFF
cmake --build build --target protoc -j 8

cd /path/to/SVGAPlayer
PROTOC=/tmp/protobuf-hnp-host/build/protoc \
  library/tools/generate_proto.sh
```

The script requires `libprotoc 34.0-dev` and verifies that generated code targets `PROTOBUF_VERSION == 6034000`.
