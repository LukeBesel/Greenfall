# M3-14b: crew and Glim looks found only, no starting-set bonus, wrecks seen from afar

Nov 11 2026, on top of `e8eb066`. Follows `docs/reviews/M3-14_16_LOOKS.md` (open calls 3 and 4) and `docs/reviews/M3-15_WRECKS.md` (below the bar 1, 2 and 4). Sheet: `screenshots/finds/sheet_b.png` (before / after, opengl3 under xvfb, 960x540, Low preset; single shots and logs beside it).

## Result

| Ask | Result | Proof |
|---|---|---|
| Crew and Glim looks are found pieces | met | `data/cosmetics.json` `targets` (Glim: 15 pieces, 4 starting; crew: 39). `tests/test_crew_looks.gd` |
| A few on Planet 1, the rest held | met: 3 | Glim's Moss shell (paint tin, Highreach), Glim's Leaf glow (lens chip, Lowmeadow), the crew's Mint lights (lens chip, Ironside). `test_a_planet_hides_crew_and_glim_looks_only_through_its_finds` (both planets), `test_playing_the_first_planet_finds_its_crew_and_glim_looks` |
| Edited only in the Locker | met | A tab for Glim and one per robot type. `test_the_locker_gives_glim_and_each_robot_type_a_tab`, `test_the_glim_panel_points_to_the_locker` |
| No purchase, counter or Request unlocks | met | Crafting, the Haggle stall, the Requests track looks, the first-robot gift, the lucky clover drop, Glim's bought / tier / hex looks are gone. `test_nothing_buys_or_counts_open_a_crew_or_glim_look`, `test_no_way_to_get_a_part_but_finding_it`, `test_reward_track_pays_capsules_and_parts_never_looks` |
| Old saves keep what they had | met | Save v6. `tests/fixtures/saves/crew_looks_v5.json`, `test_an_old_save_keeps_its_crew_and_glim_looks`; save round trip `old_crew_looks_*` (9 checks, through a save and a load) |
| Aurora gives no set bonus | met | `data/designs.json`. `test_the_starting_set_gives_no_bonus` (also: every design with a bonus is made of pieces to be found) |
| Wreck visible from 30 m | partly | A young plant grows up out of a wreck that still holds pieces. `test_a_wreck_that_holds_pieces_grows_a_young_plant_that_goes_when_salvaged`, sheet row 1 |
| Tease reads as a robot | met | Sits up slumped, less sunk, more paint. `test_the_tease_sits_up_so_it_reads_as_a_robot`, sheet row 2 |
| Found light reads in full sun | met | A ring of light on the ground and a soft column, unshaded. `test_the_found_moment_has_a_glow_that_shows_in_sunlight`, sheet row 3 |

Full suite: 1,303 tests pass (142 files; 3 new in `tests/test_find_sites.gd`, 11 in the new `tests/test_crew_looks.gd`), translations test included. Save round trip and the two-process reload: pass. One `check_exit` run flagged a SCRIPT ERROR in `art/asset_lib.gd:53` (a junk mesh with no vertex array, from `sphere_junk_view.gd`, code this task did not touch) with all round-trip checks passing; a rerun was clean.

## What changed

