class_name Outpost
extends Node3D
## One frontier outpost (managed by automation/outposts.gd). Level 0 is a ruin: a collapsed
## weigh-station kiosk, a cracked rusty scale plate, the skip tipped on its side, a broken sign,
## a tarp over a heap and a dead lamp with an amber fault light still blinking. Level 1+ is a
## working weigh station: a Depot scale (bare mode) + skip, a kiosk with a fresh paint stripe,
## a lit lamp, a green status light and a water drum Drips refill at. Level 2 swaps in a Big Skip
## and a wider plate; level 3 adds a recharge pad.
## Local frame: +Z faces the hub. The scale pad sits at PAD; the kiosk at KIOSK.

const PAD := Vector3(0.0, 0.0, 0.9)
const KIOSK := Vector3(3.3, 0.0, -0.6)
const DRUM := Vector3(-3.0, 0.0, -0.8)
const SIGN := Vector3(-3.0, 0.0, 2.5)
const CHARGER := Vector3(3.4, 0.0, 2.7)
const LAMP := Vector3(2.4, 0.0, -2.4)
const DIAL := Vector3(2.25, 0.0, 0.5)

var index: int = 0
var level: int = 0
var world: Node
var scale_depot: Depot
var anchor: Node3D  # interact point (kiosk window)
var busy: bool = false
var _ruin: Node3D
var _fixed: Node3D
var _fault_mat: StandardMaterial3D
var _status_mat: StandardMaterial3D
var _charge_mat: StandardMaterial3D
var _charge_light: OmniLight3D
var _t: float = 0.0
var _ring: Node3D  # floating status ring (working outposts)
var _holo: Node3D  # floating holo sign panel
var _rng := RandomNumberGenerator.new()


func setup(p_index: int, p_level: int, p_world: Node) -> void:
	index = p_index
	level = p_level
	world = p_world
	name = "Outpost%d" % index
	anchor = Node3D.new()
	anchor.name = "Anchor"
	anchor.position = KIOSK + Vector3(0, 0, 1.4)
	add_child(anchor)
	if level <= 0:
		_build_ruin()
	else:
		_build_fixed(level, 0)
		_make_scale()


# --- Queries ---------------------------------------------------------------------------

func working() -> bool:
	return level >= 1 and scale_depot != null and not busy


func pad_world() -> Vector3:
	return to_global(PAD)


func drum_world() -> Vector3:
	return to_global(DRUM + Vector3(0, 0, 1.0))


func charger_world() -> Vector3:
	return to_global(CHARGER)


## A parking spot in front of the outpost for idle robot k.
func idle_world(k: int) -> Vector3:
	@warning_ignore("integer_division")
	return to_global(Vector3(-1.8 + float(k % 4) * 1.2, 0.0, 4.2 + float((k / 4) % 3) * 1.1))


# --- Repair / upgrade ------------------------------------------------------------------

## Rebuilds at `new_level`. With animate: ruin lifts away, scaffold, parts drop in with sparks,
## then the lamp and the green light come on. `done` runs when the sequence ends.
func set_level(new_level: int, animate: bool, done: Callable = Callable()) -> void:
	var from: int = level
	level = new_level
	if not animate:
		if _ruin:
			_ruin.queue_free()
			_ruin = null
		_build_fixed(level, 0)
		_make_scale()
		if done.is_valid():
			done.call()
		return
	busy = true
	if scale_depot:
		scale_depot.set_physics_process(false)
	var t0: float = 0.0
	if _ruin:
		_clear_ruin()
		t0 = 0.7
	_scaffold(KIOSK + Vector3(0, 0, 0), Vector3(2.6, 3.0, 2.5), 2.2 + t0)
	_scaffold(Vector3(0, 0, -2.0), Vector3(3.6, 2.0, 2.4), 2.0 + t0)
	var tw := create_tween()
	tw.tween_interval(t0)
	tw.tween_callback(func() -> void:
		_build_fixed(level, maxi(from + 1, 1))
		_welding(1.8))
	tw.tween_interval(2.6)
	tw.tween_callback(func() -> void:
		_make_scale()
		busy = false
		Audio.play("fanfare", 1.0, -4.0)
		Vfx.burst("confetti", to_global(Vector3(0, 3.0, 0)), Color.WHITE)
		Vfx.ring(pad_world(), 4.5, Color(0.55, 1.0, 0.6, 0.9), 0.9)
		EventBus.shake_requested.emit(0.12)
		if done.is_valid():
			done.call())


