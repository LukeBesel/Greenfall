# Brief for art helpers (read fully before starting)

Greenfall is a Godot 4.7.2 game; the round planet Verdance is the only game. Read CLAUDE.md,
studio/BRIEF.md, studio/BARS.md and studio/ROUNDS.md first. You own ONE part of the art overhaul
(named in your prompt). Other helpers work on other parts at the same time in their own worktrees.

## The bar (owner)
More realistic, still super futuristic. Real far-future hardware and places in real light:
believable materials (wear, dirt, painted metal vs glass vs rubber), solid construction (thickness,
seams, joints that could move), grounded lighting, motion with weight. Not toy-like, not cheap.
Do not be afraid of big changes to looks: replace models, materials and effects outright where they
look cheap. The owner's reference for character quality is art/concept/lumi_concept.png: that level
of surface detail, wear and glow is the target for hardware too.

## Method
- ToggleOps ops (MCP server "toggleops", load tools with ToolSearch "toggleops"): call find_op, then
  load_op "toggle-studio", and read with op_file: skills/04-materials-light/SKILL.md (layered
  materials: colour variation, cavity, two-scale bump, wear at edges, varied roughness; bounce not
  flat ambient), skills/02-blender-film/SKILL.md (parts as code, stills first, change one thing and
  compare), skills/09-environments/SKILL.md if you build plating, rocks or skies. Use their methods
  for form, material and light, then bring the result into Godot at a game budget.
- Blender headless: `blender -b --python script.py` (4.0, numpy installed) or `python3 script.py`
  with `import bpy` (Blender 5.3 module; use it for bakes). Build scripts live next to their output
  in art/models/<thing>/, export .glb there, wire it into the game. Everything stays code.
  Example of the pattern: art/models/aurora/build_aurora.py + player/patch_model.gd.
- Keep it game-budget: merged meshes, shared materials, few draw calls, LODs or distance culls for
  far things, no per-frame allocation, textures via tools/fetch_assets.py conventions (CLAUDE.md).

## Rules (hard)
1. Art only. Do NOT change colliders, walkable areas, saves, gameplay, prices, text or goals. Keep
   every node name, method and anchor that other code calls; if one must change, list it.
2. Another session is editing gameplay (jump, title screen, map, far bases, removing planting):
   keep edits to gameplay files tiny. Do not restructure art/asset_lib.gd or planet/city_view.gd
   (`_load_kit`, `_flush_batches`).
3. Nothing is done until it is rendered from the PLAY camera and you have looked at it (Read tool).
   For each change keep a before and an after frame of the same view (take the before FIRST, before
   editing). Renders: software GL only (`--rendering-driver opengl3`, Low, 960x540), one at a time;
   tools/shot.sh and tools/turnaround.sh take the shared lock /tmp/gf-render.lock, so other helpers'
   renders queue behind yours and each takes 2-3 minutes: plan few, telling frames. One load can save
   many frames with `--life-tour=PREFIX --life-tour-start=105 --life-tour-stops="x,z,yaw,time,wait[,dist,pitch];..."`
   (planet/sites/life_dev.gd; x,z are metres from the start pad, time 0..1 with 0.5 = noon; give
   DELAY=150 or more to tools/shot.sh). Check at day, dusk (0.735) and night (0.0).
   Numbers: `python3 tools/frame_stats.py IMG...`. Board: `python3 tools/art_board.py OUT BEFORE_DIR AFTER_DIR name:label ...`.
4. The Mac build must not get slower. Measure before and after (headless):
   `godot --headless --path . -- --fresh --orbit --no-intro --load-report --quit-after=40` (the `[loader] ready` line, twice)
   and `godot --headless --path . -- --fresh --orbit --no-intro --orbit-spawn=0,-260 --orbit-walk=boost --hitch --quit-after=75` (the `[hitch] run:` line).
   Also compare draw_calls and prims from a `--perf` rendered run of your main view.
5. After any geometry change: `godot --headless --path . -- --fresh --orbit --no-intro --city-walk`
   and `... --target-reach` must exit 0.
6. Never skip, disable or weaken a test. Run the whole unit suite before you finish:
   `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -glog=1`
   (about 3 minutes; it was 1250/1250). Add a test for anything other code relies on.
7. Setup in your worktree: `cp -r /workspace/Greenfall/.godot .godot && godot --headless --import --path .`
   Screenshots go under screenshots/art/<your-part>/before and /after (git-ignored); put ONE board
   jpg in docs/art/ (quality 88).
8. Commit your work on your worktree's branch with clear messages. Do NOT push and do not touch
   other branches. Do not edit studio/*.md, docs/ROADMAP.md or CLAUDE.md (the lead does).

## Report (plain text, short)
What you replaced and why it now meets the bar; the board path; before/after numbers (load, hitch,
draw calls, prims); test totals and walk results; every name or position other code calls that
changed; what still falls short, honestly; your branch name and commit hashes.
