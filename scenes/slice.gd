extends Node3D
## M1 "The Slice": the Junkyard hex field around the first hub. Builds the world in code,
## wires sim ↔ view, owns hex-flip moments, saving of world objects, and UI routing.

const SPAWN := Vector3(0, 0.05, 3.0)
const BOARD_POS := Vector3(-3.4, 0, -1.6)
const FLOWER_POS := Vector3(2.9, 0, 1.4)
const HEX_MILESTONES: Array[int] = [1, 5, 10, 25, 50, 100, 150, 200, 264]

var field: HexField
var layout: CityLayout
var city: CityView
var view: FieldView
var depot: Depot
var patch: Patch
var cam: CameraRig
var hud: HUD
var upgrades: UpgradesScreen
var pause_menu: PauseMenu
var bot: InputSource
var _cubes_root: Node3D
var _flower: Node3D
var _sun: DirectionalLight3D
var _env: Environment
var _t: float = 0.0


func _ready() -> void:
	var t0: int = Time.get_ticks_msec()
	add_to_group("persist")
	_build_environment()
	var cfg: Dictionary = Economy.planet.get("slice_field", {})
	var seed_v: int = int(DevHooks.get_f("seed", float(cfg.get("seed", 4471))))
	layout = CityLayout.new(seed_v, 150.0)
	field = HexField.new(int(cfg.get("radius", 9)), float(cfg.get("hex_size", 3.2)), seed_v, layout)
	field.clean_threshold = float(cfg.get("clean_threshold", 0.99))
	var ppx: Array = cfg.get("pieces_per_hex", [6, 12])
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	field.generate(types, Vector2i(int(ppx[0]), int(ppx[1])))
	field.place_landmarks(Economy.landmarks)
	field.bury_parts(Economy.parts)
	var loaded: bool = false
	if not DevHooks.has("fresh"):
		loaded = SaveManager.load_game()
		if loaded and GameState.world.has("field"):
			if not field.apply_dict(GameState.world["field"]):
				push_warning("Saved field didn't match this field; starting the field fresh.")
	view = FieldView.new()
	view.name = "FieldView"
	add_child(view)
	view.setup(field)
	city = CityView.new()
	city.name = "City"
	add_child(city)
	city.build(layout, view.ground_material)
	_cubes_root = Node3D.new()
	_cubes_root.name = "Cubes"
	add_child(_cubes_root)
	depot = Depot.new()
	depot.name = "Depot"
	depot.position = Vector3(0, 0, -1.8)
	add_child(depot)
	_build_board()
	_build_flower()
	patch = Patch.new()
	patch.name = "Patch"
	patch.world = self
	if DevHooks.has("autoplay"):
		bot = AutoplayBot.new(self)
		patch.input = bot
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
	hud = HUD.new()
	hud.patch = patch
	hud.world = self
	add_child(hud)
	upgrades = UpgradesScreen.new()
	add_child(upgrades)
	upgrades.closed.connect(_on_modal_closed)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.closed.connect(_on_modal_closed)
	if loaded:
		_restore_world()
	cam.snap()
	if DevHooks.has("spawn-hex"):
		var hid: int = int(DevHooks.get_f("spawn-hex", 30.0))
		patch.global_position = field.hex_center(hid) + Vector3(0, 0.05, field.hex_size * 0.9)
		var pid0: int = field.hex_pieces[hid][0]
		print("[slice] piece0 xf=", view.piece_transform(pid0), " model=", field.piece_model[pid0], " mm_count=", view._mms.size(), " inst=", view._mms[view._piece_mm[pid0]].instance_count, " mmaabb=", view._mms[view._piece_mm[pid0]].get_aabb(), " itx=", view._mms[view._piece_mm[pid0]].get_instance_transform(view._piece_slot[pid0]))
		print("[slice] pieces=%d junk_hexes=%d hex%d pieces=%d piles=%s" % [field.piece_count(), field.junk_hex_count, hid, field.hex_pieces[hid].size(), str(field.hex_piles[hid])])
	if DevHooks.has("cam"):
		cam.apply_preset(DevHooks.get_s("cam", "wide"))
	if DevHooks.has("give"):
		GameState.add_currency("cubes", BigNum.from_float(DevHooks.get_f("give", 100.0)))
	if DevHooks.get_s("open", "") == "upgrades":
		open_upgrades.call_deferred()
	EventBus.hitstop_requested.connect(_hitstop)
	print("[slice] built in %d ms" % (Time.get_ticks_msec() - t0))
	if not loaded:
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			Story.once("wake", "Bzzt. Systems... online. So much junk. Hold [LMB] or [Space] to scoop it up.", "story"))
	if not bot and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	# Act 1: heavy, hazy, slightly violet-brown sky. Later acts lower turbidity and mie.
	sm.rayleigh_coefficient = 1.6
	sm.rayleigh_color = Color(0.42, 0.42, 0.62)
	sm.mie_coefficient = 0.012
	sm.mie_eccentricity = 0.82
	sm.mie_color = Color(0.86, 0.72, 0.66)
	sm.turbidity = 14.0
	sm.sun_disk_scale = 1.2
	sm.ground_color = Color(0.3, 0.27, 0.26)
	sm.energy_multiplier = 1.0
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.2
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
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.78, 0.72, 0.74)
	env.volumetric_fog_emission = Color(0.06, 0.05, 0.07)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_sky_affect = 0.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.62, 0.58, 0.62)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-32, -48, 0)
	_sun.light_color = Color(1.0, 0.9, 0.78)
	_sun.light_energy = 2.2
	_sun.light_angular_distance = 0.6
	_sun.light_volumetric_fog_energy = 1.4
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.0
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	Settings.apply_render_quality(env, get_viewport())
	Settings.apply_sun_quality(_sun)


