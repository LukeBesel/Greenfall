# M3-22: a field bench at every city's base, faster rocket cells (Nov 12)

Follows `docs/DECISIONS.md` "After the full-planet bot" (M3-11's cadence breaks: nothing could be
bought or researched away from the start yard, purchases came in bursts every 15 to 20 minutes,
the rocket's cells took 300 s after every hop).

## What was built

| Area | What it does | Where |
|---|---|---|
| Rules | Every city Lumi has reached, other than the start one, offers a field bench: a packed kit on its site's bench anchor by the landing pad. E sets it up for the data's cost (free now). A bench that is set up is the whole workbench: upgrades, rigs, research, robot building, the Assembler's mix. The start yard keeps the Locker, the yard builds and the Assembler building itself (the Build tab says "Build it at the start yard's workbench."). Saved (`field_benches` in the planet section); a save from before has a bench in every city it had reached. Emits `EventBus.field_bench_set_up` | `systems/camp/field_benches.gd` |
| World | The kit and the bench on the city's prefab (rebuilt when the site streams back in), a reach point carrying the Interactables entry ("E   Set up the field bench" / "E   Open the field bench"), a toast on arrival, the set-up moment (dust, sparkle, the bench rises, lights flicker on). `nearest(pos)` for guidance | `systems/camp/field_bench_sites.gd` |
| Look | A smaller salvaged bench under a sloping tarp on two poles, in each city's own colours (`camp.json` `field_bench.looks`): Ironside yellow frame, blue panels, orange tarp; Kettle Bay navy, cream and red; Highreach cyan, violet and magenta; and so on. Packed: a strapped crate, rolled tarp, folded legs, pennant and a cyan beacon | `systems/camp/field_bench_model.gd` |
| Slice | `near_bench()` counts a set-up field bench; `nearest_bench_position()` is where the beam points (`Objectives._bench_pos`) and where robots built at the bench are set down; robots built there join that city's base (the chain's `work_hub` is the city Lumi is in) | `scenes/slice_orbit.gd`, `scenes/slice.gd`, `story/objectives.gd` |
| Rocket cells | Mk I recharges in 30 s (was 300), Mk II 15, Mk III 8, Mk IV none (`data/rockets.json`). Lumi's own work in the rocket's city (cleaning, pressing, planting, watering) keeps her "working" for 3 s; while working the cells gain 1 extra second a second, and a pressed bale adds 3 s. A toast says when the cells are full | `automation/rocket_charge.gd`, `automation/rocket_tiers.gd` `charge_by`, `planet/sites/orbit_sites.gd` |
| Bot | Uses the nearest bench (walks up to it, sets the kit up, shops there); away it flies home only for the Assembler (and, on a planet without field benches, for a tool or shopping as before). Yard purchases (tower, stations, scrubbers, compost press, Glim, the Assembler) only at the start bench. Reports `hop_cells_wait_max_s` and `field_benches` | `tools/autoplay.gd`, `tools/autoplay_travel.gd` |
| Fix | `SiteManager.set_level` / `_on_hub0_level` cast a freed `StreetPower` when a base level was bought while the start site was unloaded (now possible at a field bench) | `planet/sites/site_manager.gd` |

The bot does not use the Locker, so "fly home for the Locker" has no bot rule.

## Bot results

Three staged runs, time-scale 8, `--save-dir=m322`.

**A. City 1, fresh, no flags** (`--fresh --autoplay --game-minutes=55`): control at 1.1 min, first
hex at 2.0 (54 s after control, target under 90 s), longest purchase wait in the first 20 minutes
144 s, Old Town stage 1 at 51.8 (M3-11: 51.5), 51 purchases, longest research idle 194 s.
**First robot at 14.5 min played (13.4 after control): misses the minute-12 target.** Nothing in
this task changes city 1 (no field bench there; the bot's bench and shopping code take the old
path at home), and M3-21 measured 8.0 to 12.0 minutes on one build; this run's hexes were slow
(4 hexes from minute 7.7 to 13). See the second run below.

**B. Dev start in Ironside** (A's save, `--district-stage=old_town:5`, 60 game minutes): the bot
flew at 56.5, landed at 57.1, set the field bench up at 57.2 and stayed in Ironside to the end
with no trip home. **C.** (B's save, `--district-stage=old_town:5,scrapyard:4 --give-parts=800
--give=5000`, 25 game minutes): Ironside's job, the hop to Kettle Bay, the trip home for the
Assembler and back, Kettle Bay's bench.

| | M3-11 | M3-22 |
|---|---|---|
| Ironside purchases | 174 in 266 min, in bursts at home trips | 45 in 61 min (base level 5, 16 robots, upgrades), all at the field bench |
| Ironside longest wait between purchases | 1,254 s | 395 s |
| Research started away from home | none | 6 in Ironside (recycler, auto_sort, silt_filters, pollinator_survey, bale_tuning, multibot_blueprint), 3 in Kettle Bay |
| Trips home | every 15 to 20 min (shopping, tools) | 1, for the Assembler: left Kettle Bay at 119.2, built it, flew back at 120.0 |
| Kettle Bay longest wait | 3,460 s | 510 s (82 purchases in 18 min) |
| Hop waits on the cells | 300 s after every hop | longest 0 s over 3 hops (`hop_cells_wait_max_s`) |
| Field bench set up after arrival | | Ironside 6 s, Kettle Bay 90 s (the Assembler trip came first) |

Notes, honestly: the hop-wait figure is helped by the time-scale-8 load frames (a 2 s frame at
x8 is 16 game seconds), but even unhelped the wait is at most 30 s against 300. Research still
idled for up to 19 minutes in Ironside (minutes 82 to 101): every node left cost more cubes than
Ironside's income gave (cubes held peaked at 1,966). That is M3-12's economy, not a missing bench.

Errors: B43 (`Camp._apply_builds` on freed yard models) fired once in B, when a base level was
bought at the field bench while the start site was unloaded; B41/B43/B44 belong to the other
bug-fix task. The two `SiteManager` freed-object errors the same purchase raised are fixed here.

## Render

`screenshots/field_bench/ironside.png` (opengl3, 960x540, `--fresh --district-stage=old_town:4
--orbit-hop=7 --field-bench-shot=2.4`): the Ironside bench reads at a glance, bright yellow frame,
blue panels, an orange tarp, Lumi in front. Weak points: the city's junk lies right up to the bench
(the start yard keeps its ground clear; city pads do not), and at this distance the pegboard
detail is lost.

## Tests

- New `tests/test_field_benches.gd` (13): no bench in the start city (first and dummy planet);
  a kit once a city is reached, on its own site; setting up pays the data cost once and emits
  once; a priced bench waits for its price; save and load; an old save gets benches in every city
  reached (both planets); each city's colours; Mk I cells in 30 s; `charge_by` never past full;
  work in the rocket's city charges faster, a bale adds a lump; robots' work and another city do
  not; the bot flies home only for the Assembler where a bench stands; the bot's longest cell wait.
- Round trip: new check `orbit_field_bench_kept`.
- Suite: see the commit that adds this review.

## Open calls

- Field bench cost is free (`cost: {}`); the lead may want a small price as a moment.
- Base level is bought at a field bench (it is a number and the crew's cap); every yard build is
  not. Change in `HubBuilds.entry` if the lead wants the base level home-only too.
- City pads keep their junk round the bench (no keep-out like the start yard).
- New player-facing strings (7) and the Mk III description change need translations.
- Originality: the bench-under-a-tarp and the crate kit come from Greenfall's salvage theme; nothing
  here felt close to another game.
