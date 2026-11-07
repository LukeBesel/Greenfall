class_name ShipModel
extends Node3D
## [ship] Lumi's travel ship, the Seedglider: a low, wide manta glider with big swept wings, twin
## engine nacelles, a faceted cyan canopy, layered pearl hull plates with crisp seams, tangerine
## accents, thin cyan light lines, small orange running lights and Lumi's C eyes on the nose sensor.
## Modelled in Blender (art/models/ship/build_ship.py -> ship.glb + ship_points.json) as modular
## parts on one base; ShipTiers.parts_for(look) picks which ones a tier carries, so the ship visibly
## grows from the Mk I one-seat glider to the Mk VII Homeward with its seed vault.
## Local frame: the nose points +Z, ground at y=0 with the gear down. VTOL: lift fans in the wings
## (set_lift) and main engines at the back (plume / boosters, `plume.power`).

const MODEL_PATH := "res://art/models/ship/ship.glb"
const POINTS_PATH := "res://art/models/ship/ship_points.json"
const PAINT := preload("res://art/shaders/ship_paint.gdshader")
const FACE := preload("res://art/shaders/bot_face.gdshader")
const GLOW := Color(0.3, 0.88, 1.0)
const ACCENT := Color(1.0, 0.5, 0.16)
const PEARL := Color(0.93, 0.93, 0.91)
## Front parts move forward by the mid section's length from Mk V (the hull gets longer).
const FRONT_PARTS: Array[String] = ["hull_front", "canopy_a", "canopy_b", "gear_n"]
## Legacy (vertical rocket) constants some callers still read.
const NOZZLE_Y: float = 1.0
const HATCH_Y: float = 1.5

static var _parts: Dictionary = {}
static var _pts: Dictionary = {}

var tier: int = 1
var plume: RocketPlume
## The canopy hinge (opens for boarding); kept under the old name for callers.
var hatch: Node3D
var lift: float = 0.0
var _boosters: Array[RocketPlume] = []
var _fans: Array[RocketPlume] = []
var _legs: Array[Node3D] = []
var _skids: Array[Node3D] = []
var _mats: Dictionary = {}
var _glow_mats: Array[StandardMaterial3D] = []
var _thruster: StandardMaterial3D
var _lamp: StandardMaterial3D
var _face: ShaderMaterial
var _banners: Array[MeshInstance3D] = []
var _ring_node: Node3D
var _front: float = 0.0
var _t: float = 0.0
var _blink: float = 2.0
var _blink_v: float = 0.0
var _charge: float = 0.0
var _legs_k: float = 1.0
var _canopy_k: float = 0.0


static func _load() -> void:
	if not _parts.is_empty():
		return
	var scene: PackedScene = load(MODEL_PATH)
	if scene != null:
		var inst: Node = scene.instantiate()
		for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = n
			_parts[str(mi.name)] = {"mesh": mi.mesh, "pos": mi.position}
		inst.free()
	_pts = Economy.read_json(POINTS_PATH)


static func points() -> Dictionary:
	_load()
	return _pts


## How far the front parts sit forward at look t.
static func front_shift(t: int) -> float:
	return float(points().get("mid", 2.2)) if t >= 5 else 0.0


## Cockpit seat (local, unscaled): where Lumi drops in when boarding.
static func seat(t: int) -> Vector3:
	var h: Array = points().get("canopy_hinge_b" if t >= 3 else "canopy_hinge_a", [0, 1.5, 0])
	return Vector3(0.0, float(h[1]) - 0.1, float(h[2]) + 0.9 + front_shift(t))


## Length / half-span (local, unscaled) of look t: for the pad, cameras and colliders.
static func extent(t: int) -> Vector2:
	var half_span: float = 5.9 if t >= 6 else (3.85 if t >= 2 else 3.3)
	var length: float = 6.4 + front_shift(t) + (0.4 if t >= 7 else 0.0)
	return Vector2(length, half_span)


