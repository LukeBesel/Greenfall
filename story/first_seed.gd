class_name FirstSeed
extends Node3D
## Act 3 opener: the ruined greenhouse, the Maker seed tin, the long cinematic with WREN's story,
## the first planting and the first sprout. Runs once.

const GREENHOUSE_POS := Vector3(15.0, 0.0, -9.0)
# l10n:begin
const LINES: Array[Array] = [
	["Wait. Hold it up to the light.", 3.5],
	["That's a Maker seed tin. Cradle stamp on the lid. One of ours, left behind in the rush.", 5.0],
	["When they left, the Makers sealed every seed they could carry into the Cradle's vault. Your vault, Lumi.", 6.0],
	["The plan was simple. Wait for the dust to settle. Come home. Plant. They called that day the Greenfall.", 7.5],
	["Then three hundred years went by, and the dust never settled. Until a seed-keeper fell out of the sky.", 5.5],
	["Nothing grows on its own anymore. The soil forgot how. Somebody has to put it in the ground.", 6.0],
	["That somebody is you. Small. Stubborn. Running on four percent. Perfect.", 4.5],
	["Find clean ground. Dig. Drop it in. Pat it down. And then — this part matters — water it.", 6.0],
]
# l10n:end

var world: Node
var _tin: Node3D
var _tin_light: OmniLight3D
var _active: bool = false
var _letterbox: CanvasLayer
var _bars: Array[ColorRect] = []
var _waiting_sprout: bool = false


func setup() -> void:
	_build_greenhouse()
	if GameState.flags.get("seeds_unlocked", false):
		_tin.visible = false
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: _check())
	_letterbox = CanvasLayer.new()
	_letterbox.layer = 25
	add_child(_letterbox)
	for top: bool in [true, false]:
		var r := ColorRect.new()
		r.color = Color.BLACK
		r.anchor_right = 1.0
		r.anchor_top = 0.0 if top else 1.0
		r.anchor_bottom = 0.0 if top else 1.0
		r.offset_bottom = 0.0
		r.offset_top = 0.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_letterbox.add_child(r)
		_bars.append(r)
	_check.call_deferred()


func _build_greenhouse() -> void:
	var gh := Node3D.new()
	add_child(gh)
	gh.position = GREENHOUSE_POS
	var frame: StandardMaterial3D = Mats.metal("dark_steel")
	var glass: StandardMaterial3D = Mats.glass(Color(0.6, 0.75, 0.75, 0.25), 0.1)
	var parts: Array = []
	for i: int in 5:
		var z: float = -4.0 + i * 2.0
		for x: float in [-2.5, 2.5]:
			parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.08, 2.4, 0.08)), ProcMesh.xf(Vector3(x, 1.2, z))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(2.9, 0.08, 0.08)), ProcMesh.xf(Vector3(-1.3, 2.9, z), Vector3(0, 0, 22))))
		if i != 2:  # a collapsed bay
			parts.append(ProcMesh.part(ProcMesh.box(Vector3(2.9, 0.08, 0.08)), ProcMesh.xf(Vector3(1.3, 2.9, z), Vector3(0, 0, -22))))
	var fm := MeshInstance3D.new()
	fm.mesh = ProcMesh.merge(parts)
	fm.material_override = frame
	gh.add_child(fm)
	for spec: Array in [[Vector3(-1.3, 2.9, -3.0), Vector3(0, 0, 22)], [Vector3(1.3, 2.9, 1.0), Vector3(0, 0, -22)], [Vector3(-2.5, 1.3, 2.0), Vector3(0, 0, 0)]]:
		var g := MeshInstance3D.new()
		g.mesh = ProcMesh.box(Vector3(2.8, 0.02, 1.9) if spec[0].y > 2.0 else Vector3(0.02, 2.2, 1.9))
		g.material_override = glass
		g.position = spec[0]
		g.rotation_degrees = spec[1]
		gh.add_child(g)
	# Dry planting beds.
	for x: float in [-1.4, 1.4]:
		var bed := MeshInstance3D.new()
		bed.mesh = ProcMesh.box(Vector3(1.4, 0.35, 7.0))
		bed.material_override = AssetLib.pbr_material("dry_ground_rocks", 0.6, Color(0.8, 0.75, 0.7), true)
		bed.position = Vector3(x, 0.17, 0)
		gh.add_child(bed)
	var tray := MeshInstance3D.new()
	tray.mesh = AssetLib.model_mesh_lite("seeding_tray_01", 3000)
	tray.position = Vector3(-1.4, 0.36, -2.0)
	gh.add_child(tray)
	# The seed tin.
	_tin = Node3D.new()
	_tin.position = Vector3(1.4, 0.36, 0.5)
	gh.add_child(_tin)
	var tin := MeshInstance3D.new()
	tin.mesh = AssetLib.model_mesh_lite("oil_tin", 2000)
	tin.scale = Vector3.ONE * 0.7
	_tin.add_child(tin)
	_tin_light = OmniLight3D.new()
	_tin_light.light_color = Color(0.6, 1.0, 0.6)
	_tin_light.light_energy = 0.0
	_tin_light.omni_range = 3.0
	_tin_light.position = Vector3(0, 0.4, 0)
	_tin.add_child(_tin_light)
	var sb := StaticBody3D.new()
	for x: float in [-1.4, 1.4]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.4, 0.4, 7.0)
		cs.shape = bs
		cs.position = Vector3(x, 0.2, 0)
		sb.add_child(cs)
	gh.add_child(sb)


