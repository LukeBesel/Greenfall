# Performance and Steam Deck

Targets, presets, how to measure, and what the draw-call pass changed.

## Targets

| Hardware | Resolution | Preset | Target |
|---|---|---|---|
| Steam Deck (LCD/OLED) | 1280x800 | Low (auto) or Medium | 30-40 fps, steady (40 Hz mode friendly) |
| Integrated GPU PC (Intel Iris Xe / UHD 7xx, Radeon 680M class) | 1920x1080 | Low (auto) | 30+ fps |
| Apple Silicon base chips (M1/M2/M3) | native, 3D at 75% above 1440p | Medium (auto) | 30+ fps |
| Intel Mac (Iris / UHD) | 1080p-class | Low (auto) | 30 fps |
| Mid discrete GPU (GTX 1060 / RX 580) | 1080p | Medium (auto) | 60 fps |
| RTX 20xx+ / RX 6000+ | 1080p-1440p | High (auto) | 60 fps |

Late game (a fully restored "future" district, base level 5) is the worst case; plan for it.

## Presets (autoload/Settings.gd `apply_render_quality`, `apply_sun_quality`)

| | Low | Medium | High | Ultra |
|---|---|---|---|---|
| SDFGI / SSIL | off | off | on | on |
| SSR | off | off | off | on |
| SSAO | off | on | on | on |
| Volumetric fog | off (plain fog) | on | on | on |
| Glow | off | on | on | on |
| Far DOF (camera) | off | off | on | on |
| AA | FXAA | MSAA 2x + FXAA | TAA | TAA |
| Sun shadows | 1 cascade, 35 m, 2k atlas, soft very low | 2 splits, 55 m, 4k | 4 splits, 80 m, 4k | 4 splits, 120 m, 8k |
| Mesh LOD threshold | 4.0 | 2.0 | 1.0 | 0.5 |
| Particles (bursts, rain) | 50% | 75% | 100% | 100% |
| Ground litter (150k instances) | lighter meshes, items to 45 m, paper to 80 m | items to 75 m | items to 75 m | items to 75 m |
| Junk pieces | 320-tri LODs | 500 | 700 | 700 |

Render scale (Graphics tab) renders 3D below native; below 100% it upscales with FSR 1 on
Forward+/Mobile. Litter and junk detail are chosen when a district loads (change the preset,
then travel or reload to see them).

Renderer: Forward+ everywhere (Metal on macOS, MoltenVK fallback, OpenGL 3 if no RD driver
works). Graphics > Renderer > "Light (Mobile)" writes `user://renderer_override.cfg` (wired
through `application/config/project_settings_override`) and uses Godot's Mobile renderer after
a restart; it always uses the Low look.

## Auto-detection (systems/quality_detect.gd, systems/quality_probe.gd)

On first launch (no saved quality in `user://settings.cfg`) `QualityDetect.pick()` reads the
adapter name and type (`RenderingServer.get_video_adapter_name/type`), OS and CPU
architecture, screen size and DPI, RAM, and the Steam Deck (`SteamDeck=1` env, "Custom GPU
0405/0932" APU names, or a 1280x800 Linux screen on an integrated GPU):

- software / virtual GPU or a non-Forward+ renderer: Low (75% render scale for software);
- Steam Deck: Low, interface scale 110%;
- macOS Apple Silicon: base chips Medium (Low + 75% scale above 2304x1440), Pro Medium, Max/Ultra High;
- macOS Intel: Low (integrated) or Medium (Radeon Pro);
- integrated GPU: Low (render scale 75% above 1920x1200, 67% above 1600p);
- discrete GPU: RTX / RX 6000+ / Arc A7 High, GTX / RX 400-500 / Vega Medium, unknown Medium;
- under 6 GB RAM: one step lower. Ultra is never picked automatically.

Small dense screens (Deck, or <= 900 px tall at >= 160 dpi) get interface scale 110%.

The first time the game scene runs with an auto-detected preset, `QualityProbe` waits 6 s for
shaders to settle, averages the frame rate over 6 s and steps the preset down one level while
it is under 45 fps (judged against 85% of the refresh rate on 30/40 Hz screens), with a toast;
then it never runs again. Settings > Graphics shows "Detected: Low for Steam Deck" (or the
hardware note once the player picks a preset). Any manual preset choice turns detection and
the probe off for good. Tool runs (any DevHooks flag) skip the probe unless `--probe`.

## How to measure

Frame rates in the cloud container (software Vulkan) mean nothing; draw calls, objects and
primitives do, and are what the tables below use. On real hardware use the same hooks.

- `--perf`: prints `[perf] t= frames= game_fps= draw_calls= objects= prims=` every 3 s
  (Godot `RenderingServer.get_rendering_info`, the in-frame totals across all passes).
- `--scene-stats[=S]` (headless works): `tools/scene_stats.gd` census per top-level node:
  visible geometry nodes, MultiMesh instances, surfaces, shadow casters, an estimated draw
  count and triangles. `STATS_SPLIT=City` breaks one group down by node name.
- Late game: `--future=5 --hub-level=5` (every hex Thriving, base level 5).
- Presets: `--quality=0..3`; Deck screen: `--resolution 1280x800`, `--ui-scale=1.1`.
- Controller / layout audit: `--pad-audit` (headless) opens every screen, checks focus
  reachability, that B closes and A presses, and that no panel is clipped by the screen
  (run with `--resolution 1280x800 --ui-scale=1.1` for the Deck); `--menu --pad-audit` does the title screen;
  add `--audit-shots=DIR` on a rendered run for a screenshot tour.
- Monitors in game on real hardware: Godot's debugger Monitors tab (Raster > Draw calls,
  Objects, Primitives; Time > FPS / Process) or `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)`.