## A ready-built ship at the player's current look (or `t`), for the solar-system map, the
## Homecoming cinematic and other displays. `engines` 0..1 lights the main engines.
## Scale it with ShipTiers.scale_of(ship.tier) for true size relative to the pad.
static func for_display(t: int = -1, engines: float = 0.0) -> ShipModel:
	var m := ShipModel.new()
	m.build(ShipTiers.look() if t < 1 else t)
	m.set_legs(0.0 if engines > 0.0 else 1.0)
	m.plume.power = engines
	return m


## Turns `n` so a ship parented to it flies nose first along `dir` (the ship's nose is +Z).
static func face_along(n: Node3D, dir: Vector3, up: Vector3 = Vector3.UP) -> void:
	if dir.length() < 0.0001:
		return
	var z: Vector3 = dir.normalized()
	var u: Vector3 = up if absf(z.dot(up)) < 0.98 else Vector3.BACK
	var x: Vector3 = u.cross(z).normalized()
	n.basis = Basis(x, z.cross(x), z).scaled(n.basis.get_scale())


func build(p_tier: int) -> void:
	tier = clampi(p_tier, 1, ShipTiers.MAX_LOOK)
	_load()
	for c: Node in get_children():
		c.free()
	_boosters.clear()
	_fans.clear()
	_legs.clear()
	_skids.clear()
	_glow_mats.clear()
	_banners.clear()
	_ring_node = null
	plume = null
	hatch = null
	_make_mats()
	_front = front_shift(tier)
	var want: PackedStringArray = ShipTiers.parts_for(tier)
	for name: String in want:
		if not _parts.has(name):
			continue
		var pos: Vector3 = _parts[name]["pos"]
		if name in FRONT_PARTS:
			pos.z += _front
		if name.begins_with("canopy"):
			# Hinged at its rear edge: the mesh is in ship space, so offset it under the hinge.
			var h: Array = _pts.get("canopy_hinge_b" if name == "canopy_b" else "canopy_hinge_a", [0, 1.5, 0])
			hatch = Node3D.new()
			hatch.name = "Canopy"
			hatch.position = Vector3(float(h[0]), float(h[1]), float(h[2]) + _front)
			add_child(hatch)
			_part(hatch, name, pos - hatch.position)
		elif name.begins_with("gear_"):
			var piv := Node3D.new()
			piv.position = pos
			add_child(piv)
			_part(piv, name, Vector3.ZERO)
			_legs.append(piv)
		elif name.begins_with("skid_"):
			var piv2 := Node3D.new()
			piv2.position = pos
			piv2.set_meta("side", -1.0 if name.ends_with("_l") else 1.0)
			add_child(piv2)
			_part(piv2, name, Vector3.ZERO)
			_skids.append(piv2)
		elif name == "ring":
			_ring_node = _part(self, name, pos)
		else:
			_part(self, name, pos)
	_build_face()
	_build_marks()
	_build_engines(want)
	if tier >= 7:
		_build_banners()
	set_legs(_legs_k)
	set_canopy(_canopy_k)


func _make_mats() -> void:
	_mats.clear()
	_mats["paint"] = _paint(PEARL, 0.3)
	_mats["panel"] = _paint(Color(0.82, 0.83, 0.84), 0.38)
	_mats["accent"] = _paint(ACCENT, 0.3)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.09, 0.1, 0.115)
	trim.roughness = 0.4
	trim.metallic = 0.5
	trim.vertex_color_use_as_albedo = false
	_mats["trim"] = trim
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.025, 0.028, 0.035)
	dark.roughness = 0.25
	dark.metallic = 0.3
	_mats["dark"] = dark
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.62, 0.64, 0.68)
	steel.roughness = 0.28
	steel.metallic = 0.9
	_mats["steel"] = steel
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.42, 0.55)
	glass.roughness = 0.04
	glass.metallic = 0.35
	glass.clearcoat_enabled = true
	glass.clearcoat = 1.0
	glass.clearcoat_roughness = 0.02
	glass.emission_enabled = true
	glass.emission = Color(0.1, 0.55, 0.7)
	glass.emission_energy_multiplier = 0.25
	glass.rim_enabled = true
	glass.rim = 0.4
	_mats["glass"] = glass
	_mats["glow"] = _glow(GLOW, 1.5)
	_lamp = Mats.lamp(Color(1.0, 0.36, 0.12), 3.0)
	_mats["lamp"] = _lamp
	_thruster = Mats.lamp(GLOW, 1.0)
	_mats["thruster"] = _thruster
	_mats["vault"] = _glow(Color(0.45, 1.0, 0.55), 1.6)
	var vg := StandardMaterial3D.new()
	vg.albedo_color = Color(0.75, 0.95, 0.88, 0.28)
	vg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vg.roughness = 0.03
	vg.metallic = 0.2
	vg.rim_enabled = true
	vg.rim = 0.5
	_mats["vault_glass"] = vg
	var leaf := StandardMaterial3D.new()
	leaf.albedo_color = Color(0.3, 0.68, 0.26)
	leaf.roughness = 0.6
	leaf.emission_enabled = true
	leaf.emission = Color(0.25, 0.7, 0.3)
	leaf.emission_energy_multiplier = 0.3
	_mats["leaf"] = leaf


