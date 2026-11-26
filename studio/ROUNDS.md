# Rounds (ledger)

## Round 1-2, 26 Nov: light, tone and atmosphere (stage 1)
New this round: the fill light is the sky's own radiance map with the ground's bounce painted into
its lower half (04 "bounce, not ambient"); one hero light; the night water mirrors the lifted night sky.
- planet/sky_director.gd `_apply_sphere`: sun 2.2 -> 2.7, companion (unshadowed) 0.75 -> 0.33, ambient
  1.1 flat-heavy -> 1.0 with sky share 0.85 by day, exposure day 1.25 -> 0.98 (+22% at low sun), fog
  0.0017 -> 0.0014 and a little darker, moon 0.38 -> 0.5, night fog bluer and lighter.
- planet/orbit/orbit_sky.gdshader: blue dome above a low dust band, round stars of mixed size and
  colour, moon halo, moonlit cloud edges, `ground_bounce` in the cubemap pass.
- sphere_water.gdshader / sphere_ground.gdshader: night sky reflection without the extra 0.25, a
  moon path, skylight scatter floor.
- story/waypoint.gd (owner, mid-run): 4 slim chevrons 3.2 m apart at 0.8 m/s (7 solid, 2.2 m, 1.4 m/s),
  beam breathing 7% at 0.19 Hz (15% at 0.35 Hz), ring pulse every 3.3 s (1.8 s); objective hex beat 0.6 Hz (0.9).
Measured (tools/frame_stats.py, 8-bit luminance; before -> r2):
  lake_night crushed 5.75% -> 1.72%, far band 13.9 -> 36.6 · yard_noon mean 171.7 -> 150.4, p5 83 -> 50
  lake_day mean 156 -> 134, saturation 0.28 -> 0.33 · clipped under 0.1% everywhere.
Measured (headless): load 11.8 s / 11.8 s, frames over 30 ms in the boost walk 5 / 6 (base / after).
Eyeballed: dusk shade is strongly blue; the noon pad is still a pale flat slab (material, stage 4).
Not checked: Forward+/Metal, High preset (SSAO, glow, 4 shadow splits), 60 fps.

## 26 Nov, later: helpers, Lumi v2, bases
- Lumi: hero v2 merged (7db3f787). Round-1 outline overlap with the concept turnaround 0.45-0.54
  (tools/hero/overlay.py, docs/art/lumi_overlay_r1.jpg): torso and pod too wide, head too flat, arms
  raised, eye rings thick. A helper is matching it part by part.
- World target art/concept/world_target.jpg (BARS.md). Wet ground in sphere_ground.gdshader (hardly
  visible from the start pad), opt-in --look-fx (volumetric fog, SSR) for Forward+, unseen so far.
- Bases merged (helper branch worktree-agent-a705c6a3ad429aae1): the pad is a wet concrete quay
  (art/models/outpost, planet/sites/outpost_pad.gd), bench, bin, lamps aged; kit "repaired" state more
  worn everywhere. Ground band at noon 171 -> 103 (bin view); target picture 70. Open: night crush
  2% on the built yard (bar 0.5%), lean-to/generator/Bot Bay/tower only recoloured, far bases.
- Running: buildings, shuttle, worker robots, regrowth, junk, Lumi match. Machine limits in
  studio/HELPER_BRIEF.md (one headless run at a time, time limits).