func _build_board() -> void:
	# The hub terminal: an old utility cabinet with a working screen.
	var board := Node3D.new()
	board.name = "UpgradeTerminal"
	board.position = BOARD_POS
	board.rotation_degrees = Vector3(0, 35, 0)
	add_child(board)
	var cab := MeshInstance3D.new()
	cab.mesh = AssetLib.model_mesh("utility_box_01")
	board.add_child(cab)
	var aabb: AABB = cab.mesh.get_aabb()
	var screen := Label3D.new()
	screen.text = "MUNICIPAL SANITATION\nUPGRADE TERMINAL\n> READY_"
	screen.font_size = 28
	screen.pixel_size = 0.0018
	screen.modulate = Color(0.55, 1.0, 0.75)
	screen.outline_size = 0
	screen.shaded = false
	screen.position = Vector3(aabb.get_center().x, aabb.end.y * 0.72, aabb.end.z + 0.01)
	board.add_child(screen)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.55, 1.0, 0.75)
	lamp.light_energy = 0.4
	lamp.omni_range = 1.5
	lamp.position = screen.position + Vector3(0, 0, 0.3)
	board.add_child(lamp)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = aabb.size
	cs.shape = bs
	cs.position = aabb.get_center()
	sb.add_child(cs)
	board.add_child(sb)
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
	var gen := MeshInstance3D.new()
	gen.mesh = AssetLib.model_mesh("portable_generator")
	gen.position = Vector3(-4.6, 0, 0.8)
	gen.rotation_degrees = Vector3(0, 70, 0)
	add_child(gen)


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

func collect_piece(pid: int) -> void:
	var hid: int = field.piece_hex[pid]
	var became_clean: bool = field.remove_piece(pid)
	view.hide_piece(pid)
	view.refresh_hex(hid, became_clean)
	if became_clean:
		_on_hex_clean(hid)


func _on_hex_clean(hid: int) -> void:
	var bonus: BigNum = Economy.hex_bonus(field.hex_total[hid])
	GameState.add_currency("cubes", bonus)
	GameState.inc_stat("hexes_cleaned")
	var center: Vector3 = field.hex_center(hid)
	Audio.play("chime", 1.0, -3.0)
	Vfx.burst("big_sparkle", center + Vector3(0, 0.3, 0), Color(1.0, 0.92, 0.55))
	Vfx.ring(center, field.hex_size * 1.1, Color(1.0, 0.9, 0.5, 0.9), 0.8)
	Vfx.float_text(center + Vector3(0, 1.4, 0), "HEX CLEAN!  +" + Settings.fmt(bonus), Color(1.0, 0.92, 0.45), 1.5, 2.0)
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
			EventBus.toast.emit("Milestone: %d hexes clean!" % n, "story")
		if n >= field.junk_hex_count:
			EventBus.toast.emit("The whole Junkyard is clean. Patch beeps a very long, very happy beep.", "story")


func add_cube(cube: JunkCube) -> void:
	_cubes_root.add_child(cube)


func _hitstop(duration: float, scale: float) -> void:
	if Settings.reduced_motion:
		return
	Engine.time_scale = scale * (float(DevHooks.get_f("time-scale", 1.0)))
	get_tree().create_timer(duration, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = DevHooks.get_f("time-scale", 1.0))


# --- Interaction / UI -------------------------------------------------------------

func try_interact(p: Patch) -> void:
	if near_bench():
		open_upgrades()


func interact_prompt(p: Patch) -> String:
	if near_bench():
		return "upgrades"
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
		EventBus.toast.emit("Upgrades need a workbench. Head back to the hub.", "info")
		Audio.play("buzz", 1.2, -10.0)
		return
	upgrades.open_screen()
	if patch.input is PlayerInput:
		(patch.input as PlayerInput).enabled = false
	cam.input_enabled = false


func _on_modal_closed() -> void:
	if patch.input is PlayerInput:
		(patch.input as PlayerInput).enabled = true
	cam.input_enabled = true
	if not bot and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if upgrades.is_open or pause_menu.is_open:
		return
	if event.is_action_pressed("open_upgrades"):
		open_upgrades()
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
	GameState.world["patch"] = patch.to_dict()
	var cubes: Array = []
	for n: Node in _cubes_root.get_children():
		var c: JunkCube = n as JunkCube
		if c and not c.carried and not c.claimed:
			cubes.append(c.to_dict())
	GameState.world["cubes"] = cubes


func _restore_world() -> void:
	for cd: Dictionary in GameState.world.get("cubes", []):
		var c: JunkCube = JunkCube.from_dict(cd)
		add_cube(c)
		var p: Array = cd.get("pos", [0.0, 1.0, 0.0])
		c.global_position = Vector3(float(p[0]), float(p[1]) + 0.02, float(p[2]))
		var r: Array = cd.get("rot", [0.0, 0.0, 0.0])
		c.rotation = Vector3(float(r[0]), float(r[1]), float(r[2]))
	if GameState.world.has("patch"):
		patch.from_dict(GameState.world["patch"])
	EventBus.toast.emit("Welcome back. The junk waited for you.", "info")
