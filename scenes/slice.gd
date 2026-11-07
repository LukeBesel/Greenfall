extends Node3D
## M1 "The Slice": the Junkyard hex field around the first hub. Builds the world in code,
## wires sim ↔ view, owns hex-flip moments, saving of world objects, and UI routing.

const SPAWN := Vector3(0, 0.05, 3.0)
const BOARD_POS := Vector3(-3.6, 0, 2.2)
const FLOWER_POS := Vector3(2.9, 0, 1.4)
const HEX_MILESTONES: Array[int] = [1, 5, 10, 25, 50, 100, 150, 200, 264]

var field: HexField
var layout: CityLayout
var city: CityView
var litter: LitterView
var tutorial: Tutorial
var wren: Wren
var fleet: Fleet
var planet: PlanetData
var hub_index: int = 0
var anchor_cell: int = 0
var district_name: String = "Old Town"
var globe: GlobeView
var sky_director: SkyDirector
var hub: Hub
var rocket: Rocket
var _pad_holo: LaunchPad  # level 4: hologram of the launch pad to come
var shards: ShardSystem
var garden: Garden
var hex_levels: HexLevels
var goals: Goals
var first_seed: FirstSeed
var wildlife: Wildlife
var water: WaterView
var doc_view: DocumentView
var interactables: Interactables
var eggs: EasterEggs
var ledger: LedgerArc
var outposts: Outposts  # [outposts] ruined frontier depots (automation/outposts.gd)
var events: WorldEvents  # [events] world events, cleaning streak (systems/events.gd)
var lumi_level: LumiLevel  # [hud] Lumi Level / XP (systems/lumi_level.gd), drawn by the hotbar
var contracts: Contracts  # [events] contracts board + token shop (systems/contracts.gd)
var photo: PhotoMode  # [photo] photo mode (ui/photo_mode.gd)
var frontier: FrontierDistrict  # [biomes] late-game frontier districts (planet/frontier_district.gd)
var slice_cells := PackedInt32Array()  # slice hex id -> planet cell
var view: FieldView
var depot: Depot
var patch: Patch
var cam: CameraRig
var hud: HUD
var upgrades: UpgradesScreen
var command: CommandView
var music: MusicHooks
var intro: Intro
var core_charge: CoreCharge
var composter: Composter
var pause_menu: PauseMenu
var research: Research
var achievements: Achievements
var codex: CodexScreen
var bot: InputSource
var _cubes_root: Node3D
var _flower: Node3D
var _sun: DirectionalLight3D
var _env: Environment
var dressing: StreetDressing
## Shack and yard lamp pieces that sit derelict while a non-starter base is at level 1.
var _ruin_bits: Dictionary = {}
var _t: float = 0.0
## Rocket launch → flight → travel: no modal hotkeys, and closing a modal doesn't hand control back.
var launching: bool = false


