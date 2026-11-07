class_name Recycler
extends Node3D
## The Recycler: bales drop into a throat with two counter-rotating toothed shredder drums; the
## shred is blown into a little smelter (glowing window, chimney steam). The bale is gone for
## good; out come Parts and a few cubes [money]. Fed by the conveyor's incline belt
## or by hand on the intake plate (Patch drives on, his bales hop in). Local +Z faces the feeder.

const THROAT := Vector3(0, 1.05, 0.2)
const PAD_LOCAL := Vector3(-1.75, 0, 1.45)
const PAD_HALF: float = 0.55
const MAX_QUEUE: int = 3

static var _hub_data: Dictionary = {}

var stations: Stations
var queue: Array[JunkCube] = []
var _cur: JunkCube
var _t: float = 0.0
var _dur: float = 3.2
var _spark_t: float = 0.0
var _drums: Array[Node3D] = []
var _drum_spin: float = 0.0
var _glow: float = 0.0
var _glow_mat: StandardMaterial3D
var _glow_light: OmniLight3D
var _beacon: StandardMaterial3D
var _steam_t: float = 0.0
var _feed_t: float = 0.0
var _clock: float = 0.0
var _ingots: Node3D
var _ingot_n: int = 0


func _ready() -> void:
	add_to_group("recycler")
	_build()


## Belt path for the conveyor's incline line, from the feeder pad edge up over the throat lip.
func belt_path(from: Vector3) -> Array[Vector3]:
	var xf: Transform3D = global_transform if is_inside_tree() else transform
	return [from, xf * Vector3(0, 1.45, 1.35), xf * Vector3(0, 1.45, 0.62)]


func throat_world() -> Vector3:
	return to_global(THROAT)


func pad_contains(p: Vector3) -> bool:
	var d: Vector3 = p - to_global(PAD_LOCAL)
	return absf(d.x) <= PAD_HALF and absf(d.z) <= PAD_HALF and p.y < 1.6


func can_feed() -> bool:
	return queue.size() < MAX_QUEUE


func busy() -> bool:
	return _cur != null or not queue.is_empty()


## Takes a bale (from a belt, the pad or Patch) and drops it into the throat.
func feed(cube: JunkCube) -> void:
	cube.claimed = true
	cube.set_carried(true)
	if cube.get_parent() != self:
		if cube.get_parent():
			cube.reparent(self, true)
		else:
			add_child(cube)
	queue.append(cube)
	var start: Vector3 = cube.global_position
	var end: Vector3 = throat_world() + Vector3(0, 0.25, 0)
	var top: Vector3 = (start + end) * 0.5 + Vector3(0, 0.5 + maxf(0.0, end.y - start.y) * 0.4, 0)
	cube.set_meta("arriving", true)
	var tw := cube.create_tween()
	tw.tween_method(func(t: float) -> void:
		cube.global_position = start.lerp(top, t).lerp(top.lerp(end, t), t)
		cube.rotation += Vector3(0.02, 0.03, 0.0)
		, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		cube.remove_meta("arriving")
		Audio.play("thud", 0.8, -6.0))


## Pays out for one bale and frees it. Returns what it gave: {parts, cubes, kg}.
## [money] Bolts and the three building stocks are one currency now: Parts. A bale gives a flat
## parts_per_bale plus its volume's worth of stock (metal-heavy bales give the most).
func recycle(cube: JunkCube) -> Dictionary:
	var d: Dictionary = stations.def("recycler") if stations else Economy.read_json("res://data/stations.json").get("recycler", {})
	var y: float = Stations.yield_mult()
	var fill: float = clampf(float(cube.info.get("fill", 1.0)), 0.25, 1.2)
	var vol: float = float(cube.info.get("volume", fill * 12.0))
	var parts: float = maxf(1.0, round(float(d.get("parts_per_bale", 10.0)) * (0.5 + fill) * y))
	var cubes: BigNum = cube.value.mul_f(float(d.get("cube_mult", 0.25)))
	if _hub_data.is_empty():
		_hub_data = Economy.read_json("res://data/hub.json")
	var mdefs: Dictionary = _hub_data.get("materials", {})
	var dom: String = str(cube.info.get("dominant", ""))
	var per: float = vol * float(d.get("material_mult", 4.0)) * y
	if mdefs.has(dom):
		parts += per * float(mdefs[dom].get("per_unit", 0.1))
	else:
		# Mixed or unknown junk: the average of the three stocks.
		for k: String in mdefs:
			parts += per * float(mdefs[k].get("per_unit", 0.1)) / maxf(mdefs.size(), 1.0)
	parts = round(parts * 10.0) / 10.0
	GameState.add_currency("parts", BigNum.from_float(parts))
	if cubes.mantissa > 0.0:
		GameState.add_currency("cubes", cubes)
	var kg: float = cube.mass
	GameState.inc_stat("bales_recycled")
	GameState.inc_stat("junk_destroyed_kg", kg)
	GameState.inc_stat("air_filtered", float(d.get("air_per_bale", 30.0)))
	queue.erase(cube)
	cube.queue_free()
	return {"parts": parts, "cubes": cubes, "kg": kg}


