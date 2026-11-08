# Greenfall — notes for Claude sessions

## Toolchain
- Engine: **Godot 4.7.2-stable** (`godot` on PATH). Installed by the "Greenfall" cloud environment's setup script into `/opt/godot`.
- MCP: `.mcp.json` registers `@coding-solo/godot-mcp` (run project, capture debug output, create scenes/nodes).
- No GPU in the cloud container. Rendering goes through Mesa llvmpipe (software GL), so use the **Compatibility** renderer (`gl_compatibility`) for anything that must render here.

## Common commands
- Import / refresh resources: `godot --headless --import --path .`
- Run headless (logic, tests): `godot --headless --path . <scene-or-script args>`
- Rendered run (screenshots): `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720`
- Audio errors from ALSA in the container are expected; Godot falls back to the dummy driver.

## Workflow
- Planning and status: `docs/ROADMAP.md`. Update it before ending a session.
- The user asked that multi-agent workflows be used sparingly (≤6 agents, ask before more).

## Verification tools
- Tests: `tools/run_tests.sh` (GUT, headless).
- Screenshot: `DELAY=60 tools/shot.sh NAME --cam=close --spawn-pos=0,14 --spawn-yaw=3.14` (software Vulkan is slow: Low preset, 960x540; log in screenshots/NAME.log).
- Robot turnarounds: `tools/turnaround.sh res://player/patch_model.gd screenshots/turn_x`.
- Autoplay pacing: `godot --headless --path . -- --fresh --autoplay --time-scale=4 --quit-after=200` (report in screenshots/autoplay_report.json).
- Save/load round trip (all systems): `godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh` (prints PASS/FAIL per system, exit 1 on failure).
- Robot report: add `--robots=scoopie:3,haulbug:2,... --time-scale=4 --quit-after=90` to a headless run; prints a `[bots]` table.
- Load timing: add `--load-report` to a run (headless or rendered); prints build steps, slices over 80 ms, and `[loader] ready in N ms, longest frame M ms`. After changing what the district build loads, refresh `data/preload_models.json` with `--record-preload`.
- Title screen shot: `xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver vulkan --resolution 1280x720 -- --menu --quality=1 --shot=screenshots/title_menu.png --shot-delay=40 --quit-after=43`
- Assets: `python3 tools/fetch_assets.py` after editing `data/assets.json`; new vendor textures need `compress/mode=2` (+ `compress/normal_map=1` for `*_nor_gl_*`) in their .import files.
- Blender (for modeling) is not preinstalled: `apt-get install -y --no-install-recommends blender`, then script it with `blender -b --python script.py`.