func _clear_ruin() -> void:
	var old: Node3D = _ruin
	_ruin = null
	var k: int = 0
	for c: Node in old.get_children():
		if not c is Node3D:
			continue
		var n: Node3D = c
		var tw := n.create_tween()
		tw.tween_interval(0.04 * k)
		tw.tween_property(n, "position", n.position + Vector3(randf_range(-0.6, 0.6), 1.6, randf_range(-0.6, 0.6)), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(n, "scale", Vector3.ONE * 0.02, 0.35)
		k += 1
	for p: Vector3 in [Vector3.ZERO, KIOSK, Vector3(0, 0, -2), SIGN, DRUM]:
		Vfx.burst("dust", to_global(p + Vector3(0, 0.5, 0)), Color(0.62, 0.56, 0.48, 0.7), 1.6)
	Audio.play("clunk", 0.6, -4.0)
	get_tree().create_timer(0.04 * k + 0.5).timeout.connect(old.queue_free)


func _welding(duration: float) -> void:
	var n: int = int(duration / 0.14)
	for i: int in n:
		get_tree().create_timer(0.14 * i).timeout.connect(func() -> void:
			if not is_inside_tree():
				return
			var p: Vector3 = [KIOSK + Vector3(0, 1.6, 1.0), Vector3(0, 1.2, -1.2), LAMP + Vector3(0, 3.0, 0), PAD + Vector3(1.6, 0.2, 0)][i % 4]
			p += Vector3(randf_range(-0.6, 0.6), randf_range(-0.4, 0.4), randf_range(-0.3, 0.3))
			Vfx.burst("sparkle", to_global(p), Color(1.0, 0.75, 0.35), 0.35)
			if i % 3 == 0:
				Audio.play("servo", randf_range(1.6, 2.0), -16.0))


func _scaffold(center: Vector3, size: Vector3, duration: float) -> void:
	var cage := Node3D.new()
	add_child(cage)
	cage.position = center
	var mat: StandardMaterial3D = Mats.metal("steel")
	var plank: ShaderMaterial = EggProps._wood()
	for x: float in [-size.x * 0.5, size.x * 0.5]:
		for z: float in [-size.z * 0.5, size.z * 0.5]:
			cage.add_child(EggProps.mesh(ProcMesh.cyl(0.03, 0.03, size.y, 6), mat, Vector3(x, size.y * 0.5, z)))
	for y: float in [size.y * 0.33, size.y * 0.66, size.y]:
		cage.add_child(EggProps.mesh(ProcMesh.box(Vector3(size.x, 0.04, 0.04)), mat, Vector3(0, y, -size.z * 0.5)))
		cage.add_child(EggProps.mesh(ProcMesh.box(Vector3(size.x, 0.04, 0.04)), mat, Vector3(0, y, size.z * 0.5)))
	cage.add_child(EggProps.mesh(ProcMesh.box(Vector3(size.x, 0.04, 0.3)), plank, Vector3(0, size.y * 0.66 + 0.04, size.z * 0.5 + 0.1)))
	cage.scale = Vector3(1, 0.01, 1)
	var tw := create_tween()
	tw.tween_property(cage, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(duration)
	tw.tween_property(cage, "scale", Vector3(1, 0.01, 1), 0.3)
	tw.tween_callback(cage.queue_free)


func _make_scale() -> void:
	var def: Dictionary = Outposts.level_def(level)
	if scale_depot == null:
		scale_depot = Depot.new()
		scale_depot.bare = true
		scale_depot.world = world
		scale_depot.name = "Scale"
		scale_depot.position = PAD
		scale_depot.mouth_local = _skip_pos(level) + Vector3(0, _skip_size(level).y + 0.4, 0) - PAD
		add_child(scale_depot)
		scale_depot.add_to_group("outpost_depot")
		if world and world.get("patch") != null:
			scale_depot.patch = world.patch
	scale_depot.set_physics_process(true)
	scale_depot.pad_radius = float(def.get("pad_radius", 1.6))
	scale_depot.value_bonus = float(def.get("sell_bonus", 0.0))
	scale_depot._chute_mouth = _skip_pos(level) + Vector3(0, _skip_size(level).y + 0.4, 0) - PAD
	var needle: Node = _fixed.get_node_or_null("Needle") if _fixed else null
	scale_depot._needle = needle as MeshInstance3D


func _process(delta: float) -> void:
	_t += delta
	if _fault_mat:
		# The last thing still powered: a dying amber fault light, blinking unevenly.
		var on: bool = fmod(_t, 2.3) < 0.18 or (fmod(_t, 2.3) > 0.4 and fmod(_t, 2.3) < 0.5)
		_fault_mat.emission_energy_multiplier = 3.0 if on else 0.15
	if _status_mat:
		_status_mat.emission_energy_multiplier = 2.4 + 0.6 * sin(_t * 2.0)
	if is_instance_valid(_ring) and not busy:
		_ring.rotation.y = _t * 0.9
		_ring.position.y = 3.35 + 0.08 * sin(_t * 1.7)
		var rm: Node3D = _ring.get_node_or_null("Ring")
		if rm:
			rm.rotation.z = sin(_t * 0.7) * 0.25
	if is_instance_valid(_holo):
		_holo.position.y = 1.95 + 0.04 * sin(_t * 1.3)
		_holo.visible = fmod(_t * 7.3, 11.0) > 0.25  # rare flicker
	if _charge_mat:
		var k: float = 0.5 + 0.5 * sin(_t * 3.0)
		_charge_mat.emission_energy_multiplier = 1.4 + 2.2 * k
		if _charge_light:
			_charge_light.light_energy = 0.6 + 0.9 * k


# --- Shared pieces ---------------------------------------------------------------------

static func _skip_size(lv: int) -> Vector3:
	return Vector3(3.1, 1.5, 1.9) if lv >= 2 else Vector3(2.4, 1.15, 1.5)


static func _skip_pos(lv: int) -> Vector3:
	return Vector3(0, 0, -2.45) if lv >= 2 else Vector3(0, 0, -1.95)


## Open-top steel skip with tapered ends and ribs (local origin at the floor centre).
static func skip_mesh(size: Vector3) -> ArrayMesh:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var parts: Array = []
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w * 0.8, 0.08, d)), ProcMesh.xf(Vector3(0, 0.05, 0))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w, h, 0.06)), ProcMesh.xf(Vector3(0, h * 0.5, d * 0.5))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w, h, 0.06)), ProcMesh.xf(Vector3(0, h * 0.5, -d * 0.5))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.06, h * 1.05, d)), ProcMesh.xf(Vector3(w * 0.45, h * 0.5, 0), Vector3(0, 0, -12))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.06, h * 1.05, d)), ProcMesh.xf(Vector3(-w * 0.45, h * 0.5, 0), Vector3(0, 0, 12))))
	for x: float in [-w * 0.33, 0.0, w * 0.33]:
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.08, h, 0.1)), ProcMesh.xf(Vector3(x, h * 0.5, d * 0.5 + 0.05))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.08, h, 0.1)), ProcMesh.xf(Vector3(x, h * 0.5, -d * 0.5 - 0.05))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w * 1.02, 0.07, 0.1)), ProcMesh.xf(Vector3(0, h, d * 0.5 + 0.03))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w * 1.02, 0.07, 0.1)), ProcMesh.xf(Vector3(0, h, -d * 0.5 - 0.03))))
	for s: float in [-1.0, 1.0]:
		parts.append(ProcMesh.part(ProcMesh.cyl(0.07, 0.07, 0.12, 8), ProcMesh.xf(Vector3(s * w * 0.47, h * 0.8, 0), Vector3(0, 0, 90))))
	return ProcMesh.merge(parts)


