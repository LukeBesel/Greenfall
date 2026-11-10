# M1-08: systems Planet 1 does not need are parked

Base commit `b928ead`. The running game is one planet with no campaign, travel layer, prestige mode, weekly seed, Museum, Telescope, Bot Fabricator or profile picker. Their code, data and tests are in `parked/` (Godot ignores the folder through `parked/.gdignore`; every export preset also excludes `parked/*`). `parked/README.md` lists each feature, what it did, what it depended on and how to bring it back.

## Numbers
- Parked: 62 files, about 12,470 lines (campaign 18 files / 4,203 lines, telescope 7 / 2,202, prestige 9 / 1,501, fabricator 5 / 646, museum 2 / 511, weekly 7 / 722, profiles 2 / 443, tests 11 / 2,001, plus the README and the parked achievements).
- Game code and data (everything except `tests/`, `tools/`, `docs/`, `parked/`): 10,601 lines removed, 398 added, 146 files touched.
- Tests and tools: 2,537 lines removed, 84 added. Unit tests: 958 before, 858 now (parked tests no longer run; 4 new old-save tests, 4 new or replaced tests for the kept halves).
- GDScript warnings (`tools/warnings_audit.sh`): 132, none in lines this task wrote (the count was not 0 before this task either).

## What replaced shared uses of a parked system
| Was | Now | Where |
|---|---|---|
| `Homeward.measure_current()` | `Restoration.value()`: `flags.core_charge`, 1.0 once `flags.cradle_returned`. No planet index, no planet name | new `systems/restoration.gd`; caller `tools/autoplay.gd` (the only caller left) |
| `Homeward.planet_def(...).id`, `CradleMode.current_world()`, `WorldLook.planet_id()` for "which planet is this" | `Planets.current_id()` | `planet/sky_director.gd`, `systems/solar_system.gd`, `scenes/slice_orbit.gd`, `tools/autoplay.gd` |
| `CradleMode.stat_mod()` in `Economy.stat` (Heirlooms x world modifiers x decor charm x nursery) | `Decor.stat_mult() * Nursery.stat_mult()` applied directly (the other two were 1.0 on Verdance) | `autoload/Economy.gd` |
| `CradleMode.day_speed()`, `CradleMode.event_weight()` | removed (1.0 without world modifiers) | `planet/sky_director.gd`, `systems/events.gd` |
| `CradleMode.unlocked()` in the Garden Mode unlock | `flags.bloom_finale_seen` | `systems/decor.gd` |
| `CradleMode.persist` | `PhotoAlbum`'s own `_persists()` (same rule: not under `--fresh` / `--nosave` unless `--save-dir`) | `systems/extras/album.gd` |
| `CradleMode.planet_mix()` | removed (empty on Verdance) | `core/save_orbit_migrate.gd` |
| `CradleMode.reset_all()` on New Game | `SaveManager.delete_save()` only (it was already called) | `ui/main_menu.gd` |
| `LateDirector` (Garden Mode + Ark Bridge + campaign + world look) | `GardenDirector`: the Garden Mode wiring only | new `systems/garden_director.gd`; `scenes/slice_orbit.gd`, `ui/late_menu.gd`, `tools/orbit_roundtrip.gd` |
| `Museum.exhibits / progress / filled / hint` in the Codex Collection page | `Exhibits` (the catalogue half of the Museum, pure helpers) | new `systems/exhibits.gd`; `ui/codex_screen.gd` |
| `Homeward.redirect_finale()` in `Bloom.play_finale` | the ark finale (`BloomFinale`) plays directly | `systems/bloom.gd` |
| `Homeward.cap_for(0)` on the Bloom Core | no cap | `story/core_charge.gd` |
| `Homeward.has_tech()` gate on research with `requires_tech` | no gate (prerequisites only) | `systems/research.gd`, `planet/frontiers.gd` |
| `Homeward.planet_name()` for a song's planet | the planet id, capitalised and translated (same text as before for all five ids) | `systems/tunes.gd` |
| `ShipTiers.drive_tier()` (loaded `systems/homeward.gd` by path) | removed; `look()` follows the in-planet rocket tier | `automation/ship_tiers.gd` |
| `WorldLook.current()` in the city and yard dressing | removed with the tint, bleach, drift and puddle factors it fed (all neutral on Verdance) | `planet/city_view.gd`, `planet/building_detail.gd`, `planet/street_dressing.gd` |