func _ready() -> void:
	var t0: int = Time.get_ticks_msec()
	add_to_group("persist")
	# Backstop: never start a district frozen (e.g. paused during a rocket flight).
	get_tree().paused = false
	_build_environment()
	var cfg: Dictionary = Economy.planet.get("slice_field", {})
	var base_seed: int = int(DevHooks.get_f("seed", float(cfg.get("seed", 4471))))
	var loaded: bool = false
	var from_memory: bool = GameState.reload_in_memory
	if GameState.reload_in_memory:
		GameState.reload_in_memory = false
		loaded = true
	elif not DevHooks.has("fresh"):
		loaded = SaveManager.load_game()
	if DevHooks.has("hub") and not loaded:
		GameState.switch_hub(int(DevHooks.get_f("hub", 0.0)))
	if DevHooks.has("hub-level"):  # dev: start this base at a given hub level (1-5)
		GameState.world["hub_level"] = clampi(int(DevHooks.get_f("hub-level", 1.0)), 1, 5)
	planet = PlanetData.new(base_seed, 6, 10.0)
	planet.generate()
	if not GameState.planet_state.is_empty():
		planet.apply_dict(GameState.planet_state)
	if DevHooks.has("frontier") and not loaded:  # [biomes] dev: --frontier=dust_flats|frozen_port|sunken_city|cradle_returns
		GameState.switch_hub(int(planet.frontier_hubs.get(DevHooks.get_s("frontier", "dust_flats"), 0)))
		if DevHooks.has("hub-level"):
			GameState.world["hub_level"] = clampi(int(DevHooks.get_f("hub-level", 1.0)), 1, 5)
	hub_index = clampi(GameState.current_hub, 0, planet.hubs.size() - 1)
	anchor_cell = planet.hubs[hub_index]
	# Each hub's district has its own deterministic seed; city hubs get streets, others are wild.
	var seed_v: int = base_seed + hub_index * 1009
	var is_city: bool = planet.city[anchor_cell] >= 0
	district_name = str(planet.cities[planet.city[anchor_cell]]["name"]) if is_city else PlanetData.BIOMES[planet.biome[anchor_cell]].capitalize().replace("_", " ")
	var fk: Dictionary = Frontiers.field_params(planet, hub_index)  # [biomes] frontier district?
	var f_radius: int = int(fk.get("radius", cfg.get("radius", 9)))
	if not fk.is_empty():
		district_name = str(fk.get("name", district_name))
	layout = CityLayout.new(seed_v, 150.0, (not is_city) if fk.is_empty() else str(fk.get("layout", "wild")) != "city")
	field = HexField.new(f_radius, float(cfg.get("hex_size", 3.2)), seed_v, layout)
	field.clean_threshold = float(cfg.get("clean_threshold", 0.99))
	if not is_city:  # [biomes] wilderness districts get their biome's junk, wrecks and ground tint
		field.biome = PlanetData.BIOMES[planet.biome[anchor_cell]]
		field.biome_set = Economy.biome_set(field.biome)
	if not fk.is_empty():  # [biomes]
		field.biome = str(fk["biome"])
		field.biome_set = Economy.biome_set(field.biome)
	var ppx: Array = (cfg.get("pieces_per_hex", [6, 12]) as Array).duplicate()
	if not fk.is_empty():  # [biomes] more junk per hex
		ppx = [int(float(ppx[0]) * float(fk.get("pieces_mult", 1.0))), int(float(ppx[1]) * float(fk.get("pieces_mult", 1.0)))]
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	# Lake hexes: district hexes that sit on planet water cells.
	for i: int in Hex.spiral(f_radius).size():
		var a: Vector2i = Hex.spiral(f_radius)[i]
		var w: Vector2 = Hex.axial_to_world(a, float(cfg.get("hex_size", 3.2)))
		var cell: int = planet.grid.nearest_from(planet.local_to_dir(anchor_cell, w.x, w.y), anchor_cell)
		if planet.state[cell] == PlanetData.State.WATER:
			field.water_ids[i] = true
	if not fk.is_empty():  # [biomes] the frontier's own harbour / flood replaces planet lakes
		field.water_ids = Frontiers.water_ids_for(fk, f_radius, float(cfg.get("hex_size", 3.2)))
		field.float_mult = float(fk.get("float_mult", 1.0))
	# Older saves were generated with straight hex borders; keep their piece layout identical.
	if loaded and GameState.world.has("field"):
		field.natural_borders = bool((GameState.world["field"] as Dictionary).get("natural_borders", false))
	field.generate(types, Vector2i(int(ppx[0]), int(ppx[1])))
	if not fk.is_empty():
		Frontiers.toughen(field, float(fk.get("vol_mult", 1.0)))
	field.place_landmarks(Economy.landmarks_for(field.biome))
	field.bury_parts(Economy.parts)
	if loaded and GameState.world.has("field"):
		if not field.apply_dict(GameState.world["field"]):
			push_warning("Saved field didn't match this field; starting the field fresh.")
	loaded = loaded and GameState.world.has("field")
	_map_slice_to_planet()
	if not fk.is_empty():  # [biomes] ice locks, drained streets, base start level: before the views
		frontier = FrontierDistrict.new()
		frontier.name = "Frontier"
		add_child(frontier)
		frontier.prepare(self)
	view = FieldView.new()
	view.name = "FieldView"
	add_child(view)
	if not fk.is_empty():  # [biomes] frontier ground textures and shader extras
		view.layer_swap = fk.get("ground_layers", {})
		var gfx: Array = fk.get("fx", [0, 0, 0, 0])
		view.ground_fx = Vector4(float(gfx[0]), float(gfx[1]), float(gfx[2]), float(gfx[3]))
		view.skip_horizon = true  # [biomes2] FrontierView builds the terrain and skyline
	view.setup(field)
	water = WaterView.new()
	water.name = "Water"
	water.world = self
	add_child(water)
	litter = LitterView.new()
	litter.name = "Litter"
	add_child(litter)
	litter.density_mult = float(fk.get("litter_mult", 1.0))  # [biomes]
	litter.setup(field)
	city = CityView.new()
	city.name = "City"
	add_child(city)
	city.build(layout, view.ground_material)
	# Awnings, neon, murals, string lights, yard slab and props (planet/street_dressing.gd).
	if not DevHooks.has("no-dressing"):
		dressing = StreetDressing.new()
		dressing.name = "StreetDressing"
		add_child(dressing)
		dressing.skip_facades = not fk.is_empty()  # [biomes] (the Sunken City's facades sit below the waterline)
		dressing.build(layout, field, hub_index, district_name, ("" if is_city else field.biome) if fk.is_empty() else str(fk.get("dressing_biome", "")), int(GameState.world.get("hub_level", 1)))
	_cubes_root = Node3D.new()
	_cubes_root.name = "Cubes"
	add_child(_cubes_root)
	depot = Depot.new()
	depot.name = "Depot"
	depot.position = Vector3(0, 0, -1.8)
	add_child(depot)
	_build_board()
	if DevHooks.has("future"):  # --future=N preview: the hub at level N too (FutureLayer.apply_preview)
		GameState.world["hub_level"] = clampi(int(DevHooks.get_f("future", 5.0)), 1, 5)
	hub = Hub.new()
	hub.name = "Hub"
	hub.cost_mult = float(fk.get("cost_mult", 1.0))  # [biomes] frontier bases cost more cubes
	add_child(hub)
	# Every base but Old Town's starter lean-to begins derelict and is fixed up level by level.
	_apply_base_level(hub.level, false)
	hub.level_changed.connect(func(l: int) -> void:
		_apply_base_level(l, true)
		if dressing:
			dressing.set_level(l, true))
	hub.leveled.connect(func(_l: int) -> void: _refresh_rocket_site())
	_refresh_rocket_site()
	# [stations] Conveyor feeder, auto-baler, recycler (automation/stations.gd).
	var stations := Stations.new()
	stations.name = "Stations"
	stations.world = self
	add_child(stations)
	_build_flower()
	patch = Patch.new()
	patch.name = "Patch"
	patch.world = self
	if DevHooks.has("autoplay"):
		bot = AutoplayBot.new(self)
		patch.input = bot
	elif DevHooks.has("demo-scoop"):
		patch.input = DemoScoopInput.new(self)
	add_child(patch)
	patch.global_position = SPAWN
	patch.rotation.y = 0.0
	depot.patch = patch
	patch.detector.field = field
	cam = CameraRig.new()
	cam.name = "CameraRig"
	add_child(cam)
	cam.target = patch
	cam.yaw = 0.0
	patch.cam_yaw_provider = func() -> float: return cam.yaw
	lumi_level = LumiLevel.new()  # [hud]
	lumi_level.name = "LumiLevel"
	lumi_level.world = self
	add_child(lumi_level)
	hud = HUD.new()
	hud.patch = patch
	hud.world = self
	add_child(hud)
	var lens := LensOverlay.new()
	lens.cam = cam
	lens.patch = patch
	add_child(lens)
	globe = GlobeView.new()
	globe.planet = planet
	globe.current_hub = hub_index
	globe.rocket_ready = func() -> bool: return Demo.rockets_allowed() and rocket_status() == ""  # [steam] Demo
	globe.rocket_lock_text = rocket_status
	globe.launch_to = func(i: int) -> void: _launch(i)
	globe.patch_cell_provider = func() -> int: return planet_cell_at(patch.global_position)
	globe.holder = patch
	globe.world_root = self
	add_child(globe)
	globe.closed.connect(_on_modal_closed)
	fleet = Fleet.new()
	fleet.name = "Fleet"
	fleet.world = self
	add_child(fleet)
	var builder := RobotBuilder.new()  # [drones] robot builder: salvage finds, starter kit, dev hooks
	builder.name = "RobotBuilder"
	builder.world = self
	add_child(builder)
	upgrades = UpgradesScreen.new()
	upgrades.fleet = fleet
	upgrades.hub = hub
	upgrades.build_at = func() -> Vector3: return BOARD_POS + Vector3(2.5, 0.2, 0.0)
	add_child(upgrades)
	upgrades.closed.connect(_on_modal_closed)
	music = MusicHooks.new()
	music.world = self
	add_child(music)
	command = CommandView.new()
	command.world = self
	add_child(command)
	command.closed.connect(_on_modal_closed)
	EventBus.robot_built.connect(func(_n: String) -> void:
		if not GameState.flags.get("hint_command", false):
			GameState.flags["hint_command"] = true
			EventBus.toast.emit(tr("Robot uplink online. Press B for Command: paint zones and send crews where you want them."), "info"))
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.closed.connect(_on_modal_closed)
	photo = PhotoMode.new()  # [photo]
	photo.world = self
	add_child(photo)
	pause_menu.photo_requested.connect(func() -> void: photo.try_open(true))
	if loaded:
		_restore_world(from_memory)
	cam.snap()
	if DevHooks.has("spawn-pos"):
		var sp: PackedStringArray = DevHooks.get_s("spawn-pos", "0,3").split(",")
		patch.global_position = Vector3(float(sp[0]), 0.2, float(sp[1]))
		patch.rotation.y = DevHooks.get_f("spawn-yaw", 0.0)
		cam.yaw = patch.rotation.y
	if DevHooks.has("spawn-hex"):
		var hid: int = int(DevHooks.get_f("spawn-hex", 30.0))
		patch.global_position = field.hex_center(hid) + Vector3(0, 0.05, field.hex_size * 0.9)
		var pid0: int = field.hex_pieces[hid][0]
		print("[slice] piece0 xf=", view.piece_transform(pid0), " model=", field.piece_model[pid0], " mm_count=", view._mms.size(), " inst=", view._mms[view._piece_mm[pid0]].instance_count, " mmaabb=", view._mms[view._piece_mm[pid0]].get_aabb(), " itx=", view._mms[view._piece_mm[pid0]].get_instance_transform(view._piece_slot[pid0]))
		print("[slice] pieces=%d junk_hexes=%d hex%d pieces=%d piles=%s" % [field.piece_count(), field.junk_hex_count, hid, field.hex_pieces[hid].size(), str(field.hex_piles[hid])])
	if DevHooks.has("demo-scoop"):
		DemoScoopInput.place(self, patch, patch.global_position)
		cam.yaw = patch.rotation.y + DevHooks.get_f("demo-yaw", 0.7)
		cam.distance = DevHooks.get_f("demo-dist", 2.8)
		cam.pitch = -0.3
		cam.snap()
	if DevHooks.has("lens"):
		cam.lens_view = true
	if DevHooks.has("cam"):
		cam.apply_preset(DevHooks.get_s("cam", "wide"))
	if DevHooks.has("cam-pitch"):  # e.g. --cam-pitch=0.05 to look up at the skyline for shots
		cam.pitch = DevHooks.get_f("cam-pitch", -0.3)
		cam.snap()
	if DevHooks.has("give"):
		GameState.add_currency("cubes", BigNum.from_float(DevHooks.get_f("give", 100.0)))
	if DevHooks.has("unlock-seeds"):
		GameState.flags["seeds_unlocked"] = true
		GameState.add_currency("seeds", BigNum.from_float(200))
	if DevHooks.has("upgrade-levels"):
		# --upgrade-levels=multi_lock:3+laser_reach:4  (screenshots/testing)
		for spec: String in DevHooks.get_s("upgrade-levels", "").split("+"):
			if ":" in spec:
				GameState.upgrades[spec.get_slice(":", 0)] = int(spec.get_slice(":", 1))
	if DevHooks.has("give-parts"):
		for k: int in int(DevHooks.get_f("give-parts", 8.0)):
			@warning_ignore("integer_division")  # [health]
			GameState.parts.append({"type": k % 8, "rarity": mini(k / 8, 4)})
	if DevHooks.has("clean-hexes"):
		# --clean-hexes=N  pre-clean the N land hexes nearest the base (to test planters/waterers).
		var land: Array = range(field.hex_count()).filter(func(h: int) -> bool: return field.hex_hub[h] == 0 and not field.is_water(h) and not field.is_clean(h))
		land.sort_custom(func(a: int, b: int) -> bool: return field.hex_center(a).length() < field.hex_center(b).length())
		for h: int in land.slice(0, int(DevHooks.get_f("clean-hexes", 2.0))):
			for pid: int in field.hex_pieces[h]:
				if field.piece_alive[pid] == 1:
					collect_piece(pid)
	if DevHooks.has("robots"):
		# --robots=scoopie:2,haulbug:1@3  (count, optional tier after @)
		var n_spawned: int = 0
		for spec: String in DevHooks.get_s("robots", "").split(","):
			var tier_i: int = int(spec.get_slice("@", 1)) if "@" in spec else 0
			var kv: String = spec.get_slice("@", 0)
			for k: int in int(kv.get_slice(":", 1)):
				GameState.flags["tier_" + kv.get_slice(":", 0)] = tier_i
				var rb: Robot = fleet.spawn(kv.get_slice(":", 0), tier_i, Vector3(-2.4 + n_spawned * 1.6, 0.2, 0.6), 0.0, "Test-%d" % n_spawned)
				rb.tier = tier_i
				rb.rebuild_visual()
				rb.rotation.y = PI
				if DevHooks.has("freeze-robots"):
					rb.set_physics_process(false)
				n_spawned += 1
	if DevHooks.has("order"):
		# --order=clean:stay:far  (role:mode:hex ids separated by '+', or 'far' = farthest junk hex)
		var spec_o: PackedStringArray = DevHooks.get_s("order", "").split(":")
		var hexes: Array = []
		@warning_ignore("incompatible_ternary")  # [health]
		for t: String in spec_o[2].split("+") if spec_o.size() > 2 else []:
			if t == "far":
				var far_h: int = -1
				for id: int in field.hex_count():
					if field.hex_hub[id] == 0 and not field.is_clean(id) and (far_h < 0 or field.hex_center(id).length() > field.hex_center(far_h).length()):
						far_h = id
				hexes.append(far_h)
			else:
				hexes.append(int(t))
		for h: int in hexes:
			fleet.toggle_zone_hex(spec_o[0], false, h, true)
		fleet.set_mode(spec_o[0], false, spec_o[1] if spec_o.size() > 1 else "priority")
		get_tree().create_timer(DevHooks.get_f("quit-after", 30.0) * 0.5, false).timeout.connect(func() -> void:
			for r: Robot in fleet.robots():
				print("[order] %s hex=%d at_hex=%d zone=%s status=%s" % [r.robot_name, r.work_hex, field.hex_at(r.global_position), str(fleet.zone_hexes(r)), r.status_text()]))
	if DevHooks.get_s("open", "") == "upgrades":
		open_upgrades.call_deferred()
	if DevHooks.get_s("open", "") == "command":
		_open_command.call_deferred()
	if DevHooks.get_s("open", "") == "globe":
		(func() -> void:
			globe.open_view()
			globe.focus_on(planet_cell_at(patch.global_position))).call_deferred()
	EventBus.hitstop_requested.connect(_hitstop)
	for sig: Signal in [EventBus.hex_cleaned, EventBus.robot_built, EventBus.upgrade_bought]:
		sig.connect(func(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void: CosmeticsPanel.check_unlocks())
	print("[slice] built in %d ms  district=%s hub=%d" % [Time.get_ticks_msec() - t0, district_name, hub_index])
	if DevHooks.has("auto-launch") and not GameState.flags.get("auto_launched", false):
		GameState.flags["auto_launched"] = true
		get_tree().create_timer(1.0).timeout.connect(func() -> void: _launch(int(DevHooks.get_f("auto-launch", 1.0))))
	if DevHooks.has("rocket-arrive"):  # screenshots: play the arrival cinematic here
		GameState.flags["arrived_from_rocket"] = true
	if GameState.flags.get("arrived_from_rocket", false):
		GameState.flags.erase("arrived_from_rocket")
		_arrive_by_rocket.call_deferred()
		if GameState.flags.has("patch_cargo"):
			patch.restore_cargo(GameState.flags["patch_cargo"])
			GameState.flags.erase("patch_cargo")
	wren = Wren.new()
	wren.world = self
	add_child(wren)
	var subs := Subtitles.new()
	add_child(subs)
	wren.line_started.connect(subs.show_line)
	garden = Garden.new()
	garden.name = "Garden"
	garden.world = self
	add_child(garden)
	if frontier:  # [biomes] drained Sunken City streets keep their slot order
		garden.late_hexes = frontier.drain_order.duplicate()
	garden.setup()
	hex_levels = HexLevels.new()
	hex_levels.name = "HexLevels"
	hex_levels.world = self
	add_child(hex_levels)
	hex_levels.setup()
	# Future layer: the district builds up into a glowing city as hexes level (planet/future_layer.gd).
	if DevHooks.has("future"):
		if frontier:  # [biomes] thaw the ice / run the pumps first so the preview covers every hex
			frontier.dev_pre_preview()
		FutureLayer.apply_preview(self, int(DevHooks.get_f("future", 5.0)))
	var future := FutureLayer.new()
	future.name = "FutureLayer"
	add_child(future)
	future.setup(self)
	goals = Goals.new()
	goals.name = "Goals"
	goals.world = self
	add_child(goals)
	wildlife = Wildlife.new()
	wildlife.world = self
	add_child(wildlife)
	first_seed = FirstSeed.new()
	first_seed.world = self
	add_child(first_seed)
	shards = ShardSystem.new()
	shards.world = self
	add_child(shards)
	shards.setup()
	doc_view = DocumentView.new()
	add_child(doc_view)
	doc_view.closed.connect(_on_modal_closed)
	first_seed.setup()
	wildlife.setup()
	water.setup()
	tutorial = Tutorial.new()
	tutorial.world = self
	add_child(tutorial)
	var feel := FeelFx.new()  # [first] core-loop juice (bale press, first robot, hex reveal)
	feel.world = self
	add_child(feel)
	var finds := SeedFinds.new()  # [first] rare seeds in scooped junk (early trickle)
	finds.world = self
	add_child(finds)
	_setup_research_codex()
	var cargo := CargoPods.new()
	cargo.world = self
	add_child(cargo)
	composter = Composter.new()
	composter.world = self
	add_child(composter)
	composter.global_position = Composter.POS + Vector3(0, clampf(layout.height_at(Composter.POS.x, Composter.POS.z), 0.0, 0.3) if layout else 0.0, 0)
	# Story: generic E-interactables, easter eggs, and the Ledger arc (story/*.gd).
	interactables = Interactables.new()
	interactables.name = "Interactables"
	add_child(interactables)
	outposts = Outposts.new()
	outposts.name = "Outposts"
	outposts.world = self
	add_child(outposts)
	outposts.setup()
	eggs = EasterEggs.new()
	eggs.name = "EasterEggs"
	eggs.world = self
	add_child(eggs)
	eggs.setup()
	ledger = LedgerArc.new()
	ledger.name = "Ledger"
	ledger.world = self
	add_child(ledger)
	ledger.setup()
	# [events] World events director (+ streak and its HUD) and the contracts board.
	events = WorldEvents.new()
	events.name = "WorldEvents"
	events.world = self
	add_child(events)
	contracts = Contracts.new()
	contracts.name = "Contracts"
	contracts.world = self
	add_child(contracts)
	var bloom := Bloom.new()  # [bloom] post-game milestones + Seed Ark (systems/bloom.gd)
	bloom.name = "Bloom"
	bloom.world = self
	add_child(bloom)
	# Cradle Returns complete -> the ark comes home (the finale plays once per save).
	# [beat] (Bloom connects EventBus.cradle_district_complete itself: a lambda here outlived the scene)
	if frontier:  # [biomes] frontier mechanics and visuals, once the scene is built
		frontier.setup()
	core_charge = CoreCharge.new()  # Lumi's Bloom Core charge + its story beats (story/core_charge.gd)
	core_charge.name = "CoreCharge"
	core_charge.world = self
	add_child(core_charge)
	intro = Intro.new()
	intro.world = self
	add_child(intro)
	var wake := func() -> void:
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			Story.once("wake", tr("LM-1 online. Bloom Core 4%: green light low. Cradle relay: faint. Grow something."), "story"))
	if intro.should_play():
		intro.finished.connect(wake)
		hud.visible = false  # [first] no one-frame HUD/world flash before the deferred intro starts
		intro.cover_now()
		intro.play.call_deferred()
	else:
		if GameState.flags.get("intro_done", false) or not loaded:
			GameState.flags["intro_done"] = true
			intro.place_pod.call_deferred()
		if not loaded:
			wake.call()
	if not bot and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	# Act 1: heavy, hazy, slightly violet-brown sky. Later acts lower turbidity and mie.
	sm.rayleigh_coefficient = 2.4
	sm.rayleigh_color = Color(0.3, 0.45, 0.85)
	sm.mie_coefficient = 0.006
	sm.mie_eccentricity = 0.82
	sm.mie_color = Color(0.95, 0.85, 0.75)
	sm.turbidity = 6.0
	sm.sun_disk_scale = 1.2
	sm.ground_color = Color(0.45, 0.43, 0.4)
	sm.energy_multiplier = 1.0
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_energy = 1.25
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.3
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.07
	env.glow_hdr_threshold = 0.95
	env.ssao_enabled = true
	env.ssao_radius = 1.0
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.2
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.85, 0.86, 0.9)
	env.volumetric_fog_emission = Color(0.04, 0.045, 0.06)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_sky_affect = 0.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.72, 0.78, 0.88)
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-62, -30, 0)
	_sun.light_color = Color(1.0, 0.93, 0.82)
	_sun.light_energy = 2.6
	_sun.light_angular_distance = 0.6
	_sun.light_volumetric_fog_energy = 1.4
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.0
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	Settings.apply_render_quality(env, get_viewport())
	Settings.apply_sun_quality(_sun)
	sky_director = SkyDirector.new()
	sky_director.world = self
	add_child(sky_director)
	sky_director.setup(env, _sun)
	if DevHooks.has("time"):
		sky_director.time_of_day = DevHooks.get_f("time", 0.5)
		sky_director.frozen = true


