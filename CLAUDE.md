# Greenfall — notes for Claude sessions

## Toolchain
- Engine: **Godot 4.7.2-stable** (`godot` on PATH). Installed by the "Greenfall" cloud environment's setup script into `/opt/godot`.
- MCP: `.mcp.json` registers `@coding-solo/godot-mcp` (run project, capture debug output, create scenes/nodes).
- No GPU in the cloud container. Rendering goes through Mesa llvmpipe (software GL), so use the **Compatibility** renderer (`gl_compatibility`) for anything that must render here.

## Common commands
- Import / refresh resources: `godot --headless --import --path .`
- Run headless (logic, tests): `godot --headless --path . <scene-or-script args>`
- Rendered run (screenshots): `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720`
- Always render with `--rendering-driver opengl3`. Software Vulkan (lavapipe) runs under 1 fps here and gets OOM-killed. One render at a time (`flock /tmp/gf-render.lock ...`; `tools/shot.sh` and `tools/turnaround.sh` take the lock themselves), Low quality, 960x540.
- Audio errors from ALSA in the container are expected; Godot falls back to the dummy driver.

## Workflow
- The round world (SliceOrbit, the globe) is the only game. The flat world was removed (docs/FLAT_REMOVAL.md): there is no `--flat`, and `--orbit` only skips the title screen. Old flat saves are imported once into `user://saves_round` at startup.
- Planning and status: `docs/ROADMAP.md`. Update it before ending a session.
- The user asked that multi-agent workflows be used sparingly (≤6 agents, ask before more).

## Verification tools
- Tests: `tools/run_tests.sh` (GUT, headless).
- Screenshot: `DELAY=110 tools/shot.sh NAME --orbit --no-intro` (the globe takes a while to build: Low preset, 960x540; log in screenshots/NAME.log). The flat world's `--cam`, `--spawn-pos` and `--spawn-yaw` are gone; on the globe use `--orbit-spawn=x,z` and `--orbit-cam=D,P`.
- Robot turnarounds: `tools/turnaround.sh res://player/patch_model.gd screenshots/turn_x`.
- Autoplay pacing: `godot --headless --path . -- --fresh --autoplay --time-scale=4 --quit-after=200` (report in screenshots/autoplay_report.json).
- Save/load round trip (all systems): `godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh` (prints PASS/FAIL per system, exit 1 on failure).
- Hitches in play: add `--hitch` to a headless run (e.g. `-- --fresh --orbit --orbit-spawn=0,-260 --orbit-walk=boost --hitch --quit-after=75`); prints every frame over 30 ms of main-thread CPU with what ran in it. See docs/PERFORMANCE.md.
- Building glitches: add `--bld-watch[=s] --bld-watch-quit` to a headless orbit run: walks Lumi to the lake shore south of the yard and stands; logs every building swap, rebuild, visibility-range flip, new shader and in-play build (`[bldw]`). `--bld-look` swings the camera round, `--bld-progress` levels the hub and cleans round Lumi, `--bld-zfight` audits the town meshes for coplanar faces, `--bld-burst=DIR` (rendered) saves frames.
- Robot report: add `--robots=scoopie:3,haulbug:2,... --time-scale=4 --quit-after=90` to a headless run; prints a `[bots]` table.
- Load timing: add `--load-report` to a run (headless or rendered); prints build steps, slices over 80 ms, and `[loader] ready in N ms, longest frame M ms`. After changing what the district build loads, refresh `data/preload_models.json` with `--record-preload`. On the globe the list is `data/orbit_preload.json`: `godot --headless --path . -- --fresh --orbit --record-preload --quit-after=30`.
- Title screen shot: `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 -- --menu --quality=1 --shot=screenshots/title_menu.png --shot-delay=40 --quit-after=43`
- Opening film (shot table `data/intro_shots.json`, docs/ADJUSTING.md "The opening film"): render it as frames with `--fixed-fps 10 ... -- --fresh --orbit --intro [--intro-shot=ID | --intro-at=S] --quality=1 --intro-frames=screenshots/v9/intro/x --intro-every=2` (off-world shots alone, no globe: `res://tools/intro_preview.tscn -- --intro --intro-frames=...`), then `python3 tools/intro_sheet.py DIR OUT` for contact sheets. `tools/check_intro.sh`: skipping at any moment leaves the same world as watching (headless).
- Round Verdance checks (the round world is the game; all headless unless noted, add `-- --fresh --orbit --no-intro`):
  - `--city-walk`: walks the start town: walk area, dead-end pockets, the 8 ways out, junk you can reach. Exit 1 on failure.
  - `--target-reach`: every collectible and objective target (shards, CDs, parts, outposts, eggs, greenhouse) stands on reachable ground, and no junk heap or wreck stands inside an outpost's ruin. Exit 1 if any is cut off. `--target-reach-hubs=N` limits the hubs.
  - `--spot-probe=x,y,z` (or `=outpostK`) `[--orbit-hop=N --hop-skip --spot-probe-off=9]`: what boxes in a spot (e.g. a `[bot-trap]` position): TargetReach's verdict, a 0.5 m collider map with a legend, shut-in pockets (`*`).
  - `--site-reach`: narrow-gap audit of every hub site, a `[reach]` line per hub. Exit 1 if an anchor is cut off.
  - `--ground-probe=300 --ground-probe-quit [--orbit-spawn=x,z] [--ground-probe-r=120]`: lists floating and sunken props and junk around Lumi (`[ground]` lines). Wall signs show up as noise.
  - `--hex-audit --hex-audit-quit [--seed=N] [--hex-audit-hubs] [--hex-audit-all] [--hex-audit-raw]`: every land hex in the start area (data/start_area.json `radius_m`) as if Lumi took all the starter scoop can take where it lies; lists hexes that can't reach the 95% clear (what is left and why: big, under, inside, shut, building, ghost) and big things round base 1 (`[hexaudit]` lines). Exit 1 if any. Also in tools/check_exit.sh.
  - `--yard-probe --yard-probe-quit`: how close the junk starts to the pad and pod, and what stands in the start yard (`[yardprobe]` lines).
  - `--autoplay --time-scale=8 --clarity-log --quit-after=N`: logs what the player is told over time (card, prompt, beam target, toasts, WREN) as `[clarity]` lines, and flags stretches with nothing to do.
  - `--lake-view[=back_m]` or `--lake-view-high[=m]` (rendered): puts Lumi on a lake shore to check the water look.
  - `--orbit-survey=2 [--survey-zoom=1.4..6.0]` (rendered, shot delay 110 s or more): opens the survey map after the world is up, to check its glyphs and card.
  - Soak: `--autoplay --soak --time-scale=8 --quit-after=2400` (`[soak] WARN` lines). See docs/QA_VERDANCE.md.
  - `--walk-opening` (headless, `-- --fresh --orbit`, add `--no-intro` to skip the intro part): New Game to the first robot with real keys, mouse clicks on the bench and W/A/S/D walking (`[walk-opening]` lines, exit 1 on a failure; tools/walk_opening.gd, in tools/check_exit.sh).
