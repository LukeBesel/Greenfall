# World audit: Verdance today against "full cities around the planet full of junk"

Task M3-17, Nov 10 2026, on commit `55589fb`. No game code changed. Numbers come from the read-only probe `tools/world_audit/world_probe.tscn` (output: `screenshots/world/world_probe.json`) and from 21 renders in `screenshots/world/` made with `tools/world_audit/world_shot.tscn`.

Judged against `docs/design/PLANET1_DESIGN.md` section 15 and the owner's art rule of Nov 10 (style guide section 9 on branch `claude/greenfall-aurora`): realistic in detail, bright in mood, never a gloomy brown game.

## 1. Short answer

- **At street level, in daylight, inside a hub town, the game already looks like a bright, colourful, junk-covered town.** Brick facades, awnings, murals, a billboard, wrecked vans, dense litter (`harbour_street`, `suburb_street`, `downtown_edge`).
- **Everywhere else it falls short of the owner's goal.** From above and from far away the world is a pale cream ball with scattered boxes on a brown-grey backdrop. The cities are a small street grid with boxes dropped round it. The five town kinds differ mostly in building height. No landmark belongs to a pollution source. Nine of ten hubs have a junk-free centre 120 m across. The land between is one uniform litter carpet with two box shapes repeated 31,688 times.
- **Mood:** street-level day frames pass. Every high or far frame fails (washed out, saturation 0.06-0.10, brown-grey backdrop). Ruined towns at dusk and night have no lit lamp or window.

## 2. How it was measured

| Tool | What it does |
|---|---|
| `godot --headless --path . res://tools/world_audit/world_probe.tscn -- --fresh` | Builds the globe without the slice, builds each hub's prefab in turn and reads it, lays the junk of sample cells per ring band, classifies every land cell, samples three walks out of the start. 42 s. Writes `screenshots/world/world_probe.json`. |
| `res://tools/world_audit/world_shot.tscn` (rendered, see the script header) | Starts the slice with no menu, so `--shot`, `--perf` and `--scene-stats` work as usual. It also lets a hub town that builds in play use long work slices, because at 1 frame a second the game's 6 ms a frame would never finish a town before the screenshot. |

Limits to know about:
- Renders are `opengl3` at 1280x720 on software GL, `--quality=1` (Medium) as the task asked. One extra run at the heaviest spot used `--quality=0` (Low).
- Local time follows longitude. Hub 4 (industrial) was at dusk and then night when rendered. Those two frames are kept as the dusk and night evidence; there is no daylight street shot of the industrial town.
- The survey map (the hologram on M) was not rendered. Its look is judged from the far-shell shader it shares and from the two far renders.
- `--no-hud` does not hide the Command view hint line (top left of the high shots).
- The junk count is pieces of scoopable junk per cell. The flat paper and small litter on the ground are a separate layer (`SphereLitter`, 8-14 items per m2) and are not in that count.

## 3. The globe in numbers

| | |
|---|---|
| Radius, area | 1,840 m, 42.6 km2 |
| Cells | 163,842 (17.3 m apart) |
| Land / water | 122,900 / 40,942 (25% water) |
| Hub sites | 10, between 1,594 and 2,101 m from their nearest neighbour |
| Hub pads (flat, with streets) | 2,718 cells, 2.2% of land |
| Town outskirts (to 345 m from a hub) | 8,966 cells, 7.3% of land |
| Land between | 111,216 cells, 90.5% of land |
| Junk on untouched land | 200 pieces a cell everywhere (mean junk fraction 0.997) |
| Survey "cities" (what the far shell and map paint as urban) | 24 patches, 3,941 cells, 3.2% of land |

Two things follow from this table. The ten towns together cover under a tenth of the land, so the land between decides whether the globe reads as covered. And the map's urban paint does not match the towns: only 6 of the 10 hub towns stand on a survey city (hubs 0, 1, 5, 6, 7, 8), and 18 survey cities have no town at all.

## 4. The ten hub sites

Kinds are what the game builds today. `KIND_BY_HUB` asks hubs 1-9 for 3 suburbs, 2 old towns, 2 downtowns and 2 industrial, but the "harbour" kind takes over wherever more than 12% of the sample points are water, so the real mix is **3 harbours, 2 downtowns, 2 industrial, 1 old town, 1 suburb, plus the start**.

### 4.1 Numbers

| Hub | Kind | From start | Pad | Blocks (built) | Pad buildings, floors min/median/max | Outskirts buildings (skipped for water), tallest | Furniture | Landmark prop | Water share, rings 1-6 / 7-12 / 13-18 | Junk-free hub ground, rings 1-6 | Junk pieces a cell, rings 1-6 / 7-12 / 13-18 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | start ("Old Town") | 0 | 140 m | 22 (17) | 79, 3/6/26 | 211 (666), 29 fl | 523 | water tower | 41% / 61% / 68% | 1% | 195 / 194 / 191 |
| 1 | downtown | 5,560 m | 120 m | 21 (20) | 129, 3/10/30 | 873 (0), 34 fl | 311 | crane | 0 / 0 / 0 | 59% | 200 / 191 / 188 |
| 2 | harbour | 2,879 m | 120 m | 15 (10) | 54, 2/4/8 | 434 (388), 16 fl | 358 | ferris wheel | 37% / 49% / 42% | 33% | 200 / 190 / 184 |
| 3 | harbour | 3,203 m | 120 m | 18 (16) | 104, 2/4/14 | 609 (225), 15 fl | 353 | radio mast | 11% / 23% / 21% | 53% | 200 / 188 / 192 |
| 4 | industrial | 2,655 m | 120 m | 21 (14) | 88, 2/3/5 | 568 (0), 5 fl | 348 | smokestack | 0 / 0 / 0 | 50% | 200 / 194 / 193 |
| 5 | old town | 2,359 m | 120 m | 21 (20) | 124, 2/3/6 | 823 (237), 7 fl | 293 | old bus | 0 / 2% / 20% | 49% | 200 / 190 / 191 |
| 6 | harbour | 4,114 m | 120 m | 18 (14) | 84, 2/4/10 | 326 (402), 15 fl | 370 | water tower | 17% / 37% / 47% | 48% | 200 / 198 / 183 |
| 7 | industrial | 1,865 m | 120 m | 21 (15) | 92, 2/3/5 | 544 (0), 5 fl | 329 | crane | 0 / 0 / 0 | 50% | 200 / 187 / 189 |
| 8 | downtown | 3,035 m | 120 m | 21 (18) | 113, 3/10/30 | 901 (0), 34 fl | 308 | ferris wheel | 0 / 0 / 0 | 61% | 200 / 197 / 185 |
| 9 | suburb | 1,594 m | 120 m | 21 (16) | 41, 1/2/3 | 379 (74), 2 fl | 399 | radio mast | 1% / 9% / 11% | 47% | 200 / 198 / 199 |