func _paint(c: Color, rough: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAINT
	m.set_shader_parameter("paint_color", c)
	m.set_shader_parameter("roughness", rough)
	return m


func _glow(c: Color, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = Mats.lamp(c, energy)
	m.set_meta("base", energy)
	_glow_mats.append(m)
	return m


func _part(parent: Node3D, name: String, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = _parts[name]["mesh"]
	mi.position = pos
	for i: int in mi.mesh.get_surface_count():
		var src: Material = mi.mesh.surface_get_material(i)
		var key: String = src.resource_name if src else ""
		if _mats.has(key):
			mi.set_surface_override_material(i, _mats[key])
	parent.add_child(mi)
	return mi


## Lumi's C eyes on the nose sensor (the same face shader as Lumi and the robots).
func _build_face() -> void:
	var v := Node3D.new()
	v.name = "Sensor"
	v.position = Vector3(0, 0.5 + float(_pts.get("lift", 0.62)), 3.037 + _front)
	v.rotation = Vector3(deg_to_rad(12.0), PI, 0)
	add_child(v)
	_face = ShaderMaterial.new()
	_face.shader = FACE
	_face.set_shader_parameter("eye_color", GLOW)
	_face.set_shader_parameter("half_width", 0.13)
	_face.set_shader_parameter("half_height", 0.03)
	_face.set_shader_parameter("eye_spacing", 2.1)
	_face.set_shader_parameter("eye_radius", 0.75)
	_face.set_shader_parameter("energy", 3.0)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.27, 0.062, 0.01)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = _face
	v.add_child(mi)


func _build_marks() -> void:
	var lift_y: float = float(_pts.get("lift", 0.62))
	for side: float in [-1.0, 1.0]:
		var l := Mats.stencil("GREENFALL", 64, Color(0.24, 0.28, 0.34, 0.9))
		l.pixel_size = 0.0022
		l.position = Vector3(side * 0.855, 0.66 + lift_y, -0.2)
		l.rotation = Vector3(0, side * PI * 0.5, 0)
		add_child(l)
		var tag := Label3D.new()
		tag.text = tr(ShipTiers.mark(tier))
		tag.font_size = 64
		tag.pixel_size = 0.0022
		tag.modulate = Color(0.45, 1.3, 1.7)
		tag.outline_size = 0
		tag.shaded = false
		tag.position = Vector3(side * 0.86, 0.58 + lift_y, -0.2)
		tag.rotation = Vector3(0, side * PI * 0.5, 0)
		add_child(tag)


func _build_engines(want: PackedStringArray) -> void:
	var main_len: float = [0.0, 0.42, 0.42, 0.5, 0.55, 0.6, 0.65, 0.75][tier]
	for nz: Dictionary in _pts.get("nozzles", []):
		var part: String = str(nz["part"])
		if not (part in want):
			continue
		var p: Array = nz["pos"]
		var rp := RocketPlume.new()
		rp.radius = float(nz["r"]) * 0.95
		rp.scale_len = main_len * (1.3 if part == "eng_core" else 1.0)
		rp.use_light = plume == null
		rp.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		rp.rotation_degrees = Vector3(90, 0, 0)  # the plume hangs down -Y: turn it to stream back (-Z)
		add_child(rp)
		if plume == null:
			plume = rp
		else:
			_boosters.append(rp)
	for f: Dictionary in _pts.get("fans", []):
		var fp: Array = f["pos"]
		for sx: float in [1.0, -1.0]:
			var lp := RocketPlume.new()
			lp.radius = float(f["r"]) * 0.8
			lp.scale_len = 0.22
			lp.use_light = sx > 0.0
			lp.position = Vector3(float(fp[0]) * sx, float(fp[1]) - 0.05, float(fp[2]))
			add_child(lp)
			_fans.append(lp)
	if plume == null:  # never null for callers
		plume = RocketPlume.new()
		add_child(plume)


## Thin banners of light streaming from the Mk VII's wingtips and fins.
func _build_banners() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 1.0, 0.7, 0.9))
	g.add_point(0.25, Color(0.4, 0.95, 1.0, 0.55))
	g.set_color(g.get_point_count() - 1, Color(0.3, 0.85, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = tex
	m.albedo_color = Color(1.4, 1.4, 1.4, 0.8)
	for sx: float in [1.0, -1.0]:
		for k: int in 2:
			var q := QuadMesh.new()
			q.size = Vector2(4.5 + k * 1.5, 0.05)
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var root: Vector3 = Vector3(sx * (5.4 - k * 3.0), 0.95 - k * 0.1, -3.3 - k * 0.2)
			# The quad's +X end is the banner's root; it streams back along -Z.
			mi.position = root + Vector3(0, 0, -q.size.x * 0.5)
			mi.rotation = Vector3(0, PI * 0.5, 0)
			mi.set_meta("y", mi.position.y)
			mi.set_meta("ph", sx * 1.3 + k)
			add_child(mi)
			_banners.append(mi)


## 0..1 extra brightness on the glow parts (charging before take-off).
func set_charge(c: float) -> void:
	_charge = c


## 1 = gear down (standing), 0 = folded into the hull.
func set_legs(k: float) -> void:
	_legs_k = k
	for leg: Node3D in _legs:
		leg.rotation.x = (1.0 - k) * 1.5
	for s: Node3D in _skids:
		s.rotation.z = float(s.get_meta("side")) * (1.0 - k) * 1.35


## 0..1: canopy opened for boarding.
func set_canopy(k: float) -> void:
	_canopy_k = k
	if hatch:
		hatch.rotation.x = -k * 0.95


## 0..1: VTOL lift fans.
func set_lift(k: float) -> void:
	lift = k


func _process(delta: float) -> void:
	_t += delta
	_blink -= delta
	var want: float = 0.0
	if _blink < 0.12:
		want = 1.0
		if _blink < 0.0:
			_blink = randf_range(2.0, 4.5)
	_blink_v = lerpf(_blink_v, want, clampf(delta * 30.0, 0.0, 1.0))
	if _face:
		_face.set_shader_parameter("blink", _blink_v)
		_face.set_shader_parameter("energy", 3.0 + _charge * 3.0)
	if _lamp:
		_lamp.emission_energy_multiplier = 7.0 if fmod(_t, 1.3) < 0.12 else 1.6
	var pulse: float = 1.0 + _charge * (1.0 + 0.6 * sin(_t * (8.0 + 20.0 * _charge)))
	for m: StandardMaterial3D in _glow_mats:
		m.emission_energy_multiplier = float(m.get_meta("base")) * pulse
	var pw: float = plume.power if plume else 0.0
	if _thruster:
		_thruster.emission_energy_multiplier = 1.0 + _charge * 6.0 + maxf(pw, lift) * 10.0
	for bp: RocketPlume in _boosters:
		bp.power = pw
	for fp: RocketPlume in _fans:
		fp.power = lift
	for i: int in _banners.size():
		var b: MeshInstance3D = _banners[i]
		var ph: float = float(b.get_meta("ph"))
		b.position.y = float(b.get_meta("y")) + sin(_t * 1.7 + ph) * 0.04
		b.rotation.z = sin(_t * 1.3 + ph) * 0.08
