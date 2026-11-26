# Visual pass: round Verdance (v7look, 2026-11-11)

The first real-renderer look at recent work (renders were blocked by a stale lock for a long time).
Shots are 960x540, Low quality, opengl3 (scratchpad `render.sh`), in `screenshots/v7/`.
Each line: what it shows, file, and OK / fixed (what) / open (why).

## Shots

### HUD and arrival
- Gantry Works arrival title, 1.6 s in (sky veil still lifting): `v7/hub_7_land_1.png`. OK (the title fades in as the veil lifts).
- Gantry Works arrival title: `v7/hub_7_land_9.png`. **fixed**: the title ran under the goal card and was crowded by the HUD lines. It now sits top centre in a column at most 62% of the screen wide (lines wrap), and the top-right cards fade out while it is up and come back after (`HUD.hold_corner`). `--ui-audit` has an `arrival` pass (title vs. the top-right cards, the cube counter, the subtitle bar, off-screen, clipped), every size, scale and language.
- Top-right corner (base % and bases n/6): `v7/pips_0.png`, `v7/cmd.png`. **fixed**: the two faint floating lines are now one glass card in the goal cards' style (base name and %, a 6 px green bar, "VERDANCE BASES 1/6"), placed *under* the goal stack, 10 px apart. In the default Minimal HUD it fades after 6 s idle as before, and since it is at the bottom it leaves no hole above the goal card. The subtitle bar keeps clear of both cards (`Subtitles._goal_rect` reads `HUD.corner_rect`).

### Command view
- Command view (card with OTHER BASES, painted hexes, hints): `v7/cmd.png`. **fixed**: the `--crew-command` hook used a game-time timer that never fired before the wall-clock shot (now `DevHooks.wait_wall`). In the view: the objective beam lay flat as a long white streak across the map (hidden in the Command view now); a light shade dims the world under the overlay so painted hexes and robot marks stand out on the pale ground; robot marks 8 px (were 6); the goal stack steps aside while the view is open (it collided with the hints at UI 1.25 and 1.5). The card reads at a glance.