Notes on the columns:
- **Street grid.** Streets, kerbs, crossings and furniture exist only on the pad: 119 m from the centre at the start, 83 m at every other hub (a 5 x 5 grid of 36 m blocks with the corners cut). The outskirts have no road, kerb, sign, lamp or furniture at all.
- **Furniture** is counted pieces: crossings, benches, bins, post boxes, bus stops, bollards, name posts, stop signs, traffic lights, parked wrecks (38-58 a town), plus quay pieces, piers and boats where the lake reaches in.
- **Landmark prop** is picked by `hub_index % 6` from one list. It is not tied to the town's kind or to any source. Two towns share the crane, two the ferris wheel, two the radio mast, two the water tower.
- **Junk-free hub ground**: `OrbitPlanet._clear_site` clears every cell within 60 m of hubs 1-9 (22 m at the start). About half of rings 1-6 round those hubs has no junk.
- On top of the loose junk, about one sampled cell in four has a "wreck landmark" (barrel, road barrier, plastic chair, stove, covered car).

### 4.2 Rating

good = meets section 15, thin = present but not enough, missing = not there.

| Hub | Buildings | Streets | Junk | Landmark | Distinct character |
|---|---|---|---|---|---|
| 0 start | **thin**: 290 in all, the fewest of any hub; the lake took 15 pad blocks and 666 outskirts buildings | thin: 22 blocks on the pad, none beyond | good: 191-195 a cell right to the yard | thin: a water tower with the town's name, no source | thin: "OLD TOWN" sign, billboard, murals, quay and an old ship; reads as a waterfront corner, not a whole town |
| 1 downtown | good: 1,002, towers to 34 floors | thin: pad only | thin: full outside, but a 120 m junk-free hole in the middle | thin: crane, generic | thin: the skyline is real, the street looks like every other town's |
| 2 harbour | thin: 488 | thin: 10 built blocks | thin: hole in the middle | thin: ferris wheel, nothing to do with a harbour | thin: quay, piers and boats only |
| 3 harbour | good: 713 | thin | thin: hole | thin: radio mast | thin |
| 4 industrial | thin: 656, but every one is a 2-5 floor box | thin | thin: hole | thin: smokestack (fits by luck) | thin: no yards, tanks, pipes, cranes or gantries; half the pad is snow-white frostcap ground |
| 5 old town | good: 947 | thin | thin: hole | thin: old bus | thin: looks like the downtown's mid-rise streets |
| 6 harbour | thin: 410 | thin | thin: hole | thin: water tower | thin |
| 7 industrial | thin: 636 low boxes | thin | thin: hole | thin: crane (fits by luck) | thin |
| 8 downtown | good: 1,014 | thin | thin: hole | thin: ferris wheel | thin: same as hub 1 |
| 9 suburb | thin: 420, and the "houses" are flat-roofed 1-3 floor shop boxes | thin | thin: hole | thin: radio mast | thin: low and open, which is the most distinct street view of the ten |

No hub has a missing column, and no hub has a good row. The pattern is the same everywhere: a decent 170-240 m wide town core, then boxes on bare ground.

## 5. The land between

### 5.1 Numbers

| Zone (decided per cell by low-frequency noise) | Cells | Share of the land between | Cells with a building | Cells with a prop | Junk pieces a cell |
|---|---|---|---|---|---|
| Open junk field | 40,499 | 36% | 0 | 1,345 (3.3%) | 200 |
| Suburb | 57,385 | 52% | 32,644 (57%) | 1,519 (2.6%) | 200 |
| Industrial edge | 13,332 | 12% | 1,464 (11%) | 1,059 (7.9%) | 196 |
| **All** | 111,216 | 100% | 34,108 (31%) | 3,923 (3.5%) | 196-200 |

- **Bare ground:** none. Every land cell starts with its full junk. 73,185 cells (66% of the land between) have nothing on them except that junk and the litter carpet.
- **Buildings:** 34,108. Of these 31,688 (93%) are the two "house" shapes (9 x 8 m, one or two floors, flat roof, three colour variants each). 466 small blocks, 858 sheds, 660 warehouses, 436 works.
- **Props:** 2,127 cars (one colour, `#7a3b30`), 1,066 poles, 402 fence panels, 328 tanks. That is one car per 52 cells.
- **No roads, tracks, fences round yards, pylon lines, heaps bigger than a cell's two small mounds, or large wreck silhouettes.**

### 5.2 Walking out from the start

