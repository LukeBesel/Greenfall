# M3-18a: the landing yard and Old Town as the first city

Nov 10-11 2026, on top of `4efa608`. Renders: `screenshots/world/city1/` (`before_*`, `after_*`, `stage_0/3/4`, `sheet.png`), all `opengl3`, 1280x720, Medium, made with `tools/world_audit/world_shot.tscn`.

## 1. What was built

| Area | What | Where |
|---|---|---|
| Pad | One quad with a paving shader: 1.75 m slabs with joints and their own tone, cracks, stains, soot round the pod, worn floor paint (safety yellow and Lumi's teal edge lines, a landing ring with a heading arrow, a hatched gate, the bin bay's blue floor, the bench's orange work zone). Replaces 36 pale panels. | `systems/camp/yard_pad.gdshader`, `VerdanceSite.clean_pad` |
| Workbench | Steel wear plate, burn rings, saw kerfs, parts tray, vice screw and handle, soldering iron, mug, oil can, red toolbox, jerrycan, three cable reels. Same teal, orange and yellow. | `systems/camp/yard_art.gd` (`bench_body`, `_reel`) |
| Pod | Leans further (0.28 / 0.15 rad), sits 20 cm in, longer furrow with ploughed lips and a bank, six hull shards, thicker and darker smoke. The 320 m plume was already there. | `story/crash_site.gd` |
| Old Town | Its own module: palette (brick, cream, terracotta, mustard, teal walls; terracotta, copper-green, slate, sand roofs; strong awnings), roof tanks, roof signs and parasols (3 MultiMeshes), 18 market stalls, 149 street trees, shore scum and reeds. | `planets/verdance/sites/city_old_town.gd` |
| Density | Outskirts now take every block the pad town does not keep (a bare ring used to lie between them), fewer open lots, walk-ups with a few 9-16 floor blocks in place of 14-30 floor towers: 354 to 438 buildings. Streets carry on through the outskirts (1,078 road pieces, one mesh). | `town_outskirts.gd`, `verdance_site.gd` |
| Source landmark | Pump house No. 1 at the head of the main street on the lake: brick hall, gable roof, 34 m standpipe tower with tank, two teal mains, the burst one fountaining 15 m over a flooded forecourt, barriers and a beacon. `CityOldTown.set_source_state("broken" / "shut_down")`: shut down hides the fountain and flood, caps the main, leaves damp ground, turns the beacon green and lights the sign. | `city_old_town.gd` |
| Stage hook | `TownSite.set_district_stage(stage)` (shared, a no-op by default); `VerdanceSite` wires it to `EventBus.district_stage_changed` for its site's district and reads the saved stage from the `Districts` node. `CityOldTown.set_stage(0-5)`: signs clean from 1; shop windows and lamp heads lit from 2; rooms lit and trees in leaf from 3; shore scum gone and reeds from 4; all lights, full crowns and flowers at 5. | `planet/sites/town_site.gd`, `verdance_site.gd`, `art/shaders/building_city.gdshader` (`lit`, `sign_clean`) |

Two bugs found and fixed on the way, both in shared code and both visible in every town:
- **Roofs white from above.** A proxy building's roof lay 1 cm above its cornice's pale top face; from a distance the two fought for depth and the cornice won. The roof is now 10 cm proud (`planet/building_detail.gd`).
- **Black back walls.** On ring-1 buildings the dark "rooms" box stood 2 cm outside the brick shell on the sides and back (`planet/city_view.gd`). `before_street.png` shows it filling the left third of the frame.

Other shared changes: `StreetDressing.billboard_x` (Old Town moves its billboard off the main-street axis so the pump house closes the view from the yard); `CityView.building_material`; building plans may carry `wall_tex`, `awning`, `awning_striped`.

## 2. Honest state of each view

| View | Better | Still wrong or unfinished |
|---|---|---|
| Yard looking out | The pad reads as used paving with markings; the bay is a blue field; the pump house, its fountain and tower close the main street; coloured walls. | The left third is still flat lake. Slab tone is a little pink in full sun. The name sign hides the pump house's left half from the spawn point. |
| Yard from above | Markings, bay and work zone read; junk starts 0.3 m off the pad. | The furrow is dark lumps under the litter, not a ploughed trench: the litter carpet is not cleared along it. The bench is small in frame and its new detail does not show from here. The loose boards and bent poles south-east of the pad (existing dressing) look like debris from nowhere. |
| Old Town street | No black wall; pink, brick, cream and terracotta fronts; trees; a roof tank on the skyline. | Proxy windows still show the dotted moire. No readable shop names on this street (the painted names only exist near the yard). Litter is still flat coloured sheets. |
| Pumping station | A recognisable brick waterworks with a sign, tower and fountain. | The fountain is a pale cone with dots, not convincing water; the flood is hidden under the junk at stage 0. The dead trees are plain brown cylinders up close. |
| Command view | Roofs are terracotta, teal, slate and sand; streets run through the whole town; the plume and the pump house's orange roof stand out. | The pad town's sidewalk blocks are still pale; open lots near the yard are bare junk squares. |
| 900 m | The town is a street grid with coloured roofs, not specks. | This is 900 m over Old Town, not the audit's `far_900` point (1.5 km north, hinterland only, unchanged by this task). Street strips on the south shore have almost no buildings beside them and read as dark bars. |
| Stages 0, 3, 4 | Lights, clean signs and trees in leaf all change with the stage. | **Stage 5 could not be rendered:** setting the district to 5 starts the planet's ending film. Tree crowns are lumpy low-poly balls with shadow banding up close: stylised, below the bar. Lit windows are flat yellow squares by day. The lamp glow is a plain disc. The cleaned ground is pale cream (not part of this task). |

## 3. Performance (Medium, `--perf`, same cameras before and after)

| View | Before: draws, triangles | After | Change |
|---|---|---|---|
| Yard looking out (audit: 1,088 / 5.5 M) | 1,145, 5.52 M | 1,253, 6.00 M | +9.4%, +8.6% |
| Yard from above | 1,252, 5.63 M | 1,342, 6.09 M | +7.2%, +8.2% |
| Old Town street (54, 10) | not captured | 1,389, 7.36 M | see note |
| Pumping station street | new | 1,033, 5.99 M | |
| Command view, 300 m | 581, 2.28 M | 608, 2.40 M | +4.6%, +5.3% |
| 900 m | 582, 2.06 M | 593, 2.09 M | +1.9%, +1.1% |

Note: the `before_street` run printed no perf line, so the street has no baseline at this camera. It is the heaviest view and is over the audit's proposed 6 M triangles on Medium; not measured on Low.

## 4. Yard distances

- Bench to scale plate 5.5 m; scale plate to bin 2.7 m; bench to bin about 8.2 m (from the anchors; nothing was moved).
- Nearest junk piece 0.3 m from the pad edge, none on the pad (`--yard-probe`).

## 5. Checks

- `tools/run_tests.sh`: 953 tests, 953 passing (7 new in `tests/test_city_old_town.gd`); save round trip PASS; orbit reload PASS.
- `--target-reach` (hub 0): 325 targets, 0 unreachable. `--city-walk`: PASS.
- Bot, `--fresh --autoplay --time-scale=8 --quit-after=400`: no SCRIPT ERROR.

## 6. Open points

1. The round trip's `orbit_start_view_clear` check tests bounding boxes, so a scorch disc under the pod and a 13 m furrow both failed it; the furrow is back to about 8 m and the disc is gone.
2. Soot on the pad does not fade when the pod is repaired.
3. Old saves load into the new town layout (nothing about the town is saved); junk keeps off the new footprints piece by piece.
4. `docs/ART_KIT.md` line 3 names another game as the quality bar; the style guide says not to. Not changed here.
5. Nothing here was modelled on another game. The landing ring is a plain double ring with ticks and a heading arrow.
