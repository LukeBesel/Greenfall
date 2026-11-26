class_name ShipModel
extends Node3D
## [ship] Lumi's travel ship. [art5] It is now a used far-future short-hop shuttle: a lifting-body
## hull with seamed panels, a side hatch, framed glazing over a cockpit tub, heat-shield tiles
## underneath, stub wings with ducted lift engines, gimballed main engine bells stained by heat,
## oleo landing legs with foot pads, vents, attitude-jet ports, antennas, worn painted marks,
## riveted repair plates and a mismatched replacement door.
## Modelled in Blender in code (art/models/shuttle/build_shuttle.py -> shuttle.glb +
## shuttle_points.json + shuttle_decals.png) as modular parts on one base; ShipTiers.parts_for(look)
## picks which ones a tier carries, so the ship still grows from the Mk I to the Mk VII Homeward.
## The points file's `subs` names each part's moving pieces: <part>_foot (the gear's rods and pads,
## which slide as the gear takes the weight) and <part>_bell_N (an engine bell on its gimbal).
## Local frame: the nose points +Z, ground at y=0 with the gear down. VTOL: lift engines in the
## wings (set_lift) and main engines at the back (plume / boosters, `plume.power`).
## Motion with weight, all inside _process (nothing allocates per frame): the gear unloads and
## hangs when the ship leaves the ground and squats, rebounds and settles on touchdown
## (set_airborne); the engines' metal heats fast and cools slowly (the bells glow before the plume
## and for a while after); the bells swing on their gimbals; landing lamps come on with the engines.

const MODEL_PATH := "res://art/models/shuttle/shuttle.glb"
const POINTS_PATH := "res://art/models/shuttle/shuttle_points.json"
const DECALS_PATH := "res://art/models/shuttle/shuttle_decals.png"
const PAINT := preload("res://art/shaders/shuttle_hull.gdshader")
const TILE := preload("res://art/shaders/shuttle_tile.gdshader")
const METAL := preload("res://art/shaders/shuttle_metal.gdshader")
const DECAL := preload("res://art/shaders/shuttle_decal.gdshader")
const FACE := preload("res://art/shaders/bot_face.gdshader")
const GLOW := Color(0.3, 0.88, 1.0)
const ACCENT := Color(1.0, 0.5, 0.16)
const PEARL := Color(0.93, 0.93, 0.91)
## Front parts move forward by the mid section's length from Mk V (the hull gets longer).
const FRONT_PARTS: Array[String] = ["hull_front", "canopy_a", "canopy_b", "gear_n"]
## Legacy (vertical rocket) constants some callers still read.
const NOZZLE_Y: float = 1.0
const HATCH_Y: float = 1.5
## Gear travel (m): how far the legs are pressed in standing, how far they hang in the air.
const SQUAT_REST: float = 0.035
const SQUAT_HANG: float = -0.03
const SQUAT_MAX: float = 0.085

static var _parts: Dictionary = {}
static var _subs: Dictionary = {}  # part -> its moving pieces' names
static var _pts: Dictionary = {}

var tier: int = 1
var plume: RocketPlume
## The canopy hinge (opens for boarding); kept under the old name for callers.
var hatch: Node3D
var lift: float = 0.0
## 0 cold .. 1 running hot: the engines' metal (read by the hop's effects).
var heat: float = 0.0
## The belly lamp that lights the ground under the ship (off for display models).
var ground_lights: bool = true
var _boosters: Array[RocketPlume] = []
var _fans: Array[RocketPlume] = []
var _legs: Array[Node3D] = []
var _feet: Array[Node3D] = []
var _bells: Array[Node3D] = []
var _mats: Dictionary = {}
var _glow_mats: Array[StandardMaterial3D] = []
var _thruster: StandardMaterial3D
var _lamp: StandardMaterial3D
var _land: StandardMaterial3D
var _steel: ShaderMaterial
var _face: ShaderMaterial
var _vault: StandardMaterial3D
var _belly: OmniLight3D
var _rotors: Array[Node3D] = []
var _pulse_mats: Array[StandardMaterial3D] = []
var _banners: Array[MeshInstance3D] = []
var _ring_node: Node3D
var _kids: Array[Node3D] = []
var _kid_y: PackedFloat32Array = PackedFloat32Array()
var _front: float = 0.0
var _t: float = 0.0
var _blink: float = 2.0
var _blink_v: float = 0.0
var _charge: float = 0.0
var _legs_k: float = 1.0
var _canopy_k: float = 0.0
var _airborne: bool = false
var _squat: float = SQUAT_REST
var _squat_v: float = 0.0
var _squat_shown: float = 0.0
var _wake: float = 0.0
var _glow_col: Color = GLOW


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
	_subs = _pts.get("subs", {})


