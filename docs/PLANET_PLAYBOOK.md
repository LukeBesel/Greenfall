# Planet playbook

A living guide for building every planet after the first. Updated at the end of each milestone. It records how to make a planet, what made Planet 1 work, what failed and how it was fixed, the balance rules, and the checklists and templates.

Status: started in Phase 0 (Nov 9, 2026). Sections marked *(fills in during Mx)* are placeholders for knowledge that does not exist yet; everything else is current.

## 1. How to create a new planet *(steps become exact in M1; this is the target)*
1. Copy `planets/_template/` to `planets/<id>/`. Ids are lowercase, one word, and never change after release.
2. Fill in `planet.tres` (the PlanetDefinition): display name, globe spec (size, site count), target playtime, palette, music set.
3. Fill in the data tables in `planets/<id>/data/`:
   - `districts.json`: the chapters, their order and unlock rules
   - `pollution.json`: pollution kinds, the tool each needs, payouts
   - `upgrades.json`, `rigs.json`, `research.json`: the upgrade tree
   - `regrowth.json`: regrowth stages and their rewards
   - `restoration.json`: how district states add up to planet restoration, and what triggers the ending
   - `tutorial.json`, `goals.json`: onboarding steps and the goal ladder
   - `balance.json`: curves and constants
4. Add art hooks only if needed: `env.gd` (sky, light, weather) and site scripts for the planet's own props. Shared systems call them through the definition.
5. Run the simulator (`tools/pace_sim`) until the cadence rules pass.
6. Run the planet-parameterised tests and the bot on the new id.
7. Play it. Then run the engagement review.

A new planet should need no change outside its folder. If it does, the shared system is missing a data field: add the field, do not add a branch.

### What a planet folder holds today (M1-07)
`Planets` registers every `planets/<id>/planet.tres` at start. `shipped = false` keeps a planet out of the game but loadable by id (tests, and the dev flag `--orbit-planet=<id>`). Five are registered: the first planet ships; four later ones are parked as data (their READMEs say what they inherit).