| Distance | North | East | South-west |
|---|---|---|---|
| 150 m | On the lake edge of the pad. 62 town buildings within 150 m. 57% of the ground round you is water. | On the pad. 86 town buildings within 150 m. | In the lake (79% water round you). |
| 300 m | In the lake (82% water). 20 town buildings within 150 m. | In the lake (74% water). 2 town buildings and 11 houses within 150 m. | Open water (100%). |
| 600 m | Open junk field on a lake shore. 35 houses within 150 m, 4 within 60 m. | Suburb zone. 109 houses within 150 m, 23 within 60 m (`walk_east_600`). | Lake shore. 34 houses within 150 m. |
| 1 km | Suburb zone. 66 houses within 150 m. | Suburb zone. 107 houses within 150 m. | Suburb zone. 104 houses within 150 m. |

So the start town is a peninsula: in two of three directions the player reaches the lake before the town ends. Past the lake the land is the same sprinkle of boxes in every direction, with nothing to steer by.

### 5.3 Rating

| | Buildings | Streets | Junk | Landmark | Distinct character |
|---|---|---|---|---|---|
| Open junk field (36%) | missing (by design) | missing | good in the near ring, uniform; no heaps or big wrecks | missing | thin: the brightest "full of junk" view in the game (`land_open`), but the same view everywhere |
| Suburb (52%) | thin: many, two shapes | missing | good, uniform | missing | thin: boxes dropped on a carpet, no yards, fences or roads |
| Industrial edge (12%) | thin: one in nine cells | missing | good, uniform | missing | thin: not told apart from the suburb at walking height |

## 6. From orbit and the map

The globe reads as **mostly empty with dots**, and pale.

- `far_900` (900 m up) and `planet_far` (2,600 m up): a cream-white ball with grey lakes and a few clusters of specks. Mean saturation 0.06 and 0.09. No city is visible as a city. No junk is visible at all.
- Why the junk vanishes: scoopable pieces are drawn in the 70 m near ring only and the litter carpet to 45-80 m. Past that the ground shader's "trash" mottle is black, brown and cream (`sphere_ground.gdshader` lines 60-62) and the fog adds grey (`fog_light_color` 0.62/0.62/0.66, density 0.0011: about 89% fog at 2 km). In the high shots the far ground also shows a regular tiling pattern.
- Why the backdrop is brown-grey: below the horizon the sky shader shows `haze_day` (0.55, 0.52, 0.48) while haze is 1, which is the whole early game (`orbit_sky.gdshader` lines 33 and 144).
- Why cities do not read: the far shell paints "urban" where the survey placed its 24 cities, not where the ten towns and the hinterland buildings stand (section 3).
- World goals on the map: there is no districts table yet (task M3-03), so nothing like "Old Town: Growing 62%" or "4 of 6 cities restored" can be shown. Hub sites get a cyan outline; that is all.

## 7. Performance at each render position

Rendered numbers are `--perf` (after culling). Census numbers are `--scene-stats` (whole scene, before culling). Medium preset unless marked.

| Position | Draw calls | Objects | Triangles drawn | MultiMesh instances in scene | Census est. draws | Census triangles |
|---|---|---|---|---|---|---|
| Start yard, day | 1,088 | 1,141 | 5.5 M | 104,496 | 4,529 | 7.5 M |
| Start yard, night | 1,109 | 1,159 | 5.6 M | 104,489 | 4,523 | 7.5 M |
| Start, 200 m oblique | 666 | 722 | 2.4 M | 214,595 | 6,429 | 11.8 M |
| Downtown street (centre) | 1,037 | 1,124 | 4.5 M | 39,785 | 3,574 | 5.0 M |
| Downtown street (60 m out) | 919 | 958 | 4.7 M | 51,231 | 3,808 | 5.7 M |
| Downtown, 300 m up | 640 | 749 | 2.1 M | 38,761 | 3,747 | 5.0 M |
| Harbour street | 1,313 | 1,372 | 5.8 M | 108,870 | 4,787 | 8.1 M |
| Harbour, 300 m up | 722 | 853 | 1.5 M | 27,530 | 3,707 | 3.7 M |
| Industrial street, dusk | **1,877** | 1,956 | 7.1 M | 138,090 | 5,434 | 9.8 M |
| Industrial street, night | 1,592 | 1,700 | 5.2 M | 104,299 | 5,015 | 7.9 M |
| **Industrial street, Low preset** | **1,103** | 1,181 | **3.0 M** | 104,027 | 5,426 | 5.8 M |
| Industrial, 300 m up | 799 | 935 | 1.8 M | 41,247 | 4,132 | 4.5 M |
| Old town street | 1,361 | 1,443 | 5.2 M | 88,796 | 4,684 | 7.3 M |
| Old town, 300 m up | 649 | 759 | 1.7 M | 33,772 | 3,948 | 4.3 M |
| Suburb street | 1,196 | 1,251 | 6.0 M | 139,039 | 5,403 | 9.7 M |
| Suburb, 300 m up | 570 | 674 | 1.5 M | 45,552 | 4,024 | 4.5 M |
| Land between: suburb | 1,028 | 1,034 | **7.5 M** | 180,049 | 4,265 | 10.6 M |
| Land between: open field | 927 | 933 | 6.2 M | 174,452 | 3,918 | 9.8 M |
| Land between: industrial | 1,012 | 1,015 | 6.8 M | 168,925 | 4,008 | 9.7 M |
| Land between: 600 m east | 1,106 | 1,114 | 6.4 M | 164,136 | 4,853 | 10.5 M |
| 900 m up | 388 | 468 | 2.0 M | 171,588 | 3,989 | 9.2 M |
| 2,600 m up | 511 | 605 | 1.7 M | 101,682 | 4,299 | 6.8 M |