Example (rendered, 1280x800, Low):

    xvfb-run -a -s "-screen 0 1280x800x24" godot --path . --rendering-driver vulkan --resolution 1280x800 \
      -- --fresh --quality=0 --perf --future=5 --hub-level=5 --quit-after=60

On a Deck: run from desktop mode with `-- --perf` (or set the launch options in Steam to
`%command% -- --perf`) and read the console, or use the Steam performance overlay.

## Draw-call pass (Nov 2026)

`art/mesh_batch.gd` (MeshBatch) batches static props without changing how they look:
`instance()` groups identical mesh + material + shadow setting into one MultiMesh (exact: same
object-space data per instance), `merge()` bakes parts sharing a material into one mesh with
normals, tangents, UVs and colours kept (exact for world-space and UV-mapped materials), both
split into ground cells so culling and visibility ranges still work.

- City (`planet/city_view.gd`): the 90 skyline towers (~700 nodes) are merged per material /
  instanced per prop; sidewalk tops, curbs and fences merge per 72 m cell; building bodies
  merge per 72 m cell (world-space shader); facade kit pieces are one MultiMesh per piece for
  the detail ring instead of per block; fire escapes and street props are instanced.
- Garden (`plants/garden.gd`): plants batch per 72 m cell and species instead of per hex and
  species (about 2 plants per draw before, each plant mesh having ~6 surfaces).
- Wildlife: all butterfly wings are one coloured MultiMesh (was 2 nodes and a material each).
- Field junk: MultiMeshes whose pieces are all scooped are hidden (late game they were empty
  draws). Litter: one shared material for every chunk; tiny items end at 75 m.

Low also drops triangles: ground litter and junk use lighter meshes, and tiny litter items stop
drawing at 45 m (Low) / 75 m (others).

### Results (1280x800, default spawn view, settled frames, Forward+ on lavapipe)

Numbers are `RenderingServer` in-frame totals (all passes: depth prepass, colour, shadow
cascades). Before = commit 3c86504, after = this branch. "Future" = `--future=5 --hub-level=5`.

| View | Preset | Draw calls before | after | change | Primitives before | after | change |
|---|---|---|---|---|---|---|---|
| Start (Old Town) | High | 3,245 | 2,939 | -9% | 29.8 M | 30.5 M | +2% |
| Start (Old Town) | Low | 1,742 | 1,586 | -9% | 23.4 M | 16.2 M | -31% |
| Late-game future city | High | 8,614 | 4,220 | -51% | 31.8 M | 25.6 M | -20% |
| Late-game future city | Low | 4,235 | 2,187 | -48% | 24.5 M | 13.9 M | -43% |

Headless census (`--scene-stats`, the whole scene, not frustum-culled): geometry nodes
2,351 -> 962 at the start and 3,058 -> 974 late game; estimated draws 7,389 -> 3,696 and
13,926 -> 4,257. The biggest late-game wins: garden plants (308 MultiMeshes -> 48), the city
(1,783 nodes -> ~460) and butterflies (332 nodes -> 1).

The start view at High is already dominated by unique shadow-casting geometry near the player
(the hub yard, shack, Lumi, junk heaps); the next candidates are outposts (~120 meshes) and
easter-egg props (~70). Frame rates in the container are meaningless (software Vulkan); check
the targets above on a Deck and an integrated-GPU laptop.

## Junk distance LOD (Nov 2026, [vqa2])

Frontier junk was the biggest frontier cost: 15-18k bulky pieces drawn with one mesh at every
distance, and a few models never got lighter at all (the 18k-triangle plastic crate's importer
LODs stall at 10,270 triangles, so the "lighter junk on Low/Medium" setting did nothing for it,
and it is ~10% of the pieces).

`planet/junk_lod.gd` (JunkLod) now owns FieldView's junk buffers. Each junk group (chunk x model)
has two MultiMeshes:

- NEAR: the mesh the game always drew (`model_mesh_lite` at 320/500/700 triangles by preset):
  the close-up look is unchanged.
- FAR: `JunkLod.far_mesh`: vertices welded by position (UV/normal seams no longer block the
  simplifier), then the importer's LOD generator, then vertex clustering if that still stalls:
  80/120/180/240 triangles by preset (the crate: 18,320 -> 124). Materials and the frontier
  weathering overlay are kept.
- A hex's pieces sit in NEAR while its centre is within 26/32/40/52 m of the camera (Low..Ultra,
  6 m hysteresis), else in FAR. Models whose near mesh stays heavy (> 3,000 triangles: the crate,
  the generator) switch closer, at 14/16/20/26 m, to a far mesh with 4x the budget.
- Instances are packed at the front of each buffer and drawn with `visible_instance_count`, so
  far, scooped or carried pieces cost nothing in the other buffer (a zero-scale instance is
  still vertex-shaded and counted). Transforms are kept on the CPU (no MultiMesh read-back).
