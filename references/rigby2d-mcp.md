# Rigby2D MCP: operating notes

## Official project and documentation

- Website/docs: https://rigby2d.com/docs/
- MCP setup: https://rigby2d.com/docs/mcp.html
- MCP tool reference: https://rigby2d.com/docs/mcp-tools.html
- Importing art: https://rigby2d.com/docs/importing-art.html
- Quick start: https://rigby2d.com/docs/quick-start.html
- Export: https://rigby2d.com/docs/export.html
- Runtimes: https://rigby2d.com/docs/runtimes.html

Rigby2D's MCP tool reference is generated from the server's definitions. The current local server schema takes precedence over this guide.

## Installing the server

`scripts/setup-linux.sh` downloads `Rigby2D-AI-0.5.1.mcpb` from the Rigby2D release, checks its hash and unpacks it. The `.mcpb` is a zip that holds the whole server plus Pyodide (for `run_script`) and ag-psd (for reading PSD files). Start it with Node 20+, never through `npm run` (npm writes to stdout, which the protocol uses):

```bash
node <dir>/server/src/mcp/server.js --root /path/to/project   # --root is repeatable; paths outside the roots are refused
```

`scripts/add_mcp_servers.py <project>` writes that entry into the project's `.mcp.json`. On Windows and macOS, Claude Desktop installs the same `.mcpb` by drag and drop. A clone of the Rigby2D repo also works (`npm install` once for PSD support).

Keep the server, editor and engine runtimes at one release (0.5.1 here).

## Important workflow facts

- Rigby2D accepts layered PSD, layered SVG, or PNG artwork. For AutoRig, use a layered PSD with one layer per moving part as the most predictable hand-off.
- Each PSD pixel layer becomes an image/slot, in its original canvas position. Layer order is draw order, bottom-most first. Hidden layers are imported hidden.
- The canvas bottom-centre is the world origin. Place the character's feet/ground-contact point accordingly.
- Layer names matter to AutoRig. Examples include `upperarm_l` and `Hand Right`.
- Rigby2D's character-left side is on the viewer's right when the character faces the viewer. Confirm side assignments.
- Overlap joint artwork to prevent gaps during rotation.

## Tools (0.5.1, 42)

- **Read:** `inspect_project`, `describe_rig`, `describe_animation`, `sample_pose` (setup or animation at a time: world transforms, visible attachments, draw order, bounds), `validate_project`, `detect_parts` (PSD or unrigged `.rigby`; read-only), `map_bones`.
- **Rig:** `autorig` (`psd_file` or `path`, `output`, `meshes`: `deforming`/`all`/`none`, `ik`, `roles`, `sides`, `overwrite`), `add_bone`, `set_bone_setup`, `rename_bone`, `set_slot`.
- **Animate:** `add_animation`, `set_bone_key` (`rotate`/`translate`/`scale`/`shear`, curve `linear`, `stepped`, `easeIn`, `easeOut`, `easeInOut` or `[cx1,cy1,cx2,cy2]`), `delete_bone_key`, `set_attachment_key`, `set_event_key`, `batch_edit` (many edits, one atomic save), `rename_animation`, `delete_animation`, `retarget_animation`.
- **Poses and faces:** `save_pose`, `apply_pose`, `delete_pose`, `add_face_control`, `set_face_control`, `delete_face_control`, `lip_sync`, audio track tools.
- **Film:** `set_workspace`, `set_output`, `add_actor`, `add_clip`, `remove_clip`, `set_actor`, `set_layer_depth`.
- **Script:** `run_script` (sandboxed Python with the editor's `rigby` module; `dry_run` to only read).
- **Export:** `export_sprite_sheet` (`json`, `defold`, `frames`), `convert_project` (skeleton JSON 3.8/4.2/4.3 or `.skel` 4.3; **no atlas**), `export_defold_model`.

Key values are relative to the setup pose. Every edit loads, changes and atomically saves the file; there is no undo, so pass `output` for a copy before risky edits.

## Recommended sequence

1. `detect_parts` on the PSD.
2. Review every detected role and side. Supply overrides for misclassified names/sides.
3. `autorig` to a new `.rigby` path; use deforming meshes for bendable parts and IK for two-bone arms/legs when appropriate.
4. `inspect_project` and `describe_rig`.
5. Sample neutral and extreme poses with `sample_pose`.
6. Correct rig defects; save a versioned `.rigby` master.
7. Create and key clips. Use seconds or frame numbers exactly as the current tool schema specifies.
8. Inspect each clip with `describe_animation`; sample start, middle, end and key moments.
9. `validate_project` before export.
10. Export sprite sheets with `export_sprite_sheet`. For native skeletal playback, ask the user to export skeleton + atlas from the Rigby2D editor: `convert_project` writes skeleton data only.

## Export rules

- The `.rigby` project is the editable source. Exported engine files are derived outputs.
- A skeletal delivery needs skeleton data **and** the matching atlas and texture page(s). Only the editor's export packs the atlas; `convert_project` does not.
- Skeleton JSON format versions currently documented are 3.8, 4.2 and 4.3; binary `.skel` is documented for 4.3. Match the version with the engine runtime being installed.
- `export_sprite_sheet` in `json` mode writes a PNG and TexturePacker-style JSON metadata; documentation describes frame durations, pivots, Aseprite frame tags and PixiJS animation lists.
- Do not assume a frame-based sheet carries editable bones or runtime IK.