What this means for the plan:
- `docs/PERFORMANCE.md` gives no draw-call ceiling for a globe town. The nearest reference is the flat Old Town on Low after the draw-call pass: 1,586 draws, 16.2 M triangles. Today's towns are at or under that: 920-1,880 draws on Medium, 1,103 draws and 3.0 M triangles on Low at the heaviest spot. **Proposed budget for every city on Low: 1,500 draws and 6 M triangles drawn at street level.** That leaves about 400 draws of headroom per city for everything in section 10.
- The litter carpet is the largest cost everywhere: 4.1-7.3 M of the census triangles and 1,400-2,560 of the estimated draws. Buildings are cheap (the whole hinterland is 40 MultiMeshes, 104 estimated draws). So buildings, roads and landmarks are affordable; more loose junk is not.
- Only the Low run above was measured on Low. The first task in the plan should re-measure all six city sites on Low.

## 8. The renders

All in `screenshots/world/`. "sat" is mean saturation of the frame and "dull" the share of grey or muddy-brown pixels (a rough script; street-level day frames score sat 0.20-0.27).

**Start**

- `start_yard_out.png` (sat 0.12, dull 34%). The yard looking north. Good: the "OLD TOWN" sign, a painted billboard, a mural, brick blocks with awnings, a dense colourful junk field up to the pad edge, blue sky. Wrong: the pad is a large, spotless white slab that fills half the frame; the left third is flat grey-green lake with a thin skyline of pale boxes across it; the town is visible on one side only.
- `start_oblique.png` (sat 0.10, dull 90%). 200 m up behind the yard. Good: a real cluster of towers and mid-rise on a peninsula. Wrong: the frame is grey-brown. The lake is dark olive and takes half the picture, the sky below the horizon is a flat brown, the towers are pale blue-white proxies with no colour, and the ground past the near ring is bleached. Fails the mood rule.
- `start_night.png` (sat 0.42). The same view at midnight. Good: readable, deep blue, the billboard and mural still carry colour, the pad's cyan edge reads. Wrong: no lamp, window or sign is lit anywhere in the town; the lake is black.

**Downtown (hub 1)**

- `downtown_street.png` (sat 0.21, dull 57%). The hub yard at the centre. Good: towers down the street, laundry lines, a wrecked van, a mural. Wrong: there is no junk in the frame at all. Broken slabs, a clean pavement and a clean road: this is the 60 m cleared core, and it is what a player sees first on arrival.
- `downtown_edge.png` (sat 0.25). 60 m south of the centre looking north. This is the best "city" frame of the set: brick, striped awning, a BAKERY sign, a van, towers closing the street. Wrong: still almost no junk on the road, and a bent lamp post cuts the frame.
- `downtown_high.png` (sat 0.08, dull 62%). 300 m up. Good: a dense ring of towers round the grid; this is the only town with a skyline. Wrong: the streets stop at the pad and the towers stand on bare cream ground with a visible repeating tile pattern; roofs are white; nothing reads as junk; the ruined centre looks tidier than the outskirts.

**Harbour (hub 2)**

- `harbour_street.png` (sat 0.23, dull 32%). A corner lot on the pad. Good: bright, sunny, colourful junk on warm ground, wrecked vans, awnings, blue sky. Passes the mood rule. Wrong: nothing says harbour (no crane, container, boat or water in view); the junk is mostly flat paper sheets and black bags, a carpet and not heaps.
- `harbour_high.png` (sat 0.10, dull 67%). Wrong: the lake is a flat dark olive slab; only ten blocks are built; the outskirts are loose boxes with no road between them; the pad looks like a model on a table.

**Industrial (hub 4)**

- `industrial_street_dusk.png` (sat 0.45, 39% of pixels dark). Good: junk on the road, a wrecked truck, a stack on the skyline, a pink dusk sky. Wrong: dark navy overall, no light anywhere, and the buildings are the same brick flats and awnings as every other town.
- `industrial_street_night.png` (47% dark). Readable but dead: stars, blue-black walls, no lamp, no window.
- `industrial_street_low.png`. The same street on the Low preset, for the performance row.
- `industrial_high.png` (sat 0.26). Wrong: half the town stands on blue-white frostcap ground and half on sand, the hex overlay covers everything, the buildings are small scattered boxes, and nothing shows what the industry was.

**Old town (hub 5)**

- `oldtown_street.png` (sat 0.25). Good: a believable street of walk-ups with fire escapes, an awning, a traffic light, a wreck. Wrong: junk only in the foreground and a clean road beyond (the cleared core again); it cannot be told from the downtown's side streets; the street is in shade and reads a little dark.
- `oldtown_high.png` (sat 0.06, dull 51%). The worst frame for mood: the ground is blown out to white, the buildings are pale, and only the near ring keeps its warm ground. 823 outskirts buildings and no street between them.

**Suburb (hub 9)**

- `suburb_street.png` (sat 0.20). Good: low shops with striped awnings, a radio mast, a billboard, a wide junk-covered lot, blue sky. The most distinct town at street level. Wrong: the "houses" are flat-roofed shop boxes, and the wall on the right is a blank proxy with a dotted window.
- `suburb_high.png` (sat 0.09). Wrong: tiny boxes scattered evenly on cream ground. It looks like a sparse industrial estate, not a suburb.

**Land between**

- `land_open.png` (sat 0.27, dull 33%). Open junk field 1.5 km north of the start. The best "planet full of junk" frame: bright, colourful, junk to the horizon in the near ring, mounds, blue sky. Wrong: a dark brown-grey band sits on the horizon, the far buildings are pale boxes, and there is no large shape anywhere (no car stack, no heap taller than Lumi).
- `land_suburb.png` (sat 0.23). The densest suburb spot (84 houses within 100 m). The "house" behind Lumi is a shuttered shop box with a flat roof. (The camera is pushed in close by a mound.)
- `land_industrial.png` (sat 0.22). An alley between two proxy buildings. Bright, with a yellow awning. The windows show a dotted moire pattern up close.
- `walk_east_600.png` (sat 0.27). 600 m east of the start. Good: sunny and colourful. Wrong: three-floor blocks dropped on a junk carpet with no street, fence or yard, and no way to tell which way the town lies.