- Goals: `--walk-goals` (headless, `-- --fresh --orbit --no-intro`): GoalAudit proves every goal and achievement left on Verdance can complete (stat written on the globe, target reachable, nothing closed; also tests/test_goal_audit.gd), then plays one goal of each hand-done kind with real input (`[walk-goals]` lines, exit 1 on a failure). A new goal's stat must be named in tools/goal_audit.gd SOURCES.
- Audio by numbers (nobody can listen here): `godot --headless --path . res://tools/dump_audio.tscn && python3 tools/check_audio.py` checks every built-in sound for clipping, DC, sub-80 Hz rumble, crackle, loop clicks and helicopter-like chop; `--audio-capture` on a run records the real mix per bus (`--wav` to check it; add `--life-sound` headless); `check_audio.py --sound-log screenshots/sound_log_summary.json` caps retrigger rates after a `--sound-log` run (docs/ADJUSTING.md "Listen by numbers").
- Repeating sounds: `python3 tools/check_audio.py --repeat screenshots/sound_log.txt` after a `--sound-log --life-sound` run at time-scale 1: per sound plays/min, takes, same-take runs, metronome gaps, annoyance; fails on a breach (rules in the script, knobs in data/sound.json `variety`/`wildlife`).
- Translations: `python3 tools/extract_strings.py` after adding or changing player text, then `python3 tools/l10n_status.py --export` and `tools/l10n_merge_draft.py` (docs/LOCALIZATION.md). Early-game strings must be translated in all six languages or `tests/test_l10n.gd` fails. Text that skipped `tr()`: add `--locale=pseudo --l10n-audit` to an autoplay run.
- Assets: `python3 tools/fetch_assets.py` after editing `data/assets.json`; new vendor textures need `compress/mode=2` (+ `compress/normal_map=1` for `*_nor_gl_*`) in their .import files.
- Blender (for modeling) is not preinstalled: `apt-get install -y --no-install-recommends blender`, then script it with `blender -b --python script.py`.
- Travel walk (real input: rocket E + clicks, stations 2 and 6, bench rocket row, system map drive, end card): `--fresh --orbit --no-intro --walk-travel` (tools/walk_travel.gd; `--walk-travel-save` then `--walk-travel-resume` reloads mid-station; `--walk-travel-end` loads the post-end save; `--walk-travel-shots=PREFIX` in a rendered run). In tools/check_exit.sh.
- Home steps walk (goal audit): `godot --headless --path . -- --fresh --orbit --no-intro --walk-home` plays hex2..base3, the garden after the first seed and the Requests board with real keys and workbench clicks (`[walk-home]` lines, exit 1 on a failure; in tools/check_exit.sh).
- Home steps walk (goal audit): `godot --headless --path . -- --fresh --orbit --no-intro --walk-home` plays hex2..base3, hex10/hex20 with real Scoopies, the garden after the first seed, steps met out of order, too-heavy junk and the Requests board with real keys and workbench clicks, and saves and reloads mid-step through the title 12 times (`[walk-home]` lines, exit 1 on a failure; in tools/check_exit.sh). `--walk-home-noreload`, `--walk-home-only=hex2,...`, `--walk-home-shots=/abs/dir` (rendered frames).
