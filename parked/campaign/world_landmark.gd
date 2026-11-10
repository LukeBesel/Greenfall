class_name WorldLandmark
extends Node3D
## [worlds2] One big silhouette per Cradle Mode world type, out past the city in the base's
## default view (data/world_looks.json "landmark"):
##   cryo_spire     Ice Moon: the old seed silo, iced to the waist
##   sun_tower      Desert World: a solar tower in a field of heliostat mirrors, half of them down
##   surge_barrier  Ocean World: a row of steel-hooded storm-surge gates
##   bloom_stack    Marsh World: a cooling tower gone soft, giant shelf fungi up its sides
##   gantry         Rust World: a colossal ship-breaking gantry crane
## Three layers follow the base level: "Ruin" (fallen parts, levels 1-2), "Mended" (what was put
## back, level 4+) and "Glow" (thin, warm or cool trim lights, level 3+). Static geometry merged
## per material; no collision (it stands far outside the play area).

const MIN_D: float = 88.0
const MAX_D: float = 135.0

var kind: String = ""
var level: int = 1
var _parts: Dictionary = {}   # layer -> {mat key -> Array of ProcMesh parts}
var _layer: String = "Base"
var _mats: Dictionary = {}
var _rng := RandomNumberGenerator.new()


static func make(p_kind: String, at: Vector3, yaw: float, seed_v: int, p_level: int) -> WorldLandmark:
	var lm := WorldLandmark.new()
	lm.name = "WorldLandmark"
	lm.kind = p_kind
	lm.position = at
	lm.rotation.y = yaw
	lm._rng.seed = seed_v
	lm._build()
	lm.set_level(p_level)
	return lm


## A spot in the default view (toward -Z), clear of the field and of building lots (pure given
## the layout and field). Falls back to straight ahead.
static func find_spot(layout: CityLayout, field: HexField, seed_v: int, foot: float = 14.0) -> Vector3:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var side: float = -1.0 if r.randf() < 0.5 else 1.0
	for attempt: int in 80:
		var ang: float = -PI * 0.5 + side * r.randf_range(0.15, 0.55 + attempt * 0.006)
		var dist: float = r.randf_range(MIN_D, MIN_D + 20.0 + attempt * 0.4)
		var p := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var ok: bool = true
		for o: Vector3 in [Vector3.ZERO, Vector3(foot, 0, foot), Vector3(-foot, 0, foot), Vector3(foot, 0, -foot), Vector3(-foot, 0, -foot)]:
			if field and field.hex_at(p + o) >= 0:
				ok = false
				break
		if ok:
			return p
	return Vector3(side * 30.0, 0, -110.0)


func set_level(l: int) -> void:
	level = l
	for c: Node in get_children():
		match String(c.name):
			"Ruin":
				(c as Node3D).visible = l < 3
			"Mended":
				(c as Node3D).visible = l >= 4
			"Glow":
				(c as Node3D).visible = l >= 3


## Weathering overlay on every surface (the same coat the city wears).
func set_overlay(m: Material) -> void:
	for c: Node in get_children():
		for mi: Node in c.get_children():
			if mi is MeshInstance3D and String(mi.name) != "glow":
				(mi as MeshInstance3D).material_overlay = m


# --- Building ---------------------------------------------------------------------------

func _build() -> void:
	match kind:
		"cryo_spire":
			_cryo_spire()
		"sun_tower":
			_sun_tower()
		"surge_barrier":
			_surge_barrier()
		"bloom_stack":
			_bloom_stack()
		_:
			_gantry()
	_flush()


func _at(nm: String) -> void:
	_layer = nm


func _add(key: String, mesh: Mesh, xf: Transform3D, col: Color = Color.WHITE) -> void:
	if not _parts.has(_layer):
		_parts[_layer] = {}
	var d: Dictionary = _parts[_layer]
	if not d.has(key):
		d[key] = []
	(d[key] as Array).append(ProcMesh.part(mesh, xf, col))


## A beam between two points (box of the given thickness).
func _beam(key: String, a: Vector3, b: Vector3, t: float, col: Color = Color.WHITE) -> void:
	var mid: Vector3 = (a + b) * 0.5
	var len_: float = a.distance_to(b)
	var y: Vector3 = (b - a).normalized()
	var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z: Vector3 = x.cross(y).normalized()
	_add(key, ProcMesh.box(Vector3(t, len_, t)), Transform3D(Basis(x, y, z), mid), col)


