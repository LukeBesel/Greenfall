# Art overhaul: state at the stop, 26 Nov ~14:00 UTC (owner ran low on usage)

Branch claude/practical-meitner-eipd0h. Combined tree: unit suite 1288/1288, --city-walk, --target-reach
and --hex-audit exit 0, one rendered run from the start pad (noon, dusk, night, junk field) with no
script or shader errors. NOT run on the combined tree: tools/check_exit.sh walks (walk_opening, walk_home,
walk_travel, walk_goals, seed_walk, rewatch), load and hitch numbers, the opening film, the title screen.
Nothing has been seen on a real GPU (Forward+/Metal, High, 60 fps). Targets: art/concept/lumi_concept.png,
aurora_turnaround.png, aurora_portrait.png, world_target.jpg (notes in studio/BARS.md).

| Part | In the branch | Verified by its helper | Not verified / short of the pictures |
|---|---|---|---|
| Light, sky, night lake | sky_director, orbit_sky, water | frames, numbers | --look-fx (fog shafts, SSR) never seen: needs the Mac |
| Ground | damp, puddles (sphere_ground `wetness`) | renders without error | hardly visible from the pad; not tuned on open ground |
| Lumi | hero v2 + concept match (outline overlap 0.82 mean, was 0.74) | suite, 2 turnarounds | head commit's last tweaks unrendered (list in docs/HANDOVER_AURORA.md); portrait, play camera, other designs, film, title not rendered; shell too clean, arms thin, back views wide |
| Bases round 1 | quay pad, bench, bin, lamps | suite, walks, board | night crush 2% on the built yard |
| Bases round 2 | NOT merged: studio/pending/bases_round2.patch | its own test, one headless run | never rendered; new shader never compiled. `git am studio/pending/bases_round2.patch`, render, then keep or drop |
| Buildings | window depth, staining, roofs, pilings | suite, city-walk, frames | ivy cards drew black: OFF unless --ivy-cards; inner kit fronts still clean; streets, far shore untouched |
| Shuttle | new model, gear, dust, scorch | suite, walks, travel walk, board | Mk II-VII, Locker paints, film/system map ship not rendered; plume still the cyan cone |
| Workers | Scoopie, Haul Bug rebuilt, spring motion, far mesh | suite, walks, board | ground glow not showing in the globe; far mesh, other tiers and kits unseen |
| Regrowth | flora kit, wind, staged growth | suite, walks (before the last change) | last colour change unrendered; trees need hex level 3+, which planting used to give: design call |
| Junk | kit pieces as looks, aged colour, contact dirt | own test, yard-probe, walks | new litter carpet OFF unless --litter-art (did not show in game); no board; kit plastics too bright |

Changed names and positions for other code: see each helper's commit messages and reports summarised
in docs/HANDOVER_AURORA.md (Lumi), and: ShipModel points and paths (art/models/shuttle), RobotVisual
points (hopper/fork/emitter, wheels under `_base`), SphereJunkView.piece_transform/piece_mesh return
the drawn look, BuildingDetail.Geo.mat uv2 packing, CellVerdure child nodes Tufts/Flowers removed,
YardArt.state_for threshold and KitMat "repaired" wear (global: all kit buildings look more used).

Pick up next, in order:
1. Run tools/check_exit.sh and the load/hitch comparison on this branch; fix what fails.
2. Run the two Mac review cards (real GPU): overall look and motion; --look-fx on/off with cost.
3. Lumi: one staged render of everything unrendered, then surface (warmer, stained shell, deeper seams), forearms, hands.
4. Junk: get --litter-art showing, make it default, board; then the ground on open land to value 45-55.
5. Bases round 2 patch: render, fix, merge. Buildings: ivy cards, inner kit fronts, streets, far shore.
6. Regrowth: decide how cells pass level 1 without planting. Workers: ground glow, far mesh.
Owner rules in force: no new helpers without his say (studio/BRIEF.md); machine limits in studio/HELPER_BRIEF.md.
