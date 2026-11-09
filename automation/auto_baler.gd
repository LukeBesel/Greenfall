class_name AutoBaler
extends Node3D
## Auto-baler: a vertical hydraulic baling press dropped at the cleaning frontier. Cleaner robots
## drive to the infeed chute at the back and tip their hoppers in; when the chamber holds a bale's
## worth (or has waited a while) the gate drops, twin rams drive the platen down, the bale is
## strapped and pushed out the front onto a roller ramp for the haulers. Local +Z = output side.

const FLOOR_Y: float = 0.34
const PLATEN_TOP: float = 2.05
const CHAMBER := Vector3(1.16, 1.9, 1.0)

var stations: Stations
var store: Dictionary = {}  # junk type -> volume waiting in the chamber
var store_fill: float = 0.0
var phase: String = "idle"  # idle | press | wait_output
var _t: float = 0.0
var _dur: float = 5.0
var _idle_t: float = 0.0
var _bale: JunkCube
var _bale_info: Dictionary = {}
## Junk taken out of the store for the press in progress, until the bale exists (saved back
## into the store so a reload presses it again).
var _press_contents: Dictionary = {}
var _press_take: float = 0.0
## Bale riding the eject ramp (no longer _bale, not yet released): saved as a held bale.
var _ejecting: JunkCube
var _platen: Node3D
var _gate: Node3D
var _mound: MeshInstance3D
var _gauge: Node3D
var _lamp_mat: StandardMaterial3D
var _ramp_rollers: Array[Node3D] = []
var _pressed_fx: bool = false
var _ejected: bool = false
var _clock: float = 0.0


func _ready() -> void:
	add_to_group("baler_station")
	_build()
	YardArt.kitify(self)  # [yard] bevelled kit parts and shaders


func cfg() -> Dictionary:
	return stations.def("auto_baler") if stations else Economy.read_json("res://data/stations.json").get("auto_baler", {})


func bale_cap() -> float:
	return float(cfg().get("bale_capacity", 14.0))


func can_accept(vol: float) -> bool:
	return store_fill + vol <= float(cfg().get("store_max", 70.0))


func idle() -> bool:
	return phase == "idle"


## Where cleaners park to tip their hoppers: behind the infeed chute.
func dump_point() -> Vector3:
	return to_global(Vector3(0, 0, -1.7))


func output_point() -> Vector3:
	return to_global(Vector3(0, 0, 2.3))


func place(pos: Vector3) -> void:
	position = pos
	var to_base: Vector3 = -Vector3(pos.x, 0, pos.z)
	rotation.y = atan2(to_base.x, to_base.z) if to_base.length() > 0.5 else 0.0


## Air-drops the baler onto a spot: it falls on a parachute-less pallet, lands with a thump.
func drop_at(pos: Vector3) -> void:
	place(pos)
	var final: Vector3 = position
	position = final + Vector3(0, 22.0, 0)
	var tw := create_tween()
	tw.tween_property(self, "position", final, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		Audio.play("thud", 0.55, 0.0)
		Audio.play("clunk", 0.6, -3.0)
		Audio.play("hydraulic", 0.7, -8.0)
		EventBus.shake_requested.emit(0.3)
		Vfx.burst("dust", global_position + Vector3(0, 0.2, 0), Color(0.72, 0.66, 0.58, 0.8), 3.0)
		Vfx.ring(global_position + Vector3(0, 0.05, 0), 2.6, Color(1.0, 0.85, 0.5, 0.8), 0.7))
	tw.tween_property(self, "scale", Vector3(1.04, 0.94, 1.04), 0.08)
	tw.tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## A robot tips its hopper in. `from` = where the junk flies from.