func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	if key == "glow":  # thin trim lights: the vertex colour a little over the glow threshold
		var sm := ShaderMaterial.new()
		sm.shader = _glow_shader()
		_mats[key] = sm
		return sm
	var m: StandardMaterial3D
	match key:
		"concrete":
			m = AssetLib.pbr_material("concrete_wall_008", 0.08, Color.WHITE, true)
		"white":
			m = AssetLib.pbr_material("painted_concrete", 0.08, Color.WHITE, true)
		"metal":
			m = AssetLib.pbr_material("metal_plate", 0.12, Color.WHITE, true)
		"rust":
			m = AssetLib.pbr_material("rusty_metal_02", 0.07, Color.WHITE, true)
		"ice":
			m = StandardMaterial3D.new()
			m.roughness = 0.18
			m.metallic_specular = 0.7
		"mirror":
			m = StandardMaterial3D.new()
			m.metallic = 0.9
			m.roughness = 0.08
		_:
			m = StandardMaterial3D.new()
			m.roughness = 0.85
	m.vertex_color_use_as_albedo = true
	if m.uv1_triplanar:
		m.uv1_world_triplanar = true
	_mats[key] = m
	return m


static var _glow: Shader


static func _glow_shader() -> Shader:
	if _glow == null:
		_glow = Shader.new()
		_glow.code = "shader_type spatial;\nrender_mode unshaded, shadows_disabled;\nuniform float energy = 1.5;\nvoid fragment() { ALBEDO = COLOR.rgb * energy; }\n"
	return _glow


func _flush() -> void:
	for layer: String in _parts:
		var node := Node3D.new()
		node.name = layer
		add_child(node)
		var d: Dictionary = _parts[layer]
		for key: String in d:
			var mi := MeshInstance3D.new()
			mi.name = key
			mi.mesh = ProcMesh.merge(d[key])
			mi.material_override = _mat(key)
			if key == "glow":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mi.visibility_range_end = 700.0
			node.add_child(mi)
	_parts.clear()


# --- Ice Moon: the seed silo -------------------------------------------------------------

func _cryo_spire() -> void:
	var shell := Color(0.86, 0.9, 0.95)
	var dark := Color(0.32, 0.36, 0.42)
	var ice := Color(0.8, 0.9, 1.0)
	_at("Base")
	_add("concrete", ProcMesh.cyl(10.0, 11.0, 3.0, 24), ProcMesh.xf(Vector3(0, 1.5, 0)), Color(0.78, 0.8, 0.84))
	_add("metal", ProcMesh.cyl(3.2, 5.6, 48.0, 24), ProcMesh.xf(Vector3(0, 27.0, 0)), shell)
	for k: int in 4:
		var a: float = TAU * k / 4.0 + 0.4
		var d0 := Vector3(cos(a), 0, sin(a))
		_beam("metal", d0 * 6.2 + Vector3(0, 3, 0), d0 * 3.7 + Vector3(0, 49, 0), 1.1, dark)
	for y: float in [15.0, 28.0, 41.0]:
		var r: float = lerpf(5.6, 3.2, (y - 3.0) / 48.0)
		_add("metal", ProcMesh.torus(r - 0.1, r + 0.55, 28, 6), ProcMesh.xf(Vector3(0, y, 0)), dark)
	_add("metal", ProcMesh.cyl(0.5, 3.2, 8.0, 20), ProcMesh.xf(Vector3(0, 55.0, 0)), shell)
	_add("metal", ProcMesh.box(Vector3(3.0, 2.2, 1.0)), ProcMesh.xf(Vector3(0, 6.0, 5.4)), dark)  # hatch
	# Ice to the waist: frozen runs down the shaft and a skirt of ice at the foot.
	for k: int in 9:
		var a2: float = TAU * k / 9.0 + _rng.randf_range(-0.2, 0.2)
		var h: float = _rng.randf_range(5.0, 14.0)
		var rr: float = lerpf(5.6, 3.2, h / 48.0 * 0.5) + 0.3
		_add("ice", ProcMesh.cyl(0.4, _rng.randf_range(1.6, 2.8), h, 7), ProcMesh.xf(Vector3(cos(a2) * rr, 3.0 + h * 0.5, sin(a2) * rr)), ice)
	_add("ice", ProcMesh.cyl(7.0, 12.5, 1.6, 20), ProcMesh.xf(Vector3(0, 0.6, 0)), ice)
	_at("Ruin")
	# The mast came down long ago; it lies in the ice.
	_beam("metal", Vector3(9.0, 0.6, 3.0), Vector3(19.0, 1.8, -2.0), 0.35, dark)
	for k: int in 5:
		var a3: float = _rng.randf() * TAU
		_add("ice", ProcMesh.cyl(0.3, _rng.randf_range(1.0, 2.2), _rng.randf_range(3.0, 7.0), 6), ProcMesh.xf(Vector3(cos(a3) * 8.0, 2.5, sin(a3) * 8.0)), ice)
	_at("Mended")
	_add("metal", ProcMesh.cyl(0.14, 0.24, 11.0, 6), ProcMesh.xf(Vector3(0, 64.5, 0)), dark)
	_add("metal", ProcMesh.box(Vector3(2.4, 0.15, 0.15)), ProcMesh.xf(Vector3(0, 66.0, 0)), dark)
	_at("Glow")
	for y2: float in [15.0, 28.0, 41.0]:
		var r2: float = lerpf(5.6, 3.2, (y2 - 3.0) / 48.0)
		_add("glow", ProcMesh.torus(r2 + 0.5, r2 + 0.62, 32, 4), ProcMesh.xf(Vector3(0, y2 + 0.45, 0)), Color(0.45, 0.85, 1.0))
	_add("glow", ProcMesh.sphere(0.35, 8, 4), ProcMesh.xf(Vector3(0, 70.2, 0)), Color(1.0, 0.3, 0.25))


