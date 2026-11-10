# World quick wins: outcome

Task M3-17b, Nov 10 2026, on top of `7a692ad`. It applies the quick wins Q1-Q14 of `docs/reviews/WORLD_AUDIT.md` section 12, one commit each, and fixes the `_attach_power` script error. Every change was rendered before and after and looked at; the pairs are in `screenshots/world/qw/`.

## 1. Needs a decision

1. **Q9 is over the performance limit at hub centres.** The task allowed 10% more draw calls or triangles at the audit's positions. With junk up to the hub yard, the downtown centre went from 1,100 to 1,482-1,490 draw calls (+34%) and from 4.5 M to 8.6 M triangles (+90%) on Medium, and the 300 m view over the same hub from 2.14 M to 3.14 M triangles (+47%). On Low the centre is 1,276 draw calls and 5.1 M triangles, inside the audit's proposed city budget of 1,500 and 6 M. The cost is the litter carpet and junk that now lie in view; it cannot be had for less with a smaller core. Q9 is its own commit, so it can be reverted alone. I kept it because the view is the one the owner asked for and the reach audit passes.
2. **Q7 bends a written owner rule.** `planet/street_power.gd` records: "When you land there can't be working things like streetlamps. Only broken-down things you fix." Q7 asks for a few lights in ruined towns. What was built: in hubs 1-9 only, 40% of the standing lamp heads glow warm after dark as dying emergency cells. Street power, its repair and its switch-on moment are untouched, and the start town stays dark. If the owner's rule is meant to cover every town, revert the Q7 commit.
3. **Q10 was dropped** (see below).

## 2. Per change

Render times: about 2 minutes for a start or open-land view, 3 minutes for a far hub. All at 1280x720, `opengl3`, Medium.

