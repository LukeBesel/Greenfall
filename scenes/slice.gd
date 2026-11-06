extends Node3D
## M1 "The Slice": the Junkyard hex field around the first hub. Builds the world in code,
## wires sim ↔ view, owns hex-flip moments, saving of world objects, and UI routing.

const SPAWN := Vector3(0, 0.05, 3.0)
const BOARD_POS := Vector3(-3.4, 0, -1.6)
const FLOWER_POS := Vector3(2.9, 0, 1.4)
const HEX_MILESTONES: Array[int] = [1, 5, 10, 25, 50, 100, 150, 200, 264]

var field: HexField
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
var _t: float = 0.0


func _ready() -> void:
	add_to_group("persist")
	_build_environment()
	var cfg: Dictionary = Economy.planet.get("slice_field", {})
	var seed_v: int = int(DevHooks.get_f("seed", float(cfg.get("seed", 4471))))
	field = HexField.new(int(cfg.get("radius", 9)), float(cfg.get("hex_size", 3.2)), seed_v)
	field.clean_threshold = float(cfg.get("clean_threshold", 0.99))
	var ppx: Array = cfg.get("pieces_per_hex", [6, 12])
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	field.generate(types, Vector2i(int(ppx[0]), int(ppx[1])))
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
	if DevHooks.has("cam"):
		cam.apply_preset(DevHooks.get_s("cam", "wide"))
	if DevHooks.has("give"):
		GameState.add_currency("cubes", BigNum.from_float(DevHooks.get_f("give", 100.0)))
	if DevHooks.get_s("open", "") == "upgrades":
		open_upgrades.call_deferred()
	EventBus.hitstop_requested.connect(_hitstop)
	if not loaded:
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			Story.once("wake", "Bzzt. Systems... online. So much junk. Hold [LMB] or [Space] to scoop it up.", "story"))
	if not bot and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.43, 0.36, 0.68)
	sm.sky_horizon_color = Color(0.96, 0.7, 0.78)
	sm.sky_curve = 0.14
	sm.ground_horizon_color = Color(0.86, 0.64, 0.72)
	sm.ground_bottom_color = Color(0.36, 0.27, 0.42)
	sm.sun_angle_max = 25.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.68, 0.86)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.35
	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.ssao_radius = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.02
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, -38, 0)
	_sun.light_color = Color(1.0, 0.93, 0.82)
	_sun.light_energy = 1.3
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.5
	_sun.directional_shadow_max_distance = 70.0
	add_child(_sun)


func _build_board() -> void:
	var board := Node3D.new()
	board.name = "UpgradeBoard"
	board.position = BOARD_POS
	board.rotation_degrees = Vector3(0, 35, 0)
	add_child(board)
	var post_mat: ShaderMaterial = ProcMesh.toon_material(Color(0.55, 0.42, 0.35), 0.6, 21.0)
	for x: float in [-0.7, 0.7]:
		var post := MeshInstance3D.new()
		post.mesh = ProcMesh.cyl(0.07, 0.08, 2.0, 8)
		post.material_override = post_mat
		post.position = Vector3(x, 1.0, 0)
		board.add_child(post)
	var panel := MeshInstance3D.new()
	panel.mesh = ProcMesh.rounded_box(Vector3(1.9, 1.1, 0.12), 0.06, 2)
	panel.material_override = ProcMesh.toon_material(Color(0.3, 0.55, 0.52), 0.55, 22.0)
	panel.position = Vector3(0, 1.6, 0)
	board.add_child(panel)
	var l := Label3D.new()
	l.text = "UPGRADES"
	l.font_size = 72
	l.pixel_size = 0.005
	l.outline_size = 14
	l.modulate = Color(1.0, 0.9, 0.5)
	l.outline_modulate = Color(0.15, 0.08, 0.2)
	l.position = Vector3(0, 1.75, 0.08)
	board.add_child(l)
	var l2 := Label3D.new()
	l2.text = "[E] or [Tab]"
	l2.font_size = 40
	l2.pixel_size = 0.005
	l2.outline_size = 10
	l2.modulate = Color(1, 1, 1, 0.9)
	l2.position = Vector3(0, 1.38, 0.08)
	board.add_child(l2)


func _build_flower() -> void:
	# The First Flower: growing out of a crack in an old soda can. Never scoopable.
	_flower = Node3D.new()
	_flower.name = "FirstFlower"
	_flower.position = FLOWER_POS
	add_child(_flower)
	var parts: Array = []
	parts.append(ProcMesh.part(JunkMeshes.get_mesh("can"), ProcMesh.xf(Vector3(0, 0, 0), Vector3(0, 30, 0), Vector3.ONE * 1.4), Color(0.9, 0.3, 0.28)))
	parts.append(ProcMesh.part(ProcMesh.cyl(0.012, 0.016, 0.42, 6), ProcMesh.xf(Vector3(0.02, 0.36, 0), Vector3(0, 0, -6)), Color(0.35, 0.75, 0.35)))
	parts.append(ProcMesh.part(ProcMesh.sphere(0.06, 8, 4), ProcMesh.xf(Vector3(0.08, 0.24, 0), Vector3(0, 0, -40), Vector3(1.6, 0.4, 0.8)), Color(0.4, 0.82, 0.4)))
	parts.append(ProcMesh.part(ProcMesh.sphere(0.05, 8, 4), ProcMesh.xf(Vector3(-0.05, 0.31, 0.01), Vector3(0, 0, 35), Vector3(1.6, 0.4, 0.8)), Color(0.4, 0.82, 0.4)))
	for k: int in 6:
		var a: float = TAU * k / 6.0
		parts.append(ProcMesh.part(ProcMesh.sphere(0.045, 8, 4), ProcMesh.xf(Vector3(0.045 + cos(a) * 0.06, 0.58, sin(a) * 0.06), Vector3(0, -a * 57.3, 0), Vector3(1.4, 0.45, 1.0)), Color(1.0, 0.95, 0.98)))
	parts.append(ProcMesh.part(ProcMesh.sphere(0.035, 8, 4), ProcMesh.xf(Vector3(0.045, 0.6, 0)), Color(1.0, 0.82, 0.25)))
	var mi := MeshInstance3D.new()
	mi.mesh = ProcMesh.merge(parts)
	var mat: ShaderMaterial = ProcMesh.toon_material(Color.WHITE, 0.0)
	mi.material_override = mat
	_flower.add_child(mi)


func _process(delta: float) -> void:
	_t += delta
	if _flower:
		_flower.rotation.z = sin(_t * 1.3) * 0.03


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
	if p.global_position.distance_to(BOARD_POS) < 2.6:
		open_upgrades()


func interact_prompt(p: Patch) -> String:
	if p.global_position.distance_to(BOARD_POS) < 2.6:
		return "upgrades"
	if p.global_position.distance_to(FLOWER_POS) < 1.8:
		return "flower"
	return ""


func open_upgrades() -> void:
	if pause_menu.is_open:
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