# --- Desert World: the solar tower ------------------------------------------------------

func _sun_tower() -> void:
	var bleached := Color(0.95, 0.9, 0.82)
	var steel := Color(0.5, 0.48, 0.45)
	_at("Base")
	_add("concrete", ProcMesh.cyl(2.7, 3.6, 56.0, 20), ProcMesh.xf(Vector3(0, 28.0, 0)), bleached)
	_add("concrete", ProcMesh.cyl(5.5, 6.5, 2.0, 20), ProcMesh.xf(Vector3(0, 1.0, 0)), bleached)
	_add("metal", ProcMesh.box(Vector3(7.5, 9.0, 7.5)), ProcMesh.xf(Vector3(0, 61.0, 0)), steel)
	_add("metal", ProcMesh.box(Vector3(9.0, 0.8, 9.0)), ProcMesh.xf(Vector3(0, 56.2, 0)), steel.darkened(0.2))
	_add("metal", ProcMesh.box(Vector3(8.5, 0.6, 8.5)), ProcMesh.xf(Vector3(0, 65.8, 0)), steel.darkened(0.2))
	for k: int in 4:
		var a: float = TAU * k / 4.0 + PI * 0.25
		_beam("metal", Vector3(cos(a) * 4.4, 56.5, sin(a) * 4.4), Vector3(cos(a) * 4.4, 65.5, sin(a) * 4.4), 0.35, steel.darkened(0.3))
	# Heliostats in rings around the foot, each tilted toward the receiver; some are down.
	var down: Array = []
	for ring: int in 3:
		var rr: float = 16.0 + ring * 7.0
		var n: int = 10 + ring * 4
		for k: int in n:
			var a2: float = TAU * (k + 0.5 * ring) / n
			var p := Vector3(cos(a2) * rr, 0, sin(a2) * rr)
			var fallen: bool = _rng.randf() < 0.4
			if fallen:
				down.append(p)
				continue
			_heliostat(p)
	_at("Ruin")
	for p2: Vector3 in down:
		_add("concrete", ProcMesh.cyl(0.14, 0.16, 2.2, 5), ProcMesh.xf(p2 + Vector3(0, 1.1, 0)), steel)
		_add("mirror", ProcMesh.box(Vector3(3.2, 0.1, 2.2)), Transform3D(Basis.from_euler(Vector3(_rng.randf_range(0.1, 0.4), _rng.randf() * TAU, 0.0)), p2 + Vector3(1.6, 0.3, 0.4)), Color(0.55, 0.6, 0.66))
	_at("Mended")
	for p3: Vector3 in down:
		_heliostat(p3)
	_at("Glow")
	for y: float in [57.0, 65.2]:
		_add("glow", ProcMesh.box(Vector3(9.2, 0.14, 9.2)), ProcMesh.xf(Vector3(0, y, 0)), Color(1.0, 0.82, 0.55))
	_add("glow", ProcMesh.sphere(0.3, 8, 4), ProcMesh.xf(Vector3(0, 67.0, 0)), Color(1.0, 0.3, 0.25))


