# Handover: sphere-move (wt/smove)

Movement on a round, true-scale planet: Lumi, the camera, robots and junk. Everything is in
`planet/sphere/` and started standalone, using a stand-in sphere through SphereSurface. It is now the
game's movement: the slice builds on it through `scenes/slice_orbit.gd` and
`planet/orbit/orbit_planet.gd` (the `--orbit` switch and `planet/orbit/verdance_globe.gd` are gone).

## Done (all verified)
- `tests/test_sphere_move.gd`: 11 tests, all passing.
  - Boosted lap over both poles with the camera at R 200: back within 0.40 m. Body ortho error 1e-7, camera roll 0, camera up is the local up.
  - Walking lap at R 60: back within 0.006 m.
  - Walking off the exact pole in 8 headings: straight, no NaN.
  - Jump and land once.
  - Boost ramps to x4 and back.
  - A 63-degree mound can't be climbed.
  - A bot makes a 220 m trip, and two head-on bots pass at 1.3 m or more.
  - The crew sim travels the exact distance.
  - A* on GeoSphere(4) works, including with blocked cells.
  - Placement is orthonormal and on the ground. The curved scoop cone takes pieces ahead and rejects pieces behind. The magnet pull stays on the ground.
- Demo `--sphere-walk[=boost|play]` (removed with its hook in `scenes/slice.gd`; results kept as a record) on a true-scale planet, R 1840 m:
  - Headless boost lap: **PASS**, 11.56 km, closest approach to the start 0.46 m.
  - 470 junk pieces scooped along the way.
  - Bots stream out to SphereCrewSim records and back in.
- Checks: `tools/run_tests.sh`: 498/498 pass. The save roundtrip shows 188 PASS and no FAIL. A headless autoplay run (120 s) shows no SCRIPT ERROR.
- Not done: the gated renders. The render gate was busy with other helpers when the handover came, so `screenshots/sphere/` is still empty.

## Next
1. Renders, gated, then copied to `/home/user/Greenfall/screenshots/sphere/`. Wrapper: copy `scratchpad/shoot_main.sh` and point its cd at this worktree.
   - walk: `--sphere-walk --sphere-cam=8,-0.22`, QUALITY=1, RES=1280x720, DELAY=70
   - pole: `--sphere-walk --sphere-start=pole --sphere-view=command --sphere-cmd-h=200`
   - horizon: `--sphere-walk --sphere-scene=horizon --sphere-cam=7,-0.12`
2. Patch.gd adopts SphereMotor behind a flag. This waits for rollout approval.
   - Scope: in `Patch._move`, `if sphere_motor: sphere_motor.step(self, cam.frame.x*mv.x + cam.frame.z*mv.z, delta, boost, jump)`.
   - Then: `motion_mode = FLOATING`, the collision box lifted 0.25 m, and the y < -30 safety net replaced by `altitude() < -2`.
   - Then the flat-ground assumptions. `scoop_origin` and `forward` use `Vector3(0, 0.2, 0)`: use `up()`. The magnet arm sets `to_me.y = 0`: use `SpherePlace.pull_along`. The cube spawn, the stack and `place_top_cube` all use world +Y: use local up. `find_scoop_target` should take `up()`.
   - The HexField lookups become SphereGrid's `cell_at`.
3. Adapt SphereSurface to sphere-grid: height_fn = SphereTerrain.height, cell_fn and center_fn from SphereGrid. The lead already wires these in verdance_globe.gd.
4. Robots on terrain meshes: SphereBot is analytic, using `surface.ground`. If terrain props block paths, feed them to `SphereSwarm.obstacles`, or add `passable` to `SpherePath.astar`.

## API (short)
- **SphereSurface(R, center)**: up_at, ground(dir), altitude(p), project, ground_normal(dir), cell_at, cell_dir, arc_dist. Plug-ins: height_fn(dir), cell_fn(p, hint), center_fn(cell).
- **SphereMath**: tangent, tangent_dir, basis_from_up_fwd, transport / transport_vec (parallel transport), advance (exact great-circle step), step_toward, slerp_safe, damp, ortho_error.
- **SphereMotor**: step(body, wish, delta, boost, jump), place, face, speed_ratio. Fields: hv, vv, fwd, grounded, boost_t, distance, ground_normal, altitude. Signals: landed(impact), jumped.
- **SphereWalker** (CharacterBody3D + PatchModel): up(), face(fwd), place(pos, fwd), distance, input, cam, scoop_fn(walker, delta), motor.
- **SphereInput** (PlayerInput + boost_held / jump_pressed; it registers `boost` Shift/LT and `jump` F/L3 if they are missing) and **SphereAutoInput** (dev and tests).
- **SphereCam**: target, surface, frame (x right, y up, z back). view "follow" | "command", plus pitch, distance and command_height. Methods: add_yaw, reset_frame, snap, update_camera(delta), horizon_roll.
- **SphereBot**: setup, add_visual, go_to_point, go_via, has_goal, to_record / from_record. Signals: arrived, cell_done. Graph hooks: claim_dirty, path, work_cell, junk_left, release.
- **SphereSwarm** (bucketed neighbours + static obstacles), **SphereSteer** (seek, separation, avoid with keep-right, turn, arrive), **SphereCrewSim** (advance(rec, dt, R), demote, promote), **SpherePath.astar(grid, a, b, passable)**.
- **SpherePlace**: align, on_surface, random_on_surface, random_in_cap, local_xyz, in_scoop, find_scoop_target, pull_along, beam_arc.

## Tuning decisions
- No lat/lon and no Euler angles anywhere. Bases are rebuilt every step from (radial up, transported forward), so the poles behave like anywhere else. Avoid Godot `Vector3.slerp` on near-identical vectors: it logs axis errors. Use `SphereMath.slerp_safe`.
- Horizontal feel is Patch's: ACCEL 16, DECEL 22, TURN 9, GRAVITY 20, 4.6 m/s.
- Hover: ride height 0, so the model looks the same as today (PatchModel already bobs). Spring k 160, critically damped. The collision box is lifted 0.25 m and touches only walls and props. The ground is the larger of the analytic height and a mask-1 ray.
- Boost: x4 (18.4 m/s) with a 0.8 s smoothstep ramp. It lifts Lumi 0.35 m, and the camera pulls back 45%, gains +12 FOV and swings behind. Jump: 6.5 m/s, air control 0.35. Max climbable slope: 42 degrees.
- Camera: the frame is transported, then re-orthonormalised around the exact up, and look_at uses the local up, so the horizon is level by construction. Focus damping is 14/s and lag is clamped to 2.5 m. Command view sits 70 m up (zoom 30..400) with a 0.35 rad tilt; screen-up is the frame's forward.
- Owner: true scale, with no curvature exaggeration. The curve reads at the horizon (about 105 m away from a 3 m camera at R 1840) and in Command view.
- Far-bot streaming in the demo: demoted past 320 m, promoted inside 260 m (hysteresis).
