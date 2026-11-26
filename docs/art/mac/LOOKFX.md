# `--look-fx` review: status and code findings

**Status: not yet looked at on the Mac.** No frames were rendered and no frame rates were measured.
The session that was given this review ran in a Linux cloud container (`uname -s` = `Linux`, no GPU)
and could not attach the Mac. Everything below comes from reading the code at the hash; the items
marked *predicted* are arithmetic, not observation, and need the frames to confirm.

- Art branch tip reviewed: `e1a097d486974332223ce67b21efd7d535859a59` (`claude/practical-meitner-eipd0h`)
- Godot: 4.7.2.stable (headless smoke test only: all the flags in the brief are recognised, `--lake-view`
  finds a lake 182 m from the start, `--perf` prints `game_fps`)
- Hardware: none (to be filled in from `lookfx/hardware.txt`)

## To finish this on the Mac

    bash docs/art/mac/run_lookfx.sh

It refuses to run off macOS, captures the 39 frames (start pad and lake shore at five times of day, and
three yaws toward the dusk sun, each without the flag, with `--look-fx` and with `--look-fx=2`) as
JPEG 88 in `docs/art/mac/lookfx/`, and writes `perf.tsv` (median `game_fps` after 20 s, three runs
each, V-Sync disabled) and `hardware.txt`. Then look at every frame and replace this file's
findings with what is seen.

## Frame rates

| Scenario | no flag | `--look-fx` | `--look-fx=2` |
|---|---|---|---|
| Standing on the start pad, dusk, 40 s | not measured | not measured | not measured |
| Boost walk from `0,-260`, 75 s | not measured | not measured | not measured |

## Findings from the code, most important first

### 1. There are no puddles in the ground shader at this hash
The brief says the wetness and puddles are in `planet/sphere/sphere_ground.gdshader` under a
`wetness` uniform marked `[art3]`. At `e1a097d4` that file has no `wetness` uniform and no `[art3]`
mark (`[art3]` appears only in `planet/sky_director.gd:475`); `claude/kind-wright-rhxixd` is the same.
The only wet term is the old bank wetness from `UV2.y` (lines 133 to 137, 178 to 179), which exists
next to lakes and nowhere on the start pad. The puddle work is probably uncommitted in the art
session. Until it is pushed, the puddle questions (mirror or oil stain, size, spacing, threshold)
cannot be answered on any machine.

### 2. Screen-space reflections have nothing to reflect on (predicted: cost with no visible change)
- Ground: `ROUGHNESS` is 0.95 dry and 0.6 on wet banks, `SPECULAR` 0.35 to 0.4. At roughness 0.6 a
  reflection is a broad blur, not a mirror.
- Lake water (`planet/sites/sphere_water.gdshader`): `blend_mix`, writes `ALPHA`,
  `specular_disabled`, `ROUGHNESS = 1.0`, `SPECULAR = 0.0`. Transparent materials are not in the
  buffers screen-space reflections read, and this one has no specular at all. It paints its own sky.

Suggested for the puddle branch of the opaque ground shader: `ROUGHNESS` 0.05 to 0.10,
`SPECULAR` 0.5, albedo about 0.03 to 0.05 (dark, not black: the old `puddle.gdshader` note says
near-black read as a hole where reflections were missing). The note on line 178
("0.12 mirrored the sky as a white strip") may have been seen on software GL (the water shader reports the same white mirror on opengl3); it needs
re-checking on Metal, where the reflection should be the sky gradient, not white.
If the frames confirm no visible change from reflections, drop them from the flag until the
puddles land and save their cost.

### 3. Fog density at `--look-fx=2` is likely to wash a fresh game (predicted)
A fresh game starts with `haze = 1.0`, so density is `0.004 * K`, over `volumetric_fog_length = 260`:

| | at 100 m | at 260 m |
|---|---|---|
| K = 1, haze 1 (`0.004`) | 67% of the scene left | 35% |
| K = 2, haze 1 (`0.008`) | 45% | 12% |
| K = 1, clean air (`0.0012`) | 89% | 73% |

This is on top of the depth fog (`fog_density` 0.0014: 69% left at 260 m). So in Act 1 at K = 2 the
far town keeps about 9% of its own colour, which is the grey wash the owner complained about, only
arriving through a different setting. Expected best is K = 1 or lower; try `--look-fx=0.5` too
(`0.002`: 82% at 100 m, 59% at 260 m). If K = 1 washes, lower the hazy end from `0.004` to `0.0025`.
`volumetric_fog_sky_affect = 0.0` keeps the sky itself clear, so the thing to look for is a seam
where fogged far land meets the unfogged sky at the horizon.

### 4. Shafts can only come from shadow casters near the camera (predicted)
Shafts are the sun's shadow cut into the fog. The sun's shadow reaches 80 m at High
(`Settings.apply_sun_quality`; `orbit_day.gd:65` sets 120), but the fog runs to 260 m. Past the
shadow distance the fog is lit without shadow, so it adds a flat veil and no shafts. Expect
shafts only from buildings, trees and junk piles within about 80 m, and only looking toward the sun:
anisotropy 0.75 throws nearly all scatter forward, with `light_volumetric_fog_energy` up to 2.2 on
a sun of 2.7. Looking away from the sun (the default view may) the fog will be nearly invisible.
Suggested if shafts are weak or the sun halo clips: `volumetric_fog_length` 140 (matches the
shadow range better and gives the froxel grid finer depth slices), anisotropy 0.6, sun volumetric
energy 1.5 at low sun, and keep the density constant by fog length when comparing.

### 5. Night (predicted)
The moon scatters at 0.4 with `ambient_inject` 0.15 while night exposure is 1.55, so the fog will
lift the blacks into a blue-grey veil, and the moon's shadow only reaches 50 m. Suggested at night:
moon volumetric energy 0.15, ambient inject 0.05, or fade the volumetric density by `day`.

### 6. Things to watch for in the frames
- Temporal noise or ghost trails in the fog on the boost walk (High uses TAA and the fog reprojects).
- Banding in the fog toward the sun (the froxel grid is coarse over 260 m).
- Reflection drop-out at screen edges once puddles exist (`ssr_fade_in` 0.15 is short; try 0.3).
- `--look-fx` never turns reflections off again in the same run; harmless for these captures.
