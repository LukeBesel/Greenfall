class_name Depot
extends Node3D
## The Depot Intake: a rusty pad with a big hungry chute. Patch rolls onto the pad and his carried
## cubes hop off his back into the chute one by one. Loose cubes pushed onto the pad get sucked in.

const PAD_RADIUS: float = 1.7
const FEED_INTERVAL: float = 0.16

var patch: Node3D  # Patch (set by the scene)
## [outposts] Outpost scales reuse this class: `bare` skips the main depot's visuals (the outpost
## builds its own and sets `mouth_local`), `world` names the slice when the parent isn't it, and
## `value_bonus` adds to the hub's sell multiplier.
var bare: bool = false
var world: Node
var pad_radius: float = PAD_RADIUS
var value_bonus: float = 0.0
var mouth_local := Vector3.ZERO
var cashed: int = 0  ## bales cashed here this session (dev reports)
var _chute: Node3D
var _chute_mouth: Vector3
var _feed_timer: float = 0.0
var _combo: int = 0
var _combo_timer: float = 0.0
var _light_mat: ShaderMaterial
var _needle: MeshInstance3D
var _needle_t: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	add_to_group("depot")
	if bare:
		_chute_mouth = mouth_local
	else:
		_build()


func _build() -> void:
	# A steel scrap skip on a platform weigh scale. Bales dropped on the scale plate are tipped
	# into the skip and weighed; the dial swings and the payout is logged.
	var plate := MeshInstance3D.new()
	plate.mesh = ProcMesh.box(Vector3(PAD_RADIUS * 1.9, 0.08, PAD_RADIUS * 1.9))
	plate.material_override = Mats.worn_paint(Color(0.28, 0.3, 0.3), 0.55, 0.6, 3.0, 0.7)
	plate.position = Vector3(0, 0.04, 0)
	add_child(plate)
	# Hazard edge stripes.
	var stripe_mat := Mats.worn_paint(Color(0.95, 0.72, 0.12), 0.7, 0.5, 4.0, 0.6)
	for k: int in 4:
		var st := MeshInstance3D.new()
		st.mesh = ProcMesh.box(Vector3(PAD_RADIUS * 1.9, 0.01, 0.12))
		st.material_override = stripe_mat
		st.rotation.y = k * PI * 0.5
		st.position = Vector3(0, 0.085, 0) + Basis(Vector3.UP, k * PI * 0.5) * Vector3(0, 0, PAD_RADIUS * 0.9)
		add_child(st)
	_chute = Node3D.new()
	_chute.position = Vector3(0, 0, -2.7)
	add_child(_chute)
	_build_body(TrashBin.level())  # [camp] the bin's body follows its level (automation/trash_bin.gd)
	TrashBin.events.changed.connect(_on_bin_changed)
	# Scale head: a post with a big analog dial facing the plate.
	var post := MeshInstance3D.new()
	post.mesh = ProcMesh.cyl(0.05, 0.06, 1.4, 10)
	post.material_override = Mats.worn_paint(Color(0.85, 0.82, 0.75), 0.6, 0.6, 9.0)
	post.position = Vector3(PAD_RADIUS * 1.05, 0.7, -PAD_RADIUS * 0.6)
	add_child(post)
	var pcs := CollisionShape3D.new()  # [world2] the dial post is solid (local frame, shared shape)
	pcs.shape = PropColliders.cyl_shape(0.08, 1.4)
	pcs.position = post.position
	var pbody := StaticBody3D.new()
	pbody.collision_layer = PhysLayers.PROP
	pbody.add_child(pcs)
	add_child(pbody)
	var dial := MeshInstance3D.new()
	dial.mesh = ProcMesh.cyl(0.22, 0.22, 0.08, 24)
	dial.material_override = Mats.worn_paint(Color(0.9, 0.88, 0.82), 0.8, 0.4, 10.0)
	dial.rotation_degrees = Vector3(90, 0, 0)
	dial.position = post.position + Vector3(0, 0.75, 0.05)
	add_child(dial)
	var face := Label3D.new()
	face.text = "kg"
	face.font_size = 28
	face.pixel_size = 0.004
	face.modulate = Color(0.15, 0.15, 0.15)
	face.shaded = true
	face.position = dial.position + Vector3(0, -0.08, 0.05)
	add_child(face)
	_needle = MeshInstance3D.new()
	_needle.mesh = ProcMesh.box(Vector3(0.015, 0.18, 0.01))
	_needle.material_override = Mats.lamp(Color(0.8, 0.1, 0.05), 0.5)
	_needle.position = dial.position + Vector3(0, 0, 0.05)
	add_child(_needle)
	var lamp := MeshInstance3D.new()
	lamp.mesh = ProcMesh.sphere(0.06, 10, 5)
	_light_mat = ShaderMaterial.new()
	lamp.material_override = Mats.lamp(Color(1.0, 0.65, 0.2), 1.2)
	lamp.position = post.position + Vector3(0, 1.05, 0)
	add_child(lamp)