## A tarpaulin thrown over a heap: a lumpy draped grid drooping to the ground at the edges.
static func tarp_mesh(size: Vector2, h: float, seed_v: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var n: int = 10
	var pts: Array = []
	for j: int in n + 1:
		var row: Array = []
		for i: int in n + 1:
			var u: float = float(i) / n * 2.0 - 1.0
			var v: float = float(j) / n * 2.0 - 1.0
			var dd: float = clampf(maxf(absf(u), absf(v)) * 0.6 + Vector2(u, v).length() * 0.5, 0.0, 1.0)
			var y: float = h * pow(1.0 - dd * dd, 0.8) * r.randf_range(0.75, 1.05) + 0.02
			row.append(Vector3(u * size.x * 0.5, y, v * size.y * 0.5))
		pts.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j: int in n:
		for i: int in n:
			var shade: float = r.randf_range(0.82, 1.0)
			st.set_color(Color(shade, shade, shade))
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var c: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			for vtx: Vector3 in [a, b, c, a, c, d]:
				st.set_uv(Vector2(vtx.x, vtx.z) * 0.8)
				st.add_vertex(vtx)
	st.generate_normals()
	return st.commit()


static func _tarp_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.88
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = AssetLib.tex("dirty_concrete", "diff")
	m.uv1_scale = Vector3.ONE * 0.6
	return m


func _model(parent: Node3D, id: String, pos: Vector3, yaw: float, h: float, tilt := Vector3.ZERO) -> MeshInstance3D:
	if not AssetLib.has_model(id):
		return null
	var mi: MeshInstance3D = EggProps.model(id, pos, yaw, EggProps._fit(id, h))
	mi.rotation_degrees += tilt
	parent.add_child(mi)
	return mi


func _concrete(tint: Color) -> StandardMaterial3D:
	return AssetLib.pbr_material("concrete_floor_worn_001", 0.5, tint, true)


# --- Ruin ------------------------------------------------------------------------------

func _build_ruin() -> void:
	_ruin = Node3D.new()
	_ruin.name = "Ruin"
	add_child(_ruin)
	_rng.seed = 7700 + index * 131
	var rust_plate: ShaderMaterial = Mats.worn_paint(Color(0.3, 0.31, 0.3), 0.3, 0.95, 60.0 + index, 0.85)
	var faded_yellow: ShaderMaterial = Mats.worn_paint(Color(0.78, 0.62, 0.2), 0.35, 0.8, 61.0 + index, 0.8)
	# Scale plate: cracked in two, one half sunk and tipped.
	var half: float = 1.5
	_ruin.add_child(EggProps.mesh(ProcMesh.box(Vector3(half * 2.0, 0.08, half)), rust_plate, PAD + Vector3(0, 0.03, -half * 0.5), Vector3(1.5, 0, -1.0)))
	_ruin.add_child(EggProps.mesh(ProcMesh.box(Vector3(half * 2.0, 0.08, half * 0.95)), rust_plate, PAD + Vector3(0.1, 0.12, half * 0.52), Vector3(-7.0, 4.0, 3.0)))
	_ruin.add_child(EggProps.mesh(ProcMesh.box(Vector3(half * 2.0, 0.012, 0.12)), faded_yellow, PAD + Vector3(0, 0.08, -half + 0.08), Vector3(1.5, 0, -1.0)))
	_ruin.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.12, 0.012, half * 0.95)), faded_yellow, PAD + Vector3(-half + 0.1, 0.11, -half * 0.5), Vector3(1.5, 0, -1.0)))
	# The skip, tipped on its side and half spilled.
	var skip_mat: ShaderMaterial = Mats.worn_paint(Color(0.22, 0.38, 0.28), 0.35, 0.9, 62.0 + index, 0.8)
	var sk: Vector3 = _skip_size(1)
	_ruin.add_child(EggProps.mesh(skip_mesh(sk), skip_mat, _skip_pos(1) + Vector3(-0.2, sk.z * 0.5, -0.2), Vector3(-84, 14, 0)))
	var spill := MeshInstance3D.new()
	spill.mesh = FieldView._mound_mesh()
	spill.material_override = AssetLib.pbr_material("rubble", 1.0, Color(0.55, 0.5, 0.45), true)
	spill.scale = Vector3(1.2, 0.35, 0.9)
	spill.position = _skip_pos(1) + Vector3(0.2, 0.0, 1.2)
	_ruin.add_child(spill)
	# Collapsed kiosk: footing, a leaning back wall, a fallen side, the roof sheet slid off.
	var wall_mat: ShaderMaterial = Mats.worn_paint(Color(0.82, 0.8, 0.74), 0.35, 0.85, 63.0 + index, 0.9)
	var roof_mat: StandardMaterial3D = AssetLib.pbr_material("corrugated_iron", 0.6, Color(0.62, 0.48, 0.38), true)
	_ruin.add_child(EggProps.mesh(ProcMesh.box(Vector3(2.4, 0.14, 2.2)), _concrete(Color(0.7, 0.68, 0.64)), KIOSK + Vector3(0, 0.07, 0)))
	_ruin.add_child(EggProps.mesh(ProcMesh.box(Vector3(2.0, 2.1, 0.08)), wall_mat, KIOSK + Vector3(0, 1.0, -0.95), Vector3(-11, 0, 3)))
	_ruin.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.08, 1.9, 1.9)), wall_mat, KIOSK + Vector3(-1.05, 0.9, -0.05), Vector3(0, 0, 21)))
	_ruin.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.9, 0.08, 2.0)), wall_mat, KIOSK + Vector3(1.9, 0.18, 0.1), Vector3(0, 6, -4)))
	_ruin.add_child(EggProps.mesh(ProcMesh.box(Vector3(2.5, 0.05, 2.3)), roof_mat, KIOSK + Vector3(0.45, 0.95, 0.35), Vector3(14, 8, -30)))
	# Broken window frame lying in front, a few glass shards.
	var frame_mat: StandardMaterial3D = Mats.metal("dark_steel")
	var fw := Node3D.new()
	fw.position = KIOSK + Vector3(-0.2, 0.06, 1.35)
	fw.rotation_degrees = Vector3(0, 23, 0)
	_ruin.add_child(fw)
	for spec: Array in [[Vector3(0, 0, -0.5), Vector3(1.2, 0.05, 0.05)], [Vector3(0, 0, 0.5), Vector3(1.2, 0.05, 0.05)], [Vector3(-0.6, 0, 0), Vector3(0.05, 0.05, 1.0)]]:
		fw.add_child(EggProps.mesh(ProcMesh.box(spec[1]), frame_mat, spec[0]))
	for k: int in 5:
		var shard := EggProps.mesh(ProcMesh.box(Vector3(_rng.randf_range(0.1, 0.25), 0.01, _rng.randf_range(0.08, 0.2))), Mats.glass(Color(0.3, 0.38, 0.4, 0.6), 0.1),
			KIOSK + Vector3(_rng.randf_range(-1.0, 1.0), 0.03, _rng.randf_range(0.9, 1.8)), Vector3(0, _rng.randf_range(0, 360), 0))
		_ruin.add_child(shard)
	# Fault light: the only thing still powered.
	_fault_mat = Mats.lamp(Color(1.0, 0.55, 0.12), 3.0)
	var fl := EggProps.mesh(ProcMesh.sphere(0.07, 10, 5), _fault_mat, KIOSK + Vector3(0.55, 1.72, -0.82))
	_ruin.add_child(fl)
	_ruin.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.2, 0.12, 0.08)), frame_mat, KIOSK + Vector3(0.55, 1.62, -0.86), Vector3(-11, 0, 3)))
	# Broken sign: one post snapped, the board hanging off the other.
	var post_mat: ShaderMaterial = Mats.worn_paint(Color(0.3, 0.45, 0.48), 0.3, 0.9, 64.0 + index, 0.8)
	_ruin.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.05, 2.3, 8), post_mat, SIGN + Vector3(-0.8, 1.15, 0), Vector3(0, 0, 4)))
	_ruin.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.05, 0.9, 8), post_mat, SIGN + Vector3(0.8, 0.45, 0)))
	_ruin.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.05, 1.3, 8), post_mat, SIGN + Vector3(1.35, 0.07, 0.4), Vector3(84, 30, 0)))
	var board := Node3D.new()
	board.position = SIGN + Vector3(-0.78, 2.1, 0.06)
	board.rotation_degrees = Vector3(0, 0, -38)
	_ruin.add_child(board)
	var board_mat: ShaderMaterial = Mats.worn_paint(Color(0.18, 0.42, 0.45), 0.4, 0.85, 65.0 + index, 0.8)
	board.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.9, 0.6, 0.05)), board_mat, Vector3(0.95, -0.3, 0)))
	board.add_child(EggProps.label("W E I G H   S T A T I O N", 30, Color(0.85, 0.82, 0.72, 0.55), Vector3(0.95, -0.24, 0.03)))
	board.add_child(EggProps.label("O U T P O S T  %d" % (index + 1), 22, Color(0.85, 0.82, 0.72, 0.45), Vector3(0.95, -0.44, 0.03)))
	# Dead lamp post, bent over.
	var lamp_n := Node3D.new()
	lamp_n.position = LAMP
	lamp_n.rotation_degrees = Vector3(18, 0, -24)
	_ruin.add_child(lamp_n)
	lamp_n.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.08, 3.6, 10), Mats.worn_paint(Color(0.3, 0.32, 0.3), 0.3, 0.9, 66.0, 0.7), Vector3(0, 1.8, 0)))
	lamp_n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.5, 0.14, 0.26)), frame_mat, Vector3(0.25, 3.55, 0)))
	lamp_n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.36, 0.02, 0.18)), Mats.glass(Color(0.1, 0.1, 0.1, 0.9), 0.3), Vector3(0.25, 3.47, 0)))
	# Water drum on its side, the dial post snapped off.
	_ruin.add_child(EggProps.mesh(ProcMesh.cyl(0.3, 0.3, 0.9, 16), Mats.worn_paint(Color(0.2, 0.35, 0.55), 0.3, 0.9, 67.0 + index, 0.8), DRUM + Vector3(0.3, 0.3, 0.2), Vector3(90, 35, 0)))
	_ruin.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.06, 0.55, 10), Mats.worn_paint(Color(0.85, 0.82, 0.75), 0.3, 0.8, 68.0), DIAL + Vector3(0, 0.27, 0)))
	_ruin.add_child(EggProps.mesh(ProcMesh.cyl(0.22, 0.22, 0.08, 24), Mats.worn_paint(Color(0.85, 0.82, 0.75), 0.4, 0.8, 69.0), DIAL + Vector3(0.5, 0.06, 0.4), Vector3(4, 0, 6)))
	# Tarp over a heap, plus what everyone dumped here since.
	var tarp := MeshInstance3D.new()
	tarp.mesh = tarp_mesh(Vector2(2.2, 1.8), 0.85, 900 + index)
	tarp.material_override = _tarp_mat(Color(0.2, 0.36, 0.6))
	tarp.position = Vector3(-2.2, 0, -2.4)
	tarp.rotation.y = 0.4
	_ruin.add_child(tarp)
	_model(_ruin, "old_tyre", KIOSK + Vector3(-1.6, 0.0, 1.6), 30.0, 0.25, Vector3(0, 0, 0))
	_model(_ruin, "old_tyre", KIOSK + Vector3(-1.5, 0.22, 1.55), 75.0, 0.25, Vector3(6, 0, 4))
	_model(_ruin, "Barrel_01", Vector3(-1.6, 0.3, 2.6), 0.0, 0.9, Vector3(90, 40, 0))
	_model(_ruin, "trashbag", PAD + Vector3(-0.8, 0.12, 0.3), 20.0, 0.55)
	_model(_ruin, "trashbag", PAD + Vector3(0.6, 0.15, -0.4), 140.0, 0.5)
	_model(_ruin, "cardboard_box_01", PAD + Vector3(0.2, 0.1, 0.9), 33.0, 0.4, Vector3(0, 0, 12))
	_model(_ruin, "plastic_crate_01", KIOSK + Vector3(1.4, 0.0, 1.6), 64.0, 0.35, Vector3(0, 0, 0))
	_model(_ruin, "rusted_wheel_rim_01", Vector3(1.2, 0.05, -1.0), 10.0, 0.12)