func _heliostat(p: Vector3) -> void:
	var to: Vector3 = (Vector3(0, 60, 0) - p).normalized()
	var yaw: float = atan2(to.x, to.z)
	_add("concrete", ProcMesh.cyl(0.14, 0.16, 2.2, 5), ProcMesh.xf(p + Vector3(0, 1.1, 0)), Color(0.6, 0.58, 0.55))
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.75)
	_add("mirror", ProcMesh.box(Vector3(3.2, 0.1, 2.2)), Transform3D(b, p + Vector3(0, 2.3, 0)), Color(0.6, 0.68, 0.76))


# --- Ocean World: the storm-surge barrier -----------------------------------------------

func _surge_barrier() -> void:
	var steel := Color(0.82, 0.84, 0.86)
	var conc := Color(0.7, 0.72, 0.72)
	var dark := Color(0.25, 0.28, 0.3)
	var piers: int = 4
	var gap: float = 22.0
	var x0: float = -gap * (piers - 1) * 0.5
	_at("Base")
	for i: int in piers:
		var x: float = x0 + i * gap
		_add("concrete", ProcMesh.box(Vector3(6.0, 8.0, 18.0)), ProcMesh.xf(Vector3(x, 4.0, 0)), conc)
		# The hood: a rounded shell with a peaked ridge and a fin, steel-clad.
		_add("metal", ProcMesh.cyl(4.4, 4.4, 17.0, 16), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, 10.0, 0)), steel)
		_add("metal", ProcMesh.box(Vector3(4.6, 4.6, 16.5)), Transform3D(Basis(Vector3.FORWARD, PI * 0.25), Vector3(x, 12.4, 0)), steel)
		_add("metal", ProcMesh.box(Vector3(0.35, 5.0, 11.0)), ProcMesh.xf(Vector3(x, 17.5, 0)), steel.darkened(0.08))
		for k: int in 5:
			_add("metal", ProcMesh.box(Vector3(9.0, 0.25, 0.3)), ProcMesh.xf(Vector3(x, 10.0 + (k % 2) * 0.1, -6.5 + k * 3.25)), dark)
		if i < piers - 1:
			# Gate arm between piers (the gates rise from the sea bed).
			_add("metal", ProcMesh.box(Vector3(gap - 6.0, 2.2, 1.2)), ProcMesh.xf(Vector3(x + gap * 0.5, 6.6, 4.5)), dark)
	# A navigation mast at one end.
	var mx: float = x0 - 9.0
	_add("white", ProcMesh.cyl(0.9, 1.4, 26.0, 12), ProcMesh.xf(Vector3(mx, 13.0, 0)), Color(0.94, 0.94, 0.92))
	for k2: int in 3:
		_add("rust", ProcMesh.cyl(1.05 - k2 * 0.1, 1.15 - k2 * 0.1, 2.0, 12), ProcMesh.xf(Vector3(mx, 6.0 + k2 * 7.0, 0)), Color(0.8, 0.25, 0.2))
	_add("metal", ProcMesh.cyl(1.6, 1.6, 0.4, 12), ProcMesh.xf(Vector3(mx, 26.2, 0)), dark)
	_at("Ruin")
	# One gate sprung off its pivots, half sunk.
	_add("metal", ProcMesh.box(Vector3(gap - 6.0, 2.2, 1.2)), Transform3D(Basis(Vector3.FORWARD, 0.22), Vector3(x0 + gap * 1.5, 1.4, 9.0)), dark)
	_at("Mended")
	_add("metal", ProcMesh.box(Vector3(gap * (piers - 1), 0.5, 2.0)), ProcMesh.xf(Vector3(0, 8.3, -6.0)), steel.darkened(0.15))  # a walkway over the gates
	_at("Glow")
	for i2: int in piers:
		_add("glow", ProcMesh.sphere(0.32, 8, 4), ProcMesh.xf(Vector3(x0 + i2 * gap, 20.2, 0)), Color(1.0, 0.3, 0.25) if i2 % 2 == 0 else Color(0.3, 1.0, 0.5))
	_add("glow", ProcMesh.box(Vector3(gap * (piers - 1), 0.1, 0.12)), ProcMesh.xf(Vector3(0, 8.62, -5.0)), Color(0.55, 0.85, 1.0))
	_add("glow", ProcMesh.sphere(0.6, 10, 5), ProcMesh.xf(Vector3(mx, 27.0, 0)), Color(1.0, 0.9, 0.7))