func pad_contains(world_pos: Vector3) -> bool:
	var d: Vector3 = world_pos - global_position
	d.y = 0.0
	return d.length() <= pad_radius


## What a bale is worth here relative to its base value (hub level bonus + this scale's bonus).
func sell_factor() -> float:
	var w: Node = world if world else get_parent()
	var m: float = 1.0 + value_bonus
	if not bare:
		m *= TrashBin.value_mult()  # [camp] the bin's level
	if w and w.get("hub") != null:
		m += float(w.hub.sell_mult())
	if w and w.get("field") != null:  # [biomes] frontier junk sells for more (data/frontiers.json value_mult)
		m *= float(Frontiers.def_for_biome(str(w.field.biome)).get("value_mult", 1.0))
	return m


func mouth_world() -> Vector3:
	return to_global(_chute_mouth)


func _physics_process(delta: float) -> void:
	_t += delta
	_needle_t = maxf(0.0, _needle_t - delta * 0.8)
	if _needle:
		_needle.rotation.z = -_needle_t * 2.4 + sin(_t * 23.0) * 0.02 * _needle_t
	_combo_timer -= delta
	if _combo_timer <= 0.0:
		_combo = 0
	_feed_timer -= delta
	if patch and _feed_timer <= 0.0 and pad_contains(patch.global_position) and patch.has_method("pop_carried_cube"):
		var cube: JunkCube = patch.pop_carried_cube()
		if cube:
			_feed_timer = FEED_INTERVAL if bare else TrashBin.feed_interval()  # [camp]
			_swallow(cube)
	if patch and not bare and _feed_timer <= 0.0:  # [pace] no Baler yet: empty the chest loose
		var bin: Node3D = Pace.trash_bin(get_tree(), global_position)
		if bin:
			Pace.try_dump(patch, bin.global_position, Pace.BIN_RADIUS, bin)
		else:
			Pace.try_dump(patch, global_position, pad_radius)
	# Loose cubes on the pad get sucked in.
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n
		if c.carried or c.claimed:
			continue
		if pad_contains(c.global_position) and c.global_position.y < 3.0:
			_swallow(c)


func _swallow(cube: JunkCube) -> void:
	cube.claimed = true
	cube.set_carried(true)
	var start: Vector3 = cube.global_position
	var end: Vector3 = mouth_world()
	var top: Vector3 = (start + end) * 0.5 + Vector3(0, 2.2, 0)
	Audio.play("whoosh", 1.2, -8.0)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var a: Vector3 = start.lerp(top, t)
		var b: Vector3 = top.lerp(end, t)
		cube.global_position = a.lerp(b, t)
		cube.rotation += Vector3(0.15, 0.2, 0.1)
		, 0.0, 1.0, 0.32).set_trans(Tween.TRANS_SINE)
	tw.tween_property(cube, "scale", Vector3.ONE * 0.2, 0.08)
	tw.tween_callback(_cash.bind(cube))


