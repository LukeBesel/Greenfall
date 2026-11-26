# Art baseline and the art guard

The art overhaul (lighting and tone, Lumi's model and animation, buildings and the start town, the
bases, the shuttle, the worker robots, regrowth) arrives from its own branch in stages. Before each
stage is merged, `tools/art_guard.sh` proves the new art did not break the game, against numbers
measured on main before the overhaul (`docs/art_baseline.json`). It checks breakage, not taste:
look at the frames for that.

## Running it

| Command | What |
|---|---|
| `tools/art_guard.sh` | every check, compared with the baseline; exit 1 on any FAIL |
| `tools/art_guard.sh --quick` | the file census and the world check only (about 10 s of checks once the globe is up) |
| `ART_GUARD_RENDER=1 tools/art_guard.sh` | also renders 4 fixed views by day, 3 at dusk and 3 at night (draw calls, primitives, texture memory, frames in `screenshots/art_guard/view_*.png`) |
| `tools/art_guard.sh --fault=NAME` | plants one world fault and must FAIL (proof the check works) |
| `python3 tools/art_guard.py self-test` | plants every file-side and numbers-side fault on a tiny tree and synthetic numbers (also run first by art_guard.sh) |
| `tools/art_guard.sh --write-baseline` | stores the current numbers as the baseline (main only, after a merge is accepted) |

Headless runs: the world check (`--art-guard`), `--city-walk`, `--site-reach`, `--target-reach
--target-reach-hubs=3` and the perf walk (`--load-report --hitch --orbit-spawn=0,-260
--orbit-walk=boost --quit-after=75`) run side by side; each is one globe build (2-4 min on a quiet
box; on a busy box the `godot` wrapper queues them, so the whole guard can take 20-40 min). Logs and
numbers: `screenshots/art_guard/`. Every line it prints starts `[artguard] PASS|WARN|FAIL area:`.

It is not in `tools/check_exit.sh`: it is five globe builds, and its baseline is meant to move
with each accepted art stage. Main runs it on each art merge (below).

## What fails

| Area | FAIL when | Where |
|---|---|---|
| collider | a visible solid prop in the start yard or town (site-local, 142 m round the pad) with nothing solid in Lumi's body band (0.2-1.2 m), or a solid collider there with nothing visible along its outline, that the baseline did not have (matched by owner and spot within 2.5 m; `allow.passable` / `allow.invisible` in the JSON list owners meant to be so) | tools/art_guard.gd `_mesh_collider_audit` |
| walk | `--city-walk` fails, or the start town's free or reached area moves more than 4%, more shut-in pockets, junk unreachable, a way out of town closed | city_walk.log |
| reach | `--site-reach` fails, an anchor cut off, a hub's walkable area moves more than 6% | site_reach.log |
| targets | `--target-reach` fails (first 3 hubs), or fewer targets than the baseline | target_reach.log |
| perf | load (`[loader] ready in`) over baseline +35% and +4 s, longest load frame +50% and +400 ms, hitches (frames over 30 ms CPU on the walk) +50% and +6 | perf.log |
| render | draw calls or primitives at a fixed view +40%, texture memory +40% (rendered runs only) | render.log |
| model | a .glb/.gltf in art/ over 120k triangles (unless already so), +50% and +3000 over its baseline, primitives with no material, LODs lost (`meshes/generate_lods`), a new model over 2000 triangles without LODs, an embedded image over 2048 px, animations gone, its .import not committed | tools/art_guard.py |
| texture | a new texture without `compress/mode=2` or a new normal map (`_nor_gl_`) without `compress/normal_map=1` (CLAUDE.md Assets), an old one's compression turned off, a missing or uncommitted .import, over 2048 px | tools/art_guard.py |
| builder | a procedural build over budget (Lumi 150k, a robot 30k, other 200k triangles) or +50% and +3000 over baseline, a visible surface with no material (default white), a build that no longer builds. Builds: Lumi in 6 designs, 6 robot kinds x 4 looks, 9 kit buildings x 3 states, the ship Mk I/IV/VII | `_builders` |
| materials | more visible surfaces with no material in the start area than the baseline | `_mesh_collider_audit` |
| rig | a member, node name or animation that player/patch.gd, lumi_style_rig.gd, photo_poser.gd, pickup_fx.gd, carry_point.gd, story/intro.gd, space_stage.gd, systems/lumi_style.gd or the Locker / builder UI use on Lumi's model (read from the sources each run) is missing on a built PatchModel; Lumi in the world is not a PatchModel | `contract()`, `_rig` |
| locker | a Character Builder choice (each colour slot, eye shape, head, chest, shoulders, held item, companion, pattern, wear) that changed Lumi's look (a hash of his visible meshes, materials, shader values and style metas) no longer does; fewer choices | `_locker` |
| film | a shot of data/intro_shots.json without `_in_`/`_run_` code, a cue without `_cue_`, a line without text, a camera anchor the start site lacks, a node the film looks up by name (Hatch, Scorch, SeedTray, Beacon, Plume, GlimStuck, PodLight, ...) gone from the ark, the pods or the crash site, the space stage missing its ark / pod / vault pod / Lumi | `_film` |
| world | the world run did not finish, a SCRIPT ERROR, a resource that failed to load | world.log |