func build_in() -> void:
	var final: Vector3 = position
	position = final + Vector3(0, 12.0, 0)
	var tw := create_tween()
	tw.tween_property(self, "position", final, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		Audio.play("thud", 0.6, 0.0)
		Audio.play("clunk", 0.7, -2.0)
		EventBus.shake_requested.emit(0.25)
		Vfx.burst("dust", global_position + Vector3(0, 0.3, 0), Color(0.7, 0.65, 0.6, 0.7), 2.5)
		Vfx.burst("steam", to_global(Vector3(-1.55, 3.5, -0.3)), Color(0.9, 0.9, 0.9, 0.6), 1.0))


# --- Running ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	_feed_t -= delta
	if _feed_t <= 0.0 and can_feed():
		_feed_t = 0.3
		var p: Node3D = stations.patch_node() if stations else null
		if p and pad_contains(p.global_position) and p.has_method("pop_carried_cube"):
			var c: JunkCube = p.pop_carried_cube()
			if c:
				feed(c)
		else:
			for n: Node in get_tree().get_nodes_in_group("junk_cube"):
				var c2: JunkCube = n
				if not c2.carried and not c2.claimed and pad_contains(c2.global_position):
					feed(c2)
					break
	if _cur == null:
		for c3: JunkCube in queue:
			if is_instance_valid(c3) and not c3.has_meta("arriving"):
				_start(c3)
				break
	var target_spin: float = 9.0 if _cur else 1.2
	_drum_spin = lerpf(_drum_spin, target_spin, clampf(delta * 3.0, 0.0, 1.0))
	for i: int in _drums.size():
		_drums[i].rotation.x += delta * _drum_spin * (1.0 if i == 0 else -1.0)
	_glow = lerpf(_glow, 1.0 if _cur else 0.25, clampf(delta * (1.5 if _cur else 0.4), 0.0, 1.0))
	var flicker: float = 0.85 + 0.15 * sin(_clock * 17.0) * sin(_clock * 5.3)
	if _glow_mat:
		_glow_mat.emission_energy_multiplier = 1.0 + _glow * 5.0 * flicker
	if _glow_light:
		_glow_light.light_energy = 0.3 + _glow * 2.2 * flicker
	if _beacon:
		_beacon.emission_energy_multiplier = (3.0 + 2.0 * sin(_clock * 10.0)) if busy() else 0.5
	_steam_t -= delta
	if _steam_t <= 0.0:
		_steam_t = 0.5 if _cur else 2.6
		Vfx.burst("steam", to_global(Vector3(-1.55, 3.55, -0.3)), Color(0.92, 0.92, 0.95, 0.35 if _cur else 0.18), 0.35 if _cur else 0.15)
	if _cur:
		_work(delta)


func _start(c: JunkCube) -> void:
	_cur = c
	_t = 0.0
	var d: Dictionary = stations.def("recycler") if stations else {}
	_dur = float(d.get("process_time", 3.2))
	Audio.play("servo", 0.6, -6.0)
	Audio.play("hydraulic", 0.8, -8.0)


