# 2D Asset Creator

An agent skill for Claude Code (and other agents that read `SKILL.md` skills) that makes original 2D game characters end to end:

1. draws layered artwork in **Krita** through [krita-mcp](https://github.com/thuanlm215/krita-mcp),
2. rigs and animates it in **Rigby2D** through its [MCP server](https://rigby2d.com/docs/mcp.html),
3. exports sprite sheets (or a skeletal rig) for Godot, Unity, PixiJS and other engines,

with approval checkpoints so you sign off on the art, the rig and the animation before the next stage.

## What you need

| | Version | Notes |
|---|---|---|
| Linux, x86_64 | | The drawing helper is Linux-only. On Windows or macOS see [Other systems](#other-systems). |
| Krita | **6.0.4** official AppImage | Installed by the setup script. Your existing Krita can stay. |
| krita-mcp | v1.8.1 + a one-line patch in `patches/` | Installed and built by the setup script. |
| Rigby2D MCP server | 0.5.1 | Installed by the setup script. |
| Rigby2D editor | 0.5.1 (optional) | [Download](https://github.com/jaisurya-dev-art/rigby2d/releases/tag/v0.5.1). Needed only for skeletal exports with a texture atlas. |
| Node.js | 20 or newer | Runs the Rigby2D MCP server. |
| uv | any recent | `uvx` fetches Qt headers. [Install uv](https://docs.astral.sh/uv/). |
| Build tools | cmake, a C++17 compiler, git, curl, unzip | |
| Headers | KF6 I18n, KF6 Config, Boost, Eigen | See step 2. |
| Xvfb (optional) | | Only for running Krita without a window. |

## Setup (about ten minutes)

### 1. Get the skill

```bash
git clone https://github.com/HellboundGlory/2d-asset-creator ~/.claude/skills/2d-asset-creator
```

That folder is the skill: Claude Code picks it up in every project. For a single project, clone it into `<project>/.claude/skills/2d-asset-creator` instead. Other agents: put it wherever they load skills from.

### 2. Install the build headers

Fedora (tested):

```bash
sudo dnf install kf6-ki18n-devel kf6-kconfig-devel boost-devel eigen3-devel cmake gcc-c++
```

Debian / Ubuntu (untested): `sudo apt install libkf6i18n-dev libkf6config-dev libboost-dev libeigen3-dev cmake g++`
Arch (untested): `sudo pacman -S ki18n kconfig boost eigen cmake gcc`

### 3. Close Krita, then run the setup script

```bash
~/.claude/skills/2d-asset-creator/scripts/setup-linux.sh
```

It downloads and checks Krita 6.0.4, builds the krita-mcp drawing helper against it, installs the Krita plugin, and installs the Rigby2D MCP server. Everything goes into `~/.local/share/2d-asset-creator` (set `A2D_HOME` to change that). Before it touches Krita's settings it backs them up to `~/.local/share/2d-asset-creator/backups/`. Running it again skips finished steps (`--rebuild` forces a fresh helper build). It needs network access to download.kde.org, github.com, api.github.com, raw.githubusercontent.com, download.qt.io and pypi.org.

Krita 5 and Krita 6 share one settings folder, so Krita 5 also gets the new plugin. That is harmless; the backup has the old one.

### 4. Add the MCP servers to your game project

```bash
python3 ~/.claude/skills/2d-asset-creator/scripts/add_mcp_servers.py /path/to/your/game
```

This adds `krita` and `rigby2d` to the project's `.mcp.json`, keeping anything already there. Rigby2D may only read and write inside the project (add `--root <folder>` for more). The file holds absolute paths for your machine, so keep it out of version control.

Prefer every project instead? Register them once for your user (adjust the paths if you changed `A2D_HOME`):

```bash
claude mcp add --scope user krita -- "$(command -v python3)" ~/.local/share/2d-asset-creator/krita-mcp/mcp_server.py
claude mcp add --scope user rigby2d -- "$(command -v node)" ~/.local/share/2d-asset-creator/rigby2d-mcp/0.5.1/server/src/mcp/server.js --root ~/GameProjects
```

The first time Claude Code starts in that folder it asks you to approve the new servers. Say yes.

### 5. Start Krita and check

```bash
~/.claude/skills/2d-asset-creator/scripts/start-krita.sh     # opens Krita 6.0.4 and keeps this terminal busy
```

Then, in a second terminal:

```bash
~/.claude/skills/2d-asset-creator/scripts/doctor.sh          # every line should say PASS once Krita is open
```

In Krita, **Tools > Scripts > MCP Bridge Status...** shows the bridge is running.

### 6. Use it

Open Claude Code in your project and ask for a character, for example *"Make a side-view goblin thief for my platformer with idle, run and attack clips, exported as a sprite sheet for Godot."* The skill asks for anything essential that's missing (art direction, size, clips), then shows you its work at three checkpoints.

## Running Krita without a window

On a server, in CI, or when you don't want a window:

```bash
scripts/start-krita.sh --headless ~/krita-headless          # private profile, no window (needs Xvfb, not FUSE)
python3 scripts/add_mcp_servers.py /path/to/game --krita-state-dir ~/krita-headless/state --force
scripts/start-krita.sh --stop ~/krita-headless
```

## What the skill can and can't export

- **Sprite sheets:** fully automatic (PNG + JSON with frame tags, durations and pivots; also Defold atlases or plain frames).
- **Skeletal rigs** (bones and meshes moving at runtime): the MCP server writes the skeleton data, but only the Rigby2D editor packs the texture atlas. The skill asks you to do that one export in the editor.

## Other systems

The drawing helper only exists for Linux. On Windows and macOS you can still install krita-mcp with `uvx krita-mcp install` (Krita 5.2 or newer) and Rigby2D's `.mcpb` in Claude Desktop. Documents, layers, inspection and export then work, but drawing, brushes, selections, undo and frames don't, so the skill can organise and export art you draw yourself but can't paint for you.

## Why these exact versions

krita-mcp's drawing helper is compiled against Krita 6.0.4's internals and refuses any other version. KDE's official 6.0.4 AppImage reports `6.0.4 (git 57db7cd)`, which krita-mcp v1.8.1's check rejects, so `patches/` holds a one-line fix (upstream already handles that suffix elsewhere). The AppImage bundles Qt 6.8.0, so the helper is built against Qt 6.8.0 headers. Details and troubleshooting: [`references/setup.md`](references/setup.md).

## Files

- `SKILL.md`: the workflow the agent follows.
- `references/`: setup notes, tool notes for krita-mcp and Rigby2D, engine export notes, naming and animation conventions.
- `scripts/setup-linux.sh`, `start-krita.sh`, `doctor.sh`, `add_mcp_servers.py`: setup and checks.
- `scripts/new_character.py`, `preflight.py`: character project scaffold and file checks.
- `patches/`: the krita-mcp patch.
- `tests/`: `python3 -m pytest tests` (under a second).

## Credits and licences

krita-mcp is by thuanlm215 (plugin and server CC0-1.0, native helper GPL-2.0-or-later). Rigby2D is MIT OR Apache-2.0; its names and logos are trademarks of the Rigby2D project. Krita is GPL and a KDE project. This repo is MIT licensed (see `LICENSE`) and ships none of their code, only scripts that download the official releases and a patch.
