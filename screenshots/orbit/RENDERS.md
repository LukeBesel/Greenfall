# Orbit renders

Lap run first: `[orbit] LAP walked=11579m around=11564m game_time=2545s (42.4 min) closest_to_start=0.11m PASS`
(the trail is in `lap_trail_v2.json`, used by `--orbit-trail`).

Two sets: `*.png` = QUALITY=0 at 960x540, `*_q2.png` = QUALITY=2 at 1280x720 (tools/shot.sh, Vulkan/lavapipe under xvfb).

- `orbit_mid` / `orbit_mid_q2`: the whole globe from orbit as a **big-hex map**. Each of the 10,242 level-5 hexes
  (~16 ground hexes each) is coloured by its share of junk (biome palette: rust, sand, marsh olive, neon violet,
  frost), cleaned soil (pale), green (planted -> restored) and water (blue), so it changes as crews clean and plant.
  Cities are slate-blue clusters with amber outlines and labels (Lumen Pier, Stillwater, Old Town); hubs are cyan
  "hub" labels and HOME. Atmosphere rim; the cyan pole-to-pole line is the walked lap. presim 600 min.
- `orbit_command` / `orbit_command_q2`: Command view at 380 m over the home hub: coastline, fine hex texture,
  base blocks. presim 90 min.
- `orbit_play` / `orbit_play_q2`: follow camera behind Lumi on the start plaza (brick and concrete blocks, lamp,
  home beacon, junk field).
- `orbit_ground` / `orbit_ground_q2`: lower ground-level view of the same plaza.

Issues found and fixed in this pass:
- Command view was a flat grey haze, and at QUALITY=2 every view (even the globe) was buried in brown fog:
  `Settings.apply_quality_to_tree` overwrote the orbit's fog with the flat-district density and turned on
  volumetric fog. verdance_globe now re-applies its own fog and keeps volumetric fog off.
- `orbit_play` needed DELAY=120 (150 at QUALITY=2): at DELAY=45 it was still on the "Warming up" loading screen.

Still open:
- The sky is black in the play/ground views (the PhysicalSky does not show).
- Some start-base blocks stand in the lake west of the home hub (visible in Command view).
