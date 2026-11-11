# M3-04: pollution kinds 2 to 5

Nov 11 2026, on top of `4aa3542`. Rules: `systems/pollution.gd`. Data: `planets/verdance/data/pollution.json` (table `pollution_kinds`; the `pollution` table is still the junk models). Formulas: `docs/PLANET_PLAYBOOK.md`, "Pollution kinds (M3-04)".

## 1. What was built

**One waste ledger per hex.** A hex still holds its city's `hex_work` units and is clean at 95% gone. Each kind owns a share of that ledger; litter has what the others leave. This keeps "a hex has a cube value" and the 95% rule as they were, and lets a hex hold several kinds (Old Capital has hexes with four).

| Kind | City (first) | How it is worked (`work`) | Lumi's gate | Robot | Share of a hex | Cube weight |
|---|---|---|---|---|---|---|
| `litter` | Old Town | loose pieces, scooped | none | cleaners | the rest | 1.0 |
| `wrecks` | Ironside | 4 big pieces (stove, air-con unit, tyre, TV, barrel, car shell), scooped in bites | Lift Strength 2 (`lift_class`) | cleaners | 0.40 | 0.9 |
| `slick` | Kettle Bay | the floating waste of a lake hex | Hover Jets (`hover_water`) | skimmers | the whole lake hex | 1.0 |
| `smog` | Highreach | no pieces: misted with the watering can | the garden tools (`seeds_unlocked`), water in the can | watering robot | 0.25 | 1.0 |
| `blight` | Lowmeadow | no pieces: cleansing plants set with the planter | the garden tools, 0.35 seeds a hex | planting robot (spends the seeds) | 0.30 | 1.1 |

- **Reused, not copied:** wrecks are ordinary pieces in the large size class, so the lift classes, bites, the chest and the bale press apply unchanged. Slick is the lake junk and the Skimmer that already existed. Smog and blight are worked with Lumi's existing watering can and planter (same keys, same tank, same seeds); what she takes streams into the chest and is baled like anything else. The watering and planting robots' existing jobs take the two kinds as extra work.
- **Held waste.** Smog and blight cannot be scooped. Their share is a floor under the hex's junk (`SphereCells.hold`) for cleaner robots, far crews and the offline jump, so those leave the hex dirty and stop looking for work there.
- **Payout.** A take pays the hex's plain share times the kind's weight over the hex's average weight. Hexes cleaned by hand in the tests pay their city's `hex_cubes` within 3% (litter, wrecks, smog, blight). Robots are paid nothing.
- **Events:** `pollution_cleared(kind, amount, by_player)` (robot work batched every 0.5 s) and `pollution_blocked(kind, cell_id)`.
- **Feedback:** the hex readout adds the kind and its tool ("HEX 40% CLEAR   SMOG  MIST IT WITH THE CAN", or "WRECKS  NEED LIFT STRENGTH 2" when the gate is not met); a scoop that meets a gated piece, or a hex with only held waste, floats the same line over it; a refused tool gives a toast. 14 new strings are in `locale/` (English only, untranslated in the six drafts).
- **A sixth kind from data:** `tests/fixtures/planets/testworld/data/pollution_kinds.json` adds `spores` (held, watering can, a flag gate, a seed cost, weight 2.0). No code names it.
- **Saves:** `orbit.pollution` keeps part-cleared held kinds and the cost owed. A save without it loads with every dirty hex holding its kinds in full; hexes already clean stay clean.

## 2. Where each kind is (`--fresh --district-stage=...`, the run prints these)

| City | Hexes | litter | wrecks | slick | smog | blight |
|---|---|---|---|---|---|---|
| Old Town | 127 | 126 | | | | |
| Ironside | 271 | 270 | 71 | | | |
| Kettle Bay | 469 | 373 | 94 | 95 | | |
| Highreach | 817 | 816 | 236 | **0** | 420 | |
| Lowmeadow | 1,261 | 1,260 | 257 | | 613 | 597 |
| Old Capital | 2,107 | 2,097 | 528 | 9 | 1,264 | 961 |