func _cash(cube: JunkCube) -> void:
	_combo += 1
	_combo_timer = 1.2
	cashed += 1
	var v: BigNum = cube.value
	v = v.mul_f(sell_factor())
	GameState.add_currency("cubes", v)
	GameState.inc_stat("cubes_cashed")
	if bare:
		GameState.inc_stat("outpost_bales")  # [outposts]
	EventBus.cube_cashed.emit(v, mouth_world())
	Audio.play_scale("coin", mini(_combo - 1, 8), -4.0)
	var col: Color = Color(1.0, 0.75, 0.35) if cube.info.get("perfect", false) else Color(0.9, 0.92, 0.88)
	Vfx.float_text(mouth_world() + Vector3(0, 0.3, 0), "+" + Settings.fmt(v), col, 0.5, 0.8)
	Vfx.burst("dust", mouth_world() - Vector3(0, 0.3, 0), Color(0.6, 0.55, 0.5, 0.5), 0.8)
	Audio.play("clunk", 0.8, -4.0)
	_needle_t = 1.0
	if _ram:  # [camp] the compactor presses each bale
		var tw := create_tween()
		tw.tween_property(_ram, "position:y", 1.35, 0.08)
		tw.tween_property(_ram, "position:y", 1.95, 0.3).set_trans(Tween.TRANS_SINE)
	EventBus.shake_requested.emit(0.05)
	cube.queue_free()


# --- [camp] The bin's body by level (data/trash_bin.json) ---------------------------------------

var _ram: Node3D  # level 4+: the compactor ram plate (bobs as a bale goes in)
var _body_level: int = 0


