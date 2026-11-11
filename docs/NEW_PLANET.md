# Making a new planet

How to add a planet the way Verdance was made (owner items 62 and 71). The recipe follows in the
next commit; this first part is the audit (v7planet).

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