| # | Outcome | What changed and the values used | Files | Renders (`screenshots/world/qw/`) |
|---|---|---|---|---|
| Q1 | **Kept** | Below-horizon haze `haze_day` (0.55, 0.52, 0.48) to (0.68, 0.77, 0.9). | `planet/orbit/orbit_sky.gdshader` | `Q1_before.png`, `Q1_after.png` (planet_far); `Q1_*_land_open.png`; `Q1_*_downtown_high.png` |
| Q2 | **Kept, in another file, then tuned** | The audit pointed at `orbit_day.gd`, but in play `SkyDirector._apply_sphere` sets the fog every frame. Fog density `lerp(0.0005, 0.001, haze)` to `lerp(0.0003, 0.0005, haze)`; dusty fog colour (0.78, 0.76, 0.72) to (0.72, 0.8, 0.92). `orbit_day.gd` defaults were matched (0.0005, pale blue). Tuned in the Q3 commit: the density is divided by `1 + (height - 300) / 300` above 300 m of camera height, because the globe still bleached at 2,600 m. | `planet/sky_director.gd`, `planet/orbit/orbit_day.gd` | as Q1; `Q3_after.png` shows the height rule |
| Q5 | **Kept, tuned** | Sun energy 2.2 to 1.95, day exposure 1.25 to 1.1, day sky fill 1.1 to 1.2, day saturation 1.2 to 1.26. Saturation 1.32 was tried first and turned the white pad pink. Lowering the sun and raising the fill keeps shade as bright as before. Night values are unchanged. | `planet/sky_director.gd` (four named constants) | `Q5_before.png`, `Q5_after.png` (downtown_high); `Q5_*_yard.png` |
| Q3 | **Kept, tuned twice** | Six junk colours (can red, crate blue, bottle green, sack yellow, tarp teal, paper white) as hashed patches at three sizes, each fading out before it shrinks under a pixel. Near ground past 45-95 m: 1.3 m (30% of cells), 5 m (24%), 10 m (12%, at 60% strength). Far shell: 9 m, 26 m, 64 m (55% strength). First try had patches up to 150 m (giant squares); second try was too faint. | `planet/sphere/sphere_ground.gdshader`, `planet/sphere/sphere_shell.gdshader` | `Q3_before.png`, `Q3_after.png` (planet_far); `Q3_*_far_900.png`; `Q3_*_downtown_high.png` |
| Q4 | **Kept** | Litter palette weights: the five packaging colours from 14% to 36% of draws, each a little purer. Pull to grey 0.1-0.4 to 0.05-0.2, darkening 0.05-0.4 to 0.05-0.3, pull to brown 0-0.35 to 0-0.17. | `planet/sites/sphere_litter.gd` | `Q4_before.png`, `Q4_after.png` (land_open) |
| Q9 | **Kept, over the limit (section 1)** | Clear core of hubs 1-9 from 60 m to the site's `clear_core_m` (12 m on Verdance). Fresh worlds only; old saves keep their cells. Reach audit `--target-reach`: 5,680 targets on 10 hubs, 0 unreachable, PASS (rocket pad, depot and bench anchors included). The yard itself stays clear and usable (`Q9_after.png`). | `planet/orbit/orbit_planet.gd` | `Q9_before.png`, `Q9_after.png` (downtown centre) |
| Q8 | **Kept, tuned** | Dirty lake: deep (0.045, 0.055, 0.03) to (0.045, 0.1, 0.075), shallow (0.09, 0.095, 0.05) to (0.09, 0.17, 0.115), far water (0.05, 0.058, 0.032) to (0.048, 0.105, 0.078); scum film 0.3 to 0.4. First try was a turquoise brighter than clean water, so it was pulled to an algae green. | `planet/sites/sphere_water.gdshader`, `planet/sphere/sphere_ground.gdshader` | `Q8_before.png`, `Q8_after.png` (200 m over the start); `Q8_*_yard.png` |
| Q6 | **Kept** | Five wreck colours: the old red-brown, teal, yellow, cream, red (four more MultiMeshes). | `planets/verdance/sites/hinterland.gd` | `Q6_before.png`, `Q6_after.png` (150 m over the suburb point); `Q6_*_land_open.png`; `Q6_after_land_suburb.png` |
| Q12 | **Kept** | Props on open junk-field hexes from 3.5% to 12%: 7.5% wrecks, 1.5% tanks, 3% fence runs. | same | same |
| Q13 | **Kept** | Looks per hinterland archetype 3 to 5. Look 0 keeps the kit palette; the other four are painted (mint, butter, coral, sky-blue walls with red, green, slate and terracotta roofs; yellow, blue, rust and sea-green works). `BuildingDetail.proxy_building` takes an optional `tint` and `roof_tint`. | `planets/verdance/sites/hinterland.gd`, `planet/building_detail.gd` | same |
| Q10 | **Dropped** | Tried the 30% water rule. Hub 3 turned from a mid-rise harbour town into a suburb of 1-3 floor boxes and looked emptier (`Q10_after_dropped.png`). The accepted six-city plan makes site 3 the harbour city, so pinning it to "suburb" now works against the next task. Kinds are unchanged. | none | `Q10_before.png`, `Q10_after_dropped.png` |
| Q14 | **Kept** | `StreetDressing.landmark_kind` lets the site script choose. Verdance: old town and start water tower, downtown radio mast, industrial crane, suburb ferris wheel, harbour lighthouse. | `planet/street_dressing.gd`, `planets/verdance/sites/verdance_site.gd` | `Q14_before.png`, `Q14_after.png`, `Q14_crop_before_after.png` (hub 3: radio mast to lighthouse) |
| Q7 | **Kept, changed (section 1)** | New `RuinLights`: 40% of a town's standing lamp heads glow warm after dark (one MultiMesh), and the six nearest the camera carry a real light (range 18 m, no shadow). Off by day. 25% and a weaker light were tried first and did not show. Hubs 1-9 only. | `planet/sites/ruin_lights.gd` (new), `planets/verdance/sites/verdance_site.gd`, `tests/test_ruin_lights.gd` | `Q7_before.png`, `Q7_after.png` (downtown street, night); `Q7_after_high.png` |
| Q11 | **Kept** | Start outskirts open-lot share [0.12, 0.3] to [0.05, 0.15]: 211 to 275 buildings, 51 to 28 open lots. | `planets/verdance/sites/town_outskirts.gd` | `Q11_before.png`, `Q11_after.png` (200 m over the start) |
| Bug | **Fixed** | `SiteManager._attach_power` read a prefab that was freed while it waited for the slice's HexLevels. It now checks the prefab first. The regression test fails without the fix. | `planet/sites/site_manager.gd`, `tests/test_site_power_freed.gd` | none |

## 3. Performance

