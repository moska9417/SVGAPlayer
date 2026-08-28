#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_FILE="$MODULE_DIR/src/main/proto/svga.proto"
OUTPUT_DIR="$MODULE_DIR/src/main/cpp/generated"
PROTOC_BIN="${PROTOC:-}"

if [[ -z "$PROTOC_BIN" || ! -x "$PROTOC_BIN" ]]; then
  echo "Set PROTOC to the executable path of the 6.34.0-dev compatible host protoc." >&2
  exit 1
fi

VERSION="$($PROTOC_BIN --version)"
if [[ "$VERSION" != "libprotoc 34.0-dev" ]]; then
  echo "Expected 'libprotoc 34.0-dev', got '$VERSION'." >&2
  echo "Official protoc 34.0 generates C++ 7.34 code and is incompatible with protobuf.hnp." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
"$PROTOC_BIN" \
  --proto_path="$(dirname "$PROTO_FILE")" \
  --cpp_out="$OUTPUT_DIR" \
  "$PROTO_FILE"

if ! grep -q "PROTOBUF_VERSION != 6034000" "$OUTPUT_DIR/svga.pb.h"; then
  echo "Generated code does not target protobuf C++ runtime 6.34.0-dev." >&2
  exit 1
fi
if ! grep -q "InternalMetadataOffset::Build" "$OUTPUT_DIR/svga.pb.cc"; then
  echo "Generated code does not match the protobuf.hnp arena-offset ABI." >&2
  echo "Build protoc from commit 49d04b36aea28de3a4546b7264bedac229a79aad." >&2
  exit 1
fi

echo "Generated $OUTPUT_DIR/svga.pb.h and svga.pb.cc"
