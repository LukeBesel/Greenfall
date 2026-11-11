# Making a new planet

How to add a planet the way Verdance was made: its own size, theme, hubs and landmarks, from data.
Owner items 62 and 71: "set the foundation for more planets made the way Verdance was: different
themes, planet sizes and landmarks", and keep everything easy to change.

The worked example is **Testworld**, a dev-only stub planet defined only in data (no code). It is
half Verdance's size, has two hubs, a red-earth ground, a radio mast at home and a smokestack at
its second hub, its own life colours and landmark colours, and Ochre's score over Verdance's
ambience. Players never see it: it is not in `data/homeward.json`, so it is not on the system map
or in the campaign. Only `--orbit-planet=testworld` reaches it.

```
godot --headless --path . -- --fresh --orbit-planet=testworld --no-intro
tools/planet_smoke.sh testworld          # boots it, walks, hops, wakes hub 1, saves, loads
```

The code that reads all of this is `core/planet_cfg.gd` (`PlanetCfg`). Section 3 lists what still
assumes Verdance.

---

## 1. The recipe, step by step

Do the steps in this order. After each one the planet still boots (`--orbit-planet=<id>`); what
you leave out comes from a `_default` block.

### Step 1. The planet block: `data/planets.json`

Add a block keyed by the planet's id (lower case, no spaces). The `"_default"` block at the top
of the file holds what every planet gets; your block repeats only what it changes.
Dictionaries merge key by key and lists replace them (`PlanetCfg.entry`).

```json
"testworld": {
  "name": "Testworld",
  "dev": true,
  "globe": {"radius": 0.5, "frequency": 64, "hub_count": 2},
  "look": {"ground": {"dirt_tex": "red_laterite_soil_stones", "clean_tex": "sand_01",
           "dirt": [1.1, 0.85, 0.75], "clean": [1.05, 0.95, 0.85], "grass": [0.9, 1.05, 0.8]}},
  "hub_defaults": {"main_path": 2, "clean_hexes": 4},
  "hubs": [ ... see step 3 ... ]
}
```

