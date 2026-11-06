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

## Art and tone override (owner, during M1) — supersedes the toon direction above
- Grounded realism in the spirit of Potato Please: PBR everywhere, real-world scale, atmosphere first, dry dark humor. The toon shader, candy palette, squash/stretch and bouncy numbers from the first slice pass were removed.
- **Rendering (Godot 4.7.2 Forward+)**: PhysicalSkyMaterial + directional sun, SDFGI, SSAO, SSIL, SSR (Ultra), volumetric fog, subtle glow, TAA, **AgX tonemapping** (available since 4.4). Quality presets Low/Medium/High/Ultra in `Settings.apply_render_quality`; Low (also used automatically on Mobile/Compatibility renderers) drops SDFGI, SSIL, SSR, volumetrics and SSAO and uses plain fog + MSAA.
- **Assets**: CC0 from Poly Haven only (models + textures at 1k), fetched by `tools/fetch_assets.py` from `data/assets.json`; credits in `docs/CREDITS.md`. ambientCG was requested but its downloads redirect to a host outside the network allowlist, and Poly Haven covers the same needs.
- Normal maps are imported with `compress/normal_map=1`; vendor textures VRAM-compressed with mipmaps (set in their `.import` files).
- Ground: one shader over Texture2DArrays (albedo/normal/ARM, 8 layers) so it stays within 16 samplers for the Mobile tier.
- The first slice's "Perfect/Pure/Lumpy" rules stay; their presentation is now restrained (small crisp text, sound, the bale's look).

## Nov 2026 decisions
- **Main character**: Aurora from the owner's concept sheet is P-47CH ("Patch"), the futuristic bot sent down from the Cradle. Other bots start rusty and modernise with Mk tiers. Colourways (Bolt, Sprout, Pixel, Nova, Patch) are unlockable cosmetics.
- **Planet travel**: districts per base on a 40k-hex planet, travelled by rocket; seamless sphere walking deferred (scale and streaming cost on target hardware).
- **Map**: a hologram Aurora holds in her claw (deliberately different from Moon Sweepers' console map); Command mode is a real overhead camera rather than a 2D map.
- **Sustain** is done by watering robots and refill tanks, never sprinklers (owner request).
- **Recycler vs. selling**: selling at the scale pays full cubes; recycling destroys junk for bolts/materials plus 25% cubes and clears the air.
- **Hex levels never drop** (rewards are one-off); Ledger drops can make a clean, unplanted hex dirty again but never touch planted ground.
- **Physics at 120 Hz** for smooth motion on high-refresh displays.
- **Music** is synthesized at startup (no downloadable music source in the container).

## The hero: Lumi (LM-1)
- Name: **Lumi**, designation LM-1 ("lumen"), the seed-keeper bot of the ark *Cradle*. Code identifiers stay `Patch`/`patch_*`; all player-facing text says Lumi.
- Story: 300 years ago Verdance drowned in waste and its people left on the ark *Cradle* with the last seed vault. During a meteor storm a hull breach blew a cargo pod loose; Lumi had climbed in to save a tray of seedlings and was shot out, falling for days back to Verdance. The ark could not turn back; WREN (the ark AI) can only whisper over a failing relay. Lumi's core runs on photosynthetic "green light", and there is no green left, so its battery is dying. Every plant it grows feeds the core; to get home it must clean, grow enough life to charge a Bloom Core, and rebuild the launch sites so a rocket can reach the ark. Ending: the core is full, the planet is green again, and the ark comes home.
- **Told with animation** (story2): the opening cinematic (story/intro.gd) shows the ark *Cradle* in space (Blender model art/models/cradle), Lumi humming in the seed vault, the meteor storm, the pod blown loose, re-entry, the crash and the low-battery wake; off-world shots play in a SpaceStage (story/space_stage.gd, its own World3D in a SubViewport) so the game's sky and lights are untouched.
- **Bloom Core charge** (story/core_charge.gd, flags.core_charge / core_beats): 4% at the start; blooms 16%, this district's hex levels 20%, progress toward the Verdance Bloom 60%. Never drops; reaches 100% exactly with the Verdance Bloom so "core full" and the ark-comes-home finale are one moment. Beats: 25% WREN's signal clears + garden-deck memory, 50% Lumi's glow brightens (PatchModel.core_glow), 75% the ark seen as a moving star at night (and every night after), 100% the finale (story/bloom_finale.gd: the ark descends, beams down, Lumi waves; it stays parked over the district). HUD shows a tiny self-contained ui/core_meter.gd (`set_charge(f)`).
