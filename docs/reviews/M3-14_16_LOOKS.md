# M3-14 and M3-16: looks from found pieces, and the Locker as a place

Nov 11 2026, on top of `5ae685b`. Spec: `docs/design/PLANET1_DESIGN.md` section 13. Decisions: `docs/DECISIONS.md`, "Looks from found pieces and the Locker". Screenshot: `screenshots/locker/locker.png`.

## Result

| Acceptance line | Result | Proof |
|---|---|---|
| No look unlocks from a stat, level or cost | met | `tests/test_looks.gd` (no unlock key in the three data files, the unlock functions are gone), `tests/test_designs.gd` (huge stats, levels and currencies open nothing) |
| Every piece has a find | **partly** | Every Sprout piece and nine loose colours have a find on Planet 1. Fifteen loose pieces and the four later designs have none on any planet yet (listed below) |
| Bot run: first piece near minute 12 | met | Bot, time scale 4: `old_town_tin` (Sky tin) at minute 14.5, the 12th cleaned hex |
| Only Sprout can be completed on Planet 1, not before the last city | met | `test_playing_the_first_planet_completes_sprout_alone_and_only_in_the_last_city`: all 5,052 city hexes cleaned and every source shut, in order |
| The other four designs have no pieces on Planet 1 | met | same test, and `test_the_first_planet_offers_sprout_alone_spread_over_its_cities` |
| Old saves keep what they had | met | `tests/fixtures/saves/looks_v4.json` and `test_an_old_save_keeps_what_it_had`; the save round trip loads the old flat fixture |
| Locker offered after the first find | met | `test_the_locker_is_offered_after_the_first_find`, `test_the_goal_chain_brings_the_locker_once_a_piece_is_found` |
| Only found pieces can be worn | met | `test_only_found_pieces_can_be_worn` (every piece, before and after it is found) |
| Unfound pieces are silhouettes with a hint | met | `test_the_locker_page_lists_found_pieces_first_and_unfound_as_hints`, the screenshot |
| The only place looks are edited | met for Lumi | `test_the_locker_is_the_only_place_looks_are_edited` |

Full suite: 1,108 tests pass (133 files). Save round trip: passes, including found pieces in the `global` section and the old-save migration. Strings: the POT is up to date; all six languages have drafts for the new strings.

## What was built

**Pieces** (`data/cosmetics.json`, `systems/looks.gd`). 61 pieces in the spec's eleven slots. Each names one option, one colour or one design's paint set or light colour. Sets: Aurora 5 (the starting pieces), Bolt 6, Sprout 7, Pixel 7, Nova 5, Patch 6. Events: `piece_found(piece_id, source)`, `set_completed(design_id)`, `look_changed()`.

**Finds** (`planets/verdance/data/finds.json`, `systems/finds.gd`). Sixteen finds:

| City | Buried | Wreck | Source |
|---|---|---|---|
| Old Town | Sky tin (hex 12 to 14), Mint chip | | Plastic bottle |
| Ironside | Copper tin | Leaf lenses, Leaf plate | |
| Kettle Bay | Sea glass tin, Coral chip | | Sprout green |
| Highreach | Midnight tin | Moss patches | |
| Lowmeadow | Rose gold tin | Sprout paint | |
| Old Capital | Lilac chip | | Sprout leaf (the last piece) |

Plus a Royal blue tin on open ground (1 in 200 hexes) and the Firefly from the campfire curiosity. Buried chance is 1 in 40 hexes from a set hex, certain by a later one. Every find is fixed by the planet's seed.

**The moment** (`ui/piece_reveal.gd`). Lumi wears the piece for 3.5 s with a burst in its colour; a plate names the piece and its slot and points to the Locker (to build it, before it stands). The last piece of a set gets a second plate.

**The save.** Version 5. Found pieces are in `global.pieces`; what the planet has handed out is in the planet's section (`orbit.finds`).

**The Locker** (`systems/camp/locker_cabinet.gd`, `systems/camp/locker_stage.gd`, `ui/locker_panel.gd`, `ui/lumi_builder.gd`, `ui/piece_row.gd`, `ui/field_plate.gd`). 400 cubes, offered by the first find through the Build tab and two goals that jump to the front of the chain ("Build the Locker", "Wear a look at the Locker"). Pressing E puts a stand-in Lumi on the turntable, hides the real one and moves the view to a camera that swings round the turntable. The panel docks on the right on field-instrument plates: slots on the left, the slot's pieces on the right with found ones first, "Wear look" at the foot. Sets and Saved looks (three) are pages of the slot list. A complete set shows its name and bonus at the top in green; a mixed look says so.

