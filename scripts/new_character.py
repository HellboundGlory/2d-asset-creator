#!/usr/bin/env python3
"""Create a character project scaffold for the 2d-asset-creator skill."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def slugify(value: str) -> str:
    value = re.sub(r"[\s-]+", "_", value.strip().lower())
    value = re.sub(r"[^a-z0-9_]+", "", value)
    value = re.sub(r"_{2,}", "_", value).strip("_")
    if not value:
        raise ValueError("Project name must contain at least one letter or number.")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, help="Folder to create for the new character project")
    parser.add_argument("--name", required=True, help="Character display name")
    parser.add_argument("--id", dest="character_id", help="Optional stable ID (defaults to slugified name)")
    parser.add_argument("--width", type=int, default=1024)
    parser.add_argument("--height", type=int, default=1024)
    parser.add_argument("--fps", type=int, default=24)
    parser.add_argument("--engines", nargs="+", choices=["godot", "unity", "pixijs", "phaser", "defold", "cocos"],
                        default=["godot", "unity", "pixijs"])
    args = parser.parse_args()

    if args.width < 1 or args.height < 1 or args.fps < 1:
        parser.error("width, height and fps must be positive integers")

    character_id = slugify(args.character_id or args.name)
    project = args.destination.expanduser().resolve()

    if project.exists() and (not project.is_dir() or any(project.iterdir())):
        parser.error(f"Refusing to write into an existing file or non-empty folder: {project}")

    folders = ["source", "rig/backups", "exports/spritesheet", "qa"]
    folders += [f"exports/{engine}" for engine in args.engines]
    for folder in folders:
        (project / folder).mkdir(parents=True, exist_ok=True)

    manifest = {
        "schema_version": 1,
        "character": {
            "id": character_id,
            "name": args.name,
            "art_direction": "",
            "view": "side",
            "default_facing": "right",
            "canvas": {
                "width": args.width,
                "height": args.height,
                "color_mode": "RGBA",
                "colour_space": "sRGB",
                "background": "transparent",
                "origin": "bottom_center"
            },
            "fps": args.fps,
            "target_engines": args.engines
        },
        "parts": {
            "directory": "source/parts",
            "expected": [],
            "optional": []
        },
        "animations": [],
        "deliverables": {
            "krita_master": f"source/{character_id}.kra",
            "layered_handoff": f"source/{character_id}.psd",
            "rigby_master": f"rig/{character_id}.rigby",
            "skeleton_json": f"exports/skeletal/{character_id}.json",
            "atlas": f"exports/skeletal/{character_id}.atlas",
            "atlas_texture": f"exports/skeletal/{character_id}.png"
        }
    }

    manifest_path = project / "character.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    readme = f"""# {args.name}\n\nCharacter asset project created with the 2d-asset-creator skill.\n\n- ID: `{character_id}`\n- Canvas: {args.width} × {args.height} RGBA\n- Frame rate: {args.fps} fps\n- Targets: {', '.join(args.engines)}\n\n## Workflow\n\n1. Create layered artwork in `source/{character_id}.kra`.\n2. Export a layered PSD to `source/{character_id}.psd`.\n3. Import/AutoRig in Rigby2D and save `rig/{character_id}.rigby`.\n4. Validate and export engine/runtime assets under `exports/`.\n5. Record versions and test results below.\n\n## Tool versions and QA\n\n- Krita: not recorded yet\n- Krita MCP: not recorded yet\n- Rigby2D: not recorded yet\n- Engine/runtime versions: not recorded yet\n- Engine smoke tests: not run\n"""
    (project / "README.md").write_text(readme, encoding="utf-8")
    (project / "qa" / "animation-checklist.md").write_text(
        "# Animation checklist\n\nAdd required clips and mark each check after testing.\n", encoding="utf-8")
    print(f"Created project scaffold: {project}")
    print(f"Manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
