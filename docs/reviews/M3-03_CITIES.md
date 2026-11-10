# M3-03 and M1-10: cities as chapters, the launch point as the ending

What was built for tasks M3-03 (districts) and M1-10 (restoration model and ending hook), the data shapes, the decisions taken where the spec left a choice, and what did not fit the code. Logic and data only; the HUD line and the end screen are minimal and wait for their own tasks.

## 1. What exists now

| Piece | File | Job |
|---|---|---|
| Districts | `systems/districts.gd` | Hex set per district, counts per regrowth stage, district stage and share, unlock rules, the player's district, the travel rule, save and load |
| Restoration | `systems/restoration.gd` | Launch progress, the launch rule (`launch_ready` once), whole-planet share and its named steps (`planet_restored`), `Restoration.value()` and `Restoration.measure()` |
| Ending | `story/planet_ending.gd` | On `launch_ready`: waits for a quiet moment, plays the planet's sequence, rolls the credits once, opens the end screen |
| End screen | `ui/end_screen.gd` | Title, time played, hexes cleaned, cities restored, robots built, "Keep playing", "Quit to title" |
| Dev flags | `systems/districts_dev.gd` | `--district-stage=<id>:<stage>[,...]` and `--launch-ready[=S]` |
| Data | `planets/verdance/data/districts.json`, `restoration.json` | Registered in `planet.tres` as tables `districts` and `restoration` |
| Tests | `tests/test_districts.gd`, `tests/test_restoration.gd`, `tests/support/district_fixture.gd`, `tests/fixtures/saves/pre_districts_cells.json` | 36 tests, most run on the first planet, the dummy planet and a parked planet; `tests/test_planet_reuse.gd` also builds the real world on the dummy planet and on a parked planet |

Signals added to `EventBus`: `district_unlocked(id)`, `district_stage_changed(id, stage)`, `district_entered(id)`, `planet_restoration_changed(value)`, `launch_ready(planet_id)`, `planet_restored(planet_id)`, and two the spec did not list: `planet_step_reached(planet_id, step_id)` and `ending_shown(planet_id)`.

## 2. Data shapes

`districts` table:

```json
{"stage_share": 0.8, "open_ground_rings": 18, "open_ground_travel": "all_unlocked",
 "districts": [
  {"id": "old_town", "name": "Old Town", "site": 0, "rings": 6, "pollution": ["litter"], "unlock": {"type": "start"}},
  {"id": "scrapyard", "name": "Ironside", "site": 7, "rings": 9, "pollution": ["litter", "wrecks"],
   "unlock": {"type": "district_stage", "district": "old_town", "stage": 4}}
 ]}
```

| # | id | Name | Site | Rings | Hexes |
|---|---|---|---|---|---|
| 1 | `old_town` | Old Town | 0 | 6 | 127 |
| 2 | `scrapyard` | Ironside | 7 | 9 | 271 |
| 3 | `kettle_bay` | Kettle Bay | 3 | 12 | 469 |
| 4 | `highreach` | Highreach | 8 | 16 | 817 |
| 5 | `lowmeadow` | Lowmeadow | 9 | 20 | 1,261 |
| 6 | `old_capital` | Old Capital | 1 | 26 | 2,107 |

5,052 hexes in all. Rings, the stage share and the unlock stage are the accepted proposal's; sites and names are the world audit's (section 10.1).

`restoration` table:

```json
{"stage_values": [0, 0.25, 0.45, 0.65, 0.85, 1.0],
 "launch": {"when": "all_districts_stage", "stage": 5, "sequence": "bloom"},
 "planet": {"measure": "cell_share_restored", "check_s": 2.0,
  "steps": [{"id": "first_green", "name": "First green", "share": 0.01}, "... 0.05, 0.25, 0.5, 1.0"]}}
```

Save: two keys in the planet's section (`GameState.orbit`): `districts` = `{stages: {id: n}, unlocked: [ids], visited: [ids], focus: id}` and `restoration` = `{launched, ending_seen, restored, steps: [ids]}`. No migration step is needed: a save without them loads and the state is derived (section 4).

## 3. Rules as built