# --- Marsh World: the overgrown cooling tower --------------------------------------------

func _bloom_stack() -> void:
	var conc := Color(0.62, 0.64, 0.58)
	var cap_a := Color(0.78, 0.64, 0.46)
	var cap_b := Color(0.58, 0.62, 0.42)
	var vine := Color(0.16, 0.26, 0.1)
	_at("Base")
	_add("concrete", ProcMesh.cyl(13.0, 19.0, 30.0, 32), ProcMesh.xf(Vector3(0, 15.0, 0)), conc)
	_add("concrete", ProcMesh.cyl(15.0, 13.0, 14.0, 32), ProcMesh.xf(Vector3(0, 37.0, 0)), conc)
	_add("concrete", ProcMesh.torus(14.6, 15.6, 32, 6), ProcMesh.xf(Vector3(0, 44.0, 0)), conc.darkened(0.15))
	# Legs at the foot (the air inlets).
	for k: int in 16:
		var a: float = TAU * k / 16.0
		_beam("concrete", Vector3(cos(a) * 19.0, 0, sin(a) * 19.0), Vector3(cos(a) * 18.6, 2.6, sin(a) * 18.6), 0.9, conc.darkened(0.25))
	# Shelf fungi up the sides, the big ones low, and vines hanging from the lip.
	for k2: int in 22:
		var a2: float = _rng.randf() * TAU
		var y: float = _rng.randf_range(4.0, 40.0)
		var r_wall: float = lerpf(19.0, 13.0, y / 30.0) if y < 30.0 else lerpf(13.0, 15.0, (y - 30.0) / 14.0)
		var s: float = lerpf(5.5, 2.0, y / 40.0) * _rng.randf_range(0.7, 1.2)
		var p := Vector3(cos(a2) * (r_wall + s * 0.35), y, sin(a2) * (r_wall + s * 0.35))
		_add("fungus", ProcMesh.hemisphere(s, 14, 4), Transform3D(Basis(Vector3.UP, -a2).scaled(Vector3(1.0, 0.32, 0.8)), p), cap_a if _rng.randf() < 0.6 else cap_b)
		_add("fungus", ProcMesh.cyl(s * 0.98, s * 0.98, 0.15, 14), Transform3D(Basis(Vector3.UP, -a2).scaled(Vector3(1.0, 1.0, 0.8)), p - Vector3(0, 0.05, 0)), Color(0.42, 0.36, 0.28))
	for k3: int in 40:
		var a3: float = _rng.randf() * TAU
		var len_: float = _rng.randf_range(6.0, 22.0)
		var top := Vector3(cos(a3) * 15.3, 44.0, sin(a3) * 15.3)
		_beam("fungus", top, top + Vector3(cos(a3) * 0.8, -len_, sin(a3) * 0.8), 0.22, vine)
	_at("Ruin")
	for k4: int in 7:
		var a4: float = _rng.randf_range(-0.6, 0.6) + PI * 0.5
		_add("concrete", ProcMesh.box(Vector3(_rng.randf_range(2, 4), _rng.randf_range(1, 2.5), _rng.randf_range(2, 4))), Transform3D(Basis.from_euler(Vector3(_rng.randf(), _rng.randf() * 3, _rng.randf())), Vector3(cos(a4) * 21.0, 0.8, sin(a4) * 21.0)), conc)
	_at("Mended")
	_add("fungus", ProcMesh.torus(15.0, 16.4, 36, 5), ProcMesh.xf(Vector3(0, 44.6, 0)), Color(0.28, 0.5, 0.2))  # a planted terrace on the lip
	_at("Glow")
	# Faint bioluminescence under the biggest caps (thin rims).
	_rng.seed = _rng.seed + 1
	for k5: int in 8:
		var a5: float = TAU * k5 / 8.0 + 0.3
		var y5: float = 6.0 + (k5 % 3) * 7.0
		var r5: float = lerpf(19.0, 13.0, y5 / 30.0) + 1.0
		_add("glow", ProcMesh.torus(1.6, 1.75, 16, 3), Transform3D(Basis(Vector3.UP, -a5).scaled(Vector3(1.0, 1.0, 0.8)), Vector3(cos(a5) * r5, y5 - 0.3, sin(a5) * r5)), Color(0.45, 1.0, 0.75))


