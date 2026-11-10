# M1-06: planet content moved to `planets/verdance/data/`

Base commit `bc13499`. Behaviour is unchanged: no id, value or row was edited; the 28 files were moved with `git mv` and keep their names.

## How shared code reads planet content now
- `Economy.planet_table(name)` returns a private deep copy of `Planets.current().table(name)` (empty when the planet has no such table). A copy, because the old `Economy.read_json` gave every caller its own parse and several callers keep or edit what they get.
- Loaders that keep a table in a `static var` call `Economy.drop_on_planet_change(_drop_planet_cache)` when they load. Economy runs every registered drop once when `Planets.current_changed` fires, then reloads its own tables (`load_data`). Loaders register again on their next load.
- Node loaders that read in `_ready` (hub, stations, garden, hex levels, goals, objectives, eggs, shards, guide lines, ledger, seed finds) read through the definition each time they are created; they hold no static cache.
- `const PATH` in the moved loaders became `const TABLE` (the table name). `Objectives.PATH` was the only one used outside its file (one test).

## Classification of `data/`

### Planet content (moved to `planets/verdance/data/`, 28 files)
| File | Table name | Readers (through the definition) |
|---|---|---|
| junk.json | pollution | `autoload/Economy.gd`, `core/pace.gd` |
| upgrades.json | upgrades | `autoload/Economy.gd` |
| hex_levels.json | regrowth | `plants/hex_levels.gd` |
| objectives.json | tutorial | `story/objectives.gd`, `story/intro.gd` |
| goals.json | goals | `story/goals.gd` |
| research.json | research | `systems/research.gd` |
| robots.json | robots | `autoload/Economy.gd` |
| hub.json | hub | `automation/hub.gd`, `automation/recycler.gd` |
| stations.json | stations | `automation/stations.gd`, `automation/auto_baler.gd`, `automation/recycler.gd`, `ui/upgrade_card.gd` |
| plants.json | plants | `plants/garden.gd`, `plants/seed_finds.gd`, `player/patch.gd`, `systems/codex.gd` |
| fauna.json | fauna | `fauna/fauna_rules.gd` |
| events.json | events | `systems/events.gd`, `systems/contracts.gd`, `systems/collection.gd` |
| patch.json | player (new) | `autoload/Economy.gd`, `core/pace.gd` |
| lumi_level.json | robot_level (new) | `systems/lumi_level.gd` |
| planet.json | field (new) | `autoload/Economy.gd` |
| builds.json | builds (new) | `systems/camp/hub_builds.gd` |
| camp.json | yard (new) | `systems/camp/yard_builds.gd` |
| trash_bin.json | trash_bin (new) | `automation/trash_bin.gd` |
| outposts.json | outposts (new) | `automation/outposts.gd` |
| frontiers.json | frontiers (new) | `planet/frontiers.gd` |
| signal_tower.json | signal_tower (new) | `story/signal_tower.gd` |
| wren_lines.json | guide_lines (new) | `story/wren.gd` |
| shards.json | shards (new) | `story/shards.gd`, `systems/codex.gd`, `systems/museum.gd` |
| eggs.json | eggs (new) | `story/eggs.gd`, `systems/codex.gd` |
| ledger.json | ledger (new) | `story/ledger.gd` |
| codex.json | codex (new) | `systems/codex.gd` |
| museum.json | museum (new) | `systems/museum.gd` |
| bloom.json | postgame (new) | `systems/bloom.gd` |

