class_name ShipModel
extends Node3D
## [ship] Lumi's travel ship, the Seedglider: a low, wide manta glider with big swept wings, twin
## engine nacelles, a faceted cyan canopy, layered pearl hull plates with crisp seams, tangerine
## accents, thin cyan light lines, small orange running lights and Lumi's C eyes on the nose sensor.
## Modelled in Blender (art/models/ship/build_ship.py -> ship.glb + ship_points.json) as modular
## parts on one base; ShipTiers.parts_for(look) picks which ones a tier carries, so the ship visibly
## grows from the Mk I one-seat glider to the Mk VII with its seed vault.
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
var _vault: StandardMaterial3D
var _rotors: Array[Node3D] = []
var _pulse_mats: Array[StandardMaterial3D] = []
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


## A ready-built ship at the player's current look (or `t`), for previews and
## other displays. `engines` 0..1 lights the main engines.
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
	_rotors.clear()
	_pulse_mats.clear()
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
	_build_tier_extras()
	if tier >= 7:
		_build_banners()
	set_legs(_legs_k)
	set_canopy(_canopy_k)


## [ship] Per-tier finish: each Mk looks cooler, not just bigger. Mk I is a plain satin glider;
## the panels darken to graphite, the pearl gets glossier, the metal more polished, the cyan line
## light brighter, and Mk VII gets champagne-gold fittings.
func _make_mats() -> void:
	_mats.clear()
	var t: int = tier
	var u: float = float(t - 1) / 6.0                      # 0 at Mk I .. 1 at Mk VII
	var pearl := _paint(ShipStyle.paint_color(), lerpf(0.38, 0.16, u))  # [ui7] Locker ship looks
	pearl.set_shader_parameter("pearl", lerpf(0.3, 0.95, u))
	pearl.set_shader_parameter("flake", lerpf(0.2, 0.7, u))
	pearl.set_shader_parameter("clearcoat_amt", lerpf(0.35, 1.0, u))
	_mats["paint"] = pearl
	# Accent plates: light grey (I-II), mid grey (III), graphite from IV, deep metallic graphite at VII.
	var pc: Color = [Color(0.82, 0.83, 0.84), Color(0.82, 0.83, 0.84), Color(0.78, 0.79, 0.8), Color(0.5, 0.52, 0.55),
		Color(0.2, 0.21, 0.24), Color(0.17, 0.18, 0.21), Color(0.15, 0.16, 0.19), Color(0.12, 0.125, 0.15)][t]
	var panel := _paint(pc, lerpf(0.4, 0.22, u))
	panel.set_shader_parameter("metallic", 0.05 if t < 4 else lerpf(0.3, 0.6, u))
	panel.set_shader_parameter("seam_dark", 0.55 if t < 4 else 0.25)
	panel.set_shader_parameter("clearcoat_amt", lerpf(0.3, 0.9, u))
	_mats["panel"] = panel
	_mats["accent"] = _paint(ShipStyle.trim_color(), lerpf(0.34, 0.2, u))  # [ui7]
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.09, 0.1, 0.115)
	trim.roughness = lerpf(0.45, 0.18, u)
	trim.metallic = lerpf(0.4, 0.9, u)
	_mats["trim"] = trim
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.025, 0.028, 0.035)
	dark.roughness = 0.25
	dark.metallic = 0.3
	_mats["dark"] = dark
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.95, 0.8, 0.5) if t >= 7 else Color(0.62, 0.64, 0.68)
	steel.roughness = lerpf(0.4, 0.15, u)
	steel.metallic = 0.95
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
	glass.emission_energy_multiplier = lerpf(0.2, 0.55, u)
	glass.rim_enabled = true
	glass.rim = 0.4
	_mats["glass"] = glass
	_mats["glow"] = _glow(ShipStyle.glow_color(), glow_energy(t))  # [ui7]
	_lamp = Mats.lamp(Color(1.0, 0.36, 0.12), 3.0)
	_mats["lamp"] = _lamp
	_thruster = Mats.lamp(ShipStyle.glow_color(), 1.0)  # [ui7]
	_thruster.set_meta("idle", lerpf(0.6, 3.5, u))
	_mats["thruster"] = _thruster
	_vault = Mats.lamp(Color(0.45, 1.0, 0.55), 1.6)
	_mats["vault"] = _vault
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


