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
- Robot report: add `--robots=scoopie:3,haulbug:2,... --time-scale=4 --quit-after=90` to a headless run; prints a `[bots]` table.
- Load timing: add `--load-report` to a run (headless or rendered); prints build steps, slices over 80 ms, and `[loader] ready in N ms, longest frame M ms`. After changing what the district build loads, refresh `data/preload_models.json` with `--record-preload`. On the globe the list is `data/orbit_preload.json`: `godot --headless --path . -- --fresh --orbit --record-preload --quit-after=30`.
- Title screen shot: `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 -- --menu --quality=1 --shot=screenshots/title_menu.png --shot-delay=40 --quit-after=43`
- Round Verdance checks (the round world is the game; all headless unless noted, add `-- --fresh --orbit --no-intro`):
  - `--city-walk`: walks the start town: walk area, dead-end pockets, the 8 ways out, junk you can reach. Exit 1 on failure.
  - `--target-reach`: every collectible and objective target (shards, CDs, parts, outposts, eggs, greenhouse) stands on reachable ground, and no junk heap or wreck stands inside an outpost's ruin. Exit 1 if any is cut off. `--target-reach-hubs=N` limits the hubs.
  - `--spot-probe=x,y,z` (or `=outpostK`) `[--orbit-hop=N --hop-skip --spot-probe-off=9]`: what boxes in a spot (e.g. a `[bot-trap]` position): TargetReach's verdict, a 0.5 m collider map with a legend, shut-in pockets (`*`).
  - `--site-reach`: narrow-gap audit of every hub site, a `[reach]` line per hub. Exit 1 if an anchor is cut off.
  - `--ground-probe=300 --ground-probe-quit [--orbit-spawn=x,z] [--ground-probe-r=120]`: lists floating and sunken props and junk around Lumi (`[ground]` lines). Wall signs show up as noise.
  - `--yard-probe --yard-probe-quit`: how close the junk starts to the pad and pod, and what stands in the start yard (`[yardprobe]` lines).
  - `--autoplay --time-scale=8 --clarity-log --quit-after=N`: logs what the player is told over time (card, prompt, beam target, toasts, WREN) as `[clarity]` lines, and flags stretches with nothing to do.
  - `--lake-view[=back_m]` or `--lake-view-high[=m]` (rendered): puts Lumi on a lake shore to check the water look.
  - `--orbit-survey=2 [--survey-zoom=1.4..6.0]` (rendered, shot delay 110 s or more): opens the survey map after the world is up, to check its glyphs and card.
  - Soak: `--autoplay --soak --time-scale=8 --quit-after=2400` (`[soak] WARN` lines). See docs/QA_VERDANCE.md.
- Translations: `python3 tools/extract_strings.py` after adding or changing player text, then `python3 tools/l10n_status.py --export` and `tools/l10n_merge_draft.py` (docs/LOCALIZATION.md). Early-game strings must be translated in all six languages or `tests/test_l10n.gd` fails. Text that skipped `tr()`: add `--locale=pseudo --l10n-audit` to an autoplay run.
- Assets: `python3 tools/fetch_assets.py` after editing `data/assets.json`; new vendor textures need `compress/mode=2` (+ `compress/normal_map=1` for `*_nor_gl_*`) in their .import files.
- Blender (for modeling) is not preinstalled: `apt-get install -y --no-install-recommends blender`, then script it with `blender -b --python script.py`.