WARN (listed for main, not a fault): the collider census changed (count / layout hash of the solid
shapes, yard and town apart: new buildings change it), lighting / sky / water settings changed
(environment, both suns, the sky shader's and the lake shader's parameters: the art pass changes
these first), a model removed, materials renamed, Blender default material names.

## Planted faults (each must FAIL; clean main must PASS)

`--fault=walkthrough` (a 1 m crate with no collider by the bench), `invisible` (a 3 m box collider
with nothing over it), `white` (a mesh with no material), `rig` (a member the code would call that the
model lacks), `locker` (the eye colour slot stops applying), `film` (a cue with no method), `tris`
(Lumi three times heavier). File side and numbers side: `python3 tools/art_guard.py self-test`
(31 cases). On main 72648c6 (26 Nov): `tools/art_guard.sh --fault=all` plants all seven in one
world run and each is caught (`[artguard] planted fault X: caught`); the self-test passes 31/31; the
clean guard on main passes 16/16 with no WARN.

## On each art drop (main)

1. `git fetch origin claude/practical-meitner-eipd0h`, merge it into a scratch branch.
2. `godot --headless --import --path .`, then `tools/art_guard.sh` (and `ART_GUARD_RENDER=1` for
   the frames); read every FAIL; WARN lines list what changed on purpose.
3. GUT, `--walk-opening`, the save round trip and `tools/check_intro.sh --quick` as usual.
4. Look at `screenshots/art_guard/view_*.png` before and after (broken things: holes, floating or
   sunken buildings, black or white surfaces, Lumi missing parts, unlit night).
5. Accepted: `tools/art_guard.sh --write-baseline` on main, commit `docs/art_baseline.json`.

## The baseline (main 72648c6, 26 Nov)

Every number here is measured in the cloud container: **software GL here** (Mesa llvmpipe, Compatibility renderer, Low preset, 960x540) or headless (no renderer). None is real hardware; frame rates here mean nothing. The full set is `docs/art_baseline.json`.