func accept(contents: Dictionary, from: Vector3) -> void:
	for k: String in contents:
		var v: float = float(contents[k])
		if v <= 0.0:
			continue
		store[k] = float(store.get(k, 0.0)) + v
		store_fill += v
	_idle_t = 0.0
	if not is_inside_tree():
		return
	var chute: Vector3 = to_global(Vector3(0, 2.25, -0.95))
	var cols: Array[Color] = []
	for k2: String in contents:
		cols.append(Color.html(str(Economy.junk_types.get(k2, {}).get("cube_color", "#888888"))))
	for i: int in 5:
		var fl := MeshInstance3D.new()
		fl.mesh = ProcMesh.rounded_box(Vector3.ONE * randf_range(0.1, 0.18), 0.02, 1)
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[i % cols.size()] if not cols.is_empty() else Color(0.5, 0.48, 0.45)
		m.roughness = 0.8
		fl.material_override = m
		if get_tree().current_scene:
			get_tree().current_scene.add_child(fl)
		else:
			add_child(fl)
		fl.global_position = from
		var start: Vector3 = from + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1))
		var tw := fl.create_tween()
		tw.tween_interval(i * 0.07)
		tw.tween_method(func(t: float) -> void:
			var top: Vector3 = (start + chute) * 0.5 + (global_basis.y if is_inside_tree() else Vector3.UP)  # [orbD] local up
			fl.global_position = start.lerp(top, t).lerp(top.lerp(chute, t), t)
			fl.rotation += Vector3(0.2, 0.15, 0.1)
			, 0.0, 1.0, 0.45)
		tw.tween_callback(fl.queue_free)
	Audio.play("crunch", 1.1, -10.0)
	Audio.play("clink", 0.9, -12.0)
	get_tree().create_timer(0.5, false).timeout.connect(func() -> void:
		if is_instance_valid(self):
			Vfx.burst("dust", to_global(Vector3(0, 1.9, -0.6)), Color(0.65, 0.6, 0.55, 0.5), 0.6))


func _output_blocked() -> bool:
	var n: int = 0
	var op: Vector3 = output_point()
	for node: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = node
		if not c.carried and not c.claimed and c.global_position.distance_to(op) < 2.6:
			n += 1
	return n >= int(cfg().get("output_limit", 6))


func _physics_process(delta: float) -> void:
	_clock += delta
	match phase:
		"idle":
			_idle_t += delta
			var go: bool = store_fill >= bale_cap() or (store_fill > bale_cap() * 0.3 and _idle_t > float(cfg().get("press_time", 5.0)) * 4.0)
			if go:
				if _output_blocked():
					phase = "wait_output"
				else:
					_start_press()
		"wait_output":
			if Engine.get_physics_frames() % 30 == 0 and not _output_blocked():
				_start_press()
		"press":
			_press(delta)
	_update_visuals(delta)


func _start_press() -> void:
	phase = "press"
	_t = 0.0
	_dur = float(cfg().get("press_time", 5.0)) / Stations.baler_mult()
	_pressed_fx = false
	_ejected = false
	# Take one bale's worth, proportionally from what is waiting.
	var cap: float = bale_cap()
	var take: float = minf(cap, store_fill)
	var k: float = take / maxf(store_fill, 0.0001)
	var contents: Dictionary = {}
	for t: String in store:
		var v: float = float(store[t]) * k
		contents[t] = v
		store[t] = float(store[t]) - v
	store_fill -= take
	for t2: String in store.keys():
		if float(store[t2]) <= 0.0001:
			store.erase(t2)
	_press_contents = contents
	_press_take = take
	_bale_info = Economy.evaluate_cube(contents, cap, float(cfg().get("value_mult", 0.85)))
	_bale_info["perfect"] = false
	Audio.play("servo", 0.7, -8.0)


func press_progress() -> float:
	return clampf(_t / maxf(_dur, 0.01), 0.0, 1.0) if phase == "press" else 0.0


func _platen_y(k: float) -> float:
	var size: float = lerpf(0.36, 0.6, clampf(float(_bale_info.get("fill", 1.0)), 0.0, 1.0))
	var low: float = FLOOR_Y + size + 0.02
	if k < 0.12:
		return PLATEN_TOP
	if k < 0.45:
		var u: float = (k - 0.12) / 0.33
		return lerpf(PLATEN_TOP, low, u * u * (3.0 - 2.0 * u))
	if k < 0.62:
		return low - sin((k - 0.45) / 0.17 * PI) * 0.02
	if k < 0.85:
		var u2: float = (k - 0.62) / 0.23
		return lerpf(low, PLATEN_TOP, u2 * u2 * (3.0 - 2.0 * u2))
	return PLATEN_TOP