func ready_to_find() -> bool:
	return not GameState.flags.get("seeds_unlocked", false) and world.field.cleaned_count >= int(world.garden.cfg.get("first_seed", {}).get("hexes_needed", 5))


func _check() -> void:
	if ready_to_find() and not GameState.flags.get("seed_signal", false):
		GameState.flags["seed_signal"] = true
		world.wren.line_started.emit(tr("Lumi. I'm getting a signal. Green, faint, east of the hub. An old greenhouse. Go look."), 1)
		Audio.play("detector", 0.7, -6.0)


func _process(delta: float) -> void:
	if _tin and _tin.visible and ready_to_find():
		_tin_light.light_energy = 1.2 + sin(Time.get_ticks_msec() * 0.004) * 0.6
		_tin.rotation.y += delta * 0.5
	if _waiting_sprout:
		for s: int in world.garden.slot_species.size():
			if world.garden.slot_species[s] >= 0 and world.garden.slot_stage[s] >= 1:
				_waiting_sprout = false
				_sprout_moment(world.garden.slot_pos[s])
				break


func near_tin(pos: Vector3) -> bool:
	return _tin != null and _tin.visible and ready_to_find() and _tin.global_position.distance_to(pos) < 2.2


func take_tin() -> void:
	if _active:
		return
	_active = true
	_tin.visible = false
	var cfg: Dictionary = world.garden.cfg.get("first_seed", {})
	_cinematic()
	await get_tree().create_timer(_total_time() + 1.0).timeout
	GameState.flags["seeds_unlocked"] = true
	GameState.add_currency("seeds", BigNum.from_float(float(cfg.get("seeds_given", 15))))
	world.patch.water = world.patch.water_cap()
	world.patch.set_tool(Patch.Tool.PLANT)
	EventBus.tutorial_changed.emit(Tutorial.glyphs(tr("Find clean ground.  Hold  {scoop}  to plant.  {tool_water}  for the watering can, hold  {scoop}  to water.")))  # [deck]
	_waiting_sprout = true
	_active = false


func _total_time() -> float:
	var t: float = 0.0
	for l: Array in LINES:
		t += float(l[1])
	return t


func _cinematic() -> void:
	if world.get("music") != null:
		world.music.set_cinematic(true)
	var cam: CameraRig = world.cam
	var hud: CanvasLayer = world.hud
	hud.visible = false
	cam.input_enabled = false
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = false
	for i: int in _bars.size():
		var r: ColorRect = _bars[i]
		var tw := create_tween()
		if i == 0:
			tw.tween_property(r, "offset_bottom", 90.0, 0.8)
		else:
			tw.tween_property(r, "offset_top", -90.0, 0.8)
	Audio.play("fanfare", 0.6, -10.0)
	var start_yaw: float = cam.yaw
	var dist0: float = cam.distance
	cam.distance = 3.4
	var total: float = _total_time()
	var tw2 := create_tween()
	tw2.tween_method(func(v: float) -> void:
		cam.yaw = start_yaw + v * 1.6
		cam.pitch = lerpf(-0.18, -0.42, v), 0.0, 1.0, total)
	for l: Array in LINES:
		world.wren.line_started.emit(str(l[0]), 1)
		await get_tree().create_timer(float(l[1])).timeout
	for i: int in _bars.size():
		var r: ColorRect = _bars[i]
		var tw := create_tween()
		if i == 0:
			tw.tween_property(r, "offset_bottom", 0.0, 0.8)
		else:
			tw.tween_property(r, "offset_top", 0.0, 0.8)
	cam.distance = dist0
	hud.visible = true
	cam.input_enabled = true
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = true


func _sprout_moment(pos: Vector3) -> void:
	EventBus.hitstop_requested.emit(1.2, 0.3)
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.7, 1.0, 0.6)
	flash.light_energy = 8.0
	flash.omni_range = 8.0
	add_child(flash)
	flash.global_position = pos + Vector3(0, 0.6, 0)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 2.5)
	tw.tween_callback(flash.queue_free)
	Vfx.burst("big_sparkle", pos + Vector3(0, 0.3, 0), Color(0.7, 1.0, 0.6))
	Audio.play("chime", 0.7, -2.0)
	Audio.play("fanfare", 0.8, -6.0)
	world.wren.line_started.emit(tr("...It's green. Lumi, it's actually green."), 1)
	await get_tree().create_timer(4.5).timeout
	world.wren.line_started.emit(tr("Keep it watered. Plant more. Every bloom gives you seeds back, and a little green light for your core. This is how it starts."), 1)
	EventBus.tutorial_changed.emit("")
	GameState.flags["first_sprout"] = true
	Audio.music_sting("first_sprout")
	if world.get("music") != null:
		world.music.set_cinematic(false)