- One distance per hex every 0.2 s; only hexes that cross a radius move their pieces. Overhead
  views go all-FAR on their own (the camera is far from every hex).

A/B and debugging: `--no-junk-lod` keeps everything on the near mesh (the old cost),
`--lod-debug` prints the flips, `--scene-stats` prints the near/far split. Tests:
`tests/test_junk_lod.gd`.

### Results

Rendered, 960x540 Medium, default spawn view, settled frames (`[perf]`, all passes), same build
with `--no-junk-lod` as "before":

| View | Primitives before | after | change | Draw calls before | after |
|---|---|---|---|---|---|
| Sunken City start | 97.6 M | 18.9 M | -81% | 2,028 | 2,217 |
| Frozen Port start | 131.1 M | 25.4 M | -81% | 1,674 | 2,149 |

Software-rendered frames per second in the container went from 0.12 to 0.75 in the Sunken City; on
real hardware use the targets above.

Headless census of junk triangles (`--scene-stats`, whole district, not frustum-culled):

| District | Preset | before | after |
|---|---|---|---|
| Sunken City | High | 23.4 M | 6.2 M (-73%) |
| Sunken City | Medium | 20.7 M | 3.6 M (-82%) |
| Frozen Port | High | 27.3 M | 6.8 M (-75%) |
| Frozen Port | Medium | 25.0 M | 4.1 M (-84%) |
| Old Town start | Low | 5.3 M | 1.2 M (-77%) |

Cost: the far buffers add draw calls (about +12% estimated draws in Old Town at Low, +250 to
+650 measured in the frontiers) because every visible group now draws in two pieces. Next
candidates: merge the far meshes' surfaces (wine bottles have 16, the stove 20) into one
vertex-coloured surface, and drop far-group shadows on Low where the shadow distance (35 m)
barely reaches past the near ring.

## Round planet (--orbit, orbE, Nov 8 2026)

Target: 60 fps on the owner's Mac on Medium. These numbers come from the cloud container
(4 cores shared with other helpers, load average 11-17, so CPU times are roughly 3x what one
free core gives) and from headless runs. Counts (triangles, instances, chunks) and the thread
build times are the robust part. Real Mac fps still needs a run on the Mac:
`godot --path . -- --orbit --orbit-walk --orbit-scoop --perf --quality=1` and read `[perf]`
and `[orbit-perf]`.

### Per-preset budgets (planet/orbit_quality.gd, `OrbitQuality`)

| | Low | Medium (Mac target) | High | Ultra |
|---|---|---|---|---|
| LOD 0 chunks (full detail, junk, future layer) | 180 m | 240 m | 280 m | 320 m |
| LOD 1 chunks | 520 m | 650 m | 760 m | 860 m |
| Far shell beyond | 1.7 km x size | 2.0 km x size | 2.3 km x size | 2.6 km x size |
| Chunk meshes applied per frame | 1 | 2 | 2 | 3 |
| Future layer range | 220 m | 320 m | 380 m | 420 m |
| Moon shadows | off | on | on | on |

"x size" = globe radius / 1,840 m, clamped 0.85..1.4 (planets differ in size; `GlobeSize`).
Medium keeps phase A's radii. Junk density is a design value (~70 pieces per 10 m hex) and is
not cut per preset; the junk ring is the streamer's 70 m near ring on every preset.

### Measured (headless, scoop walk with the Future Layer on 148 cells, 110 s; phase A globe scene)

`godot --headless --path . -- --fresh --orbit --orbit-walk --orbit-scoop --orbit-future=10 [--orbit-hex=13.5 | --orbit-level=8] --quit-after=110`

| Globe | Hexes | R | Ready (load) | Process ms avg (max) | Junk pieces drawn | Chunk tris (LOD 0/1 count) | Shell tris | Chunk build (worker) max | Chunk apply (main) max | Memory |
|---|---|---|---|---|---|---|---|---|---|---|
| Verdance (level 7, 10 m) | 163,842 | 1,840 m | 10.3 s | 9-23 (17-55) | 1,800-2,450 | 73-80k (6-7 / 12-14) | 61k | 308 ms | 9 ms | 597 MB |
| Anvil radius at the old 1.35x (level 7, 13.5 m hexes) | 163,842 | 2,485 m | 9.4 s | 10-11 (22-37) | 1,260-1,610 | 55-58k (4-5 / 9-10) | 61k | 100 ms | 14 ms | 596 MB |
| Anvil now (2.0x = level 8, 10 m) | 655,362 | 3,681 m | 9.1 s (grid cached; 32.6 s first time, planet 15.5 s) | 19-29 (45-68) | 4,340-4,760 | 106-109k (7 / 15-17) | 61k | 180 ms | 26 ms | 709 MB |

Planet sizes changed after these runs (main c56151f): Anvil is now 2.0x Verdance's radius,
R 3,681 m, 655,362 hexes, which is exactly the level-8 row. Per-frame costs follow the hexes
near the camera (10 m hexes on every planet), so frames cost about the same as Verdance's. The
junk drawn is higher on that row (4.3-4.8k pieces) because its near ring covers more cells.
Load time and memory scale with the whole planet (below).

### Load time on the globe (--orbit, the real slice)