static func points() -> Dictionary:
	_load()
	return _pts


## How far the front parts sit forward at look t.
static func front_shift(t: int) -> float:
	return float(points().get("mid", 2.2)) if t >= 5 else 0.0


## Cockpit seat (local, unscaled): where Lumi drops in when boarding.
static func seat(t: int) -> Vector3:
	var h: Array = points().get("canopy_hinge_b" if t >= 3 else "canopy_hinge_a", [0, 1.5, 0])
	return Vector3(0.0, float(h[1]) - 0.42, float(h[2]) + 0.45 + front_shift(t))


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
	m.ground_lights = false
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
	_feet.clear()
	_bells.clear()
	_glow_mats.clear()
	_banners.clear()
	_rotors.clear()
	_pulse_mats.clear()
	_kids.clear()
	_ring_node = null
	_belly = null
	plume = null
	hatch = null
	_make_mats()
	_front = front_shift(tier)
	var fold: Dictionary = _pts.get("fold", {})
	var want: PackedStringArray = ShipTiers.parts_for(tier)
	for name: String in want:
		if not _parts.has(name):
			continue
		var pos: Vector3 = _parts[name]["pos"]
		if name in FRONT_PARTS:
			pos.z += _front
		if name.begins_with("canopy"):
			# Hinged at its rear edge (the mesh's own origin is the hinge).
			hatch = Node3D.new()
			hatch.name = "Canopy"
			hatch.position = pos
			add_child(hatch)
			_part(hatch, name, Vector3.ZERO)
		elif name.begins_with("gear_") or name.begins_with("skid_"):
			var piv := Node3D.new()
			piv.position = pos
			var fd: Array = fold.get(name, ["x", 1.45])
			piv.set_meta("axis", 2 if str(fd[0]) == "z" else 0)
			piv.set_meta("angle", float(fd[1]))
			add_child(piv)
			_part(piv, name, Vector3.ZERO)
			_legs.append(piv)
			for sub: String in _subs.get(name, []):
				_feet.append(_part(piv, sub, Vector3.ZERO))
		elif name == "ring":
			_ring_node = _part(self, name, pos)
		else:
			_part(self, name, pos)
			for sub: String in _subs.get(name, []):  # engine bells on their gimbals
				var bp := Node3D.new()
				bp.name = sub
				bp.position = _parts[sub]["pos"]
				add_child(bp)
				_part(bp, sub, Vector3.ZERO).name = "Bell"
				_bells.append(bp)
	_build_face()
	_build_marks()
	_build_engines(want)
	_build_tier_extras()
	if tier >= 7:
		_build_banners()
	if ground_lights:
		_belly = OmniLight3D.new()
		_belly.name = "BellyLamp"
		_belly.light_color = Color(1.0, 0.86, 0.66)
		_belly.omni_range = 7.0
		_belly.omni_attenuation = 1.4
		_belly.shadow_enabled = false
		_belly.position = Vector3(0, 0.62, 0.3 + _front * 0.5)
		add_child(_belly)
	for c: Node in get_children():
		if c is Node3D:
			_kids.append(c as Node3D)
	_kid_y.resize(_kids.size())
	for i: int in _kids.size():
		_kid_y[i] = _kids[i].position.y
	_squat_shown = 0.0
	_squat = SQUAT_HANG if _airborne else SQUAT_REST
	_squat_v = 0.0
	set_legs(_legs_k)
	set_canopy(_canopy_k)
	_apply_squat()
	_apply_heat()