**Far above**

- `far_900.png` (sat 0.06). 900 m up over the open field. A cream-white ball, grey lakes, specks. Brown-grey backdrop.
- `planet_far.png` (sat 0.09, dull 72%). 2,600 m up over the start: the curve of the planet. Pale white and pink land, light-blue lakes, the start town a smudge of grey specks. Nothing reads as junk or as a city. Fails the mood rule and the "covered" rule.

## 9. The five biggest gaps, most visible first

1. **From above and from far away the world is pale, empty and brown-backed.** Past about 100 m the junk is not drawn and the ground bleaches to cream or white with a tiling pattern; fog adds grey; the sky below the horizon is brown-grey. Every high frame scores saturation 0.06-0.10. The map's urban paint is in the wrong places. This is what the owner sees on the intro fall, in Command view and on the map.
2. **The cities are a small core with boxes round it, and they are not six characters.** Streets, kerbs, signs and furniture stop 83 m from the centre (119 m at the start); 326-901 outskirts buildings per town stand on bare ground. Kinds differ in floor counts and little else. The real mix today is 3 harbours, 2 downtowns, 2 industrial, 1 old town, 1 suburb. The start town, the one every player sees, has the fewest buildings (290) because the lake took 15 blocks and 666 outskirts buildings.
3. **No landmark belongs to a source, and nothing in a city changes with its regrowth stage.** The landmark is one of six props picked by hub number. The town's look follows the base level (broken, repaired, restored), not the district's stage. There is no districts table or source yet. A ruined town has no working light at dusk or night.
4. **Nine hubs open on a clean hole.** Every cell within 60 m of hubs 1-9 is cleared: about half of rings 1-6. The first thing seen on arrival is a tidy street (`downtown_street`). The start has a large spotless white pad in the middle of the frame.
5. **The land between is one carpet.** 200 pieces on every cell, the same mix everywhere, mostly flat sheets and bags. 66% of its cells have nothing else. 93% of its 34,108 buildings are two flat-roofed boxes. No roads, no big heaps, no large wrecks, one car colour. There is nothing to navigate by and no reason one kilometre differs from the next.

Smaller findings:
- The far-shell and ground "trash" colours and the litter palette lean brown: 59% of litter draws are cream, tan or brown, 21% grey or black, and each colour is then pulled 10-40% toward grey and up to 35% toward brown (`sphere_litter.gd` lines 259-278).
- The lake is murky olive before cleaning. Where it fills the frame (the start, the harbours) it is the main cause of a grey-green picture.
- Light walls and roofs blow out to white in direct sun (AgX tonemap at exposure 1.25 with sun 1.25 and ambient 1.1).
- Proxy-building windows show a dotted moire pattern up close on `opengl3`.
- **Bug seen in every far-hub render:** `SCRIPT ERROR: Invalid access to property or key 'content' on a base object of type 'previously freed'` at `planet/sites/site_manager.gd:417` (`_attach_power`). It fires when Lumi starts far from hub 0 (`--orbit-spawn`), so hub 0's prefab is freed while its power hook is pending. Not checked on a real rocket hop.

## 10. Proposal

### 10.1 Six cities

Order follows the design's pollution order (section 2). Sites were picked for water share, distance from the start and what already stands there. Each city gets its own palette and sign style; all of them stay sunny and saturated, with wear on top of the colour.

| # | City (site) | Character | Pollution | Source and its landmark | Palette and signs | What it needs built |
|---|---|---|---|---|---|---|
| 1 | **Old Town** (site 0) | Lakeside market town: brick walk-ups, a quay, a market street | litter | The burst main: a red-brick pumping station and water tower with a broken main fountaining over a flooded, litter-choked square. Shut down: the fountain stops, the square drains, the tower's sign lights. | Terracotta brick, cream, teal shopfronts, red-and-white awnings, hand-painted shop signs, murals | Fill the peninsula: quay-side blocks and a market street in place of the 15 blocks and 666 buildings lost to the lake; streets through the outskirts; shrink the white pad or dress it |
| 2 | **Ironside** (site 7, 1.9 km) | Scrapyard and works town: sheds, gantries, stacked car shells | litter, wrecks | The crusher yard: a gantry crane over a car crusher with a tall stack, feeding a wall of crushed cubes. Shut down: the stack stops smoking, the crane parks, floodlights come on. | Safety yellow, hazard orange, container blue and red, galvanised grey sheds, stencilled numbers | Yard blocks (fenced lots, car stacks, tyre piles, container rows) in place of apartment blocks; the existing crane becomes the source |
| 3 | **Kettle Bay** (site 3, 3.2 km) | Working harbour: quays, cranes, warehouses, a fish market | litter, slick | A grounded tanker leaking at the main quay, visible down every dock street. Shut down: the slick boom closes, the water round it clears to blue, harbour lamps light. | Navy and white, rust red hulls, buoy orange, signal flags, painted boat names, big dock numbers | Dock cranes, container stacks, a long quay; 11-23% water is enough lake to skim without drowning the town as at site 0 |
| 4 | **Highreach** (site 8, 3.0 km) | Downtown: towers, a plaza, a transit street | litter, smog | The incinerator plant on the edge of the towers: three striped stacks pouring smog that hangs over this district only. Shut down: the plume stops and the haze over the district lifts. | Glass blue and white towers, sign yellow, magenta and cyan shop signs, rooftop billboards | Tower-base shopfronts and signs on the outskirts towers (today bare proxies); the plant; a local haze volume that belongs to the district, not the sky |
| 5 | **Lowmeadow** (site 9, 1.6 km) | Garden suburb: detached houses, yards, a high street | litter, blight | The treatment works: round tanks and a cracked outfall pipe staining the ground down a slope. Shut down: the outfall runs clear and the stain stops spreading. | Pastel houses (mint, butter, coral, sky blue), red and green pitched roofs, white fences, shop signs on the high street | Real houses with pitched roofs, fences, drives and garden plots; the works from kit tanks and pipes |
| 6 | **Old Capital** (site 1, 5.6 km, the far side of the globe) | The big city: civic centre, a station, the tallest skyline | all five | The transfer terminal where the world's waste was sent: a conveyor tower and hopper over a rail yard, the largest structure on the planet. Shut down in stages, one per kind. | Sandstone and copper-green civic buildings, gold lettering, red transit signs, flags and banners | A sixth kind ("capital"): a plaza, a station hall, wide avenues; it already has 1,002 buildings and 34-floor towers |