**Removed.** The unlock rules in `data/designs.json` and `data/style_parts.json`, the bonus picker, the colour mixer and its price, the Cosmetics picker (`ui/cosmetics_panel.gd`), the design toast, the standalone builder and its preview, `scenes/style_builder_shot.tscn`, and the dev flag that opened the builder.

## The screenshot, looked at critically

Good: bright scene, Lumi and the whole turntable in the free part of the screen, the cabinet in view, plates with a clipped corner, text at 16 px and above, hints wrap without being cut.

Short of the bar:
1. **The slot list scrolls at 720p.** Thirteen entries at 44 px do not fit; nine show.
2. **The camera swings over an arc of about 100 degrees; it does not circle.** A full circle passes through the yard fence. The turntable turns Lumi instead, and a drag turns it by hand.
3. **Slot marks are plain drawn shapes**, not pictures of the pieces. A silhouette shows the slot, not the piece.
4. **The crew, Glim and rocket pages still use the older glass panels.** Only the frame and Lumi's page are in the field-instrument style.
5. **One render, at 1280x720.** 16:10, 21:9, 4:3, Steam Deck and the interface-scale setting were not rendered; a test checks the dock leaves the turntable in view at the test window's size only.

## Outside the task's file list

Touched because the change needed it: `autoload/GameState.gd`, `autoload/SaveManager.gd` (save version 5), `autoload/EventBus.gd` (four events), `core/planet_definition.gd` (the `finds` table), `scenes/slice_orbit.gd` (builds and saves Finds, adds the reveal), `story/goals.gd` (`after_flag`), `story/eggs.gd` (the duck's hint read an unlock rule), `systems/achievements.gd`, `systems/camp/yard_builds.gd` (the flag's text comes from data), `systems/robot_builder.gd` and `ui/hub_panel.gd` (two lines that named a base level for the Locker), `tools/orbit_roundtrip.gd`, `tools/extract_strings.py` (one key), `planets/verdance/data/camp.json` and `goals.json`.

**Locale.** Running the extractor, as the localisation guide asks, also pulled in about 215 strings from earlier tasks that had never been extracted. The six `.po` files are rewritten as a result. I drafted this task's 99 strings and 60 short ones from earlier tasks in all six languages; 156 strings from earlier tasks remain untranslated (4.3%, inside the test's 5% allowance).

## Open design calls

1. **Fifteen loose pieces have no find on any planet.** Round, heart and bar eyes, antenna, halo, heart plate, med kit, watering can, tiny drone, and the Graphite, Slate, Chalk, Orange, Gold and Bloom green colours. They exist so old saves keep them. Decide which later planet hides each, or drop the ones not wanted.
2. **Nova's set has five pieces**; the spec asks for six to eight.
3. **Aurora's detector bonus is on from the start**, because her five starting pieces are a complete set. It goes off as soon as one found piece is worn. If that reads as a penalty for dressing up, Aurora's bonus should go.
4. **Crew and Glim cosmetics still open by their old rules** (robot builder parts, liveries from Requests, Glim's looks). The owner's rule covers them; they were not in this task's files.
5. **Planet 1 places nine loose colours, not eight** (eight in the cities, one on open ground), and a companion from a secret.
6. **Graphite, Slate and Orange were free before.** New games no longer have them; old saves do.
7. **Robots' cleaning counts toward buried finds and can uncover a wreck.** The spec says a wreck needs hand-clearing. M3-15's placed wrecks are used by Lumi alone (`Finds.register_site`), which settles it.
8. **A found piece is shown on Lumi even when a robot cleaned the hex far away.**
9. **The detector does not ping buried tins yet** (M3-15).
10. **Source finds come at city stage 4 until M3-07.** Then sources emit `EventBus.source_shut_down(district)` and `source_shut_at_stage` leaves the finds table.
11. **Originality.** Found cosmetic pieces, sets with a small bonus and a place to try them on are common across games. Nothing here copies another game's layout, names or progression: the pieces are old robots' salvage, the place is a steel locker with a turntable in Lumi's own yard, and the panel is her field instrument.

## Not verified

- A played run past the first find: building the Locker in a real session, wearing a piece, and the found moment seen on screen. The bot run found the first piece; it did not build or open the Locker. The moment is covered by a test, not by a render.
- Cities 2 to 6 in a played run: wrecks and sources are proven on the test globe and by the round trip (the three wreck hexes are picked on the real globe).
- Controller and touch use of the Locker (focus order is set, not played).
- The translations are machine drafts, like the rest.