func _build_board() -> void:
	# The first "base": an open lean-to of salvaged pipe and corrugated iron over a workbench.
	var shack := Node3D.new()
	shack.name = "Shack"
	shack.position = BOARD_POS + Vector3(-1.3, 0, 0)
	shack.rotation_degrees = Vector3(0, 90, 0)  # opens toward +X (the yard)
	add_child(shack)
	var pipe: StandardMaterial3D = Mats.metal("dark_steel")
	var iron: StandardMaterial3D = AssetLib.pbr_material("corrugated_iron", 0.6, Color(0.95, 0.92, 0.88), true)
	var parts: Array = []
	for p: Vector3 in [Vector3(-1.6, 0, -1.1), Vector3(1.6, 0, -1.1), Vector3(-1.6, 0, 1.0), Vector3(1.6, 0, 1.0)]:
		var hgt: float = 2.5 if p.z < 0 else 2.1
		parts.append(ProcMesh.part(ProcMesh.cyl(0.045, 0.05, hgt, 8), ProcMesh.xf(p + Vector3(0, hgt * 0.5, 0))))
	parts.append(ProcMesh.part(ProcMesh.cyl(0.035, 0.035, 3.3, 8), ProcMesh.xf(Vector3(0, 2.45, -1.1), Vector3(0, 0, 90))))
	parts.append(ProcMesh.part(ProcMesh.cyl(0.035, 0.035, 3.3, 8), ProcMesh.xf(Vector3(0, 2.05, 1.0), Vector3(0, 0, 90))))
	var frame := MeshInstance3D.new()
	frame.mesh = ProcMesh.merge(parts)
	frame.material_override = pipe
	shack.add_child(frame)
	var roof := MeshInstance3D.new()
	_ruin_bits["roof"] = roof
	roof.mesh = ProcMesh.box(Vector3(3.7, 0.03, 2.6))
	roof.material_override = iron
	roof.position = Vector3(0, 2.3, -0.05)
	roof.rotation_degrees = Vector3(-9, 0, 2)
	shack.add_child(roof)
	var back := MeshInstance3D.new()
	back.mesh = ProcMesh.box(Vector3(3.3, 2.3, 0.03))
	back.material_override = iron
	back.position = Vector3(0, 1.15, -1.15)
	shack.add_child(back)
	var side := MeshInstance3D.new()
	_ruin_bits["side"] = side
	side.mesh = ProcMesh.box(Vector3(0.03, 1.6, 1.4))
	side.material_override = iron
	side.position = Vector3(-1.62, 0.8, -0.45)
	shack.add_child(side)
	# Workbench: steel top on welded legs, a vice, tools, a lamp, a clipboard.
	var bench := Node3D.new()
	bench.position = Vector3(0, 0, -0.65)
	shack.add_child(bench)
	var bparts: Array = []
	bparts.append(ProcMesh.part(ProcMesh.box(Vector3(2.2, 0.06, 0.8)), ProcMesh.xf(Vector3(0, 0.92, 0))))
	for x: float in [-1.0, 1.0]:
		for z: float in [-0.33, 0.33]:
			bparts.append(ProcMesh.part(ProcMesh.box(Vector3(0.06, 0.9, 0.06)), ProcMesh.xf(Vector3(x, 0.45, z))))
	bparts.append(ProcMesh.part(ProcMesh.box(Vector3(2.0, 0.03, 0.7)), ProcMesh.xf(Vector3(0, 0.25, 0))))
	var bmesh := MeshInstance3D.new()
	bmesh.mesh = ProcMesh.merge(bparts)
	bmesh.material_override = Mats.worn_paint(Color(0.32, 0.38, 0.45), 0.5, 0.6, 12.0, 0.7)
	bench.add_child(bmesh)
	for spec: Array in [["metal_toolbox", Vector3(-0.6, 0.95, 0.0), 0.2], ["clipboard", Vector3(0.35, 0.955, 0.1), 0.0], ["circuit_board", Vector3(0.05, 0.955, 0.05), 0.5], ["oil_tin", Vector3(0.8, 0.95, -0.2), 0.0], ["metal_jerrycan", Vector3(0.7, 0.26, 0.0), 1.2]]:
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh_lite(spec[0], 3000)
		mi.position = spec[1]
		mi.rotation.y = spec[2]
		bench.add_child(mi)
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.light_energy = 2.0
	lamp.spot_range = 3.5
	lamp.spot_angle = 50.0
	lamp.position = Vector3(0, 2.2, -0.4)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	shack.add_child(lamp)
	_ruin_bits["lamp"] = lamp
	var bulb := MeshInstance3D.new()
	bulb.mesh = ProcMesh.sphere(0.05, 8, 4)
	bulb.material_override = Mats.lamp(Color(1.0, 0.85, 0.6), 3.0)
	bulb.position = Vector3(0, 2.15, -0.4)
	shack.add_child(bulb)
	_ruin_bits["bulb"] = bulb
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(3.4, 2.4, 1.2)
	cs.shape = bs
	cs.position = Vector3(0, 1.2, -0.6)
	sb.add_child(cs)
	shack.add_child(sb)
	# Hub dressing: a street lamp and a generator.
	var sl := MeshInstance3D.new()
	sl.mesh = AssetLib.model_mesh("street_lamp_01")
	sl.position = Vector3(4.2, 0, -3.0)
	add_child(sl)
	var light := SpotLight3D.new()
	light.light_color = Color(1.0, 0.82, 0.6)
	light.light_energy = 3.0
	light.spot_range = 12.0
	light.spot_angle = 55.0
	light.shadow_enabled = true
	light.position = Vector3(4.2, sl.mesh.get_aabb().end.y - 0.3, -3.0)
	light.rotation_degrees = Vector3(-90, 0, 0)
	add_child(light)
	_ruin_bits["street_lamp"] = sl
	_ruin_bits["street_light"] = light
	var gen := MeshInstance3D.new()
	gen.mesh = AssetLib.model_mesh("portable_generator")
	gen.position = Vector3(-4.6, 0, 0.8)
	gen.rotation_degrees = Vector3(0, 70, 0)
	add_child(gen)