### Robots
- Mk rank pips, Scoopie Mk III close-up (subtitles off, new `--no-subs` dev flag): `v7/pips_0.png`. **fixed**: the pips were 4 cm diamonds spinning round the lamp and could not be seen at all; bigger ones smeared into the orange lamp. Now a row of crisp gold diamonds with a dark rim (picture texture, `BotBadge._diamond_image`) between the head and the lamp, turned to face the camera; lamp 11 cm (was 8.5).
- Mk pips, Haul Bug Mk II close-up: `v7/pips_1.png`. OK after the fix (two diamonds, grey idle lamp, "z").
- Key-hint pill vs. the hotbar on a 960-wide screen (it covered STREAK and the hex count): **fixed** (third try, the owner's rule): always ONE row. When the row doesn't fit beside the hotbar's right readouts it gets smaller text and tighter gaps, then drops the words and keeps the key caps (`KeyHints.compact` 0/1/2, picked from measured widths). It hides completely while a WREN line or an arrival title is on screen, and fades back after. `--ui-audit` play pass: hints vs. hotbar, more than one row, mid-screen, still up during a WREN line.
- Arrival title with a WREN line playing (subs on): `v7/hub_7_land_9.png`. **fixed**: WREN's bar, the hotbar band and the key hints fade out while the title is up; the line pauses and plays on after (`Subtitles.hush`, `HUD.hold_corner(s, true)`). The arrival audit checks both.

### Pod (v7pod's cabin, merged)
- Cabin, stage 2 close-up: `v7/pod_pod_in2.png`. **fixed**: kit paint wear showed as grime smudges on the padded seat. Cushions, bolsters and quilted pads now use a new kit key `pad` (`KitMat.pad`: the paint colour, no wear in any state).
- Pod at stage 0, three-quarter view: `v7/pod_pod_q0.png`. **fixed**: the crash sparks used the star "sparkle" burst (0.18 m stars that hang for 0.9 s) and read as hard dots round the pod. They now use a new `spark` burst (6 cm soft points that spit out, fall fast and die in 0.38 s).

### Lumi
- Carry pose after the fix: `v7/feel2_q0/tour_29_carry.png`, `tour_31_carry.png` (the tray and the cyan lift beam read clearly at Low).
- Next-piece reticle after the fix: `v7/feel2_q0/tour_08_scoop.png`, `tour_12_scoop.png` (the bead on its stalk shows over the junk).
- Carry pose (q2 `v7/feel_q2/tour_28..31_carry.png`, q0 close `v7/feel_q0/`): **fixed**: the bale rode about 0.3 m over his head and his raised arms couldn't be made out, so it read as floating. There is now a carry rig: a gunmetal lift tray with a hazard-yellow lip under the stack, held by a soft beam in Lumi's laser colour from his head (`Patch._build_carry_rig`). The gap is the same (the owner had asked for it so the bale stops clipping).
- Next-piece reticle while scooping (q2 and q0): **fixed**: the ring was there (`aim` is set) but lay under the junk and, right in front of him, behind his body. It is brighter now, with a second outer ring, plus a glowing bead on a thin light stalk 1 m over the piece that shows above his head.

### Snag
- Hub 3: a 0.2x0.2 m box held Lumi up 0.6 s on a glancing push (`--feel=walk --feel-hubs=3 --feel-seed=3 --feel-props=80`). It was not the outpost ruin but the town's broken name sign: its square posts (planet/street_dressing.gd `_build_name_sign`, in every town with that sign). **fixed**: the sign posts, the fence posts and the neon sign's posts are round colliders now, and the snapped post lying in the dirt is a round log. Re-run: Lumi now slides past the post (7.9 m instead of 4.9 m). The walk still flags the push 3 m further on, where the fallen sign board blocks the way on purpose (a real wall, not a snag).

### Rocket picker
- Rocket picker at Gantry Works: `v7/hub_7_picker.png`. OK: it reads well (opaque card, two rows, clear Fly buttons). The old shot was taken 1 s after opening, mid fade-in; the dev hook now waits 6 s of wall clock.

### Screens
- Workbench at UI 1.0 (Upgrades / Lumi): `v7/bench10.png`. OK.
- Workbench at UI 1.5 (Research): `v7/bench15.png`. OK. The detail column wraps into short lines next to the big icon; it is readable, but at 1.5 it is the tightest screen.
- Title at UI 1.0 / 1.5: `v7/title10.png`, `v7/title15.png`. Menu OK. **open**: the background camera sits close to tall buildings, which show as big blurry beige blocks across the top right (see "Needs a decision").
- Settings, German, UI 1.5: `v7/settings_de15.png`. OK.
- Survey map at UI 1.0 / 1.5: `v7/survey10.png`, `v7/survey15.png`. Card OK. The headline "0.0000 %" on a fresh game is the agreed tiny-progress format (tests pin it). **open**: the globe's place labels ("Landing Yard") are too small to read at 960x540.
- Play view, subs on, 960x540: `v7/play_subs.png` (hint column beside the hotbar; while WREN speaks over it, it fades).

### The world comes alive (v6life)
- Day, cleaned (6 rings, ramp, grown), facing town: `v7/life_on_0.png` vs. dirty `v7/life_off_0.png`; facing the pad's other side: `v7/life_on_1.png`. The difference reads at once (green lawns, tufts, flowers, a living street vs. bare grey ground). **fixed**: the lawn rendered as one flat lime carpet (rejected by the owner before). The ground shader now breaks it up with darker clumps and dry sunlit tips at two scales, and Low gets denser tufts over more rings (data/life.json `tufts_per_cell` 44 -> 70, `tuft_rings` 3 -> 4). Re-render: `v7/life2_on_0.png` (the lawn now has clumps; from the pad it is still a far strip, and the tour's stops look mostly at the concrete pad). `life2_on_1.png` is a bad dev stop (Lumi put inside a building), not a game bug.
- Dusk, cleaned vs. dirty: `v7/life_on_2.png`, `v7/life_on_3.png` vs. `v7/life_off_2.png`. OK: lit windows across the blocks, lit lamps, fireflies as small points over the grass; the dirty town stays dark. Butterflies are too small to pick out at 960x540 Low (they are there in the [life] report).

