extends Node3D
## The game scene: one planet as a walkable globe. This node is `world` for Lumi (Patch), the HUD,
## the Depot and every system; SliceOrbit (scenes/slice_orbit.gd) builds everything into it and
## owns the hex-clean flow, interaction, modals and saving. The methods below forward to it.
## (The flat district this scene used to build is gone: docs/FLAT_REMOVAL.md.)

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
var doc_view: DocumentView
var interactables: Interactables
var scope_from_memory: bool = false  # [scope]
var camp: Camp  # [camp] the landing yard: broken bench, trash bin, yard builds (systems/camp/camp.gd)
var eggs: EasterEggs
var ledger: LedgerArc
var outposts: Outposts  # [outposts] ruined frontier depots (automation/outposts.gd)
var events: WorldEvents  # [events] world events, cleaning streak (systems/events.gd)
var lumi_level: LumiLevel  # [hud] Lumi Level / XP (systems/lumi_level.gd), drawn by the hotbar
var contracts: Contracts  # [events] contracts board + token shop (systems/contracts.gd)
var photo: PhotoMode  # [photo] photo mode (ui/photo_mode.gd)
var fauna: Fauna  # [wild] ambient animals (fauna/fauna.gd)
var planet_env: Dictionary = {}  # [planet-rime] dev: --planet-env=<id> dresses a district with a planet env (data/planets.json)
var slice_cells := PackedInt32Array()  # slice hex id -> planet cell
var orbit: SliceOrbit  # [orbB] --orbit: the slice on the walkable globe (scenes/slice_orbit.gd); null on the flat game
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
var _flower: Node3D
var _sun: DirectionalLight3D
var _env: Environment
var dressing: StreetDressing
var street_power: StreetPower  # [world3] the district's dead street lights (planet/street_power.gd)
## Shack and yard lamp pieces that sit derelict while a non-starter base is at level 1.
var _ruin_bits: Dictionary = {}
var _t: float = 0.0
## Rocket launch → flight → travel: no modal hotkeys, and closing a modal doesn't hand control back.
var launching: bool = false
## [leftovers] True while the district builds across frames behind the loading screen (a
## BuildBudget is open: ui/loading_screen.gd). `built` fires once everything exists.
var building: bool = false
var _t_build: int = 0
var _env_pending: Environment
signal built


func _ready() -> void:
	orbit = SliceOrbit.new()
	orbit.name = "Orbit"
	add_child(orbit)
	# [orbE] Behind the loading screen the globe builds across frames, disabled and unrendered
	# until it is whole (orbB measured a ~15 s first frame).
	building = BuildBudget.active()
	var ovp: Viewport = get_viewport()
	var o_had_3d: bool = not ovp.disable_3d
	if building:
		process_mode = Node.PROCESS_MODE_DISABLED
		ovp.disable_3d = true
	var obb: BuildBudget = BuildBudget.current
	await orbit.build(self)
	if building:
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


func _process(delta: float) -> void:
	_t += delta


# --- Sim hooks used by Patch ----------------------------------------------------

func planet_cell_at(pos: Vector3) -> int:
	return orbit.cell_at(pos)


func collect_piece(pid: int) -> void:
	orbit.collect_piece(pid)


## [orbB] A bite was taken off a heavy globe piece (Patch._take_piece): the cell's numbers follow.
func piece_bitten(pid: int) -> void:
	orbit.piece_bitten(pid)


## The workbench's Rockets list and dev tools ask for a launch: the globe flies with its own
## rocket (OrbitSites: E at the pad).
func _launch(_to_hub: int) -> void:
	if launching or Demo.block("rocket"):  # [steam] demo: first district only
		return
	EventBus.toast.emit(tr("Walk to the rocket on the launch pad and press E to choose where to fly."), "info")


## "" when the rocket can launch, else why not (no pad yet, or the energy cells are recharging).
func rocket_status() -> String:
	var os_: OrbitSites = OrbitSites.of(self)  # [v6pace] the rocket's gate is data (Hub.rocket_open); once owned it travels with Lumi
	if not (Hub.rocket_open(hub.level) or DevHooks.has("rocket") or GameState.world.get("rocket_parked", false) or (os_ != null and os_.rocket_unlocked())):
		return Hub.rocket_lock_text(hub.level)
	var left: float = RocketTiers.recharge_left()
	if left > 0.0:
		return tr("Energy cells recharging: %s. Rocket upgrades refill them faster.") % RocketTiers.fmt_time(left)
	return ""


## Salvaged building materials from scooped junk (data/hub.json "materials").
func salvage_materials(type_id: String, vol: float) -> void:
	# [v5play] The globe pays Parts for scooped metal, plastic and glass too, as the flat game did
	# (it returned early here since the first globe port, so Parts came only from digs: base 2 and
	# 3 sat behind a Parts wall, and the "salvage junk" hint was wrong).
	if composter:
		composter.on_salvage(type_id, vol)
	var m: Dictionary = hub.data.get("materials", {}).get(type_id, {}) if hub else {}
	if m.is_empty():
		return
	var got: float = vol * float(m.get("per_unit", 0.1))
	GameState.add_currency(str(m["id"]), BigNum.from_float(got))
	if orbit:
		GameState.inc_stat("parts_salvaged", got)


func add_cube(cube: JunkCube) -> void:
	_cubes_root.add_child(cube)



# --- Interaction / UI -------------------------------------------------------------

func try_interact(p: Patch) -> void:
	orbit.try_interact(p)


func interact_prompt(p: Patch) -> String:
	return orbit.interact_prompt(p)


## Where the workbench is: the start site's bench anchor.
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
	if orbit:
		orbit.unhandled_input(event)


# --- Persistence -----------------------------------------------------------------

func persist_save() -> void:
	orbit.persist_save()  # GameState.orbit (direction + height)