| Key | What it does | Default (`_default`) |
|---|---|---|
| `name` | The name on the HUD, the map and the hub cards (English; translated through the .po files) | required |
| `dev` | `true` = a test planet: `--orbit-planet` only, never in `data/homeward.json` | `false` |
| `globe` | The size, see step 2 | Verdance's |
| `site_kit` | How hubs are built: `towns` (Verdance's town kit) or `prefab` (your own site scripts in `sites`) | `towns`, or `prefab` if the block lists `sites` |
| `hinterland` | The land between the hub towns (houses, tracks, works; towns kit only) | `true` |
| `look.ground` | The ground's textures and colours, see step 4 | Verdance's |
| `hub_defaults` | Main path length, chain, levels, the rocket hop and the arrival title (docs/ADJUSTING.md "Hubs") | Verdance's values |
| `hubs` | One entry per hub: name, town look, landmark, gifts. See step 3 | none (a `prefab` planet can go without) |

Older keys used by the four planets that came before the round world (`env`, `sky`, `fog`, `sun`,
`ambient`, `palette`, `junk_tint`, `junk_biome`, `pieces_mult`, `no_lakes`, `music_mood`,
`district`) are **not read on the globe**. See section 3.

### Step 2. Size: `globe`

```json
"globe": {"frequency": 64, "hub_count": 2, "radius": 0.5, "seed": 4471}
```

- `frequency` decides everything. The grid has `10·f²+2` hexes of 10 m each, and the radius grows
  in step with f: Verdance's f = 128 gives about 163,842 hexes and 1,840 m.
- `radius` is only a note of the size you aimed for, times Verdance's. If you give `radius` and
  no `frequency`, the frequency is worked out from the radius (`GlobeSpec.freq_for_radius`).
- `hub_count` is how many hub pads the survey reserves, spread as far apart as they can be.
  `hubs[].site` refers to these pads: 0 is the start pad, and the rest go in survey order.
- `seed` (optional) is the survey and terrain seed. Without it the seed is 4471.

Sizes in use:

| Planet | f | Hexes | Radius | Hubs |
|---|---|---|---|---|
| Testworld (dev) | 64 | 40,962 | 920 m | 2 |
| Ochre | 109 | 118,812 | 1,567 m | 8 |
| Verdance | 128 | 163,842 | 1,840 m | 10 |
| Tidewell | 166 | 275,562 | 2,387 m | 12 |
| Rime | 205 | 420,252 | 2,948 m | 16 |
| Anvil | 256 | 655,362 | 3,681 m | 20 |

A power of two (64, 128, 256) uses the level grid cache. Any other f builds and caches its own
grid on first use, in `user://sphere_grid_f<f>.bin`, which takes a few seconds once. Hub regions,
offline work and the far view scale with the size (`SphereOffline.region_rings`,
`OrbitQuality`). Bigger planets are not faster to clean: hexes stay 10 m.

### Step 3. Hubs and landmarks: `hubs[]` (and `data/landmarks.json`)

```json
{"site": 0, "order": 1, "id": "test_yard", "home": true, "name": "Test Yard", "town": "suburb",
 "landmark": {"kind": "radio_mast", "name": "Test Mast"}, "desc": "Home on the test planet."},
{"site": 1, "order": 2, "id": "test_works", "name": "Test Works", "town": "industrial",
 "landmark": {"kind": "smokestack", "name": "Test Stack"}, "desc": "The second test hub.",
 "gift": {"cubes": 100}, "hint": "The test works. Wake the stack."}
```

- Exactly one hub has `"home": true`, at `site` 0. `order` 1..n is the main path.
  `hub_defaults.main_path` says how many of them the leave gate counts.
- `town`: `oldtown`, `downtown`, `suburb` or `industrial`. Where a lake reaches into a town, it is
  built and named as a harbour.
- `landmark.kind`: one of the art-kit models (`water_tower`, `windpump`, `crane`, `radio_mast`,
  `ferris_wheel`, `smokestack`) or one of the older models (`old_bus`, `lighthouse`). The start
  yard uses its hub's kind too.
- `piece`, `gift`, `boosts`, `chain`, `reason`, `hint`: see docs/ADJUSTING.md "Hubs". The same
  keys work on every planet.
- The landmarks' colours and sizes on this planet go in `data/landmarks.json` under
  `planets.<id>.<kind>`, e.g. `"testworld": {"radio_mast": {"main": "orange", "accent": "navy"}}`.
  Whatever you leave out comes from `kinds`.

A `prefab` planet (Ochre, Tidewell, Rime, Anvil) lists its own site scripts in `sites` instead
(SiteBuilders documents the contract). It can go without `hubs[]`, but then it has no hub plan:
no hub names, no wake chain and no leave gate.

### Step 4. Theme: the ground, the landmarks and the life

- **Ground** (`look.ground` in data/planets.json): `dirt_tex`, `rubble_tex`, `clean_tex` and
  `grass_tex` are Poly Haven texture ids from `data/assets.json` (`python3 tools/fetch_assets.py`
  after adding one). `dirt`, `clean` and `grass` are colour multipliers `[r, g, b]` (1 = as is)
  on trashed ground, cleaned ground and grass, near and far.
- **Landmark colours**: `data/landmarks.json` `planets.<id>` (step 3).
- **Life** (`data/life.json` `planets.<id>`): how the ground greens, grass tufts and flower
  colours, when town blocks wake up, butterflies. Repeat only what changes:
  `"testworld": {"ground": {"grow_s": 120, "petals": ["#ffd27a", ...]}, "flutter": {"colors": [...]}}`.
  The keys are in docs/ADJUSTING.md "The world coming back to life".
- **Suns**: `data/solar_system.json` `planets.<id>` (orbit, day length, sun colours). A planet
  without an entry gets Verdance's suns.
- Not yet themable from data: the sky's colours, fog, the junk models, the animals and the town
  buildings' palette. These are listed in section 3, with what to do.

### Step 5. Sound, ambience and songs

- **Score and ambience** (`data/sound.json` `planets.<id>`): `theme` is the built-in score (one of
  verdance, ochre, tidewell, rime, anvil). `ambience` holds the bed (loops, events) and
  `ambience.life`, which follows the ground round Lumi. Use `"like": "<planet>"` to start from
  another planet's block and change only some keys. Testworld is
  `{"like": "verdance", "theme": "ochre"}`: Verdance's ambience and life bed under Ochre's score.
  A planet with no block gets `planets._default`, which is `{"like": "verdance"}`.
- **Songs** (`data/songs.json`): a song plays on a planet through its `"planets": ["<id>"]`, its
  `group`, a folder `audio/songs/<id>/`, or a `planets.<id>.songs` list. A `planets.<id>` block
  can also repeat any music rule (`gap_s`, `main_share`, `landing_gap_s`...). With no block the
  global rules apply and songs marked `"all"` play. See docs/ADJUSTING.md "Music and sound".
  Testworld has no songs block on purpose: that is the fallback.
- **CDs** to find on the planet: songs with `"unlock": "cd", "found_on": "<id>"`.

### Step 6. Economy and pacing

The planet's place in the campaign is its entry in `data/homeward.json` `planets[]`. The index
is the travel order, and 0 is Verdance, the home planet. That entry holds:

- `leave` {`hubs`, `hub_level`, `toast`}: when the drive to the next planet opens.
- `far_hub`: any key of `data/hub.json` `far_hub` (wake price curve, sell growth), for this
  planet only.
- `arrival`: the research tier, robots, cubes and parts the player lands with. Also `seed`,
  `mods`, `needs_tech`, `twist`, `color` and `orbit` (the system map).

Prices, gates and the step order are v6pace's: see **docs/BALANCE.md** and docs/ADJUSTING.md
"Pacing, prices and gates". A dev planet has no Homeward entry, so it runs on the economy of the
campaign planet the save is on (Verdance's on a fresh start).

### Step 7. The story block

v7arc is adding a per-planet story block; see **docs/STORY_ARC.md** (if it is not merged yet,
ask v7arc). Leave room for it here:

> **Story slot for `<id>`** (to fill from docs/STORY_ARC.md): why Lumi comes here (the fuel or
> power this planet gives toward the way home, owner item 72), the arrival line, the WREN lines
> per hub (`data/story_reasons.json` `goal_reasons.by_id.hub_fly_<order>` or each hub's
> `reason`), the leave toast (`data/homeward.json` `planets[k].leave.toast`), and the exit beat.

Today the objective chain (`data/objectives.json`) and the goals (`data/goals.json`) are one list
for the whole game, written for Verdance's six stations. See section 3, "Goals".

### Step 8. Translations

Every player-facing string in the new blocks (`name`, hub `name`, `desc`, `hint`, `reason`,
landmark `name`, toasts) needs the six languages:
`python3 tools/extract_strings.py`, then `python3 tools/l10n_status.py --export` and
`tools/l10n_merge_draft.py` (docs/LOCALIZATION.md). Blocks with `"dev": true` are skipped by
the extractor, so Testworld's strings stay English and out of the catalog.

### Step 9. Checks

Run them one at a time (one godot process at a time on this box):

| Check | Command | What it proves |
|---|---|---|
| Data | `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_planet_data.gd -gexit` | Every planet has its blocks (`PlanetCfg.problems`): name, globe, a site kit that builds, hubs that make sense, a known score, a Homeward entry unless dev |
| Planet smoke | `tools/planet_smoke.sh <id>` | Boots the globe at its size, the start town has the data's landmark, Lumi walks, the rocket hops to hub 1 and its site builds, hub 1 wakes, the game saves, and a new process loads the same planet, Lumi's spot and the woken hub. No script errors |
| Save round trip | `godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh --orbit-planet=<id>` | Every system's state through a save |
| Hub walkthrough | `godot --headless --path . -- --fresh --orbit-planet=<id> --no-intro --hop-skip --hub-walkthrough` | Every main-path hub: town, landmark, reach, wake, gift, bench, HUD |
| Start town | `... -- --fresh --orbit-planet=<id> --no-intro --city-walk` | Walk area, dead ends, the ways out |
| Targets | `... -- --fresh --orbit-planet=<id> --no-intro --target-reach` | Every collectible and objective target stands on reachable ground |
| Look | `bash <scratchpad>/render.sh -- --fresh --orbit-planet=<id> --no-intro ...` | One render, with the shared render lock (CLAUDE.md) |

`--city-walk`, `--target-reach` and `--hub-walkthrough` were written on Verdance and assume its
start town. They are worth running, but read their failures as "Verdance-shaped expectation" first.

---

## 2. What was changed so that a planet is data (v7planet)

| Was | Now |
|---|---|
| `planet_id == "verdance"` picked Verdance's town builder (5 places), the town hub radius, the yard keep-out, the hinterland and the harbour rule | `site_kit` in data (`PlanetCfg.uses_towns`, `has_hinterland`) |
| A planet with no `globe` got a const in code | `_default.globe` in data, plus an optional `globe.seed` |
| `hub_defaults` with no fallback (`main_path` 6 in code, hop timings only Verdance's) | `_default.hub_defaults`, merged under each planet's |
| The start town is built before HubPurpose, so it read Verdance's hub plan, and its landmark was always the water tower | `PlanetCfg.use_planet` points the hub plan at the globe's planet before anything builds; the start yard takes its hub's `landmark.kind` (Verdance's is the water tower, as before) |
| Sound: a planet (of data/planets.json) with no `data/sound.json` block was silently ignored by `Audio.set_planet_theme`, and the score followed the Homeward planet, not the globe | `planets._default` and `"like"`; the globe's planet sets the score and ambience |
| The sky's suns were always Verdance's on the globe | `SkyDirector.current_planet_id` is the globe's planet |
| The ground textures and colours were fixed | `look.ground` (textures and three tint uniforms in `sphere_ground.gdshader`, 1 = unchanged) |
| The HUD said "VERDANCE" on any globe | the planet's `name` when the globe is not the campaign's planet |

Verdance's behaviour is unchanged. `tests/test_planet_data.gd` checks that its merged values equal
its own block.

---

## 3. What still assumes Verdance

Found by grepping for `"verdance"`, `== 0` on the planet index, radius and hex constants, hub
counts, landmark and town lists, `biome == ""`, goal ids and per-planet lookups. File:line is as
of commit 41b427b (before this pass).

Severity:
- **block**: a new planet cannot be built or played without touching code.
- **high**: it builds, but plays wrong or looks like Verdance.
- **medium**: it needs a code edit to add a planet to a list, or the dev path is wrong.
- **low**: cosmetic, a fallback, or intentional.

### Fixed in this pass

| Where | What | Sev |
|---|---|---|
| planet/sites/site_builders.gd:22, :79, :94 | `match "verdance", ""` chose VerdanceSite; any other id needed its own `sites` scripts | block |
| planet/orbit/orbit_planet.gd:160 | hub pad radius 120 m only when id == verdance | block |
| planet/orbit/orbit_planet.gd:198 | the start yard's keep-out only on Verdance | block |
| planet/planets/planet_envs.gd:117 | the town filling its pad only on Verdance | high |
| planet/sites/orbit_sites.gd:346 | hinterland only on Verdance | high |
| planet/sites/hub_purpose.gd:408 | harbour towns only on Verdance | medium |
| planet/sites/verdance_site.gd:304, :441 | the start town's landmark hard-wired, and its plan read from "verdance" before HubPurpose is up | high |
| planet/sites/hub_plan.gd:44, :51 | `hub_defaults` with no default; the hop read "verdance" | high |
| planet/orbit/globe_spec.gd:11 | the default globe as a const; no per-planet seed | medium |
| core/sound_cfg.gd:67 | no fallback for a planet without a sound block | high |
| systems/homeward_director.gd:152 | the score follows the Homeward planet, not the globe (`--orbit-planet`) | medium |
| planet/sky_director.gd:54 | the globe's suns were Verdance's unless a Cradle world | medium |
| planet/sphere/sphere_streamer.gd:92 | the ground textures fixed | high (theme) |
| ui/hud.gd:302, planet/sites/hub_purpose.gd:443 | the HUD name from data/planet.json ("Verdance") | low |

### To do when the planet is built

| Where | What | Sev | What to do |
|---|---|---|---|
| data/objectives.json (hub_fly_2..4, hub_wake_2..4 at :219 on), data/goals.json:36-42 (hub_fly_5/6, "Wake station 6 of 6") | One objective and goal list for the whole game, written for Verdance's six stations. On a planet with fewer hubs the card waits for a hub that does not exist; with more, the texts say "of 6" | high | v6pace and v6story own these. Add a `planets` filter per entry (or `planets.<id>` lists) in story/objectives.gd and story/goals.gd, and fill the counts from `HubPlan.main_total(planet)` |
| data/story_reasons.json, data/wren_lines.json, story/intro.gd | WREN's lines and the crash-landing intro are Verdance's story. A new planet arrives by rocket (Homeward), so the intro only plays on a fresh `--orbit-planet` run | high | v7arc's per-planet story block (docs/STORY_ARC.md) |
| planet/orbit/orbit_planet.gd, planet/orbit/sphere_field.gd:343 | On the globe the junk is Verdance's everywhere: `junk_biome`, `pieces_mult`, `no_lakes` and `junk_tint` are only read by the flat-era env scripts (planet/planets/*/env.gd:94-137) | high | Set `SphereField.biome_set = Economy.biome_set(PlanetCfg.value(pid, "junk_biome", ""))` and the density in OrbitPlanet.build, behind a data key, then check the junk LOD and preload lists (`--record-preload`) |
| data/fauna.json `species` | The same animals on every planet; no per-planet list | high | A `planets` key per species, or `fauna.json planets.<id>`; fauna/fauna.gd picks the list |
| planet/sky_director.gd presets, planet/orbit/orbit_day.gd:42, :142 | Sky colours, fog colour and ambient light are Verdance's in code (only the suns follow the planet) | high (theme) | A `look.sky` block (zenith, horizon, fog, ambient) read by SkyDirector's sphere mode |
| planet/sites/verdance_site.gd:38 `KINDS`, :47 `KIND_BY_HUB`; planet/sites/hub_plan.gd:12 `TOWN_NAMES` | Town types (rings, towers, lots, factories, ruin share) are consts | medium | Move `KINDS` to data (e.g. `data/towns.json`) when a planet needs a new town type; until then, pick from the four |
| planet/sites/verdance_site.gd:673 | The town buildings' kit palette (cream with teal) is Verdance's | medium (theme) | A `look.palette` read there |
| planet/sites/hub_landmarks.gd:20 `KINDS`, :159 `match kind` | A new landmark kind needs a model function in code (colours and sizes are data) | medium | Expected: a new model is new code. Add the kind to `KINDS` and `landmark_kinds()` in core/planet_cfg.gd |
| planet/street_dressing.gd:1963 `city_kinds`, :1988 `biome == ""` | The kit landmark is only used on the default biome; the fallback kinds per hub index are Verdance's | low | Fine while every towns-planet hub names a kind in data |
| audio/planet_themes.gd:7, audio/music_tracks.gd, audio/planet_synth.gd:12, audio/music_director.gd:480 | Built-in scores are code (five); `_active_theme == "verdance"` has a calm-mood special case | medium | A new planet borrows a score (`theme`). A new score is new code |
| planet/globe_size.gd:10, ui/planet_globe.gd:16, :24, :265, ui/system_map.gd:28, ui/ark_bridge.gd:14, systems/homeward_director.gd:106, systems/tunes.gd:121 | The five campaign planets listed in code for maps, discs, orbit radii and shaders; unknown ids get a generic grey rocky world | medium | Add the id there when the planet joins `data/homeward.json`, or move these lists to `data/solar_system.json` |
| automation/hub.gd:97, systems/homeward.gd:170-177 | The economy and the leave gate are looked up by the Homeward index, not the globe's id | medium | Expected for campaign planets. A dev planet uses the current campaign planet's |
| story/core_charge.gd:109, systems/homeward_director.gd:56-390, systems/homeward.gd:657-669, story/egg_props_late.gd:22 | `current_planet() == 0` means "home, Verdance" | low | Intentional: index 0 is the home planet |
| scenes/slice_orbit.gd:68-72 | A save of another planet, loaded with `--orbit-planet`, is thrown away (`GameState.orbit = {}`) | low (dev) | Only use `--orbit-planet` with `--fresh` or a `--save-dir` |
| planet/planets/planet_envs.gd:67 `GLOBE_DEFAULTS` | A second, older size table, used only when a planet has no `globe` block | low | Delete it once every planet has `globe` (all do now) |
| planet/sky_director.gd:268, planet/sphere/sphere_terrain.gd:9, planet/sphere/sphere_surface.gd:11, planet/sites/town_outskirts.gd:26 | `1840.0` defaults | low | Overwritten from the grid at build; harmless |
| core/sphere_offline.gd:21 | `REF_CELLS_PER_HUB = 163842 / 10` | low | A reference size; regions scale from it |

### The four older planets on the globe (smoke results)

`tools/planet_smoke.sh rime ochre tidewell anvil` passes for all four (Nov 11): each boots at its
size (f 205 / 109 / 166 / 256), Lumi walks, the rocket hops to hub 1 and its own site prefab
builds, level 2 is set, and the save loads back with the same planet, spot and level. No script
errors. What they lack is content, not foundation:
- They have no `hubs[]`, so there is no hub plan: no hub names, no wake chain, no leave gate counts.
- Their sky, junk and palette blocks are the flat-era env's and are not read on the globe (above).
- They use their own `sites` scripts (`site_kit` "prefab").

---

## 4. Files at a glance

| File | Block for a planet |
|---|---|
| data/planets.json | `<id>`: name, globe, site_kit, look, hub_defaults, hubs (and `_default`) |
| data/landmarks.json | `planets.<id>.<kind>`: landmark colours and sizes |
| data/life.json | `planets.<id>`: ground, town, flutter (and `_default`) |
| data/sound.json | `planets.<id>`: theme, ambience, ambience.life, like (and `_default`) |
| data/songs.json | `planets.<id>`: songs, rule overrides; songs' `planets`, `found_on` |
| data/solar_system.json | `planets.<id>`: suns, orbit, day length |
| data/homeward.json | `planets[k]`: campaign order, leave gate, far_hub, arrival (not for dev planets) |
| data/hub.json, data/rockets.json | the shared economy (docs/BALANCE.md) |
| data/objectives.json, data/goals.json, data/story_reasons.json | the story steps (shared today; see section 3) |
| docs/STORY_ARC.md | the per-planet story block (v7arc) |

Code: `core/planet_cfg.gd` (merging, the site kit, checks), `planet/orbit/globe_spec.gd` (size),
`planet/sites/hub_plan.gd` (hubs), `core/sound_cfg.gd`, `core/life_cfg.gd`,
`planet/sites/planet_smoke.gd` (the smoke), `tests/test_planet_data.gd` (the data check).