func _on_bin_changed(l: int) -> void:
	if bare or not is_inside_tree() or l == _body_level:
		return
	_build_body(l)
	Vfx.burst("dust", mouth_world(), Color(0.7, 0.65, 0.6, 0.6), 1.4)
	Vfx.burst("sparkle", mouth_world() + Vector3(0, 0.4, 0), Color(1.0, 0.85, 0.5), 0.8)
	Audio.play("clunk", 0.7, -2.0)
	_chute.scale = Vector3(1, 0.05, 1)
	create_tween().tween_property(_chute, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_body(l: int) -> void:
	_body_level = l
	_ram = null
	for c: Node in _chute.get_children():
		c.queue_free()
	var size: Vector3
	if l <= 1:
		size = _build_wheelie()
	else:
		size = _build_skip(l)
	var sb := StaticBody3D.new()
	sb.name = "BinBody"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	sb.add_child(cs)
	_chute.add_child(sb)


## Level 1: a dented, faded wheelie bin with its lid flopped open, standing at the plate's head.
func _build_wheelie() -> Vector3:
	var paint: ShaderMaterial = Mats.worn_paint(Color(0.2, 0.36, 0.24), 0.75, 0.55, 6.0, 0.75)
	var dark: StandardMaterial3D = Mats.metal("dark_steel")
	var bin := Node3D.new()
	bin.rotation = Vector3(0.0, 0.18, deg_to_rad(-3.0))  # a little crooked
	_chute.add_child(bin)
	var w: float = 0.86
	var d: float = 0.92
	var h: float = 1.08
	var parts: Array = []
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w * 0.86, 0.06, d * 0.86)), ProcMesh.xf(Vector3(0, 0.12, 0))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w, h, 0.05)), ProcMesh.xf(Vector3(0, h * 0.5 + 0.08, d * 0.5), Vector3(-3, 0, 0))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w, h, 0.05)), ProcMesh.xf(Vector3(0, h * 0.5 + 0.08, -d * 0.5), Vector3(3, 0, 0))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, h, d)), ProcMesh.xf(Vector3(w * 0.5, h * 0.5 + 0.08, 0), Vector3(0, 0, 3))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.05, h, d)), ProcMesh.xf(Vector3(-w * 0.5, h * 0.5 + 0.08, 0), Vector3(0, 0, -3))))
	# A dent: a pushed-in panel on the front face.
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.34, 0.28, 0.04)), ProcMesh.xf(Vector3(0.14, 0.62, d * 0.5 - 0.02), Vector3(-8, 10, 6))))
	# Rim lip.
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w + 0.08, 0.06, d + 0.08)), ProcMesh.xf(Vector3(0, h + 0.1, 0))))
	var body := MeshInstance3D.new()
	body.mesh = ProcMesh.merge(parts)
	body.material_override = paint
	bin.add_child(body)
	# Lid flopped back over the hinge, hanging at an angle.
	var lid := MeshInstance3D.new()
	lid.mesh = ProcMesh.box(Vector3(w + 0.1, 0.05, d + 0.06))
	lid.material_override = paint
	lid.position = Vector3(0, h + 0.05, -d * 0.5 - 0.42)
	lid.rotation_degrees = Vector3(-62, 0, 4)
	bin.add_child(lid)
	# Wheels and axle at the back, a handle bar over them.
	for x: float in [-w * 0.42, w * 0.42]:
		var wh := MeshInstance3D.new()
		wh.mesh = ProcMesh.cyl(0.11, 0.11, 0.06, 12)
		wh.material_override = dark
		wh.rotation_degrees = Vector3(0, 0, 90)
		wh.position = Vector3(x, 0.11, -d * 0.5 - 0.02)
		bin.add_child(wh)
	var bar := MeshInstance3D.new()
	bar.mesh = ProcMesh.cyl(0.02, 0.02, w * 0.9, 8)
	bar.material_override = dark
	bar.rotation_degrees = Vector3(0, 0, 90)
	bar.position = Vector3(0, h + 0.02, -d * 0.5 - 0.06)
	bin.add_child(bar)
	# Junk heaped over the rim.
	var fill := MeshInstance3D.new()
	fill.mesh = FieldView._mound_mesh()
	fill.material_override = AssetLib.pbr_material("rubble", 1.0, Color(0.6, 0.55, 0.5), true)
	fill.scale = Vector3(0.4, 0.3, 0.42)
	fill.position = Vector3(0, h + 0.02, 0)
	bin.add_child(fill)
	var sign_label := Mats.stencil(tr("TRASH"), 48, Color(0.92, 0.9, 0.82, 0.85))
	sign_label.position = Vector3(-0.12, 0.86, d * 0.5 + 0.04)
	bin.add_child(sign_label)
	_chute_mouth = _chute.position + Vector3(0, h + 0.35, 0)
	return Vector3(w + 0.1, h + 0.15, d + 0.1)