func _work(delta: float) -> void:
	if not is_instance_valid(_cur):
		_cur = null
		return
	_t += delta
	var k: float = clampf(_t / _dur, 0.0, 1.0)
	var base: Vector3 = throat_world()
	# The bale sinks between the drums, chewed smaller and shaking.
	var shake := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.03 * (1.0 - k)
	_cur.global_position = base + Vector3(0, 0.25 - 0.55 * smoothstep(0.0, 1.0, k), 0) + shake
	_cur.scale = Vector3.ONE * lerpf(1.0, 0.15, smoothstep(0.1, 1.0, k))
	_cur.rotation.z = sin(_t * 30.0) * 0.06
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = randf_range(0.1, 0.2)
		var cols: Array = _cur.info.get("colors", [])
		var col: Color = cols[0] if cols.size() > 0 else Color(0.55, 0.52, 0.5)
		Vfx.burst("sparkle", base + Vector3(randf_range(-0.3, 0.3), 0.15, randf_range(-0.2, 0.2)), Color(1.0, 0.62, 0.22), 0.5)
		Vfx.burst("bits", base + Vector3(0, 0.2, 0), col, 0.4)
		Audio.play("crunch", randf_range(0.7, 0.95), -9.0)
		EventBus.shake_requested.emit(0.015)
	if k >= 1.0:
		_finish()


func _finish() -> void:
	var c: JunkCube = _cur
	_cur = null
	var got: Dictionary = recycle(c)
	Audio.play("steam", 0.9, -4.0)
	Audio.play("clunk", 0.7, -6.0)
	var window: Vector3 = to_global(Vector3(-2.15, 0.62, -0.3))
	Vfx.burst("steam", to_global(Vector3(-1.55, 3.55, -0.3)), Color(0.95, 0.95, 0.97, 0.6), 1.0)
	Vfx.burst("sparkle", window, Color(1.0, 0.55, 0.15), 1.0)
	var txt: String = L10nFmt.amount("parts", float(got["parts"]), true)  # [money]
	Vfx.float_text(throat_world() + Vector3(0, 0.8, 0), txt, Color(0.75, 0.95, 1.0), 0.7, 1.2)
	Vfx.float_text(throat_world() + Vector3(0, 1.25, 0), tr("GONE FOR GOOD  -%d kg") % int(got["kg"]), Color(0.7, 1.0, 0.7), 0.55, 1.4)
	_pop_ingot()


