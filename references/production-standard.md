# 2D character production standard

This document is a practical default, not an inflexible rule. Follow the game brief when it conflicts.

## Layer naming

Use lowercase `snake_case`, no spaces, stable side suffixes, and a single naming convention per character. Example biped:

```text
back_hair
cape_back
weapon_back
foot_l
shin_l
thigh_l
foot_r
shin_r
thigh_r
pelvis
torso
upperarm_l
forearm_l
hand_l
upperarm_r
forearm_r
hand_r
neck
head
hair_front
brow_l
brow_r
eye_l_open
eye_r_open
mouth_neutral
weapon_front
```

This example is a suggested draw-order sketch only; reorder it for the character's anatomy and direction. Rigby2D uses bottom-to-top layer order as draw order, so the layer tree must be deliberately arranged.

Rigby2D recognises standard part roles such as `head`, `torso`, `upperarm`, `forearm`, `hand`, `thigh`, `shin`, `foot`, `eye`, `mouth`, `hair`, `tail`, and others. Confirm the exact detected roles with `detect_parts` before AutoRig.

## Joint overlap

- Build enough hidden overlap into both adjoining pieces.
- Upper parts should cover the upper edge of lower parts through full expected rotation.
- Avoid placing the art seam exactly on the pivot line if it can reveal a gap.
- For sleeves, gloves, boots, armour and cuffs, plan whether the decoration belongs to the upper or lower segment.
- Test a range greater than the final intended motion so small later rig adjustments do not expose gaps.

## Mesh quality

- Use deforming meshes for parts expected to bend rather than rotating as rigid plates.
- Keep silhouettes smooth with enough thickness at joints.
- Avoid placing all mesh vertices in a single straight line through a bend.
- Verify weights by sampling deep bends and twists.
- Rigid objects (weapons, hard armour plates, tools) generally should remain rigid unless a specific bend is intended.

## Origin and scale

- Choose one consistent canvas size across all layers.
- For PSD import into Rigby2D, the world origin is the canvas bottom-centre. Put the feet/ground baseline there.
- Keep the character centred predictably; do not auto-trim each part into different canvases before PSD import.
- Record art scale and any intended engine-side scaling in the manifest.

## Animation readability

- Prioritise silhouette and timing over unnecessary key density.
- Give actions anticipation, contact/impact, follow-through and recovery.
- Avoid foot sliding in planted phases.
- Use clear key poses for attacks, jumps and interactions.
- Keep loops phase-aligned at start/end, including secondary elements.
- Use attachment swaps for discrete expressions/equipment; use bone/mesh animation for continuous motion.

## Deliverable names

Use the character ID (lowercase `snake_case`) as the filename stem, for example:

```text
hero.kra
hero.psd
hero.rigby
hero.json
hero.atlas
hero.png
hero_spritesheet.png
hero_spritesheet.json
```

Use engine subfolders for package-specific copies; do not create `hero_final_final2` variants. Prefer explicit version suffixes only for intentional revisions, such as `hero_v002.rigby`.
