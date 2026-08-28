#!/usr/bin/env python3
"""Verify the checked-in SVGA wire schema against real .svga resources.

This tool only needs a host protoc executable and Python's standard library.
It intentionally does not generate target C++ sources; target code generation
must use the protoc version matching protobuf.hnp.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import zlib
from collections import Counter
from pathlib import Path
from typing import Any

UNKNOWN_FIELD_PATTERN = re.compile(rb"^\s*\d+\s*(?::|\{)")
UNKNOWN_ENUM_PATTERN = re.compile(rb"^\s*(?:type|lineCap|lineJoin):\s*-?\d+\s*$")
OBJC_SYMBOL_PATTERN = re.compile(r"^\s*(SVGAProto[A-Za-z0-9_]+) = (-?\d+),", re.MULTILINE)
OBJC_ENUM_PREFIXES = (
    "SVGAProtoShapeEntity_ShapeType_",
    "SVGAProtoShapeEntity_ShapeStyle_LineCap_",
    "SVGAProtoShapeEntity_ShapeStyle_LineJoin_",
)


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    default_proto = script_dir.parent / "src" / "main" / "proto" / "svga.proto"

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--protoc", default="protoc", help="Host protoc executable")
    parser.add_argument("--proto", type=Path, default=default_proto, help="SVGA schema")
    parser.add_argument(
        "--resource-root",
        action="append",
        type=Path,
        required=True,
        help="Directory containing .svga files; may be specified more than once",
    )
    parser.add_argument(
        "--ios-header",
        type=Path,
        help="Optional YWSVGAPlayer Svga.pbobjc.h used for field-number comparison",
    )
    parser.add_argument("--output", type=Path, help="Optional JSON report path")
    return parser.parse_args()


def validate_schema(protoc: str, proto: Path) -> None:
    with tempfile.NamedTemporaryFile(suffix=".desc") as descriptor_file:
        command = [
            protoc,
            f"--proto_path={proto.parent}",
            f"--descriptor_set_out={descriptor_file.name}",
            proto.name,
        ]
        result = subprocess.run(
            command,
            cwd=proto.parent,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())


def extract_objc_wire_symbols(header: Path) -> dict[str, int]:
    symbols: dict[str, int] = {}
    for name, raw_value in OBJC_SYMBOL_PATTERN.findall(header.read_text(encoding="utf-8")):
        is_wire_symbol = (
            "_FieldNumber_" in name
            or "_OneOfCase_" in name
            or name.startswith(OBJC_ENUM_PREFIXES)
        )
        if is_wire_symbol and "GPBUnrecognized" not in name:
            symbols[name] = int(raw_value)
    return symbols


def validate_ios_header(protoc: str, proto: Path, ios_header: Path) -> dict[str, Any]:
    reference_symbols = extract_objc_wire_symbols(ios_header)
    if not reference_symbols:
        raise RuntimeError(f"No SVGA wire symbols found in {ios_header}")

    with tempfile.TemporaryDirectory() as output_dir:
        command = [
            protoc,
            f"--proto_path={proto.parent}",
            f"--objc_out={output_dir}",
            proto.name,
        ]
        result = subprocess.run(
            command,
            cwd=proto.parent,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.decode(errors="replace").strip())
        generated_header = Path(output_dir) / "Svga.pbobjc.h"
        generated_symbols = extract_objc_wire_symbols(generated_header)

    mismatches: list[dict[str, Any]] = []
    for name, expected in sorted(reference_symbols.items()):
        actual = generated_symbols.get(name)
        if actual != expected:
            mismatches.append({"symbol": name, "expected": expected, "actual": actual})
    if mismatches:
        raise RuntimeError(f"iOS generated field-number mismatch: {mismatches}")

    return {
        "referenceHeader": str(ios_header),
        "matchedSymbols": len(reference_symbols),
        "schemaOnlySymbols": len(set(generated_symbols) - set(reference_symbols)),
        "mismatches": mismatches,
    }


def decode_resource(protoc: str, proto: Path, resource: Path) -> dict[str, Any]:
    raw = resource.read_bytes()
    if raw.startswith(b"PK\x03\x04"):
        return {"format": "zip", "error": "SVGA 1.x ZIP is outside this schema check"}

    try:
        protobuf_data = zlib.decompress(raw)
    except zlib.error as error:
        return {"format": "unknown", "error": f"zlib: {error}"}

    counts: Counter[str] = Counter()
    version = ""
    fps = 0
    frames = 0
    width = 0.0
    height = 0.0
    unknown_fields: list[str] = []

    with tempfile.NamedTemporaryFile(suffix=".protobuf") as protobuf_file:
        protobuf_file.write(protobuf_data)
        protobuf_file.flush()
        protobuf_file.seek(0)
        command = [
            protoc,
            f"--proto_path={proto.parent}",
            "--decode=com.opensource.svga.MovieEntity",
            proto.name,
        ]
        process = subprocess.Popen(
            command,
            cwd=proto.parent,
            stdin=protobuf_file,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        assert process.stdout is not None
        for raw_line in process.stdout:
            line = raw_line.strip()
            if raw_line.startswith(b"version:"):
                version = raw_line.split(b":", 1)[1].strip().decode(errors="replace").strip('"')
            elif raw_line.startswith(b"  viewBoxWidth:"):
                width = float(raw_line.split(b":", 1)[1])
            elif raw_line.startswith(b"  viewBoxHeight:"):
                height = float(raw_line.split(b":", 1)[1])
            elif raw_line.startswith(b"  fps:"):
                fps = int(raw_line.split(b":", 1)[1])
            elif raw_line.startswith(b"  frames:"):
                frames = int(raw_line.split(b":", 1)[1])
            elif raw_line == b"images {\n":
                counts["images"] += 1
            elif raw_line == b"sprites {\n":
                counts["sprites"] += 1
            elif raw_line == b"audios {\n":
                counts["audios"] += 1
            elif line.startswith(b"matteKey:"):
                counts["matte"] += 1
            elif line.startswith(b"clipPath:"):
                counts["clipPath"] += 1
            elif line == b"shape {":
                counts["shape"] += 1
            elif line == b"type: RECT":
                counts["rect"] += 1
            elif line == b"type: ELLIPSE":
                counts["ellipse"] += 1
            elif line == b"type: KEEP":
                counts["keep"] += 1

            if UNKNOWN_FIELD_PATTERN.match(raw_line) or UNKNOWN_ENUM_PATTERN.match(raw_line):
                if len(unknown_fields) < 10:
                    unknown_fields.append(line.decode(errors="replace")[:200])

        stderr = process.stderr.read().decode(errors="replace") if process.stderr else ""
        return_code = process.wait()

    if return_code != 0:
        return {"format": "zlib+protobuf", "error": stderr.strip() or "protoc decode failed"}

    return {
        "format": "zlib+protobuf",
        "version": version,
        "width": width,
        "height": height,
        "fps": fps,
        "frames": frames,
        "counts": dict(counts),
        "unknownFields": unknown_fields,
    }


def update_maximum(maxima: dict[str, dict[str, Any]], name: str, value: int, resource: Path) -> None:
    if value > maxima[name]["value"]:
        maxima[name] = {"value": value, "file": resource.name}


def main() -> int:
    args = parse_args()
    proto = args.proto.resolve()
    validate_schema(args.protoc, proto)
    ios_compatibility = None
    if args.ios_header:
        ios_compatibility = validate_ios_header(
            args.protoc,
            proto,
            args.ios_header.resolve(),
        )

    resources: list[Path] = []
    for root in args.resource_root:
        resources.extend(root.resolve().rglob("*.svga"))
    resources = sorted(set(resources))

    totals: Counter[str] = Counter()
    versions: Counter[str] = Counter()
    maxima: dict[str, dict[str, Any]] = {
        "frames": {"value": 0, "file": ""},
        "images": {"value": 0, "file": ""},
        "sprites": {"value": 0, "file": ""},
    }
    failures: list[dict[str, str]] = []
    unknowns: list[dict[str, Any]] = []

    for resource in resources:
        result = decode_resource(args.protoc, proto, resource)
        totals["files"] += 1
        totals[result["format"]] += 1
        if "error" in result:
            failures.append({"file": str(resource), "error": result["error"]})
            continue

        versions[result["version"]] += 1
        counts = result["counts"]
        for name, value in counts.items():
            totals[name] += value
        update_maximum(maxima, "frames", result["frames"], resource)
        update_maximum(maxima, "images", counts.get("images", 0), resource)
        update_maximum(maxima, "sprites", counts.get("sprites", 0), resource)
        if result["unknownFields"]:
            unknowns.append({"file": str(resource), "fields": result["unknownFields"]})

    report = {
        "schema": str(proto),
        "iosGeneratedCompatibility": ios_compatibility,
        "resourceRoots": [str(root.resolve()) for root in args.resource_root],
        "totals": dict(sorted(totals.items())),
        "versions": dict(sorted(versions.items())),
        "maxima": maxima,
        "unknownWireFields": unknowns,
        "failures": failures,
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    print(rendered, end="")

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")

    return 1 if failures or unknowns or not resources else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        print(f"verify_svga_schema: {error}", file=sys.stderr)
        sys.exit(2)
