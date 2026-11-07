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

- **Frontier look pass (wt/biomes2)**: each frontier builds a heightfield terrain ring from the field edge to ~1.3 km (`FrontierView._build_terrain`, `art/shaders/terrain.gdshader`, 8 sector meshes, world-space texturing): transverse dunes with a crusted pan for the big solar farm, snowfields and ridged mountains with the harbour dropping under the sea ice, a drowned bay with green headlands, the Cradle's lawns and hills. FieldView skips its hemisphere horizon in frontiers (`skip_horizon`) and the ground shader stops at the terrain (`clip_r`). Props beyond the edge sit on the terrain (`_gy`). Grades now carry absolute clear-air targets (`fog_density`, `vol_density`, `turbidity`, `height_fog`, `sun`). The Sunken City's field water and flood use a deep, mirror-like teal (water.gdshader look uniforms). Ice sheets use `ice_slab.gdshader`. The saturated blue industrial drum is swapped out of the frontier junk palettes (same vol/weight), and frontier litter fades toward the biome's dust colour. Batched boxes now scale in their own axes (`Basis.scaled()` is a parent-space scale and skewed rotated boxes).
- **Frontier boundaries follow the natural-border warp** (wt/biomes2): every frontier edge samples hex state at the same warped position as the junk (`HexField.border_warp_image` via `FrontierView._share_warp`): the Frozen Port ice is one dense sheet (`ice_slab.gdshader`, per-hex ice image, domes inside and thins to a glassy lip, melt holes as it thaws) instead of per-hex prisms; field water (`water.gdshader` `warp_amp`, frontier-only) and its lakebed (`ground_pbr` `lake_warp`) and the outer flood (`flood.gdshader`) share one shoreline. Ordinary districts keep hex-shaped lakes (opt-in uniforms default off). The field ground's terrain seam (`clip_r`) wanders with noise; the terrain tucks 0.3 m under it to avoid z-fighting.
- **Frontier junk is weathered with an overlay, not new models** (`junk_coat.gdshader`, `FieldView.set_junk_overlay`): sand, frost or silt on up-facing faces mutes bright plastics without touching piece models, counts or saves. Clear air comes from `fog_aerial_perspective` (grade `aerial`) plus lower fog targets, so distance takes the sky's colour rather than a grey wash. The Sunken City turns on SSR at High so the flooded towers reflect.
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

## Wildlife (wt/wild)
- **Procedural animals, not downloaded ones**: Poly Haven has one CC0 animal that fits (street_rat, used for rats); other CC0 sources were not reachable from the sandbox or not consistent in style. Soft ellipsoid/limb models with vertex colours match the toy-like props and stay cheap; one mesh per pose (cat standing/sitting/curled, bird perched/flying).
- **Rig in the vertex shader**: per-vertex pivot + part id (CUSTOM0) and per-instance custom data (phase, gait, packed head yaw/pitch, packed coat + tail) let one MultiMesh per model animate legs, heads, tails and wings with no skeletons or nodes.
- **Animals are pure visuals**: no colliders, no navigation; standing spots and wander targets (plus their midpoint) are checked against live junk pieces, mounds and building footprints. Robots and Lumi pass through them.
- **The plan is stateless**: counts come from hex levels, biome, lake cleanliness and time of day, seeded per district/hex/species, so nothing about the animals needs saving except player-facing progress (sightings, photos, the adopted cat).
- **Sightings need the animal in view and near Lumi**; photo credit needs the animal in the photo camera's frustum at >= ~4% of the frame height (no occlusion test).

## Whole game (wt/beat, Nov 7)
- **The Cradle is the true ending.** The Verdance Bloom milestone (finale, Bloom Core 100%, Seed Ark)
  is met by `cradle_returned` (or 2% of the planet), no longer by "three districts in bloom": that
  path could play the finale early in an ordinary district, after which the Cradle Returns frontier
  ended in a dud, and the Cradle path never opened the Seed Ark.
- **The finale is only "seen" once it has played through** (`flags.bloom_finale_seen` set at the end);
  quitting mid-cinematic replays it on the next load. The end credits (ui/credits_roll.gd, built from
  docs/CREDITS.md, skippable) roll once after the first finale; the game then simply carries on.
- **Bloom Core charge follows the critical path** (`CoreCharge.campaign_progress`): bases at 5,
  frontiers visited / levelled / Growing, the Cradle pad and district. 100% only at the Cradle.
- **Garden ramp at ~1 h** through research (Seedling/Drip blueprints dearer, Pollinator Survey adds
  `plant_growth` / `seed_yield`), not through timers: a player who researches botany early gets it early.
- **Finished districts keep paying** (stipend cap 900/min, Thriving hexes give a little Data), so the
  late base levels and research never stall for good.
- **Goal chain covers the whole game** (144 goals): new types research / bases_l5 / frontier_base /
  frontier_growing. District-relative goals (hex_level, hub_level) are placed where the player is in
  the district they mean.