## Level 1 at any base but Old Town's start: the lean-to roof has slumped off its frame, the side
## sheet is gone, the bench bulb is dead and the yard lamp lies toppled. From level 2 it is fixed
## (tweened back into place when it happens live).
func _apply_base_level(l: int, animate: bool) -> void:
	var ruined: bool = l <= 1 and hub_index != 0
	var roof: Node3D = _ruin_bits.get("roof")
	var sl: Node3D = _ruin_bits.get("street_lamp")
	if roof == null or sl == null:
		return
	var roof_xf := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-9), 0, deg_to_rad(2))), Vector3(0, 2.3, -0.05))
	var lamp_xf := Transform3D(Basis(), Vector3(4.2, 0, -3.0))
	if ruined:
		roof_xf = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-31), deg_to_rad(8), deg_to_rad(17))), Vector3(0.45, 1.3, 0.25))
		lamp_xf = Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(-35), deg_to_rad(84))), Vector3(4.35, 0.18, -3.0))
	(_ruin_bits["side"] as Node3D).visible = not ruined
	(_ruin_bits["lamp"] as Light3D).visible = not ruined
	(_ruin_bits["street_light"] as Light3D).visible = not ruined
	(_ruin_bits["bulb"] as Node3D).visible = not ruined
	if not animate:
		roof.transform = roof_xf
		sl.transform = lamp_xf
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(roof, "transform", roof_xf, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.3)
	tw.tween_property(sl, "transform", lamp_xf, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.6)
	Vfx.burst("dust", BOARD_POS + Vector3(0, 1.0, 0), Color(0.7, 0.65, 0.6, 0.6), 1.2)