| In the definition | What it is for | Read by |
|---|---|---|
| `id`, `display_name`, `tagline`, `order`, `shipped` | Identity. Text takes the name through `name_in("... {planet} ...")` | `Planets`, HUD, story text |
| `globe_frequency`, `hub_count`, `world_seed` | Globe size (10 m cells, radius 14.375 m per unit of frequency), number of hub sites, seed: `globe_spec()` | `OrbitPlanet`, `SphereOffline` |
| `tables` | Table name to JSON file. Five are required; the rest are optional | `Economy.planet_table(name)` |
| `tables["look"]` | Sky, fog, sun, ambient, palette, junk tint (the env script's values), `globe` (the map globe) and `orbit` (place round the binary star) | the env script, `PlanetGlobe`, `SolarSystem` |
| `tables["sites"]` | The hub and landmark site list, plus `hub_pad_m`, `fill_pad`, `yard_keep_out` | `SiteBuilders`, `OrbitPlanet` |
| `sites_script` | Static hooks that build the sites: `build_site` (or `build_async` / `build` / `place`), optional `restyle_site`, `build_surroundings` | `SiteBuilders` only |
| `env_script` | Static hooks for the planet's own environment art: `dev_hub`, `prepare_field`, `dress_view`, `apply` | `PlanetDefinition.call_env` only |
| `globe_shader` | Surface shader of the map globe (empty: the shared rocky world) | `PlanetGlobe` |
| `music_set` | One of `MusicTracks.SETS`: tracks, instruments and ambience bed | `Audio` |

A site script that is a town on a street grid extends the shared `TownSite` (`planet/sites/town_site.gd`), so the garden, street power and outposts can read its streets without knowing the planet. A planet with no sites table gets a bare pad with the shared yard anchors (`SitePrefab.START_YARD_ANCHORS`).

Two tests hold the rule: `tests/test_planets.gd` fails when a shared script quotes a planet id or a planet folder, and `tests/test_planet_reuse.gd` builds, runs, saves and loads the world on the dummy planet in `tests/fixtures/planets/testworld/` (five small tables, one site, one 18-line sites script).

## 2. What made Planet 1 addictive *(fills in during M3-M6)*
Design intent, to be confirmed by measurement:
- A win every 20-40 seconds and a purchase within 3 minutes, at every stage.
- Hexes sized to finish in 1-3 minutes by hand early on.
- One new pollution kind and one new tool per district, with a power spike that at least doubles cleaning rate.
- Hand work stays above 30% of output: robots copy what the player has mastered.
- The planet itself shows progress; the player can always see what they changed.

## 3. What did not work and how it was fixed
| Problem (found Nov 9, before the redesign) | Evidence | Fix (task) |
|---|---|---|
| The first hour was slow and empty | First hex at 7.5 bot-minutes, then one every 6; gaps of 20, 16 and 32 minutes with no goal; 74 hexes after 100 bot-minutes | Faster hands, districts, goal ladder (M3-02, M3-03, M3-10) |
| The planet could not be finished | No code path set the restored state; restoration capped at 68% pending later planets | Restoration model and ending owned by the planet's data (M1-10) |
| Progress was shown as a planet percentage with four decimals | HUD read "0.0000%" after minutes of work | District-level progress readout (M3-03) |
| Waiting on timers stood in for play | Research cost real time; the garden was slow on purpose | Work-driven research and tending (M3-06) |
| Planet logic was hardcoded | 200 planet-name literals; index branches; global data files | PlanetDefinition and per-planet folders (M1-03 to M1-07) |
| Two world modes doubled every system | 78 flat-or-globe branches | Remove the flat world (M1-04) |
| Tuning needed a 30-minute bot run per game hour | Bot wall-clock times | Fast simulator on the same data (M1-12) |
| Breadth came before a fun core | Five planets and a prestige mode while pillars 2 and 4 failed | Park everything Planet 1 does not need (M1-08) |

## 4. Balance rules of thumb
Targets, to be replaced by measured values as milestones land.

| Rule | Target |
|---|---|
| Playtime to a planet's ending (first-time player) | about 4 h for Planet 1; later planets set theirs in the definition |
| Bot-to-player speed | bot is about 2x faster |
| First payout / first upgrade / first clean hex | 20 s / 90 s / 3 min |
| Small win interval | 40 s or less |
| Affordable purchase interval | 3 min or less in the first hour, 4 min after |
| Longest gap between goals | 4 min |
| New mechanic | every 10-15 min in the first hour, every 30-40 min after |
| Power spike | every 30-40 min, at least 2x cleaning rate |
| Hand share of output | 30% or more at all times |
| Offline bonus | capped; never more than a few minutes of active play |

**Cost curves:** inside a district, a track's cost grows by a fixed ratio per level, tuned so the time to the next level rises about 10-15% each step. A new district starts a new tier: income jumps, the first purchases are quick, then the curve climbs again. *(Exact formulas and ratios are documented here in M3-01 and M3-12.)*

## 5. Checklists

**New planet setup**
- [ ] Folder copied from the template; id chosen
- [ ] Definition validates (`Planets` reports no errors)
- [ ] Every data table has a `_doc` and passes the schema test
- [ ] Simulator meets the cadence rules
- [ ] No change outside `planets/<id>/`

**Testing**
- [ ] Planet-parameterised tests pass on the new id
- [ ] Bot plays start to ending with no stall over 4 minutes
- [ ] Save round trip and old-save migration pass
- [ ] Out-of-order tutorial test passes

**Polish**
- [ ] Every district has distinct polluted and restored looks, readable from 30 m
- [ ] Every core action has sound, motion and a number
- [ ] Ending sequence and end screen in place
- [ ] Engagement review has no flag above minor
- [ ] Originality checklist passes

**Release**
- [ ] Performance budgets met on every preset
- [ ] Translations complete for shipped languages
- [ ] Credits and version updated

## 6. Templates *(created in M1 and M8)*
- `planets/_template/planet.tres`: PlanetDefinition with every field and comments
- `planets/_template/data/*.json`: each table with a `_doc` and one example row
- Tutorial step: `{id, trigger, text, pointer, done_when, skip_if}`
- Upgrade track: `{id, stat, base_cost, cost_ratio, max, tier, requires}`
- Planet test case: `tests/planet_case.gd`, a base class that takes a planet id
