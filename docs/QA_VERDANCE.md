# QA: round Verdance, first 60–90 minutes (owner item 41)

Glitch hunt on the default game (`--orbit`, first planet Verdance) by helper v3qa. Each row: what, status, and how to reproduce it. Positions are start-site local metres (x east, z south), the same as `--orbit-spawn=x,z`.

**Status:** fixed (with the commit tag `[v3qa]`), handed (to the helper who owns that area), open, or not reproduced.

## Tools used
- Soak: `godot --headless --path . -- --fresh --orbit --autoplay --soak --time-scale=8 --quit-after=2400` (game-minute lines `[soak] t=...`, `[soak] WARN ...`).
- Ground probe (new, `planet/sites/ground_probe.gd`): `godot --headless --path . -- --fresh --orbit --no-intro --ground-probe=300 --ground-probe-quit [--orbit-spawn=x,z] [--ground-probe-r=120]`. Lists floating and sunken props and junk pieces off the ground around Lumi.
- Round trips: `tools/run_tests.sh`; `godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh --orbit`.

## Glitches

| # | Area | What | Status | Repro |
|---|---|---|---|---|
| 1 | Progress | The story stopped at "Build your first robot": robots were built (cubes and parts spent, toast shown) but the step never completed, so nothing after it (zone, Haul Bug, seed, base levels) was ever offered. On the globe the Fleet keeps its robots in the crew and `robots()` is empty; objectives and goals counted `robots().size()`. The soak sat 36+ minutes with no new step after the Bot Bay. | fixed | Soak above: before the fix, `[onboard] objective bench2 done at 30.7 min`, then no objective for the rest of the run; `robot {"fleet":0,...}` events. Test: `tests/test_v3qa.gd::test_robot_objective_counts_globe_crews`. |
| 2 | Progress / save | "Send your robot to work" (paint a zone, B) could never complete on the globe: the count read the flat game's `GameState.world.orders`, and the globe crew's painted zones weren't saved either (lost on reload). | fixed | Paint a zone in the B view with a robot built: step stays at 0. Test: `test_globe_zones_count_and_save`. |
| 3 | Yard | Three small meshes of the workbench sit wholly under the ground (top 0.19 m below), at (-7.4, 8.2). Invisible; harmless. | open (cosmetic, not visible) | Ground probe at spawn: `[ground] sunk StartSite/Site_start_yard_#/Workbench/...`. |
| 4 | Soak | `Lumi stuck` warning at 5 min near the bin (-7.2, 2.9): autoplay shuttles between the bin and the junk next to it, so 3-minute displacement is under 3 m. Not a real stuck spot. | not a glitch | Soak, first 5 minutes. |
| 5 | Walking | Outpost wrecks on a slope: pieces float up to 0.56 m (a lying window frame, the tipped skip). The outpost stands on one tangent plane at its centre; the ground falls away under its far pieces. Now each top-level piece of the wreck (and of the rebuilt outpost) rides to the terrain under its own footprint, on the globe only. The rebuilt outpost's drop-in sparks also used world up (sideways on the globe). | fixed | Ground probe: `--orbit-spawn=160,0` (outpost near (176, -49)) and `--orbit-spawn=60,200` (near (-19, 180)): `[ground] float Outpost#/Ruin/... alt 0.56 m` before, gone after. |
| 6 | Events | Salvage Surge's sparkle tick picked a random piece of the glowing cell with `randi() % size`; a globe cell with no near pieces would divide by zero. Guarded. | fixed | Code path; not hit in two soaks. |
| 7 | Ground probe noise | Painted shop signs, neon backings and the billboard panel read as "floating" (they hang on walls and poles merged into big batches). Checked in code: they're attached. | not a glitch | Ground probe at spawn. |
| 8 | Robots / pad | The globe's Command view (B) only took the mouse: on a controller you could pan but not paint a zone or change the role, so "Send your robot to work" could not be done on a pad. Now the screen centre is the cursor (a reticle shows), hold A paints, hold X erases, Y cycles the role; the hint line follows the device. | fixed | Pad only: build a robot, D-pad down, try to paint. Test: `test_globe_command_pad_paints_and_cycles`. |
