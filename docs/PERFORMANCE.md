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