func _build_flower() -> void:
	# The First Flower: a small wildflower growing beside a crushed can. Never scoopable.
	_flower = Node3D.new()
	_flower.name = "FirstFlower"
	_flower.position = FLOWER_POS
	add_child(_flower)
	var f := MeshInstance3D.new()
	f.mesh = AssetLib.model_mesh("flower_heliophila")
	f.scale = Vector3.ONE * 0.8
	_flower.add_child(f)
	var can := MeshInstance3D.new()
	can.mesh = AssetLib.model_mesh("can_rusted")
	can.position = Vector3(0.12, 0.04, 0.05)
	can.rotation_degrees = Vector3(90, 20, 0)
	_flower.add_child(can)


func _process(delta: float) -> void:
	_t += delta
	if _flower:
		_flower.rotation.z = sin(_t * 1.1) * 0.02


# --- Sim hooks used by Patch ----------------------------------------------------

## The slice is Old Town, the first city: its hexes sit on planet cells around the city center.
func _map_slice_to_planet() -> void:
	var anchor: int = anchor_cell
	slice_cells.resize(field.hex_count())
	for id: int in field.hex_count():
		var c: Vector3 = field.hex_center(id)
		slice_cells[id] = planet.grid.nearest_from(planet.local_to_dir(anchor, c.x, c.z), anchor)
		if field.is_clean(id) and field.hex_hub[id] == 0:
			planet.mark_clean(slice_cells[id])


