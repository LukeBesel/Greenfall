# QA report status (qafix)

Status of every item in `docs/QA_REPORT.md` (branch `claude/greenfall-qa`, commit cac99f9), checked against main `claude/kind-wright-rhxixd` @ 0e70656 on Nov 8. Tests for the qafix fixes are in `tests/test_qafix.gd`.

## P1

1. Objective/checklist text fades to 50%: **already fixed on main** (a0cab0e, onboard2: the dim branch is gone from `ui/goals_panel.gd`; `test_onboard.gd::test_goals_never_dim_in_minimal_hud`).
2. Several message lines at once: **already fixed on main** (1f15fb8 + 87f3d58, onboard2: every toast goes through the subtitle bar's single queue; `test_onboard.gd::test_two_messages_at_once_never_show_together`). **Fixed** the leftover double line (7a1b82a): the buried-part hint is WREN's line when she can be heard, otherwise the toast, never both (`story/objectives.gd`).
3. First objective needs the Baler: **already fixed on main** (a9c9b1b, onboard2: the chain starts bin x3, Compartment, Scoop Size, Baler, then bales; no bale key before the Baler; `test_onboard.gd::test_early_objectives_use_what_lumi_has`, `test_no_bale_key_before_the_baler`).

## P2

4. Dead early stretch: **already fixed on main** (onboard2/pace2; the committed `screenshots/autoplay_report.json` from a9c9b1b has the longest goal gap at 5.9 min (1.0-6.8), the owner's bar is a new thing every 5-20 min). A 45-min re-run was not possible here: the shared container ran autoplay at about 1/4 speed (10.9 game minutes in 20 real minutes).
5. First seed at 37 min: **already fixed on main** (same report: `seed_tin_s` 1285 s = 21.4 min, base level 2 at 21.7 min, so the first robot follows soon after).
6. Parts pile up: **owned by pace** (economy). Parts now pay for Hub builds (camp2, `data/builds.json`) and Glim upgrades (buddy), but `parts_bought` is still 0 and research sat starved for 1,252 s in the last report; needs a pace re-measure past 30 min.
7. Camera clips into geometry / Lumi's head: roofs and walls at the view edges **already fixed on main** (87f3d58 + a9c9b1b, onboard2: the arm pulls in until the frustum edges are clear; `test_camera_pulls_in_when_a_roof_fills_the_view_edge`). **Fixed** the head case (7a1b82a): when a wall squeezes the camera closer than 1.25 m to Lumi, his model hides and comes back as the arm opens (`player/camera_rig.gd`, `test_qafix.gd::test_camera_hides_lumi_only_when_inside`).
8. Post-intro camera behind Lumi's head: **already fixed on main** (a9c9b1b, onboard2: hand-off at normal distance, turns away from a wall; `test_hand_off_turns_away_from_a_wall_behind_lumi`).
9. Black ellipses on the ground: **fixed** (7a1b82a). They were the rain puddles, not the manhole covers: `art/shaders/puddle.gdshader` relied on screen-space reflections (Ultra only) and was near-black everywhere else. Now damp-ground colours plus a grazing sky sheen.
10. Hex outlines as thick dark lines: **not fixed, render pending.** The shader's hex grid lines are emission-only and off by default (`show_grid` 0 in `art/shaders/ground_pbr.gdshader`) and the target hex uses onboard's laser outline (`story/objective_hex.gd`), so the dark square-ish lines in `03_spawn.png` are most likely the yard/street paving texture's seams, not hex outlines. Needs a spawn render to confirm; four attempts here were killed by memory pressure from other helpers' renders. Hand to world3/kit with the render if it still shows.
11. Yard has more than pod, bench and bin: **fixed** the water barrel (7a1b82a): it is built once the Drip blueprint is researched (or a Drip exists on an old save), not on a fresh yard (`robots/water_net.gd`, `test_water_barrel_waits_for_waterers`). The broken workbench reading as a railing is **owned by yard** (workbench model).
12. Flat pink and green fans: **not reproduced, render pending.** No butterfly-like fauna exist, the waypoint/Glim/tutorial meshes are not pink or green, and the census groups near the camera (Garden 888k triangles with nothing grown, FirstFlower) are the likeliest source: flower petals and leaves seen from very close. Needs a rendered autoplay with a node probe; not attempted further for the same render reason as #10.
13. Loading-screen Lumi differs: **won't fix (owner decision).** The owner calls the hero "the red Lumi" and asked for the real red Lumi on the loading screen; a qafix render on main (Nov 8) shows the loading screen is now a small 3D junk scene with the red Lumi, matching that. Whether the in-game hero should also be red is pod2/hero's open owner line.
14. Glim's toast cut off: **already fixed on main** (1f15fb8: toasts go through the subtitle bar, which splits long lines into readable chunks instead of an ellipsis; `test_qafix.gd::test_long_toast_is_never_cut`).
15. Locked card shows a negative need: **already fixed on main** (6d0a562, ui4), and the card grid was since replaced by ui6's list + detail workbench (0af2d32).
16. Workbench tabs open scrolled: **owned by ui5** (workbench/upgrade screens; ui6's list layout replaced the card grid this was seen on).
17. Research cards cut off their time: **owned by ui5**.
18. Settings last row clipped: **already fixed on main** (d981367, ui5: Basics fits above the footer).
19. Pause legend overlaps the HUD hint bar / advertises "press bale": **already fixed on main** (d981367: HUD key strip hides while paused; a9c9b1b: no bale key before the Baler; `test_no_bale_key_before_the_baler`).
20. Reward toasts without amounts: **fixed** (7a1b82a). "Recovered: ..." now ends with the Parts it paid (`player/patch.gd`), and a level-up lists Parts once as a total (`systems/lumi_level.gd`, `test_level_reward_names_parts_once`).
21. Title now-playing tag invisible: **fixed** (7a1b82a). Two bugs: `set_anchors_preset` left the tag a 0x0 rect at the top-left (so the box sat off-screen), and the clipped label had no width. `ui/title_song_tag.gd`, `test_title_song_tag_has_room_for_its_text`.
22. CD player and Nursery in Keepsakes from the start: **fixed** (7a1b82a). Keepsakes shows a tab only once its thing exists: CD Player after the radio build, Album with the camera bot or a photo, Nursery after the nursery build or a retiree; Seed of the Week always (`ui/extras_panel.gd`, `test_keepsakes_tabs_wait_for_their_builds`).
23. Loading stalls at 57%: **already fixed on main** (2ba48b2, leftovers: the district builds across frames, the bar shows real progress; headless ready 21.7 s -> 14.5 s, longest frame ~0.8 s).
24. Performance risk on Low (litter 239k instances): **owned by orbE** (performance / Mac pass, `docs/PERFORMANCE.md`; the round-planet rollout replaces the flat district these numbers came from).

## P3

25. Settings "Q E switch tabs" with one tab: **already fixed on main** (d981367: back-only prompt until More is opened).
26. Codex counters wrap: **already fixed on main** (d981367: one counter for the open tab).
27. Intro BLOOM CORE readout 12 px at 60%: **fixed** (7a1b82a): 15 px at 85-95% alpha (`story/intro.gd`). What it means is WREN's brief and the Bloom Core ring later; no new text added.
28. Overexposed daylight, sawtooth shadow edge: **owned by orbE** (sky/exposure, `planet/sky_director.gd`). The sawtooth edge is the Low preset's single orthogonal shadow split (35 m), by design for performance.
29. Pod ramp flat slab, pod upright: **won't fix here** (art; pod2's open owner lines "crash site: the pod leans, smokes..." and "the pod door looks good").
30. Maxed card "Buy" highlighted, "Max (5)" on locked, "Base 0" jargon: **owned by ui5**.
31. Hub tab empty boxes: **owned by ui5** (the Hub tab no longer exists: ui6 folded it into Build).
32. Glim scan white triangles, hard blob shadow: markers **already fixed on main** (4851a2f, buddy: small cyan/amber gems by lift tier). The dark disc is Glim's real sun shadow on Low (hard orthogonal shadows); **won't fix**.
33. Title focuses PROFILES first: **fixed** (7a1b82a): with no save, New Game is first and focused; with a save, Continue is (`ui/main_menu.gd`).
34. No CD in 45 min: **already fixed on main** by the pity rule (`planet/cd_finds.gd`: chance grows per cleaned hex, certain by `guarantee_hexes`); the QA run cleaned too few hexes for it to fire. The "New CD" toast is info priority on the message line (ffb5c81).
35. Log noise on Compatibility: **fixed** (7a1b82a). SSR/SSIL/SDFGI/volumetric fog are only switched on under Forward+ (`scenes/slice.gd`), and FXAA is not requested on Compatibility (`autoload/Settings.gd`, `story/space_stage.gd`, `systems/extras/album.gd`); checked on an opengl3 run that setting them off is silent. The ObjectDB leaks at exit are **won't fix here** (engine cleanup; code-health task).
36. Objective trail is a thin white line: **fixed** (7a1b82a). The chevrons were additive, which washes to white on pale ground; they now blend normally in the purple and are a bit wider (`story/waypoint.gd`, `test_waypoint_trail_is_not_additive`).

## Extra items from main

- Easter-egg props glow on landing (world3 note: vending screen, TV, jukebox, camera LED): **fixed** (41dbe0e). `story/egg_power.gd` switches every emissive surface, glow light and unshaded label of the vending machine, TV, jukebox, security camera, arcade and microwave off at spawn; Lumi's first poke wakes the machine (`story/eggs.gd` `_effect`), a found egg loads awake, and a dead camera does not track Lumi. `test_qafix.gd::test_egg_machines_start_dead_and_wake`.

## Checks
- `tools/run_tests.sh` (GUT + save round trip) and a headless autoplay (`--fresh --autoplay --time-scale=4 --quit-after=200`, no SCRIPT ERROR) before each ready message.
- Renders: none finished in this session (the shared container killed or starved every district render); #9, #10 and #12 still want one spawn shot at 960x540 Low.
