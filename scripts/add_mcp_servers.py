#!/usr/bin/env python3
"""Add the krita and rigby2d MCP servers to a project's .mcp.json (Claude Code project scope)."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path


def read_paths(a2d_home: Path) -> dict[str, str]:
    paths = {
        "KRITA_MCP_DIR": str(a2d_home / "krita-mcp"),
        "RIGBY_MCP_DIR": str(a2d_home / "rigby2d-mcp" / "0.5.1"),
    }
    env_file = a2d_home / "paths.env"
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            key, sep, value = line.partition("=")
            if sep and key.strip() in paths:
                paths[key.strip()] = value.strip()
    for key in paths:
        paths[key] = os.environ.get(key, paths[key])
    return paths


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="Project folder that gets the .mcp.json")
    parser.add_argument("--root", type=Path, action="append",
                        help="Folder Rigby2D may read and write (repeatable; default: the project)")
    parser.add_argument("--krita-state-dir", type=Path,
                        help="KRITA_MCP_STATE_DIR of a headless Krita from start-krita.sh --headless")
    parser.add_argument("--force", action="store_true", help="Replace existing krita/rigby2d entries")
    args = parser.parse_args()

    data_home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    a2d_home = Path(os.environ.get("A2D_HOME") or data_home / "2d-asset-creator").expanduser().resolve()
    paths = read_paths(a2d_home)
    krita_server = Path(paths["KRITA_MCP_DIR"]).expanduser().resolve() / "mcp_server.py"
    rigby_server = Path(paths["RIGBY_MCP_DIR"]).expanduser().resolve() / "server/src/mcp/server.js"
    for server in (krita_server, rigby_server):
        if not server.is_file():
            parser.error(f"{server} is missing. Run scripts/setup-linux.sh first.")

    project = args.project.expanduser().resolve()
    if not project.is_dir():
        parser.error(f"not a folder: {project}")
    roots = [str(r.expanduser().resolve()) for r in (args.root or [project])]

    # Absolute but unresolved commands: Claude Code may start servers without the shell's PATH, and
    # resolving symlinks would pin python3.14 or a version-manager shim's target.
    node = shutil.which("node")
    if not node:
        parser.error("node is not on PATH; the Rigby2D MCP server needs Node.js 20 or newer.")
    python = shutil.which("python3") or sys.executable
    krita: dict = {"command": os.path.abspath(python), "args": [str(krita_server)]}
    if args.krita_state_dir:
        krita["env"] = {"KRITA_MCP_STATE_DIR": str(args.krita_state_dir.expanduser().resolve())}
    rigby_args = [str(rigby_server)]
    for root in roots:
        rigby_args += ["--root", root]
    entries = {"krita": krita, "rigby2d": {"command": os.path.abspath(node), "args": rigby_args}}

    config_path = project / ".mcp.json"
    try:
        text = config_path.read_text(encoding="utf-8") if config_path.is_file() else ""
        config = json.loads(text) if text.strip() else {}
        servers = config.setdefault("mcpServers", {})
        if not isinstance(servers, dict):
            raise TypeError("mcpServers is not an object")
    except (ValueError, AttributeError, TypeError) as exc:
        parser.error(f"cannot update {config_path}: {exc}. Fix or move that file first.")
    changed = kept = False
    for name, entry in entries.items():
        if servers.get(name) == entry:
            continue
        if name in servers and not args.force:
            print(f"Kept the existing '{name}' entry (use --force to replace it)")
            kept = True
            continue
        servers[name] = entry
        changed = True
    if not changed:
        if not kept:
            print(f"{config_path} already has these servers")
        return 0
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=project, delete=False, suffix=".tmp") as tmp:
        tmp.write(json.dumps(config, indent=2) + "\n")
    if config_path.exists():
        shutil.copymode(config_path, tmp.name)
    else:
        os.chmod(tmp.name, 0o644)
    os.replace(tmp.name, config_path)
    print(f"Wrote {config_path} (it holds paths for this machine; don't commit it)")
    print("Claude Code asks you to approve project MCP servers the first time it starts in this folder.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