Names are from the survey's own city list (`planet_data.gd`), so they are already Greenfall's. The source ids and steps belong to tasks M3-03 and M3-07; this proposal only fixes where each source stands and what it looks like.

Shared by all six:
- **Streets carry on through the outskirts** to the 330 m edge: road strips, kerbs, parked wrecks, lamp posts and signs, so the whole built area is blocks on streets.
- **Junk to the door.** The clear core shrinks to the hub yard. Arrival is into junk.
- **A skyline or silhouette of its own** that can be recognised from 500 m: Old Town's water tower, Ironside's gantry, Kettle Bay's cranes and tanker, Highreach's towers and stacks, Lowmeadow's tanks, the Capital's conveyor tower.
- **The regrowth stage changes the city** through one shared hook (`TownSite.set_stage`), with each planet's site script deciding what it shows: stage 1 clean streets; stage 2 lamps and some windows lit, signs readable; stage 3 planters and street trees, the source's effect fading; stage 4 clear water and awnings out; stage 5 flowers, birds, every light on.
- **Lights from the start.** Even a ruined city keeps a few emergency lamps, lit signs and the landmark's beacon, so dusk and night stay colourful.

### 10.2 The other four sites

They stay open ground (design section 1: optional, no source). Each becomes a small place with one bright landmark and no outskirts ring, so the six cities stand out and the budget goes to them.

| Site | Today | Becomes | Reuses |
|---|---|---|---|
| 2 | harbour, 37-49% water, ferris wheel | **The lakeside fairground**: the ferris wheel, stalls, a pier | the ferris wheel, quay and pier pieces, awnings |
| 4 | industrial on frostcap, smokestack | **The cold store**: a freight depot with tank rows and a stack in the snow | kit `tank_farm`, `hangar`, the smokestack |
| 5 | old town, old bus | **The bus depot**: a market village round a depot full of wrecked buses | the old bus, the pad town at 3 x 3 blocks |
| 6 | harbour, 17-47% water, water tower | **The fishing village**: a pier, boats, net racks, a water tower | boats, piers, quay lamps |

### 10.3 The land between

- **Roads between the cities.** One road along the great circle from each city to its nearest two: a strip of asphalt, wrecked cars nose to tail, pylons, a billboard every few hundred metres with the next city's name and distance. This is the cheapest way to make the land read as one world and gives the player a line to follow.
- **Junk country with shapes.** The open zone (36%) becomes named dump types decided by the same noise: tyre hills, car stacks, appliance fields, container heaps, bale walls. Each is one large MultiMesh shape per few cells in strong colours, so there is always a silhouette on the horizon.
- **Real outskirts.** The suburb zone clusters into small estates along the roads (pitched roofs, fences, pastel colours) with open junk between, in place of an even sprinkle on 57% of cells.
- **Industrial edges** get fenced yards, tank rows and pylon lines, within 600 m of Ironside, Kettle Bay and the Capital.
- **The far ground reads as junk.** The ground and shell shaders carry the junk's colours (can red, crate blue, bottle green, bag black, paper white) as flecks, so the junk does not stop at 70 m and the globe reads as covered from orbit.
- **The map shows what is there.** The far shell and the survey map paint urban where the towns and estates really stand, and each city shows its state and name.

## 11. Work plan

One row is about one agent session. "Needs" lists what must land first. Performance risk is against the proposed Low budget of 1,500 draws and 6 M drawn triangles per city view.

