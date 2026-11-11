# M3-06: Research from field work, and tending

Nov 11 2026, on top of `e8eb066`. Spec: `docs/design/PLANET1_DESIGN.md` sections 5 and 6; `docs/TASKS.md` row M3-06. Rules: `systems/research.gd`, `systems/field_data.gd`, `plants/tending.gd`, `plants/garden.gd`, `plants/hex_levels.gd`, `core/offline.gd`. Data: `planets/verdance/data/research.json`, `hex_levels.json` (the regrowth table), `balance.json`. Tests: `tests/test_research.gd`, `tests/test_tending.gd`.

## What was built

- **Research costs stock and field data, not time.** A node's stock (cubes, or Parts where the data says) is paid once, when it is first started. Its field-data bar fills only from work: a cleaned hex (4), a hex stage 2 to 5 (1, 2, 3, 4), a mastery level (6), a find (5), a source step (10) and shutdown (30), a memory shard (5). Data multipliers: `data_gain` and `research_speed` (Soil Survey, Field Notebook, a worn set's buff).
- **One node active; switching keeps progress.** A node switched away from is "paused": it keeps its bar and its paid stock. Data earned with no node active, or past what the node needs, is banked; a node draws on the bank when started (design decision 16.10). There is no queue and no cancel/refund.
- **Time away adds no research.** Nothing runs on a clock and the offline jump emits no work events. The offline rate and the cap on time away are now planet data (`balance.offline`: 0.5, 8 h), not constants.
- **Tending.** One watering soaks every plant on the hex in front of Lumi for 180 s and grows each 0.3 of a stage at once (one burst per hex per 30 s). Thirsty plants grow at 0.25 instead of stopping. A planting action sets a patch of up to 6 plants within 4.5 m for one seed. Each hex stage has its own sound, burst and size from data, larger at higher stages, and its float text shows the field data it paid.
- **UI.** Each research card has a field-data bar on its bottom edge and reads "34 / 70 data" (or "Paused · ..."). The panel shows the bank and what earns it, with this planet's amounts. The bench list shows field data and what feeds the active node. A HUD strip under the mastery line shows "RESEARCH WIDE BEAM 34/45" with a bar and the last gain ticking ("+4"). If nothing is active it reads in amber "PICK A NODE · N DATA BANKED".
- **Old saves.** The running node keeps its share of the old clock as data put in. A node whose time was up is researched, as the old load did. Queued nodes stay paid with an empty bar. Fixture `tests/fixtures/saves/research_clock_v4.json`.
- **Bot.** Keeps one node running from the moment the Research tab opens. It switches only for an on-screen goal, picks a paused node before a new one, and buys a new one with spare cubes or when it costs no more than a fifth of what the card is saving for. It waters planted hexes whose burst is ready. Idle time is now counted only once research exists: the old ~880 s was mostly the 14 minutes before the Research Desk. The report adds `field_data_earned` and `field_data_banked`.
- **Simulator.** `tools/pace_sim` models field data: a bank, one active node, paid nodes free to resume, mastery and stage data, seeds by patch and the watering burst. Its report prints field data earned and banked.

## Numbers (city 1)

Data by tier: 25, 45, 70, 100, 140, 190 (frontier tiers 6 and 7: 320, 450). Stock is 0.3 of the M3-21 cube prices. The dearest city 1 price is 1,200 (Auto-Baler), under the 4,200 cap. Clean to growing (`test_tending`, no walking): 41 s with tending, 320 s planted and left dry.

## Measured

Two fresh bot runs, `--fresh --autoplay --time-scale=8 --quit-after=300` (about 26 game minutes). No SCRIPT ERROR. Seconds from control.

| | Run A | Run B |
|---|---|---|
| First hex | 55 | 58 |
| First robot | 496 (8.3 min) | 532 (8.9 min) |
| Research Desk | 875 | 833 |
| First research | 901 | 898 |
| Research idle, longest | 58 | 99 |
| Research idle, total | 95 | 116 |
| Nodes researched | 8 | 8 |
| Field data earned | 192 | 195 |
| Longest purchase wait, first 20 min | 152 | 113 |

The 152 s wait in run A falls between minutes 12 and 14.6, during the seed tin and before the Research Desk. That is the reward beat M3-21 accepted, and research is not open yet.

Simulator, 40 minutes: first hex 62 s, first robot 9.2 min, longest wait in 20 min 101 s, field data 364 earned. Against the base commit, `purchase_first_hour` improved from 381 s to 252 s and `mechanic_first_hour` from 1,341 s to 1,005 s. `goal_gap` went from 386 s to 464 s, starting at minute 31.5 (after city 1's first 20 minutes). All three checks already failed on the base commit.

Suite: 1,299 tests, all pass (GUT, with the round trip and two-process reload checks). Save round trip: 197 PASS, exit 0.

## Open calls

1. **Seeds, not actions, now limit the garden.** The seed tin gives one seed (the story's "one Maker seed"). A hex needs about three patches to be Planted and about six to be Growing. In 26 bot minutes no hex passed stage 1, the same as before this task. The seed supply (tin size, seed finds, bloom yield) goes to M3-12.
2. **Clean to growing is 41 s of tending without walking**, faster than "about 2 minutes". Walking and refills make up the rest in play. Slow it with `burst_stage` or `rewater_s` if a played run shows it too quick.
3. **Thirsty plants grow at a quarter rate**, so a Surge wave's push now also shows on dry plants (a `test_surge` assertion changed accordingly).
4. **Touched outside the named files:** `player/patch.gd` (planting and pouring call `Tending`), `autoload/EventBus.gd` (two signals), `ui/hud.gd` (one line), `ui/bench_lists.gd`, `scenes/slice.gd` (dev hooks), and the callers of the old offline constants.