## Cyan line-light energy per tier (thin lines, brighter as the ship upgrades).
static func glow_energy(t: int) -> float:
	return [1.0, 0.9, 1.1, 1.4, 1.7, 2.0, 2.4, 2.8][clampi(t, 0, 7)]


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


## Painted livery only (a shaded stencil on the hull); [ship2] no glowing text.
func _build_marks() -> void:
	var lift_y: float = float(_pts.get("lift", 0.62))
	for side: float in [-1.0, 1.0]:
		var l := Mats.stencil("GREENFALL", 64, Color(0.24, 0.28, 0.34, 0.9))
		l.pixel_size = 0.0022
		l.position = Vector3(side * 0.855, 0.66 + lift_y, -0.2)
		l.rotation = Vector3(0, side * PI * 0.5, 0)
		add_child(l)


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


## [ship] Tier pieces built at runtime on top of the GLB parts: spinning lift-fan rotors (all),
## extra cyan line lights (II+), a dorsal blade fin and nose canards (III+), landing lights (IV+),
## engine halo rings (V+), a pulsing fold-ring light (VI+) and a seed-vault light spine (VII).
func _build_tier_extras() -> void:
	var t: int = tier
	var ly: float = float(_pts.get("lift", 0.62))
	var line: StandardMaterial3D = _mats["glow"]
	var pearl := StandardMaterial3D.new()
	pearl.albedo_color = PEARL
	pearl.roughness = 0.25
	pearl.clearcoat_enabled = true
	pearl.clearcoat = 0.8
	var tang := StandardMaterial3D.new()
	tang.albedo_color = ACCENT
	tang.roughness = 0.3
	tang.clearcoat_enabled = true
	# Lift-fan rotors (they spin; faster with the fans on).
	for f: Dictionary in _pts.get("fans", []):
		var fp: Array = f["pos"]
		for sx: float in [1.0, -1.0]:
			var rot := Node3D.new()
			rot.position = Vector3(float(fp[0]) * sx, float(fp[1]) + 0.09, float(fp[2]))
			add_child(rot)
			for k: int in 7:
				var a: float = TAU * k / 7.0
				var b := _box(rot, Vector3(0.28, 0.012, 0.075), _mats["steel"], Vector3(cos(a) * 0.17, 0, sin(a) * 0.17))
				b.rotation = Vector3(0.0, -a, 0.35)
			_box(rot, Vector3(0.1, 0.05, 0.1), _mats["trim"], Vector3.ZERO)
			if t >= 3:
				var ring := MeshInstance3D.new()
				ring.mesh = ProcMesh.torus(0.33, 0.342, 32, 3)
				ring.material_override = line
				ring.position = Vector3(float(fp[0]) * sx, float(fp[1]) + 0.165, float(fp[2]))
				add_child(ring)
			_rotors.append(rot)
	for sx2: float in [1.0, -1.0]:
		if t >= 2:  # trailing-edge line lights
			_strip(Vector3(sx2 * 0.75, 1.17, -2.46), Vector3(sx2 * 3.0, 1.0, -2.6), 0.012, line)
		if t >= 4:  # rear chine lights and landing lights under the nose
			_strip(Vector3(sx2 * 0.865, 1.09, -2.3), Vector3(sx2 * 0.865, 1.09, -0.15), 0.012, line)
			var ll := MeshInstance3D.new()
			ll.mesh = ProcMesh.sphere(0.045, 10, 5)
			ll.material_override = Mats.lamp(Color(1.0, 0.85, 0.6), 4.0)
			ll.position = Vector3(sx2 * 0.18, 0.42 + ly, 2.4 + _front)
			add_child(ll)
		if t >= 3:  # nose canards
			var poly := PackedVector2Array([Vector2(0.45, 2.55), Vector2(0.6, 2.15), Vector2(1.08, 1.78), Vector2(1.14, 1.9), Vector2(0.72, 2.4)])
			if sx2 < 0.0:
				var mp := PackedVector2Array()
				for i: int in range(poly.size() - 1, -1, -1):
					mp.append(Vector2(-poly[i].x, poly[i].y))
				poly = mp
			var c := MeshInstance3D.new()
			c.mesh = RocketModel.extrude(poly, 0.035)
			c.material_override = pearl
			c.rotation_degrees = Vector3(90, 0, 0)
			c.position = Vector3(0, 0.45 + ly, _front)
			add_child(c)
			_strip(Vector3(sx2 * 0.62, 0.47 + ly, 2.15 + _front), Vector3(sx2 * 1.08, 0.47 + ly, 1.8 + _front), 0.008, line)
	if t >= 3:  # dorsal blade fin with a lit leading edge and a tangerine tip
		var fin := MeshInstance3D.new()
		fin.mesh = RocketModel.extrude(PackedVector2Array([Vector2(-2.45, 1.42), Vector2(-0.7, 1.47), Vector2(-1.15, 1.8),
			Vector2(-2.05, 2.02), Vector2(-2.4, 1.97)]), 0.045)
		fin.material_override = pearl
		fin.rotation_degrees = Vector3(0, -90, 0)
		add_child(fin)
		var tip := MeshInstance3D.new()
		tip.mesh = RocketModel.extrude(PackedVector2Array([Vector2(-2.05, 2.02), Vector2(-2.4, 1.97), Vector2(-2.3, 1.86), Vector2(-1.95, 1.9)]), 0.05)
		tip.material_override = tang
		tip.rotation_degrees = Vector3(0, -90, 0)
		add_child(tip)
		_strip(Vector3(0, 1.5, -0.75), Vector3(0, 1.97, -2.0), 0.009, line)
	if t >= 5:  # halo rings on every nozzle
		for nz: Dictionary in _pts.get("nozzles", []):
			if not (str(nz["part"]) in ShipTiers.parts_for(t)):
				continue
			var p: Array = nz["pos"]
			var h := MeshInstance3D.new()
			var r: float = float(nz["r"]) * 1.45
			h.mesh = ProcMesh.torus(r, r + 0.014, 24, 3)
			h.material_override = line
			h.rotation_degrees = Vector3(90, 0, 0)
			h.position = Vector3(float(p[0]), float(p[1]), float(p[2]) + 0.05)
			add_child(h)
	if t >= 6:  # the fold ring's inner light, pulsing
		var rl := MeshInstance3D.new()
		rl.mesh = ProcMesh.torus(1.0, 1.012, 64, 3)
		var pm: StandardMaterial3D = Mats.lamp(Color(0.45, 0.9, 1.0), 2.5)
		pm.set_meta("base", 2.5)
		_pulse_mats.append(pm)
		rl.material_override = pm
		rl.rotation_degrees = Vector3(90, 0, 0)
		rl.scale = Vector3(1.4, 1.0, 0.84)
		rl.position = Vector3(0, 0.52 + ly, -1.975)
		add_child(rl)
	if t >= 7:  # seed-vault light spine
		var vm: StandardMaterial3D = Mats.lamp(Color(0.5, 1.0, 0.7), 2.5)
		vm.set_meta("base", 2.5)
		_pulse_mats.append(vm)
		var top: float = 0.86 - 0.03 + 0.42 + ly + 0.02
		_strip(Vector3(0, top, 0.15), Vector3(0, top, 2.05), 0.014, vm)


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


