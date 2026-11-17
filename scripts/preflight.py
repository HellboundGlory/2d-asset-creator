#!/usr/bin/env python3
"""File-level preflight for a 2d-asset-creator character project (stdlib only)."""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path
from typing import Any

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def read_png_header(path: Path) -> tuple[int, int, int, bool]:
    """Return width, height, colour type, and whether an alpha channel is present."""
    with path.open("rb") as stream:
        header = stream.read(33)
    if len(header) < 26 or header[:8] != PNG_SIGNATURE:
        raise ValueError("not a valid PNG signature/header")
    length = struct.unpack(">I", header[8:12])[0]
    if length != 13 or header[12:16] != b"IHDR":
        raise ValueError("missing/invalid IHDR chunk")
    width, height, bit_depth, colour_type, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", header[16:29]
    )
    if width <= 0 or height <= 0:
        raise ValueError("invalid zero-sized image")
    if bit_depth not in (1, 2, 4, 8, 16):
        raise ValueError(f"unsupported PNG bit depth {bit_depth}")
    if colour_type not in (0, 2, 3, 4, 6):
        raise ValueError(f"unsupported PNG colour type {colour_type}")
    # Colour type 4 = grayscale + alpha; 6 = RGBA. Indexed PNG can also carry tRNS,
    # which is checked separately by scanning chunk headers.
    alpha = colour_type in (4, 6)
    if not alpha:
        alpha = has_trns_chunk(path)
    return width, height, colour_type, alpha


def has_trns_chunk(path: Path) -> bool:
    """Scan PNG chunk headers for a tRNS transparency chunk without decoding pixels."""
    with path.open("rb") as stream:
        if stream.read(8) != PNG_SIGNATURE:
            return False
        while True:
            head = stream.read(8)
            if len(head) != 8:
                return False
            length = struct.unpack(">I", head[:4])[0]
            chunk_type = head[4:8]
            if chunk_type == b"tRNS":
                return True
            if chunk_type == b"IEND":
                return False
            stream.seek(length + 4, 1)  # skip data and CRC


def load_manifest(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("manifest root must be a JSON object")
    for key in ("schema_version", "character", "parts", "animations", "deliverables"):
        if key not in data:
            raise ValueError(f"manifest is missing required top-level key: {key}")
    if not isinstance(data["character"], dict) or not data["character"].get("id"):
        raise ValueError("character.id must be present")
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="Character project folder")
    parser.add_argument("--manifest", default="character.json", help="Manifest path relative to project")
    args = parser.parse_args()

    project = args.project.expanduser().resolve()
    manifest_path = (project / args.manifest).resolve()
    if not project.is_dir():
        print(f"ERROR: project folder not found: {project}")
        return 2
    try:
        manifest = load_manifest(manifest_path)
    except Exception as exc:  # useful diagnostic for malformed/user-edited manifests
        print(f"ERROR: cannot read manifest {manifest_path}: {exc}")
        return 2

    errors: list[str] = []
    warnings: list[str] = []
    notes: list[str] = []
    character = manifest["character"]
    canvas = character.get("canvas", {})
    expected_canvas = (canvas.get("width"), canvas.get("height"))
    if not all(isinstance(v, int) and v > 0 for v in expected_canvas):
        warnings.append("manifest canvas width/height are not both positive integers")

    parts = manifest.get("parts", {})
    parts_dir = (project / parts.get("directory", "source/parts")).resolve()
    expected_parts = parts.get("expected", [])
    if not isinstance(expected_parts, list):
        errors.append("parts.expected must be a list")
        expected_parts = []

    pngs = sorted(parts_dir.glob("*.png")) if parts_dir.is_dir() else []
    if not pngs:
        notes.append("no per-part PNGs (optional; the layered PSD is the hand-off)")
    else:
        seen_names = {p.stem for p in pngs}
        for name in expected_parts:
            if isinstance(name, str) and name not in seen_names:
                warnings.append(f"expected part PNG not found: {name}.png")

    dimensions: set[tuple[int, int]] = set()
    for image_path in pngs:
        if image_path.stem.lower() != image_path.stem or " " in image_path.stem:
            warnings.append(f"use lowercase snake_case filenames: {image_path.name}")
        try:
            width, height, colour_type, has_alpha = read_png_header(image_path)
            dimensions.add((width, height))
            if not has_alpha:
                warnings.append(f"PNG has no alpha/transparency channel: {image_path.name}")
            if expected_canvas[0] and expected_canvas[1] and (width, height) != expected_canvas:
                warnings.append(
                    f"{image_path.name} is {width}x{height}; manifest canvas is "
                    f"{expected_canvas[0]}x{expected_canvas[1]}"
                )
        except Exception as exc:
            errors.append(f"invalid PNG {image_path.name}: {exc}")

    if len(dimensions) > 1:
        warnings.append(f"part PNGs use inconsistent canvas dimensions: {sorted(dimensions)}")

    deliverables = manifest.get("deliverables", {})
    for key in ("krita_master", "layered_handoff", "rigby_master"):
        rel = deliverables.get(key)
        if rel and not (project / rel).is_file():
            warnings.append(f"deliverable not present yet ({key}): {rel}")

    # Try a deeper alpha-bound check when Pillow is installed; do not require it.
    try:
        from PIL import Image  # type: ignore
        for image_path in pngs:
            try:
                with Image.open(image_path) as img:
                    if img.mode not in ("RGBA", "LA"):
                        if "A" not in img.getbands():
                            continue
                    alpha = img.getchannel("A") if "A" in img.getbands() else None
                    if alpha is not None and alpha.getbbox() is None:
                        warnings.append(f"PNG is fully transparent/empty: {image_path.name}")
            except Exception as exc:
                warnings.append(f"could not inspect pixels in {image_path.name}: {exc}")
        notes.append("Pillow pixel inspection: available")
    except ImportError:
        notes.append("Pillow not installed; PNG checks used header/chunk inspection only")

    print(f"2d-asset-creator preflight: {character.get('name', character.get('id', 'unnamed'))}")
    print(f"Project: {project}")
    print(f"Part PNGs inspected: {len(pngs)}")
    for message in notes:
        print(f"INFO: {message}")
    for message in warnings:
        print(f"WARN: {message}")
    for message in errors:
        print(f"ERROR: {message}")
    if errors:
        print(f"RESULT: FAIL ({len(errors)} error(s), {len(warnings)} warning(s))")
        return 1
    print(f"RESULT: PASS WITH {len(warnings)} WARNING(S)")
    print("Note: this is a file-level preflight, not Krita, Rigby2D or in-engine validation.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
