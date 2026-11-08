# Orbit renders

Lap run first: `[orbit] LAP walked=11579m around=11564m game_time=2545s (42.4 min) closest_to_start=0.11m PASS`
(the trail is in `lap_trail_v2.json`, used by `--orbit-trail`).

## QUALITY=0, 960x540 (tools/shot.sh, Vulkan/lavapipe under xvfb)
- `orbit_play.png`: follow camera behind the robot on the plaza, with brick and concrete blocks, a lamp post, the beacon beam and a field of scrap. Needed DELAY=120: at DELAY=45 it was still on the "Warming up" loading screen (71%).
- `orbit_ground.png`: lower ground-level view of the same plaza scene (DELAY=45).
- `orbit_command.png`: top-down command view at 380 m. **Issue:** the whole frame is washed out by a flat grey haze, so the land and water shapes and the build grid are barely visible. A retry at DELAY=100 gave the identical image, so this is not a timing problem. It is likely fog or atmosphere density at that height.
- `orbit_mid.png`: the whole globe from orbit with land and water and the walked lap drawn as a pale cyan pole-to-pole line (DELAY=50, presim 600).

General: the sky is black in the play and ground views (no sky or atmosphere visible behind the buildings).

## Phase A (local, QUALITY=0, 640x360, `--orbit --orbit-nohud --orbit-time=0.4`)
- `orbit_phaseA_play.png`: the real Lumi on the start site with the Depot/trash bin, real junk models in the field, and the new world-space sky (no longer black). The grey-box buildings are phase-A stand-ins; the real city dressing comes with phase D.
