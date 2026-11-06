# Decisions and assumptions

Format: **Decision** — reason. Items marked *(assumption)* are unverified until tested; *(verified)* means tested here.

## Engine and tooling
- **Godot 4.7.2-stable (official)** — `godot --version` → `4.7.2.stable.official.ed1daf0bf` *(verified)*.
- **Renderer: Forward+** for desktop. The cloud dev container has no GPU; Forward+ runs on Mesa lavapipe (software Vulkan) under Xvfb, so screenshots use the real renderer *(verified)*. Frame rates measured in the container are meaningless for performance targets; perf must be measured on real hardware.
- **Test framework: GUT 9.7.1** — mature, pure-GDScript, simple headless CLI (`gut_cmdln.gd`), no C# or editor plugin needed to run in CI. gdUnit4 is stronger for scene testing but heavier; GUT is enough for economy/save/progression logic.
- **No external art packs in M0-M1.** Kenney/Poly Pizza block automated downloads from the cloud container and Quaternius files are on Google Drive, which also blocks automated downloads. All art in the slice is procedural (code-built meshes + toon shader). If the owner uploads CC0 packs to `assets/incoming/`, they get recolored into the palette and logged in `docs/CREDITS.md`.
- **`core/` folder added** (not in the brief's tree) for engine-agnostic classes like `BigNum` and hex math, shared by autoloads, sim and tests.

## Design calls (brief was open)
- **Perfect Cube rule**: junk pieces have different volumes; the compartment has a fill line at 100%. Scooping pulls pieces in one by one while held. Releasing so the press happens at 90-100% fill gives a Perfect Cube (x1.5). Over 100% (the last piece didn't fit cleanly) gives a Lumpy Cube (x0.8). Single junk type gives a Pure Cube (x2). Mixed gives a speckled Mixed Cube (x1). Skill beats idle, never required.
- **Currency "Cubes" vs physical cubes**: physical cubes have a value; cashing them at the Depot adds that value to the Cubes counter. HUD shows the currency with a cube glyph.
- **M1 test field is already a hex grid** (flat, axial coordinates) so the hex-flip moment and completion bonus are in the slice. M2 swaps the flat grid for the sphere but keeps the same per-hex ledger API.
- **Patch's look** (original): squat teal-green box body with orange rust, a domed lid "head" fused to the body (no neck), one big round porthole lens on the front of the dome with a dilating iris, a mushroom-shaped antenna bulb, two stubby piston arms, chunky treads, a chest hatch with a fill gauge, one mismatched brass bolt, and a flower sticker on the side.