"(new)" names were added to `PlanetDefinition.OPTIONAL_TABLES`. Judgement calls: `patch.json` (base stats, dump rule and old-save grant are pacing numbers tuned for this planet), `planet.json` (field size and hex bonus of this world), `ledger.json`, `codex.json`, `museum.json` and `frontiers.json` (their rows are keyed to this planet's junk, plants, story and districts).

### Global (stay in `data/`, 24 files)
| File | Why global | Readers |
|---|---|---|
| currencies.json | one currency set for the whole game | `core/currencies.gd` |
| designs.json, style_parts.json, robot_parts.json, ship_style.json, decor.json | cosmetics and decoration catalogues owned across planets | `systems/designs.gd`, `systems/lumi_style.gd`, `systems/robot_builder.gd`, `systems/ship_style.gd`, `systems/decor.gd` |
| parts.json | part rarities and detector rules, one scheme for every planet | `autoload/Economy.gd` |
| achievements.json, steam.json | account-wide | `systems/achievements.gd`, `steam/steam_service.gd`, `tools/steam/export_steam_csv.py` |
| songs.json, radio.json | music catalogue | `systems/tunes.gd`, `systems/extras/radio.gd` |
| assets.json, preload_models.json | build and load lists | `tools/fetch_assets.py`, loader |
| solar_system.json, planets.json | the system and the campaign registry (left as told) | `systems/solar_system.gd`, `planet/planets/*`, `systems/world_look.gd`, `systems/homeward_director.gd`, `ui/*` |
| rockets.json, telescope.json, homeward.json, fabricator.json | travel between planets and cross-planet progress (parked in M1-08) | `automation/rocket_tiers.gd`, `systems/remote_progress.gd`, `systems/homeward.gd`, `robots/fabricator/bot_fabricator.gd` |
| cradle.json, world_looks.json, weekly.json | prestige mode, its world types and the weekly challenge (M1-08) | `systems/world_gen.gd`, `systems/world_look.gd`, `systems/extras/weekly.gd` |
| glim.json | the companion bot and its looks travel with Lumi | `systems/glim/glim.gd` |
| workbench.json | mixed, see below | `ui/bench_tiers.gd`, `ui/upgrades_screen.gd` |

## Not moved cleanly, and why
- **`workbench.json`** mixes global UI rules (when each workbench tab opens) with planet rows (`tiers` and `upgrade_order` list this planet's upgrade ids). Left whole in `data/`. Suggested follow-up: move `tiers` and `upgrade_order` into the planet's `upgrades` table.
- **`fabricator.json`** and **`telescope.json`** carry planet ids (`unlock_planet`, `planets_default`). They belong to the travel layer that M1-08 parks, so they stay global until then.
- **`codex.json`** has one cross-planet category (`homeward`); the file moved as a whole because every other category is keyed to this planet's ids.

## Files touched outside the task's list (each one because a moved file broke it, or the cache rule needed it)
- `autoload/Planets.gd` (1 line): `unregister()` now emits `current_changed` when it replaces the current planet. Without it Economy and the static loaders kept the removed planet's tables.
- `export_presets.cfg`: `planets/*/data/*.json` added to all six `include_filter` lines; exports would otherwise ship without the planet tables.
- `tools/extract_strings.py`: scans `data/` and every `planets/<id>/data/`, in file-name order so the catalog order does not change.
- `tests/`: 22 test files changed; they read moved tables through `Economy.planet_table`. Nothing under `planet/planets/*` and no row of `data/planets.json` was touched.

## Open points
- `locale/greenfall.pot` was already out of date before this task (`tools/extract_strings.py --check` fails on strings removed by earlier merges). It was not regenerated here; the next extraction will also rewrite the `#:` source references of the moved tables.
- About 60 comments in shared scripts, the `_doc` keys inside the tables and several docs still say `data/<file>.json` for moved files. Code paths are clean (the new test checks them); the comments were left because rewriting them would put a planet folder name into shared code, and the docs are outside this task.
- `music_set = "verdance"` in `planet.tres` and planet-name literals in shared code are M1-07.
- Originality: nothing in this task adds or changes player-facing content.

## Verification
- `tools/run_tests.sh`: 958 of 958 pass (953 before, 5 new in `tests/test_planets.gd`), save round trip and orbit reload pass.
- New tests: every registered table exists and parses; the planet's data folder and its table list agree and no copy is left in `data/`; `planet_table` returns a private copy; Economy and cached loaders follow a planet switch; no `.gd` outside `tests/`, `tools/`, `planets/`, `addons/` contains the planet's folder path or `res://data/<moved file>` (the list of moved files is read from the planet's data folder).
- Bot run `godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=600`: exit 0, no SCRIPT ERROR and no engine ERROR lines; objective `hex` done at 7.0 game-minutes (`hex2` 10.8, `hex3` 15.3, `robot` 21.8). The run's rewritten `screenshots/autoplay_*.json` were not committed.
- One of five exit checks printed the note "1 RID allocations of type DummyMesh were leaked at exit" (the check still passed; four other runs, before and after, were clean). It looks timing-dependent and was not chased here.
