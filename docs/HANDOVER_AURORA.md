# Handover: Aurora (Lumi) hero model v2

Branch `wt/hero`. The latest `claude/kind-wright-rhxixd` is merged in. The owner reviews Aurora only. Do not start the other five designs.

## Where things are
- Concept references (copied into the repo; `.gdignore` keeps Godot from importing them):
  - `art/concept/aurora_portrait.png`: materials, face, lighting, 3/4 angle.
  - `art/concept/aurora_turnaround.png`: front, 3/4, side, back 3/4, back.
  - `art/concept/lumi_concept.png`: the full sheet.
- Model: `art/models/aurora/build_aurora.py` (Blender 4.0, scripted) writes `art/models/aurora/aurora.glb`.
  - Build: `blender -b --python art/models/aurora/build_aurora.py`.
  - Quick Cycles shape preview (4 views, about 50 s): add `PREVIEW=/tmp/p`.
  - `designs.glb` (the other designs' add-ons) is untouched. It is rebuilt only with `DESIGNS=1` from `designs_addons.py`, using the old head constants.
- Runtime: `player/patch_model.gd` (PatchModel).
  - `VARIANTS["aurora"]` holds the sampled palette.
  - Also here: the material map, `ARM_REST` idle pose, `ANCHORS`, `BEACON_LOCAL` and `EYE_SHAPES`.
- Shaders:
  - `art/shaders/hero_paint.gdshader`: v2 procedural wear, clear-coat, warm/cool rim.
  - `art/shaders/bot_face.gdshader`: crescent eyes, `eye_shape`, crisp blink, warm visor streak.
- Review scene: `scenes/hero_preview.tscn` with `--view=portrait|head|chest|turn|blink`.
- Tests: `tests/test_hero_model.gd`.
  - Covers: parts, the single face surface, anchors, the claw/chest points, eye shapes, blink and happy snapping.
  - Also: the beacon stays within 2 cm of the head over 3 s of animation for every design.

## v2 done so far (committed)
- **Head:** a superellipsoid pill/capsule.
  - Exponents 3.0 horizontal, 2.9 vertical; half sizes 0.415 x 0.295 x 0.335.
  - Slightly domed top, convex face.
  - The visor recess cut is fixed for the curved shell: the cutter's back cap is triangulated, or EXACT left a patch of shell in the middle of the visor.
  - Crown slot with a lid, back vent band with amber LEDs, big dark neck opening at the back with cables, real panel grooves, screws.
  - Dark side modules with layered rings, a cyan ring lens, steel fins and a glass lens.
- **Fin:** a brushed-metal stalk from the back-top, leaning back, with a long flat amber paddle and a lit lighter edge (materials `fin`, `paddle`, `paddle_edge`).
- **Torso:** 0.60 x 0.31 x 0.42.
  - A closed cyan light band in the top seam (`glow`), and a dark machinery bay under the head with a cyan strip.
  - A recessed dark frame holding the raised, bevelled chest plate, with screws and the modelled recycle icon.
  - Glowing orange latches (`latch`) in dark housings, orange flank vents, a dark lower panel band, steel socket rings.
- **Hover pod:** dark bowl with a steel lip, the big cyan ring underneath (R 0.149) and a glowing core disc.
- **Arms:** shoulder drum + cap, upper core + guard, elbow drum + caps, chunky forearm.
  - Pistons and cable bundles (`cable`) cross the joints.
  - Chunky segmented claws: the base segment plus a hooked tip.
  - The idle pose holds the arms out and slightly up (`ARM_REST`). Scoop, hold and photo poses still work.
- **Poly count:** about 68k triangles in the hero glb, plus about 6 x 1.2k for the claws. The head and body are decimated to 0.6.
- **Wear:** texture baking was tried and does NOT work in this container. Blender 4.0.2 Cycles bakes every shaded pass to images as black (EMIT, DIFFUSE colour and AO all came out black; only NORMAL works).
  - So the wear is per-pixel procedural in object space in `hero_paint.gdshader`, driven by per-vertex AO / edge / cavity / joint masks.
  - Layers: dark speckle chips in two sizes plus edge flakes, denser on edges, joints and up-facing surfaces; lighter worn edges; tiny rust specks; two-direction scratches; seam grime with downward streaks; dust.
  - The paint has a clear-coat.
  - If a working Blender is available on the new machine, baking real 2K masks per part is still the better option.

## Palette (sampled from art/concept, sRGB)
| Element | Sampled | Used |
|---|---|---|
| Shell cream, lit (turnaround) | (204,195,199) / (191,193,203) | paint Color(0.839,0.808,0.765) = #D6CEC3 |
| Warm grey shadow on shell | (161,135,127) #A1877F, (126,108,97) | comes from the lighting |
| Visor black | (18,32,36) / (7,10,11) | face glass vec3(0.006,0.008,0.011) |
| Eye cyan core | (158,245,252) #9EF5FC, (183,248,250) | glow Color(0.25,0.886,0.94); the crescent lightens toward the core |
| Eye cyan edge | (23,82,91) | halo |
| Pupil | (12,23,26) | glass |
| Orange latch | (241,107,3) #F16B03 | accent / latch Color(0.945,0.42,0.012) |
| Cheek amber | (248,175,9) #F8AF09 | lamp Color(0.973,0.686,0.035) |
| Fin paddle amber | (243,192,64) #F3C040 | paddle Color(0.953,0.753,0.251) |
| Paddle top edge | (236,155,70) and lighter | paddle_edge = paddle lightened 0.35, lit |
| Dark joint metal | (29,32,36) #1D2024 | dark Color(0.114,0.125,0.141), metal 0.85, rough 0.26 |
| Pod ring cyan | (52,145,157) up to (155,235,246) | thruster = glow |
| Torso glow strip | (155,235,246) #9BEBF6 | glow, energy 3.6 |

## Next
1. Render and review against the concept:
   - portrait, head close-up, chest close-up, the 5-view turnaround, blink;
   - then ONE in-game Old Town shot and a title-screen shot (`--menu`) at the end.
   - These have not been rendered since the latest v2 changes. `screenshots/hero/portrait_v2.png` is from before the visor and shape fixes.
2. Known gaps to check after rendering:
   - **Speck density:** reduced after the first v2 render, which looked like freckles.
   - **Left-arm reach pose in the preview** (`hero_preview.gd` `_pose`): it should match the portrait, arm out to the side at shoulder height.
   - **Paddle size and angle.**
   - **Pod size:** the concept's pod is smaller and flatter.
   - **Visor reflections:** they rely on the sky / reflection probe in each scene.
   - **Speed:** the paint shader's cost (5 cellular lookups per pixel) on slower GPUs.
3. Copy the finals to `/home/user/Greenfall/screenshots/hero/*_v2.png` and list every remaining difference honestly.

## Commands
```
blender -b --python art/models/aurora/build_aurora.py                  # rebuild aurora.glb
godot --headless --import --path .
SKIP_ROUNDTRIP=1 tools/run_tests.sh -gselect=test_hero_model             # hero tests
tools/hero/render.sh 1120x700 --view=portrait --out=screenshots/hero/portrait_v2
tools/hero/render.sh 1080x800 --view=head     --out=screenshots/hero/head_v2
tools/hero/render.sh 1080x800 --view=chest    --out=screenshots/hero/chest_v2
tools/hero/render.sh 640x800  --view=turn     --out=screenshots/hero/turn_v2
tools/hero/render.sh 960x600  --view=blink    --out=screenshots/hero/blink_v2
for v in portrait head chest turn; do python3 tools/hero/compose_v2.py screenshots/hero $v; done   # concept vs render sheets
QUALITY=2 RES=1280x720 DELAY=110 tools/shot.sh hero/oldtown_v2 --no-intro --demo-scoop --cam=close --demo-yaw=2.5   # once, at the end
```
`tools/hero/render.sh` waits until no other Vulkan Godot is running and at least 6 GB is free. It was made for the shared container, so drop the gate on a dedicated machine.

The `blink` view writes `blink_v2_0..3.png`. `compose_v2.py` has no blink option yet (the v1 blink sheet is `screenshots/hero/blink_sequence.png`), so lay those four frames side by side by hand.

Full checks before reporting: `godot --headless --path . --import`, `tools/run_tests.sh`, `godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh`, and a headless autoplay.