Measured against the data's density: wrecks 0.7 to 0.8 of 0.35, smog 0.9 to 1.1 of 0.55, blight 0.9 of 0.5 (patches make the density approximate).

## 3. Checks

- `tools/run_tests.sh`: 1,092 tests, 1,092 passing. 20 new in `tests/test_pollution.gd` (spawn, gate and payout for each kind, several kinds on one hex, robots, saving, the dummy planet's kind, a planet with no table).
- Save round trip and two-process reload: PASS (the pollution state is in the snapshot).
- City 1 bot, `--fresh --autoplay --time-scale=8 --quit-after=130`, twice, no script errors: first hex 55 s and 56 s after control (limit 90); first robot 8.9 and 9.4 minutes (limit 12). A test also checks that an Old Town hex is laid out piece for piece as before.
- `--district-stage` for all six cities: every city reaches stage 4.

## 4. Not verified, and faults found

- **No played run in cities 2 to 6.** Lumi misting smog, planting out blight and lifting wrecks are tested at rule level only; the scene wiring (`player/patch.gd`, `scenes/slice_orbit.gd`) for those was not exercised by a bot or by hand. No render was made.
- **Highreach lists slick and has no lake**, so it has none; Old Capital has 9 hexes. Either the lists or the cities' water need changing.
- **The dev stage flag broke on held kinds** (Highreach and Lowmeadow stayed at stage 0). Fixed: it now drops the hold first (`SphereCells.release_hold`).
- **Offline:** watering and planting robots do not clear smog or blight while the game is closed.
- **No in-world mark for smog or blight on a hex** (only the readout and prompts). The globe's hex outline is not drawn today, so there was nothing to tint.
- Running `tools/extract_strings.py` rewrites about 33,000 lines of `locale/` (the template was already out of date); I added the 14 strings by hand instead and did not regenerate `pseudo.po`.

## 5. Open design calls

1. **Wrecks gate is Lift Strength 2**, as the spec's example says, but that upgrade is sold in city 1 (the bot buys it at minute 7). Most players arrive in Ironside with the gate already met. A third lift level or the cutter would make it a real gate.
2. **Smog and blight are gated only by the garden tools**, which every player has by city 4. The spec names scrubber units and cleansing plants; a Mister upgrade or research would be the city's tool. Not added: new upgrades change the bench and the balance tables.
3. **Robots on wrecks:** any cleaner may take them. Mastery (M3-05) is where "only after Lumi has learnt it" belongs.
4. **Shares, densities, `robot_units` and water use are first values** for M3-12. Smog and blight thin the loose junk on their hexes (the hex's work is unchanged), so cities 4 to 6 have less to scoop and more to mist or plant than the accepted simulation assumed.
5. **Every kind ends in the chest** (the proposal's note), including smog and blight residue. If the lead would rather they pay as field work, it is one function (`Patch._work_held`).

## 6. Files outside the task's list, and why

`planet/sphere/sphere_cells.gd` (the hold), `planet/orbit/sphere_field.gd` (piece kinds, heavy pieces, held takes), `core/sphere_offline.gd`, `planet/orbit/orbit_crews.gd`, `robots/sphere/sphere_crew.gd` (workers respect the hold; the two tending roles take held kinds), `player/patch.gd` (tools, payout weight, hint), `scenes/slice_orbit.gd`, `scenes/slice.gd` (wiring, save), `ui/hud.gd` (readout), `autoload/EventBus.gd` (two signals), `core/planet_definition.gd` (table name), `systems/districts_dev.gd` (the fix above), `tools/orbit_roundtrip.gd` (snapshot), `docs/PLANET_PLAYBOOK.md`. Nothing under `planets/verdance/sites/` was touched.

Originality: nothing here was modelled on another game; the kinds and tools come from the cleanup theme.