## Behaviour changes (all follow from removing a call into a parked system)
1. **The Bloom Core is no longer capped at 68% on Verdance.** The cap came from `data/homeward.json` (`needs_tech`: Deep Drill from Ochre, and so on). This is bug B1's cap. The ending is still not proven reachable: that is M1-10.
2. **Research nodes `dune_charts`, `thermal_lance`, `pump_works`, `ark_beacon` are no longer locked behind tech from later planets.** They open with their normal prerequisites. The `requires_tech` key in `research.json` is ignored.
3. **The Verdance Bloom plays the ark finale** instead of the campaign's "The Cradle Answers" cinematic.
4. **The Seed Ark loop is gone.** After the last Bloom milestone the hologram's milestone line is empty. The finale and credits still say the Seed Ark opens (see "story lines").
5. **The pause menu's Keepsakes entry is hidden until there is a keepsake** (CD player, album or nursery). Before, the Seed of the Week tab was always there, so the panel always had a tab. `ExtrasPanel.open_panel` also returns early with no tabs instead of indexing an empty list.
6. **Title screen:** Continue, New Game, Settings, Quit. No Profiles button, no world name in the Continue subtitle.
7. **Rocket list:** hubs on this globe only. No "Other planets", no "Launch home". The survey map has no "Solar system" button.
8. **Workbench:** no Fabricator category in Bots, no Telescope or Museum rows in Build.
9. **Codex:** categories with no entries are not shown (drops Homeward and Sightings). The Collection page says "In your collection" for a complete exhibit (the old line named the Museum) and no longer shows the Museum line or the four planet relics. Curiosities count 39, not 41: the two that only wait on a generated world are not listed.
10. **Achievements:** 108 to 88 (list below). Steam CSVs regenerated; Steam stat `ARK_WAVES` removed from `data/steam.json`.
11. **Dev flags removed** with their features: `--post-finale`, `--world`, `--heirlooms`, `--starseeds`, `--new-world`, `--sample-worlds`, `--open=ark`, `--planet-start`, `--orbit-home`, `--orbit-planet-hop`, `--orbit-sysmap`, `--soak-planet`, `--fabricator-build`, `--museum*`, `--scope*`, `--weekly`, `--menu=profiles|worlds`, `--all-tech`, `--drive`, `--home-ff`. The `DevHooks.gd` flag list was updated where it named them.

## Achievements removed (in `parked/achievements_parked.json`)
`museum_complete`, `ark_1`, `ark_10`, `late_bridge`, `late_world_1`, `late_world_3`, `late_heirloom_1`, `late_heirloom_20`, `late_starseeds_100`, `late_eggs_40` (needs 40 curiosities; 39 can be found), `late_older_pod`, `home_landed`, `home_planets_2`, `home_planets_4`, `home_planets_5`, `home_relics`, `home_drive_6`, `home_homecoming`, `extras_weekly_1`, `extras_weekly_4`.