## Needs a decision
- ~~Title screen background~~: done by the main session's decision, see "Title" above.
- **Life tour viewpoints**: the dev tour's stops are set by distance from the start cell, so they mostly frame the concrete pad. To judge cleaned ground fairly, add stops that face a cleaned street from about 10 m (e.g. `--life-tour-stops` with cam_dist and pitch), and judge from those before tuning the grass any further.
- **Survey globe labels** (`v7/survey10.png`): the place names on the little globe are unreadable at 960x540. Recommendation: hide the names below a zoom level, and let the card name the hub under the cursor.
- ~~Shared settings file~~ **fixed**: a dev or test run with --fresh, --nosave, --ui-scale, --locale, --quality, --ui-audit, --colorblind, --no-subs or --menu applies those for the run only and never writes user://settings.cfg (`Settings.no_write`, set by DevHooks). test_settings.gd uses its own per-process file (the shared one made `rebind_persists` flake when two runs overlapped), and a new test checks that a no_write save leaves the player's file alone.

### Title (group 3, the main session's decision)
- Old: `v7/title_t0.png`, `title_t12.png` (the camera's high passes went right past huge untextured skyline blocks, and the pod sat tiny far below). **fixed**: the title is now one slow drifting shot, low over the clearing. The crash-site pod (lamp, smoke plume) and Lumi cleaning sit right of centre, clear of the menu, with the trashed ground running back into the low sun's haze (`TitleCinematic._drift`; the old keyed path stays behind `--title-old`). The plain box skyline is gone (`--title-skyline` brings it back). Shots: `v7/title4_960.png` (Low 960x540, with a save), `title4_nosave.png` (first launch, new dev flag `--menu-nosave`), `title4_720q1.png` (Medium 1280x720), `title4_720q0.png` (Low 1280x720, later in the drift). Earlier steps: `title2_*`, `title3_*`.

### Woken bases (dev chain, `--lm-shots=PREFIX`: Lumi on open ground by the landmark, by day and at dusk)
- Garden Row, windpump: `v7/hub_9_woken.png`, `hub_9_woken_dusk.png`. OK (from 30 m; its lamps are small at dusk).
- Gantry Works, gantry crane: `v7/hub_7_woken.png`, `hub_7_woken_dusk.png`. OK, looks great.
- Signal Heights, signal mast: `v7/hub_8_woken.png`. OK (from its foot, top cut off). The first try put Lumi inside a building; the dev placement now uses the reach check's open ground.
- Fairground, big wheel: `v7/hub_2_woken_dusk.png`. OK: lit gondolas, a fine dusk shot.
- Stack Works, tall stack: `v7/hub_4_woken.png`. OK.

### Landmarks asleep and at night (lineup)
- Asleep (`--lm-state=broken`): `v7/lm_broken_lm_*.png`. OK: faded, rusty, no glow; reads as asleep at a glance.
- Night (repaired): `v7/lm_night_lm_*.png`. Landmarks OK: warm lamps, lit consoles. **fixed**: the pod's tall smoke plume (behind several lineup shots) was unshaded and stayed cream-white at night, reading as glowing white curtains. It is lit by the scene now, with only its ember foot and a faint self-light (`art/shaders/smoke_plume.gdshader`). Re-render: `v7/lm2_night_*.png` (now a dim brown column, no longer white curtains; it still shows as a few tall streaks in the lineup), by day `v7/lm2_day_*.png` (unchanged, grey).

### Cleaned street vs. dirty (new stops: Lumi past the pad's edge, facing out)
- `v7/street_on_0..3.png` vs `v7/street_off_0..3.png`: the difference is huge and pleasing (a tidy street with lawns, tufts and props vs. a sea of litter). **fixed** (second step): close up, the lawn still read as a flat lime carpet; the clump/dry-tip breakup is stronger now, with a fine mottle and a slightly deeper green. Re-render: `v7/street2_on_*.png` (the near lawn is mottled now; still a smooth lawn rather than meadow, but no longer one flat tone).

### Survey map at 1280x720
- `v7/survey720.png`: card OK; the place names on the globe were about 8 px tall, unreadable at 1280x720 too. **fixed**: labels at about twice the size (`globe_view.gd`). Re-render: `v7/survey720b.png`: "Landing Yard" and "Garden Row" read clearly.