- **A hex's stage** is its regrowth level (`SphereCells.level`, written from `HexLevels`), and at least 1 once its pollution is gone. Water and hub ground (the yard, hexes under buildings) are not land and are never counted.
- **A district's stage** is the highest stage that at least `stage_share` of its land hexes have reached. The share shown is hexes at the next stage or above over the hexes needed. The stage never drops; ground dirtied again lowers the share only.
- **Counts are incremental.** Districts listen to `SphereCells.cell_changed`: one dictionary lookup per changed hex. The task named `hex_cleaned` and the hex-level events; `cell_changed` was used instead because the crew, the offline jump, hub footprints and the Ledger's dumps change hexes without those events, and every one of them goes through `SphereCells`. The hex-level event still drives it (it writes the level into the cells).
- **Unlock** rules are data: `start`, or `district_stage` (another district at a stage). The named district must be unlocked itself, so chapters open in order even if the player works ahead on foot.
- **`district_entered`** fires once per save per district, the first time the player stands in it while it is unlocked (or the moment it unlocks under the player). Districts open from the start are not arrivals.
- **Launch progress** = mean of the districts' values. `launch_ready` fires once per save; a save that already meets the rule but has no restoration state fires on its first check.
- **Whole-planet share** = land hexes that are not junk over all land hexes, from two native byte counts (cheap on any globe). Steps and `planet_restored` are checked every `check_s`.
- **Travel:** the rocket's list offers unlocked cities only; open-ground sites appear once every city is unlocked (`open_ground_travel`, default `all_unlocked`). With nowhere to fly, the list says what opens the next city. The rocket now also appears once a second district is unlocked, not only at base level 5: otherwise city 2 could open with no way to reach it.
- **Ending:** `launch_ready` → cinematic named by `launch.sequence` (`bloom` = `story/bloom_finale.gd`) → credits (once per profile) → end screen. "Ending seen" is saved when the end screen opens; a save that quit before then plays the ending again. The old triggers are gone: the Bloom finale milestone and `cradle_district_complete` no longer start the cinematic (`systems/bloom.gd`).

## 4. Planets without a districts table

Decision: **one district**. A planet with no `districts` table plays as a single district: its start site, named after the planet, 18 rings (the size every hub region had before), unlocked from the start. Every other site is open ground and the rocket may fly to all of them, as before. With no `restoration` table the stage values are even steps, the launch rule is "every district at the last stage", there is no cinematic and there are no named steps. So the four parked planets and the dummy planet have a readout and an ending with no data, and no shared system needs a "no districts" branch. Tested on the dummy planet and on Ochre.

## 5. What did not fit, and what was done

1. **District ids.** The proposal's ids 3 to 6 are marked as working names. Ids here follow the audit's city names (`kettle_bay`, `highreach`, `lowmeadow`, `old_capital`); `old_town` and `scrapyard` are kept. The simulator's proposal files still use the working ids (`tools/pace_sim` was off limits): they must be aligned before the simulator reads game data.
2. **Site indices.** The proposal lists sites 0 to 5; the task and the audit say 0, 7, 3, 8, 9, 1. The audit's are used.
3. **Pollution lists.** Taken from the proposal (accepted numbers). The audit's table lists fewer kinds per city (for example Kettle Bay: litter, slick). The lead should pick one.
4. **The rocket in the launch rule.** The proposal's `launch.rocket` (six parts built in city 6) is not in the table: nothing reads it yet (M3-07). The rule today is only "all cities at stage 5".
5. **`REGION_RINGS` had other users.** Shards, the hub frame's systems (fauna, eggs, outposts, Ledger), the round-trip tool and the bot used it as "the ground round a hub". Shrinking that to 6 rings would have moved saved content and starved the bot, so they now use `HubFrame.AREA_RINGS` (18, the old value). Only the regions themselves follow the districts.
6. **The finale's length.** The acceptance run (`--launch-ready=20 --quit-after=60`) cannot fit a 42 s cinematic plus credits. Under `--launch-ready` the ending plays at 3x and skips the credits; the flag counts wall-clock seconds from process start, like `--quit-after`.
7. **The finale's story.** `story/bloom_finale.gd` still tells the ark's arrival and ends with a line about the Seed Ark. It now belongs to the launch point but its words do not match (M5-08).
8. **Old ending content left in data.** `goals.json` still has the Cradle goals and `bloom.json` a milestone flagged `finale`; they pay but end nothing. One WREN line in `objectives.json` still says the Bloom Core brings the Cradle down. These are the objective chain's (M3-10).
9. **Goals and objectives.** No goal or objective in the data measured planet % or the Bloom Core, so nothing was repointed. Three measure types were added for the chain to use: `launch`, `city_stage`, `cities_restored` (`Restoration.measure`).
10. **Translations.** The new strings go through `tr()` but are not in `locale/`: `tools/extract_strings.py` was already out of date before this task and running it pulls in about 200 untranslated strings from earlier work, which fails the 5% rule in `tests/test_l10n.gd`. Left for a translation pass.
11. **Can every land hex reach stage 5?** A hex needs plant slots to pass stage 1. If some land hexes of a city can never be planted, more than 20% of them would make stage 5 unreachable. Not checked here; the bot task (M3-11) should.
12. **Old Town is 41% water** in rings 1 to 6 (audit section 4), so city 1 has 73 land hexes on the built globe, not 127 (measured with `--district-stage=old_town:4`).
13. **The bot on a parked planet** already fails before this task (no robots table: `fleet.gd` build cost). The parked planet was checked by loading it without the bot and driving its district to the launch point with `--district-stage`.

## 6. How to check

- `tools/run_tests.sh`
- `godot --headless --path . -- --fresh --no-intro --launch-ready=20 --quit-after=60` logs `[restoration] launch_ready`, `[ending] sequence 'bloom' starting`, `[ending] end screen open`, once each.
- `godot --headless --path . -- --fresh --no-intro --district-stage=old_town:4 --orbit-rocket-open=8 --quit-after=20` unlocks the second city and prints the rocket's list.
- `godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=600`: each `[Autoplay]` line shows `city=`, `stage=`, `share=` and `launch=`.