`godot --headless --path . -- --fresh --orbit --orbit-planet=anvil --load-report --quit-after=30`
prints `[orbit-load]` with the build breakdown (planet, grid, field, streamer setup, settle,
preload wait) and the streamer stats.

| Step (Anvil, 655k hexes) | Before | After | What changed |
|---|---|---|---|
| Streamer settle | 6-14 s | ~0.8-1.1 s | `settle(near_only)`: only LOD-0 and collision chunks block; LOD-1 streams in during the first seconds (the far shell covers it). Most of the old settle was the near ring's junk loading 40+ models one by one on the main thread (7.3 s in `near_changed`). Those models now load on loader threads from the start of the build (`OrbitPreload`). |
| SphereField setup | 1.2-3.4 s | 0.1 s | Per-cell pass inlined over packed arrays (8 method calls per cell before). |
| Far shell setup | 2.0-3.2 s | 0.9 s | Fine-to-coarse cell map cached in `user://sphere_shell_map_<n>_<nc>.bin`; aggregation over local packed arrays with a fixed vote array. |
| Planet survey (PlanetData.generate) | 2-4 s | unchanged | Not touched (the survey generator); the next thing to thread. |
| **Slice built** | 14.5-28 s here (21.9 s reported) | **8.5-9.2 s** | Container at load average ~10 on 4 cores. Verdance: 6.5 s. |

All numbers are wall clock on a container running 2-3x oversubscribed (other helpers' builds
and renders), so an idle machine is faster. Expect Anvil under 8 s on the Mac. The flag
`--orbit-settle-all` restores the full settle (screenshots that want every LOD-1 chunk at
frame one); `--orbit-no-preload` turns the model preload off for A/B timing.

Systems added in this pass, measured in the same runs:
- Sky (SkyDirector sphere mode): one uniform update per frame. It asked SphereCells for the
  clean fraction every frame (an O(n) loop over 164k cells); now every 4 s.
- Future Layer on chunks: 2,737 pieces on 7-9 chunks. Builds are budgeted at 2.5 ms a frame
  (measured max 2.7 ms), about 19 ms spread per chunk, and a swap of 0.8 ms. A chunk rebuilds
  only when one of its cells changes level. Before that fix, every junk or near-flag write
  rebuilt chunks (a 138 ms frame).
- Survey hologram and PlanetGlobe overlay: the far shell's 10,242 big hexes (61k triangles),
  built when opened or re-surveyed (and every 4 s while the system map is open), never per frame.

### Where the frame goes, and what to cut first if the Mac misses 60
1. Chunk apply on the main thread (mesh and collision upload): 9-26 ms worst case. It's a hitch
   when a new LOD-0 chunk lands, not a steady cost. Low applies one per frame; next step:
   build the collision shape on the worker (SphereChunkJob) (orbB).
2. Junk instances in the near ring (1.8-2.5k on Verdance, 4.7k at level 8): SphereJunkView
   rebuilds take 2-8 ms. JunkLOD (impostors past ~40 m) is orbB's B2 item and the biggest
   remaining win.
3. Shadows: the sun (and the moon at night) are the only shadowed lights; Low turns the moon's
   shadow off. Glim's lantern is unshadowed below Medium (systems/glim/glim_bot.gd).
4. Sky shader: 4-octave cloud noise per sky pixel. If it shows up on the Mac GPU profiler,
   drop to 3 octaves on Low (`fbm` in planet/orbit/orbit_sky.gdshader).

### Perf pass 2 (Nov 8, headless only: the owner asked for no renders)

All numbers come from the real `--orbit` slice, headless, on the shared 4-core container
(load average 6-10). Headless doesn't render, so the frame numbers are CPU only. The GPU side
is estimated from the scene census (`--scene-stats`, before frustum culling).

**Build across frames.** The globe now builds behind the loading screen the way the flat
district does:
- `slice.gd` is `building` (disabled and not rendered) while it builds.
- The survey and terrain elevation run on a worker thread (`BuildBudget.add_task`/`join`).
- The globe steps, the start yard's city/kit/dressing and the chunk settle yield between steps
  (`settle_async`).
- SphereCells writes its state texture in one buffer pass (before: three per-pixel passes over
  every cell).

| | Longest frame before | Longest frame after | Slice built | Loader ready |
|---|---|---|---|---|
| Verdance (164k hexes) | ~15 s (orbB) / 6.6 s here | **0.66 s** (StreetDressing pole lamps) | 9.9 s | 11.6 s |
| Anvil (655k hexes) | 21.9 s build (reported) | **1.15 s** (its site builder, `AnvilSites.build`, is synchronous) | **5.1 s** | **7.7 s** |

The Anvil site would need `await BuildBudget.check()` inside p_anvil's builder to go below 1 s.
The flat game is unchanged: without a budget everything stays synchronous.

**CPU frame on the slice** (walking and scooping, all systems on):
- Anvil: **130-145 fps headless** on Low and Medium alike (about 7 ms a frame; physics runs at
  120 Hz).
- Per-system cost per physics tick: Lumi 0.5 ms, HUD 0.3-0.4 ms, sky 0.1 ms, camera 0.1 ms,
  streamer 0.07 ms, everything else under 0.05 ms.
