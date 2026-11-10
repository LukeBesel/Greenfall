class_name LumiStyleRig
extends Node3D
## [style] The Character Builder layer on a PatchModel (added by LumiStyle.after_build, freed with
## the model's other children on every rebuild). Draws what the hero model does not have natively
## (eye shapes are NOT here: every shape is drawn by the face shader, art/shaders/bot_face.gdshader,
## which PatchModel sets from the style's eye_shape):
##   - the heart chest icon (acc_icon_heart from the add-on library, else a glowing quad)
##   - head pieces, held items and companions that are not PatchModel acc ids: the first mesh
##     named in the option's "parts" found in aurora.glb / designs.glb, else a small procedural
##     stand-in (antenna, halo, medkit, watering_can, firefly, drone)
## Everything goes through get()/has_method() so the hero rebuild can change the model under it.

var model: Node3D
var style: Dictionary = {}
var _icon_mat: ShaderMaterial
var _halo: Node3D
var _comp: Node3D
var _comp_kind: String = ""
var _comp_wings: Array[Node3D] = []
var _comp_glow: StandardMaterial3D
var _drone_eye: StandardMaterial3D
var _t: float = 0.0
var _seed: float = 0.0


func setup(m: Node3D, s: Dictionary) -> void:
	model = m
	style = s
	_seed = randf() * 10.0
	if str(s.get("chest", "")) == "heart":
		_build_heart_icon()
	for slot: String in ["head", "held", "companion"]:
		var o: Dictionary = LumiStyle.option(slot, str(s.get(slot, "none")))
		if o.is_empty() or not (o.get("acc", []) as Array).is_empty() or str(o.get("build", "")) == "":
			continue
		_build_part(slot, o)
	restyle(s)


func restyle(s: Dictionary) -> void:
	style = s
	if _icon_mat:
		_icon_mat.set_shader_parameter("col", LumiStyle.col(s, "glow"))
	if _drone_eye:
		_drone_eye.emission = LumiStyle.col(s, "eyes")
		_drone_eye.albedo_color = LumiStyle.col(s, "eyes")


# --- Building ---------------------------------------------------------------------------------

func _lib_has(part: String) -> bool:
	PatchModel._load_parts()
	return PatchModel._parts.has(part)


func _lib_part(parent: Node3D, part: String, pos: Vector3) -> MeshInstance3D:
	if model.has_method("_part"):
		return model.call("_part", parent, part, pos)
	return null


func _pivot(part: String) -> Vector3:
	return PatchModel._pivot(part) if _lib_has(part) else Vector3.ZERO


func _mat(key: String, fallback: Material) -> Material:
	var mats: Variant = model.get("_mats")
	if mats is Dictionary and (mats as Dictionary).has(key):
		return (mats as Dictionary)[key]
	return fallback


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	mi.layers = 1 | PatchModel.HERO_LAYER
	parent.add_child(mi)
	return mi


