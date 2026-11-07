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
- **Pad confirm/back are added to ui_accept / ui_cancel at startup** *(verified)*: Godot 4.7's defaults have keys only, so focused buttons ignored A and screens ignored B. B is also `drop` in play; no gameplay handler reads ui_cancel, so the two never clash.
- **Auto-detected quality only on first launch** — a saved preset (any player choice) is never changed; the frame-rate probe runs once and only steps down. Ultra is never auto-picked.
- **Font floor (12 px) is enforced globally** by a SceneTree `node_added` hook rather than per screen, so new screens inherit it; labels under 4 px are treated as deliberate.
- **Batching keeps the look**: MultiMesh for repeated meshes (object-space data unchanged), merged meshes only for world-space / UV materials; the far skyline's unique roof slabs and masts use world-space triplanar copies (only the texture phase differs, 200+ m away in haze).

## Frontier districts (wt/biomes)
- **Four late-game frontier districts** (`data/frontiers.json`, `planet/frontiers.gd` rules, `planet/frontier_district.gd` live node, `planet/frontier_view.gd` visuals): Dust Flats, Frozen Port, Sunken City and the final Cradle Returns. Each is one extra hub on the planet, **appended after the ordinary hubs** (`PlanetData.frontier_hubs`, `base_hub_count`) so existing hub indices and saves never shift; the frontier biomes are appended to `PlanetData.BIOMES` for the same reason.
- **Frontiers replace planet lakes with their own water** (`Frontiers.water_ids_for`): the Frozen Port harbour east of the quay, the Sunken City flood past the dry ring. Fields are radius 4 (61 hexes vs 37) with `pieces_mult`/`float_mult`/`vol_mult`; bales sell for `value_mult` more at the scale (`Depot.sell_factor`) and base levels cost `cost_mult` more cubes (`Hub.cost_mult`; materials stay as they are because a district's materials are finite).
- **Unlocks are rocket destinations, not map clicks**: the Rockets tab has a FRONTIERS section (`ui/frontier_rockets.gd`) with each kind's checklist (research node + bases at level 5 + the previous frontier's base level); the globe's nearby list only shows ordinary hubs. `Frontiers.can_launch` also gates `slice._launch`. Once visited, a frontier stays open.
- **Sandstorms re-dust with the Ledger's revive mechanism** (`HexField.revive_pieces`): saves (alive bits) just work, and the "never touch planted ground" rule from the Ledger applies. Sustained hexes shelter their neighbours (Dune Fences: two rings). No new junk is created.
- **Ice is a per-hex lock**, `HexField.locked`, honoured by the scoop queries (`find_scoop_target`, `pieces_within`, `nearest_alive`) and by robots' work-hex choice. Thawing is heaters (E, cubes; they also warm neighbours) and Lumi's beam (slow); no new robot type, to keep the fleet readable.
- **Cold**: in the Frozen Port only greenhouses (E with the seed tool) or Cold-Hardy Seeds (research) make a slot plantable (`Garden.plantable`, used by Lumi and Seedlings). Native seeds (`plants.json` `biomes`) grow only in their frontiers; ordinary districts never roll them.
- **Draining the Sunken City turns water hexes into land in place** (`Frontiers.drain_hex`): pieces settle on the street; clean hexes get ~30% of their pieces back as stranded silt debris. Garden slots for drained hexes are made after the others, in drain order (`Garden.late_hexes`), so slot ids stay stable across saves. The city (CityView) sits `sink_m` lower while flooded and rises with each stage, so "rooftops poking out" become streets.
- **The ark finale hook**: when the Cradle Returns landing pad (7 hexes) is clean and every pad hex is Sustained, and 70% of the district's land is Growing or better, `FrontierDistrict.complete()` sets `flags.cradle_returned`, plays the pylon beams and WREN line, and emits **`EventBus.cradle_district_complete(hub_index)` once per save**. The story cinematics (story/*, owned by another helper) should connect to this signal and play the ark-landing finale; `story/bloom_finale.gd` and `story/intro.gd` were not edited. Dev: `--frontier=cradle_returns --frontier-done=3` fires it.

## Steam (Nov 2026)
- **GodotSteam GDExtension, reached only through `Engine.get_singleton("Steam")`** so the game parses and runs with the addon missing (CI, tests, itch builds). Not vendored yet: the project moved to Codeberg, which the sandbox cannot reach.
- **Cloud: Remote Storage API by default, newest save wins** using the `saved_unix` stamp inside the save (file mtimes change on copy); ties keep local; a replaced local save is kept as `.local_bak`. Auto-Cloud stays available with one setting.
- **Demo = same build + `demo` feature tag**, one `Demo.is_demo()` check; separate save folder so a full-game save never opens in the demo, imported once by the full game.
- **Told with animation** (story2): the opening cinematic (story/intro.gd) shows the ark *Cradle* in space (Blender model art/models/cradle), Lumi humming in the seed vault, the meteor storm, the pod blown loose, re-entry, the crash and the low-battery wake; off-world shots play in a SpaceStage (story/space_stage.gd, its own World3D in a SubViewport) so the game's sky and lights are untouched.
- **Bloom Core charge** (story/core_charge.gd, flags.core_charge / core_beats): 4% at the start; blooms 16%, this district's hex levels 20%, progress toward the Verdance Bloom 60%. Never drops; reaches 100% exactly with the Verdance Bloom so "core full" and the ark-comes-home finale are one moment. Beats: 25% WREN's signal clears + garden-deck memory, 50% Lumi's glow brightens (PatchModel.core_glow), 75% the ark seen as a moving star at night (and every night after), 100% the finale (story/bloom_finale.gd: the ark descends, beams down, Lumi waves; it stays parked over the district). HUD shows a tiny self-contained ui/core_meter.gd (`set_charge(f)`).

## Localization (wt/l10n)
- **gettext PO via TranslationServer, English text as msgid** — translators' tools (Poedit, Weblate, Crowdin) read PO natively, Godot loads .po without import, and an untranslated string falls back to English. Keys like `MENU_NEW_GAME` were rejected: they would need a full English table and a rewrite of every data file.
- **Data JSON stays English; translate at display** — `tr(str(def["name"]))` where text is shown, `tr()` before `%`/`.format()` for templated lines. Load-time caches built from data (fleet upgrade names) are translated once, in the startup language.
- **Sinks translate too** (toasts, subtitles, Ledger, captions): raw data lines handed to them work even if a caller forgot; double translation is a no-op.
- **Logic never reads translated text**: robots keep an English `status_text()` (Command view pip colours, tests) and show `status_label()`; prefix checks compare the translated prefix.
- **"System default" only picks complete languages** (`Settings.SYSTEM_LOCALES`, English for now): the de/es samples are opt-in so a German OS never gets a half-German game.
- **Pseudo-locale is generated, Latin-1/Extended-A only** — renders in every shipped font, so a tofu box in pseudo means a real font gap, not a pseudo artefact; the leading `E   ` of interaction prompts is kept because the HUD swaps it for the key glyph.
- **World signage stays English** (shop signs, robot decals): it is part of the art, like painted text on a prop.