- Fixed: the HUD recomputed the planet % over every hub-region cell each frame (3.5 ms on
  Anvil); it now refreshes 4x a second.

**Draw calls with the kit hubs** (census, start yard in view, Medium; estimated draws = surfaces
+ shadow surfaces):

| Group | Draws (est.) | Triangles | Note |
|---|---|---|---|
| Kit building bodies (`Body`) | 303 | 400k | 101 surfaces on 12 buildings, all shadowed: merging each building's surfaces by material is the biggest win (kit helper) |
| Loose site props | 305 | 124k | 64 single meshes: candidates for MultiMesh batching (orbD/yard) |
| Lumi (PatchModel) | 191 | 96k | 64 surfaces on 27 meshes, 63 shadowed: the hero model's own budget |
| Kit ground plates | 153 → **102** | 581k | shadows off now (8 cm plates) |
| Junk (near + far impostors) | ~250 | ~190k | far impostors don't cast shadows |
| Grit / tufts MultiMeshes | 68 | 195k | |
| **Total** | **1,691 → 1,640** (Verdance), 1,410 (Anvil) | 2.3-2.5 M | before frustum and distance culling |

**Reading for the Mac (Medium, 60 fps):** the CPU side has room: about 7 ms a frame on this
loaded box, Anvil included. The GPU side is the risk. ~1,600 draws (~1,000 after culling is a
fair guess) and ~2.4 M triangles in the scene are fine for Apple Silicon on Metal at 1080p, but
not with margin. First cuts, in order:
1. Merge kit building surfaces (-200 draws).
2. Batch the yard props (-150).
3. Give Lumi's model fewer shadow casters (-60).
4. Plates triangle count (581k).

A real `[perf]` run on the Mac is the check:
`godot --path . -- --orbit --quality=1 --perf --orbit-walk --orbit-scoop`.

### Perf pass 3 (Nov 8, headless): load frames under 1 s, batching

Same box and method as pass 2 (shared 4 cores, scene census for draws). Every change has an A/B
switch: `--no-kit-batch`, `--no-prop-batch`.

**1. No loading frame over 1 s.**
- Anvil's foundry yard builds in steps behind the loader (`AnvilSites.build_async`;
  `build()` is unchanged for previews and tests).
- The site's deferred reach audit gets a frame of its own: SiteReach flood-fills a 249x249 grid
  of physics queries (~0.7 s), and it used to land in the same frame as the next build slice.

| | Longest loading frame | Loader ready |
|---|---|---|
| Verdance | 0.53-0.59 s | 8.4-8.5 s |
| Anvil | 0.62 s (was 1.15 s) | 6.6-7.0 s |

**2. Kit buildings merged per material** (`planet/kit_batch.gd`): all of a site's KitBuilding
bodies become one mesh with one surface per material. Materials are shared and paint is baked
per vertex, so it looks the same.
- Verdance's yard: 101 body surfaces → 9 (≈303 → ≈27 est. draws).
- The hidden originals keep their lights, ground patches and collision.
- It re-merges after a state change (VerdanceSite.set_level), and Anvil sites merge at build.

**3. Static loose props batched** (`planet/prop_batch.gd`): the crash site's furrow clods and
shards and an Anvil site's loose pieces, about -21 to -24 surfaces each.
- Conservative: only auto-named, script-less, childless meshes merge. Anything found by name or
  animated stays separate.
- The escape pod (~90 meshes, ~300 draws) is not batched: its parts are looked up by metadata,
  animated and swapped per repair stage (story/escape_pod.gd). Batching it needs a pass by its
  owners: merge the static shell, keep the hatch, fins, lamps and condition layers apart.

**4. Lumi far away** (`planet/lumi_lod.gd`, globe only): past 30 m (Command view) the 27-mesh
rig, 62 surfaces almost all casting shadows (~190 draws), hands over to one merged proxy with 13
surfaces and no shadow (~26 draws). It uses the same materials, so glow and colours match, and
is rebuilt every 4 s while the camera is far.

| Estimated draws (census, start site, Medium) | Before | After |
|---|---|---|
| Verdance | 2,024 | **1,700** (-324) |
| Anvil | 1,997 | **1,856** (-141) |
| Lumi in Command view | ~190 | ~26 |

The census counts both Lumi's rig and its far proxy, so in either view the real number is ~26
or ~190 lower than the table. Still to do, by owner:
- The escape pod (above).
- The Anvil road barriers: 8 meshes, 487k triangles, a RetopoFlow export that needs a LOD.
- The far junk impostors (~100 draws).

### Perf pass 4 (Nov 8, headless): pod, landmarks, far impostors, site reach

Same method. A/B switches: `--no-pod-batch`, `--no-far-single` (plus the pass 3 ones).

**1. The escape pod batched** (`story/pod_batch.gd`): ~90 meshes become a few merged meshes.
- The static shell merges per material in the pod's own space, so it flies, leans and lands with
  the pod.
- Each repair-stage group that `EscapePod.set_condition` shows or hides as a unit (Patches,
  Planter, Bolts) merges inside itself.
- Untouched: anything looked up by name (Hatch and the door, Beacon, Scorch, HoverGlow/Light,
  PodLight, Spill, ReentryFire), anything held in the pod's metadata (canopy, porthole, damage
  kit), anything scripted or with an overlay.
