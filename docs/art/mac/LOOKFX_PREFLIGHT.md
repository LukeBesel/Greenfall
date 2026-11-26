# Look-fx review: preflight (no GPU frames yet)

Art branch tip: `e1a097d486974332223ce67b21efd7d535859a59` (`claude/practical-meitner-eipd0h`), 26 Nov 2026.

**Status: the Mac review has not been run.** The session that wrote this was a Linux cloud container
with no GPU, and the Mac's Greenfall folder was not reachable from it. Nothing below was seen on
screen. It is a reading of the code, to be confirmed or thrown out by the real frames.
`LOOKFX.md` (the actual report) does not exist yet.

## To run the review on the Mac

```bash
git fetch origin && git checkout claude/tender-faraday-klx84n
```

```bash
bash docs/art/mac/run_lookfx.sh
```

About an hour. It stops if it is not on macOS or Godot is not 4.7.2-stable. It writes 39 JPEG frames
(5 times of day x 3 variants x start pad and lake, plus dusk at yaw 90/180/270), the logs, the
hardware, and `lookfx/perf.tsv` (3 runs each, median, with and without `--disable-vsync`).
Someone still has to look at the frames and write `LOOKFX.md`. `PARTS=frames` or `PARTS=perf` runs half.

## Findings from the code, most important first

1. **The puddles are not on this branch.** The brief says the ground's wetness and puddles are in
   `planet/sphere/sphere_ground.gdshader` (uniform `wetness`, marked `[art3]`) and always on. At
   `e1a097d` that shader has no `wetness` uniform and no `[art3]` mark; the only `[art3]` in the
   repository is the look-fx block in `planet/sky_director.gd:475`. The shader's last commit is
   `ebb15192` (art stage 1). Either the puddle work was never pushed, or it lives somewhere else.
   Until it is pushed, every puddle question in the review has nothing to look at on the globe.
2. **SSR probably has nothing to reflect off.** The ground writes `ROUGHNESS` 0.95 (dry) to 0.6
   (lake banks) and `SPECULAR` 0.35 to 0.4 (`sphere_ground.gdshader:178`); open water turns the
   renderer's reflection off on purpose (specular 0, its own sky term). Screen-space reflections
   fade out as roughness rises, so on this ground `--look-fx` is likely to pay for SSR and show
   almost none. A puddle needs roughness near 0.05 to 0.1 to mirror the sky. Expect the with/without
   frames to differ only by the fog. If so, either leave SSR off until puddles exist, or cost it
   separately.
3. **The fog is not thin at range.** Density is `lerp(0.0012, 0.004, haze) * K` over a 260 m volume
   (`sky_director.gd:483`). Light surviving 260 m of it: 73% (clear air) down to 35% (full haze) at
   K=1, and 54% down to 12% at K=2. Plain depth fog is added on top. With `volumetric_fog_sky_affect
   = 0` the sky stays clean, which answers the old "fog hides the sky" complaint, but far land goes
   pale against an unfogged sky; look for a bright rim where terrain meets the horizon, worst at
   K=2 in the hazy first act. Starting suggestion if it washes out: cap at 0.0025, keep K=1.
4. **Shafts need something to cast them.** Sun scatter is `lerp(0.6, 2.2, low_sun)` with anisotropy
   0.75, so the fog will glow strongly toward a low sun. That gives a bright haze around the sun,
   not shafts, unless buildings, trees or clouds shadow the volume. From the start pad expect a
   glow; shafts are most likely between town buildings. The sunward yaw frames test this.
5. **V-Sync will probably cap the timing runs, and `--disable-vsync` may not lift it.**
   `Settings.apply_display()` (`autoload/Settings.gd:650`) sets the V-Sync mode from the saved
   setting (default on) after the engine flag is read. If the "off" rows in `perf.tsv` sit at the
   display's refresh rate, turn V-Sync off in the game's settings once and rerun `PARTS=perf`.
6. **Night.** The moon scatters into the fog at 0.4 and ambient inject is 0.15, on top of a night
   exposure of 1.55. Watch for a grey lift of the night ground at K=2.

## What was not done

No frames, no frame rates, no judgement against `art/concept/world_target.jpg`, no chosen K.
The script was syntax-checked and its frame-rate parsing tested on sample lines, but it has never
run on a Mac.
