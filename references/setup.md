# Setup notes for agents

People install with `README.md`. This file explains the pins, so you can diagnose a broken setup without guessing. Everything here was checked on 2026-11-17 on Fedora 44 (x86_64).

## Version pins and why

| Piece | Pin | Why |
|---|---|---|
| Krita | official `krita-6.0.4-x86_64.AppImage`, SHA-256 `4ec9a458…fd6de9f` (the hash krita-mcp's own CI pins) | krita-mcp's native helper is ABI-pinned to Krita 6.0.4. The `release/6.0.4` branch now builds as 6.0.4.2 and Fedora ships 6.0.4.1; both are refused. |
| krita-mcp | tag `v1.8.1` + `patches/krita-mcp-1.8.1-helper-version-check.patch` | The helper gate compares `Krita.version()` with exactly `"6.0.4"`, but the official AppImage reports `"6.0.4 (git 57db7cd)"`. Upstream already strips that suffix for `close_document`; the patch does the same for the helper. 1.8.1 still reports `plugin_version: "1.7.0"` from `status`; that is upstream's string, not a stale install. |
| Qt headers | 6.8.0 from `aqtinstall==3.3.0` | The AppImage bundles Qt 6.8.0. Building against a newer distro Qt can pull in symbols 6.8 lacks. |
| KF6 headers | distro `ki18n` and `kconfig` dev packages | Only headers are used. The distro's `KF6I18nConfig.cmake` demands a newer Qt, so setup writes a small CMake shim that links the AppImage's own `libKF6I18n.so.6`. |
| Rigby2D MCP | `Rigby2D-AI-0.5.1.mcpb`, SHA-256 `5fc01589…491e0c6` (taken from the download on 2026-11-17; Rigby2D publishes no hash) | The `.mcpb` is a zip holding the whole server plus Pyodide and ag-psd (PSD reading). Run it with Node 20+. Keep it at the same version as the Rigby2D editor. |

The helper build also passes `-DCMAKE_SKIP_RPATH=ON`, so the `.so` carries no library path into the build folders; inside Krita it resolves Qt, KF6 and Krita libraries from the ones Krita already loaded.

## What setup-linux.sh does

1. Checks commands (`curl git cmake c++ python3 objdump readelf ldd strings sha256sum pgrep`, plus `uvx` until Qt is installed and `node unzip` unless `--skip-rigby`), Node 20+, and the KF6, Boost and Eigen headers. Prints distro install commands if any are missing. Stops if Krita is running.
2. Downloads and verifies the AppImage, extracts it once to `$A2D_HOME/krita-6.0.4-sdk/` (the helper builds against these libraries, and `start-krita.sh` runs Krita from this tree so FUSE is not needed) and confirms it bundles Qt 6.8.0.
3. Installs Qt 6.8.0 headers into `$A2D_HOME/qt`.
4. Clones krita-mcp v1.8.1, applies the patch (skips it if already applied, warns if it no longer applies).
5. Builds the helper and checks it: 0 undefined symbols against the AppImage libraries, no RPATH, no Qt symbol newer than 6.8.
6. Refuses to continue if Krita is running, backs up `kritarc` and `pykrita` to `$A2D_HOME/backups/<time>/`, then runs krita-mcp's installer (copies the plugin, enables **MCP Bridge**).
7. Downloads, verifies and unpacks the Rigby2D MCP server.
8. Writes `$A2D_HOME/paths.env` for the other scripts.

`$A2D_HOME` defaults to `~/.local/share/2d-asset-creator`. `KRITA_APPIMAGE`, `KRITA_MCP_DIR` and `RIGBY_MCP_DIR` override single paths.

## Headless Krita

`scripts/start-krita.sh --headless DIR` runs Krita under Xvfb with a private profile in `DIR` (own `XDG_*` dirs, HOME and `kritarc`, OpenGL off), installs or refreshes the plugin there, and waits for the bridge file `DIR/state/krita_mcp_bridge.json`. If the krita MCP server was already running with a different `KRITA_MCP_STATE_DIR`, restart it (in Claude Code: `/mcp`, or a new session). The krita MCP server must get `KRITA_MCP_STATE_DIR=DIR/state`, for example with `scripts/add_mcp_servers.py <project> --krita-state-dir DIR/state`. Stop it with `--stop DIR`. This mirrors krita-mcp's own `scripts/run_isolated_tests.py`.

Use it for servers, CI and smoke tests. Start one only with the user's OK.

## Runtime evidence for this combination

On 2026-11-17, with the official 6.0.4 AppImage and the patched v1.8.1 plugin in an isolated profile:

- `list_capabilities` (`kind: "workflow"`) returned `native_helper.available: true`, ABI `krita-6.0.4-qt6`.
- `draw` reported "Recorded in Krita's native history"; `undo` reverted it (pixel read back transparent).
- `export_document` to `.psd` kept named layers; Rigby2D `detect_parts` found `head` and `torso` by name.
- krita-mcp's own suites `tests.test_workflow` (14 tests) and `tests.test_advanced` (38 tests) passed.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `native_helper.available: false`, reason "requires Linux/Krita 6.0.4" | Wrong Krita build, or the patch is missing. `scripts/doctor.sh` says which. |
| "Build/install the native helper first" | The plugin was installed from a clone without a built helper. Rerun `setup-linux.sh`. |
| "Native helper could not be loaded: undefined symbol" | Built against the wrong Qt or Krita libraries. Delete `$KRITA_MCP_DIR/native/build` and rerun setup. |
| "Could not reach the Krita MCP bridge" | Krita is not running, the plugin is disabled (Settings > Configure Krita > Python Plugin Manager > MCP Bridge), or the server looks at a different profile than Krita (check `KRITA_MCP_STATE_DIR` / `XDG_DATA_HOME`). |
| Rigby2D `detect_parts` lists one flat layer | The PSD was flattened. Export with `export_document` from the layered document, not from a PNG. |
| Project MCP servers missing in Claude Code | Project `.mcp.json` servers need approval the first time Claude Code starts in that folder (`claude mcp list` shows "Pending approval"). |
| Krita 5 lost its MCP plugin settings | Krita 5 and 6 share `~/.local/share/krita` and `~/.config/kritarc`. Restore from `$A2D_HOME/backups/`. |

## Other systems

The helper is Linux x86_64 only. On Windows and macOS, krita-mcp's basic document, layer, inspection and export tools work with Krita 5.2+ (`uvx krita-mcp install`, see its README), but drawing, brushes, selections, undo and frames return `unsupported`. Rigby2D's MCP server runs anywhere Node 20+ runs; Claude Desktop can install the `.mcpb` directly.
