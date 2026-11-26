# `--look-fx`: code read-through before the Mac review

**This is not the Mac review.** It was written in a cloud container with no GPU. No frame was
captured and no frame rate was measured. Everything below comes from reading the code at
`21532a4c` (branch `claude/practical-meitner-eipd0h`) and from arithmetic; each point says what
the Mac run should confirm. The Mac report goes in `LOOKFX.md` next to this file.

Software Vulkan (lavapipe) was tried once here to see the Forward+ effects. It started in
Forward+ but never produced a frame in ten minutes, as CLAUDE.md warns, so it was stopped.

## Findings, most important first

### 1. The puddles are not in the branch
The review brief says the wetness and puddles are in `planet/sphere/sphere_ground.gdshader`
(uniform `wetness`, marked `[art3]`). At `21532a4c` that shader has no `wetness` uniform and no
`[art3]` mark; the only `[art3]` in the repository is the fog and reflection block in
`planet/sky_director.gd`. The ground's last change is art stage 1 (`ebb15192`).
If the puddle work exists, it has not been pushed. The Mac review cannot judge puddles until it is.

### 2. Screen-space reflections will show almost nothing on the ground as it is
`sphere_ground.gdshader:178-179` sets roughness 0.95 on dry ground, 0.6 on wet banks and 1.0 on
open water, with specular 0 on water. Screen-space reflections only appear on smooth surfaces
and fade out as roughness rises, so on this ground the flag pays for reflections and draws
none. To confirm on the Mac: the `--look-fx` frames should show no ground reflections at all.

Two things follow for the puddle work:
- Puddles need roughness about 0.05 to 0.15 and specular about 0.5 inside a noise mask, not on
  the whole bank. The comment on line 178 records that a glossy whole bank (0.12) "mirrored the
  sky as a white strip", so the mask and a cap on brightness matter.
- The sky in a puddle does not come from screen-space reflections: they can only reflect what
  is on screen and in the depth buffer, and the sky is not. It comes from the sky's radiance
  map, which works without the flag and on every renderer. Screen-space reflections would add
  only Lumi, junk and buildings standing next to a puddle. If that is not worth its cost on
  the Mac, drop it and keep the puddles.

### 3. The fog is not thin once it is added to the depth fog
Transmittance over a distance d is about exp(-density x d). At the end of the 260 m fog volume:

| haze | K | volumetric density | volumetric alone | with depth fog (0.0005 to 0.0014) |
|---|---|---|---|---|
| clear (0) | 1 | 0.0012 | 73% | 64% |
| clear (0) | 2 | 0.0024 | 54% | 47% |
| dusty Act 1 (1) | 1 | 0.004 | 35% | 25% |
| dusty Act 1 (1) | 2 | 0.008 | 12% | 9% |

In the dusty opening, K=1 already hides three quarters of land at 260 m and K=2 is a wall.
This is the old "fog washes the scene grey" complaint waiting to happen. Suggested start:
`lerpf(0.0006, 0.002, haze)`, and compare `--look-fx=0.5` against `--look-fx` on the Mac.

### 4. A seam at the horizon is likely
`volumetric_fog_sky_affect = 0.0` keeps the sky clear (right, given the owner's complaint) while
land at 260 m is 25 to 65% fog colour. Far land will meet an untouched sky. The depth fog avoids
this because the sky shader paints its horizon band in the same colour (`fog_col`); the
volumetric albedo is a different colour. Suggested: tint the albedo toward `env.fog_light_color`,
or lower the density as in finding 3 so the difference is small. Look for it in the noon frames.

### 5. Shafts will be strong toward the sun and nearly absent away from it
Anisotropy 0.75 scatters about 28 times more light straight toward the camera when it looks at
the sun than even scattering does, and about 12 times less when it looks away. With the sun's
fog energy at 2.2 when low, expect a white bloom around the sun in the frames facing it and no
visible shafts in the default view if that faces away. Suggested start: anisotropy 0.55, low-sun
energy 1.4 (keep 0.6 for a high sun).

### 6. Shafts stop where the sun's shadows stop
The fog volume is 260 m long; the sun's shadow distance is 120 to 150 m
(`planet/orbit/orbit_day.gd:65`, `planet/sphere/sphere_demo.gd:294`). Beyond that the fog is lit
with no shadow in it, so the far half of the volume is an even glow that lowers contrast and
cannot show shafts. Suggested: `volumetric_fog_length` 160.

### 7. Night
`volumetric_fog_ambient_inject = 0.15` under the night exposure of 1.55 may lift the dark side to
grey; the moon at 0.4 is probably harmless. Check the night frames for a flat grey veil over
land and compare with the frame without the flag. Suggested if it shows: ambient inject 0.05.

### 8. Motion
Volumetric fog reuses earlier frames to hide noise. In the boost walk, watch for shafts that
trail behind trees and buildings, and for flicker in thin trunks' shafts.

## Values to try on the Mac

| setting | now | try |
|---|---|---|
| `volumetric_fog_density` | `lerpf(0.0012, 0.004, haze)` | `lerpf(0.0006, 0.002, haze)` |
| `volumetric_fog_anisotropy` | 0.75 | 0.55 |
| `sun.light_volumetric_fog_energy` | `lerpf(0.6, 2.2, low_sun)` | `lerpf(0.6, 1.4, low_sun)` |
| `volumetric_fog_length` | 260 | 160 |
| `volumetric_fog_ambient_inject` | 0.15 | 0.05 |
| `ssr_max_steps` | 48 | 32, or reflections off if puddles read without them |
| puddle roughness / specular | not present | 0.05 to 0.15 / 0.5, noise-masked |
