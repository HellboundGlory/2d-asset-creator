# Engine delivery matrix

Use the official runtime/package matching the Rigby2D editor release. The 0.5.1 release (2026-11-11) ships a Godot add-on (Linux, macOS, Windows), a Unity package, PixiJS and Phaser modules, a Defold extension and a Cocos package. Verify the engine floors below against https://rigby2d.com/docs/runtimes.html before quoting them.

| Target | Native skeletal route | Current documented engine floor | Notes |
|---|---|---|---|
| Godot | Rigby2D Godot add-on; `RigbySkeleton2D` / `RigbyScene2D` | Godot 4.3+ | GDExtension based on the Rust core; package is platform-specific. |
| Unity | Rigby2D Unity package; `RigbySkeleton` / `RigbyScene` | Unity 2021.3+ and Unity 6 | Include the package that matches the editor/runtime release. |
| PixiJS | Rigby2D PixiJS runtime with native display objects | PixiJS 8 | Current docs describe WebGL and WebGPU. |

Primary reference: https://rigby2d.com/docs/runtimes.html

## Native skeletal package

The MCP server cannot produce this package on its own: `convert_project` writes skeleton data only and never packs the atlas. The user exports skeleton + atlas + pages from the Rigby2D editor.

For each target engine, provide (as applicable):

- Skeleton JSON or binary SKEL, version matched to runtime.
- Matching `.atlas` file.
- Every texture page referenced by the atlas.
- Matching engine runtime/package and concise integration notes.
- Character manifest with animation names, default skin, origin, scale and version metadata.
- A minimal test scene/prefab/example where feasible.

Use the current Rigby2D editor's **Get runtimes** workflow or official matching release assets. Avoid mixing a newer editor export with an older engine runtime without testing.

## Frame-based sprite sheet package

For consumers that want conventional frames rather than a live skeleton, Rigby2D's `export_sprite_sheet` MCP tool has a `json` export that produces PNG + JSON metadata, including frame durations/pivots and engine-oriented animation metadata. Deliver the exact PNG and matching JSON together. Keep the original `.rigby` project too.

Use the sprite-sheet output when:

- the engine/game pipeline expects a conventional atlas;
- you intentionally want to bake all skeletal motion into frames;
- the target runtime is unavailable or not desired;
- a user explicitly requests sprite sheets.

Do not use sprite-sheet export as the sole deliverable when the brief calls for runtime IK, skin swapping, skeletal constraints or retargetable animation.

## Smoke tests

### Godot

- Add the matching Rigby2D runtime to a test project.
- Create a `RigbySkeleton2D` node or matching runtime node according to the package docs.
- Load skeleton/atlas/texture assets.
- Play `idle` and one non-looping clip.
- Check origin/feet placement, scale, textures, draw order, animation transitions and output console.

### Unity

- Import the matching package.
- Create the documented `RigbySkeleton` component.
- Load the same skeleton/atlas/textures.
- Play looping and one-shot clips.
- Check prefab references, transform scale, animation names, rendering order and console.

### PixiJS

- Use the official PixiJS 8 runtime sample/API that matches the installed package.
- Load skeleton JSON, atlas text and page texture(s).
- Create the documented Rigby display objects.
- Play a loop and one-shot animation.
- Check texture URLs, WebGL/WebGPU path, anchor/origin, scaling and browser console/network logs.

If the relevant editor/runtime is not installed or cannot be run in the current environment, mark the output `structurally validated — engine smoke test not run` and give the user concise test steps.