| # | Task | Files | Needs | Reuse | Performance risk |
|---|---|---|---|---|---|
| W1 | **Bright and far-read pass**: sky haze and below-horizon colour, fog colour and density, exposure and saturation, colour flecks in the far ground and the far shell, litter palette, lake murk tint. A/B renders at 6 of this audit's positions. | `planet/orbit/orbit_sky.gdshader`, `planet/orbit/orbit_day.gd`, `planet/sphere/sphere_ground.gdshader`, `planet/sphere/sphere_shell.gdshader`, `planet/sites/sphere_litter.gd`, `planet/sites/sphere_water.gdshader` | none | this audit's shot list and mood script | none (shader constants) |
| W2 | **Sites as data**: a per-site table (name, kind, palette, landmark, rings, clear core) replaces `KIND_BY_HUB` and the water rule; the clear core reads `clear_core_m`; city names on name posts and signs; fix the `_attach_power` error. Baseline all six on Low. | `planets/verdance/data/sites.json`, `planets/verdance/sites/verdance_site.gd`, `planet/orbit/orbit_planet.gd`, `planet/sites/site_manager.gd` | none; lines up with M3-03's `districts.json` | `KINDS`, `PROFILES` | none |
| W3 | **Streets through the outskirts, part 1**: road and kerb strips per 72 m tile on the curved ground, crossings at junctions, merged into the tile mesh. | `planets/verdance/sites/town_outskirts.gd` | W2 | `CityLayout` pitch and widths, the tile frames | low: +1 surface per tile, 23-64 tiles a town |
| W4 | **Streets through the outskirts, part 2**: lamp posts, signs, parked wrecks and bus stops along those streets as MultiMeshes; emergency lights and lit signs in the ruined state. | `planets/verdance/sites/town_outskirts.gd`, `planet/street_furniture.gd` | W3 | `StreetFurniture` builders, `KitProps.lamp_post` | medium: keep to 8 MultiMeshes a town, no small-prop shadows, lights capped near Lumi |
| W5 | **City palettes and signs**: per-kind facade palette and awning colours in the building shader, shop-sign and billboard sets per city, mural density, tower-base shopfronts on proxies; fix the dotted window pattern. | `planet/building_detail.gd`, the `building_city` shader, `planet/street_dressing.gd`, `planets/verdance/sites/*` | W2 | murals, neon signs, billboard, awnings | low (vertex colours and atlas decals) |
| W6 | **Old Town**: pumping station and burst main, market street, quay blocks filling the peninsula, pad dressing. | `planets/verdance/sites/` (new `city_old_town.gd`), `sites.json` | W2-W5 | water tower, quay, piers, ship, kit pipes and tanks | low |
| W7 | **Ironside**: crusher yard and gantry, yard blocks, car stacks, tyre piles, container rows. | `planets/verdance/sites/` (new `city_ironside.gd`) | W2-W5 | crane, smokestack, kit `hangar`, `machine_housing`, crates, barrels, the car prop | medium: stacks must be MultiMesh |
| W8 | **Kettle Bay**: grounded tanker, dock cranes, container quay, fish market. | new `city_kettle_bay.gd` | W2-W5 | the ship, boats, quay, crane, lighthouse | medium: water plus a dense quay in one view |
| W9 | **Highreach**: incinerator plant and stacks, plaza, district haze that lifts. | new `city_highreach.gd`, a local haze node | W2-W5 | smokestack, tower blocks, neon signs | medium: 900 outskirts buildings already; haze must be one cheap volume or shader term |
| W10 | **Lowmeadow**: house archetypes with pitched roofs, fences and yards; treatment works. | new `city_lowmeadow.gd`, `planets/verdance/sites/hinterland.gd` (shares the houses) | W2-W5 | kit `tank_farm`, pipes, the fence prop | low |
| W11 | **Old Capital**: the sixth kind (plaza, station, avenues) and the transfer terminal. | new `city_old_capital.gd`, `verdance_site.gd` | W2-W5 | downtown profile, kit `tower`, `hangar`, pipe runs | medium: the largest town; hold the tower count |
| W12 | **Stage changes the city (shared hook)**: `TownSite.set_stage(stage, share)` called from district state; source landmarks expose `set_shut_down`. | `planet/sites/town_site.gd`, `planet/sites/site_manager.gd`, `planet/sites/site_prefab.gd`, tests | M3-03, M3-07 | `set_level`, `StreetPower`, `kit_state` | low |
| W13 | **Stage changes the city (art)**: lit windows and lamps, readable signs, street trees and planters, clear water, awnings, birds, per city. | `planets/verdance/sites/*`, `planet/street_dressing.gd`, fauna data | W12, W6-W11 | kit planters and bushes, `PowerFx`, fauna regions | medium: trees are the cost; MultiMesh with a far card |
| W14 | **Roads between cities**: great-circle road strips with wrecks, pylons and distance billboards, streamed with the hinterland. | `planets/verdance/sites/hinterland.gd` (or a new `roads.gd` beside it) | W2 | hinterland streaming and keep-out, car, pole, billboard | low: 4-6 MultiMeshes |
| W15 | **Junk country**: dump types in the open zone (tyre hills, car stacks, appliance fields, container heaps, bale walls), car colour variants, estates in place of the even sprinkle, fenced industrial yards. | `planets/verdance/sites/hinterland.gd`, `planets/verdance/data/` (a new land table) | W10, W14 | `ARCH`, `PROPS`, the zone noise | medium: every new shape is a MultiMesh with a far LOD; no new loose pieces |
| W16 | **The four small places**: fairground, cold store, bus depot, fishing village as pad-only sites. | `planets/verdance/sites/verdance_site.gd`, `sites.json` | W2, W5 | section 10.2 | low (smaller than today) |
| W17 | **Orbit and map read**: the far shell and survey map paint urban from the real towns and estates; city markers with name and state; goal lines on the map. | `planet/sphere/sphere_shell.gd`, `planet/sphere/sphere_shell.gdshader`, the globe view and map UI (with the ui agent) | M3-03, W2, W15 | the shell's city and site channels | none |
| W18 | **Junk look**: more upright and bulky pieces in view, fewer flat sheets, colour variety, heaps that read from 30 m, with no rise in piece count. | `planets/verdance/data/junk.json`, `planet/orbit/sphere_field.gd` (data hooks only), `planet/sites/sphere_litter.gd` | W1; agree with balance (M3-12) | junk types and weights, piles | high: litter is already 55-70% of triangles; any change must be count-neutral |
| W19 | **World QA and budget pass**: this audit's probe and shot list re-run on all six cities on Low; `--city-walk`, `--target-reach`; fix what fails; update `docs/PERFORMANCE.md` with a globe-town budget. | `tools/world_audit/*`, `docs/reviews/`, `docs/PERFORMANCE.md` | all | this audit's tools | none |

**Size: about 19 agent sessions.** Order: W1 and W2 first (both stand alone and change what the owner sees at once), then W3-W5 (shared city work), then the six cities W6-W11 (two at a time at most, since each needs renders), W14-W16 alongside, W12-W13 when M3-03 and M3-07 land, W17-W19 last.

