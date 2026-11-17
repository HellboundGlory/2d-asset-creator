# krita-mcp: operating notes

Community project by `thuanlm215`, not part of Krita: https://github.com/thuanlm215/krita-mcp (usage: `docs/usage.md`, workflows: `docs/workflows.md` in that repo). This skill pins v1.8.1. The live tool schema wins over this file.

## How it connects

- A Python plugin inside Krita (`pykrita/krita_mcp`, shown as **MCP Bridge**) runs a local HTTP bridge and writes its port and token to `krita_mcp_bridge.json` in its state folder (`$KRITA_MCP_STATE_DIR`, else `$XDG_DATA_HOME/krita`).
- The MCP server (`mcp_server.py`, stdlib Python) reads that file and forwards tool calls. It must see the same state folder as the running Krita.
- Krita must be running. The bridge drives a live document; it is not a headless renderer. For machines without a display, see "Headless Krita" in `setup.md`.
- From a shell, `python3 mcp_server.py --call <op> --params '<json>'` calls one bridge operation (op names can differ from tool names: the `list_capabilities` tool with `kind: "workflow"` is op `workflow_capabilities`, `inspect_document` is op `document_info`).

## Tools (v1.8.1, 57)

- **Status:** `status`, `list_capabilities` (`kind`: `filters`, `blending_modes`, `workflow`), `inspect_document`, `self_test`, `dismiss_recovery_dialog`.
- **Documents:** `create_document`, `open_document`, `save_document`, `export_document` (format from the extension), `close_document`, `transform_image`. The tool text says "flattened copy", but a `.psd` export kept every named layer in testing on 2026-11-17; check with Rigby2D `detect_parts` each time.
- **Layers:** `create_layer`, `set_layer`, `delete_layer`, `duplicate_layer`, `move_layer`, `merge_layer_down`, `mask_layer`, `bake_layer`, `outline_layer`, `export_layers`.
- **Painting (helper):** `draw`, `list_brushes`, `draw_brush`, `plan_stroke`, `paint_stroke`, `apply_filter`, `edit_batch`, `texture_patch`, `clone_stamp`, `remove_background`, `quantize_layer`.
- **Selection and transform (helper):** `select_polygon`, `select_content`, `set_selection`, `selection_to_layer`, `transform_layer`, `warp_layer`.
- **Inspection:** `get_image` (`layer`, `region`, `max_size`, `save_path`), `get_pixel`, `sample_colors`, `compare_images`, `preview_changes`.
- **History (helper):** `undo`, `redo`.
- **Animation (helper):** `animation_frame`, `export_animation`, `import_animation`, `animation_review`, `slice_sheet`.
- **Repairs:** `prepare_repair`, `render_repair`, `inspect_repair`, `commit_repair`, `repair_status`, `discard_repair`.
- `trigger_action` runs a named Krita action.

"Helper" tools need the native helper (Linux, Krita 6.0.4, Qt6). Without it they return `unsupported`.

## Before each kind of edit

1. `status`: Krita version and open documents.
2. `list_capabilities` with `kind: "workflow"`: `native_helper.available` and the per-feature list. A tool in the schema is not proof the helper is loaded.
3. Name the target document and layer in every call.
4. Use `preview_changes` or `get_image` before and after.
5. `save_document` to a new version when a pass is done.

## Notes from use

- `create_document` with `background: "transparent"` still creates a `Background` layer. Delete it or give it role `none` in Rigby2D.
- Paths: krita-mcp resolves relative paths against Krita's working folder, so pass absolute paths. `params_file` must be absolute.
- New layers go on top and become active; reorder with `move_layer`.
- `draw` takes a `commands` list (`fill_rect`, `rect`, `ellipse`, `circle`, `line`, `polyline`, `polygon`, `ink`, `text`, `linear_gradient`, `radial_gradient`, `image`, `svg`, `clear`). Colours are `#rrggbb`, `#rrggbbaa`, SVG names or `[r,g,b,a]`. One call is one undo step.
- `close_document` drains Krita 6.0.4's layer-model updates before closing (works around a crash). Prefer it over closing through `trigger_action`.
- Krita 5 and 6 share the same plugin folder and `kritarc`. Installing 1.8.1 replaces the plugin Krita 5 loads too.

## Safe art pattern

1. Create or open the document; inspect size, colour space and layers.
2. Create one uniquely named layer per moving part.
3. Draw only on explicitly named layers.
4. `get_image` and look.
5. `save_document` (`.kra`).
6. `export_document` to `.psd` and confirm the layers with Rigby2D `detect_parts` before rigging.

Never flatten the working character before Rigby2D import. Export a separate flat PNG for QA if needed.