## What stayed, and why
- **`systems/solar_system.gd` and `data/solar_system.json`.** They are the binary-star sky data, not the travel layer: `BinarySun` (Verdance's own sky), `CdFinds`, `PlanetGlobe` and the later planets' environment scripts read them. Only its `current_id()` changed (it asked Homeward).
- **`story/space_stage.gd`, `story/cradle_ship.gd`.** The intro, the 25% Bloom Core memory and the ark finale use them.
- **`planet/frontiers.gd` and the frontiers table.** Not a flat-only leftover: goals, research, the garden, the depot, the Codex and `CoreCharge.campaign_progress` read its rules for Verdance's own late districts. Its two Homeward lines are gone. `planet/frontier_view.gd` stays because `planet/planets/*` uses its names.
- **`ui/planet_globe.gd`, `ui/rocket_picker.gd`, `planet/sites/hub_hop.gd`, `automation/ship_*.gd`.** Used by the survey map, hub hops and the parked rocket on the pad. Their campaign parts were removed (the interplanet legs of `HubHop` are a snippet in `parked/campaign/`).
- **`planet/planets/*`, `data/planets.json`.** Left in place as the task says. Nothing in the game flow travels there; `--orbit-planet=<id>` (dev) still loads one.
- **`slice.launching`.** Nothing sets it now, but 10 scripts and 2 tests read it as "a launch owns the screen". Left for the ending work (M1-10) to reuse or remove.
- **`SaveManager` profile functions** (`profile_slot`, `read_profile_choice`, `set_profile`, `delete_profile`, `migrate_to_profiles`). Save paths are unchanged. The game still starts on the remembered profile (`profiles.cfg`, default 1); there is just no UI to change it. Left for M2-05.
- **Yard anchors named `telescope` and `fabricator`** (`planet/sites/verdance_site.gd`, `site_reach.gd`, `story/ledger.gd`, `story/first_seed.gd`). Empty slots in the yard layout now. They are layout data of Verdance's site script, which moves in a later task.
- **`data/currencies.json` "starseeds"** (rate 0): the legacy-currency rule that makes an old save's Starseeds load as nothing.
- **Prop builders for the two generated-world curiosities** in `story/egg_props_late.gd` (never called now).
- **`data/radio.json` and `data/songs.json`:** 11 radio songs unlock by landing on or building on a later planet, and 65 of the 88 CDs are found on later planets. Other-planet content, left for the planet-definition move.
- **Other-planet strings in `locale/*.po`.** Unused message ids are harmless; the next string extraction drops them (`tools/extract_strings.py` now skips `parked/`).

## Entangled with `planets/verdance/data/` (out of bounds for this task)
These table entries belong to parked features. The game skips them at load so nothing shows or stalls, but the tables should be cleaned:
- `builds.json`: `telescope`, `museum`, `bot_fabricator`. Skipped by `HubBuilds.ids()` (a build needs an owner: one of `SYSTEM_BUILDS` or a yard build definition).
- `goals.json`: 17 goals (`home_drive_5`, `home_land_1`, `home_restore_2`, `home_drive_6`, `home_restore_4`, `home_restore_5`, `home_drive_7`, `home_last_seed`, `home_launch`, `ark_1`, `ark_3`, `late_bridge`, `late_heirloom_1`, `late_ark_5`, `late_world_1`, `late_heirloom_10`, `late_world_2`). Without a filter the ordered chain would stall on them right after "Call the Cradle home". `Goals.playable()` drops goals whose stat is in the new `data/parked.json`. **This list and filter are a stopgap**: delete both when the goals are removed from the table. `tests/test_beat.gd` checks that nothing in the game writes a listed stat.
- `codex.json`: `homeward`, `sightings`. `museum.json`: four `relic` exhibits and the building's cost and position. `eggs.json`: `older_pod`, `heirloom_tin`. `bloom.json`: `seed_ark`. `wren_lines.json`: 37 pools only parked code triggers.
- `research.json`: **node `observatory` is still researchable and now unlocks nothing** (its only effect was the Telescope). This one is visible to the player and needs a data edit.

## Story lines that promise parked things (text left alone)
Still shown to the player:
- `story/bloom_finale.gd:21` (finale, WREN): "The seed bays are open. From now on every bloom, anywhere on Verdance, fills the next Seed Ark wave."
- `story/bloom_finale.gd:225` (toast after the finale): "The Cradle is home. The Seed Ark is open: every bloom on Verdance counts toward the next wave. Progress shows on the hologram (M)."
- `ui/credits_roll.gd:163` (credits): "Lumi is still out there, planting. The Seed Ark is open."
- `planets/verdance/data/research.json` node `observatory`: "Any base can build a Telescope (without it, from base level 4) and watch the crews on other worlds."
- `data/radio.json`: 11 locked-song hints ("Land on Ochre", "A base on Tidewell at level 3", and so on).
- `ui/codex_screen.gd:625`: the Collection page labels two exhibits "EVERY PLANET".

Not shown any more (only parked code triggered them): WREN pools `cradle_mode` ("There are other worlds out here, Lumi. Ruined ones. Waiting."), `new_world`, `home_arrive`, `home_half`, `home_restored`, `home_system_done` ("Five worlds. All of them green."), `home_rocket`, `home_last_seed`, `ark_wave`, `museum_complete`, `world_*`; Codex category Homeward ("Restore every world and launch home."); the 17 goals above.

The intro and the Bloom Core beats do not name another planet or promise travel. The 75% beat says "We're coming back for you", which the ark finale keeps.

## Old saves
`tests/test_parked_saves.gd` loads `tests/fixtures/saves/parked_v4/` (written by `tools/parked_save_fixture.gd` from a real Verdance globe save): a first slot with the parked features' flags, stats, finished goals, achievements, Codex keys, decor and hub state; a second planet's slot; a weekly run and its record; the prestige profile pointing at the second planet; a second save profile. It checks that the save loads, Verdance's progress is kept (cubes, hexes, upgrades, the globe's cells, Lumi's level), parked keys are carried untouched and nothing counts or builds them, saving writes only the first slot, and New Game deletes only the first slot.

The fixture exposed three counting bugs with such saves, fixed here: `Achievements.unlocked_count()` and `Codex.count()` counted ids the game no longer has, and `SteamService.sync_achievements()` pushed them to Steam.

A full boot from the fixture (`--save-dir` copy, bot for 2 game minutes) loaded the world, played on and printed no SCRIPT ERROR. The only new log line is the existing legacy-currency warning for `starseeds`.

Behaviour for a player whose prestige profile last pointed at another planet: the game opens Verdance (slot 0). The other slots and `profile.save` stay on disk, unread.

## Checks
- `grep` for every parked class name and data file outside `parked/`: only prose in planet tables and the "Homecoming" song and Codex names (command and output in the task report).
- `project.godot`: no `CradleBoot`.
- `tools/run_tests.sh`: unit tests and the save round trip pass (numbers in the task report).
- Bot: `godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=600`: no SCRIPT ERROR, objective `hex` done at 7.1 game minutes, 51 game minutes played. A shorter run on the final tree (`--quit-after=150`): no SCRIPT ERROR, `hex` at 7.4 minutes.

## Notes for the reviewer
- The baseline round trip failed once on this machine before any change (`orbit_hex_level_1: 1 -> 0`, a 1.4 s timer against a once-a-second sampler) and passed on every later run. It is a timing flake under load, not part of this task.
- `tests/test_achievements.gd::test_screen_builds_every_tab` prints two engine errors (`grab_focus` on a control that left the tree) whenever a slow test runs just before it. A 400 ms busy loop reproduces it. Not caused by this task; the suite still passes.
- `tools/extras_roundtrip.gd` was not called by anything (the save round trip stopped using it when the flat world went); it is parked with the weekly code it mostly covered.
- `docs/ARCHITECTURE.md`, `docs/FUTURE.md`, `docs/DECISIONS.md` and `CLAUDE.md` still describe parked features (M1-15 and the lead's docs).
