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
- **Nothing works when you land** (owner, Nov 8): no working street lamps, neon signs, string lights, billboards, traffic lights or lit windows at a fresh start; only broken-down things you fix with parts and cubes. The district's street lamps, shop neon and the string lights across streets start dead (cold glass, dark bulbs, some signs hanging off one bracket, more lamps bent; the bent ones stay dead) and come back with a stutter-then-on moment when their hex reaches Sustained, or round the base (30 m) at hub level 3 (`planet/street_power.gd`, `planet/power_fx.gd`, the neon shader's `power`). Yard lights are Hub builds (Yard Lamps, data/camp.json) and hub-level layers, which also flicker on when they arrive. State is derived from hex and hub levels, never saved, so old saves keep what they earned. Check: `tools/light_audit.tscn` (0 lit at a fresh start), `tests/test_dead_power.gd`. Lumi's crashed pod, ruined outposts' dying fault light, the Easter eggs and the Cradle (a working ship) are not the district's grid.

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
- **Real models after owner feedback (wt/fauna2)**: the primitive-built animals read as fake. Now: the cat is sculpted and rigged in Blender (`art/models/fauna/build_cat.py`: one remeshed seamless skin, coat masks in vertex colours, glossy eyes, 8 baked actions) and drawn as a skinned `FaunaRig` with a fur shader + fur shells near the camera; deer, stags and red foxes are Quaternius's CC0 animated animals (smoothed and recoloured by `build_quaternius.py`). Numerous animals (birds, ducks, rabbits, seals, fish) are sculpted in Blender as smooth parts (`build_small.py`) and assembled into the existing MultiMesh vertex-shader rig, so flocks stay cheap. Kenney and Poly Pizza were blocked by the proxy; the Quaternius Google Drive hit its download quota, so the three glTFs came from a public GitHub mirror of the same CC0 pack.
- **Blender needs python3-numpy** for its glTF exporter (`apt-get install -y python3-numpy`); the environment setup script doesn't install it yet.
- **Two-part wings**: the outer wing carries a second pivot (CUSTOM1 = shoulder) so the hand can lag and fold on the upstroke; one rigid wing per side read as a "paper plane".
- **Spacing without colliders**: animals still have no physics bodies. Every place one stands is checked against other animals (body radius per species, including where they're heading), a prop grid stamped from prop-sized meshes (catches the many props that have no collider), one physics shape query on the static layer, fence lines, the yard and outposts. The grid is rebuilt every 90 s rather than tracked live.
- **Perches come from geometry**: the top of any tall, slim mesh (lamp posts, roof crowns, trees) is a perch, read from the mesh's highest vertices, so new props become perches without data.

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
- **A world's look is data, applied after the district is built** (wt/worlds2): `data/world_looks.json`
  per world type, read by CityView / StreetDressing for tints at build time and by `WorldLookView` for
  sky, sky body, weathering overlay and landmark. The grade and weathering ease with the base level or
  field progress but never fully go (a restored Ice Moon is still an ice moon). Frontier districts keep
  their own grade and landmarks; the sky body and Long Nights carry over. Verdance gets no look at all.
- **WREN is clear on new worlds**: she speaks over the ark's relay, so world-thread lines use signal
  stage 2 from the first line instead of the campaign's glitched stage 0.
- **Save profiles are folders** (`user://saves/p1..p3`): SaveManager.save_dir() is the active profile's
  folder, so CradleMode, slots and every system stay unchanged; the Steam Cloud names carry the profile
  as a prefix. Settings are shared across profiles.
- **Planets own their art, the look stays data**: a planet with an env script in data/planets.json
  draws its own landmarks and sky; the generic look keeps grade, tint and weathering.
- **The profile syncs like a save**: it carries `saved_unix` so the Steam Cloud newest-wins rule applies
  to it unchanged; the SteamService autoload syncs before CradleBoot reads it.
- **Decorations refund in full** so moving costs nothing; their bonus is small and per district.
  Wildlife integration is a group hook ("decor" + metas), no dependency either way.


## Homeward: the Verdance system campaign (wt/home, Nov 7)
Canon (consistent with Lumi LM-1, the seed-keeper; the ark *Cradle*; WREN; the Bloom Core; the Makers; the Ledger):
- **The Verdance system is a binary star**: Hearth (warm, yellow-white) and its small orange companion Ember. Every world sees both. From nearest to farthest: Ochre, Verdance, Tidewell, Anvil, Rime. Single source of truth: `data/solar_system.json` read through `SolarSystem.suns_for(id)` (systems/solar_system.gd). The sky director's DirectionalLight is Hearth (shadows, the PhysicalSky disc); `planet/binary_sun.gd` adds Ember (unshadowed warm fill and a soft disc with a thin halo) at the planet's separation, so the pair rises and sets together. Sizes go as 1/AU and light as 1/AU².
- **The Ledger strip-mined the whole system**, not just Verdance: Ochre's sands (open pits), Tidewell's seabed (dredging), Rime's core heat (until it froze), Anvil (its foundry world and head office). When the ore ran out it dissolved itself and left five worlds under its trash; only the audit drones carried on. Each planet tells this in an arrival memo, a half-way intercept and a restored note (`data/homeward.json` docs, DocumentView + Codex "Homeward").
- **The Makers sleep aboard the Cradle.** Their charter, one line long: wake us when the system can feed us. Not one world, all five. So at Cradle Returns the ark comes and answers but will not land ("The Cradle Answers", story/cradle_answers.gd), which replaces the old ark finale at that point. Verdance alone isn't enough.
- **The ending, "Homecoming"**: restore every planet, return to Verdance's Cradle Returns (the Homeward launch complex), build the Mk VII Homeward rocket from all five worlds (one relic from each), plant the last seed in a bed with a yellow fence (Class 4B's school garden), launch. In orbit the Cradle wakes and takes the rocket in; in the seed vault Lumi sets the seedling tray back on its pedestal, three hundred years after climbing into a pod to save it; below decks the Makers wake. Then the existing ark finale (story/bloom_finale.gd) brings the Cradle down to Verdance ("welcome home"), and the credits roll. The game goes on.
Mechanics:
- **Planets are profile worlds with fixed seeds, names, types and modifiers** (`data/homeward.json`, `Homeward.make_planet_world`), so every system persists per planet through the existing slot machinery and worlds2's save slots. A record with `"planet": k` keeps its type when its mix is recomputed (`WorldGen.make(..., type_id)` from `CradleMode.current_full`). Verdance is world 0 / planet 0, unchanged.
- **Random Cradle Mode worlds are kept as the post-game "beyond the system" mode**: the Ark Bridge's "Seed a new world" opens only after Homecoming (`CradleMode.unlocked()` is set by the ending). Every random world keeps its own finale (`Homeward.redirect_finale` only redirects on system planets, and only before the ending).
- **Restoration per planet** (never drops, profile `homeward.pct`): Verdance = its Bloom Core charge (100% when the Cradle answers); the others = 0.5·thriving/target + 0.3·bases L5/target + 0.2·(landing district Thriving share / 60%). The targets are smaller than Verdance's campaign, growing from Ochre to Anvil. System % = mean of the five, shown on the solar map. A restored planet gives its relic and one **Heirloom pick** (Heirlooms become milestone unlocks, no Starseeds; `CradleMode.buy` spends a pick first).
- **Rocket drive tiers are separate from the in-planet Mk I-IV** (`data/homeward.json` drive, profile `homeward.drive`, carried to every planet; the visible rocket keeps its Mk look, so `RocketTiers` and the rocket model are untouched): Mk V Orbital (after the Cradle answers; Ochre, Tidewell), Mk VI Interplanetary (one relic; Rime, Anvil), Mk VII Homeward (all relics, system 100%, built only at Cradle Returns). Priced in cubes and parts. **Per-planet nav**: a planet also needs its chart, i.e. the previous planet at 50%. The in-planet rocket tier is carried too (best of all planets).
- **Travel**: the solar map's Launch (or the autoplay) runs the rocket's own launch sequence with a sentinel target (`Homeward.PLANET_BASE - k`, `HOME`); `automation/rocket.gd` hands the flight to `HomewardDirector.start_flight / travel`: the solar map shows the flight, then `Homeward.travel_to_planet` switches worlds and the rocket's arrival plays there (a new planet gets a rocket parked on the ground, so Lumi can always fly back).
- **The solar map (ui/system_map.gd) is a 3D orrery** in its own World3D: the two suns circling, thin additive orbit lines, planets with restoration rings and labels (name, %, drive needed), two starfield shells for parallax. Selecting a planet glides the camera in; on the current planet "Choose a district" zooms in and hands over to the survey globe full screen (hubs and districts); closing the globe pulls back out. Other planets land at their last district (their PlanetData isn't generated until visited).
- **Text**: all player-facing strings through tr(); data JSON stays English.

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

## Three currencies (wt/money, Nov 7)
- **Exactly three currencies: Cubes, Parts, Seeds** (owner: "keep it extremely low like 3 or less").
  One source of truth: `data/currencies.json` + `core/currencies.gd` (ids, names, icons, colours,
  legacy table). GameState stores only these three.
- **Legacy alias layer, not a hard break**: `add_currency / get_currency / spend / can_afford` accept
  the retired ids and map them at a fixed rate (bolts x5 parts, sheet metal / plastic / glass x1
  parts, Data x10 cubes, compost x0.25 seeds, tokens x5 parts, trinkets x150 cubes, Maker Fragments
  x25 parts), warning once per id in debug builds, so code from parallel branches keeps working
  through merges. `Currencies.fold()` does the same for cost/reward dictionaries.
- **Save v2** folds old balances at the same rates; old compost goes into the compost press's hopper
  (a machine fill level, not a currency) and Maker Fragments into Parts. Nothing earned is lost.
- **Research costs cubes (x10 the old Data) plus real time**; the old Data sources ("field notes":
  hexes cleaned, restored, shards, robot bales, blooms) pay those cubes instead, so research paces as
  it did. Thriving wildlife notes are a small cube trickle (6/min per hex, capped at 300/min).
- ~~Robot part items stay items~~ [ui2, Nov 7]: superseded. The owner found the two "parts" confusing;
  a found robot part now pays Parts at its rarity's value (save v4 converts held items), builds and
  Mk tiers cost Parts + cubes. See "Simpler workbench" below.
- **Contracts and World Events are one Requests board.** Requests pay cubes or parts; the token shop
  became a reward track (liveries, Builder parts, Curio Capsules, rare robot parts at 2..20 finished
  requests; a Vintage part every 5 after). Handled world events count as finished requests.
- **Trinkets are only Collection finds.** Decorations that cost trinkets now need Collection finds
  (`needs_finds`); old trinket rewards pay 150 cubes each.
- **Heirlooms are milestone unlocks** (systems/heirloom_track.gd): the banked restoration score (the
  old Starseed total) passes the old prices in a fixed cheapest-first order. Kept self-contained
  because the "home" helper is replacing Cradle Mode's main flow.
- **Base 2 and 3 ask 150 / 350 parts** (were 25 metal + 15 plastic / 90 metal + 60 plastic + 30
  glass): with one pooled currency the per-type gates vanished; those amounts arrive at about the
  minute the metal and glass used to. Frontier research costs x25 cubes (x10 below): late cubes are
  plentiful where Data used to be the gate.
- **The Ledger is quieter**: one uplink line per act; coupons and quips are small notify-stack
  entries, coupons every 12-20 min (was 4-7).

## Simpler workbench (wt/ui2, Nov 7)
- **One parts**: robot part items became Parts at the rarity's old scrap value (10/25/60/150/450).
  Keeping the rarity roll keeps the detector exciting (a Legendary find is a big Parts payout).
- **Build cost = cubes + Parts** (Scoopie 70, Haul Bug 40, Seedling/Drip 45, Skimmer 60, Multibot
  140; cubes x1.35 and Parts x1.2 per robot owned: a garden needs many Drips, and Haggle no longer
  sells the missing parts for cubes). Mk steps: cubes as before + 200 / 700 / 2000 Parts; the rare
  Restored+ Control Core used to be the gate. Tuned with the autoplay so robots and base levels
  (which also want Parts) arrive about when they did. No rarity bonus any more.
- **No trading**: Haggle's trade, scrap and swap are gone; Haggle survives only as a name in data
  ids ("haggle" source = the Locker shop). His builder stall no longer rotates.
- **Requests start themselves and never expire**: the owner found Accept / Pass / timers too much.
- **Locker at hub level 3**; cosmetic parts are unlocks (owning one fits every robot). Robot Builder
  parts lost their stat mods (pure cosmetics); the Maker set's +5% speed / +6% work is the one perk.
- **Hub card shows "what you get"** computed from data (sell bonus, crew spots, the scrubber,
  stations and Locker levels, the launch pad at 5).
- **Playtest 2: futuristic, smaller, honest costs.** One holo style (BenchKit.holo) for workbench,
  pause and settings. Affordable = green glow, otherwise dim with the missing amount in red. Tabs
  are hidden (not locked) until their data condition holds (data/workbench.json), so the "pace"
  helper can move unlocks without code. No Save button: autosave every minute and on quit; "Quit"
  saves and returns to the title. Keepsakes opens the Codex Collection.

## Keepsakes (wt/extras, Nov 7)
- **One idle-gains entry point**: `Offline.simulate` (time cap, junk cap, `offline_units` bookkeeping) so the welcome card and any remote view (telescope) share one capped calculation; currency only moves in `Offline.apply`.
- **Radio songs are MusicDirector moods** (same key and layers), so they crossfade like any mood; the override lives in Audio and is cleared when the district leaves the tree.
- **Album pictures use a fixed camera over the base**, not the player's view, so before and after line up in the slider; the HUD never appears in them.
- **The weekly challenge is a save slot, not a world**: `WeeklyChallenge.active` steers CradleMode's seed/mix/modifiers; it never banks Starseeds, and its record and chips sit next to the profile so they belong to the save profile, not to a world.

## Planet globes (wt/globes, Nov 7)
- **One reusable component for every planet seen from space**: `ui/planet_globe.gd` (`PlanetGlobe`,
  a Node3D). `PlanetGlobe.new()`, `add_child`, `.setup(planet_id, restoration)`, later
  `.set_restoration(f)`. Optional: `.radius` (the node itself is never scaled, so labels/markers
  parented to it keep their size), `.track_suns(node_a, node_b)` (light from two sun nodes in the
  same world, re-aimed every frame), `.set_sun_dirs(a, b)`, `.set_sun_colors(a, b)`, `.max_lod`,
  `.set_lod(n)`, `.spin_scale`. Unknown ids get a generic rocky world tinted by the optional
  third `setup()` argument.
- **Procedural, unshaded shaders with their own binary-sun lighting** (`art/shaders/planet_*.gdshader`,
  shared maths in `planet_lib.gdshaderinc`): 3D value noise with analytic derivatives, so the
  domain-warped FBM / ridged / eroded FBM heights give real relief normals in one pass; the
  non-smooth features (canyons, terraces, cracks, dunes) bump through screen-space derivatives.
  The globe sets two sun directions and colours itself (SolarSystem.suns_for when present, else
  data/solar_system.json, else the canon), so it looks the same in any 3D view whatever lights it
  has. With no host directions the key light comes from the upper left of the active camera and
  the companion sits the planet's sun separation (canon 14 degrees) beside it. Energies fall off
  with orbit distance at half strength (a UI view: Rime still reads, Ochre doesn't blow out).
- **Looks**: Verdance rust-brown junk continents turning green in spreading patches, murky seas
  clearing to blue, smog clouds turning white, dusty rim turning blue; Ochre dunes, stratified
  canyon networks, a giant terraced strip mine, dust ring + drifting grains; Tidewell island
  chains, reef shelves, three storm spirals, a glint per sun; Rime cracked glassy ice plates with
  glowing blue faults and lineae, polar caps, an orbiting ring of instanced ice spikes; Anvil rust
  highlands, ridged ranges, a great rift, craters, thin lava/foundry seams, a fire ring of embers
  and ash (thin, subtle). Rings and debris are MultiMeshes; motes are billboard quads.
- **LOD**: by screen radius (under 48 px: 4 octaves, 40x20 spheres, 35% of the debris; under 190 px:
  6 octaves; else 8). The telescope caps at 1 below the High preset.
- **How "home" should use it in `ui/system_map.gd`** (not edited here; it lives on wt/home): replace
  each planet's sphere mesh + material with
  `var g := PlanetGlobe.new(); g.radius = <current sphere radius>; parent.add_child(g); g.setup(id, pct)`
  where `pct` is 0..1 restoration (the current world: `world.planet.restored_fraction()`; others:
  their saved share). If the map has sun nodes, call `g.track_suns(sun_a_node, sun_b_node)` so
  each planet is lit from the real suns (otherwise it lights itself from the camera). Call
  `g.set_restoration(pct)` when the value changes; don't rebuild. Keep picking/hover on the globe
  node (add an Area3D child of radius `g.radius` if the map ray-picks meshes). Rings reach 2.5-3x
  the radius on Ochre/Rime/Anvil, so leave orbit spacing for them. Remove the map's own planet
  lights if they were only there for the spheres.
- Not done: the Homecoming / Cradle Answers space shots (`story/space_stage.gd`) keep their
  near-orbit planet shader: they frame a planet thousands of units wide from low orbit, which
  needs a different detail scale than a globe; a later pass can drop a `PlanetGlobe` with
  `radius = PLANET_R` there behind a check.
- **One subtitle line, reading-time rule** (intro2, owner playtest #1): every story/WREN/Ledger line goes
  through `ui/subtitles.gd`: one line at a time at the bottom, 55 ms per character + 1.2 s (min 2.5 s).
  Readable words never scramble while up (a ~150 ms glitch on appearance only); heavy glitching is
  reserved for spans marked `[glitch]`/`[REDACTED]`/`█` (owner: "heavy glitches on what is redacted").
- **Every scene load goes through the loading screen** (`Loader.goto`), with a shader warm-up pass; the
  default clear colour is near-black so nothing ever flashes purple.

## Round planets (orbit, owner decisions Nov 8, 2026)
Supersedes "Planet travel: districts per base on a 40k-hex planet" above.
- **Each planet is one true-scale walkable globe, no curvature exaggeration** (owner: "not that curved, the planets are still super big", the Moon Sweepers feel). Ground looks almost flat near Lumi; the curve shows at the horizon and clearly from Command view or higher.
- **Size: BIG.** GeoSphere level 7 = 163,842 hexes (hexes + 12 pentagons), hex circumradius 10 m, R ~ 1.84 km, 11.6 km around: ~42 min on foot, ~11 min on x4 boost *(verified: lap 11.58 km, back within 0.14 m)*. Cell ids are the survey PlanetData ids, so the hologram, the system map and the walkable globe share one state.
- **Planet % is counted over the hub regions**, not the whole globe. The rest of the globe greens slowly on its own as hubs thrive. You can leave a planet at ~50% and come back later with tools and bots from other planets; 100% needs them.
- **Planets differ in size, growing much larger as you go** (owner, Nov 8, revised): campaign order Verdance → Ochre → Tidewell → Rime → Anvil. Radius vs Verdance (hex size stays 10 m): Ochre 0.85x (a little smaller), Tidewell 1.3x, Rime 1.6x, Anvil 2.0x, so Anvil has about 4x Verdance's area (~655k hexes, frequency 256). Hubs: 10 / 8 / 12 / 16 / 20. Bigger planets never feel slower: Tidewell (3rd) unlocks the **Bot Fabricator**, a bot-building bot that builds robots on its own from cubes and parts, so fleets grow into the hundreds. Each later planet's tools, bots and drive upgrades speed the work up. Robots go out and work on their own (far crews), and a planet's fleet cap grows with its size. Per-planet size lives in data/planets.json `globe`; SphereGrid takes any frequency (cells = 10·f²+2).
- **[orbB] The game's slice runs on the globe under `--orbit`** (phase B): `scenes/slice_orbit.gd` builds into the slice node (it stays `world` for Patch, the HUD and every system), and slice.gd routes a few calls there through `# [orbB]` hooks. Systems are ported by moving them off the "not ported yet" list. `SphereField` is the `field`, and `SphereJunkView` is the `view` (a FieldView subclass). The globe core is `OrbitPlanet` (planet/orbit/orbit_planet.gd), with `OrbitDay` (sky, orbE) and `OrbitCrews` (orbC) beside it. The phase A prototypes stay as `--orbit=globe` and `--orbit=v1`.
- **[orbB] Grids of any frequency**: power-of-two f is the level grid (same ids, so level-6 ids are level-7 ids). Any other f is a class I lattice with slerped rows, which keeps cells as even as the level grids (spacing ratio 1.23 vs 1.20), with explicit `chunk_center`. The survey (PlanetData) runs on the same cells via `GeoSphere.from_grid`.
- **[orbB] Field parity is per cell, made on materialize, deterministic per (seed, cell)**: parts at the flat chance per hex, heaps (cell-local Vector4), wrecks at the flat districts' rate, locked biome cells, and floating junk on lakes (lakes with junk are junk hexes). The globe's JunkLOD uses JunkLod's near/far scheme for a growing piece set, under a per-frame budget.
- **[orbB] Frontier districts retire on the globe** (main, Nov 9): Dust Flats, Frozen Port, Sunken City and Cradle Returns become parts of the other planets rather than districts of Verdance's globe, so they are not ported to the orbit slice. Their flat code (planet/frontier_district.gd, planet/frontiers.gd, frontier views) stays untouched until phase F retires the flat game.
- **[orbB] Flat systems on the globe**: per-hub state lives in the hub site's own dict (`GameState.use_orbit_world`; the flat district's dict is kept for saves); yard systems stand on the hub-0 prefab's anchors (`SliceOrbit.yard_slot` / `yard_point`, re-seated by `reseat_yard` when anchors move); flat code is made globe-aware line by line with `OrbitUp` (local up, distance along the ground, the hexes around a point), which returns exactly the flat values on the flat game; whole-field scans visit the hub region, never all cells; HexLevels and the garden run sparse (per cell, on demand). A piece's ledger volume is scaled for pacing; `HexField.visual_vol` says how big it looks.
- **[orbB] Flat-yard systems run per hub in a HubFrame** (planet/orbit/hub_frame.gd): fauna, eggs, outposts, the Ledger arc and Garden Mode's decor are built under a node on the site transform of the hub Lumi is nearest (site-local metres, +Y up, so their flat coordinates and maths carry over), and they convert only at their edges. They are rebuilt when Lumi comes within 220 m of another hub and sleep beyond 320 m from every hub. Per-hub state stays in the start site's dict, keyed by hub (`orbit_outposts`, `orbit_decor`); hub 0 keeps the flat keys. Story state stays global (flags). Things far from the hub (outposts, the relay) are seated on the ground's own up, not the frame's. Physics checks on the globe include `PhysLayers.PROP`, because the site prefabs build with prop colliders.
- **[orbB] The globe's save is its own key, `GameState.orbit`** (`core/save_orbit.gd`, schema 2). It holds the cells (packed), sites, hub states, paid hexes, sparse hex levels, and positions as direction + height. An orbit run never rewrites the flat state (`world` / `districts` / `planet_state`) until phase F. **Old flat saves migrate** (`core/save_orbit_migrate.gd`): the level-6 survey spreads exactly over the level-7 cells by hierarchy, base levels go to the nearest globe hub, and Lumi starts on the start site with his chest. Only Verdance's size takes a level-6 survey.
- **Travel**: walk, the x4 hover-boost (Shift / LT), later a buyable ground vehicle or hover-sled. The rocket hops between far hubs (10 hubs, ~1.6-1.7 km apart); walking hub to hub is possible but impractically long.
- **Day and night are real sides of the planet.** The two suns are fixed in space and light one side; the planet turns once every **24 minutes** (`--orbit-day=MIN` to tune, 20-30 min range), so walking far changes your local time and every spot gets a day/night cycle. Nights stay readable: lifted ambient and exposure, and a light on Lumi (Glim takes this over once found).
- **Hubs are sites on the globe**: each a level pad (`SphereTerrain.reserve_site`, flat + blend radius) with its base and landmarks built as a site prefab in site-local metres (`build(site_root, stage, restoration)`, +Y up, y = 0 on the pad).
- **Streaming**: only the ground near the camera, Lumi and working robots is 3D (threaded LOD chunks, collision within 70 m); scoopable junk exists only in a ~70 m ring per centre and is otherwise a number per hex (SphereCells); the rest of the globe is a low-detail shell reading the same per-hex state texture. Robots far from Lumi are data records advanced like offline progress.
- **Phase A (`--orbit`, default off)**: the real Lumi (`player/patch.gd`) runs on the sphere through `Patch.enable_sphere()` + SphereMotor (hover, radial gravity, boost, jump, camera-frame input); the flat game is unchanged when it isn't called. Bales fall with radial gravity (a point-gravity Area3D); the Depot reads its pad in its own frame. `SphereField` (a HexField over SphereGrid cells) and `SphereJunkView` give Patch, the HUD and the Depot the APIs they already use.
- **[world2] Props are solid, on their own layer**: street furniture, yard kit, sign posts, outposts,
  eggs, the composter, greenhouse, pod, hub additions, future-layer posts and frontier ruins collide on
  `PhysLayers.PROP` (`planet/phys_layers.gd`). Lumi, robots and bales mask it; the camera spring arm
  does not (thin poles would yank the camera in). Simple boxes/cylinders with shared shapes
  (`planet/prop_colliders.gd`); merged frontier geometry gets greedy-merged column boxes. Junk that
  spawns inside a prop is nudged to its edge at load (deterministic; only alive bits are saved).
  Tiny clutter (pots, weeds, paint, wires, junk, litter) stays non-solid. `tools/collider_audit.gd`
  must report 0. Robots have no navmesh; their detour/stall logic handles the new obstacles.
- **[world2] No yard fence**: the owner walked through it and it boxed Lumi in at the start. Lot fences
  elsewhere are broken runs with gaps, each run solid.
- **[world2] Junk gen 2 (new games)**: the only clear ground is what Lumi or the bots picked up. No
  mid-road sparsity, a full ring around the base, landfill junk between the heaps, and the streets of
  building-blocked hexes plus the hub hex outside the yard belong to the nearest junk hex
  (`HexField.owner_hex`), so they are covered and clear with it. Each hex keeps gen 1's junk volume
  (more, smaller pieces), so bales, cubes and hex flips pace as before. Old Town's field is radius 4
  (was 3); past the field a static, non-interactive junk layer (`planet/far_junk.gd`) keeps the planet
  covered, and WREN explains the survey line once. Saves without `junk_gen` keep gen 1 and radius 3.
  Frontiers stay radius 4 (now the same hex count, still denser and tougher).
- **[world2] Bales**: collider = the drawn bale (straps included; overstuffed bales get their wider,
  flatter box), CCD on, lifted out of anything solid after a spawn or put-down, put down short of
  walls, and junk mounds are solid for bales only (`PhysLayers.MOUND`, `planet/mound_colliders.gd`).
  The bale shader is explicitly opaque, with desaturated per-item chunks, labels in the dominant junk's
  accent colour and rough, sparse metal. **Root cause of the "transparent" bale**: its mesh,
  `ProcMesh.rounded_box`, was inside-out (counter-clockwise from outside, so back-face culling showed
  the far inner walls: a see-through box tinted by the pale-blue plastic colour). rounded_box (used by
  ~130 props) and the junk-heap mesh now wind clockwise from outside; `tests/test_bale_rest.gd`
  checks the winding.
- **[world2] Playtest #2 follow-ups**: junk heaps are solid for Lumi and robots too (MOUND | PROP),
  drawing in as the hex is cleaned, so piles are scooped from the edge, not vacuumed from inside.
  Hub/blocked hexes' ground follows the junk hexes that own it (no clean-looking patches). Pieces
  carry a size class (`HexField.piece_size`: SIZE_SMALL / SIZE_MEDIUM / SIZE_LARGE, from the
  model's base volume, LARGE >= 2.5: tyres, TVs, microwaves, stoves), and the starting ring has no
  large pieces (re-picked from the same type on their own RNG). Carried bales sit above Lumi's head
  (`player/carry_point.gd`). The bale is a pillowed, lumpy pressed block with three straps one way
  and two across.

## Character Builder (wt/style, Nov 7)
- **A style is a layer the hero model reads**, not a fork of it: `systems/lumi_style.gd` (data `data/style_parts.json`). Two tagged one-line hooks in `PatchModel._build` (`# [style]`): first line `var v: Dictionary = LumiStyle.variant_for(self, VARIANTS[variant])`, last line `LumiStyle.after_build(self)`. `variant_for` turns the style into a VARIANTS-shaped dict (so PatchModel builds its own native add-ons and colours); `after_build` recolours what VARIANTS has no key for and adds a `LumiStyleRig` child (`player/lumi_style_rig.gd`) for eye shapes and non-native add-ons. Hero rebuild: keep both hook lines, keep `_mats`, `_face_mat`, `_ring_mat`, `_float`, `_head`, `_arm_l` (with meta `wrist`), `_icon`, `_part()`, `_paint()`, `_load_parts()/_parts/_pivot()`; everything is read through get()/has_method() and degrades quietly if missing.
- **The six designs are presets** read straight from `PatchModel.VARIANTS` (`LumiStyle.preset(id)`), so a preset reproduces the design exactly (tests/test_lumi_style.gd checks every VARIANTS key and acc id, and `unmapped_acc()` flags a renamed add-on).
- **Bonus = worn design**: the style's `bonus` is written to `flags.patch_skin`, so `Designs.mult` and "Looks only" are unchanged; a custom look can take any unlocked design's bonus. A model of variant X shows the worn style only when its bonus is X, else X's preset (dev `--design=`, previews and lineups keep working).
- **Eye shapes without touching bot_face**: crescent and happy arcs are native (happy = VARIANTS `happy` 1.0); round / visor bar / hearts are a `next_pass` (`art/shaders/lumi_eyes.gdshader`) on the face material, with bot_face's eyes hidden by `eye_radius = -1`; look/blink/wink/happy/energy/eye_color are copied each frame. If the hero adds native shapes later, drop them from `LumiStyle.OVERLAY_SHAPES`.
- **Colours saved as [r,g,b] floats** (4 decimals) in `flags.lumi_style`, `flags.lumi_looks` (5), `flags.style_bought`; swatches are hex in the JSON. Off-swatch colours need the advanced picker (80 parts); the designs' own colours are always allowed once the design is unlocked.
- **Unlocks trickle over the whole game**: free starters, Lumi Level, hub level, each design (its parts and colours), Collection finds, Requests, achievements (Alive Again, Gardener, Overachiever, A District in Bloom) and a few buys for parts/seeds only.
- **Add-on names the applicator expects** (add-on library = aurora.glb + designs.glb mesh names; first found wins, else a procedural stand-in):
  - native PatchModel acc ids (VARIANTS `acc`, built by PatchModel): `antenna` (fin), `acc_sprout`, `acc_catears`, `acc_pixel` (wing fins + heart lenses), `acc_pad_r`, `acc_pad_l`, `gear` (mesh `acc_gear`), `acc_toolbox` + `case` (mesh `acc_case`), `holo`, `butterfly` (meshes `acc_bfly_body`, `acc_wing`); chest icons `acc_icon_leaf`, `acc_icon_cross`.
  - library meshes the builder picks up if the hero models them: `acc_antenna` (plain antenna, head-relative pivot like `antenna`), `acc_halo` (head-relative pivot), `acc_icon_heart` (same pivot as `acc_icon_leaf`), `acc_medkit`, `acc_watering_can` (left claw, origin at the grip), `acc_firefly`, `acc_drone` (companions, origin at the body centre, facing -Z).
  - material slot `side` on the side-module plates (optional `_mats["side"]`): the side-module colour; until then side modules follow trim.
- **Locked cosmetics are never shown** (owner playtest #2): locked designs are a dark silhouette (`LumiStyle.silhouette`, `DesignPreview.show_design(id, hidden)`) named "???" with only the unlock hint; locked presets, parts, swatches and bonuses in the builder are "???" cards / grey "?" swatches with the hint.
- **Other dressable bots plug in through `CosmeticTargets`** (`systems/cosmetic_targets.gd`): `register(id, {name, order, editor: Callable(world) -> Control, unlocked: Callable -> bool, hint})`, `all()`, `make_editor(id, world)`, `display_name(id)` ("???" while locked). Lumi is built in (`LumiBuilder`). Part unlock rules can reuse `LumiStyle.unlock_met / unlock_progress / unlock_text / buy` with their own data.
- **LumiBuilder is a hostable Control**: `var b := LumiBuilder.new(); b.world = world; parent.add_child(b)` (embedded: no backdrop, the host owns Esc and LB/RB, footer button "Wear look", signals `worn` / `closed`), or `LumiBuilder.open(world, parent)` for a full-screen overlay (CanvasLayer 100).

## Planet 1 redesign (Phase 0, Nov 9, 2026)
The owner's new brief: finish Planet 1 as a complete, polished, original experience on planet-agnostic systems. Reference games are for feel only. The lead may make large changes without asking, except to the core premise or the realistic art direction. Details in `docs/PLAN.md`; tasks in `docs/TASKS.md`. These calls are proposals until the owner approves the Phase 0 summary.

- **The audit ran on the main line, not the stale hero branch.** `claude/kind-wright-rhxixd` was merged into `claude/greenfall-aurora` first (967 tests pass). Conflicts: the hero face shader was kept (it is a superset), the quieter detector and the petting pose were kept from main.
- **Aurora's default eye is the solid shape.** Main carried a later owner decision (one solid glowing eye per side). The concept's crescent stays as a builder option. The two eye systems are unified in task M1-13.
- **Planet 1 must be finishable on its own (R1).** The 68% restoration cap and the dependency on tools from later planets are removed for Planet 1. This reverses the Nov 8 "leave at 50%, return later for 100%" rule for this planet; that idea is noted in `docs/FUTURE.md` as optional extra ground only.
- **Districts as chapters (R2).** Six of the ten hub sites form the main path, each with its own pollution kind, tool and source job. The rest are optional ground.
- **Target playtime: about 4 hours** to the ending for a first-time player (3.5-5), about 8 for full completion. The owner's earlier figure for Verdance was 3-4 hours.
- **First robot at about minute 20, as an apprentice (R4).** This keeps the owner's earlier call that automation comes later, and answers the new brief's "real grind" pillar: robots can only do what Lumi has mastered by hand.
- **No real-time waits (R5).** Research and growth advance from play.
- **The flat world is removed (R8)** rather than kept behind a flag. It has not been playable since "round world is the only mode".
- **Later planets, the travel layer, the prestige mode and several side features are parked (R10).** Allowed by the brief ("you may remove or restructure it"). Each item is listed when task M1-08 lands.
- **Originality.** The repo's notes name the main reference as the model for the map view, the workbench layout and the hub's hero building; the owner had already flagged the map as too close. All three are rebuilt in our own style (M5), and mentions of other games are removed from code and data (M1-14). The lead cannot inspect the reference game from this environment, so the side-by-side check needs someone who can.
- **UI identity: a field instrument** (`docs/STYLE.md` section 10). Chosen because it comes from the theme (Lumi is a survey and salvage machine) and suits the realistic art direction.
- **PlanetDefinition is a typed Resource that points to JSON tables.** The game's content is already JSON with tooling and translation hooks; a Resource adds typing and validation without rewriting 55 data files.
- **One extra agent: world-artist.** The brief's list had no owner for 3D environment and model work, which is a large part of this game. No agents were dropped.
- **Earlier owner feedback that conflicts with the new brief** is resolved in favour of the new brief, and listed in the Phase 0 report: the workbench "like" the reference game, hubs "as good as" the reference game's hubs (kept as a quality bar, not a design model), and the round-planet structure by reference (kept as a structure, with every specific made our own).

## Owner approval of Phase 0 (Nov 9, 2026)
The owner approved the plan and left the open calls to the lead ("decide what is best").
- **Eyes: the concept sheet's cute crescent eyes, never solid discs.** Aurora, Sprout, Nova and Patch rest on the crescent; Bolt and Pixel rest on the smiling arcs, as drawn on the sheet. This reverses main's Nov 8 solid-eye change.
- **The flat world is removed.** Planets are round.
- **Later planets must work in future.** They are parked, not deleted: their content moves behind the PlanetDefinition system as data and planet-folder scripts, out of the Planet 1 build, with a test that a second planet still loads.
- **Lead and branch.** This session leads the Planet 1 work on `claude/greenfall-aurora`. Work from other branches is merged in by the lead only when it serves the plan.
- **Target playtime stays at about 4 hours** to the ending.
- **Agents.** Fifteen definitions in `.claude/agents/`, all on Opus 5.5. Code-changing agents work in their own git worktrees; the lead reviews and merges. Two or three run at a time.
- **Models (owner, Nov 9).** Opus 5.5 agents do routine execution. Fable agents may be used for work where being right matters most: reviewing large refactors, the save format, and checks on core design.
- **All six robot designs must match the concept sheet** (`art/concept/lumi_concept.png`), not only Aurora. Animation that "makes sense" is wanted but is a later pass.
- **PlanetDefinition landed** (`core/planet_definition.gd`, `autoload/Planets.gd`, `planets/verdance/planet.tres`). For now its tables point at the existing files in `data/`; task M1-06 moves them into the planet's folder. A dummy planet in `tests/fixtures/planets/testworld/` proves a second planet registers from its folder alone.
- **Looks are found, not earned by counters (owner, Nov 9).** In the owner's playthrough the other designs unlocked far too fast: they opened from easy counters (50 bales, 5 animals petted). Now every cosmetic is a physical piece found in the world; designs are rare sets of pieces from robot wrecks, district sources and secrets; nothing cosmetic is bought. The Locker is a place the player builds and the only place looks are edited. Spec: `docs/design/PLANET1_DESIGN.md` section 13. Tasks M3-14 to M3-16.
- **The whole robot matches the sheet.** The six-designs task covers body colours, wear, add-on pieces, chest plates, glow colours and eyes, and makes each piece separately wearable for the Locker.
- **Fable 5.2 for everything (owner, Nov 9, replaces the Opus note above).** Every agent definition uses Fable 5.2. The three Opus jobs were stopped and continued by Fable agents from their preserved working copies.
- **Quality bar (owner): a premier, high-quality game.** When a task can be done quickly or done properly, it is done properly; reviews compare against the concept art and the Definition of Done, and anything short of it is listed, not hidden.
- **Interim: design unlocks made much harder** (`data/designs.json`: 400 bales, 250 blooms, 20 trinkets, 25 research projects, a Mk III fleet) until found pieces replace the counters (M3-14).

## Planet 1 is only the beginning (owner, Nov 10, 2026)
- **One new design on Planet 1.** The player starts as Aurora and can complete exactly one more design there: Sprout, finished near the ending. Bolt, Pixel, Nova and Patch are for later planets, one each. This replaces the earlier "two complete designs by the ending".
- **The same restraint applies to everything else.** Planet 1 stops short of final robot tiers, tools and base levels, so later planets have real things to add. The balance plan (M3-01) sets where each track stops on Planet 1.
- **Character design is parked (owner, Nov 10): "pretty close for now".** The six designs as merged are the working versions. The lead's own review found shared gaps against the portraits (head too tall, eyes too fat, body and arms too small, wear too light); they are listed in task M5-13 and wait until the owner returns to character design. The lead sized the head from the turnaround row earlier; the portraits are the better guide and M5-13 follows them.
- **The magnet cap was flat-only** and went with the flat world. The owner's rule (capped; never pulls what Lumi cannot lift) is restored as bug B23.

## Parked features (M1-08, Nov 10, 2026)
Moved to `parked/` (ignored by the engine; `parked/README.md` lists each feature and its dependencies): the multi-planet campaign and solar-system travel, the telescope, the prestige mode with heirlooms and the endless seed-delivery loop, the weekly seed, the museum building, the robot-building station, the profiles screen, and their tests. Twenty achievements that could no longer be earned went with them.
- Planet restoration is read through `Restoration.value()`; task M1-10 gives it a data rule.
- The 68% cap on Verdance and the research locks that waited on later planets are gone.
- The title screen is Continue, New Game, Settings, Quit.
- Story text that still promises parked things (the finale and credits say the seed ark opens; 11 radio hints) is left for the story pass in M5.
- Stopgaps to clear in M1-07: `data/parked.json` skips 17 goals that belong to parked features; the `observatory` research node unlocks nothing.
- **Bug-fix pass (M1-11).** The Baler stall is fixed by counting a sold bale toward the first bin step, not by keeping the bin open: an always-open bin would pay 1.3x against 1.0x for a plain mixed bale and empty the chest by itself, which would make it better than baling. That 1.3x figure is noted for the balance work (M3-01): tipping loose trash should never beat pressing a bale. The magnet's cap and filters and the refill radius (24 m) are now data.

## World, crew and currency direction (owner, Nov 10, 2026)
The owner asked for more attention on the world's goals and look (full cities round the planet, full of junk), on robot design and the pacing of building and upgrading robots, and on currency pacing that makes sense: parts hard to get early, numbers that do not climb fast, and in the long term a robot that finds parts. Design sections 14 and 15 hold the rules; tasks M3-17 to M3-20.
- **Small numbers on Planet 1.** The biggest purchase stays under 50,000 cubes; no reward bursts; no income jump over 3x. This replaces the current curve, where one objective paid 68,000 cubes at once.
- **A crew of 10 to 12 by the ending**, two robot tiers. This replaces the earlier figure of 24.
- **The Scrounger**, a parts-finding robot, unlocks late on Planet 1 as one unit that marks buried parts for Lumi to dig. The self-sufficient version is for later planets.
- **One job per currency, no conversions.**

## Correction: crew size and the two goals (owner, Nov 10, 2026)
- **The lead was wrong about "fewer robots".** The owner asked to look at the pacing of building and upgrading robots, not to reduce their number. The crew reaches about **100 to 200 robots** by the point where the player can move on; cleaning the whole planet takes thousands.
- **Moving on does not require finishing the planet.** Planet 1 has a launch point (six cities thriving: the big moment, the end of the demo, the hook) and a separate long goal (the whole globe). This replaces "Planet 1 is fully restorable in about 4 hours" (R1): the 4-hour target now applies to the launch point.
- **A production queue for batch building comes back to Planet 1** (a simpler form of the parked robot-building station), because nobody should build 150 robots one click at a time.
- **The fixed 50,000-cube cap and the 30% hand-share rule are dropped**; both were the lead's numbers and do not fit a crew of 100 to 200. The owner's rule that currency must not climb fast stays, and the simulator reports the largest prices and incomes for the owner to judge.
- **Robot creation is a chain of robots, not a queue (owner, Nov 10).** Scroungers find and deliver parts; an Assembler builds robots from them, including more Scroungers. This replaces the lead's production queue and the earlier Scrounger that only marked parts. The loop is limited by travel time, by parts running out in an area (so growth follows cleaning) and by assembly time, so the crew cannot explode and numbers stay paced.
- **The Assembler (robot-building bot) arrives at city 3 (owner, Nov 10).** Through cities 1 and 2 every robot is built by hand; Scroungers arrive in city 2 and only supply parts until then.
- **Planet-agnostic shared code (M1-07).** All five planets are PlanetDefinitions in `planets/<id>/`; only Planet 1 ships. The later planets inherit Planet 1's content tables until their own are written. Shared code holds no planet name. Mentions of other games were removed from code comments (five lines); the designs those comments described (the hotbar, the hub's main building, the kit palette) are on the originality list for the UI and world passes.
- **The Assembler is a factory building, not a robot (lead's call; the owner left it open, Nov 10).** It fits the base's build ladder, gives city 3 a visible landmark, shows the chain in the world (parts in, robots out) and upgrades naturally. The numbers are the same either way.
- **Bright and colourful, never gloomy (owner, Nov 10).** The lead had read "realistic, not cartoonish" as "less colour" and called the colourful junk and the teal and orange workbench faults. That was wrong. STYLE section 9 now says: realistic in detail, bright in mood; junk and cities stay colourful; no brown or grey grade; restoration adds colour. World and visual work moves up to run alongside the core-loop milestone instead of after it.
- **After the first balance proposal (design section 16).** The lead settled the conflicts it found: robots earn no cubes (keeps numbers small with a large crew); the watering robot moves to city 4 and clears smog; city 6 is the launch site where the rocket is built; robots slow with distance from a base, so the whole planet needs outposts and thousands of robots; rigs get crew-affecting modules; seeds and parts get late uses.

## World audit (M3-17, Nov 10, 2026)
`docs/reviews/WORLD_AUDIT.md`. The world is bright and colourful up close (open junk fields, city streets with brick, murals and signs) and pale, empty and brown-backed from any distance: junk draws to about 70 m, the fog is grey, the sky below the horizon is brown, and from above cities wash out to white boxes. Cities are small street cores; nine of ten have a junk-free centre; none has a landmark tied to its pollution source; nothing in a city changes with regrowth.
- **The six cities** (lead accepts the audit's proposal): Old Town (site 0, litter, a burst-main pumping station), Ironside (site 7, wrecks, a crusher yard and gantry), Kettle Bay (site 3, fouled water, a grounded leaking tanker), Highreach (site 8, smog, incinerator stacks), Lowmeadow (site 9, poisoned soil, a treatment works), Old Capital (site 1, the launch site). The other four sites are open ground.
- **"The entire world is trashed, no cleared spots" is the wanted start state**, so junk now reaches the town centres.
- **A changed fresh world does not have to match old saves' worlds.** Old saves keep loading with their own world; new games get the improved one.
- Quick wins Q1-Q14 are applied first (task M3-17b), each kept only after a before-and-after render.
- **Second balance proposal accepted (design section 17).** Largest price 4,200 cubes (was 39,383), peak income 103 a second (was 1,739), launch at about 3 h 45 with 149 robots. The lead confirmed the rule that a hex, not a unit of waste, has a cube value.
- **Open for the owner:** on these numbers the whole planet needs hundreds of robots (about 115 to 460 depending on how many hours it should take), not thousands. Making "thousands" true means slower robots far from a base or a much shorter target time; the lead has not changed anything for this.
- **World quick wins kept (M3-17b).** Two needed a call: junk now reaches town centres although it breaks the 10% performance limit there (the look is what the owner asked for; task M7-07 recovers the cost), and about four in ten street lamps glow at night in the nine other towns (the start town stays dark, as the owner's earlier note asked).
- **Still wrong after the quick wins:** city roofs read white from above; the start yard's pad is a big empty pale slab; from far away towns are white specks; flat litter sheets look like plain paper up close.

## Economy in the real game (M3-19 + M3-02, Nov 11, 2026)
`docs/reviews/M3-19_ECONOMY.md`. The accepted rules are in the game. The bot's first minute is fast, then the game runs 1.5 to 2.5 times slower than the proposal (first robot at 23.7 minutes, proposal 9.4) because the proposal's model had no walking.
- **The game's real walking is the truth; the numbers move to fit it.** The simulator gets distance, then prices, hex weights and rewards for city 1 are refitted so the bot meets the cadence rules (first hex under 90 s, no wait between purchases over 120 s in the first 20 minutes, first robot by minute 12).
- **The yard is laid out for the first minutes:** junk starts within 4 m of the bin and the first hex's middle is within 8 m.
- **The first robot is the answer to walking.** A hauling helper arrives early in city 1 and carries bales to the scale, so Lumi stays at the work. No moving drop points.
- **Research prices in city 1 are capped with everything else** (largest price in city 1 stays under the accepted 4,200).
- **Old Town look (M3-18a) merged.** Kept as bright and colourful. Tree crowns, the fountain, the crash furrow, a render of the fully restored stage and the street's triangle count go to M3-18b.

## City 1 pacing fit (M3-21, Nov 11, 2026)
`docs/reviews/M3-21_PACING_FIT.md`. First hex 54 to 86 s, first robot at 8.5 to 9.7 minutes, largest city 1 price 4,000, most cubes held 709. Merged.
- **The first robot is a Haul Bug, the Scoopie follows about 8 minutes later.** This reverses the owner's note of Nov 9 (items 44 and 46: the Scoopie first, the Haul Bug later). Reason: walking bales to the scale is the slow part of the first quarter hour, and a hauler is what fixes it. **Flagged to the owner; reverted if they prefer the old order.**
- **The first seed sequence counts as a reward beat** in the purchase-wait rule: it is a story moment with a reward, not dead time. The remaining longest wait (130 to 136 s) is accepted on that basis. Trimming dead walking out of the sequence goes to the tutorial milestone (M4).
- **Hexes under 60 s after the Haul Bug** are left for the balance pass (M3-12), where ring 2 hex weights are set with the crew numbers.
- **Shared stage payouts for stages 4 and 5 were cut about 40%** for every city; cities 2 to 6 are refitted in M3-12.
- Fixed at merge: the card's new `scoopie` step had no guidance and pointed at the bench before the plans arrived (regression test in `tests/test_v1guide_guidance.gd`).
- Old Town polish (M3-18b) merged: still below the bar are clumpy crowns up close, faceted flowers, flat lawns, pale flood water and pale lots at stages 1 and 2. These go to the M5 polish pass.

## Crew and the robot chain (M3-20, Nov 11, 2026)
`docs/reviews/M3-20_CREW.md`. Crew after each city (simulator): 8, 50, 74, 98, 123, 159, against the accepted 8, 50, 72, 94, 119, 147. Scroungers find Parts in a painted Search area; the Assembler builds robots from them with a player-set build mix; 200 robots cost 5.4 ms a frame. Merged.
- **The Assembler is offered on reaching city 3 and stands in the start yard** (the only base with a bench). When cities get bases of their own it can move to city 3.
- **Scroungers must matter.** Today a player with no Scroungers still reaches 140 robots because hand-found Parts are plentiful from city 3. The balance pass (M3-12) cuts hand yield in cities 3 to 6 so the chain is the way to a large crew.
- **Robots are shipped between cities, unseen**, for now. A visible transport goes to `docs/FUTURE.md`.
- **Tier steps open with city 2** until a repair-bench research exists.
- **Originality:** a factory that turns found parts into robots is a common genre mechanic; nothing here copies another game's layout, names or interface.
- Not yet verified in a played run: cities 2 to 6 and the Assembler panel's layout (simulator and tests only). Covered by the end-of-milestone bot playthrough.

## The other five cities (M3-18, Nov 11, 2026)
`docs/reviews/M3-18_CITIES.md`. Ironside, Kettle Bay, Highreach, Lowmeadow and Old Capital are built, bright and colourful, each with its own palette and source landmark; every street view is under 6 M triangles on Medium. Merged.
- **Follow-up M3-18c (lead's review of the sheets):** the restored yards show bare sand and dark kit plates instead of Old Town's paving and lawns; running and shut-down landmarks look alike from the street in Ironside, Kettle Bay and Old Capital; Highreach's smog does not reach the streets (it must be a coloured haze, not grey); Old Capital's launch pad must read as the goal of the whole game; Lowmeadow is thin; two yard views are just over budget.
- Landmark close-up detail (bolts, ladders, railings) and animation go to the M5 polish pass.
- A save round trip check failed once and then passed four times (`orbit_ledger_drop_dirties_cell`); given to the bug-fix pass as flaky.

## City polish (M3-18c, Nov 11, 2026)
`docs/reviews/M3-18c_CITY_POLISH.md`. Restored yards get city paving, lawns and flowers; Ironside's crane swings with smoke and sparks; Kettle Bay's oil leak and slick are on the near side; Highreach has a magenta-to-coral street haze that clears on shutdown; Old Capital has a flag avenue and named gate to the pad; Lowmeadow doubled to 869 houses; all views under 6 M on Medium. Merged.
- For the M5 polish pass (lead's review of the sheets): restored paving is a little candy-pastel (Highreach pink and mint) and should be warmer; the launch pad is still small from the yard; effects were judged from stills only and need a watched run; budget margins are thin (0.4 to 1.4%).

## Pollution kinds (M3-04, Nov 11, 2026)
`docs/reviews/M3-04_POLLUTION.md`. Litter, wrecks, slick, smog and blight are data-driven kinds sharing one waste ledger per hex; a hex is clean only when every kind is cleared; Lumi's takes pay the hex's cube value, robots earn nothing; a sixth kind on the dummy planet needs data only. City 1 pacing unchanged (first hex 55 s, first robot about 9 minutes). Merged.
- **Each city's kind needs a real new tool** (lead): today the gates are already met on arrival (Lift Strength 2 is bought in city 1; smog and blight need only garden tools). Rigs (M3-08) supply each city's tool: a cutter for wrecks, a scrubber for smog, a soil treatment for blight; mastery (M3-05) keeps robots off a kind until Lumi has learnt it.
- **All kinds end in the chest** for now; whether smog and blight pay as field work is settled in M3-12.
- Highreach lists slick with no lake to hold it: removed in M3-12 with the other first-value shares and densities.
- Not yet seen in a played run in cities 2 to 6 (rule tests only); covered by the end-of-milestone playthrough.

## Looks from found pieces and the Locker (M3-14, M3-16, Nov 11, 2026)
`docs/reviews/M3-14_16_LOOKS.md`. Every look is made of pieces (`data/cosmetics.json`, `systems/looks.gd`); a piece is worn only after it is found (`systems/finds.gd`, the planet's `finds` table). No look opens from a stat, a level, an achievement or a price any more.
- **Found pieces are the first thing in the save's `global` section** (`GameState.global`, save version 5). Which finds a planet has handed out is in the planet's own section.
- **Finds are fixed by the planet's seed, not rolled live.** A buried tin turns up at the same cleaned hex in every run (chance per hex from `from_hex`, certain at `by_hex`), so the simulator and tests can replay it and a reload cannot re-roll it.
- **Planet 1 hands out Sprout (7 pieces over the six cities, the last from Old Capital's source) and nine loose colours.** Bolt, Pixel, Nova and Patch have no find here.
- **A set's bonus needs every piece of the set worn.** The free "bonus" picker is gone: a mixed look gives nothing. Slots the set does not use may hold anything. Aurora's own five pieces are the starting set, so her detector bonus is on from the start as before.
- **The Locker has eleven slots, as in the spec.** "Paint" holds a design's paint set (body colours and wear) or a paint tin over it (main paint only); "Light colour" sets eyes, strips, hover and laser together. The free colour mixer and the per-part colour pickers are gone.
- **Old saves keep what they had** as found pieces: each piece carries its old rule in `legacy`, read only by the migration. Colours that used to be free (Graphite, Slate, Orange) are pieces now, given to old saves and not to new games. A look mixed in the old colour picker stays wearable until it is changed.
- **Until sources are jobs (M3-07) a city's source counts as shut down at regrowth stage 4** (`source_shut_at_stage` in the finds table); `EventBus.source_shut_down(district)` releases the find at once when something emits it.
- **Until wrecks stand in the world (M3-15) a wreck's pieces come when its hex is cleared.** The hex is fixed by the seed, in the outer rings. `Finds.site_cell(id)` tells the world where to put the wreck and `Finds.register_site(id, anchor, prompt)` makes it a thing Lumi uses instead.
- **The Locker costs 400 cubes and is offered by the first find**, not by a base level. Old saves that owned any piece see it at once.
- **Lumi on the turntable is a stand-in model.** The real Lumi is hidden while the Locker is open and never moves, so position, cargo and physics are untouched.
- **Where a piece lies is the planet's to say.** The hint under an unfound piece comes from its find in the planet's table ("A paint tin lies under Ironside's scrap."); the piece list holds only general hints per slot.
- **Unfound pieces of other worlds are counted, not shown** ("3 more lie on other worlds"). Only pieces this planet hides appear as silhouettes with a hint.
- **Open (owner):** fifteen loose pieces (round and heart eyes, antenna, halo, Chalk, Gold and others) have no find on any planet yet and wait for later planets. Nova's set has five pieces where the spec asks for six to eight.

## Looks from found pieces and the Locker (M3-14 + M3-16, Nov 11, 2026)
`docs/reviews/M3-14_16_LOOKS.md`. 61 pieces in 11 slots, found only (buried tins and chips, wrecks, source shutdowns, secrets); every stat, level and cost unlock removed; pieces are global progress in a new save section (v5, old saves migrate); the Locker is a yard build offered by the first find, with a turntable, silhouettes and hints, three presets and set bonuses. First piece at bot minute 14.5. Only Sprout can be completed on Planet 1, in the last city. Merged.
- **Aurora's starting set gives no bonus** (lead): a bonus that switches off when the player dresses up reads as a penalty. To do in the looks follow-up.
- **The fifteen loose pieces with no find** (extra eye shapes, antenna, halo, heart plate, med kit, watering can, tiny drone, six colours) are kept for later planets' finds tables; old saves keep them. Listed in `docs/FUTURE.md`.
- **Crew and Glim cosmetics follow the same rule**: found, not bought or counted. Follow-up task M3-14b.
- Nova's set gets a sixth piece when its planet is designed.
- Merge fix: `tools/extract_strings.py` scanned agent worktrees under `.claude/`; it now skips them.

## Mastery and apprentice robots (M3-05, Nov 11, 2026)
`docs/reviews/M3-05_MASTERY.md`. Mastery 0 to 10 per pollution kind from Lumi's own work only; robots leave a kind alone until mastery 1, then follow the speed curve, with +25% near Lumi; saved per planet, old saves credited from clean hexes. City 1 bot: first hex 60 to 69 s, first robot at 9.5 to 10 minutes, litter mastery 1 at 134 to 184 s. Merged.
- **The 30% hand-share rule is replaced** (lead). With 100 to 200 robots, which the owner asked for, Lumi cannot do 30% of the cleaning, and forcing it would shrink the crew. The rule becomes: Lumi's hands stay needed through work only she can do: each new kind's first mastery level, each city's source job (M3-07) and Surge (M3-09). Hand share of cleaning stays at or above 10% in cities 1 to 3 (simulator: 100%, 46%, 20%) and is only reported after that.
- **A hex holding an unlearnt kind is shut to robots whole**, litter included: the robots come in once Lumi has learnt the new kind. Kept: it makes each new city start with hand work.
- The simulator's purchase-wait limit is 136 s, matching the accepted first-seed sequence (M3-21).
- Robot plans do not wait on mastery yet; review in M3-12.

## Rigs (M3-08, Nov 11, 2026)
`docs/reviews/M3-08_RIGS.md`. Three slots on Lumi (arm, chest, drive), thirteen modules in the planet's `rigs` table, fitted free at the workbench's Rig tab; a fitted module shows on Lumi's model.
- **Each city's kind is gated by a rig tool, and by nothing bought earlier.** Wrecks need the Plate Cutter (arm), slick the Skim Skirt (drive), smog the Mist Scrubber (chest), blight the Soil Doser (drive). Lift Strength 2, Hover Jets and the garden tools no longer open a kind on their own; the Cutter brings the lift and the Skirt the hover.
- **A tool's plan arrives when its city opens, not when Lumi lands there** (a change from the task's wording, "on reaching that city"). The only workbench is in the start yard: a tool handed over on landing would cost two flights before the first new hex. The player is told at the bench, fits it, then flies. To revert, the unlock listens for `district_entered` instead of `district_unlocked` (one line in `systems/rigs.gd`).
- **Tools are free; their price is the slot.** Every other module is built once for cubes and Parts (800 to 3,400 cubes, 8 to 80 Parts, all under the 4,200 cap) and trades one stat for another.
- **No rig module in city 1.** The Rig tab appears when Ironside opens, so the first city's pacing is as it was.
- **Skim Skirt and Soil Doser share the drive slot.** Slick is whole lake hexes and blight is land, so no single hex needs both; Old Capital (9 slick hexes) is a choice per outing.
- **Once Lumi has learnt a kind she may take its tool off** and leave the kind to the robots at their first-level rate; keeping the tool on keeps her mastery, and so the crew's rate, climbing. This is the standing trade-off of cities 3 to 6.
- **Saved per planet** (`orbit.rigs`): modules, prices and tools are the planet's own. A save from before rigs gets the tools of its open cities fitted wherever the slot is free.
- **Rigs are not looks.** They mount on the right wrist and the body, take no Locker slot and are not in `data/cosmetics.json`. The Locker's turntable shows looks only.
- **Parts on the model are procedural stand-ins** (`player/rig_parts.gd`, one shape per module); modelled parts are M5-10.
- **The rig study is separate from the accepted proposal.** `tools/pace_sim/rig_study.gd` scores the game's own table; the proposal's loadout study (8% spread, `--model=redesign --rigs=1`) still runs on the proposal's table and was not changed. Five modules are never the study's best fit (Long Reach, Guide Arm, Press Frame, Sprint Coils, Relay Mast: 4 to 9% behind); their numbers go to M3-12.
- Originality: slots, module names and effects come from the cleanup theme (cutting wrecks, skimming, scrubbing, dosing soil); nothing was modelled on another game. Equipment slots with trade-offs are a common genre mechanic.

## Rigs (M3-08) and source jobs (M3-07), Nov 11, 2026
`docs/reviews/M3-08_RIGS.md`, `docs/reviews/M3-07_SOURCES.md`. Merged.
- **Rigs:** three slots (arm, chest, drive), thirteen modules from data, saved per planet. Each city's kind opens only with its tool fitted: Plate Cutter (Ironside wrecks), Skim Skirt (Kettle Bay slick), Mist Scrubber (Highreach smog), Soil Doser (Lowmeadow blight). Tools are free and arrive when their city opens; other modules cost 800 to 3,400 cubes. The study shows no module best everywhere, but the Plate Cutter wins the arm slot in four of five cities and five modules are never best: rebalanced in M3-12. Module shapes on Lumi are stand-ins that clip near the face: art in M5.
- **Source jobs:** each city has a Lumi-only job of 3 to 5 steps from data (Old Capital: six rocket parts, 2,600 Parts) that gates the last stage, shuts the landmark down, pays its reward and fires its finds. The bot completes all six; the rocket run reaches the end screen.
- **A running source sends waste back** (lead, as the design says): while a city's source runs, its hexes cannot pass stage 3 and cleaned hexes near the landmark slowly re-soil. This makes the job matter. Task M3-07b.
- **Rocket parts take the Assembler's line** (about 45 s each, as M3-20 assumed), so the crew's last stretch and the rocket compete for Parts and line time. M3-07b.
- **The job opens at stage 4**, not 3, so planting stays the main work at stage 3.
- No step waits on robots (a crewless player must never be stuck). Kept.
- The rocket must visibly grow on the pad as parts are fitted; source markers need proper props: M5 art.

## Surge (M3-09, Nov 11, 2026)
`docs/reviews/M3-09_SURGE.md`. Hand work, pressing and tending charge the Bloom Core; robots never do; a full core releases a 12 s Surge measured at 3.5x Lumi's output; from city 4 it also pushes a growth wave; charge and power scale by district; saved. Merged.
- **The Surge opens with the first robot** (lead; data `balance.surge.unlock`). Open from the start it sped the opening (first robot 7.5 to 8.7 minutes against about 9); opening with the robot keeps the fitted opening and gives a new tool exactly when the crew starts taking work from Lumi. Bot: first Surge about 2.5 minutes after the robot, then every 2 to 3.5 minutes.
- Fixed at merge: the Surge only listened for work if it was already open at setup, so a game that opened it later never charged (regression test in `tests/test_surge.gd`).
- **"Salvage Surge" event renamed "Salvage Glint"** so only one thing is called a Surge.
- Kept: release on R, LB+RB on a pad; chest packing during a Surge (the burst is not spent walking to the bin).
- **Run-to-run spread of the first robot is wide** (two runs today: 7.6 and 13.8 minutes; the target is by minute 12). M3-12 narrows it (likely buried-part luck and walk-offs).

## Source follow-up (M3-07b, Nov 11, 2026)
Merged. Crew at the launch point 155 (cap 200); city 1 first hex 55 s, first robot 9.2 minutes.
- **The stage-3 hold covers only the 12 hexes nearest each running source** (the agent's correction of the lead's brief: holding the whole city at stage 3 would stop it reaching stage 4, where its job opens). Those hexes re-soil one per 90 s, at most 3 dirty, and stop at shutdown; the readout says "SOURCE STILL RUNNING".
- **Rocket parts** take 45 s each on the Assembler's line (robot building pauses); without the Assembler the workbench builds one in 135 s.
- Follow-ups: a "keep Parts back" control on the Assembler panel so the line does not spend the rocket's Parts (M3-12/UI); a visible mark in the world for a source's reach (M5); the rocket and Kettle Bay's slick do not re-soil (kept).

## Goals in three tiers (M3-10, Nov 11, 2026)
`docs/reviews/M3-10_GOALS.md`. NOW (41 authored, 6 repeating), CITY (65 authored, 2 repeating) and PLANET (9) goals from data, one of each always active, beside the story card; 114 goals pointing at parked systems removed. Bot: longest stretch with no goal finished 2.0 minutes; no tier ever empty. Merged.
- The first PLANET goal ("Restore Old Town") does not finish in the first 25 minutes. Kept: the long tier is meant to be long, and the card and NOW goals carry the opening.
- Purchase waits of 155 and 198 s between minutes 14 and 20 go to M3-12; the simulator's goal-gap check must count repeating goals (M3-12).

## Wrecks and buried finds (M3-15, Nov 11, 2026)
`docs/reviews/M3-15_WRECKS.md`. Three Sprout wrecks (Ironside, Highreach, Lowmeadow) that Lumi uncovers by hand and salvages; one Bolt wreck in Kettle Bay as an unsalvageable tease; buried tins and lens chips that the detector pings; a found moment on Lumi with light, chimes, the piece named and a pointer to the Locker. All reachable. Merged.
- Below the bar, for M5 art: wrecks are hard to pick out from 30 m; the tease reads as a dark lump; the found light barely shows in sunlight.