## [ship] Per-tier finish: each Mk is better kept, not just bigger. [art5] The Mk I is a worn
## working craft (chipped edges, grime from the ground up, soot by the nozzles); later marks are
## cleaner and glossier, their line lights brighter, and Mk VII gets champagne-gold fittings.
func _make_mats() -> void:
	_mats.clear()
	var t: int = tier
	var u: float = float(t - 1) / 6.0                      # 0 at Mk I .. 1 at Mk VII
	var wear: float = lerpf(0.9, 0.4, u)
	var dirt: float = lerpf(1.0, 0.45, u)
	var pearl := _paint(ShipStyle.paint_color(), lerpf(0.5, 0.26, u), wear, dirt)  # [ui7] Locker ship looks
	pearl.set_shader_parameter("pearl", lerpf(0.08, 0.6, u))
	pearl.set_shader_parameter("flake", lerpf(0.2, 0.6, u))
	pearl.set_shader_parameter("clearcoat_amt", lerpf(0.18, 0.8, u))
	_mats["paint"] = pearl
	# Second paint: light grey (I-III), graphite from IV, deep metallic graphite at VII.
	var pc: Color = [Color(0.56, 0.57, 0.57), Color(0.56, 0.57, 0.57), Color(0.56, 0.57, 0.57), Color(0.52, 0.53, 0.54), Color(0.36, 0.37, 0.4),
		Color(0.2, 0.21, 0.24), Color(0.17, 0.18, 0.21), Color(0.13, 0.135, 0.16)][t]
	var panel := _paint(pc, lerpf(0.55, 0.3, u), wear, dirt)
	panel.set_shader_parameter("metallic", 0.05 if t < 4 else lerpf(0.3, 0.6, u))
	panel.set_shader_parameter("clearcoat_amt", lerpf(0.1, 0.7, u))
	_mats["panel"] = panel
	_mats["accent"] = _paint(ShipStyle.trim_color(), lerpf(0.46, 0.24, u), wear, dirt)  # [ui7]
	# A replaced panel and the riveted repair plates: another craft's faded teal, never repainted.
	var patch := _paint(Color(0.3, 0.46, 0.45), 0.62, minf(wear + 0.1, 1.0), dirt * 0.8)
	patch.set_shader_parameter("clearcoat_amt", 0.0)
	patch.set_shader_parameter("primer_color", Color(0.55, 0.3, 0.2))
	_mats["patch"] = patch
	var tile := ShaderMaterial.new()
	tile.shader = TILE
	_mats["tile"] = tile
	_steel = ShaderMaterial.new()
	_steel.shader = METAL
	_steel.set_shader_parameter("metal_color", Color(0.86, 0.72, 0.46) if t >= 7 else Color(0.56, 0.57, 0.6))
	_steel.set_shader_parameter("roughness", lerpf(0.4, 0.22, u))
	_mats["steel"] = _steel
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.085, 0.09, 0.1)
	trim.roughness = lerpf(0.55, 0.3, u)
	trim.metallic = lerpf(0.5, 0.85, u)
	_mats["trim"] = trim
	var dark := StandardMaterial3D.new()  # rubber: seals, pads, the cockpit liner
	dark.albedo_color = Color(0.03, 0.031, 0.034)
	dark.roughness = 0.82
	dark.metallic = 0.0
	_mats["dark"] = dark
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.1, 0.19, 0.22, 0.5)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.06
	glass.metallic = 0.6
	glass.metallic_specular = 0.9
	glass.rim_enabled = true
	glass.rim = 0.5
	glass.rim_tint = 0.3
	_mats["glass"] = glass
	_glow_col = ShipStyle.glow_color()
	_mats["glow"] = _glow(_glow_col, glow_energy(t))  # [ui7]
	_lamp = Mats.lamp(Color(1.0, 0.3, 0.1), 3.0)
	_mats["lamp"] = _lamp
	_land = Mats.lamp(Color(1.0, 0.93, 0.8), 0.6)
	_mats["land"] = _land
	# Bell throats and duct nozzles: sooty when cold, the glow colour when running, dull orange while cooling.
	_thruster = StandardMaterial3D.new()
	_thruster.albedo_color = Color(0.045, 0.04, 0.038)
	_thruster.roughness = 0.7
	_thruster.metallic = 0.4
	_thruster.emission_enabled = true
	_thruster.emission = _glow_col
	_thruster.emission_energy_multiplier = 0.0
	_mats["thruster"] = _thruster
	var dm := ShaderMaterial.new()
	dm.shader = DECAL
	dm.set_shader_parameter("atlas", load(DECALS_PATH))
	dm.set_shader_parameter("wear", lerpf(0.62, 0.2, u))
	_mats["decal"] = dm
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