- **Pieces for Glim and the crew** (`data/cosmetics.json` `targets`, `systems/looks.gd`, new `systems/crew_looks.gd`). Each target has its own slots (Glim: shell, glow, top; crew: chassis, head, mobility, tool, topper, fleet mark, light colour) and pieces that name the look they stand for. Found pieces are the same global list as Lumi's, granted by the same `finds` table. `Looks.defs()` / `ids()` stay Lumi's; `target_defs(t)` and `target_of(id)` reach the others.
- **Glim** (`systems/glim/glim.gd`, `data/glim.json`, `ui/glim_panel.gd`): `look_unlocked` asks for the piece; `buy_look`, `unlock_hint` and the `owned` list are gone. The Locker page shows found looks, then "???" with the find's hint for looks this planet hides, then a count of those on other worlds.
- **Crew** (`systems/robot_builder.gd`, `systems/robot_design.gd`, `systems/liveries.gd`, `data/robot_parts.json`, `ui/locker_editors.gd`, `ui/locker_panel.gd`): `RobotBuilder.owned(id)` replaces the parts bin; `RobotDesign.set_look` checks marks and lights; fleet marks are defined by their pieces (moved out of `events.json`). The per-robot `ui/builder_panel.gd` is deleted (it bought and crafted parts; the Locker edits one look per type). Each robot type has its own Locker tab.
- **Requests** (`systems/contracts.gd`, `planets/verdance/data/events.json`): the track's livery and part steps became Curio Capsules and small Parts rewards; the livery shop functions are gone.
- **Found moment** (`ui/piece_reveal.gd`): a crew or Glim piece names its owner ("FOUND · GLIM · SHELL") and does not dress Lumi.
- **Save v6** (`autoload/SaveManager.gd`, `CrewLooks.migrate_save`): grants every piece whose old rule the save met (bought Glim looks, Glim upgrade count, hexes cleaned, parts in the bin, liveries won) and everything worn; robot lights were free, so old saves get all six.
- **Wrecks** (`systems/find_props.gd` `sapling`, `systems/find_sites.gd`, `systems/wreck_model.gd`, finds table `sites.sapling`): a 2.4 m young plant with three stems grows out of a salvageable wreck and goes when it is salvaged. The tease sits slumped forward, sunk 0.18 m instead of 0.46, more paint left.
- **Found light** (`ui/piece_reveal.gd`): a ring opening on the ground and a 3.2 m column in the piece's colour that settles to a haze; a set part uses its design's light (Sprout green).

## The sheet, looked at critically

1. **The 30 m plant is visible, not striking.** In the high 28 m view it is a green plant above the teal junk (clear in the 3x inset, about 15 by 30 px in the full frame). It reads because nothing else there is fresh green; in a restored, grassy hex it would read less. A camera at eye height would show it against the sky better; the before/after pair used the same high camera.
2. **The tease shows a yellow robot head with its visor and antenna**, the body mostly behind junk. Much better than the dark lump, but it still sits in a building's shadow on a dim street.
3. **The found column is heavy for the first second**: it tints Lumi green. It settles to a faint haze; the ring on the ground carries the moment after that. Its straight sides read a little like a cylinder.
4. One view per render at 960x540; no render of the Locker's new tabs (covered by tests only).

## Open design calls

1. **The rocket's looks are still bought** (`ShipStyle`, Locker Rocket tab). The owner's rule covers every cosmetic; it was not in this task.
2. **Achievements on Planet 1**: "Mix and Match" (five custom parts on a robot), "As the Makers Made It" and "Hat Rack" (5 toppers) can no longer be earned on Planet 1, since no crew part is hidden there. Global achievements, so later planets can earn them; or Planet 1 hides a part or two.
3. **Which later planet hides what**: 9 Glim looks and 38 crew pieces wait (listed by `CrewLooks.listing`). They need homes in later planets' `finds` tables, like the fifteen loose Lumi pieces.
4. **Requests track**: the livery and part steps became capsules and small Parts rewards (rarity 1 and 2). The pace simulator does not model the track; the owner may want other rewards there.
5. **The Maker set keeps its small robot bonus** (+5% speed, +6% work): it is now found-only like Sprout's, so it fits the rule.
6. **Detector range drops 8% for new and old games** with Aurora's bonus gone. Nothing was retuned.

## Originality

Found cosmetic pieces and a plant growing out of an old machine are common ideas; here they come from Greenfall's theme (salvage, regrowth on the very wrecks Lumi digs out). No layout, name or structure was taken from another game.

## Not changed

`locale/` (new strings are in `tr()`; `tools/extract_strings.py` was not run), research and garden code, CLAUDE.md, `.claude/`, `docs/DECISIONS.md` and `docs/ROADMAP.md` (left to the lead).