func planet_cell_at(pos: Vector3) -> int:
	var anchor: int = anchor_cell
	return planet.grid.nearest_from(planet.local_to_dir(anchor, pos.x, pos.z), anchor)


func collect_piece(pid: int) -> void:
	var hid: int = field.piece_hex[pid]
	var became_clean: bool = field.remove_piece(pid)
	planet.set_junk(slice_cells[hid], 1.0 - field.removed_fraction(hid))
	if became_clean:
		planet.mark_clean(slice_cells[hid])
	view.hide_piece(pid)
	view.refresh_hex(hid, became_clean)
	litter.refresh_hex(hid)
	if became_clean:
		_on_hex_clean(hid)


func _on_hex_clean(hid: int) -> void:
	# A hex the Ledger re-dumped on pays only the flat part of its bonus the second time and doesn't
	# count again toward "Clean N hexes" (otherwise a dump is a profit).
	var paid: Dictionary = GameState.world.get("hexes_paid", {})
	var first: bool = not paid.has(str(hid))
	paid[str(hid)] = true
	GameState.world["hexes_paid"] = paid
	var bonus: BigNum = Economy.hex_bonus(field.hex_total[hid] if first else 0.0)
	GameState.add_currency("cubes", bonus)
	if first:
		GameState.inc_stat("hexes_cleaned")
	var center: Vector3 = field.hex_center(hid)
	Audio.play("chime", 1.0, -3.0)
	Vfx.burst("big_sparkle", center + Vector3(0, 0.3, 0), Color(1.0, 0.92, 0.55))
	Vfx.ring(center, field.hex_size * 1.1, Color(1.0, 0.9, 0.5, 0.9), 0.8)
	Vfx.float_text(center + Vector3(0, 1.4, 0), tr("HEX CLEAN!  +%s") % Settings.fmt(bonus), Color(1.0, 0.92, 0.45), 1.5, 2.0)
	EventBus.hex_cleaned.emit(hid, center, bonus)
	EventBus.field_progress_changed.emit(field.cleaned_count, field.junk_hex_count)
	patch.model.set_happy(1.0)
	var n: int = field.cleaned_count
	if n == 1:
		EventBus.hitstop_requested.emit(0.45, 0.25)
		Audio.play("fanfare", 1.0, -4.0)
	if n in HEX_MILESTONES and not GameState.flags.get("hexm_%d" % n, false):
		GameState.flags["hexm_%d" % n] = true
		EventBus.milestone_reached.emit("hexes_%d" % n)
		if n > 1:
			Audio.play("fanfare", 1.0, -5.0)
			Vfx.burst("confetti", patch.global_position + Vector3(0, 1.5, 0), Color.WHITE)
			EventBus.toast.emit(tr("Milestone: %d hexes clean!") % n, "story")
		if n >= field.junk_hex_count:
			EventBus.toast.emit(tr("The whole Junkyard is clean. Lumi beeps a very long, very happy beep."), "story")


func _launch(to_hub: int) -> void:
	if launching or Demo.block("rocket"):  # [steam] demo: first district only
		return
	if not Frontiers.can_launch(planet, to_hub):  # [biomes] frontier destinations unlock late
		EventBus.toast.emit(tr("%s is out of range: %s") % [Frontiers.kind_name(planet.frontier_kind(to_hub)), "  ".join(Frontiers.unlock_status(planet.frontier_kind(to_hub), planet.frontier_hubs)["lines"])], "info")
		return
	if rocket == null:
		_place_rocket(false)
	rocket.launch(to_hub)


## "" when the rocket can launch, else why not (no pad yet, or the energy cells are recharging).
func rocket_status() -> String:
	if not (hub.level >= 5 or DevHooks.has("rocket") or GameState.world.get("rocket_parked", false)):
		return tr("Locked. Upgrade your base to level 5 to build the launch pad.")
	var left: float = RocketTiers.recharge_left()
	if left > 0.0:
		return tr("Energy cells recharging: %s. Rocket upgrades refill them faster.") % RocketTiers.fmt_time(left)
	return ""


