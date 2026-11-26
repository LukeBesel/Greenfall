# Handover: Aurora (Lumi) hero model v2

Branch `claude/greenfall-aurora` (was `wt/hero`). The owner reviews Aurora only. Do not start the other five designs.

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
- **Wear (updated, aurora session 2):** baking works with the official `bpy` 4.2 wheel from PyPI; only Debian's Blender 4.0.2 bakes black. `tools/hero/bake_masks.py` bakes a 2K mask atlas (`art/models/aurora/aurora_masks.png`: R = AO, G = bevel edge, B = cavity) into one UV atlas shared by every hero part. **Re-run it after every build_aurora.py run** (the atlas UVs change).
  - So the wear is per-pixel procedural in object space in `hero_paint.gdshader`, driven by per-vertex AO / edge / cavity / joint masks.
  - Layers: dark speckle chips in two sizes plus edge flakes, denser on edges, joints and up-facing surfaces; lighter worn edges; tiny rust specks; two-direction scratches; seam grime with downward streaks; dust.
  - The paint has a clear-coat.
  - If a working Blender is available on the new machine, baking real 2K masks per part is still the better option.

## Character-builder slots (aurora session 2)
Every swappable characteristic is its own part or its own colour key, so a builder can mix them:
- **Shapes:** `PatchModel.SLOT_DEFAULTS` maps `head`, `visor`, `ears` (side modules, now split out of the head), `finger` and `finger_tip` (hands) to parts in aurora.glb. A variant or builder save overrides a slot by naming another part with the same pivot conventions (unknown names fall back to Aurora's).
- **Eyes:** `"eyes"` -> `EYE_SHAPES` (face shader), independent of the head mesh. The face size is set from the visor outline (`half_width` / `half_height`).
- **Colours:** `paint`, `trim`, `glow`, `accent`, `lamp`, `paddle` plus `COLOR_DEFAULTS` keys `dark`, `fin`, `claw` and `cable`.
- **Toppers:** the `"acc"` list, placed on the `head_top` / `beacon` anchors. Add-on parts (`acc_*`, own UVs) get mask-free material copies automatically.
- **Arm and claw size:** `ARM_SCALE` / `CLAW_SCALE`.

The other five designs' add-ons in designs.glb still use the previous head constants (not rebuilt, as asked).

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
/tmp/bpyenv/bin/python tools/hero/bake_masks.py                       # then ALWAYS re-bake the mask atlas (bpy 4.2 venv, see the script header; ~4 min)
godot --headless --import --path .
SKIP_ROUNDTRIP=1 tools/run_tests.sh -gselect=test_hero_model             # hero tests
tools/hero/render.sh 1120x700 --view=portrait --out=screenshots/hero/portrait_v2
tools/hero/render.sh 1080x800 --view=head     --out=screenshots/hero/head_v2
tools/hero/render.sh 1080x800 --view=chest    --out=screenshots/hero/chest_v2
tools/hero/render.sh 640x800  --view=turn     --out=screenshots/hero/turn_v2
tools/hero/render.sh 960x600  --view=blink    --out=screenshots/hero/blink_v2
tools/hero/render.sh 800x800  --view=hands    --out=screenshots/hero/hands_v2   # both claws, one shot each
for v in portrait head chest hands turn; do python3 tools/hero/compose_v2.py screenshots/hero $v; done   # concept vs render sheets
QUALITY=2 RES=1280x720 DELAY=110 tools/shot.sh hero/oldtown_v2 --no-intro --demo-scoop --cam=close --demo-yaw=2.5   # once, at the end
```
`tools/hero/render.sh` waits until no other Vulkan Godot is running and at least 6 GB is free. It was made for the shared container, so drop the gate on a dedicated machine.

The `blink` view writes `blink_v2_0..3.png`. `compose_v2.py` has no blink option yet (the v1 blink sheet is `screenshots/hero/blink_sequence.png`), so lay those four frames side by side by hand.

Full checks before reporting: `godot --headless --path . --import`, `tools/run_tests.sh`, `godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh`, and a headless autoplay.

## Report: aurora session 2 (owner's five gaps, hands, builder slots)
Final comparison sheets are committed: `screenshots/hero/compare_{portrait,head,chest,hands,turnaround}_v2.png` and `blink_v2_0..3.png`.

### Done this session
1. **Head.** A soft superellipsoid pill with the turnaround's proportions: about 1.3:1 without the side modules (half sizes 0.43 x 0.32 x 0.335). The visor is about 0.8 of the head's width and 0.75 of its height. Eye size and spacing are re-measured from the turnaround front view. The big dark vent slot sits high on the back.
2. **Fin.** A taller, thicker dark teal-grey stalk with a wider, clean, saturated amber paddle (few chips, no grime wash), tilted tail-up, with a thin lighter lit edge.
3. **Light band.** A thicker cyan loop round the torso's top seam plus a brighter bay strip.
4. **Arms and pose.**
   - Arms are 1.2x and claws 1.3x (`ARM_SCALE`, `CLAW_SCALE`).
   - The portrait pose is now the concept's: pitched forward and leaning toward the can, left arm reaching, right arm out and down.
   - The review camera looks down on him a little, like the concept.
5. **Torso.**
   - Taller (0.34) at the concept's width, with the hover pod moved down with it.
   - Glowing orange latches at the concept's saturation, a flush dark lower band and a slimmer recycle icon with a hollow middle.
   - The pod is a flatter dark disc with the bright cyan ring at its rim, plus an inner ring and core.
6. **Hands** (owner's follow-up request). Each finger is a chain of three armoured blocks: a light worn-grey plate over a dark core, steel knuckles, dark gaps and pads. The chain curls into an open C with a short hooked end, on a cream cuff and dark palm with a steel ring. `--view=hands` renders both claws.
7. **Colours and wear.**
   - Shell paint lowered to the sampled pinkish grey.
   - Chips are warm dark brown (sampled 60–85 / 38–68 / 24–62 sRGB) and matte. They come in clusters with clean stretches between, at about 2 cm cell size, plus small specks, edge flakes and diagonal smear scuffs.
   - Broad brown stains; a warm sun-side rim and a cool cyan shadow-side rim (`rim_strength` 0.11).
8. **Real baked maps.** Baking works with the official `bpy` 4.2 wheel; Debian's Blender 4.0.2 still bakes black. `tools/hero/bake_masks.py` bakes a 2K AO / edge / cavity atlas, and the paint shader uses it per pixel. The chips and scuffs stay procedural per pixel on top: same resolution, no seams, and they recolour per design.
   - Fixed a GLB-writer bug: it merged vertices across UV seams.
9. **Character builder.** Each characteristic is swappable on its own; see "Character-builder slots" above. The side modules are now their own `ears` part.
10. **Review tool fixes.** The head and chest close-ups had been rendering the portrait camera (the portrait branch swallowed them), and review shots could catch a random blink. Both fixed.

### Remaining differences vs the concept (honest list)
- **Head reads rounder in the portrait.** The concept portrait's head looks wider, but that's perspective plus the forward tilt. Measured on the orthographic turnaround it is about 1.3:1, which is what the model uses. If the owner prefers the portrait's wider look, lower `HB` (0.32 -> about 0.29) and re-measure.
- **Torso still a little short.** The concept's torso plus dark band is about 0.67 of the head's height; ours is about 0.55. Making it taller means moving the head pivot, arm sockets and every torso feature together.
- **Idle arm pose.** The turnaround's arms hang down at the sides; our idle (`ARM_REST`) holds them out and up, as the owner asked for the portrait look. The turnaround view uses the idle pose.
- **Eyes and lamps.** The eye cyan is paler and the bloom wider than the concept's saturated (158,245,252), and the pupil is a touch smaller. I did not touch the face shader (the earlier eye fixes stay). The cheek lamps still render slightly pale yellow rather than deep amber.
- **Visor reflections.** The concept's warm orange environment reflections in the lower visor depend on each scene's sky; the preview has a plain sky, so we get a white streak instead.
- **Side modules.** The concept's lens is near-black glass with almost no visible detail. Ours shows the steel fins and rings, and reads lighter at grazing angles (side and back views).
- **Hands.** The blocks are rounder (subdivided) than the concept's crisper chamfered plates. Each claw has 3 fingers, as in the concept, but the portrait's claws are seen side-on and look bigger through perspective.
- **Wear.** The concept's scuffs include a few long thin scratches and orange-brown rust stains on the back of the head; ours has short smears and tiny rust specks. Density on lit surfaces is close; ours reads more evenly spread on the back.
- **Panel detail.** The concept's head has more visible panel seams (a vertical seam on each side behind the visor, a crown panel). Ours are shallower grooves that only read up close.
- **Hover pod.** Still bulkier than the concept's slim dark disc, and the concept's underside shows concentric glowing rings that read more strongly than our inner ring and core.
- **Turnaround floor.** The plain studio floor shows bright reflection patches behind the 3/4 and back views; that's the preview scene, not the model.
- **Not re-rendered this session:** the in-game Old Town shot and the title-screen shot.

## Concept match pass (art2, 26 Nov): measured against the turnaround
The owner asked for Lumi to look exactly like the concept. This pass rebuilt the proportions and the part layout by measurement; the sections above describe the model before it (sizes there are out of date).

### Measuring loop
```
blender -b --python art/models/aurora/build_aurora.py     # about 20 s
python3 tools/hero/quick_views.py screenshots/hero/q      # flat-shaded turnaround views of the posed glb, 2 s, no Godot
python3 tools/hero/overlay.py screenshots/hero/sheet.png screenshots/hero/q     # IoU, band widths, part measures, sheet
python3 tools/hero/bake_masks.py                          # ALWAYS before a Godot render (python3 = the bpy 5.3 module; 2 min)
tools/hero/render_gl.sh 1280x800 --view=turn --no-floor --out=screenshots/hero/turn_nf   # the real look (queues)
python3 tools/hero/overlay.py screenshots/hero/sheet.png  # same numbers on the Godot frames
python3 tools/hero/overlay.py --board docs/art/lumi_match_board.jpg docs/art/lumi_overlay_r1.jpg   # the three-row board
```
- `overlay.py`: concept masks come from a per-row backdrop model (the empty columns between the figures), holes filled, largest blob kept, the glow plume cut at the lit lower disc. Renders are keyed on the green backdrop `--no-floor` now draws. Every figure is scaled from the top of the head shell to the bottom of the hover unit and centred on the head, so the antenna's pose does not move the numbers.
- `quick_views.py` reads `ARM_REST`, `ARM_SCALE`, `CLAW_SCALE`, `ACC_FIT`, `VARIANTS` from `player/patch_model.gd` and `TURN_VIEWS` from `scenes/hero_preview.gd`. `--design=ID` adds a design's add-ons, `--pose=scoop|carry|hold|pet` shows an arm move.
- `TURN_VIEWS` (hero_preview.gd) are the sheet's five views at eye level: front, front 3/4 (his left ear toward us), the body side-on with the head turned on, straight back, back turned 20 degrees. The sheet's third figure is not a true side view (it shows the back of the head over a side-on body), so that view turns the head 45 degrees.

### What the concept measures (and where the sheet disagrees with itself)
| Measure | Concept | Model |
|---|---|---|
| Head height / width with ears, front | 0.73 | 0.79 |
| Same, straight back / turned back | 0.81 / 0.85 | 0.79 / 0.74 |
| Head share of body height | 0.55 | 0.57 |
| Head width / body height, front / back | 0.75 / 0.68 | 0.71 / 0.71 |
| Torso width / head width, front / back | 0.63 / 0.58 | 0.62 / 0.62 |
| Arm span / head width, front / back | 1.12 / 0.85 | 1.07 |
| Hover ring / head width | 0.40 to 0.53 | 0.46 |
| Eye ring diameter / visor height | 0.55 | set 0.55 |
| Eye ring stroke / visor height | 0.09 | set 0.08 |
| Ear ring diameter / head height | 0.48 | 0.47 |
The sheet's back views draw a smaller head (0.68 against 0.75 of the body height) and arms tucked in (span 0.85 against 1.12) than its front view. One model cannot be both: the head is set between them and the arms to the front view. That is the floor under the back views' overlap numbers.

### What changed in the model
- Head: half sizes 0.36 x 0.325 x 0.315 (was 0.43 x 0.32 x 0.335), a rounded box (exponents 2.7 in plan, 3.0 up, 3.1 down). Visor 0.60 x 0.356 in a dark frame. Bigger cheek lamps lying on the shell. Ear modules R 0.16 seated in sockets with a thin ring (R 0.132, tube 5.8 mm). Raised back plate over the vent band (now at mid height with four amber lights), belt seam, a tall neck recess with ribs, drums and cables. Shorter stalk, small paddle.
- Torso: 0.52 x 0.32 x 0.385 (was 0.60 x 0.34 x 0.42), straight sides with the hips angling in, dark keel, dark underside. Cyan strip along the top front and a line down each side of the plate (the closed loop round the torso is gone). Latches on the shoulder plates. Cyan-lit square frame round the bale hatch.
- Hover unit: stem, dark tiered ring disc (R 0.178) with a cyan ring on its top face and one underneath, and a lower emitter disc (R 0.114) whose top and underside glow. The old wide bowl is gone.
- Arms: shorter segments with thicker armour; `ARM_REST = (-0.2, -0.75, 0.55)` hangs them down and a little out (x = shoulder pitch, y = elbow bend, z = roll outward), `ARM_SCALE` 0.85, `CLAW_SCALE` 1.15.
- Glow: `GLOW_E`, `GLOW_SOFT_E`, `RING_E` (about 1.3 to 1.45) instead of 2.8 to 4.5, so strips and rings stay cyan instead of clipping to white.
- Paint: warmer cream; `hero_paint.gdshader` gained `rust_bright`, `rust_chips`, `rust_stain` (rust-orange chips and soft stains from seams), fewer dark specks.
- Eyes: `ring_inner` 0.7 (set by PatchModel; the shader default stays 0.56 for the rocket's face), radius 0.55, a soft glow on both sides of the stroke, a smaller dot.
- `ACC_FIT` re-fitted for the five other designs (cat ears and Pixel's fins narrower, hearts on the new ear hubs, toolbox on the slimmer hip).