## Levels 2+: the steel skip; 3 adds side ribs and a beacon, 4 a compactor ram, 5 a clean white
## shell with a thin cyan scanner seam.
func _build_skip(l: int) -> Vector3:
	var smart: bool = l >= 5
	var skip_mat: ShaderMaterial = Mats.worn_paint(Color(0.86, 0.88, 0.89) if smart else Color(0.22, 0.42, 0.3), 0.15 if smart else 0.6, 0.5 if smart else 0.6, 7.0, 0.2 if smart else 0.6)
	var parts: Array = []
	var w: float = 2.6
	var d: float = 1.6
	var h: float = 1.25
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w * 0.8, 0.08, d)), ProcMesh.xf(Vector3(0, 0.05, 0))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w, h, 0.06)), ProcMesh.xf(Vector3(0, h * 0.5, d * 0.5))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(w, h, 0.06)), ProcMesh.xf(Vector3(0, h * 0.5, -d * 0.5))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.06, h * 1.05, d)), ProcMesh.xf(Vector3(w * 0.45, h * 0.5, 0), Vector3(0, 0, -12))))
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.06, h * 1.05, d)), ProcMesh.xf(Vector3(-w * 0.45, h * 0.5, 0), Vector3(0, 0, 12))))
	for x: float in [-0.9, 0.0, 0.9]:
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.08, h, 0.1)), ProcMesh.xf(Vector3(x, h * 0.5, d * 0.5 + 0.05))))
	if l >= 3:
		for x: float in [-0.9, 0.0, 0.9]:
			parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.08, h, 0.1)), ProcMesh.xf(Vector3(x, h * 0.5, -d * 0.5 - 0.05))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(w + 0.1, 0.08, 0.14)), ProcMesh.xf(Vector3(0, h, d * 0.5 + 0.04))))
	var skip := MeshInstance3D.new()
	skip.mesh = ProcMesh.merge(parts)
	skip.material_override = skip_mat
	_chute.add_child(skip)
	var fill := MeshInstance3D.new()
	fill.mesh = FieldView._mound_mesh()
	fill.material_override = AssetLib.pbr_material("rubble", 1.0, Color(0.6, 0.55, 0.5), true)
	fill.scale = Vector3(1.15, 0.5, 0.7)
	fill.position = Vector3(0, h * 0.55, 0)
	_chute.add_child(fill)
	var sign_label := Mats.stencil(tr("SCRAP  INTAKE  ·  WEIGH HERE"), 64, Color(0.2, 0.24, 0.26, 0.9) if smart else Color(0.92, 0.9, 0.82, 0.9))
	sign_label.position = Vector3(0, h * 0.62, d * 0.5 + 0.11)
	_chute.add_child(sign_label)
	var top: float = h
	if l == 3:
		var beacon := MeshInstance3D.new()
		beacon.mesh = ProcMesh.cyl(0.07, 0.08, 0.14, 12)
		beacon.material_override = Mats.lamp(Color(1.0, 0.6, 0.12), 1.6)
		beacon.position = Vector3(w * 0.5 - 0.1, h + 0.1, d * 0.5 - 0.1)
		_chute.add_child(beacon)
	if l >= 4:
		var frame_mat: StandardMaterial3D = Mats.metal("dark_steel")
		var fparts: Array = []
		for x: float in [-w * 0.5 - 0.08, w * 0.5 + 0.08]:
			fparts.append(ProcMesh.part(ProcMesh.box(Vector3(0.14, 2.5, 0.18)), ProcMesh.xf(Vector3(x, 1.25, -0.1))))
		fparts.append(ProcMesh.part(ProcMesh.box(Vector3(w + 0.4, 0.2, 0.26)), ProcMesh.xf(Vector3(0, 2.5, -0.1))))
		fparts.append(ProcMesh.part(ProcMesh.cyl(0.07, 0.07, 0.5, 10), ProcMesh.xf(Vector3(0, 2.2, -0.1))))
		var frame := MeshInstance3D.new()
		frame.mesh = ProcMesh.merge(fparts)
		frame.material_override = frame_mat
		_chute.add_child(frame)
		_ram = MeshInstance3D.new()
		(_ram as MeshInstance3D).mesh = ProcMesh.box(Vector3(w * 0.7, 0.1, d * 0.6))
		(_ram as MeshInstance3D).material_override = Mats.worn_paint(Color(0.9, 0.7, 0.15), 0.5, 0.5, 4.0, 0.5) if not smart else frame_mat
		_ram.position = Vector3(0, 1.95, -0.1)
		_chute.add_child(_ram)
		top = 2.6
	if smart:
		var seam := MeshInstance3D.new()
		seam.mesh = ProcMesh.box(Vector3(w + 0.02, 0.025, 0.02))
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.5, 0.9, 1.0)
		gm.emission_enabled = true
		gm.emission = Color(0.5, 0.9, 1.0)
		gm.emission_energy_multiplier = 1.4
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		seam.material_override = gm
		seam.position = Vector3(0, h - 0.14, d * 0.5 + 0.1)
		_chute.add_child(seam)
	_chute_mouth = _chute.position + Vector3(0, h + 0.4, 0)
	return Vector3(w, top + 0.2 if l >= 4 else h + 0.2, d)