func _cyl(r_top: float, r_bot: float, h: float, seg: int = 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


func _sphere(r: float, seg: int = 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	return s


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 48
	t.ring_segments = 10
	return t


func _paint(c: Color, seed_: float) -> Material:
	if model.has_method("_paint"):
		var m: ShaderMaterial = model.call("_paint", c, seed_, 0.92)
		m.set_shader_parameter("grime", float(style.get("wear", 0.6)) * 0.7)
		return m
	var sm := StandardMaterial3D.new()
	sm.albedo_color = c
	sm.roughness = 0.45
	return sm


func _build_heart_icon() -> void:
	var fl: Node3D = model.get("_float") as Node3D
	if fl == null:
		return
	var lbl: Variant = model.get("_icon")
	if lbl is Label3D:
		(lbl as Label3D).visible = false
	if _lib_has("acc_icon_heart"):
		_lib_part(fl, "acc_icon_heart", _pivot("acc_icon_heart"))
		return
	var q := QuadMesh.new()
	q.size = Vector2(0.075, 0.075)
	_icon_mat = ShaderMaterial.new()
	_icon_mat.shader = preload("res://art/shaders/lumi_icon.gdshader")
	var mi := _mesh(fl, q, _icon_mat, Vector3(0, 0.44, -0.1845), Vector3(0, 180, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_part(slot: String, o: Dictionary) -> void:
	var head: Node3D = model.get("_head") as Node3D
	var arm_l: Node3D = model.get("_arm_l") as Node3D
	var wrist: Node3D = arm_l.get_meta("wrist") if arm_l and arm_l.has_meta("wrist") else null
	var lib: String = ""
	for p: Variant in o.get("parts", []):
		if _lib_has(str(p)):
			lib = str(p)
			break
	var kind: String = str(o.get("build", ""))
	match slot:
		"head":
			if head == null:
				return
			if lib != "":
				var hn := Node3D.new()
				hn.name = "lumi_" + kind
				hn.position = _pivot(lib) - _pivot("head")
				head.add_child(hn)
				_lib_part(hn, lib, Vector3.ZERO)
				if kind == "halo":
					_halo = hn
				return
			if kind == "antenna":
				_build_antenna(head)
			elif kind == "halo":
				_build_halo(head)
		"held":
			if wrist == null:
				return
			var h := Node3D.new()
			h.name = "lumi_" + kind
			h.position = Vector3(0.0, -0.06, -0.115)
			wrist.add_child(h)
			if lib != "":
				_lib_part(h, lib, Vector3.ZERO)
			elif kind == "medkit":
				_build_medkit(h)
			elif kind == "watering_can":
				_build_can(h)
		"companion":
			_comp = Node3D.new()
			_comp.name = "lumi_" + kind
			_comp.top_level = true
			add_child(_comp)
			_comp_kind = kind
			if lib != "":
				_lib_part(_comp, lib, Vector3.ZERO)
			elif kind == "firefly":
				_build_firefly(_comp)
			elif kind == "drone":
				_build_drone(_comp)
			if model.is_inside_tree():
				_comp.global_position = model.global_position + Vector3(0.5, 1.1, 0.3)


func _build_antenna(head: Node3D) -> void:
	var a := Node3D.new()
	a.name = "lumi_antenna"
	a.position = Vector3(0.07, 0.455, 0.05)
	a.rotation_degrees = Vector3(-8, 0, -10)
	head.add_child(a)
	var dark: Material = _mat("dark", Mats.metal("steel"))
	_mesh(a, _cyl(0.022, 0.026, 0.024), _mat("trim", dark), Vector3(0, 0.012, 0))
	_mesh(a, _cyl(0.0055, 0.0075, 0.2, 10), dark, Vector3(0, 0.12, 0))
	_mesh(a, _sphere(0.021), _mat("glow", Mats.lamp(LumiStyle.col(style, "glow"), 3.0)), Vector3(0, 0.235, 0))


func _build_halo(head: Node3D) -> void:
	_halo = Node3D.new()
	_halo.name = "lumi_halo"
	_halo.position = Vector3(0, 0.6, 0.03)
	head.add_child(_halo)
	var m: StandardMaterial3D = Mats.lamp(LumiStyle.col(style, "glow"), 2.2)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = LumiStyle.col(style, "glow").lerp(Color.WHITE, 0.35)
	var mi := _mesh(_halo, _torus(0.145, 0.16), m, Vector3.ZERO, Vector3(8, 0, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_medkit(h: Node3D) -> void:
	h.rotation = Vector3(0.0, PI * 0.5, 0.0)
	h.scale = Vector3.ONE * 1.15
	var body := _paint(Color(0.93, 0.92, 0.89), 17.0)
	_mesh(h, _box(Vector3(0.13, 0.09, 0.055)), body, Vector3(0, -0.035, 0))
	_mesh(h, _box(Vector3(0.05, 0.016, 0.02)), _mat("dark", body), Vector3(0, 0.017, 0))
	var red: StandardMaterial3D = Mats.lamp(Color(1.0, 0.18, 0.2), 1.6)
	for z: float in [-0.0285, 0.0285]:
		_mesh(h, _box(Vector3(0.052, 0.016, 0.003)), red, Vector3(0, -0.035, z))
		_mesh(h, _box(Vector3(0.016, 0.052, 0.003)), red, Vector3(0, -0.035, z))


func _build_can(h: Node3D) -> void:
	h.rotation = Vector3(0.0, PI * 0.5, 0.0)
	h.scale = Vector3.ONE * 1.4
	var body := _paint(LumiStyle.col(style, "accent"), 19.0)
	var dark: Material = _mat("dark", body)
	_mesh(h, _cyl(0.04, 0.046, 0.085, 20), body, Vector3(0, -0.06, 0))
	_mesh(h, _cyl(0.042, 0.042, 0.008, 20), dark, Vector3(0, -0.016, 0))
	# Spout forward and up, with a rose at the tip; a loop handle over the top.
	_mesh(h, _cyl(0.0055, 0.009, 0.11, 10), body, Vector3(-0.07, -0.05, 0), Vector3(0, 0, 55))
	_mesh(h, _cyl(0.016, 0.009, 0.014, 12), dark, Vector3(-0.115, -0.017, 0), Vector3(0, 0, 55))
	var hd := _mesh(h, _torus(0.026, 0.034), dark, Vector3(0.012, -0.012, 0), Vector3(90, 0, 0))
	hd.scale = Vector3(1.0, 1.0, 0.9)


func _glow_sprite(parent: Node3D, c: Color, size: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	m.albedo_color = c
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	m.albedo_texture = gt
	var mi := _mesh(parent, q, m, Vector3.ZERO)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_comp_glow = m


func _build_firefly(f: Node3D) -> void:
	var dark: Material = _mat("dark", Mats.metal("steel"))
	_mesh(f, _sphere(0.012, 10), dark, Vector3(0, 0, -0.012), Vector3.ZERO, Vector3(1, 1, 1.4))
	var tail: StandardMaterial3D = Mats.lamp(Color(0.85, 1.0, 0.42), 4.0)
	_mesh(f, _sphere(0.014, 10), tail, Vector3(0, -0.003, 0.012), Vector3.ZERO, Vector3(1, 1, 1.3))
	var wing := StandardMaterial3D.new()
	wing.albedo_color = Color(0.8, 0.9, 1.0, 0.35)
	wing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side: float in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(0, 0.008, -0.008)
		hinge.set_meta("side", side)
		f.add_child(hinge)
		var q := QuadMesh.new()
		q.size = Vector2(0.03, 0.014)
		var w := _mesh(hinge, q, wing, Vector3(side * 0.016, 0, 0), Vector3(-90, 0, 0))
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_comp_wings.append(hinge)
	_glow_sprite(f, Color(0.8, 1.0, 0.4, 0.55), 0.16)


func _build_drone(d: Node3D) -> void:
	var paint: Material = _mat("paint", _paint(LumiStyle.col(style, "paint"), 23.0))
	var dark: Material = _mat("dark", Mats.metal("steel"))
	_mesh(d, _sphere(0.06, 20), paint, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.62, 1.0))
	_mesh(d, _cyl(0.05, 0.05, 0.012, 20), dark, Vector3(0, -0.022, 0))
	var ring: StandardMaterial3D = Mats.lamp(LumiStyle.col(style, "glow"), 2.6)
	_mesh(d, _torus(0.058, 0.064), ring, Vector3(0, -0.006, 0))
	_drone_eye = Mats.lamp(LumiStyle.col(style, "eyes"), 3.5)
	_mesh(d, _sphere(0.014, 12), _drone_eye, Vector3(0, 0.0, -0.052), Vector3.ZERO, Vector3(1.3, 0.8, 0.5))
	for side: float in [-1.0, 1.0]:
		var arm := _mesh(d, _box(Vector3(0.05, 0.008, 0.012)), dark, Vector3(side * 0.08, 0.005, 0))
		arm.rotation_degrees = Vector3(0, 0, side * -8)
		var rotor := Node3D.new()
		rotor.position = Vector3(side * 0.105, 0.016, 0)
		d.add_child(rotor)
		var disc := StandardMaterial3D.new()
		disc.albedo_color = Color(0.85, 0.9, 1.0, 0.22)
		disc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mesh(rotor, _cyl(0.03, 0.03, 0.002, 18), disc, Vector3.ZERO)
		_comp_wings.append(rotor)


# --- Per frame --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _halo:
		_halo.rotation.y = _t * 0.6
		_halo.position.y = 0.6 + sin(_t * 1.7) * 0.008
	if _comp == null or model == null or not model.is_inside_tree():
		return
	var head: Node3D = model.get("_head") as Node3D
	var c: Vector3 = head.global_position if head else model.global_position + Vector3(0, 0.8, 0)
	var b: Basis = model.global_transform.basis.orthonormalized()
	match _comp_kind:
		"firefly":
			# Lazy drifting loops low around the shoulders, with a slow blink of its tail light.
			var a: float = _t * 0.8 + _seed
			var off := Vector3(cos(a) * 0.5 + sin(_t * 1.9) * 0.06, 0.12 + sin(_t * 1.3 + _seed) * 0.12, sin(a) * 0.38 + 0.1)
			var pos: Vector3 = c + b * off
			var heading: Vector3 = (b * Vector3(-sin(a), 0.0, cos(a) * 0.76)).normalized()
			_comp.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), pos)
			for h: Node3D in _comp_wings:
				h.rotation.z = (sin(_t * 40.0) * 0.6 + 0.3) * float(h.get_meta("side", 1.0))
			if _comp_glow:
				_comp_glow.albedo_color.a = 0.35 + 0.3 * (0.5 + 0.5 * sin(_t * 2.3 + _seed))
		"drone":
			# Hovers at the right shoulder, a little behind, lagging and facing where Lumi faces.
			var target: Vector3 = c + b * Vector3(0.46, 0.2 + sin(_t * 2.1) * 0.03, 0.18)
			var k: float = clampf(delta * 3.5, 0.0, 1.0)
			var p: Vector3 = _comp.global_position.lerp(target, k)
			if p.distance_to(target) > 3.0:
				p = target
			var fwd: Vector3 = -b.z
			fwd.y = 0.0
			var tilt: float = clampf((target - _comp.global_position).dot(b.x) * 2.0, -0.4, 0.4)
			var basis_d := Basis.looking_at(fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD, Vector3.UP).rotated(fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD, -tilt)
			_comp.global_transform = Transform3D(basis_d, p)
			for r: Node3D in _comp_wings:
				r.rotation.y = _t * 40.0
		_:
			_comp.global_position = c + b * Vector3(0.5, 0.35, 0.15)
