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

### Measured (headless, scoop walk with the Future Layer on 148 cells, 110 s)

`godot --headless --path . -- --fresh --orbit --orbit-walk --orbit-scoop --orbit-future=10 [--orbit-hex=13.5 | --orbit-level=8] --quit-after=110`

| Globe | Hexes | R | Ready (load) | Process ms avg (max) | Junk pieces drawn | Chunk tris (LOD 0/1 count) | Shell tris | Chunk build (worker) max | Chunk apply (main) max | Memory |
|---|---|---|---|---|---|---|---|---|---|---|
| Verdance (level 7, 10 m) | 163,842 | 1,840 m | 10.3 s | 9-23 (17-55) | 1,800-2,450 | 73-80k (6-7 / 12-14) | 61k | 308 ms | 9 ms | 597 MB |
| Anvil radius (level 7, 13.5 m hexes) | 163,842 | 2,485 m | 9.4 s | 10-11 (22-37) | 1,260-1,610 | 55-58k (4-5 / 9-10) | 61k | 100 ms | 14 ms | 596 MB |
| Upper bound (level 8, 10 m) | 655,362 | 3,681 m | 9.1 s (grid cached; 32.6 s first time, planet 15.5 s) | 19-29 (45-68) | 4,340-4,760 | 106-109k (7 / 15-17) | 61k | 180 ms | 26 ms | 709 MB |

Anvil (~300k hexes at 10 m) sits between the level-7 and level-8 rows: per-frame costs follow
the hexes near the camera (same 10 m density on every planet), so expect Verdance-like frame
costs. Load time and memory sit about halfway to the level-8 row (~650 MB, planet generation
~5-8 s the first time; the grid is cached in `user://sphere_grid_<level>.bin` after that).

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

Rendered draw-call numbers for the globe at Low/Medium (960x540) are pending: renders were
killed for memory in the shared container. Command (gated render):
`xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver vulkan --resolution 960x540 -- --fresh --quality=1 --perf --orbit --orbit-walk --orbit-scoop --quit-after=120`.