## Launch pad and rocket (level 5 or --rocket), a hologram of the pad at level 4, or a rocket
## parked on the ground where it landed in a district without a pad.
func _refresh_rocket_site() -> void:
	var has_pad: bool = hub.level >= 5 or DevHooks.has("rocket")
	if has_pad and (rocket == null or rocket.pad == null):
		if rocket and not rocket.is_flying():
			rocket.queue_free()
			rocket = null
		if rocket == null:
			_place_rocket(true)
			GameState.world.erase("rocket_parked")
	elif not has_pad and rocket == null and GameState.world.get("rocket_parked", false):
		_place_rocket(false)
	var want_holo: bool = hub.level == 4 and not has_pad
	if want_holo and _pad_holo == null:
		_pad_holo = LaunchPad.new()
		_pad_holo.construction = true
		_pad_holo.position = Rocket.PAD_POS
		add_child(_pad_holo)
	elif not want_holo and _pad_holo:
		_pad_holo.queue_free()
		_pad_holo = null


## Rebuilds the rocket after an upgrade (new tier look), unless it is mid-sequence.
func refresh_rocket() -> void:
	if rocket == null or rocket.is_flying():
		return
	var had_pad: bool = rocket.pad != null
	rocket.queue_free()
	rocket = null
	_place_rocket(had_pad)
	Vfx.burst("big_sparkle", Rocket.PAD_POS + Vector3(0, 5.0, 0), Color(0.5, 0.9, 1.0))


func _place_rocket(with_pad: bool) -> void:
	rocket = Rocket.new()
	rocket.name = "Rocket"
	rocket.world = self
	rocket.position = Rocket.PAD_POS
	add_child(rocket)
	rocket.setup(with_pad)


## Arrived by rocket: it lands on this district's pad (or the ground, and stays parked there).
func _arrive_by_rocket() -> void:
	if rocket == null:
		_place_rocket(false)
		GameState.world["rocket_parked"] = true
	rocket.landed.connect(func() -> void:
		EventBus.toast.emit(tr("Touchdown: %s. Hub %d of %d. %s") % [district_name, hub_index + 1, planet.hubs.size(),
			tr("The rocket is parked on the lot, ready when its cells refill.") if rocket.pad == null else tr("Landed on the base pad.")], "story"), CONNECT_ONE_SHOT)
	rocket.arrive()


## Leave this district: persist it, switch the active hub, save without re-gathering, reload.
func travel_to(to_hub: int) -> void:
	get_tree().call_group("persist", "persist_save")
	# Patch's cargo (compartment + carried stack) flies with him; only pos/yaw stay per district.
	var pd: Dictionary = GameState.world.get("patch", {})
	GameState.flags["patch_cargo"] = {"compartment": pd.get("compartment", {}), "carried": pd.get("carried", [])}
	pd.erase("compartment")
	pd.erase("carried")
	GameState.switch_hub(to_hub)
	GameState.flags["arrived_from_rocket"] = true
	GameState.reload_in_memory = true
	SaveManager.save_game(false)
	get_tree().paused = false
	get_tree().reload_current_scene()


## Salvaged building materials from scooped junk (data/hub.json "materials").
func salvage_materials(type_id: String, vol: float) -> void:
	if composter:
		composter.on_salvage(type_id, vol)
	var m: Dictionary = hub.data.get("materials", {}).get(type_id, {})
	if m.is_empty():
		return
	GameState.add_currency(str(m["id"]), BigNum.from_float(vol * float(m.get("per_unit", 0.1))))


func add_cube(cube: JunkCube) -> void:
	_cubes_root.add_child(cube)


func _hitstop(duration: float, scale_: float) -> void:
	if Settings.reduced_motion:
		return
	Engine.time_scale = scale_ * (float(DevHooks.get_f("time-scale", 1.0)))
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = DevHooks.get_f("time-scale", 1.0))


# --- Interaction / UI -------------------------------------------------------------

func try_interact(p: Patch) -> void:
	if interactables and interactables.try_use(p.global_position):
		return
	if first_seed.near_tin(p.global_position):
		first_seed.take_tin()
		return
	if shards.nearby(p.global_position) >= 0:
		var doc: Dictionary = shards.take(p.global_position)
		if not doc.is_empty():
			doc_view.show_doc(doc)
		return
	if near_bench():
		open_upgrades()
		return
	if composter and composter.near(p.global_position):
		composter.interact()


func interact_prompt(p: Patch) -> String:
	var ip: String = interactables.prompt(p.global_position) if interactables else ""
	if ip != "":
		return ip
	if first_seed and first_seed.near_tin(p.global_position):
		return "seed"
	if shards and shards.nearby(p.global_position) >= 0:
		return "shard"
	if near_bench():
		return "upgrades"
	if composter and composter.near(p.global_position):
		return composter.prompt()
	if p.global_position.distance_to(FLOWER_POS) < 1.8:
		return "flower"
	return ""


const BENCH_RANGE: float = 3.2


func near_bench() -> bool:
	return patch != null and patch.global_position.distance_to(BOARD_POS) < BENCH_RANGE


func open_upgrades() -> void:
	if pause_menu.is_open:
		return
	# Upgrades are installed at a base workbench, not in the field.
	if not near_bench() and not DevHooks.has("open"):
		EventBus.toast.emit(tr("Upgrades need a workbench. Head back to the hub."), "info")
		Audio.play("buzz", 1.2, -10.0)
		return
	upgrades.open_screen()
	if patch.input is PlayerInput:
		(patch.input as PlayerInput).enabled = false
	cam.input_enabled = false