func _pop_ingot() -> void:
	# A small cast ingot slides out of the smelter into the tray (the last few stay visible).
	var ing := MeshInstance3D.new()
	ing.mesh = ProcMesh.rounded_box(Vector3(0.16, 0.06, 0.08), 0.015, 1)
	ing.material_override = Mats.metal("brass") if _ingot_n % 3 == 0 else Mats.metal("steel")
	_ingots.add_child(ing)
	var slot: int = _ingot_n % 8
	_ingot_n += 1
	@warning_ignore("integer_division")
	var final := Vector3(-0.12 + (slot % 3) * 0.12, 0.05 + (slot / 3) * 0.065, -0.06 + (slot % 2) * 0.1)
	ing.position = Vector3(0.3, 0.45, -0.6)
	var tw := ing.create_tween()
	tw.tween_property(ing, "position", final, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if _ingots.get_child_count() > 8:
		_ingots.get_child(0).queue_free()


func held_dicts() -> Array:
	var out: Array = []
	for c: JunkCube in queue:
		if is_instance_valid(c):
			out.append(c.to_dict())
	return out


# --- Construction -------------------------------------------------------------------

func _build() -> void:
	var body_mat: ShaderMaterial = Mats.worn_paint(Color(0.18, 0.46, 0.5), 0.8, 0.5, 61.0, 0.55)
	var yellow: ShaderMaterial = Mats.worn_paint(Color(0.94, 0.7, 0.14), 0.75, 0.45, 62.0, 0.5)
	var dark: StandardMaterial3D = Mats.metal("dark_steel")
	var kiln_mat: ShaderMaterial = Mats.worn_paint(Color(0.3, 0.27, 0.25), 0.45, 0.85, 63.0, 0.8)
	# Skid and housing.
	var parts: Array = []
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(3.9, 0.14, 2.1)), ProcMesh.xf(Vector3(-0.7, 0.07, 0))))
	for x: float in [-2.55, 1.15]:
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.14, 0.2, 2.1)), ProcMesh.xf(Vector3(x, 0.1, 0))))
	var skid := MeshInstance3D.new()
	skid.mesh = ProcMesh.merge(parts)
	skid.material_override = dark
	add_child(skid)
	var housing := MeshInstance3D.new()
	housing.mesh = ProcMesh.rounded_box(Vector3(2.0, 0.86, 1.7), 0.06, 2)
	housing.material_override = body_mat
	housing.position = Vector3(0, 0.57, 0)
	add_child(housing)
	# Ribs and an access door on the front face.
	var ribs: Array = []
	for x: float in [-0.95, -0.3, 0.3, 0.95]:
		ribs.append(ProcMesh.part(ProcMesh.box(Vector3(0.06, 0.82, 0.06)), ProcMesh.xf(Vector3(x, 0.57, 0.86))))
	ribs.append(ProcMesh.part(ProcMesh.box(Vector3(2.04, 0.08, 0.08)), ProcMesh.xf(Vector3(0, 1.0, 0.84))))
	ribs.append(ProcMesh.part(ProcMesh.box(Vector3(2.04, 0.08, 0.08)), ProcMesh.xf(Vector3(0, 1.0, -0.84))))
	var rib_mi := MeshInstance3D.new()
	rib_mi.mesh = ProcMesh.merge(ribs)
	rib_mi.material_override = body_mat
	add_child(rib_mi)
	var label := Mats.stencil(tr("RECYCLER"), 120, Color(0.95, 0.93, 0.85, 0.92))
	label.position = Vector3(-0.1, 0.7, 0.905)
	add_child(label)
	var label2 := Mats.stencil(tr("SHRED  ·  SMELT  ·  GONE FOR GOOD"), 52, Color(0.95, 0.85, 0.4, 0.9))
	label2.position = Vector3(-0.1, 0.46, 0.905)
	add_child(label2)
	# Throat: a flared hopper with hazard lips, seen into from above.
	var fparts: Array = []
	var top_y: float = 1.28
	for s: float in [-1.0, 1.0]:
		fparts.append(ProcMesh.part(ProcMesh.box(Vector3(1.6, 0.34, 0.05)), ProcMesh.xf(Vector3(0, 1.12, THROAT.z + s * 0.6), Vector3(-s * 28.0, 0, 0))))
		fparts.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 0.34, 1.25)), ProcMesh.xf(Vector3(s * 0.8, 1.12, THROAT.z), Vector3(0, 0, s * 22.0))))
	var funnel := MeshInstance3D.new()
	funnel.mesh = ProcMesh.merge(fparts)
	funnel.material_override = yellow
	add_child(funnel)
	var lip: Array = []
	for s: float in [-1.0, 1.0]:
		lip.append(ProcMesh.part(ProcMesh.box(Vector3(1.9, 0.06, 0.08)), ProcMesh.xf(Vector3(0, top_y, THROAT.z + s * 0.7))))
		lip.append(ProcMesh.part(ProcMesh.box(Vector3(0.08, 0.06, 1.48)), ProcMesh.xf(Vector3(s * 0.92, top_y, THROAT.z))))
	var lip_mi := MeshInstance3D.new()
	lip_mi.mesh = ProcMesh.merge(lip)
	lip_mi.material_override = dark
	add_child(lip_mi)
	# Shredder drums: steel cores with hooked teeth, counter-rotating.
	var teeth: Array = []
	teeth.append(ProcMesh.part(ProcMesh.cyl(0.15, 0.15, 1.3, 16), ProcMesh.xf(Vector3.ZERO, Vector3(0, 0, 90))))
	for ring: int in 7:
		var x: float = -0.54 + ring * 0.18
		teeth.append(ProcMesh.part(ProcMesh.cyl(0.19, 0.19, 0.05, 12), ProcMesh.xf(Vector3(x, 0, 0), Vector3(0, 0, 90))))
		for k: int in 5:
			var a: float = TAU * k / 5.0 + ring * 0.7
			teeth.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 0.1, 0.07)), Transform3D(Basis(Vector3.RIGHT, a), Vector3(x, cos(a) * 0.22, sin(a) * 0.22) * Vector3(1, 1, 1)).rotated_local(Vector3.RIGHT, 0.3)))
	var drum_mesh: ArrayMesh = ProcMesh.merge(teeth)
	for zz: float in [THROAT.z - 0.2, THROAT.z + 0.2]:
		var piv := Node3D.new()
		piv.position = Vector3(0, 1.03, zz)
		add_child(piv)
		var dm := MeshInstance3D.new()
		dm.mesh = drum_mesh
		dm.material_override = Mats.metal("steel")
		piv.add_child(dm)
		_drums.append(piv)
	# Dark pit under the drums so the throat reads as deep.
	var pit := MeshInstance3D.new()
	pit.mesh = ProcMesh.box(Vector3(1.3, 0.04, 0.95))
	pit.material_override = Mats.rubber(Color(0.03, 0.03, 0.03))
	pit.position = Vector3(0, 1.005, THROAT.z)
	add_child(pit)
	# Gear motor and bearing blocks on the +X end.
	var motor := MeshInstance3D.new()
	motor.mesh = ProcMesh.cyl(0.22, 0.22, 0.55, 18)
	motor.material_override = yellow
	motor.rotation_degrees = Vector3(0, 0, 90)
	motor.position = Vector3(1.32, 0.62, 0.15)
	add_child(motor)
	var fan := MeshInstance3D.new()
	fan.mesh = ProcMesh.cyl(0.2, 0.2, 0.06, 18)
	fan.material_override = dark
	fan.rotation_degrees = Vector3(0, 0, 90)
	fan.position = Vector3(1.62, 0.62, 0.15)
	add_child(fan)
	var gbox := MeshInstance3D.new()
	gbox.mesh = ProcMesh.rounded_box(Vector3(0.3, 0.5, 0.6), 0.04, 2)
	gbox.material_override = dark
	gbox.position = Vector3(0.98, 1.1, THROAT.z)
	add_child(gbox)
	# Smelter: a squat kiln with a glowing peephole and a tall chimney.
	var kiln := MeshInstance3D.new()
	kiln.mesh = ProcMesh.cyl(0.5, 0.58, 1.5, 24)
	kiln.material_override = kiln_mat
	kiln.position = Vector3(-1.55, 0.89, -0.3)
	add_child(kiln)
	var bands: Array = []
	for y: float in [0.35, 0.9, 1.45]:
		bands.append(ProcMesh.part(ProcMesh.torus(0.5 + (1.6 - y) * 0.05, 0.56 + (1.6 - y) * 0.05, 24, 4), ProcMesh.xf(Vector3(0, y, 0))))
	bands.append(ProcMesh.part(ProcMesh.cyl(0.42, 0.52, 0.18, 24), ProcMesh.xf(Vector3(0, 1.72, 0))))
	bands.append(ProcMesh.part(ProcMesh.cyl(0.13, 0.13, 1.9, 14), ProcMesh.xf(Vector3(0, 2.7, 0))))
	bands.append(ProcMesh.part(ProcMesh.cyl(0.2, 0.15, 0.12, 14), ProcMesh.xf(Vector3(0, 3.62, 0))))
	bands.append(ProcMesh.part(ProcMesh.cyl(0.16, 0.16, 0.06, 14), ProcMesh.xf(Vector3(0, 2.2, 0))))
	var kb := MeshInstance3D.new()
	kb.mesh = ProcMesh.merge(bands)
	kb.material_override = dark
	kb.position = Vector3(-1.55, 0.14, -0.3)
	add_child(kb)
	_glow_mat = Mats.lamp(Color(1.0, 0.45, 0.1), 2.0)
	var window := MeshInstance3D.new()
	window.mesh = ProcMesh.box(Vector3(0.06, 0.24, 0.34))
	window.material_override = _glow_mat
	window.position = Vector3(-2.08, 0.62, -0.3)
	add_child(window)
	var frame := MeshInstance3D.new()
	frame.mesh = ProcMesh.torus(0.17, 0.22, 16, 4)
	frame.material_override = dark
	frame.rotation_degrees = Vector3(0, 0, 90)
	frame.position = Vector3(-2.1, 0.62, -0.3)
	add_child(frame)
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color(1.0, 0.55, 0.2)
	_glow_light.omni_range = 3.0
	_glow_light.light_energy = 0.5
	_glow_light.position = Vector3(-2.45, 0.7, -0.3)
	add_child(_glow_light)
	# Duct from the shredder housing to the kiln.
	var duct := MeshInstance3D.new()
	duct.mesh = ProcMesh.cyl(0.16, 0.16, 0.7, 14)
	duct.material_override = dark
	duct.rotation_degrees = Vector3(0, 0, 90)
	duct.position = Vector3(-1.05, 0.8, -0.3)
	add_child(duct)
	# Ingot tray in front of the kiln.
	var tray := MeshInstance3D.new()
	var tparts: Array = [ProcMesh.part(ProcMesh.box(Vector3(0.5, 0.03, 0.38)), ProcMesh.xf(Vector3(0, 0.015, 0)))]
	for s: float in [-1.0, 1.0]:
		tparts.append(ProcMesh.part(ProcMesh.box(Vector3(0.5, 0.12, 0.03)), ProcMesh.xf(Vector3(0, 0.06, s * 0.19))))
		tparts.append(ProcMesh.part(ProcMesh.box(Vector3(0.03, 0.12, 0.38)), ProcMesh.xf(Vector3(s * 0.25, 0.06, 0))))
	tray.mesh = ProcMesh.merge(tparts)
	tray.material_override = dark
	tray.position = Vector3(-2.4, 0.14, 0.3)
	add_child(tray)
	_ingots = Node3D.new()
	_ingots.position = Vector3(-2.4, 0.15, 0.3)
	add_child(_ingots)
	# Beacon and a control box.
	_beacon = Mats.lamp(Color(1.0, 0.62, 0.12), 0.5)
	var bk := MeshInstance3D.new()
	bk.mesh = ProcMesh.cyl(0.07, 0.09, 0.16, 12)
	bk.material_override = _beacon
	bk.position = Vector3(0.88, 1.08, -0.72)
	add_child(bk)
	var cbox := MeshInstance3D.new()
	cbox.mesh = ProcMesh.rounded_box(Vector3(0.42, 0.55, 0.18), 0.03, 2)
	cbox.material_override = Mats.worn_paint(Color(0.85, 0.85, 0.8), 0.85, 0.3, 64.0, 0.4)
	cbox.position = Vector3(0.62, 0.6, 0.95)
	add_child(cbox)
	for i: int in 3:
		var lb := MeshInstance3D.new()
		lb.mesh = ProcMesh.cyl(0.03, 0.03, 0.03, 10)
		lb.material_override = Mats.lamp([Color(0.2, 1.0, 0.3), Color(1.0, 0.7, 0.1), Color(1.0, 0.2, 0.15)][i], 2.0)
		lb.rotation_degrees = Vector3(90, 0, 0)
		lb.position = Vector3(0.52 + i * 0.1, 0.72, 1.05)
		add_child(lb)
	# Hand-feed intake plate with a hazard border.
	var plate := MeshInstance3D.new()
	plate.mesh = ProcMesh.box(Vector3(PAD_HALF * 2.0, 0.08, PAD_HALF * 2.0))
	plate.material_override = Mats.worn_paint(Color(0.3, 0.31, 0.31), 0.5, 0.6, 65.0, 0.7)
	plate.position = PAD_LOCAL + Vector3(0, 0.04, 0)
	add_child(plate)
	for side: int in 4:
		var b := Basis(Vector3.UP, side * PI * 0.5)
		var st := MeshInstance3D.new()
		st.mesh = ProcMesh.box(Vector3(PAD_HALF * 2.0, 0.012, 0.1))
		st.material_override = yellow
		st.basis = b
		st.position = PAD_LOCAL + Vector3(0, 0.085, 0) + b * Vector3(0, 0, PAD_HALF - 0.05)
		add_child(st)
	var pl := Mats.stencil(tr("HAND FEED"), 64, Color(0.95, 0.85, 0.35, 0.9))
	pl.rotation_degrees = Vector3(-90, 0, 0)
	pl.position = PAD_LOCAL + Vector3(0, 0.09, 0)
	add_child(pl)
	# Collision: housing + kiln.
	var sb := StaticBody3D.new()
	add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.1, 1.05, 1.8)
	cs.shape = bs
	cs.position = Vector3(0, 0.52, 0)
	sb.add_child(cs)
	var cs2 := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.6
	cy.height = 1.7
	cs2.shape = cy
	cs2.position = Vector3(-1.55, 0.85, -0.3)
	sb.add_child(cs2)
