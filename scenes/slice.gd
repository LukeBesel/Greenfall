extends Node3D
## The game's world node: the slice on the walkable globe. SliceOrbit (scenes/slice_orbit.gd) builds
## everything into this node, which stays `world` for Patch, the HUD, the Depot and every system;
## its members are the façade those systems read, and its methods route to the globe.

const BOARD_POS := Vector3(-3.6, 0, 2.2)  # the yard frame's workbench (site-local metres; yard systems)
const FLOWER_POS := Vector3(2.9, 0, 1.4)  # the yard frame's first flower (site-local metres)

var field: HexField
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
var shards: ShardSystem
var garden: Garden
var hex_levels: HexLevels
var goals: Goals
var first_seed: FirstSeed
var water: WaterView
var doc_view: DocumentView
var interactables: Interactables
var camp: Camp  # [camp] the landing yard: broken bench, trash bin, yard builds (systems/camp/camp.gd)
var eggs: EasterEggs
var ledger: LedgerArc
var outposts: Outposts  # [outposts] ruined frontier depots (automation/outposts.gd)
var events: WorldEvents  # [events] world events, cleaning streak (systems/events.gd)
var lumi_level: LumiLevel  # [hud] Lumi Level / XP (systems/lumi_level.gd), drawn by the hotbar
var contracts: Contracts  # [events] contracts board + token shop (systems/contracts.gd)
var photo: PhotoMode  # [photo] photo mode (ui/photo_mode.gd)
var fauna: Fauna  # [wild] ambient animals (fauna/fauna.gd)
var orbit: SliceOrbit  # [orbB] the globe build (scenes/slice_orbit.gd)
var view: FieldView
var depot: Depot
var patch: Patch
var hud: HUD
var upgrades: UpgradesScreen
var music: MusicHooks
var intro: Intro
var objectives: Objectives  # [onboard] first-minutes story objectives (story/objectives.gd)
var core_charge: CoreCharge
var composter: Composter
var pause_menu: PauseMenu
var research: Research
var achievements: Achievements
var codex: CodexScreen
var bot: InputSource
var _cubes_root: Node3D
## Shack and yard lamp pieces that sit derelict while a non-starter base is at level 1.
var _ruin_bits: Dictionary = {}
## Rocket launch → flight → travel: no modal hotkeys, and closing a modal doesn't hand control back.
var launching: bool = false
## [leftovers] True while the globe builds across frames behind the loading screen (a BuildBudget
## is open: ui/loading_screen.gd). `built` fires once everything exists.
var building: bool = false
signal built


func _ready() -> void:
	orbit = SliceOrbit.new()
	orbit.name = "Orbit"
	add_child(orbit)
	# [orbE] Behind the loading screen the globe builds across frames, disabled and unrendered until
	# it is whole (orbB measured a ~15 s first frame).
	building = BuildBudget.active()
	var ovp: Viewport = get_viewport()
	var o_had_3d: bool = not ovp.disable_3d
	if building:
		process_mode = Node.PROCESS_MODE_DISABLED
		ovp.disable_3d = true
	var obb: BuildBudget = BuildBudget.current
	await orbit.build(self)
	if not building:
		return
	if obb and DevHooks.has("load-report"):
		print("[slice] globe build spread over %d frames, longest slice %.0f ms (%s)" % [obb.frames, obb.longest_us / 1000.0, obb.longest_at])
	building = false
	process_mode = Node.PROCESS_MODE_INHERIT
	ovp.disable_3d = not o_had_3d
	built.emit()
	if DevHooks.has("load-report"):  # [orbE] the first live frame after the build
		var tf: int = Time.get_ticks_msec()
		await get_tree().process_frame
		var tf2: int = Time.get_ticks_msec()
		await get_tree().process_frame
		print("[orbit-load] first live frames: %d ms, %d ms" % [tf2 - tf, Time.get_ticks_msec() - tf2])


# --- Sim hooks used by Patch ----------------------------------------------------

## Cell ids are the planet's ids.
func planet_cell_at(pos: Vector3) -> int:
	return orbit.cell_at(pos)


func collect_piece(pid: int) -> void:
	orbit.collect_piece(pid)


## [orbB] A bite was taken off a heavy globe piece (Patch._take_piece): the cell's numbers follow.
func piece_bitten(pid: int) -> void:
	orbit.piece_bitten(pid)


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
	Loader.reload()  # [intro2] loading screen


## Salvaged materials from scooped junk: hub materials come with the hub sites; paper still feeds the press.
func salvage_materials(type_id: String, vol: float) -> void:
	if composter:
		composter.on_salvage(type_id, vol)


func add_cube(cube: JunkCube) -> void:
	_cubes_root.add_child(cube)


# --- Interaction / UI -------------------------------------------------------------

func try_interact(p: Patch) -> void:
	orbit.try_interact(p)


func interact_prompt(p: Patch) -> String:
	return orbit.interact_prompt(p)


## [orbB] Where the workbench is: the start site's bench anchor.
func bench_pos() -> Vector3:
	return orbit.bench_position()


func near_bench() -> bool:
	return orbit.near_bench()


func open_upgrades() -> void:
	orbit.open_upgrades()


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
		GameState.add_currency("cubes", BigNum.from_float(DevHooks.get_f("give-data", 500.0) * Research.note_cubes()))  # [money] research costs cubes
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
	orbit.open_codex(tab)


func any_modal_open() -> bool:
	return orbit.any_modal_open()


func _on_modal_closed() -> void:
	orbit.on_modal_closed()


func _unhandled_input(event: InputEvent) -> void:
	orbit.unhandled_input(event)


# --- Persistence -----------------------------------------------------------------

## GameState.orbit (direction + height).
func persist_save() -> void:
	orbit.persist_save()


func _restore_world() -> void:
	orbit.restore_world()


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