- Shared materials keep the glitching seams, glyph and fin lamps animating.
- `tests/test_pod_batch.gd` checks every stage still swaps, the animation runs on each stage and
  unmerge restores. About -254 est. draws on both planets.

**2. Landmark LOD** (`SphereJunkView._build_landmark`): a landmark uses its own import LOD within
a triangle budget per preset (Low 3k, Medium 6k, High 12k, Ultra 24k).
- Anvil's concrete road barriers were a 61k-triangle RetopoFlow export each, 8 in view.
- Anvil scene: 3.19 M → 2.07 M triangles. Models under budget (the 4.5k covered car) are
  unchanged.

**3. Far junk impostors in one draw per model** (`planet/junk_far_single.gd`): the far band
kept every surface of a model (a crate of wine bottles: 16 draws). Its surfaces now merge into
one, each tinted with its material's average colour (albedo × texture average), under one shared
material. The near band is unchanged. -70 est. draws on Verdance.

**4. Site reach without long frames.** orbD's anchor fix (`SiteReach.fix_anchors`, which places
the yard's 16 machines on reachable ground since 61d8b61) took ~5 s in one frame on Anvil.
- `fix_anchors` and `audit` are now coroutines that yield behind the loading screen. They stay
  synchronous without a budget.
- The flood fill tests a rasterised disc mask instead of every disc per cell. Same result:
  `--site-reach` passes on all 5 planets, and the same anchors move.
- The loader waits for the start site's probe, so it never spills past the loading screen.

| | Longest loading frame | Loader ready |
|---|---|---|
| Verdance | **0.44 s** | 10.3 s |
| Anvil | **0.72 s** | 11.2 s |

Ready times went up a little: the yields add frames, and the box was loaded.

| Estimated draws (census, start site, Medium) | All batching off | All on |
|---|---|---|
| Verdance | 2,381 | **1,670** |
| Anvil | 2,262 | **1,734** |

Left over:
- A hub built later in play (no loading screen) still runs its reach audit in one go: the
  physics sweep is ~0.5-0.7 s, the flood fills are now cheap. Spreading it over frames in
  SiteManager's runtime builds is the next step (orbD).
- Lumi's rig near the camera (62 surfaces).

### Perf pass 5 (Nov 8, headless): no hitches in play

**A hub built in play** (SiteManager builds hubs as Lumi comes near, or on a rocket hop): its
reach audit and anchor fix now run on a gameplay frame budget (`SiteReach.play_budget`, ~4 ms of
work a frame; the loading screen keeps its own budget).
- Anvil hub 3 after a hop: spread over ~180 frames, a few seconds of the hub "constructing",
  instead of one 0.5-2 s frame.
- Same anchors, same result: `--site-reach` passes on all planets and `tests/test_hub_sites.gd`
  passes.

**Found while profiling (per-script timers over all 92 processing scripts, then removed):**
- The Album took a picture check every 3 s that walked every cell for the "thriving" share
  (~270 ms each time on Anvil: a hitch every 3 s). On the globe it now counts the tracked cells
  only (same result).
- Biggest steady script cost left: wildlife (`fauna/fauna.gd`), ~3.5 ms a frame headless (animal
  updates and MultiMesh writes). Worth a look by its owner: update far animals less often,
  write only the MultiMeshes that changed.
- `OrbitDev`'s `[orbit-perf] process_ms` reads 130-200 ms on the current slice while the real
  frame rate is 135-140 fps. Trust `--perf` (`game_fps`) instead.

**Final numbers (headless, shared 4-core box, load ~5):**

| | Verdance (164k hexes) | Anvil (655k hexes) |
|---|---|---|
| Frame rate, standing in the yard | 138-142 fps | 133-138 fps |
| Longest loading frame | 0.44 s | 0.72 s |
| Loader ready | ~10 s | ~11 s |
| Est. draws at the start site, Medium (batching on) | 1,670 | 1,734 |
| Scene triangles | 2.24 M | 2.07 M |
| Hub built in play | spread over frames | spread over frames (~180 frames) |

The Mac check: `godot --path . -- --orbit --quality=1 --perf` (and `--orbit-planet=anvil`), then
read `game_fps` and `draw_calls`.

### Perf pass 6 (Nov 10, v5load, headless): no long loading frames on Verdance

Measured again after the start town, hub towns, hinterland and waterfront went in. Same box
(4 shared cores, load average 5-9 from other helpers), so `--load-report` now also prints the main
thread's own CPU time (`/proc/thread-self/schedstat`): wall time on this box reads 2-3x long.

| Verdance, `--fresh --orbit --load-report` | Before (a86fb5b) | After |
|---|---|---|
| Longest loading frame (wall) | 1.2 s quiet box, 1.8-2.3 s busy box | 0.16-0.24 s busy box |
| Longest loading frame (main-thread CPU) | not measured | **115-127 ms** |
| Longest build slice (CPU) | 1,072 ms (orbit story) | 109-123 ms (town:flush) |
| Loader ready (same box, back to back) | 16.1-17.3 s | **13.1-14.0 s** |
| First live frame | 144 ms | 60-90 ms |

What changed:
- **Worker threads for pure data:** the grid cache read, the far shell (map, aggregate, mesh
  arrays; `SphereStreamer.build_shell_async`), the SphereField ledger and the cricket bed's
  synthesis join the survey on `BuildBudget.add_task`.