# --- Working outpost -------------------------------------------------------------------

## Adds a part to the fixed build; parts tagged with `drop_lv` fly in when that level is built.
func _part(n: Node3D, lv: int) -> Node3D:
	n.set_meta("lv", lv)
	_fixed.add_child(n)
	return n


## Glossy shell paint (the Mk III/IV robot look).
static func _gloss(c: Color, rough: float = 0.18, metal: float = 0.05, coat: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if coat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.08
	return m


## Unshaded additive glow (holograms, light sheets).
static func _holo_mat(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c, alpha)
	m.no_depth_test = false
	return m


## A glowing strip between two local points (Tron-style light line).
static func _strip(a: Vector3, b: Vector3, w: float, mat: Material) -> MeshInstance3D:
	var d: Vector3 = b - a
	var mi := MeshInstance3D.new()
	mi.mesh = ProcMesh.box(Vector3(w, w, d.length()))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT), (a + b) * 0.5)
	return mi


## The restored outpost: clean and futuristic. Glossy white shells, dark glass, cyan light lines,
## orange accents, an energy-glow scale plate, a floating holo sign and a floating status ring.
func _build_fixed(lv: int, drop_lv: int) -> void:
	if _fixed:
		_fixed.queue_free()
		if scale_depot:
			scale_depot._needle = null
	_fixed = Node3D.new()
	_fixed.name = "Fixed"
	add_child(_fixed)
	var big: bool = lv >= 2
	var lv_scale: int = 2 if big else 1
	var white: StandardMaterial3D = _gloss(Color(0.93, 0.94, 0.95))
	var dark: StandardMaterial3D = _gloss(Color(0.05, 0.06, 0.08), 0.12, 0.45, 1.0)
	var glass: StandardMaterial3D = Mats.glass(Color(0.03, 0.07, 0.11, 0.82), 0.03)
	var cyan: StandardMaterial3D = Mats.lamp(Color(0.3, 0.9, 1.0), 3.2)
	var orange: StandardMaterial3D = _gloss(Color(1.0, 0.46, 0.1), 0.25, 0.0, 0.7)
	var orange_glow: StandardMaterial3D = Mats.lamp(Color(1.0, 0.5, 0.15), 2.5)
	# Energy-glow scale plate: dark glass deck, cyan edge lines and a glowing grid.
	var r: float = float(Outposts.level_def(lv).get("pad_radius", 1.6))
	var plate_n := Node3D.new()
	plate_n.position = PAD
	_part(plate_n, lv_scale)
	var hs: float = r * 0.95
	plate_n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(hs * 2.0 + 0.2, 0.12, hs * 2.0 + 0.2), 0.05, 2), white, Vector3(0, 0.06, 0)))
	plate_n.add_child(EggProps.mesh(ProcMesh.box(Vector3(hs * 2.0, 0.02, hs * 2.0)), dark, Vector3(0, 0.125, 0)))
	var y: float = 0.14
	for k: int in 4:
		var a: Vector3 = Basis(Vector3.UP, k * PI * 0.5) * Vector3(-hs, y, hs)
		var b: Vector3 = Basis(Vector3.UP, k * PI * 0.5) * Vector3(hs, y, hs)
		plate_n.add_child(_strip(a, b, 0.05, cyan))
	var grid: StandardMaterial3D = Mats.lamp(Color(0.25, 0.8, 1.0), 1.2)
	for t: float in [-0.5, 0.0, 0.5]:
		plate_n.add_child(_strip(Vector3(-hs, y - 0.005, t * hs), Vector3(hs, y - 0.005, t * hs), 0.018, grid))
		plate_n.add_child(_strip(Vector3(t * hs, y - 0.005, -hs), Vector3(t * hs, y - 0.005, hs), 0.018, grid))
	plate_n.add_child(EggProps.mesh(ProcMesh.torus(r * 0.42, r * 0.47, 40, 4), cyan, Vector3(0, y, 0)))
	plate_n.add_child(EggProps.mesh(ProcMesh.box(Vector3(hs * 2.0, 0.6, hs * 2.0)), _holo_mat(Color(0.3, 0.85, 1.0), 0.05), Vector3(0, y + 0.3, 0)))
	plate_n.add_child(EggProps.label(tr("SCALE"), 40, Color(0.6, 0.95, 1.0), Vector3(0, y + 0.01, r * 0.62), Vector3(-90, 0, 0), true))
	# Skip: glossy white hull, orange band, cyan rim lines, glowing number.
	var sk: Vector3 = _skip_size(lv)
	var skip_n := Node3D.new()
	skip_n.position = _skip_pos(lv)
	_part(skip_n, lv_scale)
	skip_n.add_child(EggProps.mesh(skip_mesh(sk), white))
	skip_n.add_child(EggProps.mesh(ProcMesh.box(Vector3(sk.x * 0.98, 0.16, 0.02)), orange, Vector3(0, sk.y * 0.25, sk.z * 0.5 + 0.035)))
	skip_n.add_child(_strip(Vector3(-sk.x * 0.5, sk.y + 0.05, sk.z * 0.5 + 0.08), Vector3(sk.x * 0.5, sk.y + 0.05, sk.z * 0.5 + 0.08), 0.045, cyan))
	skip_n.add_child(_strip(Vector3(-sk.x * 0.5, sk.y + 0.05, -sk.z * 0.5 - 0.08), Vector3(sk.x * 0.5, sk.y + 0.05, -sk.z * 0.5 - 0.08), 0.045, cyan))
	skip_n.add_child(EggProps.mesh(ProcMesh.box(Vector3(sk.x * 0.7, 0.34, 0.02)), glass, Vector3(0, sk.y * 0.58, sk.z * 0.5 + 0.11)))
	skip_n.add_child(EggProps.label(tr("OUTPOST %d%s") % [index + 1, tr("  ·  BIG SKIP") if big else ""], 34, Color(0.55, 0.95, 1.0), Vector3(0, sk.y * 0.58, sk.z * 0.5 + 0.125), Vector3.ZERO, true))
	var fill := MeshInstance3D.new()
	fill.mesh = FieldView._mound_mesh()
	fill.material_override = AssetLib.pbr_material("rubble", 1.0, Color(0.6, 0.55, 0.5), true)
	fill.scale = Vector3(sk.x * 0.42, 0.45, sk.z * 0.42)
	fill.position = Vector3(0, sk.y * 0.5, 0)
	skip_n.add_child(fill)
	_collider(skip_n, Vector3(sk.x, sk.y + 0.2, sk.z), Vector3(0, (sk.y + 0.2) * 0.5, 0))
	# Kiosk: rounded white shell, wraparound dark glass, cyan base + eave lines, a hovering roof.
	var kiosk := Node3D.new()
	kiosk.position = KIOSK
	_part(kiosk, 1)
	kiosk.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(2.4, 0.14, 2.2), 0.05, 2), dark, Vector3(0, 0.07, 0)))
	kiosk.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(2.0, 2.1, 1.9), 0.18, 3), white, Vector3(0, 1.19, 0)))
	kiosk.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(2.06, 0.75, 1.96), 0.12, 3), glass, Vector3(0, 1.5, 0)))
	for spec: Array in [[0.18, 2.12], [2.27, 2.04]]:
		var yy: float = spec[0]
		var w: float = spec[1]
		kiosk.add_child(_strip(Vector3(-w * 0.5, yy, 0.99), Vector3(w * 0.5, yy, 0.99), 0.04, cyan))
		kiosk.add_child(_strip(Vector3(-w * 0.5, yy, -0.99), Vector3(w * 0.5, yy, -0.99), 0.04, cyan))
		kiosk.add_child(_strip(Vector3(w * 0.5 - 0.01, yy, -0.99), Vector3(w * 0.5 - 0.01, yy, 0.99), 0.04, cyan))
		kiosk.add_child(_strip(Vector3(-w * 0.5 + 0.01, yy, -0.99), Vector3(-w * 0.5 + 0.01, yy, 0.99), 0.04, cyan))
	kiosk.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.1, 2.0, 0.04)), orange, Vector3(-0.85, 1.12, 0.97)))
	kiosk.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.04, 1.75, 0.8)), glass, Vector3(1.01, 0.98, -0.25)))
	kiosk.add_child(_strip(Vector3(1.03, 0.12, -0.65), Vector3(1.03, 1.86, -0.65), 0.025, cyan))
	kiosk.add_child(_strip(Vector3(1.03, 0.12, 0.15), Vector3(1.03, 1.86, 0.15), 0.025, cyan))
	kiosk.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.4, 0.05, 0.32)), white, Vector3(0, 1.08, 1.1)))
	# Hovering roof slab with a cyan underglow line (no visible supports).
	kiosk.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(2.6, 0.12, 2.5), 0.05, 2), white, Vector3(0, 2.62, 0.08)))
	kiosk.add_child(EggProps.mesh(ProcMesh.box(Vector3(2.3, 0.02, 2.2)), Mats.lamp(Color(0.3, 0.9, 1.0), 1.6), Vector3(0, 2.55, 0.08)))
	kiosk.add_child(EggProps.glow(Color(0.35, 0.85, 1.0), 0.9, 3.5, Vector3(0, 2.3, 1.2)))
	kiosk.add_child(EggProps.glow(Color(0.85, 0.95, 1.0), 0.8, 3.0, Vector3(0, 1.6, 0.3)))
	# Green status light on the front.
	_status_mat = Mats.lamp(Color(0.25, 1.0, 0.45), 2.6)
	kiosk.add_child(EggProps.mesh(ProcMesh.cyl(0.11, 0.11, 0.04, 20), dark, Vector3(0.72, 2.0, 0.98), Vector3(90, 0, 0)))
	kiosk.add_child(EggProps.mesh(ProcMesh.sphere(0.075, 12, 6), _status_mat, Vector3(0.72, 2.0, 1.0)))
	kiosk.add_child(EggProps.glow(Color(0.35, 1.0, 0.5), 0.6, 2.4, Vector3(0.72, 2.0, 1.2)))
	_collider(kiosk, Vector3(2.1, 2.4, 2.0), Vector3(0, 1.2, 0))
	# Floating status ring over the kiosk (spins and bobs; see _process).
	_ring = Node3D.new()
	_ring.position = KIOSK + Vector3(0, 3.35, 0.1)
	_ring.set_meta("lv", 1)
	_fixed.add_child(_ring)
	var ring_mat: StandardMaterial3D = Mats.lamp(Color(0.35, 1.0, 0.65), 3.0)
	var ring_mi := EggProps.mesh(ProcMesh.torus(0.42, 0.5, 40, 6), ring_mat, Vector3.ZERO, Vector3(90, 0, 0))
	ring_mi.name = "Ring"
	_ring.add_child(ring_mi)
	_ring.add_child(EggProps.mesh(ProcMesh.torus(0.26, 0.29, 32, 4), cyan, Vector3.ZERO, Vector3(0, 0, 0)))
	_ring.add_child(EggProps.mesh(ProcMesh.sphere(0.09, 12, 6), ring_mat))
	_ring.add_child(EggProps.glow(Color(0.4, 1.0, 0.7), 0.8, 3.0, Vector3.ZERO))
	# Dial: dark glass disc with a cyan bezel; the Depot swings the orange needle.
	var dial_n := Node3D.new()
	dial_n.position = DIAL
	_part(dial_n, 1)
	dial_n.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.07, 1.4, 12), white, Vector3(0, 0.7, 0)))
	dial_n.add_child(EggProps.mesh(ProcMesh.cyl(0.24, 0.24, 0.06, 28), dark, Vector3(-0.03, 1.45, 0), Vector3(0, 0, 90)))
	dial_n.add_child(EggProps.mesh(ProcMesh.torus(0.22, 0.25, 28, 4), cyan, Vector3(-0.07, 1.45, 0), Vector3(0, 0, 90)))
	dial_n.add_child(EggProps.label("kg", 24, Color(0.55, 0.95, 1.0), Vector3(-0.07, 1.36, 0), Vector3(0, -90, 0), true))
	var needle := MeshInstance3D.new()
	needle.name = "Needle"
	needle.mesh = ProcMesh.box(Vector3(0.015, 0.19, 0.01))
	needle.material_override = orange_glow
	needle.rotation_degrees = Vector3(0, -90, 0)
	needle.position = DIAL + Vector3(-0.08, 1.45, 0)
	needle.set_meta("lv", 1)
	_fixed.add_child(needle)
	# Lamp: slim white mast, curved arm, cyan light bar over the plate.
	var lamp_n := Node3D.new()
	lamp_n.position = LAMP
	_part(lamp_n, 1)
	lamp_n.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.09, 4.0, 14), white, Vector3(0, 2.0, 0)))
	lamp_n.add_child(_strip(Vector3(0, 0.3, 0.08), Vector3(0, 3.7, 0.06), 0.02, cyan))
	var arm_dir: Vector3 = ((PAD - LAMP) * Vector3(1, 0, 1)).normalized()
	var head_p: Vector3 = arm_dir * 1.6 + Vector3(0, 3.9, 0)
	lamp_n.add_child(EggProps.strut(Vector3(0, 3.98, 0), head_p + Vector3(0, 0.05, 0), 0.04, white))
	var head := EggProps.mesh(ProcMesh.rounded_box(Vector3(0.7, 0.1, 0.22), 0.04, 2), white, head_p)
	head.rotation.y = atan2(arm_dir.x, arm_dir.z) + PI * 0.5
	lamp_n.add_child(head)
	var bar := EggProps.mesh(ProcMesh.box(Vector3(0.6, 0.02, 0.12)), Mats.lamp(Color(0.8, 0.95, 1.0), 5.0), head_p - Vector3(0, 0.06, 0))
	bar.rotation.y = head.rotation.y
	lamp_n.add_child(bar)
	var sl := SpotLight3D.new()
	sl.light_color = Color(0.85, 0.95, 1.0)
	sl.light_energy = 3.0
	sl.spot_range = 9.0
	sl.spot_angle = 52.0
	sl.shadow_enabled = false
	sl.position = head_p - Vector3(0, 0.12, 0)
	sl.rotation_degrees = Vector3(-90, 0, 0)
	lamp_n.add_child(sl)
	# Water: a glossy capsule tank with a glowing level strip (Drips refill here).
	var drum_n := Node3D.new()
	drum_n.position = DRUM
	_part(drum_n, 1)
	drum_n.add_child(EggProps.mesh(ProcMesh.cyl(0.42, 0.46, 0.16, 24), dark, Vector3(0, 0.08, 0)))
	drum_n.add_child(EggProps.mesh(ProcMesh.capsule(0.36, 1.35), white, Vector3(0, 0.84, 0)))
	drum_n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.08, 0.7, 0.03)), Mats.lamp(Color(0.35, 0.75, 1.0), 2.5), Vector3(0, 0.85, 0.36)))
	drum_n.add_child(EggProps.mesh(ProcMesh.torus(0.36, 0.385, 28, 4), orange, Vector3(0, 0.45, 0)))
	drum_n.add_child(EggProps.label("H2O", 30, Color(0.55, 0.85, 1.0), Vector3(0, 1.35, 0.37), Vector3.ZERO, true))
	# Holo sign: a slim emitter post projecting a floating cyan panel.
	var sign_n := Node3D.new()
	sign_n.position = SIGN
	_part(sign_n, 1)
	sign_n.add_child(EggProps.mesh(ProcMesh.cyl(0.14, 0.2, 0.9, 16), white, Vector3(0, 0.45, 0)))
	sign_n.add_child(EggProps.mesh(ProcMesh.torus(0.13, 0.17, 24, 4), cyan, Vector3(0, 0.88, 0)))
	sign_n.add_child(EggProps.mesh(ProcMesh.cyl(0.02, 0.16, 0.7, 16), _holo_mat(Color(0.3, 0.85, 1.0), 0.12), Vector3(0, 1.25, 0)))
	_holo = Node3D.new()
	_holo.position = Vector3(0, 1.95, 0)
	sign_n.add_child(_holo)
	_holo.add_child(EggProps.mesh(ProcMesh.box(Vector3(2.1, 0.72, 0.01)), _holo_mat(Color(0.25, 0.75, 1.0), 0.16)))
	for yy: float in [-0.36, 0.36]:
		_holo.add_child(_strip(Vector3(-1.05, yy, 0), Vector3(1.05, yy, 0), 0.015, cyan))
	var t1: Label3D = EggProps.label("W E I G H   S T A T I O N", 30, Color(0.65, 0.97, 1.0), Vector3(0, 0.1, 0.01), Vector3.ZERO, true)
	t1.double_sided = true
	_holo.add_child(t1)
	var t2: Label3D = EggProps.label(tr("OUTPOST %d  ·  ONLINE") % (index + 1), 22, Color(1.0, 0.65, 0.3), Vector3(0, -0.13, 0.01), Vector3.ZERO, true)
	t2.double_sided = true
	_holo.add_child(t2)
	# Hovering cargo pods on a dark pad.
	var stock := Node3D.new()
	stock.position = Vector3(-2.3, 0, -2.7)
	stock.rotation.y = 0.3
	_part(stock, 1)
	stock.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(1.4, 0.06, 1.1), 0.03, 2), dark, Vector3(0, 0.03, 0)))
	stock.add_child(_strip(Vector3(-0.7, 0.07, 0.55), Vector3(0.7, 0.07, 0.55), 0.025, cyan))
	for k: int in 2:
		var pod := EggProps.mesh(ProcMesh.rounded_box(Vector3(0.6, 0.45, 0.6), 0.08, 2), white, Vector3(-0.33 + k * 0.66, 0.55 + k * 0.08, 0), Vector3(0, k * 18.0, 0))
		pod.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.62, 0.05, 0.62)), orange, Vector3(0, 0.05, 0)))
		pod.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.5, 0.01, 0.5)), cyan, Vector3(0, -0.23, 0)))
		stock.add_child(pod)
	# Level 3: recharge pad with a coil pylon.
	_charge_mat = null
	_charge_light = null
	if lv >= 3:
		var cp := Node3D.new()
		cp.position = CHARGER
		_part(cp, 3)
		cp.add_child(EggProps.mesh(ProcMesh.cyl(1.25, 1.32, 0.12, 40), white, Vector3(0, 0.06, 0)))
		cp.add_child(EggProps.mesh(ProcMesh.cyl(1.05, 1.05, 0.02, 40), dark, Vector3(0, 0.125, 0)))
		_charge_mat = Mats.lamp(Color(0.3, 0.85, 1.0), 2.0)
		cp.add_child(EggProps.mesh(ProcMesh.torus(0.95, 1.05, 48, 4), _charge_mat, Vector3(0, 0.14, 0)))
		cp.add_child(EggProps.mesh(ProcMesh.torus(0.35, 0.42, 28, 4), _charge_mat, Vector3(0, 0.14, 0)))
		cp.add_child(EggProps.mesh(ProcMesh.cyl(0.08, 0.12, 1.5, 12), white, Vector3(1.4, 0.75, -0.3)))
		for yy: float in [0.6, 0.85, 1.1, 1.35]:
			cp.add_child(EggProps.mesh(ProcMesh.torus(0.1, 0.15, 16, 4), _charge_mat, Vector3(1.4, yy, -0.3)))
		cp.add_child(EggProps.mesh(ProcMesh.sphere(0.12, 12, 6), orange_glow, Vector3(1.4, 1.6, -0.3)))
		cp.add_child(EggProps.mesh(ProcMesh.cyl(1.0, 1.0, 1.2, 32), _holo_mat(Color(0.3, 0.85, 1.0), 0.05), Vector3(0, 0.75, 0)))
		_charge_light = EggProps.glow(Color(0.35, 0.85, 1.0), 1.0, 4.0, Vector3(0, 0.6, 0))
		cp.add_child(_charge_light)
		cp.add_child(EggProps.label(tr("RECHARGE"), 34, Color(0.75, 0.95, 1.0), Vector3(0, 0.14, 0.7), Vector3(-90, 0, 0), true))
	if drop_lv > 0:
		_drop_in(drop_lv)


