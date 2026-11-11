# M3-08: rigs

Nov 11 2026, on top of `6b33866`. Spec: `docs/design/PLANET1_DESIGN.md` section 7 and decision 16.8; `docs/DECISIONS.md` "Pollution kinds" (each city's kind needs a real new tool). Rules: `systems/rigs.gd`. Data: `planets/verdance/data/rigs.json`. Parts on the model: `player/rig_parts.gd`. Panel: `ui/rig_panel.gd`. Study: `tools/pace_sim/rig_study.gd`. Formulas: `docs/PLANET_PLAYBOOK.md`, "Rigs (M3-08)".

## 1. What was built

Three slots on Lumi: **arm, chest, drive**. One module per slot. Swapping is free and done at the workbench's new **Rig** tab. A fitted module shows on Lumi.

| Slot | Module | Comes with | Price | Gives | Takes |
|---|---|---|---|---|---|
| Arm | **Plate Cutter** (tool) | Ironside | free | clears wrecks; lifts what it cuts | sweep width -15% |
| Arm | Wide Sweep | Ironside | 900 cubes | sweep width +50% | reach -15% |
| Arm | Long Reach | Kettle Bay | 1,500 cubes, 20 Parts | reach +50%, slick work +30% | sweep width -15% |
| Arm | Guide Arm (crew) | Highreach | 2,800 cubes, 60 Parts | robots' bonus near Lumi x3 | scoop speed -8% |
| Chest | Deep Hold | Ironside | 1,200 cubes, 10 Parts | chest size +40% | speed -8% |
| Chest | Press Frame | Kettle Bay | 2,000 cubes, 30 Parts | bale value +25% | chest size -10% |
| Chest | **Mist Scrubber** (tool) | Highreach | free | clears smog | chest size -10% |
| Chest | Sorter (crew) | Highreach | 2,600 cubes, 50 Parts | Parts found x2 | bale value -5% |
| Drive | Sprint Coils | Ironside | 800 cubes, 8 Parts | speed +30% | chest size -8% |
| Drive | **Skim Skirt** (tool) | Kettle Bay | free | clears slick; floats over water | speed -5% |
| Drive | Tow Hitch | Highreach | 2,400 cubes, 40 Parts | 2 more bales carried | speed -12% |
| Drive | **Soil Doser** (tool) | Lowmeadow | free | clears blight | speed -5% |
| Drive | Relay Mast (crew) | Lowmeadow | 3,400 cubes, 80 Parts | reach of the robots' bonus x2.5, detector +40% | speed -5% |

Largest price 3,400 cubes (cap 4,200). Every slot has a module that acts on the crew (decision 16.8).

**Gates per city** (`planets/verdance/data/pollution.json`, `gate.module`):

| City | New kind | Was opened by | Is opened by |
|---|---|---|---|
| Ironside | wrecks | Lift Strength 2 (bought in city 1) | Plate Cutter fitted |
| Kettle Bay | slick | Hover Jets | Skim Skirt fitted |
| Highreach | smog | the garden tools | the garden tools and the Mist Scrubber fitted |
| Lowmeadow | blight | the garden tools | the garden tools and the Soil Doser fitted |

- A tool's plan arrives the moment its city opens (`district_unlocked`), with a line: "New tool: Plate Cutter. Fit it at the workbench." It is owned, not fitted: until the player fits it the kind stays shut and the hex readout says "WRECKS  NEED THE PLATE CUTTER".
- The Cutter carries the lift wrecks need and the Skirt the hover, so no first-city upgrade is a hidden second gate.
- Floating waste had no kind on its pieces, so the old slick gate was only the shore. The field now asks per lake hex (`SphereField.water_open`), so a Lumi with Hover Jets and no Skirt cannot skim a slick lake; an Old Town pond (plain junk) is as before.
- Other modules are built once from their plan (cubes and Parts), then fitted free. "Build" in the panel fits at once.
- Effects reach the game through `Rigs.stat_mod` (called by `Economy.stat` after upgrades, research and sets: adds, then multipliers, then floors) and `Rigs.factor` (`kind_<id>` in `Pollution.hand_bonus`, `parts_yield` in `Patch._piece_arrived`, `crew_near` and `crew_radius` in `Mastery.near_factor`). The stat tooltip lists the module.
- Events: `rig_module_unlocked(id)`, `rig_module_built(id)`, `rig_fitted(slot, id)`.
- **Saved per planet** (`orbit.rigs`: plans, built modules, what is fitted). A save from before rigs gets the tools of its open cities fitted where the slot is free.
- **On the model:** arm tools ride the right wrist, chest and drive gear the body (`PatchModel.set_rig`, kept through a change of look). Thirteen procedural shapes, one per module. Rigs take no Locker slot and no cosmetic id; the Locker turntable shows looks only.
- **The bot** fits the tools of the open cities at the bench, newest city and newest kind first, and walks back for one that is waiting (`tools/autoplay.gd` `_rig_tools`).
- No module exists in city 1 and the Rig tab is hidden until Ironside opens.

## 2. The rig study (`--rig-study=1`)

Each module of a slot is scored in each city where the slot has a choice: cubes, cleaning and Parts a minute, weighted by city (numbers and their meaning in the table's `study` block). Share of the best fit:

| City | Arm | Chest | Drive |
|---|---|---|---|
| Ironside | **Plate Cutter**; Wide Sweep 67% | one module only | one module only |
| Kettle Bay | **Wide Sweep** = Long Reach; Cutter 97% | **Deep Hold**; Press Frame 95% | **Skim Skirt**; Sprint Coils 82% |
| Highreach | **Plate Cutter**; Sweep 99%, Reach 99%, Guide 96% | **Mist Scrubber**; Sorter 69%, Hold 66%, Press 61% | **Tow Hitch**; Coils 93%, Skirt 89% |
| Lowmeadow | **Plate Cutter**; Sweep 97%, Reach 97%, Guide 94% | **Sorter**; Hold 95%, Press 86%, Scrubber 82% | **Soil Doser**; Hitch 57%, Coils 53%, Mast 52%, Skirt 51% |
| Old Capital | **Plate Cutter**; Sweep 96%, Reach 96%, Guide 95% | **Sorter**; Hold 94%, Press 85%, Scrubber 82% | **Tow Hitch**; Coils 92%, Mast 91%, Skirt 87%, Doser 87% |

**No module is the best fit of its slot in every city** (the acceptance line; `test_the_study_finds_no_module_that_is_best_in_every_city`). Each tool is the best fit in its own city.

What the study does not show:
- **Five modules are never the best fit**: Long Reach (ties Wide Sweep), Guide Arm, Press Frame, Sprint Coils, Relay Mast, 4 to 9% behind the best outside the tool cities. They are real alternatives but the study never picks them.
- **The Plate Cutter is the best arm in four of five cities.** After Ironside it wins by 1 to 4%, because Lumi's own work on wrecks keeps the crew's wreck rate up (mastery).
- The study is a short model with first values (crew sizes, how far Lumi's hand rate has grown by each city, the weights). It was fitted by hand twice, not searched. It is not the accepted proposal's loadout study: that one (8% spread in time to launch) runs on the proposal's own rig table and still passes unchanged.

## 3. Checks

See section 5 for the numbers of the final run.

## 4. Open design calls

1. **Tools arrive when the city opens, not on landing.** The task says "on reaching that city". The only bench is in the start yard, so a tool given on landing costs two flights before the first new hex. One line to change (`district_unlocked` to `district_entered`).
2. **Tools are free.** A price would make the gate harder, but the bot has not been run through cities 2 to 6 to say what a fair price is.
3. **Skim Skirt and Soil Doser share the drive slot** (Old Capital's 9 slick hexes need a second outing). A fourth slot or moving one of them would remove the choice.
4. **Hover Jets and Lift Strength 2 are now worth less**: Hover Jets still crosses water (short cuts, plain ponds), Lift Strength still lifts big loose junk. Whether Hover Jets stays an upgrade is for M3-12.
5. **Module numbers and prices are first values** for M3-12, with the five never-best modules above.
6. **No objective card step for the first fit.** The toast and the blocked readout are the only guidance; a card step belongs with the tutorial milestone.
7. **Rig parts are procedural stand-ins** until M5-10.

## 5. Files outside the task's list, and why

`systems/pollution.gd`, `planets/verdance/data/pollution.json` (the gates), `planet/orbit/sphere_field.gd` (floating waste asks its hex), `autoload/Economy.gd` (two lines: the stat hook and the tooltip), `autoload/EventBus.gd` (three signals), `systems/mastery.gd` (the crew bonus), `player/patch.gd` (parts yield, model refresh), `player/rig_parts.gd` (new), `scenes/slice_orbit.gd` (wiring, save), `scenes/hero_preview.gd` (`--rig=`), `tools/orbit_roundtrip.gd` (snapshot), `ui/rig_panel.gd` (new), `ui/upgrades_screen.gd`, `data/workbench.json` (the tab), `tools/autoplay.gd` (the bot), `tools/pace_sim/rig_study.gd` (new), `tools/pace_sim/pace_sim.gd` (the flag), `planets/verdance/planet.tres` (the table), `tests/test_pollution.gd` (the gates moved), `docs/PLANET_PLAYBOOK.md`, `docs/DECISIONS.md`. Not touched: `systems/sources.gd`, `planets/verdance/sources/*`, `story/planet_ending.gd`, `CLAUDE.md`, `.claude/`. `tools/extract_strings.py` was not run: the new strings (module names and descriptions, panel and toast lines, four prompts) are not in `locale/` yet.

Originality: the slots, the module names and what they do come from the cleanup theme. Equipment slots with trade-offs are a common genre mechanic; nothing here copies another game's layout, names or numbers.