## A thin light line from a to b (ship space).
func _strip(a: Vector3, b: Vector3, w: float, mat: Material) -> MeshInstance3D:
	var mi := _box(self, Vector3(w, w, a.distance_to(b)), mat, (a + b) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var d: Vector3 = (b - a).normalized()
	var up: Vector3 = Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	var x: Vector3 = up.cross(d).normalized()
	mi.basis = Basis(x, d.cross(x), d)
	return mi


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
			q.size = Vector2(3.6 + k * 1.2, 0.09)
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
		_thruster.emission_energy_multiplier = float(_thruster.get_meta("idle", 1.0)) + _charge * 6.0 + maxf(pw, lift) * 10.0
	for bp: RocketPlume in _boosters:
		bp.power = pw
	var spin: float = (1.2 if tier >= 4 else 0.4) + lift * 30.0 + _charge * 6.0
	for r: Node3D in _rotors:
		r.rotate_y(delta * spin)
	for pm: StandardMaterial3D in _pulse_mats:
		pm.emission_energy_multiplier = float(pm.get_meta("base")) * (0.75 + 0.35 * sin(_t * 2.2)) * pulse
	if _vault:
		_vault.emission_energy_multiplier = 1.4 + 0.8 * sin(_t * 1.6)
	for fp: RocketPlume in _fans:
		fp.power = lift
	for i: int in _banners.size():
		var b: MeshInstance3D = _banners[i]
		var ph: float = float(b.get_meta("ph"))
		b.position.y = float(b.get_meta("y")) + sin(_t * 1.7 + ph) * 0.04
		b.rotation.z = sin(_t * 1.3 + ph) * 0.08
