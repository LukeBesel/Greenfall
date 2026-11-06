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