## Lumi designs (wt/skins, Nov 7)
- **Designs are data + one model**: one PatchModel body with per-design paint/glow and add-on parts from a second GLB (`designs.glb`) built by the same Blender script, so every design shares the hero's rig, animation and quality. Add-ons bake AO against the hero alone (the hero bakes without them), so the default look is unchanged.
- **Buffs are slight and optional**: 5-10% on one themed stat, applied last in `Economy.stat` (after research), shown in the stat breakdown; "Looks only" turns them all off (per save, `flags.designs_looks_only`). Aurora's +8% detector range is on by default.
- **Unlock conditions are any-of achievement conditions** (`Achievements.value_of` + `fleet_tier`), checked by the Achievements tick; old saves keep their earlier unlocks (`flags.skins_unlocked`).

## Late game (wt/late, Nov 7)
- **Worlds are save slots; the profile is the only shared state.** Each Cradle Mode world is a normal
  save in its own slot (Verdance = slot 0), so every system persists per world for free and old worlds
  stay playable. `profile.save` holds worlds, Starseeds and Heirlooms; `--fresh` keeps it in memory.
- **Heirlooms reach the game through one hook** (`Economy.stat` -> `CradleMode.stat_mod`), together
  with world modifiers and decor charm, so no system needs to know about worlds.
- **World 0 is untouched**: Verdance keeps seed 4471 and an empty planet mix, so the campaign, tests
  and existing saves generate exactly as before. New worlds land in their driest town.
- **New Game erases every world and the Heirlooms** (it is a full restart; Heirlooms are permanent
  across worlds, not across profiles). Achievements, Codex and skins carry into new worlds.
- **Each world keeps its own story beats** (seed tin, Ledger, finale): Seed Vault adds seeds but does
  not skip the tin (skipping it pulled the bot into hand-watering and made worlds slower).
- **Decorations refund in full** so moving costs nothing; their bonus is small and per district.
  Wildlife integration is a group hook ("decor" + metas), no dependency either way.


## Planet audio (wt/sound, Nov 7)
- **API** (all on the `Audio` autoload, all safe to call any time; unknown ids and NaN are ignored):
  - `set_planet_theme(id) -> bool`: `"verdance"` (default), `"ochre"`, `"tidewell"`, `"rime"`, `"anvil"`.
    Picks the planet's music track pool and its ambience bed; the first call for a planet synthesizes
    its instruments and ambience (~0.2-0.6 s), so planet code calls it while the planet loads.
  - `set_restoration(0..1)`: the planet's tracks switch to their restored variants past 0.55 (back
    under 0.45; on a chord-cycle boundary) and their brightness / warm bloom lerp with it; the
    ambience crossfades wind, groans and creaks into birds, insects and water. `MusicHooks` feeds it
    every second from `world.planet.restored_fraction()`.
  - `music_activity(amount)`: busy play (hexes cleaned, robots built, upgrades) favours the upbeat
    tracks and pushes their drums; decays over about a minute. `MusicHooks` calls it.
  - Mood `"homecoming"` (`set_music_mood`): the ending piece. It is sticky: `MusicHooks` never
    replaces it; the ending code leaves it with another `set_music_mood()` call.
  - Radio: `play_track(id)` loops one composed track with no gaps until `stop_track()`;
    `music_track_ids(planet)`, `music_track_title(id)` (English; tr() at display), `get_music_track()`.
    `hold_theme(id, restoration)` / `release_theme()` preview a whole planet (pool and bed).
  - `duck(seconds)`: dips music -7 dB and ambience -4.5 dB; WREN's subtitles call it per line.
  - `Audio.loop("hover_spray", level)`: Lumi hovering over water (Tidewell), built on first use.
- **Composed tracks, not just ambient pads**: owner feedback asked for melodic, more upbeat music in
  the spirit of a sandbox-game soundtrack (feel only, all compositions original). Each planet has a
  rotating pool of 2-3 tracks (`audio/music_tracks.gd`) with a fixed motif re-fitted to each chord,
  a groove and a form; pieces are separated by 8-55 s silence gaps (only the air bed plays).
  Verdance keeps its generative score for calm moments and adds two upbeat cleaning tracks.
- **Still synthesized at runtime**, no audio files: the new instruments (marimba, steel pan, hand
  drums, choir pad, detuned synth, metal hits...) reuse `MusicSynth`'s pad and envelope helpers and
  cost ~25-140 ms per planet, built lazily. Pre-rendered OGG loops were considered and not needed.
- **Mix**: a hard limiter on Master (-0.5 dB) as well as Music (-1 dB); ambience on its own
  "Ambience" bus that sends to SFX, so the SFX slider covers it; a slider at 0 mutes its bus.
  Track loudness is kept within about +-2 dB of the generative explore piece (tools/render_music.gd).
- **No new save state**: planet code re-sends the theme on load; restoration comes from the planet.