func _collider(n: Node3D, size: Vector3, center: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	sb.add_child(cs)
	n.add_child(sb)


## Fast-build: every part first built at level >= `from_lv` drops in from above, spinning, and
## lands with sparks and a clunk (the hub's style).
func _drop_in(from_lv: int) -> void:
	var d: float = 0.0
	for c: Node in _fixed.get_children():
		if not c is Node3D or int(c.get_meta("lv", 0)) < from_lv:
			continue
		var n: Node3D = c
		var final: Transform3D = n.transform
		n.position = final.origin + Vector3(randf_range(-2, 2), 8.0, randf_range(-2, 2))
		n.rotation = Vector3(randf_range(-1, 1), randf_range(-2, 2), randf_range(-1, 1))
		n.visible = false
		var tw := n.create_tween()
		tw.tween_interval(d)
		tw.tween_callback(func() -> void: n.visible = true)
		tw.tween_property(n, "transform", final, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			Vfx.burst("sparkle", to_global(final.origin) + Vector3(0, 0.3, 0), Color(1.0, 0.8, 0.4), 0.5)
			Vfx.burst("dust", to_global(final.origin), Color(0.65, 0.6, 0.52, 0.5), 0.5)
			Audio.play("clunk", randf_range(0.9, 1.2), -10.0))
		d += 0.2