func _press(delta: float) -> void:
	_t += delta
	var k: float = press_progress()
	if k > 0.12 and k - delta / _dur <= 0.12:
		Audio.play("hydraulic", 1.0, -4.0)
	if k >= 0.45 and not _pressed_fx:
		_pressed_fx = true
		Audio.play("crunch", 0.75, -3.0)
		Audio.play("clunk", 0.6, -5.0)
		Audio.play("steam", 1.1, -8.0)
		Vfx.burst("steam", to_global(Vector3(0.75, 2.75, -0.2)), Color(0.95, 0.95, 0.97, 0.6), 0.6)
		Vfx.burst("dust", to_global(Vector3(0, FLOOR_Y + 0.2, 0.5)), Color(0.65, 0.6, 0.55, 0.6), 0.8)
		EventBus.shake_requested.emit(0.06)
		_make_bale()
	if k >= 0.62 and k - delta / _dur < 0.62:
		Audio.play("hydraulic", 1.25, -7.0)
	if k >= 0.86 and not _ejected:
		_ejected = true
		_eject()
	if k >= 1.0:
		phase = "idle"
		_idle_t = 0.0


func _make_bale() -> void:
	_press_contents = {}
	_press_take = 0.0
	_bale = JunkCube.create(_bale_info["value"], _bale_info)
	_bale.claimed = true
	add_child(_bale)
	_bale.set_carried(true)
	_bale.position = Vector3(0, FLOOR_Y + _bale.size * 0.5, 0)
	_bale.flash()
	GameState.inc_stat("station_bales")
	GameState.inc_stat("cubes_made")


func _eject() -> void:
	if _bale == null or not is_instance_valid(_bale):
		return
	var c: JunkCube = _bale
	_bale = null
	_ejecting = c
	Audio.play("servo", 1.1, -9.0)
	var a := Vector3(0, FLOOR_Y + c.size * 0.5, 0)
	var b := Vector3(0, 0.14 + c.size * 0.5, 1.95)
	var tw := c.create_tween()
	tw.tween_method(func(t: float) -> void:
		c.position = a.lerp(b, t)
		for r: Node3D in _ramp_rollers:
			r.rotation.x = t * 12.0
		, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if _ejecting == c:
			_ejecting = null
		var fwd: Vector3 = global_basis.z
		if stations:
			stations.release_cube(c, c.global_position, fwd * 1.2)
		else:
			c.set_carried(false)
			c.claimed = false
		Audio.play("thud", 1.0, -6.0))


func _update_visuals(_delta: float) -> void:
	var k: float = press_progress()
	var py: float = _platen_y(k) if phase == "press" else PLATEN_TOP
	if _platen:
		_platen.position.y = py
	if _gate:
		var g: float = 0.0
		if phase == "press":
			g = clampf(k / 0.1, 0.0, 1.0) * (1.0 - clampf((k - 0.84) / 0.04, 0.0, 1.0))
		_gate.position.y = lerpf(1.95, 0.0, g)
	if _mound:
		var fill: float = clampf(store_fill / maxf(bale_cap(), 0.1), 0.0, 1.6)
		var h: float = lerpf(0.05, 1.25, clampf(fill, 0.0, 1.0)) + maxf(0.0, fill - 1.0) * 0.4
		if phase == "press" and _bale == null:
			h = minf(h + 0.3, py - FLOOR_Y)
		_mound.visible = store_fill > 0.05 or (phase == "press" and _bale == null)
		_mound.scale = Vector3(0.5, maxf(h, 0.05), 0.42)
	if _gauge:
		_gauge.scale.y = clampf(store_fill / float(cfg().get("store_max", 70.0)), 0.02, 1.0)
	if _lamp_mat:
		var col: Color = Color(0.25, 1.0, 0.35)
		var e: float = 1.5
		if phase == "press":
			col = Color(1.0, 0.65, 0.12)
			e = 2.5 + sin(_clock * 12.0) * 1.5
		elif phase == "wait_output":
			col = Color(1.0, 0.2, 0.12)
			e = 1.5 + sin(_clock * 4.0)
		_lamp_mat.emission = col
		_lamp_mat.albedo_color = col.darkened(0.3)
		_lamp_mat.emission_energy_multiplier = e


func to_dict() -> Dictionary:
	var st: Dictionary = store.duplicate()
	var fill: float = store_fill
	if phase == "press" and not _press_contents.is_empty():
		# Mid-stroke, before the bale exists: put the junk back so nothing is lost on reload.
		for t: String in _press_contents:
			st[t] = float(st.get(t, 0.0)) + float(_press_contents[t])
		fill += _press_take
	return {"pos": [position.x, position.z], "store": st, "fill": fill}