Risks to the plan:
- **Saves.** Changing the clear core, a site's kind or the hinterland's decisions changes a fresh world, not a saved one, unless the cells are re-derived on load. W2 must state the rule (the game is pre-release, so "fresh worlds only" is likely fine, but it is the lead's call).
- **The start site's lake.** Old Town cannot be a full city on a peninsula that is 41-68% water. W6 either builds the town along the shore as a quay district, or the survey's start pick moves to a drier city cell. Moving it is a bigger change (yard anchors, first-minutes checks).
- **Render time here.** Each render takes about 2.5 minutes on this machine and far hubs need the helper scene. A city task should budget six renders.

## 12. Quick wins (not applied)

Each is data or a few lines. Effects are what I expect from the code and the renders; each needs one A/B render before it is kept.

**Brighter and more colourful now**

| # | Change | Where | Expected effect |
|---|---|---|---|
| Q1 | Below-horizon and horizon haze from brown-grey to a light sky blue: `haze_day` (0.55, 0.52, 0.48) to about (0.70, 0.78, 0.88) | `planet/orbit/orbit_sky.gdshader` line 33 | The brown backdrop in every Command, map and fall view becomes sky. The dark band on the horizon in `land_open` goes. The largest single mood fix. |
| Q2 | Fog tint from grey to pale blue and half the density: `fog_light_color` (0.62, 0.62, 0.66) to about (0.68, 0.78, 0.92), `fog_density` 0.0011 to 0.0006 | `planet/orbit/orbit_day.gd` lines 42-43 and 81 | Distant towers and the far ground keep their colour; far views stop washing to grey-white. |
| Q3 | Colour flecks in the far "trash" mottle: add a red, a blue, a green and a yellow fleck to the black, brown and cream mix | `planet/sphere/sphere_ground.gdshader` lines 60-62, `planet/sphere/sphere_shell.gdshader` (the `trash` lines) | The ground past 70 m, Command view and the globe read as junk-covered, not as bare cream soil. |
| Q4 | Litter palette: raise the five saturated colours from 14% to about 35% of draws, cut the pull toward grey (0.1-0.4) and brown (0-0.35) by half | `planet/sites/sphere_litter.gd` lines 259-278 | The carpet reads as packaging and plastic, not as brown paper. No cost. |
| Q5 | Exposure and saturation: `tonemap_exposure` 1.25 to about 1.05 by day, and switch on `adjustment_saturation` at about 1.15 | `planet/orbit/orbit_day.gd` lines 39-40 and 133 | Light walls and roofs stop blowing out to white; brick, awnings and junk gain colour. |
| Q6 | Hinterland cars in four colours (teal, yellow, white, red) in place of one brown-red | `planets/verdance/sites/hinterland.gd`, `_prop_mesh("car")` and `PROPS` | 2,127 wrecks stop being one colour; three more MultiMeshes. |
| Q7 | A few lights in a ruined town: keep the landmark's beacon and one lamp in four lit at level 1 | `planets/verdance/sites/verdance_site.gd` `set_level` (`set_powered(level >= 2)`), `planet/street_furniture.gd` | Dusk and night in hubs 1-9 get warm pools of light and stop reading as dead. Needs a light cap near Lumi. |
| Q8 | Lake murk a clearer green-blue: lift the "murky olive" (0.05, 0.058, 0.032) toward teal | `planet/sphere/sphere_ground.gdshader` line 90, `planet/sites/sphere_water.gdshader` | The start and harbour frames lose their grey-green half. Still reads as dirty through the floating junk and scum. |

**Fuller and more junk now**

| # | Change | Where | Expected effect |
|---|---|---|---|
| Q9 | Clear core of hubs 1-9 from 60 m to the site's `clear_core_m` (12 m) | `planet/orbit/orbit_planet.gd` line 177 | Junk reaches the hub yard in nine towns: about 50 more junk cells a town and no tidy street on arrival. Fresh worlds only. |
| Q10 | Pin the kind per hub and raise the harbour rule from 12% to about 30% water | `planets/verdance/sites/verdance_site.gd` lines 47 and 415 | The mix becomes the intended spread (today 3 harbours, 1 old town, 1 suburb). Hub 3 (11% near water) and hub 6 keep their own kind with a waterfront. |
| Q11 | Fewer open lots and more buildings in the start outskirts: `PROFILES.start.lots` [0.12, 0.3] to [0.05, 0.15] | `planets/verdance/sites/town_outskirts.gd` line 41 | About 30 more buildings on the start's dry side (51 lots are left open today). Small, but it is the first town seen. |
| Q12 | Props on the open junk field from 3.5% to about 12% of cells, with tanks and fences allowed there | `planets/verdance/sites/hinterland.gd` line 217 | 3,500 more wrecks and shapes on the 36% of the land that has none. MultiMesh instances only. |
| Q13 | Two more hinterland building variants per archetype (`VARIANTS` 3 to 5) with stronger palette spread | `planets/verdance/sites/hinterland.gd` line 35 | 31,688 houses stop being six looks. 24 more MultiMeshes over the ring: check the draw count. |
| Q14 | Landmark prop by kind, not by hub number (crane for industrial, lighthouse for harbour, water tower for old town, radio mast for downtown, ferris wheel for the suburb) | `planet/street_dressing.gd` `_build_landmark` | Each town's one tall prop at least fits its kind until the source landmarks exist. |

Best three if only three are done: **Q1 + Q2** (one render, sky and fog together), **Q9**, **Q3**.

## 13. Open questions for the lead

1. The owner's line "the entire world is trashed. No cleared spots are visible" is read here as the wanted start state (section 15 says "all buried in junk at the start"). If it was a complaint that progress does not show, gap 4 and Q9 change meaning; gap 1 covers that reading (cleaned ground is not visible from afar either).
2. Site choice for city 3: site 3 (11-23% water) is proposed over site 2 (37-49%) so the harbour has land to stand on. If slick needs more lake cells than that, site 2 is the swap and the fairground moves to site 3.
3. Old Town on the peninsula or the start moved to a drier cell (section 11, risks).
4. Whether a changed fresh world may ignore old saves (W2).
5. Nothing in this audit or proposal is taken from another game. City names come from the survey's own list; the source landmarks are ordinary civic and industrial structures.
