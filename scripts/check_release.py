#!/usr/bin/env python3
"""Validate an SVGAPlayer HAR before publishing it to OHPM."""

from __future__ import annotations

import hashlib
import json
import sys
import tarfile
from pathlib import Path

EXPECTED_NAME = "@moska9417/svgaplayer"
REQUIRED_FILES = {
    "package/oh-package.json5",
    "package/README.md",
    "package/LICENSE",
    "package/CHANGELOG.md",
}
FORBIDDEN_MARKERS = (
    b"BEGIN PRIVATE KEY",
)
TEXT_ONLY_MARKERS = (
    b"/" + b"Users/",
    b"publish_id",
)
TEXT_SUFFIXES = (".ets", ".ts", ".js", ".json", ".json5", ".md", ".txt", ".xml", ".yaml", ".yml")


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: check_release.py <svgaplayer.har>")

    artifact = Path(sys.argv[1])
    if not artifact.is_file():
        fail(f"artifact does not exist: {artifact}")

    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()

    try:
        with tarfile.open(artifact, "r:*") as archive:
            members = {member.name: member for member in archive.getmembers()}
            missing = sorted(REQUIRED_FILES - members.keys())
            if missing:
                fail("missing required package files: " + ", ".join(missing))

            metadata_file = archive.extractfile(members["package/oh-package.json5"])
            if metadata_file is None:
                fail("cannot read package/oh-package.json5")
            metadata = json.load(metadata_file)

            if metadata.get("name") != EXPECTED_NAME:
                fail(f"unexpected package name: {metadata.get('name')!r}")
            if metadata.get("license") != "MIT":
                fail(f"unexpected license: {metadata.get('license')!r}")
            if metadata.get("artifactType") != "original":
                fail(f"artifactType must be 'original', got {metadata.get('artifactType')!r}")
            if metadata.get("obfuscated") is True:
                fail("open-source release must not be obfuscated")

            native_path = "package/libs/arm64-v8a/libsvgaplayer.so"
            if native_path not in members:
                fail(f"missing native library: {native_path}")

            for member in members.values():
                if not member.isfile() or member.size > 4 * 1024 * 1024:
                    continue
                source = archive.extractfile(member)
                if source is None:
                    continue
                data = source.read()
                markers = FORBIDDEN_MARKERS
                if member.name.endswith(TEXT_SUFFIXES):
                    markers += TEXT_ONLY_MARKERS
                for marker in markers:
                    if marker.lower() in data.lower():
                        fail(f"forbidden marker {marker!r} found in {member.name}")
    except (tarfile.TarError, json.JSONDecodeError) as error:
        fail(f"invalid HAR: {error}")

    print(f"OK: {artifact}")
    print(f"SHA-256: {digest}")


if __name__ == "__main__":
    main()