# --- Rust World: the ship-breaking gantry ----------------------------------------------

func _gantry() -> void:
	var rust := Color(0.85, 0.7, 0.62)
	var dark := Color(0.3, 0.26, 0.24)
	var span: float = 30.0
	var h: float = 44.0
	_at("Base")
	for sx: float in [-span, span]:
		# A-frame leg: two raked columns, bracing, a bogie on the ground.
		var a := Vector3(sx, 0, -7.0)
		var b := Vector3(sx, 0, 7.0)
		var t := Vector3(sx, h, 0)
		_beam("rust", a, t, 1.8, rust)
		_beam("rust", b, t, 1.8, rust)
		for k: int in 4:
			var f0: float = 0.15 + k * 0.2
			var f1: float = f0 + 0.2
			_beam("rust", a.lerp(t, f0), b.lerp(t, f1), 0.5, rust.darkened(0.1))
			_beam("rust", b.lerp(t, f0), a.lerp(t, f1), 0.5, rust.darkened(0.1))
		_add("rust", ProcMesh.box(Vector3(3.0, 2.0, 18.0)), ProcMesh.xf(Vector3(sx, 1.0, 0)), dark)
	# The girder with its lattice and the trolley.
	_add("rust", ProcMesh.box(Vector3(span * 2.0 + 14.0, 3.6, 3.2)), ProcMesh.xf(Vector3(0, h + 1.8, 0)), rust)
	_add("rust", ProcMesh.box(Vector3(span * 2.0 + 14.0, 0.6, 4.0)), ProcMesh.xf(Vector3(0, h + 3.9, 0)), dark)
	for k2: int in 16:
		var x: float = -span - 6.0 + k2 * (span * 2.0 + 12.0) / 15.0
		_beam("rust", Vector3(x, h, 1.7), Vector3(x + 2.0, h + 3.6, 1.7), 0.3, dark)
	_add("rust", ProcMesh.box(Vector3(6.5, 4.0, 5.0)), ProcMesh.xf(Vector3(8.0, h - 0.5, 0)), rust.darkened(0.15))
	_add("metal", ProcMesh.box(Vector3(4.0, 3.0, 3.2)), ProcMesh.xf(Vector3(-span + 4.0, h - 2.0, 2.4)), Color(0.75, 0.6, 0.25))  # cab
	_at("Ruin")
	# The hook block came down with its cable; it lies at the foot of the far leg.
	_add("rust", ProcMesh.box(Vector3(2.6, 3.0, 1.8)), Transform3D(Basis(Vector3.FORWARD, 1.2), Vector3(12.0, 1.0, 5.0)), dark)
	_beam("rust", Vector3(10.0, 0.3, 5.0), Vector3(2.0, 0.4, 9.0), 0.25, dark)
	_at("Mended")
	_add("rust", ProcMesh.cyl(0.14, 0.14, 22.0, 5), ProcMesh.xf(Vector3(8.0, h - 13.5, -0.8)), dark)
	_add("rust", ProcMesh.cyl(0.14, 0.14, 22.0, 5), ProcMesh.xf(Vector3(8.0, h - 13.5, 0.8)), dark)
	_add("rust", ProcMesh.box(Vector3(2.6, 3.0, 1.8)), ProcMesh.xf(Vector3(8.0, h - 26.0, 0)), Color(0.85, 0.65, 0.2))
	_at("Glow")
	for sx2: float in [-span - 6.5, span + 6.5]:
		_add("glow", ProcMesh.sphere(0.4, 8, 4), ProcMesh.xf(Vector3(sx2, h + 4.6, 0)), Color(1.0, 0.6, 0.2))
	_add("glow", ProcMesh.box(Vector3(span * 2.0 + 13.0, 0.1, 0.12)), ProcMesh.xf(Vector3(0, h - 0.05, 1.62)), Color(1.0, 0.75, 0.45))
