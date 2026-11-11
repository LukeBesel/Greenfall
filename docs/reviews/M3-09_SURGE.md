# M3-09: Surge

Nov 11 2026, on top of `01009d6`. Spec: `docs/design/PLANET1_DESIGN.md` section 8; `docs/DECISIONS.md` "Mastery" (Surge is one of the ways Lumi's hands stay needed). Rules: `core/surge_rules.gd`. State: `systems/surge.gd`. Look and sound: `art/surge_fx.gd`, `art/shaders/surge_edge.gdshader`. Data: `planets/verdance/data/balance.json` (new `balance` table). Gauge: `ui/hotbar.gd`. Bot: `tools/autoplay_surge.gd`. Formulas: `docs/PLANET_PLAYBOOK.md`, "Surge (M3-09)". Tests: `tests/test_surge.gd`.

## 1. What was built

- **Charge.** Only Lumi's own work fills the Bloom Core: waste she clears herself (every pollution kind, pieces and held kinds alike), bales she presses, seeds she plants and pours that reach a plant. Robots add nothing. Standing still adds nothing. Time away adds nothing (the save holds a charge and no clock). Work during a Surge does not charge the next.
- **Release.** Keyboard **R** (new action `surge`, rebindable). Controller: **both zoom buttons together** (LB + RB), because every single pad button already has a job. The gauge shows the key on a plate when the core is full, and the first three charges also say it in a message line.
- **The burst.** 12 seconds. Sweeps a second x1.8, waste per sweep x1.8, sweep width x1.7, reach x1.3. Waste swept in a Surge packs tight in the chest, so the chest fills no faster than in plain sweeping and the burst is spent sweeping, not walking to the bin. Cube value is unchanged (a hex pays what a hex pays).
- **Growth wave.** From city 4, the release waters every plant within 2 rings of Lumi (3 in city 6) and pushes each on by one growth stage.
- **Scaling by district.** The charge needed is set per city; every multiplier's part above 1 grows 6% per city.
- **Saved** with the planet (`orbit.surge.charge`). A Surge cut short by a save is over on load.
- **The bot** lets a full core go when it is sweeping waste in reach with the chest under half full.
- **Feel.** On release: a column of green light, three rings (cyan, green, gold) racing out over the ground, sparkles, charge-up and fanfare, a camera shake, pad rumble, the screen's edge lit with moving rays (light added, never a dark vignette), Lumi's core glowing hard, "SURGE x3.2" over her. While it runs: a sparkle trail, a ground ring at the sweep's width, the gauge and the edge glow draining, ticks over the last three seconds. At the end: a vent of steam and the core back to its own glow. With a wave: a green front sweeps out as far as the wave reached. Reduced motion stills the rays and drops the flash; shake follows the Shake setting.
- **Gauge.** The Bloom Core ring by the level bar keeps the story charge as its inner ring. Its new outer arc is the Surge: cyan while filling, a green full ring with the key plate when ready, a gold arc counting down while it runs.

## 2. Numbers (first planet)

| | City 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| Units of hand work for a charge | 420 | 1,500 | 1,500 | 2,400 | 4,000 | 12,000 |
| Output during a Surge | 3.24x | 3.42x | 3.59x | 3.78x | 3.97x | 4.16x |
| Growth wave, rings | none | none | none | 2 | 2 | 3 |

Other numbers: a bale 2% of a charge, a seed 0.4%, a pour 0.12%; the core cannot fill in under 100 seconds of work; chest fills at 0.4 of the plain rate during a Surge.

City 1's 420 units is fitted to the bot (first Surge about minute 4). Cities 2 to 6 are about four minutes of Lumi's hand rate from the pacing table in spec section 12, not yet played: they need the balance pass (M3-12).

## 3. Measured

**Output (test `test_measured_sweep_output_is_at_least_three_times_for_the_whole_surge`).** A real Lumi sweeps a real field for 12 seconds with waste always in reach and the chest emptied as it fills: 55.3 units plain, 192.4 units in a Surge, **3.48x**. The rules state 3.24x; the measured figure is higher because plain sweeping loses about 6% to frame rounding (see open call 4). After the Surge the sweep is the plain one again.

**City 1 bot**, `godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=150`, seconds from the moment the bot takes control:

| Run | First hex | First Surge | First robot | Surges in 20 min | Longest purchase gap |
|---|---|---|---|---|---|
| Before (`01009d6`), one run | 52 s | none | 582 s (9.7 min) | 0 | 138 s |
| Surge, run 1 | 50 s | 231 s (3.9 min) | 449 s (7.5 min) | 4 | 118 s |
| Surge, run 2 | 57 s | 302 s (5.0 min) | 523 s (8.7 min) | 4 | 157 s |

- First hex is unchanged (the first Surge comes after it) and stays above 45 s.
- First robot is inside the M3-21 target (minute 12) and 1 to 2 minutes earlier than the one run before. Bot runs differ by about a minute on their own (M3-21 saw 8.5 to 9.7), so part of this is the Surge and part is spread.
- Later Surges came 2.4 to 4 minutes apart.
- Run 2's 157 s purchase gap is at minutes 11 to 13.6, after the first robot. The run before the Surge has a 139 s gap in the same stretch, so this is not new, but it is over the 136 s limit and worth a look in M3-12.

## 4. Open calls

1. **Surge is on from the start of city 1** (as this task asks: first Surge about minute 4). Spec decision 16.13 reads "Surge unlocks with its growth wave in city 4" and the accepted proposal gates it behind a city 3 research (`surge_core`). Built: the Surge from the start, the wave from city 4. If the lead wants the later unlock, it is one gate in `Surge.enabled()`.
2. **The name "Surge" is already used** by the world event "Salvage Surge" (`planets/verdance/data/events.json`: a glowing hex whose junk is worth 3x). Two different things called a surge will confuse players. Suggest renaming the event (for example "Salvage Glint"); not done here, it is another system's data and strings.
3. **Controller release is LB + RB together.** No free button exists. The hotbar no longer changes tool when both are pressed. The alternative is a hold on an existing button through `ui/pad_hold.gd`. The Controls tab lists "Release Surge" with a key only.
4. **Plain sweeping is rounded to whole frames** (`player/patch.gd`, the pulse timer restarts from zero): at 4 sweeps a second Lumi really makes 3.75. During a Surge the remainder now carries over, so the burst gives its stated output at any frame rate. Plain sweeping was left as it is because city 1 pacing was fitted to it; fixing it would speed all hand work 6 to 10%.
5. **Two charges on one gauge.** The Bloom Core's story charge (0 to 100% over the whole planet, never drops) and the Surge charge (fills and empties every few minutes) are different quantities. The spec says the existing meter is the Surge's gauge; built as an outer arc round the same ring. The ring is small; a larger gauge is a HUD call.
6. **Chest packing is new** (not in the spec). Without it a chest of 12 fills in under a second of Surge and the burst is spent walking. It also means a bale pressed from Surge waste is worth more than a plain one (same waste per cube, more waste per bale).
7. **No "Core Charge" upgrade yet.** The proposal has an upgrade track that shortens the charge. Today any sweep upgrade shortens it (the charge is counted in units of work). A dedicated track is M3-12's call.
8. **The pacing simulator was not changed.** Its redesign model has its own Surge (`balance.surge` in the proposal folder: 120 bot seconds, behind research). It should read the game's table once the unlock question (call 1) is settled.
9. Files touched outside the task's list, each for a hook: `autoload/Economy.gd` (stat hook), `autoload/EventBus.gd` (four signals), `autoload/Settings.gd` (the action), `player/patch.gd` (chest packing, tending events, pulse carry), `plants/garden.gd` (`push_growth`), `scenes/slice_orbit.gd` (build and save), `ui/hotbar.gd` (gauge), `tools/autoplay.gd`, `tools/orbit_roundtrip.gd`, the dummy planet's fixture (its own `balance` table).

## 5. Checks

- Full suite: 1,229 tests pass, 27 of them new in `tests/test_surge.gd` (charge only from Lumi's work on every kind, robots never, no idle or away charge, the fill cap, release and duration, the measured 3x sweep on both planets' numbers, the wider sweep, chest packing, scaling by district, the wave and its start district, saving, the key and the pad way, the bot's rule). The translations test passes; the new strings still need translating (`tools/extract_strings.py` was not run).
- Save round trip: passes, with `orbit_surge` (a part charge survives the save, the load and the time away).
- Screenshot: `screenshots/surge/surge.png` (opengl3, 960x540, the clock stopped 0.35 s after the release). Reads bright and colourful: the green "SURGE x3.2", cyan and green light column, sparkles, coloured rays at the screen's corners, the gold "12 SURGE" plate on the gauge. Weak points: the three ground rings have already raced out of this frame, so they are not confirmed by a render; the column is thin; the first render's full-screen flash washed the picture pale and was cut back to the edges. The burst could be bolder; that is M5 polish.