| What | Baseline | Measured how |
|---|---|---|
| Load to play (`[loader] ready`) | 11236 ms, longest load frame 128 ms | headless, `--load-report`, software box (noisy: 11-16 s seen the same day) |
| Hitches on a 75 s boost walk | 6 frames over 30 ms CPU of 8438, worst 43 ms | headless `--hitch --orbit-spawn=0,-260 --orbit-walk=boost` |
| Start town walkable | 70674 m2 free, 70674 m2 reached from the pad, ways out: every side, 0 shut-in pockets | headless `--city-walk` |
| Hub sites | 15500, 15500, 11939, 10761, 11112, 10363, 11400, 11068, 11055, 13293 m2 walkable (hubs 0-9), every anchor reachable | headless `--site-reach` |
| Targets (hubs 0-2) | 1368 targets, 0 unreachable | headless `--target-reach --target-reach-hubs=3` |
| Solid shapes in the start area | yard (r<32 m) 41, town 590 | headless `--art-guard` |
| Mesh/collider leaks on main (allowed as baseline) | 15 walk-through spots, 31 invisible walls | the same |
| Default-white surfaces in the start area | 0 | the same |
| Lumi (procedural + aurora.glb parts) | 96222 triangles (aurora) .. 106404 (bolt) | headless census of visible meshes |
| Worker robots | 2322 .. 7268 triangles (24 builds) | the same |
| Kit buildings | 45758 .. 130098 triangles (27 builds) | the same |
| The ship Mk I / IV / VII | 14876 / 19404 / 31970 triangles | the same |
| art/ | 430 MB, 123 models (3605455 triangles), 514 textures (108 VRAM-compressed), est. texture memory 2761 MB | `tools/art_guard.py static` |
| Rig contract | 55 members / node names the code uses on Lumi, all present | sources read each run |
| Locker | 33 choices tried; colour side and held holo change nothing on main | fingerprint of Lumi's look |
| Opening film | 21 shots; nodes looked up and present: Beacon, GlimStuck, Hatch, HoverGlow, HoverLight, Plume, PodLight, Scorch, SeedTray, Spill | |

Fixed views, **software GL here** (draw calls / primitives per frame; texture memory 1303 MB, video memory 1603 MB in every view):

| View | Draw calls | Objects | Primitives |
|---|---|---|---|
| lumi | 957 | 1014 | 3.06M |
| yard | 1038 | 1098 | 3.38M |
| town | 643 | 692 | 2.41M |
| street | 970 | 1042 | 3.53M |
| dusk_lumi | 732 | 793 | 2.57M |
| dusk_yard | 793 | 857 | 2.87M |
| dusk_town | 654 | 710 | 2.41M |
| night_lumi | 713 | 777 | 2.53M |
| night_yard | 791 | 859 | 2.87M |
| night_town | 654 | 712 | 2.41M |

Lighting at the new game's morning (headless): tonemap 4, exposure 1.25, ambient f7e5c7ff x 1.1, fog True (density 0.0017), adjustment contrast 1.1 saturation 1.24; sun ffe8c6ff x 2.2; the sky shader's 31 and the lake shader's 8 parameters are in the JSON (`world.look`).
Reference frames: `docs/art/baseline_views.jpg` (one sheet). Full size: `ART_GUARD_RENDER=1 tools/art_guard.sh` writes `screenshots/art_guard/view_*.png` (day: lumi, yard, town, street; dusk 0.77 and night 0.95: lumi, yard, town; all from one load).

Not measured: the exported game's size (disk on the box is too tight for an export); anything on real hardware.

## Wanted from the Mac (docs/art/mac/REPORT.md)

The only real-hardware evidence. At the High preset (and Low for the Deck-class number), Forward+/Metal, 1080p:
1. Frame rate (mean and 1% low over 20 s) at the guard's fixed views: Lumi close by day, the yard from above the bench, the town from 55 m, a street at eye height; and the yard and town at dusk (0.77) and night (0.95). The views are in tools/art_guard.gd `run_views` (`--art-guard-views=DIR` prints draw calls and memory for each).
2. Load time New Game to play (`--load-report`: `[loader] ready in N ms, longest frame M ms`), cold and warm.
3. Hitches on the boost walk (`--hitch --orbit-spawn=0,-260 --orbit-walk=boost --quit-after=75`, rendered, not headless): count over 30 ms and the worst.
4. GPU memory (`[artguard-view] ... vmem=`) and draw calls at the same views, so the software numbers here can be scaled.
5. The same five after each art stage, before and after, on the same build of Godot.