- **`data/orbit_preload.json`** (`OrbitPreload.warm`): every model, model part, texture and "lite"
  (simplified) mesh the build used to load or make on the main thread. Files load on the loader
  threads from the start of the build; one worker task meshes and simplifies them (mesh
  simplification is 50-150 ms a model and can't be split). The main thread first copies each
  model's surfaces (`AssetLib.snapshot`), because a worker thread reading a mesh back from the
  rendering server waits for the main thread's next flush (about one read a frame): without the
  copies the same task took 14 s longer in a rendered run than the old main-thread path. Refresh after changing what the build
  uses: `godot --headless --path . -- --fresh --orbit --record-preload --quit-after=30`. A stale
  list is safe: a missing model just loads where it is used.
- **The near ring's junk** fills in slices (`OrbitPlanet.refresh_junk_async`): cells materialize
  one per check, its near and far meshes are made on a worker, pieces seat 40 at a time, and the
  far meshes are all made before the first live frame (they used to build one per frame in play).
- **The settle loop** no longer spins on the main thread until its slice runs out; it yields
  whenever no chunk has landed.
- **Yields inside the long steps:** yard systems, hub frame hosts, easter eggs, extras, camp,
  yard models, nursery, the town's lots, detailed city blocks, street furniture and the street
  dressing's layer flushes. A `setup()` that a synchronous caller can't await counts itself in
  `BuildBudget.busy` and the build waits with `BuildBudget.idle()`.
- The deferred greenhouse build gets a frame of its own.

`BuildBudget.check` only yields once 45 ms of the slice are used, so a slice is 45 ms plus the
longest indivisible step. What is left on Verdance is all 60-110 ms: the waterfront piers, a kit
ground patch, one detailed building, the outposts plan. Anvil's own yard builder still has a
0.45 s slice (`anvil:yard`); Verdance was the brief.

Tools: `--load-report` prints `[budget] N ms (cpu M)` per long slice, `[lap]` lines for the
steps between yields, `[model]` for any blocking model or texture load, the models still loaded
on the main thread, and the longest frame by CPU time.

One rendered check (software GL, 960x540 Low, same box): the build took 20.6 s before and 18.0 s
after, over 440 frames instead of 203, longest build slice 4.1 s before and 0.2 s after. What is
left there is the frame in which the 3D scene first draws (the warm-up stage: 6.9 s in software
GL, all shader compiles and uploads at once). It needs a look on real hardware; spreading it
means showing the scene's materials in batches before the world is drawn.

### Perf pass 7 (Nov 10, v5load, headless): hitches in play

`--hitch[=ms]` (systems/hitch.gd, default 30) prints every frame whose main-thread CPU time is over
the limit, with what ran in it (`Hitch.mark` in the streamer, the junk ring, the hinterland, the
site manager, litter, water, fauna, the autosave), a summary every 20 s, and every 10 s a check
that each live piece of the near ring is in a draw buffer. Walks: `--orbit-walk=boost` from
`--orbit-spawn=x,z` (town 0,0; outskirts 0,-260; hinterland and lake 400,300 and -300,500); a
rocket hop: `--orbit-hop=1`.

| 75 s boost walk, frames over 30 ms (CPU) | Before | After |
|---|---|---|
| Start town (0,0) | 6, worst 100-200 ms | 1, worst 33 ms |
| Outskirts (0,-260) | 5-6, worst 68-83 ms | 0-1, worst 27-30 ms |
| Hinterland and lake (400,300) | 3-4, worst 43 ms | 1, worst 33 ms |
| Rocket hop, after the veil lifts | 1.33 s (hub systems), then 40-150 ms spawns | 31 ms |

What was found and changed:
- **A fifth of the near ring's junk was never drawn.** Cells whose pieces are laid a little later
  (the deferred fill) were marked shown while still empty, so their pieces never reached a draw
  buffer: after a short walk 376 of 1,698 live pieces were scoopable and solid but invisible.
  `SphereJunkView._queue_ring` now leaves a cell out until its pieces exist.
- **Laying a cell's pieces** was 12-40 ms in one frame every few metres. `SphereField.
  materialize_step` lays a cell (land or lake) across frames under the fill's 3 ms budget;
  `materialize()` is the same work in one call.
- **The ring's heaps and wrecks** are made when their cell's turn comes in the junk pump (2.5 ms a
  frame), not all at once when the ring moves (30-50 ms).
- **Junk and landmark meshes** for every model are made at load. A model first met while walking
  cost a lite mesh in that frame and a far mesh in the next (30-150 ms each).
- **Wildlife:** the 2.5 s replan runs a part a frame (it was 35-45 ms, 100-200 ms on the first
  frame); the animals' procedural meshes are built at load; the prop scan that birds and spawns
  use walked every MultiMesh instance in the world each time Lumi moved 30 m (30-150 ms) and
  now runs 1.5 ms a frame while the last scan keeps serving.
- **Hub systems** (wildlife, outposts, eggs, the Ledger, decor) were all built in the frame Lumi
  came within 220 m of another hub: 1.3 s, in the last seconds of a rocket hop's landing. A hop
  now switches them behind its veil; a walk-in builds one system a frame.
- **Autosave:** the file is written on a worker thread (`SaveManager.save_game(true, true)`), so
  the frame only gathers the state (24-26 ms on a new game, was 55-75 ms). Every other save is
  synchronous as before and waits for a write in flight.

Left: one animal spawn can still take about 30 ms (finding a free spot); a hub town building as
Lumi walks to it (not hops) keeps frames at 25-45 ms for about 3 s with a few 90-140 ms steps
(the play budget is 6 ms plus the longest step in the town builders); a walk-in hub switch is
five frames of 100-400 ms instead of one of 1.3 s.

### Perf pass 8 (Nov 10, v5load): draw cost with the towns, litter and lakes

Census (`--scene-stats=22`, headless, start site, whole scene, one shadow split counted). The
census now leaves out instances past their `visibility_range_end` from the camera (it used to
count them; `STATS_NO_RANGE=1` gives the old numbers) and names unnamed meshes by their parents
when a group is split (`STATS_SPLIT=Globe`). A/B switches: `--no-shadow-trim`,
`--no-litter-range`, `--water-ripple-far=100000`.

| Start site | Est. draws before | after | Shadow-casting surfaces | Triangles before | after |
|---|---|---|---|---|---|
| Medium | 4,206 | **3,794** (-10%) | 688 -> 564 (-18%) | 7.03 M | 6.54 M (-7%) |
| Low | 4,206 | **3,322** (-21%) | 688 -> 564 | 4.48 M | 3.85 M (-14%) |

Where the scene's draws are now (Medium): ground litter 1,248 (428 MultiMeshes: one per cell and
item kind, 3.1 M triangles), the start town about 1,400, the hub's outposts and eggs 543, Lumi
217, the crash site 164, the hinterland 144.

What changed:
- **Shadows off where none showed.** Facade kit pieces that lie flat on the wall (under 30 cm
  deep: windows, doors, panels, trims; the building body behind them casts), street props under
  12 cm tall (manhole covers), and the outposts' and easter eggs' paint lines, shards, thin plates
  and bits under 12 cm. 124 fewer shadow surfaces, each a draw per shadow split (Medium has two).
- **Litter distance by preset.** Tiny items (5-15 cm, about a pixel at 50 m) stop at 50 m on
  Medium (60 m before) and 35 m on Low; the paper carpet keeps 90 m on Medium, 60 m on Low.
  High and Ultra are unchanged.
- **Lake shader.** The wave numbers and speeds are constants (a division and a square root per
  wave per pixel before); the scum noise is skipped on clean water; the three shortest waves
  (1.3 m and under) and the value-noise chop fade out by `ripple_far` (Low 60 m, Medium 250 m,
  High and Ultra 400 m) and are not computed past it. Per pixel: 7 waves and 5 noise lookups (40
  hashes) before; past the fade 4 waves and 1-2 lookups (8-16 hashes). Checked with a rendered
  pair at Medium from the start town's shore (ripple_far 250 against 100000): no visible
  difference; the far band differs by under 1/255 on average.

Not done, and why: the outposts' ruin pieces (90 meshes) only merge to 75 surfaces because every
piece has its own worn-paint material, and merging breaks the scatter when an outpost is repaired.
The litter is the next real win: 428 MultiMeshes for one ring. One MultiMesh per item kind for
the whole ring would be about 12 draws, but every ring move would re-upload the buffer; a mesh
merged per cell would lose the per-piece sweep.

## Yard machines and hub landmarks (v6yard, Nov 11 2026)

Budgets (pinned by `tests/test_machine_art.gd`): a yard machine stays under 30k triangles, a hub
landmark under 50k triangles and 14 mesh surfaces (the big wheel 20, its gondolas included).
Measure with `godot --headless --path . res://tools/machine_stats.tscn`: one line per model with
triangles (LOD 0), mesh surfaces (draw calls before shadows), meshes, lights and build time.

| Model | Triangles | Surfaces | Before |
|---|---|---|---|
| Auto-baler | 26k | 15 on 6 meshes | 31 single meshes, one draw each, no bevels |
| Belt drive (pad, turntable, one belt run) | 20k | 23 on 9 meshes | 60+ single meshes (36 stripe boxes alone) |
| Hub landmark (each of six) | 22-30k (big wheel 45k with 12 gondolas) | 7-13 (wheel 16) | thin rods in the shared deco mesh |
| Picture sign | about 2k a face | none of its own (it is part of the machine's mesh) | new |

- A landmark is one body mesh with automatic LODs, plus one mesh for the turning part (fan, wheel,
  radar). The wheel's gondolas are two MultiMeshes of six. Lights: 2-4 shadowless OmniLights, only
  while the hub is awake, fading out between 70 and 90 m.
- Build cost: 30-60 ms of geometry plus 30-60 ms for the mesh and its LODs on the loaded cloud box.
  StreetDressing spreads the two halves over two frames (`HubLandmarks.warm`, then `data_for`), so a
  town build's longest frame does not grow. A hub's state change (the wake) builds the new state
  once: one frame of about 100 ms on this box, during the wake's own flash and shake.
- The pod was not rebuilt. Its draw calls were already merged by `PodBatch` (story/pod_batch.gd).
  The repair cart beside it is one mesh, 5 surfaces.