func _setup_research_codex() -> void:
	research = Research.new()
	research.world = self
	add_child(research)
	achievements = Achievements.new()
	achievements.world = self
	add_child(achievements)
	codex = CodexScreen.new()
	add_child(codex)
	codex.closed.connect(_on_modal_closed)
	pause_menu.codex_requested.connect(_open_codex)
	if DevHooks.has("give-data"):
		GameState.add_currency(Research.CURRENCY, BigNum.from_float(DevHooks.get_f("give-data", 500.0)))
	if DevHooks.has("research"):
		# --research=scoop_beam+wide_beam (researched) ; --research-start=bigger_hopper+conveyor
		for id: String in DevHooks.get_s("research", "").split("+"):
			Research.grant(id)
	if DevHooks.has("research-start"):
		for id: String in DevHooks.get_s("research-start", "").split("+"):
			GameState.add_currency(Research.CURRENCY, Research.cost(id))
			Research.start(id, Research.now() - DevHooks.get_f("research-elapsed", 0.0))
	if DevHooks.has("codex-sample"):
		# Screenshot helper: a game a little way in (some finds, stats and achievements).
		var i: int = 0
		for e: Dictionary in Codex.entries():
			if i % 3 != 2:
				Codex.unlock(str(e["key"]))
			i += 1
		for t: String in Economy.junk_ids:
			GameState.add_junk_removed(t, 40.0 + 25.0 * Economy.junk_ids.find(t))
		var sample: Dictionary = {"hexes_cleaned": 37, "cubes_made": 212, "pure_cubes": 31, "perfect_cubes": 58, "plants_planted": 120,
			"plants_bloomed": 64, "robots_built": 4, "shards_found": 3, "distance_m": 4380.0, "time_played": 5420.0}
		for k: String in sample:
			GameState.stats[k] = float(sample[k])
		var ei: int = 0
		for egg: Dictionary in Codex.egg_defs():  # [curiosities] some found, some still hints
			if ei % 5 in [0, 2, 3]:
				GameState.flags["egg_" + str(egg["id"])] = true
			ei += 1
		Achievements.check_all()
	if DevHooks.get_s("open", "") == "codex":
		(func() -> void: _open_codex(DevHooks.get_s("codex-tab", ""))).call_deferred()


func _open_codex(tab: String = "") -> void:
	if codex.is_open:
		return
	codex.open_screen(tab)
	if patch.input is PlayerInput:
		(patch.input as PlayerInput).enabled = false
	cam.input_enabled = false


func _open_command() -> void:
	command.open_view()
	if patch.input is PlayerInput:
		(patch.input as PlayerInput).enabled = false
	cam.input_enabled = false


func any_modal_open() -> bool:
	return upgrades.is_open or pause_menu.is_open or globe.is_open or command.is_open \
		or (codex != null and codex.is_open) or (doc_view != null and doc_view.is_open) \
		or (photo != null and photo.is_open)  # [photo]


func _on_modal_closed() -> void:
	# During the rocket launch the rocket owns the camera and Patch stays hidden and still.
	if launching:
		return
	if patch.input is PlayerInput:
		(patch.input as PlayerInput).enabled = true
	cam.input_enabled = true
	if not bot and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if launching or upgrades.is_open or pause_menu.is_open or globe.is_open or command.is_open or intro.busy() or (codex and codex.is_open):
		return
	if event.is_action_pressed("open_codex") and codex:
		_open_codex()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_upgrades"):
		open_upgrades()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_command"):
		_open_command()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_globe"):
		globe.open_view()
		globe.focus_on(planet_cell_at(patch.global_position))
		wren.say("globe", 0.6)
		if patch.input is PlayerInput:
			(patch.input as PlayerInput).enabled = false
		cam.input_enabled = false
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or true:
			pause_menu.open_menu()
			if patch.input is PlayerInput:
				(patch.input as PlayerInput).enabled = false
			cam.input_enabled = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not bot:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Persistence -----------------------------------------------------------------

func persist_save() -> void:
	GameState.world["field"] = field.to_dict()
	GameState.planet_state = planet.to_dict()
	GameState.world["garden"] = garden.persist()
	GameState.world["patch"] = patch.to_dict()
	var cubes: Array = []
	for n: Node in _cubes_root.get_children():
		var c: JunkCube = n as JunkCube
		if c and not c.carried and not c.claimed:
			cubes.append(c.to_dict())
	# Bales on a Haul Bug's fork are saved as loose cubes beside it; it picks them up again.
	for r: Robot in fleet.robots():
		var i: int = 0
		for c: JunkCube in r.carried:
			if not is_instance_valid(c):
				continue
			var cd: Dictionary = c.to_dict()
			var p: Vector3 = r.global_position + r.global_basis.x.normalized() * 1.3 + Vector3(0, 0.4 + i * 0.75, 0)
			cd["pos"] = [p.x, p.y, p.z]
			cubes.append(cd)
			i += 1
	GameState.world["cubes"] = cubes


## from_memory: reloaded by rocket travel (not from disk), so no offline payout or welcome back.
func _restore_world(from_memory: bool = false) -> void:
	for cd: Dictionary in GameState.world.get("cubes", []):
		var c: JunkCube = JunkCube.from_dict(cd)
		add_cube(c)
		var p: Array = cd.get("pos", [0.0, 1.0, 0.0])
		c.global_position = Vector3(float(p[0]), float(p[1]) + 0.02, float(p[2]))
		var r: Array = cd.get("rot", [0.0, 0.0, 0.0])
		c.rotation = Vector3(float(r[0]), float(r[1]), float(r[2]))
	if GameState.world.has("patch"):
		patch.from_dict(GameState.world["patch"])
	fleet.restore()
	if from_memory:
		return
	var away: float = Time.get_unix_time_from_system() - GameState.saved_unix
	if GameState.saved_unix > 0.0 and away > 120.0:
		var sd: Dictionary = hub.scrubber_def() if hub else {}
		var junk_left: float = 0.0
		for h: int in field.hex_count():
			if not field.is_clean(h):
				junk_left += field.hex_left[h]
		# [beat] Junk already "baled offline" stays on the field (geometry isn't advanced), so it must not
		# pay again on the next reopen: count it against what is left.
		junk_left = maxf(0.0, junk_left - float(GameState.world.get("offline_units", 0.0)))
		var res: Dictionary = Offline.compute(GameState.world.get("robots", []), hub.scrubbers if hub else 0, float(sd.get("filter_per_s", 1.0)), away, junk_left)
		GameState.world["offline_units"] = float(GameState.world.get("offline_units", 0.0)) + float(res["units"])
		Offline.apply(res)
		if float(res["units"]) > 0.0 or float(res["air"]) > 0.0:
			get_tree().create_timer(2.0).timeout.connect(func() -> void: EventBus.toast.emit(Offline.summary_text(res), "story"))
	EventBus.toast.emit(tr("Welcome back. The junk waited for you."), "info")


## [outposts] Pins for the Command view: grey ruins, green working outposts with their level.
func command_markers() -> Array:
	var out: Array = []
	# [events] pin on the running world event
	if events != null:
		var ep: Variant = events.marker_pos()
		if ep is Vector3:
			out.append({"pos": ep, "label": tr(str(events.active.get("name", "EVENT"))).to_upper(), "color": events.active.get("color", UITheme.GOLD), "kind": "event"})
	if outposts == null:
		return out
	for o: Outpost in outposts.items:
		var working: bool = o.level >= 1
		out.append({
			"pos": o.global_position,
			"label": (tr("OUTPOST %d · Lv%d") % [o.index + 1, o.level]) if working else (tr("OUTPOST %d · RUIN") % (o.index + 1)),
			"color": Color(0.45, 1.0, 0.55) if working else Color(0.62, 0.6, 0.56),
			"kind": "outpost",
		})
	return out