`--perf` on Medium. "Audit" is section 7 of the audit. The first five rows use the audit's exact cameras (the open-field and 2,600 m baselines were re-measured before any change and matched).

| Position | Audit: draws, triangles | After: draws, triangles | Change |
|---|---|---|---|
| Start yard, day | 1,088, 5.50 M | 1,145, 5.52 M | +5.2%, +0.4% |
| Land between: open field | 927, 6.24 M | 962, 6.40 M | +3.8%, +2.6% |
| Land between: suburb | 1,028, 7.5 M | 1,070, 7.58 M | +4.1%, +1.1% |
| 900 m up | 388, 2.0 M | 392-395, 2.06 M | +1.8%, about +3% |
| 2,600 m up | 511, 1.65 M (1.7 M in the audit's rounding) | 527, 1.66 M | +3.1%, +0.6% |
| Downtown, 300 m up (my camera: 664, 2.14 M before) | 640, 2.1 M | 658, 3.14 M | -1%, **+47%** (Q9) |
| Downtown street, centre (my camera: 1,100-1,117, 4.53 M before) | 1,037, 4.5 M | 1,490, 8.59 M | **+34%, +90%** (Q9) |
| The same on Low | not measured | 1,276, 5.1 M | inside the proposed 1,500 and 6 M |

Steps Q6, Q12 and Q13 alone: land_suburb 1,028 to 1,068 draw calls, land_open 927 to 962. Q7 alone: 1,283-1,287 to 1,288 at the downtown street by night. MultiMesh batching is unchanged everywhere.

Three street views in the final set are near hub centres at my own cameras (the audit did not record its spawn points), so they cannot be compared one to one: old town street 1,441 and 6.78 M, harbour street 1,229 and 6.05 M, industrial street at night 1,919 and 7.65 M. They carry the same Q9 cost.

## 4. The six views after the pass

Sheet: `screenshots/world/qw/before_after_sheet.png` (audit on top, final below). Mean saturation from the same rough script as the audit.

| View | Saturation, before to after | What is better | What still looks wrong |
|---|---|---|---|
| `planet_far` | 0.09 to 0.20 | Blue backdrop, terracotta land speckled with junk colours, blue lakes. No longer a cream ball on brown. | The flecks read as confetti, not as recognisable junk or cities. The start town is a white smudge. The backdrop is one flat pale blue. This height is past the game's own 400 m zoom limit. |
| `downtown_high` | 0.08 to 0.13 | The ground between the towers is covered in colour to the centre; the tiling pattern shows much less. | Roofs and light walls are still white-grey. No streets past the pad. The fleck patches are square and a little loud at this height. Still the dullest of the six (51% grey pixels). |
| `far_900` | 0.06 to 0.17 | Peach land with coloured specks, dark teal lakes, blue backdrop. | Buildings are white specks with no colour or street pattern. The frostcap is a blank white patch. Flecks look like sprinkles. |
| `land_open` | 0.27 to 0.31 | The horizon band is sky, the carpet is far more colourful, far houses are pink, yellow and blue. | The flat sheets are plain coloured squares with no print, so close up they read as paper confetti. Still no large shape on the horizon. |
| `oldtown_street` | 0.25 to 0.33 | The street is full of junk to the end and much more colourful. | The street is still in shade (mean brightness 0.39, 14% dark pixels). Not the audit's exact camera. Cannot be told from a downtown side street. |
| `start_yard_out` | 0.12 to 0.18 | The pad is no longer blown out, the lake is sea green, sky and brick are richer. | The pad is still a large empty slab (65% of pixels grey or near white). A faint pink cast on the pad from the warm sun. |

Also seen: the industrial street at night has no lit lamp in frame at the spot I picked, so the night view there is still all blue.

## 5. Checks

- `tools/run_tests.sh`: 903 tests, 903 passing; save round trip PASS; orbit reload PASS.
- Bot: `godot --headless --path . -- --fresh --autoplay --time-scale=8 --quit-after=400`: no SCRIPT ERROR. Godot printed "3 ObjectDB instances were leaked at exit"; not checked against the base commit.
- Reach audit after Q9: PASS, 0 of 5,680 unreachable on all 10 hubs. Re-run at the end on hubs 0 and 1 only: PASS, 0 of 1,012.
- `docs/ROADMAP.md` was not updated: the task limited doc changes to this file and the audit.