func _paint(c: Color, rough: float, wear: float = 0.8, dirt: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAINT
	m.set_shader_parameter("paint_color", c)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("edge_wear", wear)
	m.set_shader_parameter("grime", dirt)
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


## Lumi's C eyes on the nose sensor bar (the same face shader as Lumi and the robots).
func _build_face() -> void:
	var sn: Dictionary = _pts.get("sensor", {})
	var sp: Array = sn.get("pos", [0, 1.3, 2.68])
	var v := Node3D.new()
	v.name = "Sensor"
	v.position = Vector3(float(sp[0]), float(sp[1]), float(sp[2]) + _front)
	v.rotation = Vector3(deg_to_rad(float(sn.get("pitch", 30.0)) - 90.0), PI, 0)
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
	bm.size = Vector3(0.27, 0.062, 0.006)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = _face
	v.add_child(mi)


## Painted livery only (a shaded stencil on the hull); [ship2] no glowing text.
func _build_marks() -> void:
	for mk: Dictionary in _pts.get("marks", []):
		var p: Array = mk["pos"]
		var side: float = float(mk.get("side", 1))
		var l := Mats.stencil("GREENFALL", 64, Color(0.2, 0.22, 0.26, 0.8))
		l.pixel_size = 0.0016
		l.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
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
			lp.scale_len = 0.3
			lp.use_light = sx > 0.0
			lp.position = Vector3(float(fp[0]) * sx, float(f.get("y_nozzle", float(fp[1]) - 0.05)), float(fp[2]))
			add_child(lp)
			_fans.append(lp)
	if plume == null:  # never null for callers
		plume = RocketPlume.new()
		add_child(plume)


## [ship] Tier pieces built at runtime on top of the GLB parts: the lift engines' turbine rotors
## (all), line lights where shuttle_points.json puts them (II+), engine halo rings (V+), a pulsing
## fold-ring light (VI+) and a seed-vault light spine (VII).
func _build_tier_extras() -> void:
	var t: int = tier
	var line: StandardMaterial3D = _mats["glow"]
	for f: Dictionary in _pts.get("fans", []):
		var fp: Array = f["pos"]
		for sx: float in [1.0, -1.0]:
			var rot: Node3D = _part(self, "rotor", Vector3.ZERO) if _parts.has("rotor") else Node3D.new()
			rot.position = Vector3(float(fp[0]) * sx, float(f.get("y_rotor", float(fp[1]) + 0.09)), float(fp[2]))
			if rot.get_parent() == null:
				add_child(rot)
			_rotors.append(rot)
	for st: Dictionary in _pts.get("strips", []):
		if t < int(st.get("tier", 2)):
			continue
		var a2: Array = st["a"]
		var b2: Array = st["b"]
		for sx2: float in [1.0, -1.0]:
			_strip(Vector3(sx2 * float(a2[0]), float(a2[1]), float(a2[2])), Vector3(sx2 * float(b2[0]), float(b2[1]), float(b2[2])), float(st.get("w", 0.012)), line)
	if t >= 5:  # halo rings on every nozzle
		for nz: Dictionary in _pts.get("nozzles", []):
			if not (str(nz["part"]) in ShipTiers.parts_for(t)):
				continue
			var p: Array = nz["pos"]
			var h := MeshInstance3D.new()
			var r: float = float(nz["r"]) * 1.25
			h.mesh = ProcMesh.torus(r, r + 0.012, 24, 3)
			h.material_override = line
			h.rotation_degrees = Vector3(90, 0, 0)
			h.position = Vector3(float(p[0]), float(p[1]), float(p[2]) + 0.03)
			add_child(h)
	if t >= 6 and _pts.has("ring_light"):  # the fold ring's inner light, pulsing
		var rd: Dictionary = _pts["ring_light"]
		var rp: Array = rd["pos"]
		var rs: Array = rd["scale"]
		var rl := MeshInstance3D.new()
		rl.mesh = ProcMesh.torus(1.0, 1.012, 64, 3)
		var pm: StandardMaterial3D = Mats.lamp(Color(0.45, 0.9, 1.0), 2.5)
		pm.set_meta("base", 2.5)
		_pulse_mats.append(pm)
		rl.material_override = pm
		rl.rotation_degrees = Vector3(90, 0, 0)
		rl.scale = Vector3(float(rs[0]), 1.0, float(rs[1]))
		rl.position = Vector3(float(rp[0]), float(rp[1]), float(rp[2]))
		add_child(rl)
	if t >= 7 and _pts.has("vault_spine"):  # seed-vault light spine
		var vm: StandardMaterial3D = Mats.lamp(Color(0.5, 1.0, 0.7), 2.5)
		vm.set_meta("base", 2.5)
		_pulse_mats.append(vm)
		var va: Array = (_pts["vault_spine"] as Dictionary)["a"]
		var vb: Array = (_pts["vault_spine"] as Dictionary)["b"]
		_strip(Vector3(float(va[0]), float(va[1]), float(va[2])), Vector3(float(vb[0]), float(vb[1]), float(vb[2])), 0.014, vm)


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


## 1 = gear down (standing), 0 = folded against the hull.
func set_legs(k: float) -> void:
	_legs_k = k
	for leg: Node3D in _legs:
		var a: float = (1.0 - k) * float(leg.get_meta("angle", 1.45))
		if int(leg.get_meta("axis", 0)) == 2:
			leg.rotation.z = a
		else:
			leg.rotation.x = a


## 0..1: canopy opened for boarding.
func set_canopy(k: float) -> void:
	_canopy_k = k
	if hatch:
		hatch.rotation.x = -k * 0.95


## 0..1: VTOL lift engines.
func set_lift(k: float) -> void:
	lift = k


## [art5] Whether the ship is off the ground. Leaving it, the gear unloads and hangs; coming back
## (`sink` = how hard, 0..1) the legs press in, rebound and settle under the ship's weight.
func set_airborne(on: bool, sink: float = 0.6) -> void:
	if on == _airborne:
		return
	_airborne = on
	if not on:
		_squat_v = 0.55 * clampf(sink, 0.0, 1.5)


## How far the gear is pressed in right now (m; tests and effects).
func squat() -> float:
	return _squat


func _apply_squat() -> void:
	if absf(_squat - _squat_shown) < 0.0004:
		return
	_squat_shown = _squat
	for i: int in _kids.size():
		_kids[i].position.y = _kid_y[i] - _squat
	for f: Node3D in _feet:
		f.position.y = _squat


func _apply_heat() -> void:
	var run: float = maxf(maxf(plume.power if plume else 0.0, lift), _charge * 0.6)
	if _thruster:
		_thruster.emission = Color(1.0, 0.32, 0.08).lerp(_glow_col, clampf(run * 1.6, 0.0, 1.0))
		_thruster.emission_energy_multiplier = run * 9.0 + heat * heat * 1.6
	if _steel:
		_steel.set_shader_parameter("glow", heat)


func _process(delta: float) -> void:
	_t += delta
	_blink -= delta
	var want: float = 0.0
	if _blink < 0.12:
		want = 1.0
		if _blink < 0.0:
			_blink = randf_range(2.0, 4.5)
	_blink_v = lerpf(_blink_v, want, clampf(delta * 30.0, 0.0, 1.0))
	var pw: float = plume.power if plume else 0.0
	var run: float = maxf(pw, lift)
	# Awake while the engines run or charge; the ship dozes on its pad (dim instruments, a slow beacon).
	_wake = move_toward(_wake, 1.0 if (run > 0.01 or _charge > 0.01) else 0.0, delta * (4.0 if run > 0.01 else 0.35))
	if _face:
		_face.set_shader_parameter("blink", _blink_v)
		_face.set_shader_parameter("energy", 1.6 + _wake * 1.4 + _charge * 3.0)
	if _lamp:
		_lamp.emission_energy_multiplier = 7.0 if fmod(_t, lerpf(2.6, 1.3, _wake)) < 0.12 else lerpf(0.5, 1.6, _wake)
	var pulse: float = lerpf(0.45, 1.0, _wake) + _charge * (1.0 + 0.6 * sin(_t * (8.0 + 20.0 * _charge)))
	for m: StandardMaterial3D in _glow_mats:
		m.emission_energy_multiplier = float(m.get_meta("base")) * pulse
	# Metal heats fast and cools slowly: the bells glow before the plume shows and long after it stops.
	var hot: float = maxf(run, _charge * 0.5)
	heat = move_toward(heat, hot, delta * (5.0 if hot > heat else 0.16))
	_apply_heat()
	if _land:
		_land.emission_energy_multiplier = lerpf(0.5, 9.0, _wake)
	if _belly:
		_belly.light_energy = lerpf(0.55, 2.6, _wake)
	for bp: RocketPlume in _boosters:
		bp.power = pw
	var spin: float = (1.2 if tier >= 4 else 0.4) + lift * 34.0 + _charge * 6.0
	for r: Node3D in _rotors:
		r.rotate_y(delta * spin)
	# Bells on their gimbals: they swing down to help the lift engines, and tremble under thrust.
	if not _bells.is_empty() and (run > 0.001 or absf(_bells[0].rotation.x) > 0.0005):
		var tilt: float = -0.3 * lift * (1.0 - pw)
		for i: int in _bells.size():
			var b: Node3D = _bells[i]
			b.rotation.x = lerpf(b.rotation.x, tilt + 0.012 * run * sin(_t * 31.0 + float(i) * 1.7), clampf(delta * 7.0, 0.0, 1.0))
			b.rotation.y = 0.01 * run * sin(_t * 27.0 + float(i) * 2.9)
	# The gear: a spring and damper toward where the weight puts it.
	var target: float = SQUAT_HANG if _airborne else SQUAT_REST * (1.0 - 0.7 * lift)
	if absf(target - _squat) > 0.0002 or absf(_squat_v) > 0.002:
		var dt: float = minf(delta, 0.05)
		_squat_v += ((target - _squat) * 150.0 - _squat_v * 11.0) * dt
		_squat = clampf(_squat + _squat_v * dt, SQUAT_HANG, SQUAT_MAX)
		_apply_squat()
	for pm: StandardMaterial3D in _pulse_mats:
		pm.emission_energy_multiplier = float(pm.get_meta("base")) * (0.75 + 0.35 * sin(_t * 2.2)) * pulse
	if _vault:
		_vault.emission_energy_multiplier = 1.4 + 0.8 * sin(_t * 1.6)
	for fp: RocketPlume in _fans:
		fp.power = clampf((lift - 0.2) / 0.8, 0.0, 1.0)  # the nozzles glow before the jets show
	for i: int in _banners.size():
		var b: MeshInstance3D = _banners[i]
		var ph: float = float(b.get_meta("ph"))
		b.position.y = float(b.get_meta("y")) + sin(_t * 1.7 + ph) * 0.04
		b.rotation.z = sin(_t * 1.3 + ph) * 0.08