func restore(d: Dictionary) -> void:
	store = (d.get("store", {}) as Dictionary).duplicate()
	store_fill = float(d.get("fill", 0.0))


func held_dicts() -> Array:
	if _bale and is_instance_valid(_bale):
		return [_bale.to_dict()]
	if _ejecting and is_instance_valid(_ejecting) and _ejecting.claimed:
		return [_ejecting.to_dict()]
	return []


# --- Construction -------------------------------------------------------------------

func _build() -> void:
	var blue: ShaderMaterial = Mats.worn_paint(Color(0.2, 0.36, 0.6), 0.8, 0.45, 71.0, 0.55)
	var yellow: ShaderMaterial = Mats.worn_paint(Color(0.95, 0.7, 0.14), 0.75, 0.45, 72.0, 0.5)
	var dark: StandardMaterial3D = Mats.metal("dark_steel")
	var chrome: StandardMaterial3D = Mats.metal("chrome")
	var hw: float = CHAMBER.x * 0.5
	var hd: float = CHAMBER.z * 0.5
	# Skid, chamber floor, columns, crosshead, back wall.
	var frame: Array = []
	frame.append(ProcMesh.part(ProcMesh.box(Vector3(2.3, 0.14, 2.0)), ProcMesh.xf(Vector3(0, 0.07, -0.15))))
	frame.append(ProcMesh.part(ProcMesh.box(Vector3(CHAMBER.x + 0.1, FLOOR_Y - 0.14, CHAMBER.z + 0.1)), ProcMesh.xf(Vector3(0, 0.14 + (FLOOR_Y - 0.14) * 0.5, 0))))
	for s: float in [-1.0, 1.0]:
		frame.append(ProcMesh.part(ProcMesh.box(Vector3(0.24, 2.4, CHAMBER.z + 0.24)), ProcMesh.xf(Vector3(s * (hw + 0.12), 1.34, 0))))
	frame.append(ProcMesh.part(ProcMesh.box(Vector3(CHAMBER.x + 0.6, 0.36, CHAMBER.z + 0.3)), ProcMesh.xf(Vector3(0, 2.6, 0))))
	frame.append(ProcMesh.part(ProcMesh.box(Vector3(CHAMBER.x, 1.4, 0.08)), ProcMesh.xf(Vector3(0, FLOOR_Y + 0.7, -hd - 0.04))))
	var fm := MeshInstance3D.new()
	fm.mesh = ProcMesh.merge(frame)
	fm.material_override = blue
	add_child(fm)
	# Infeed chute at the back: a sloped steel hopper into the top of the chamber.
	var chute: Array = []
	chute.append(ProcMesh.part(ProcMesh.box(Vector3(CHAMBER.x, 0.05, 0.9)), ProcMesh.xf(Vector3(0, 2.0, -0.95), Vector3(-35, 0, 0))))
	for s2: float in [-1.0, 1.0]:
		chute.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 0.45, 0.95)), ProcMesh.xf(Vector3(s2 * hw, 2.15, -0.95), Vector3(-35, 0, 0))))
	var chm := MeshInstance3D.new()
	chm.mesh = ProcMesh.merge(chute)
	chm.material_override = yellow
	add_child(chm)
	# Twin hydraulic cylinders on the crosshead, with hoses down to the power pack.
	var cyl: Array = []
	for s3: float in [-1.0, 1.0]:
		cyl.append(ProcMesh.part(ProcMesh.cyl(0.11, 0.11, 1.15, 16), ProcMesh.xf(Vector3(s3 * 0.33, 3.35, 0))))
		cyl.append(ProcMesh.part(ProcMesh.cyl(0.14, 0.14, 0.08, 16), ProcMesh.xf(Vector3(s3 * 0.33, 2.82, 0))))
		cyl.append(ProcMesh.part(ProcMesh.cyl(0.14, 0.14, 0.08, 16), ProcMesh.xf(Vector3(s3 * 0.33, 3.9, 0))))
	var cm := MeshInstance3D.new()
	cm.mesh = ProcMesh.merge(cyl)
	cm.material_override = dark
	add_child(cm)
	var hose: Array = []
	for s4: float in [-1.0, 1.0]:
		hose.append(ProcMesh.part(ProcMesh.cyl(0.025, 0.025, 2.4, 8), ProcMesh.xf(Vector3(0.95 + s4 * 0.04, 2.0, -0.15 + s4 * 0.12), Vector3(0, 0, -10))))
		hose.append(ProcMesh.part(ProcMesh.cyl(0.025, 0.025, 0.6, 8), ProcMesh.xf(Vector3(0.62, 3.75, s4 * 0.12), Vector3(0, 0, 90))))
	var hm := MeshInstance3D.new()
	hm.mesh = ProcMesh.merge(hose)
	hm.material_override = Mats.rubber()
	add_child(hm)
	# Platen with chrome rods that slide up inside the cylinders.
	_platen = Node3D.new()
	_platen.position.y = PLATEN_TOP
	add_child(_platen)
	var pl := MeshInstance3D.new()
	pl.mesh = ProcMesh.box(Vector3(CHAMBER.x - 0.06, 0.14, CHAMBER.z - 0.06))
	pl.material_override = yellow
	pl.position.y = 0.07
	_platen.add_child(pl)
	var rods: Array = []
	for s5: float in [-1.0, 1.0]:
		rods.append(ProcMesh.part(ProcMesh.cyl(0.05, 0.05, 1.65, 12), ProcMesh.xf(Vector3(s5 * 0.33, 0.95, 0))))
	var rm := MeshInstance3D.new()
	rm.mesh = ProcMesh.merge(rods)
	rm.material_override = chrome
	_platen.add_child(rm)
	# Chamber contents: loose junk waiting to be pressed.
	_mound = MeshInstance3D.new()
	_mound.mesh = FieldView._mound_mesh()
	_mound.material_override = AssetLib.pbr_material("rubble", 1.0, Color(0.62, 0.56, 0.5), true)
	_mound.position = Vector3(0, FLOOR_Y, 0)
	_mound.visible = false
	add_child(_mound)
	# Front safety gate: a barred steel grille that drops while pressing.
	_gate = Node3D.new()
	_gate.position = Vector3(0, 1.95, hd + 0.05)
	add_child(_gate)
	var bars: Array = []
	for i: int in 7:
		bars.append(ProcMesh.part(ProcMesh.box(Vector3(0.035, 1.5, 0.035)), ProcMesh.xf(Vector3(-hw + 0.08 + i * (CHAMBER.x - 0.16) / 6.0, FLOOR_Y + 0.8, 0))))
	for y: float in [FLOOR_Y + 0.08, FLOOR_Y + 0.8, FLOOR_Y + 1.52]:
		bars.append(ProcMesh.part(ProcMesh.box(Vector3(CHAMBER.x, 0.06, 0.05)), ProcMesh.xf(Vector3(0, y, 0))))
	var gm := MeshInstance3D.new()
	gm.mesh = ProcMesh.merge(bars)
	gm.material_override = dark
	_gate.add_child(gm)
	# Output roller ramp.
	var ramp_len: float = 1.8
	var ramp := Node3D.new()
	ramp.position = Vector3(0, (FLOOR_Y + 0.14) * 0.5, hd + ramp_len * 0.5)
	ramp.rotation.x = atan2(FLOOR_Y - 0.14, ramp_len)
	add_child(ramp)
	var rails: Array = []
	for s6: float in [-1.0, 1.0]:
		rails.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, 0.14, ramp_len)), ProcMesh.xf(Vector3(s6 * 0.5, -0.03, 0))))
		rails.append(ProcMesh.part(ProcMesh.box(Vector3(0.06, (FLOOR_Y + 0.14) * 0.5, 0.06)), ProcMesh.xf(Vector3(s6 * 0.5, -0.1, ramp_len * 0.4))))
	var rlm := MeshInstance3D.new()
	rlm.mesh = ProcMesh.merge(rails)
	rlm.material_override = yellow
	ramp.add_child(rlm)
	for i2: int in 9:
		var piv := Node3D.new()
		piv.position = Vector3(0, 0.0, -ramp_len * 0.5 + 0.1 + i2 * (ramp_len - 0.2) / 8.0)
		ramp.add_child(piv)
		var r := MeshInstance3D.new()
		r.mesh = ProcMesh.cyl(0.04, 0.04, 0.95, 12)
		r.material_override = Mats.metal("steel")
		r.rotation_degrees = Vector3(0, 0, 90)
		piv.add_child(r)
		_ramp_rollers.append(piv)
	# Hydraulic power pack on the side: tank, motor, pressure gauge.
	var pack := MeshInstance3D.new()
	pack.mesh = ProcMesh.rounded_box(Vector3(0.5, 0.6, 0.8), 0.04, 2)
	pack.material_override = Mats.worn_paint(Color(0.88, 0.86, 0.8), 0.85, 0.35, 73.0, 0.5)
	pack.position = Vector3(hw + 0.62, 0.44, -0.15)
	add_child(pack)
	var mot := MeshInstance3D.new()
	mot.mesh = ProcMesh.cyl(0.14, 0.14, 0.45, 16)
	mot.material_override = blue
	mot.rotation_degrees = Vector3(90, 0, 0)
	mot.position = Vector3(hw + 0.62, 0.88, -0.15)
	add_child(mot)
	var gauge_face := MeshInstance3D.new()
	gauge_face.mesh = ProcMesh.cyl(0.08, 0.08, 0.03, 16)
	gauge_face.material_override = Mats.worn_paint(Color(0.95, 0.94, 0.9), 0.9, 0.2, 74.0, 0.2)
	gauge_face.rotation_degrees = Vector3(90, 0, 0)
	gauge_face.position = Vector3(hw + 0.62, 0.55, 0.26)
	add_child(gauge_face)
	# Fill gauge on the right column and a status lamp on the crosshead.
	var slot := MeshInstance3D.new()
	slot.mesh = ProcMesh.box(Vector3(0.08, 1.6, 0.02))
	slot.material_override = Mats.rubber(Color(0.03, 0.03, 0.03))
	slot.position = Vector3(hw + 0.12, 1.3, hd + 0.125)
	add_child(slot)
	_gauge = Node3D.new()
	_gauge.position = Vector3(hw + 0.12, 0.52, hd + 0.135)
	add_child(_gauge)
	var gbar := MeshInstance3D.new()
	gbar.mesh = ProcMesh.box(Vector3(0.05, 1.56, 0.02))
	gbar.material_override = Mats.lamp(Color(0.35, 0.9, 1.0), 2.0)
	gbar.position.y = 0.78
	_gauge.add_child(gbar)
	_lamp_mat = Mats.lamp(Color(0.25, 1.0, 0.35), 1.5)
	var lamp := MeshInstance3D.new()
	lamp.mesh = ProcMesh.cyl(0.07, 0.09, 0.16, 12)
	lamp.material_override = _lamp_mat
	lamp.position = Vector3(-hw - 0.15, 2.86, 0.2)
	add_child(lamp)
	var label := Mats.stencil(tr("AUTO-BALER"), 96, Color(0.95, 0.93, 0.85, 0.92))
	label.position = Vector3(0, 2.6, hd + 0.155)
	add_child(label)
	var warn := Mats.stencil(tr("KEEP CLEAR · 40 T"), 44, Color(0.95, 0.8, 0.3, 0.9))
	warn.position = Vector3(-hw - 0.12, 1.4, hd + 0.125)
	warn.rotation_degrees = Vector3(0, 0, 90)
	add_child(warn)
	# Hazard chevrons on the skid front.
	for i3: int in 6:
		var st_pos := Vector3(-1.15 + 0.09 + i3 * 0.19, 0.07, 0.86)
		if absf(st_pos.x) < 0.55:
			continue  # [health] skip before creating: a skipped MeshInstance3D leaked
		var st := MeshInstance3D.new()
		st.mesh = ProcMesh.box(Vector3(0.18, 0.1, 0.012))
		st.material_override = yellow if i3 % 2 == 0 else Mats.worn_paint(Color(0.07, 0.07, 0.07), 0.9, 0.3, 75.0, 0.5)
		st.position = st_pos
		add_child(st)
	# Collision: columns, back, crosshead and the power pack (chamber and ramp stay open).
	var sb := StaticBody3D.new()
	add_child(sb)
	for spec: Array in [[Vector3(-(hw + 0.12), 1.34, 0), Vector3(0.24, 2.4, CHAMBER.z + 0.24)], [Vector3(hw + 0.12, 1.34, 0), Vector3(0.24, 2.4, CHAMBER.z + 0.24)],
			[Vector3(0, 1.2, -hd - 0.2), Vector3(CHAMBER.x, 2.4, 0.5)], [Vector3(hw + 0.62, 0.44, -0.15), Vector3(0.5, 0.88, 0.8)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = spec[1]
		cs.shape = bs
		cs.position = spec[0]
		sb.add_child(cs)
