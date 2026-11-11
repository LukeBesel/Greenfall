# M3-15: robot wrecks and buried finds in the world

Nov 11 2026, on top of `71e0472`. Spec: `docs/design/PLANET1_DESIGN.md` section 13. Builds on M3-14 (`docs/reviews/M3-14_16_LOOKS.md`). Sheet: `screenshots/finds/sheet.png` (eleven renders, opengl3 under xvfb, 960x540, Low preset; single shots beside it in `screenshots/finds/`).

## Result

| Acceptance line | Result | Proof |
|---|---|---|
| Wrecks in some cities | met | Ironside (Leaf lenses, Leaf plate), Highreach (Moss patches), Lowmeadow (Sprout paint). `test_a_planet_has_at_most_one_tease_and_it_is_a_later_design` |
| Reachable (reach audit) | met | `--orbit --target-reach`: 5,638 targets on 10 hubs, 0 unreachable, the three wrecks and the tease included (hubs 3, 7, 8, 9) |
| Recognisably the planet's design | met, close up | The wreck is the hero model (`player/patch_model.gd`) in Sprout's look: rust, grime, more moss, dead lamps, tipped on its back, one arm up, one eye faintly lit. `test_a_wreck_is_the_planets_own_design_worn_by_the_years` |
| At most one unsalvageable tease of a later design | met | Kettle Bay, a Bolt wreck, further gone (more rust, an arm torn off, no light). Says "Too far gone. Maybe somewhere else." `test_the_tease_says_its_line_and_can_never_be_salvaged` |
| Hand-clearing before salvage | met | Three pieces of junk, one pull each (0.7 s dig), then the salvage (1.4 s). Clearing the hex gives nothing. `test_a_wreck_is_cleared_by_hand_then_salvaged_once`, `test_clearing_a_wrecks_hex_gives_nothing` |
| Found pieces play a reveal on Lumi | met | Plate ("Salvaged · Ear lenses", the piece's name, the way to the Locker), a light in the piece's colour on Lumi that flashes and settles, a ring of sparks, two chimes. `test_a_salvaged_piece_is_a_moment_on_lumi`, render |
| Detector pings buried tins and chips | met | Same lamp, beep and readout line as a part, in the find's colour: "BURIED TIN · 3.5 m" / "LENS CHIP". Dig to reveal. `test_the_detector_pings_a_buried_find_with_its_own_readout`, `test_a_buried_find_lies_in_the_soil_until_lumi_digs_it_up`, `test_a_lens_chip_pings_as_a_chip` |
| Salvaged wrecks stay salvaged | met | Save round trip: `orbit_wreck_stays_salvaged`, `orbit_wreck_not_salvaged_twice`, `orbit_wreck_junk_pulled_kept`, `orbit_buried_find_still_lies`. `test_a_salvaged_wreck_stays_salvaged_after_a_load` |

Tests: `tests/test_find_sites.gd`, 11 tests. Full suite: 1,267 tests pass (141 files), the translations test included. Save round trip and the two-process reload: pass.

## What was built

- `systems/find_sites.gd` (FindSites): stands wrecks, the tease and surfaced buried finds near Lumi (built within 150 m, freed past 210 m), registers them with Interactables, moves a spot to open ground when buildings change while Lumi is away, plays the glint (sparks of the eye's colour every 5 to 9 s within 90 m) and the pulse of a buried find's light.
- `systems/wreck_model.gd` (WreckModel): the hero model frozen, sunk, tipped and weathered; `strip(pieces)` takes the salvaged parts off and darkens the eye.
- `systems/find_props.gd`: the junk heap (panel, drum, crate in kit colours), the soil mound with a tin rim or chip edge, and the flowers that come up round a stripped wreck.
- `systems/finds.gd`: `teases`, `sites`, `surfaced` finds and `cleared` junk in the planet's save section; once the world shows finds, nothing is handed over from far away (a buried find surfaces in its hex's soil; a wreck is salvaged by hand).
- `player/detector.gd`: `cache_fn` (the world's buried finds come before parts), `dig_at()` shared by parts, junk, salvage and tins.
- `ui/piece_reveal.gd`: the light and second chime; "Salvaged" for a wreck's pieces; the plate now sizes to its text (it filled the screen's height on its first render); `hold_for()` for render tools.
- `scenes/slice_orbit.gd` builds FindSites and hands the detector its `cache_fn`. Data: `planets/verdance/data/finds.json` (`sites`, `teases`).
- Tools: `systems/find_sites_dev.gd` (`--find-shot`), `tools/find_shot.sh`, `tools/wreck_lineup.gd`; the bot (`tools/autoplay.gd`) walks to and uses finds near it; the reach audit and the save round trip cover the wrecks.

## The renders, looked at critically

Good: the Sprout wreck reads as Lumi's kin close up (round head, lens eye, green paint under rust and moss). Junk is colourful, not brown. A salvaged wreck is dark-eyed with grass and flowers round it. The plate is short and names the piece. The ping readout is in the tin's own colour.

Below the bar:
1. **Not readable from 30 m.** In the 30 m render (high camera) the Ironside wreck cannot be picked out from the litter round it. A one-metre robot half sunk among junk is small; the glint is a brief spark every 5 to 9 s and a still frame misses it. A stronger tell (a taller silhouette such as an antenna or a bent mast, or a steadier glint) is the next step.
2. **The tease reads as a dark lump.** Bolt's navy paint under heavy rust, in a building's shadow, with a bin bag in front: it does not say "robot" at a glance.
3. **The Highreach wreck sits under a smog cast** (that city's haze); close up it is legible, the colours are dull.
4. **The found light is weak in full sun.** The flash and glow show in the shade; in daylight the moment rests on the plate, the sparks and the sound. Lumi wearing the piece (Leaf lenses) is not visible from the render's angle.
5. **The ping render puts the tin on the start pad**, which play never does (finds lie in cleared hex soil), and the tin itself is behind Lumi; the readout is the proof.
6. **Junk is three kit props**, not shaped to the wreck; the first piece lies across it, the others stand round.
7. The renders show the Wren subtitles and the checklist panel; the ping hook clears the subtitle line so the readout shows.

## Notes and open questions

- **The detector readout shares the one message line with Wren's talk**: during a spoken line the ping shows on the lamp and beep only. That is the HUD's existing rule (one message line at a time).
- **A surfaced find a robot turned up far away** gets a toast naming the city ("Your crew uncovered something buried in Ironside."), so no colour is missed.
- **New player-facing strings** (prompts, readout labels, toasts, "Salvaged · %s") are in `tr()`; `tools/extract_strings.py` was not run, as asked.
- **Originality:** a beeping detector that leads to buried things, and salvaging a wreck for a part, are common genre ideas. Here they come from Greenfall's own theme: old robots of Lumi's own family, junk pulled off by hand, soil dug where Lumi cleaned. No layout, name or structure was taken from another game.
- Not changed: goals and objectives (another agent's), `locale/`, CLAUDE.md. `docs/ROADMAP.md` is left to the lead.
