class_name StreetDressing
extends Node3D
## Colour, life and focal points for the start district: striped shop awnings, faded painted
## shop signs, a few neon signs, big weathered murals and a billboard, string lights, bunting
## and laundry across the streets, painted pots, bright plastic crates and barrels, and on the
## hub yard real concrete slabs (joints, oil, asphalt patches) with painted markings, oil-sheen
## puddles, mossy cracks with weeds, pallets, tarps, drums, crates and a work light.
## Purely presentational and deterministic from the district seed (nothing is saved). Built
## once, only around the hub (CityView.DETAIL_RING blocks); batched into a handful of merged
## meshes and MultiMeshes. Animation (neon buzz, bulb twinkle, cloth sway) lives in shaders.
## Collision only on the crate stacks parked on the hub yard's fence corners and the billboard
## legs, which stand outside the junk field.

const NEAR_R: float = 52.0           # facades farther than this from the hub get nothing
const FLOOR_H: float = 3.0
const BAY: float = 3.0

const AWNING: Array[Color] = [Color(0.04, 0.48, 0.47), Color(0.88, 0.36, 0.28), Color(0.86, 0.6, 0.12),
	Color(0.14, 0.28, 0.66), Color(0.68, 0.12, 0.13), Color(0.13, 0.43, 0.28)]
## Vertex-colour alpha selects the material class in deco.gdshader.
const FABRIC: float = 1.0
const STEEL: float = 0.5
const PLAST: float = 0.25
const PAINT: float = 0.0
const CREAM := Color(0.94, 0.9, 0.8)
const PLASTIC: Array[Color] = [Color(0.86, 0.12, 0.1), Color(0.1, 0.35, 0.85), Color(0.98, 0.75, 0.05),
	Color(0.12, 0.62, 0.3), Color(0.98, 0.45, 0.05), Color(0.0, 0.6, 0.65)]
const BULB_COLORS: Array[Color] = [Color(1.0, 0.2, 0.18), Color(0.2, 1.0, 0.35), Color(0.25, 0.45, 1.0),
	Color(1.0, 0.85, 0.2), Color(1.0, 0.3, 0.8), Color(0.2, 0.9, 1.0)]
const WARM := Color(1.0, 0.72, 0.36)
const PENNANT: Array[Color] = [Color(0.95, 0.2, 0.2), Color(0.98, 0.78, 0.1), Color(0.1, 0.6, 0.85),
	Color(0.2, 0.7, 0.35), Color(0.95, 0.5, 0.7), Color(0.98, 0.98, 0.95), Color(0.2, 0.3, 0.85), Color(1.0, 0.5, 0.1)]
const LAUNDRY: Array[Color] = [Color(0.95, 0.95, 0.92), Color(0.55, 0.75, 0.95), Color(0.9, 0.25, 0.25),
	Color(0.98, 0.8, 0.25), Color(0.3, 0.35, 0.6), Color(0.95, 0.6, 0.7), Color(0.4, 0.7, 0.45), Color(0.98, 0.98, 0.98)]
const SHOP_NAMES: Array[String] = ["HARDWARE", "BAKERY", "TAILOR", "PHARMACY", "BOOKS", "BICYCLES",
	"RADIO & TV", "GROCER", "FISH MARKET", "LOCKSMITH", "SHOE REPAIR", "PAWN"]
const NEON: Array = [["NOODLES", Color(1.0, 0.45, 0.2)], ["OPEN", Color(1.0, 0.15, 0.25)], ["LAUNDRY", Color(0.2, 0.85, 1.0)],
	["24h", Color(0.3, 1.0, 0.4)], ["CAFE", Color(1.0, 0.35, 0.8)], ["BAR", Color(0.4, 0.5, 1.0)]]

const SNOW := Color(0.93, 0.95, 0.98, 0.0)
const CYAN := Color(0.3, 0.92, 1.0)
const GLOSS := Color(0.93, 0.94, 0.96, 0.25)   # glossy white shell (plastic class)
const GLASS := Color(0.05, 0.07, 0.1, 0.25)    # dark glass
## Painted under the district name on the yard sign.
const SIGN_SLOGANS: Array[String] = ["WE FIX WHAT'S LEFT", "SWEEP. PLANT. REPEAT.", "NOTHING WASTED HERE",
	"ONE CAN AT A TIME", "GROW BACK GREENER", "OPEN FOR REPAIRS", "MIND THE SPROUTS", "HOME OF THE GOOD SCRAP",
	"SMALL WHEELS, BIG YARD", "EST. AFTER THE RAIN", "SALVAGE & SUNSHINE", "PATIENCE, THEN PETALS"]
const BILLBOARD_SLOGANS: Array[String] = ["TOMORROW, FRESHLY SWEPT", "THE FUTURE IS COMPOSTABLE", "LIFE FINDS A CRACK",
	"EVERY BOLT COUNTS", "REBUILD. REPLANT. REJOICE.", "SKY'S STILL BLUE UP HERE", "BALE NOW, BLOOM LATER",
	"STAY CURIOUS, STAY CLEAN", "THE GOOD STUFF GROWS BACK", "WELCOME HOME, LITTLE ROBOT"]

## Stroke font for neon tubes: letters on a 4 x 6 grid, each a list of polylines.
const GLYPHS: Dictionary = {
	"A": [[Vector2(0, 0), Vector2(0, 4), Vector2(2, 6), Vector2(4, 4), Vector2(4, 0)], [Vector2(0, 2.5), Vector2(4, 2.5)]],
	"B": [[Vector2(0, 0), Vector2(0, 6), Vector2(3, 6), Vector2(4, 5), Vector2(4, 4), Vector2(3, 3), Vector2(0, 3)], [Vector2(3, 3), Vector2(4, 2), Vector2(4, 1), Vector2(3, 0), Vector2(0, 0)]],
	"C": [[Vector2(4, 5), Vector2(3, 6), Vector2(1, 6), Vector2(0, 5), Vector2(0, 1), Vector2(1, 0), Vector2(3, 0), Vector2(4, 1)]],
	"D": [[Vector2(0, 0), Vector2(0, 6), Vector2(2.5, 6), Vector2(4, 4.5), Vector2(4, 1.5), Vector2(2.5, 0), Vector2(0, 0)]],
	"E": [[Vector2(4, 6), Vector2(0, 6), Vector2(0, 0), Vector2(4, 0)], [Vector2(0, 3), Vector2(3, 3)]],
	"F": [[Vector2(4, 6), Vector2(0, 6), Vector2(0, 0)], [Vector2(0, 3), Vector2(3, 3)]],
	"L": [[Vector2(0, 6), Vector2(0, 0), Vector2(4, 0)]],
	"N": [[Vector2(0, 0), Vector2(0, 6), Vector2(4, 0), Vector2(4, 6)]],
	"O": [[Vector2(1, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 5), Vector2(3, 6), Vector2(1, 6), Vector2(0, 5), Vector2(0, 1), Vector2(1, 0)]],
	"P": [[Vector2(0, 0), Vector2(0, 6), Vector2(3, 6), Vector2(4, 5), Vector2(4, 4), Vector2(3, 3), Vector2(0, 3)]],
	"R": [[Vector2(0, 0), Vector2(0, 6), Vector2(3, 6), Vector2(4, 5), Vector2(4, 4), Vector2(3, 3), Vector2(0, 3)], [Vector2(2, 3), Vector2(4, 0)]],
	"S": [[Vector2(4, 5), Vector2(3, 6), Vector2(1, 6), Vector2(0, 5), Vector2(0, 4), Vector2(1, 3), Vector2(3, 3), Vector2(4, 2), Vector2(4, 1), Vector2(3, 0), Vector2(1, 0), Vector2(0, 1)]],
	"U": [[Vector2(0, 6), Vector2(0, 1), Vector2(1, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 6)]],
	"Y": [[Vector2(0, 6), Vector2(2, 3), Vector2(4, 6)], [Vector2(2, 3), Vector2(2, 0)]],
	"2": [[Vector2(0, 5), Vector2(1, 6), Vector2(3, 6), Vector2(4, 5), Vector2(4, 4), Vector2(0, 0), Vector2(4, 0)]],
	"4": [[Vector2(3, 0), Vector2(3, 6), Vector2(0, 2), Vector2(4, 2)]],
	"h": [[Vector2(0, 6), Vector2(0, 0)], [Vector2(0, 2.5), Vector2(1, 3.5), Vector2(3, 3.5), Vector2(4, 2.5), Vector2(4, 0)]],
	"1": [[Vector2(1, 5), Vector2(2.5, 6), Vector2(2.5, 0)]],
	"3": [[Vector2(0, 5), Vector2(1, 6), Vector2(3, 6), Vector2(4, 5), Vector2(4, 4), Vector2(3, 3), Vector2(1.5, 3)], [Vector2(3, 3), Vector2(4, 2), Vector2(4, 1), Vector2(3, 0), Vector2(1, 0), Vector2(0, 1)]],
}

var layout: CityLayout
var field: HexField

var _rng := RandomNumberGenerator.new()
var _deco := Geo.new()      # vertex-coloured opaque: awnings, boards, frames, wires, poles
var _tubes := Geo.new()     # neon tubes
var _bulbs: Array = []      # [Transform3D, Color]
var _pennants: Array = []
var _cloth: Array = [[], [], []]  # towel / shirt / trousers: [Transform3D, Color]
var _crates: Array = []
var _barrels: Array = []
var _drums: Array = []
var _pots: Array = []
var _twigs: Array = []
var _puddles: Array = []    # Transform3D
var _weeds: Dictionary = {} # model id -> Array[Transform3D]
var _cracks: Array = []     # yard cracks, Array of PackedVector2Array (world xz)
var _shops: Array = []      # {pos, out, along, width, bd}
var _facades: Array = []    # {a: Vector2, b: Vector2, face: Vector2, floors: int}
var _neon_count: int = 0

## Per base: which hub (0 = Old Town's starter yard), its name, its wilderness biome ("" = city)
## and the current hub level, which picks the visible dressing layers.
var hub_index: int = 0
var district: String = "Old Town"
var biome: String = ""
var start_base: bool = true
var level: int = 1
## [biomes] Frontier districts dress their own landmarks (planet/frontier_view.gd); no shopfronts.
var skip_facades: bool = false
var _style := RandomNumberGenerator.new()   # palette, kits, landmark: fixed per district
var _layers: Dictionary = {}                # layer name -> Node3D
var _cur: Node3D
var _props: Dictionary = {}                 # model id -> Array[Transform3D] (MultiMesh per id)
var _flags: Array = []                      # [Transform3D, Color]
var _hover: Array[Node3D] = []              # floating things animated in _process
var _t: float = 0.0
var _slab_mat: ShaderMaterial
var _shop_neon: ShaderMaterial
var _neon_lights: Array[Light3D] = []
var _pennant: Array[Color] = []
var _plastic: Array[Color] = []
var _awning_cols: Array[Color] = []
var _paint_main := Color(0.98, 0.78, 0.1, 0.92)
var _hazard_a := Color(0.98, 0.76, 0.08, 0.9)
var _accent := Color(1.0, 0.5, 0.12)        # orange accent on the futuristic kit
var _tarp_cols: Array[Color] = []
var _sign_bg := Color(0.12, 0.25, 0.22)
var _lm_col := Color(0.35, 0.55, 0.62)
var _drift: float = 0.0
var _drift_col := Color(0.86, 0.74, 0.55)
var _sign_x: float = -3.8
var _lm_kind: String = ""
var _lm_pos := Vector3.ZERO
var _lm_top := Vector3.ZERO
var _warm: float = 0.8


func build(p_layout: CityLayout, p_field: HexField, p_hub: int = 0, p_district: String = "", p_biome: String = "", p_level: int = 1) -> void:
	layout = p_layout
	field = p_field
	hub_index = p_hub
	district = p_district if p_district != "" else "Old Town"
	biome = p_biome
	start_base = hub_index == 0
	level = clampi(p_level, 1, 5)
	_cur = self
	_style.seed = layout.seed_value * 31 + 4242
	_pick_style()
	_begin("Base")
	if not layout.wild and not skip_facades:  # [biomes]
		_collect_facades()
		_build_shopfronts()
		_build_murals()
		_build_billboard()
		if start_base:
			_build_street_lines()
	_build_yard_paint()
	if biome != "dust_dunes":
		_build_puddles()
	_build_weeds()
	_build_drifts(0.5)
	_build_landmark()
	if level <= 1 and not start_base:
		_begin("Ruin")
		_build_ruin()
	_begin("Salvage")
	_build_fence(false)
	_build_name_sign(false)
	_build_pole_lamps()
	_begin("Yard")
	_build_poles()
	_build_crates()
	_build_camp()
	_build_festoons()
	if not layout.wild and not start_base:
		_build_street_lines()
	_begin("Future")
	_build_future_fence()
	_build_holo_sign()
	_build_guide_lights()
	_begin("Thrive")
	_build_planters()
	_build_drones()
	_begin("Beacon")
	_build_beacon()
	_flush()
	set_level(level, false)


# --- Levels: ruined -> patched -> futuristic -------------------------------------------------

## Which hub levels show each layer. Old Town's starter yard is never ruined.
func _layer_range(nm: String) -> Vector2i:
	match nm:
		"Ruin":
			return Vector2i(1, 1) if not start_base else Vector2i(9, 9)
		"Salvage":
			return Vector2i(1 if start_base else 2, 2)
		"Yard":
			return Vector2i(1 if start_base else 2, 5)
		"Future":
			return Vector2i(3, 5)
		"Thrive":
			return Vector2i(4, 5)
		"Beacon":
			return Vector2i(5, 5)
	return Vector2i(0, 99)


## Starts collecting geometry into a new layer node (the previous one is flushed). Each layer
## has its own RNG seed so it looks the same however the base got to its level.
func _begin(nm: String) -> void:
	if _cur != self:
		_flush()
	var node := Node3D.new()
	node.name = nm
	add_child(node)
	_layers[nm] = node
	_cur = node
	_rng.seed = layout.seed_value * 7 + 90210 + (0 if nm == "Base" else nm.hash() % 100000)
	_deco = Geo.new()
	_tubes = Geo.new()
	_bulbs = []
	_pennants = []
	_cloth = [[], [], []]
	_crates = []
	_barrels = []
	_drums = []
	_pots = []
	_twigs = []
	_puddles = []
	_weeds = {}
	_props = {}
	_flags = []


## Shows the layers for hub level `l`. Live (animate): new layers rise out of the slab with
## sparkles, the ruin sinks away in a puff of dust, paint freshens, neon and seams light up.
func set_level(l: int, animate: bool) -> void:
	level = clampi(l, 1, 5)
	var k: int = 0
	for nm: String in _layers:
		var node: Node3D = _layers[nm]
		if not is_instance_valid(node):
			continue
		var r: Vector2i = _layer_range(nm)
		var want: bool = level >= r.x and level <= r.y
		if want == node.visible:
			continue
		if not animate:
			node.visible = want
			node.scale = Vector3.ONE
			if not want and level > r.y:
				node.queue_free()
			continue
		var tw := create_tween()
		if want:
			node.visible = true
			node.scale = Vector3(1, 0.02, 1)
			tw.tween_interval(0.5 + k * 0.45)
			tw.tween_callback(func() -> void:
				Audio.play("clunk", randf_range(1.1, 1.4), -8.0)
				for q: int in 5:
					Vfx.burst("sparkle", Vector3(randf_range(-7, 7), 0.6, randf_range(-7, 7)), Color(0.5, 0.95, 1.0) if level >= 3 else Color(1.0, 0.8, 0.4), 0.6))
			tw.tween_property(node, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			k += 1
		else:
			tw.tween_interval(0.2)
			tw.tween_callback(func() -> void:
				for q: int in 6:
					Vfx.burst("dust", Vector3(randf_range(-8, 8), 0.4, randf_range(-8, 8)), Color(0.7, 0.65, 0.6, 0.6), 1.2))
			tw.tween_property(node, "scale", Vector3(1, 0.02, 1), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(node.queue_free if level > r.y else node.hide)
	_apply_surface(animate)
	set_process(level >= 4)


func _apply_surface(animate: bool) -> void:
	var fade: float = 0.0
	var grime: float = 0.0
	var drift: float = _drift * 0.55
	if not start_base and level == 1:
		fade = 0.85
		grime = 1.0
		drift = _drift
	elif not start_base and level == 2:
		fade = 0.45
		grime = 0.35
		drift = _drift * 0.8
	var glow: float = 0.0 if level < 3 else (0.7 if level < 5 else 1.1)
	var neon: float = 5.0 if start_base or level >= 3 else 0.0
	var vals: Dictionary = {"fade": fade, "grime": grime, "drift": drift, "glow": glow}
	if _slab_mat:
		for key: String in vals:
			if animate:
				create_tween().tween_property(_slab_mat, "shader_parameter/" + key, vals[key], 2.0).set_delay(0.6)
			else:
				_slab_mat.set_shader_parameter(key, vals[key])
	if _shop_neon:
		_shop_neon.set_shader_parameter("energy", neon)
	for lt: Light3D in _neon_lights:
		if is_instance_valid(lt):
			lt.visible = neon > 0.0


func _process(delta: float) -> void:
	_t += delta
	for i: int in _hover.size():
		var h: Node3D = _hover[i]
		if not is_instance_valid(h) or not h.is_visible_in_tree():
			continue
		var base: Vector3 = h.get_meta("base")
		if h.has_meta("orbit"):
			var r: float = h.get_meta("orbit")
			var a: float = _t * 0.25 + i * TAU / 3.0
			h.position = base + Vector3(cos(a) * r, sin(_t * 1.3 + i) * 0.25, sin(a) * r)
			h.rotation.y = -a
		else:
			h.position = base + Vector3(0, sin(_t * 1.1 + i) * 0.12, 0)
			if not h.has_meta("nospin"):
				h.rotation.y += delta * 0.3


# --- Geometry helper -----------------------------------------------------------------

class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var u := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, d: Vector3, nrm: Vector3, col: Color, uv: Vector2 = Vector2.ZERO) -> void:
		# Godot front faces wind clockwise: keep the winding consistent with the given normal.
		if (d - a).cross(b - a).dot(nrm) < 0.0:
			var t: Vector3 = b
			b = d
			d = t
		for p: Vector3 in [a, b, d]:
			v.append(p)
			n.append(nrm)
			c.append(col)
			u.append(uv)

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, col: Color, uv: Vector2 = Vector2.ZERO, nrm: Vector3 = Vector3.ZERO) -> void:
		if nrm == Vector3.ZERO:
			nrm = (d - a).cross(b - a).normalized()
			if nrm == Vector3.ZERO:
				return
		tri(a, b, d, nrm, col, uv)
		tri(a, d, e, nrm, col, uv)

	func box(xf: Transform3D, size: Vector3, col: Color, uv: Vector2 = Vector2.ZERO) -> void:
		var h: Vector3 = size * 0.5
		for ax: int in 3:
			for sgn: float in [-1.0, 1.0]:
				var nl := Vector3.ZERO
				nl[ax] = sgn
				var t := Vector3.ZERO
				t[(ax + 1) % 3] = 1.0
				var bt := Vector3.ZERO
				bt[(ax + 2) % 3] = 1.0
				var ctr: Vector3 = nl * h
				var tt: Vector3 = t * h
				var bb: Vector3 = bt * h
				var nw: Vector3 = (xf.basis * nl).normalized()
				quad(xf * (ctr - tt - bb), xf * (ctr + tt - bb), xf * (ctr + tt + bb), xf * (ctr - tt + bb), col, uv, nw)

	## Square-section rod from a to b.
	func rod(a: Vector3, b: Vector3, r: float, col: Color, uv: Vector2 = Vector2.ZERO) -> void:
		var d: Vector3 = b - a
		var l: float = d.length()
		if l < 0.0005:
			return
		var x: Vector3 = d / l
		var y: Vector3 = x.cross(Vector3.UP)
		if y.length() < 0.01:
			y = x.cross(Vector3.RIGHT)
		y = y.normalized()
		var z: Vector3 = x.cross(y).normalized()
		box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(l + r, r * 2.0, r * 2.0), col, uv)

	## Triangle with per-vertex normals (smooth shading).
	func tri3(a: Vector3, b: Vector3, d: Vector3, na: Vector3, nb: Vector3, nd: Vector3, col: Color, uv: Vector2 = Vector2.ZERO) -> void:
		if (d - a).cross(b - a).dot(na + nb + nd) < 0.0:
			var t: Vector3 = b
			b = d
			d = t
			var tn: Vector3 = nb
			nb = nd
			nd = tn
		v.append(a)
		v.append(b)
		v.append(d)
		n.append(na)
		n.append(nb)
		n.append(nd)
		for k: int in 3:
			c.append(col)
			u.append(uv)

	## Smooth (frustum) cylinder from a to b, radius r0 at a and r1 at b.
	func cyl(a: Vector3, b: Vector3, r0: float, r1: float, col: Color, seg: int = 12, caps: bool = true, uv: Vector2 = Vector2.ZERO) -> void:
		var l: float = a.distance_to(b)
		if l < 0.0005:
			return
		var ax: Vector3 = (b - a) / l
		var x: Vector3 = ax.cross(Vector3.FORWARD if absf(ax.z) < 0.9 else Vector3.RIGHT).normalized()
		var y: Vector3 = ax.cross(x).normalized()
		var slope: float = (r0 - r1) / l
		for i: int in seg:
			var a0: float = TAU * i / seg
			var a1: float = TAU * (i + 1) / seg
			var d0: Vector3 = x * cos(a0) + y * sin(a0)
			var d1: Vector3 = x * cos(a1) + y * sin(a1)
			var n0: Vector3 = (d0 + ax * slope).normalized()
			var n1: Vector3 = (d1 + ax * slope).normalized()
			var p00: Vector3 = a + d0 * r0
			var p01: Vector3 = a + d1 * r0
			var p10: Vector3 = b + d0 * r1
			var p11: Vector3 = b + d1 * r1
			tri3(p00, p01, p11, n0, n1, n1, col, uv)
			tri3(p00, p11, p10, n0, n1, n0, col, uv)
			if caps:
				tri(a, p00, p01, -ax, col, uv)
				if r1 > 0.001:
					tri(b, p10, p11, ax, col, uv)

	## Polyline ring of rods around `center` in the plane spanned by e1, e2.
	func ring(center: Vector3, e1: Vector3, e2: Vector3, r: float, seg: int, rod_r: float, col: Color, uv: Vector2 = Vector2.ZERO) -> void:
		for i: int in seg:
			var a0: float = TAU * i / seg
			var a1: float = TAU * (i + 1) / seg
			rod(center + (e1 * cos(a0) + e2 * sin(a0)) * r, center + (e1 * cos(a1) + e2 * sin(a1)) * r, rod_r, col, uv)

	func empty() -> bool:
		return v.is_empty()

	func mesh() -> ArrayMesh:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = u
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func _catenary(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	return a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)


func _xz(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


# --- Facades and shops ---------------------------------------------------------------

## Ground-floor facade lines of the detailed buildings near the hub, split into shops.
func _collect_facades() -> void:
	for key: Vector2i in layout.blocks:
		if maxi(absi(key.x), absi(key.y)) > CityView.DETAIL_RING:
			continue
		var blk: Dictionary = layout.blocks[key]
		for bd: Dictionary in blk["buildings"]:
			var r: Rect2 = bd["rect"]
			var face: Vector2 = bd["face"]
			var along: Vector2
			var origin: Vector2
			if face.y < 0:
				along = Vector2(1, 0)
				origin = r.position
			elif face.y > 0:
				along = Vector2(-1, 0)
				origin = r.end
			elif face.x < 0:
				along = Vector2(0, -1)
				origin = Vector2(r.position.x, r.end.y)
			else:
				along = Vector2(0, 1)
				origin = Vector2(r.end.x, r.position.y)
			var bays: int = int(bd["bays"])
			var a: Vector2 = origin
			var b: Vector2 = origin + along * bays * BAY
			if ((a + b) * 0.5).length() > NEAR_R:
				continue
			_facades.append({"a": a, "b": b, "face": face, "along": along, "floors": int(bd["floors"]), "bd": bd, "block": key})
			# Shops: runs of 2-3 bays.
			var i: int = 0
			while i < bays:
				var w: int = mini(_rng.randi_range(2, 3), bays - i)
				if w >= 1:
					var c2: Vector2 = origin + along * (i + w * 0.5) * BAY
					_shops.append({"c": c2, "face": face, "along": along, "width": w * BAY, "floors": int(bd["floors"])})
				i += w


func _facing_hub(c: Vector2, face: Vector2) -> float:
	return face.dot(-c.normalized())


func _build_shopfronts() -> void:
	# Neon goes on the shops that face the hub and are closest to it.
	var order: Array = range(_shops.size())
	order.sort_custom(func(i: int, j: int) -> bool:
		var si: Dictionary = _shops[i]
		var sj: Dictionary = _shops[j]
		return (si["c"] as Vector2).length() - _facing_hub(si["c"], si["face"]) * 14.0 < (sj["c"] as Vector2).length() - _facing_hub(sj["c"], sj["face"]) * 14.0)
	var neon_left: int = NEON.size()
	var label_left: int = 9
	var names: Array = SHOP_NAMES.duplicate()
	var shuffle := RandomNumberGenerator.new()
	shuffle.seed = _rng.seed + 3
	for k: int in range(names.size() - 1, 0, -1):
		var j: int = shuffle.randi() % (k + 1)
		var t: Variant = names[k]
		names[k] = names[j]
		names[j] = t
	for idx: int in order:
		var s: Dictionary = _shops[idx]
		var c: Vector2 = s["c"]
		var face: Vector2 = s["face"]
		var along: Vector2 = s["along"]
		var width: float = s["width"]
		var out3 := Vector3(face.x, 0, face.y)
		var al3 := Vector3(along.x, 0, along.y)
		var base := Vector3(c.x, CityLayout.CURB_H, c.y)
		var toward: bool = _facing_hub(c, face) > 0.2
		var roll: float = _rng.randf()
		var col: Color = _awning_cols[_rng.randi() % _awning_cols.size()]
		var has_awning: bool = roll < (0.8 if toward else 0.5)
		if has_awning:
			_awning(base + out3 * 0.32, al3, out3, width - 0.4, col)
		var want_neon: bool = toward and neon_left > 0 and s["floors"] >= 2 and width >= 5.0
		if want_neon:
			var spec: Array = NEON[NEON.size() - neon_left]
			neon_left -= 1
			var txt: String = spec[0]
			var ncol: Color = spec[1]
			var blade: bool = txt == "24h" or txt == "BAR"
			if blade:
				# Blade sign sticking out from the wall at the shop edge.
				var p: Vector3 = base + al3 * (width * 0.5 - 0.4) + out3 * 0.95 + Vector3.UP * 3.9
				_neon_sign(txt, p, al3, 0.42, ncol, 1.0 if txt == "BAR" else 0.0, true)
				_neon_sign(txt, p, -al3, 0.42, ncol, 0.0, true)
			else:
				var p2: Vector3 = base + out3 * 0.42 + Vector3.UP * 3.55
				_neon_sign(txt, p2, out3, 0.5, ncol, 1.0 if txt == "LAUNDRY" else 0.0, txt == "OPEN")
		elif label_left > 0 and _rng.randf() < 0.75:
			label_left -= 1
			var nm: String = names[label_left % names.size()]
			_painted_sign(nm, base + out3 * 0.36 + Vector3.UP * (3.35 if has_awning else 2.6), al3, out3, minf(width - 0.6, 0.32 * nm.length() + 0.6))
		# Painted pots by the door, the odd crate or barrel against the wall.
		var n_pots: int = _rng.randi_range(0, 3) if toward else _rng.randi_range(0, 1)
		for k: int in n_pots:
			var off: float = _rng.randf_range(-width * 0.45, width * 0.45)
			var pp: Vector3 = base + al3 * off + out3 * _rng.randf_range(0.32, 0.45)
			_pot(pp)
		if _rng.randf() < 0.35:
			var off2: float = (_rng.randf_range(0.35, 0.48) * (1.0 if _rng.randf() < 0.5 else -1.0)) * width
			var cp: Vector3 = base + al3 * off2 + out3 * 0.42
			if _rng.randf() < 0.5:
				_crate(Transform3D(Basis.looking_at(-al3).rotated(Vector3.UP, _rng.randf_range(-0.2, 0.2)), cp + Vector3.UP * 0.16), _plastic[_rng.randi() % _plastic.size()])
				if _rng.randf() < 0.5:
					_crate(Transform3D(Basis.looking_at(-al3).rotated(Vector3.UP, _rng.randf_range(-0.3, 0.3)), cp + Vector3.UP * 0.48), _plastic[_rng.randi() % _plastic.size()])
			else:
				_barrels.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), cp + out3 * 0.05), _plastic[_rng.randi() % _plastic.size()]])
	# Laundry hung out of upper windows on taller facades that face the hub.
	for f: Dictionary in _facades:
		var fa: Vector2 = f["a"]
		var fb: Vector2 = f["b"]
		var face2: Vector2 = f["face"]
		var floors: int = f["floors"]
		if floors < 3 or _facing_hub((fa + fb) * 0.5, face2) < 0.2 or _rng.randf() < 0.3:
			continue
		var fl: int = _rng.randi_range(1, mini(floors - 1, 3))
		var y: float = fl * FLOOR_H + 0.15
		var len: float = fa.distance_to(fb)
		var t0: float = _rng.randf_range(0.5, maxf(0.6, len * 0.4))
		var t1: float = minf(len - 0.5, t0 + _rng.randf_range(3.5, 7.0))
		var along2: Vector2 = f["along"]
		var p0: Vector3 = _xz(fa + along2 * t0 + face2 * 0.9, y)
		var p1: Vector3 = _xz(fa + along2 * t1 + face2 * 0.9, y)
		_bracket(p0, face2)
		_bracket(p1, face2)
		_laundry_line(p0, p1, 0.18)


func _bracket(p: Vector3, face: Vector2) -> void:
	var o := Vector3(face.x, 0, face.y)
	_deco.rod(p - o * 0.9, p, 0.018, Color(0.15, 0.14, 0.13, STEEL))


## Striped canvas awning: slopes out and down from the wall, sags a little between the arms,
## with a scalloped valance; bleached on top, grimy along the hem.
func _awning(top_mid: Vector3, al: Vector3, out: Vector3, width: float, col: Color) -> void:
	var y_top: float = 2.95
	var depth: float = _rng.randf_range(1.15, 1.45)
	var drop: float = _rng.randf_range(0.5, 0.7)
	var stripes: int = maxi(4, int(width / 0.32))
	var sw: float = width / stripes
	var rows: int = 4
	var left: Vector3 = Vector3(top_mid.x, y_top, top_mid.z) - al * width * 0.5
	var dirt: float = _rng.randf_range(0.75, 1.0)
	var torn: int = _rng.randi_range(-1, stripes - 1) if _rng.randf() < 0.4 else -99
	var pts: Callable = func(i: int, j: int) -> Vector3:
		var td: float = float(j) / rows
		var ta: float = float(i) / stripes
		var sag: float = 0.07 * sin(ta * PI * 2.0) * sin(td * PI) if stripes > 6 else 0.04 * sin(td * PI)
		return left + al * ta * width + out * td * depth - Vector3.UP * (drop * td + absf(sag))
	for i: int in stripes:
		if i == torn or i == torn + 1:
			continue  # a rip: a couple of stripes gone
		var base_c: Color = col if i % 2 == 0 else CREAM
		var shade: float = _rng.randf_range(0.88, 1.0) * dirt
		for j: int in rows:
			var bleach: float = 0.25 * (1.0 - float(j) / rows)
			var cc: Color = base_c.lerp(Color(0.95, 0.93, 0.88), bleach) * shade
			cc.a = 1.0
			_deco.quad(pts.call(i, j), pts.call(i + 1, j), pts.call(i + 1, j + 1), pts.call(i, j + 1), cc)
		# Valance: drops from the front edge with a scalloped hem.
		var a: Vector3 = pts.call(i, rows)
		var b: Vector3 = pts.call(i + 1, rows)
		var vh: float = 0.26
		var vc: Color = base_c * shade * 0.92
		vc.a = 1.0
		var hem: Color = vc.darkened(0.25)
		_deco.quad(a, b, b - Vector3.UP * vh, a - Vector3.UP * vh, vc)
		var m: Vector3 = (a + b) * 0.5 - Vector3.UP * (vh + 0.09)
		_deco.tri(a - Vector3.UP * vh, b - Vector3.UP * vh, m, out, hem)
	# Frame: side arms and a front bar.
	var frame := Color(0.12, 0.12, 0.13, STEEL)
	for e: float in [0.0, 1.0]:
		var w0: Vector3 = left + al * e * width
		var f0: Vector3 = pts.call(int(e * stripes), rows)
		_deco.rod(w0 - Vector3.UP * 0.75, f0 - Vector3.UP * 0.02, 0.018, frame)
		_deco.rod(w0, f0, 0.015, frame)
	_deco.rod(pts.call(0, rows) - Vector3.UP * 0.02, pts.call(stripes, rows) - Vector3.UP * 0.02, 0.02, frame)


## Faded hand-painted sign board flat on the wall above a shop.
func _painted_sign(text: String, center: Vector3, al: Vector3, out: Vector3, width: float) -> void:
	var bg: Color = [Color(0.12, 0.25, 0.22), Color(0.55, 0.12, 0.1), Color(0.1, 0.16, 0.35), Color(0.85, 0.75, 0.55), Color(0.2, 0.2, 0.2)][_rng.randi() % 5]
	var fg: Color = Color(0.95, 0.88, 0.62) if bg.get_luminance() < 0.5 else Color(0.5, 0.12, 0.08)
	var h: float = 0.62
	var xf := Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), center)
	var board: Color = bg.lerp(Color(0.75, 0.72, 0.66), _rng.randf_range(0.15, 0.35))
	board.a = PAINT
	var trim: Color = fg.darkened(0.3)
	trim.a = PAINT
	_deco.box(xf, Vector3(width, h, 0.05), board)
	# Trim
	_deco.box(xf.translated_local(Vector3(0, h * 0.5, 0.01)), Vector3(width + 0.06, 0.05, 0.07), trim)
	_deco.box(xf.translated_local(Vector3(0, -h * 0.5, 0.01)), Vector3(width + 0.06, 0.05, 0.07), trim)
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.outline_size = 0
	l.pixel_size = 0.0048
	l.modulate = Color(fg.r, fg.g, fg.b, 0.82)
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.transform = xf.translated_local(Vector3(0, 0, 0.035))
	l.visibility_range_end = 70.0
	_cur.add_child(l)


## Neon tubes bent into text on a dark backing rail. `right`/`up` span the sign plane and
## `out` points to the viewer. state 1 = a failing sign that stutters.
func _neon_sign(text: String, center: Vector3, out: Vector3, h: float, col: Color, state: float, frame: bool) -> void:
	var up := Vector3.UP
	var right: Vector3 = up.cross(out).normalized()  # reads left-to-right for someone facing the sign
	var s: float = h / 6.0
	var lw: float = 4.0 * s
	var gap: float = 1.6 * s
	var total: float = text.length() * lw + (text.length() - 1) * gap
	var seed: float = float(_neon_count) * 1.37 + 0.3
	_neon_count += 1
	var r: float = h * 0.04
	var x0: float = -total * 0.5
	var dead_letter: int = _rng.randi_range(1, text.length() - 1) if state > 0.5 else -1
	for li: int in text.length():
		var ch: String = text[li]
		var strokes: Array = GLYPHS.get(ch, [])
		var st: float = 2.0 if li == dead_letter else state
		for poly: Array in strokes:
			for k: int in poly.size() - 1:
				var a2: Vector2 = poly[k]
				var b2: Vector2 = poly[k + 1]
				var a: Vector3 = center + right * (x0 + a2.x * s) + up * (a2.y * s - h * 0.5) + out * 0.09
				var b: Vector3 = center + right * (x0 + b2.x * s) + up * (b2.y * s - h * 0.5) + out * 0.09
				_tubes.rod(a, b, r, col, Vector2(seed, st))
		x0 += lw + gap
	var pad: float = h * 0.35
	var bw: float = total + pad * 2.0
	var bh: float = h + pad * 2.0
	if frame:
		# A tube border in a second colour.
		var fc := Color(0.25, 0.55, 1.0) if col.r > 0.5 else Color(1.0, 0.4, 0.3)
		var corners: Array = [Vector2(-bw * 0.5, -bh * 0.5), Vector2(bw * 0.5, -bh * 0.5), Vector2(bw * 0.5, bh * 0.5), Vector2(-bw * 0.5, bh * 0.5)]
		for k: int in 4:
			var ca: Vector2 = corners[k]
			var cb: Vector2 = corners[(k + 1) % 4]
			_tubes.rod(center + right * ca.x + up * ca.y + out * 0.09, center + right * cb.x + up * cb.y + out * 0.09, r, fc, Vector2(seed + 0.5, 0.0))
		bw += pad
		bh += pad
	var xf := Transform3D(Basis(right, up, out), center)
	_deco.box(xf, Vector3(bw, bh, 0.06), Color(0.06, 0.06, 0.07, STEEL))
	# Little stand-offs and a transformer box: it is a real, cheap sign.
	_deco.box(xf.translated_local(Vector3(bw * 0.3, -bh * 0.5 - 0.08, -0.02)), Vector3(0.22, 0.14, 0.1), Color(0.3, 0.3, 0.32, STEEL))
	if _neon_count <= 4:
		var lt := OmniLight3D.new()
		lt.light_color = col.lerp(Color.WHITE, 0.15)
		lt.light_energy = 1.2
		lt.omni_range = 4.5
		lt.shadow_enabled = false
		lt.position = center + out * 0.7
		lt.distance_fade_enabled = true
		lt.distance_fade_begin = 50.0
		lt.distance_fade_length = 15.0
		_cur.add_child(lt)
		if _cur == _layers.get("Base"):
			_neon_lights.append(lt)


func _pot(p: Vector3) -> void:
	var col: Color = [Color(0.0, 0.62, 0.6), Color(0.95, 0.35, 0.45), Color(0.98, 0.75, 0.1), Color(0.15, 0.32, 0.85),
		Color(0.92, 0.45, 0.12), Color(0.55, 0.3, 0.7), Color(0.7, 0.35, 0.22)][_rng.randi() % 7]
	var s: float = _rng.randf_range(0.75, 1.3)
	var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), p)
	_pots.append([xf, col.darkened(_rng.randf_range(0.0, 0.2))])
	if _rng.randf() < 0.85:
		var tw: Color = Color(0.42, 0.33, 0.22).lerp(Color(0.55, 0.5, 0.3), _rng.randf())
		_twigs.append([xf.translated_local(Vector3(0, 0.3, 0)) * Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.3)), Vector3.ZERO), tw])


func _crate(xf: Transform3D, col: Color) -> void:
	_crates.append([xf, col.darkened(_rng.randf_range(0.0, 0.2))])


# --- Murals and billboard --------------------------------------------------------------

func _mural_material(variant: float, size: Vector2, seed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/mural.gdshader")
	m.set_shader_parameter("variant", variant)
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("wall_tex", AssetLib.tex("painted_concrete", "diff"))
	return m


## Murals on the exposed end walls of corner buildings that look toward the hub.
func _build_murals() -> void:
	var cands: Array = []
	for f: Dictionary in _facades:
		var bd: Dictionary = f["bd"]
		var r: Rect2 = bd["rect"]
		var blk: Rect2 = layout.blocks[f["block"]]["rect"]
		var face: Vector2 = f["face"]
		var h: float = minf(int(bd["floors"]) * FLOOR_H, 10.5)
		if h < 6.0:
			continue
		# End walls perpendicular to the facade, on the block edge.
		var ends: Array = []
		if absf(face.y) > 0.5:
			if absf(r.position.x - blk.position.x) < 1.2:
				ends.append([Vector2(-1, 0), Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y)])
			if absf(r.end.x - blk.end.x) < 1.2:
				ends.append([Vector2(1, 0), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y)])
		for e: Array in ends:
			var nrm: Vector2 = e[0]
			var a: Vector2 = e[1]
			var b: Vector2 = e[2]
			# Keep clear of the facade modules on the front edge.
			if face.y < 0:
				a.y += 0.9
			else:
				b.y -= 0.9
			var mid: Vector2 = (a + b) * 0.5
			var score: float = nrm.dot(-mid.normalized())
			if score < 0.3 or mid.length() > 55.0:
				continue
			cands.append({"n": nrm, "a": a, "b": b, "h": h, "score": mid.length() * (1.6 - score)})
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["score"]) < float(y["score"]))
	for i: int in mini(2, cands.size()):
		var c: Dictionary = cands[i]
		var a3: Vector2 = c["a"] + c["n"] * 0.03
		var b3: Vector2 = c["b"] + c["n"] * 0.03
		var w: float = a3.distance_to(b3)
		var h2: float = c["h"]
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(w, h2)
		mi.mesh = qm
		var n3 := Vector3(c["n"].x, 0, c["n"].y)
		mi.transform = Transform3D(Basis(Vector3.UP.cross(n3), Vector3.UP, n3), _xz((a3 + b3) * 0.5, h2 * 0.5 + 0.02))
		mi.material_override = _mural_material(0.0, Vector2(w, h2), float(i) * 2.3 + float(layout.seed_value % 7))
		mi.visibility_range_end = 220.0
		_cur.add_child(mi)


## An old billboard across the parking lot from the hub, in the default view's line of sight.
## Its legs stand on the far sidewalk, outside the junk field.
func _build_billboard() -> void:
	var key := Vector2i(0, -1)
	if not layout.blocks.has(key):
		return
	var blk: Rect2 = layout.blocks[key]["rect"]
	var z: float = blk.position.y - CityLayout.WALK_W * 0.55
	var x: float = _rng.randf_range(-3.0, 3.0)
	for probe: float in [0.0, -3.0, 3.0, -6.0, 6.0]:
		if field == null or (field.hex_at(Vector3(x + probe - 6.0, 0, z)) < 0 and field.hex_at(Vector3(x + probe + 6.0, 0, z)) < 0):
			x += probe
			break
	var w: float = 15.0
	var h: float = 6.5
	var y0: float = 6.0
	var steel := Color(0.22, 0.22, 0.24, STEEL)
	var rust := Color(0.42, 0.25, 0.15, STEEL)
	var body := StaticBody3D.new()
	_cur.add_child(body)
	for lx: float in [-w * 0.3, w * 0.3]:
		var p := Vector3(x + lx, 0, z)
		_deco.box(Transform3D(Basis(), p + Vector3(0, y0 * 0.5, 0)), Vector3(0.45, y0, 0.45), steel)
		_deco.box(Transform3D(Basis(), p + Vector3(0, 0.3, 0)), Vector3(0.8, 0.6, 0.8), Color(0.55, 0.53, 0.5, PAINT))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.8, y0, 0.8)
		cs.shape = bs
		cs.position = p + Vector3(0, y0 * 0.5, 0)
		body.add_child(cs)
	# Back panel, frame, catwalk and railing.
	var c := Vector3(x, y0 + h * 0.5, z)
	_deco.box(Transform3D(Basis(), c - Vector3(0, 0, 0.12)), Vector3(w, h, 0.2), Color(0.35, 0.34, 0.33, STEEL))
	for k: int in 4:
		var yy: float = y0 + k * h / 3.0
		_deco.box(Transform3D(Basis(), Vector3(x, yy, z - 0.3)), Vector3(w, 0.18, 0.18), rust if k % 2 == 0 else steel)
	_deco.box(Transform3D(Basis(), Vector3(x, y0 - 0.15, z + 0.55)), Vector3(w + 0.4, 0.08, 1.2), steel)
	for k: int in 13:
		var px: float = x - w * 0.5 + k * w / 12.0
		_deco.rod(Vector3(px, y0 - 0.15, z + 1.1), Vector3(px, y0 + 0.85, z + 1.1), 0.025, steel)
	_deco.rod(Vector3(x - w * 0.5, y0 + 0.85, z + 1.1), Vector3(x + w * 0.5, y0 + 0.85, z + 1.1), 0.03, steel)
	# Gooseneck lamps over the top (dead).
	for k: int in 4:
		var px2: float = x - w * 0.375 + k * w * 0.25
		_deco.rod(Vector3(px2, y0 + h, z - 0.1), Vector3(px2, y0 + h + 0.5, z + 0.3), 0.03, steel)
		_deco.rod(Vector3(px2, y0 + h + 0.5, z + 0.3), Vector3(px2, y0 + h + 0.35, z + 0.9), 0.03, steel)
		_deco.box(Transform3D(Basis(), Vector3(px2, y0 + h + 0.3, z + 0.95)), Vector3(0.35, 0.12, 0.25), steel)
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	mi.mesh = qm
	mi.position = c + Vector3(0, 0, 0.0)
	mi.material_override = _mural_material(1.0, Vector2(w, h), 5.1 + float(layout.seed_value % 5))
	mi.visibility_range_end = 260.0
	_cur.add_child(mi)
	# Pasted-up slogan along the bottom, half peeled.
	var l := Label3D.new()
	l.text = "BRIGHTER DAYS AHEAD" if start_base else BILLBOARD_SLOGANS[(hub_index * 7 + _style.randi()) % BILLBOARD_SLOGANS.size()]
	l.font_size = 160
	l.pixel_size = 0.0075
	l.outline_size = 24
	l.outline_modulate = Color(0.06, 0.05, 0.07, 0.9)
	l.modulate = Color(0.98, 0.95, 0.85, 0.95)
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = Vector3(x - w * 0.12, y0 + h * 0.86, z + 0.03)
	l.visibility_range_end = 260.0
	_cur.add_child(l)


# --- Lines across streets: string lights, bunting, laundry ------------------------------

func _string_lights(a: Vector3, b: Vector3, sag: float, warm: bool, spacing: float = 0.55) -> void:
	var len: float = a.distance_to(b)
	var segs: int = maxi(6, int(len / 1.2))
	var wire := Color(0.08, 0.08, 0.08, STEEL)
	for i: int in segs:
		_deco.rod(_catenary(a, b, sag, float(i) / segs), _catenary(a, b, sag, float(i + 1) / segs), 0.008, wire)
	var n: int = int(len / spacing)
	for i: int in range(1, n):
		var t: float = float(i) / n
		var p: Vector3 = _catenary(a, b, sag, t) - Vector3.UP * 0.07
		var col: Color = WARM if warm and _rng.randf() < _warm else BULB_COLORS[(i + _rng.randi_range(0, 1)) % BULB_COLORS.size()]
		if warm and col != WARM:
			col = col.lerp(WARM, 0.3)
		if _rng.randf() < 0.06:
			col = Color(0.05, 0.05, 0.05)  # a dead bulb
		_bulbs.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p), col])


func _bunting(a: Vector3, b: Vector3, sag: float) -> void:
	var len: float = a.distance_to(b)
	var segs: int = maxi(6, int(len / 1.2))
	for i: int in segs:
		_deco.rod(_catenary(a, b, sag, float(i) / segs), _catenary(a, b, sag, float(i + 1) / segs), 0.007, Color(0.55, 0.5, 0.42, PAINT))
	var n: int = int(len / 0.42)
	var dir: Vector3 = (b - a).normalized()
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	var start: int = _rng.randi() % _pennant.size()
	for i: int in range(1, n):
		if _rng.randf() < 0.07:
			continue  # torn off
		var p: Vector3 = _catenary(a, b, sag, float(i) / n)
		var col: Color = _pennant[(start + i) % _pennant.size()].darkened(_rng.randf_range(0.0, 0.15))
		_pennants.append([Transform3D(Basis(dir, Vector3.UP, side).rotated(dir, _rng.randf_range(-0.12, 0.12)), p), col])


func _laundry_line(a: Vector3, b: Vector3, sag: float) -> void:
	var len: float = a.distance_to(b)
	var segs: int = maxi(4, int(len / 1.0))
	for i: int in segs:
		_deco.rod(_catenary(a, b, sag, float(i) / segs), _catenary(a, b, sag, float(i + 1) / segs), 0.006, Color(0.75, 0.73, 0.68, PAINT))
	var dir: Vector3 = (b - a).normalized()
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	var t: float = _rng.randf_range(0.3, 0.7)
	while t < len - 0.4:
		var kind: int = _rng.randi() % 3
		var w: float = [0.55, 0.6, 0.45][kind]
		var p: Vector3 = _catenary(a, b, sag, (t + w * 0.5) / len)
		var col: Color = LAUNDRY[_rng.randi() % LAUNDRY.size()].darkened(_rng.randf_range(0.0, 0.15))
		(_cloth[kind] as Array).append([Transform3D(Basis(dir, Vector3.UP, side).scaled(Vector3.ONE * _rng.randf_range(0.85, 1.1)), p), col])
		t += w + _rng.randf_range(0.08, 0.6)


## Lines across the streets between facades that face each other, and from the yard poles to
## the nearest facades across the road.
func _build_street_lines() -> void:
	var done: int = 0
	for i: int in _facades.size():
		for j: int in range(i + 1, _facades.size()):
			var fi: Dictionary = _facades[i]
			var fj: Dictionary = _facades[j]
			var ni: Vector2 = fi["face"]
			var nj: Vector2 = fj["face"]
			if ni.dot(nj) > -0.9:
				continue
			# Gap between the two facade planes along ni, and overlap along the street.
			var gap: float = ((fj["a"] as Vector2) - (fi["a"] as Vector2)).dot(ni)
			if gap < 8.0 or gap > 18.0:
				continue
			var ax: Vector2 = Vector2(absf(ni.y), absf(ni.x))
			var i0: float = minf((fi["a"] as Vector2).dot(ax), (fi["b"] as Vector2).dot(ax))
			var i1: float = maxf((fi["a"] as Vector2).dot(ax), (fi["b"] as Vector2).dot(ax))
			var j0: float = minf((fj["a"] as Vector2).dot(ax), (fj["b"] as Vector2).dot(ax))
			var j1: float = maxf((fj["a"] as Vector2).dot(ax), (fj["b"] as Vector2).dot(ax))
			var o0: float = maxf(i0, j0) + 0.8
			var o1: float = minf(i1, j1) - 0.8
			if o1 - o0 < 1.5:
				continue
			var hmax: float = mini(int(fi["floors"]), int(fj["floors"])) * FLOOR_H
			var pi0: float = (fi["a"] as Vector2).dot(ni)
			var lines: int = 0
			var t: float = o0 + _rng.randf_range(0.0, 1.0)
			while t < o1 and lines < 4:
				var pa: Vector2 = ax * t + ni * pi0
				var pb: Vector2 = ax * (t + _rng.randf_range(-1.5, 1.5)) + ni * (pi0 + gap)
				pb = ax * clampf(pb.dot(ax), o0, o1) + ni * pb.dot(ni)
				var kind: int = (lines + done) % 3
				if kind == 0:
					_string_lights(_xz(pa, minf(5.2, hmax - 0.5)), _xz(pb, minf(5.4, hmax - 0.5)), 0.9, false)
				elif kind == 1:
					_bunting(_xz(pa, minf(4.6, hmax - 0.8)), _xz(pb, minf(4.9, hmax - 0.8)), 0.8)
				elif hmax >= 8.0:
					_laundry_line(_xz(pa, 7.3), _xz(pb, 7.1), 0.5)
				lines += 1
				t += _rng.randf_range(2.0, 3.5)
			done += 1


# --- Hub yard ----------------------------------------------------------------------------

func _pole(base: Vector3, h: float) -> Vector3:
	var wood := Color(0.36, 0.27, 0.2, PAINT)
	_deco.box(Transform3D(Basis(Vector3.UP, _rng.randf() * 0.5), base + Vector3(0, h * 0.5, 0)), Vector3(0.16, h, 0.16), wood)
	_deco.box(Transform3D(Basis(), base + Vector3(0, h - 0.25, 0)), Vector3(0.7, 0.08, 0.08), wood.darkened(0.2))
	return base + Vector3(0, h - 0.2, 0)


func _pole_tops() -> Array[Vector3]:
	var y: float = CityLayout.YARD_HALF + 0.35
	var tops: Array[Vector3] = []
	for c: Vector2 in [Vector2(-y, -y), Vector2(y, -y), Vector2(y, y), Vector2(-y, y)]:
		tops.append(Vector3(c.x, 5.4, c.y))
	return tops


func _build_poles() -> void:
	for t: Vector3 in _pole_tops():
		_pole(Vector3(t.x, 0, t.z), 5.6)
		if biome == "frostcap":
			_deco.box(Transform3D(Basis(), Vector3(t.x, 5.64, t.z)), Vector3(0.2, 0.06, 0.2), SNOW)


func _build_festoons() -> void:
	var tops: Array[Vector3] = _pole_tops()
	# Perimeter and a cross over the yard: warm festoon lights.
	for i: int in 4:
		if i != 2:  # no run along the front edge: it would hang across the default camera view
			_string_lights(tops[i], tops[(i + 1) % 4], 1.0, true)
	_string_lights(tops[0], tops[2], 1.6, true, 0.6)
	_string_lights(tops[1], tops[3], 1.6, true, 0.6)
	# Bunting just under the back run.
	_bunting(tops[0] - Vector3(0, 0.45, 0), tops[1] - Vector3(0, 0.45, 0), 1.1)
	if not start_base and _style_flag(0.5):
		_bunting(tops[0] - Vector3(0, 0.5, 0), tops[3] - Vector3(0, 0.5, 0), 1.0)
	if biome == "fungal_marsh":
		_lanterns()
	if layout.wild:
		return
	# Out from each pole to the nearest facade across the street.
	for top: Vector3 in tops:
		var best: Vector2 = Vector2.INF
		var best_d: float = 28.0
		for f: Dictionary in _facades:
			if int(f["floors"]) < 2:
				continue
			var a: Vector2 = f["a"]
			var b: Vector2 = f["b"]
			var q := Vector2(top.x, top.z)
			var t: float = clampf((q - a).dot(b - a) / maxf((b - a).length_squared(), 0.01), 0.1, 0.9)
			var p: Vector2 = a.lerp(b, t)
			var d: float = p.distance_to(q)
			if d < best_d and (f["face"] as Vector2).dot(q - p) > 0.0:
				best_d = d
				best = p + (f["face"] as Vector2) * 0.1
		if best != Vector2.INF:
			_string_lights(top, _xz(best, 5.4), 1.4, false, 0.6)


func _build_yard_paint() -> void:
	var half: float = CityLayout.YARD_HALF
	var px: int = 512
	var mpp: float = half * 2.0 / px  # metres per pixel
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var to_px: Callable = func(w: Vector2) -> Vector2: return (w + Vector2(half, half)) / mpp
	var yellow: Color = _paint_main
	var white := Color(0.95, 0.94, 0.9, 0.85)
	var line: Callable = func(a: Vector2, b: Vector2, width_m: float, col: Color) -> void:
		var pa: Vector2 = to_px.call(a)
		var pb: Vector2 = to_px.call(b)
		var wpx: int = maxi(1, int(width_m / mpp))
		var steps: int = maxi(1, int(pa.distance_to(pb)))
		for k: int in steps + 1:
			var p: Vector2 = pa.lerp(pb, float(k) / steps)
			img.fill_rect(Rect2i(int(p.x) - wpx / 2, int(p.y) - wpx / 2, wpx, wpx), col)
	# Hazard border: diagonal yellow/black stripes in a band just inside the fence.
	var band: int = int(0.6 / mpp)
	var inset: int = int(0.12 / mpp)
	var spx: int = int(0.4 / mpp)
	for e: int in range(inset, inset + band):
		for i: int in range(e, px - e):
			for ij: Vector2i in [Vector2i(i, e), Vector2i(i, px - 1 - e), Vector2i(e, i), Vector2i(px - 1 - e, i)]:
				var stripe: bool = ((ij.x + ij.y) / spx) % 2 == 0
				img.set_pixelv(ij, _hazard_a if stripe else Color(0.07, 0.07, 0.07, 0.85))
	# Walkway: two yellow lines from the front edge in to the depot.
	line.call(Vector2(-1.1, half - 0.6), Vector2(-1.1, 0.4), 0.16, yellow)
	line.call(Vector2(1.1, half - 0.6), Vector2(1.1, 0.4), 0.16, yellow)
	# Numbered bays along the back fence (count and offset vary per base).
	var nb: int = 3 if start_base else _style.randi_range(2, 4)
	var bx0: float = -3.9 if start_base else _style.randf_range(-5.5, 5.5 - nb * 2.6)
	var digits: Array[String] = ["1", "2", "3", "4"]
	for k: int in nb:
		var x0: float = bx0 + k * 2.6
		line.call(Vector2(x0, -half + 0.6), Vector2(x0, -half + 3.6), 0.15, yellow)
		line.call(Vector2(x0 + 2.6, -half + 0.6), Vector2(x0 + 2.6, -half + 3.6), 0.15, yellow)
		_paint_glyph(img, digits[k], Vector2(x0 + 1.3, -half + 2.4), 0.75, white, to_px, line)
	line.call(Vector2(bx0, -half + 3.6), Vector2(bx0 + nb * 2.6, -half + 3.6), 0.15, yellow)
	# Arrows: to the hopper on the right, and along the walkway to the depot.
	_paint_arrow(Vector2(2.6, -0.6), Vector2(1, 0), 1.6, white, line)
	_paint_arrow(Vector2(0.0, 6.2), Vector2(0, -1), 1.4, white, line)
	_paint_arrow(Vector2(-3.0, -half + 4.6), Vector2(0, -1), 1.0, yellow, line)
	# Cracks with moss, wandering in from the edges (a neglected base has more).
	for k: int in (9 if start_base else 15):
		var side: int = _rng.randi() % 4
		var along: float = _rng.randf_range(-half + 1.0, half - 1.0)
		var p: Vector2 = [Vector2(along, -half), Vector2(half, along), Vector2(along, half), Vector2(-half, along)][side]
		var inward: Vector2 = [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)][side]
		var pts := PackedVector2Array([p])
		var dir: Vector2 = inward.rotated(_rng.randf_range(-0.5, 0.5))
		var steps: int = _rng.randi_range(8, 22)
		for s: int in steps:
			dir = dir.rotated(_rng.randf_range(-0.6, 0.6)).lerp(inward, 0.15).normalized()
			p += dir * _rng.randf_range(0.2, 0.4)
			pts.append(p)
		_cracks.append(pts)
		for s: int in pts.size() - 1:
			line.call(pts[s], pts[s + 1], 0.16, Color(0.24, 0.36, 0.12, 0.55))
		for s: int in pts.size() - 1:
			line.call(pts[s], pts[s + 1], 0.03, Color(0.06, 0.05, 0.04, 0.9))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://art/shaders/yard_slab.gdshader")
	mat.set_shader_parameter("paint", tex)
	mat.set_shader_parameter("conc_alb", AssetLib.tex("concrete_floor_worn_001", "diff"))
	mat.set_shader_parameter("conc_nrm", AssetLib.tex("concrete_floor_worn_001", "nor_gl"))
	mat.set_shader_parameter("conc_arm", AssetLib.tex("concrete_floor_worn_001", "arm"))
	mat.set_shader_parameter("asph_alb", AssetLib.tex("worn_asphalt", "diff"))
	mat.set_shader_parameter("asph_nrm", AssetLib.tex("worn_asphalt", "nor_gl"))
	mat.set_shader_parameter("half_size", half)
	mat.set_shader_parameter("bay", half * 2.0 / (6.0 if start_base else float(_style.randi_range(5, 7))))
	mat.set_shader_parameter("seed", float(layout.seed_value % 97))
	mat.set_shader_parameter("drift_col", _drift_col)
	if not start_base:
		# Broken-off slab corners: one or two, never the front-left (rocket pad) one.
		var cut := Vector4.ZERO
		for k: int in _style.randi_range(1, 2):
			var ci: int = [0, 1, 3][_style.randi() % 3]
			cut[ci] = _style.randf_range(1.8, 3.4)
		mat.set_shader_parameter("cut", cut)
	_slab_mat = mat
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0, half * 2.0)
	mi.mesh = pm
	mi.name = "YardSlab"
	mi.position = Vector3(0, 0.012, 0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cur.add_child(mi)


func _paint_glyph(img: Image, ch: String, center: Vector2, h: float, col: Color, _to_px: Callable, line: Callable) -> void:
	var s: float = h / 6.0
	# Painted on the ground, read from the hub (looking toward -z): glyph +y maps to world -z.
	for poly: Array in GLYPHS.get(ch, []):
		for k: int in poly.size() - 1:
			var a: Vector2 = poly[k]
			var b: Vector2 = poly[k + 1]
			line.call(center + Vector2((a.x - 2.0) * s, -(a.y - 3.0) * s), center + Vector2((b.x - 2.0) * s, -(b.y - 3.0) * s), 0.13, col)


func _paint_arrow(at: Vector2, dir: Vector2, length: float, col: Color, line: Callable) -> void:
	var tip: Vector2 = at + dir * length * 0.5
	var tail: Vector2 = at - dir * length * 0.5
	line.call(tail, tip, 0.18, col)
	line.call(tip, tip - dir.rotated(0.6) * length * 0.35, 0.18, col)
	line.call(tip, tip - dir.rotated(-0.6) * length * 0.35, 0.18, col)


func _build_puddles() -> void:
	var spots: Array = [Vector3(-1.9, 0, 0.9), Vector3(3.2, 0, -6.6), Vector3(-6.2, 0, 6.6), Vector3(2.6, 0, 6.9), Vector3(-2.6, 0, -4.4)]
	for p: Vector3 in spots:
		var s: float = _rng.randf_range(1.1, 1.9)
		_puddles.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, 1.0, s * _rng.randf_range(0.6, 0.9))), p + Vector3(0, 0.022, 0)))
	if layout.wild:
		return
	# Along the gutters of the roads around the hub.
	var e: float = CityLayout.PITCH * 0.5 - CityLayout.ROAD_W * 0.5
	for k: int in 6:
		var t: float = _rng.randf_range(-10.0, 10.0)
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		var pos: Vector3 = Vector3(t, 0.012, side * (e + 1.2)) if k % 2 == 0 else Vector3(side * (e + 1.2), 0.012, t)
		var s2: float = _rng.randf_range(1.8, 3.2)
		_puddles.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s2, 1.0, s2 * 0.6)), pos))


## Stacks of bright plastic crates and a barrel or two, tucked into the yard's fence corners
## (hub ground: no junk, no plant slots, nothing parks there).
func _build_crates() -> void:
	var y: float = CityLayout.YARD_HALF - 0.95
	var body := StaticBody3D.new()
	_cur.add_child(body)
	var corners: Array[Vector2] = [Vector2(-y, -y), Vector2(y, -y), Vector2(-y, y), Vector2(y, y)]
	# Which salvage kit sits in which corner: the starter yard keeps its classic set; elsewhere a
	# seeded pick, always with the work light (kit 3) and the biome's own kit when it has one.
	var kits: Array[int] = [0, 1, 2, 3]
	if not start_base:
		var pool: Array[int] = [0, 1, 2, 4, 5]
		for k: int in range(pool.size() - 1, 0, -1):
			var j: int = _style.randi() % (k + 1)
			var t: int = pool[k]
			pool[k] = pool[j]
			pool[j] = t
		var bk: int = {"frostcap": 10, "neon_coast": 11, "lake": 11, "dust_dunes": 12, "rustlands": 13, "fungal_marsh": 14}.get(biome, pool[3])
		kits = [pool[0], pool[1], 3, bk]
		for k: int in range(3, 0, -1):
			var j: int = _style.randi() % (k + 1)
			var t: int = kits[k]
			kits[k] = kits[j]
			kits[j] = t
	for ci: int in 4:
		var c: Vector2 = corners[ci]
		# Slide the kit in along the diagonal until it sits wholly on hub ground (no junk, no
		# plant slots): the hexagonal hub area doesn't reach the square yard's corners.
		for step: int in 12:
			if _on_hub_ground(Vector3(c.x, 0, c.y), 1.0):
				break
			c -= c.normalized() * 0.3
		var base := Vector3(c.x, 0, c.y)
		var out := Vector3(signf(c.x), 0, signf(c.y))
		_corner_kit(kits[ci], base, out)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.6, 1.0, 1.6)
		cs.shape = bs
		cs.position = base + Vector3(-out.x * 0.15, 0.5, -out.z * 0.15)
		body.add_child(cs)


func _corner_kit(kit: int, base: Vector3, out: Vector3) -> void:
	var yaw: float = _rng.randf_range(-0.2, 0.2)
	var top: float = 0.14
	var snow: bool = biome == "frostcap"
	if kit != 12 and kit != 14:
		# A pallet on the ground under everything.
		_pallet(Transform3D(Basis(Vector3.UP, yaw), base + Vector3(-out.x * 0.15, 0, -out.z * 0.15)))
	match kit:
		0:  # crate stack and a plastic barrel
			var n: int = _rng.randi_range(2, 4)
			for k: int in n:
				_crate(Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.12, 0.12)), base + Vector3(_rng.randf_range(-0.04, 0.04), top + 0.16 + k * 0.32, 0.0)), _plastic[_rng.randi() % _plastic.size()])
			if snow:
				_deco.box(Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, top + n * 0.32 + 0.02, 0)), Vector3(0.62, 0.06, 0.42), SNOW)
			_barrels.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), base + Vector3(-out.x * 1.0, 0, 0)), _plastic[1 % _plastic.size()]])
		1:  # steel drums and a tarp-covered heap
			for k: int in 3:
				var dp: Vector3 = base + Vector3(-out.x * (0.1 + (k % 2) * 0.62), top, -out.z * (k / 2) * 0.62 - out.z * 0.1)
				_drums.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), dp), [Color(0.55, 0.13, 0.08), Color(0.12, 0.25, 0.45), Color(0.2, 0.32, 0.18)][k]])
				if snow:
					_deco.cyl(dp + Vector3(0, 0.88, 0), dp + Vector3(0, 0.94, 0), 0.29, 0.25, SNOW, 10)
			_tarp(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)), base + Vector3(-out.x * 0.4, 0, -out.z * 1.5)), Vector2(1.8, 1.4), 0.75, _tarp_cols[0])
		2:  # stacked pallets and a crate
			for k: int in range(1, 4):
				_pallet(Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.08, 0.08)), base + Vector3(-out.x * 0.15, k * 0.14, -out.z * 0.15)))
			if snow:
				_deco.box(Transform3D(Basis(Vector3.UP, yaw), base + Vector3(-out.x * 0.15, 0.6, -out.z * 0.15)), Vector3(1.15, 0.07, 1.1), SNOW)
			_crate(Transform3D(Basis(Vector3.UP, yaw + 0.4), base + Vector3(-out.x * 1.05, 0.16, 0.1)), _plastic[_rng.randi() % _plastic.size()])
			_pot(base + Vector3(0.0, 0, -out.z * 1.1))
		3:  # tarp heap and a work light aimed into the yard
			_tarp(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)), base + Vector3(-out.x * 0.1, 0.0, -out.z * 0.1)), Vector2(1.6, 1.5), 0.9, _tarp_cols[1 % _tarp_cols.size()])
			_crate(Transform3D(Basis(Vector3.UP, yaw - 0.3), base + Vector3(-out.x * 1.1, 0.16, 0.0)), _plastic[_rng.randi() % _plastic.size()])
			_work_light(base + Vector3(-out.x * 0.6, 0, -out.z * 1.4), Vector3(-out.x, 0, -out.z).normalized())
		4:  # lumber pile: planks stacked crosswise
			var wood := Color(0.62, 0.5, 0.34, PAINT)
			for k: int in 5:
				var ky: float = top + 0.06 + k * 0.08
				var rot: float = yaw + (0.0 if k % 2 == 0 else 0.08)
				for q: int in 3:
					_deco.box(Transform3D(Basis(Vector3.UP, rot), base + Vector3((q - 1) * 0.28, ky, 0)), Vector3(0.24, 0.07, 1.5), wood.darkened(_rng.randf_range(0.0, 0.25)))
			_crate(Transform3D(Basis(Vector3.UP, yaw + 1.2), base + Vector3(-out.x * 1.05, 0.16, -out.z * 0.3)), _plastic[_rng.randi() % _plastic.size()])
		5:  # tyre stack and jerrycans
			for k: int in _rng.randi_range(3, 4):
				_prop("old_tyre", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), base + Vector3(_rng.randf_range(-0.05, 0.05), top + k * 0.24, 0)))
			for k: int in 2:
				_prop("metal_jerrycan", Transform3D(Basis(Vector3.UP, yaw + k * 0.3), base + Vector3(-out.x * (1.0 + k * 0.3), 0, -out.z * 0.2)))
		10:  # frostcap: heater barrel ringed by snowy crates
			_heater_barrel(base + Vector3(-out.x * 0.2, top, -out.z * 0.2))
			for k: int in 2:
				var cp: Vector3 = base + Vector3(-out.x * (1.0 + k * 0.1), 0.16, -out.z * (0.2 + k * 0.7))
				_crate(Transform3D(Basis(Vector3.UP, yaw + k), cp), _plastic[_rng.randi() % _plastic.size()])
				_deco.box(Transform3D(Basis(Vector3.UP, yaw + k), cp + Vector3(0, 0.18, 0)), Vector3(0.62, 0.05, 0.42), SNOW)
		11:  # coast: buoys and a lifebuoy
			_prop("ocean_buoy", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * 0.7), base + Vector3(0, top, 0)))
			_prop("lifebuoy", Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.15).rotated(Vector3.UP, atan2(out.x, out.z)), base + Vector3(out.x * 0.55, 0.9, -out.z * 0.5)))
			_drums.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), base + Vector3(-out.x * 1.0, 0, -out.z * 0.3)), Color(0.85, 0.85, 0.82)])
		12:  # dunes: sun-bleached tarp shade over jerrycans
			_tarp_shade(base + Vector3(-out.x * 0.6, 0, -out.z * 0.6), yaw)
			for k: int in 3:
				_prop("plastic_jerrycan" if k < 2 else "metal_jerrycan", Transform3D(Basis(Vector3.UP, yaw + k * 0.5), base + Vector3(-out.x * (0.3 + k * 0.4), 0, -out.z * 0.9)))
		13:  # rustlands: oil drum cluster, one toppled
			for k: int in 4:
				var dp: Vector3 = base + Vector3(-out.x * (0.1 + (k % 2) * 0.62), top, -out.z * (k / 2) * 0.62)
				_drums.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), dp), Color(0.42, 0.24, 0.14).lerp(Color(0.2, 0.22, 0.25), _rng.randf())])
			_drums.append([Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, yaw + 0.7), base + Vector3(-out.x * 1.3, 0.3, -out.z * 1.4)), Color(0.5, 0.28, 0.14)])
		14:  # marsh: lantern post and crates on a plank deck
			for k: int in 6:
				_deco.box(Transform3D(Basis(Vector3.UP, yaw), base + Vector3((k - 2.5) * 0.3 * -out.x, 0.04, -out.z * 0.4)), Vector3(0.26, 0.06, 1.8), Color(0.36, 0.28, 0.2, PAINT))
			_crate(Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, 0.22, -out.z * 0.2)), _plastic[_rng.randi() % _plastic.size()])
			_lantern_post(base + Vector3(-out.x * 1.0, 0, -out.z * 1.0))


func _on_hub_ground(p: Vector3, r: float) -> bool:
	if field == null:
		return true
	for o: Vector3 in [Vector3.ZERO, Vector3(r, 0, r), Vector3(-r, 0, r), Vector3(r, 0, -r), Vector3(-r, 0, -r)]:
		var hid: int = field.hex_at(p + o)
		if hid >= 0 and field.hex_hub[hid] == 0:
			return false
	return field.pieces_within(p, r + 0.4).is_empty()


func _pallet(xf: Transform3D) -> void:
	var wood := Color(0.6, 0.5, 0.36, PAINT).darkened(_rng.randf_range(0.0, 0.3))
	for k: int in 3:
		_deco.box(xf * Transform3D(Basis(), Vector3(0, 0.05, (k - 1) * 0.5)), Vector3(1.2, 0.09, 0.09), wood.darkened(0.15))
	for k: int in 7:
		if _rng.randf() < 0.08:
			continue  # a broken board
		_deco.box(xf * Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.02, 0.02)), Vector3((k - 3) * 0.19, 0.115, 0)), Vector3(0.12, 0.022, 1.12), wood)


## A tarpaulin thrown over a heap: a lumpy draped grid, drooping to the ground at the edges.
func _tarp(xf: Transform3D, size: Vector2, h: float, col: Color) -> void:
	col.a = FABRIC
	var n: int = 9
	var pts: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = _rng.randi()
	for j: int in n + 1:
		var row: Array = []
		for i: int in n + 1:
			var u: float = float(i) / n * 2.0 - 1.0
			var v: float = float(j) / n * 2.0 - 1.0
			var d: float = clampf(maxf(absf(u), absf(v)) * 0.6 + Vector2(u, v).length() * 0.5, 0.0, 1.0)
			var y: float = h * pow(1.0 - d * d, 0.8) * r.randf_range(0.75, 1.05) + 0.02
			row.append(xf * Vector3(u * size.x * 0.5, y, v * size.y * 0.5))
		pts.append(row)
	for j: int in n:
		for i: int in n:
			var shade: float = r.randf_range(0.85, 1.0)
			var cc := Color(col.r * shade, col.g * shade, col.b * shade, FABRIC)
			_deco.quad(pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i], cc)
	# Rope over the top.
	_deco.rod(pts[0][n / 2], pts[n / 2][n / 2] + Vector3.UP * 0.02, 0.012, Color(0.7, 0.62, 0.45, PAINT))
	_deco.rod(pts[n / 2][n / 2] + Vector3.UP * 0.02, pts[n][n / 2], 0.012, Color(0.7, 0.62, 0.45, PAINT))


## Construction work light on a tripod, lamp lit, cable snaking off along the fence.
func _work_light(base: Vector3, aim: Vector3) -> void:
	var steel := Color(0.85, 0.65, 0.1, STEEL)  # yellow-painted steel
	var top: Vector3 = base + Vector3.UP * 1.9
	for k: int in 3:
		var a: float = TAU * k / 3.0 + 0.3
		_deco.rod(top - Vector3.UP * 0.4, base + Vector3(cos(a), 0, sin(a)) * 0.55, 0.018, steel)
	_deco.rod(top - Vector3.UP * 0.4, top, 0.022, steel)
	var right: Vector3 = Vector3.UP.cross(aim).normalized()
	var head := Transform3D(Basis(right, Vector3.UP, aim).rotated(right, 0.35), top + Vector3.UP * 0.12)
	_deco.box(head, Vector3(0.42, 0.3, 0.14), Color(0.1, 0.1, 0.11, STEEL))
	_tubes.box(head.translated_local(Vector3(0, 0, 0.075)), Vector3(0.34, 0.22, 0.01), Color(1.0, 0.9, 0.75), Vector2(9.1, 0.0))
	var sl := SpotLight3D.new()
	sl.light_color = Color(1.0, 0.88, 0.72)
	sl.light_energy = 2.5
	sl.spot_range = 14.0
	sl.spot_angle = 38.0
	sl.shadow_enabled = false
	sl.transform = Transform3D(Basis.looking_at(head.basis.z, Vector3.UP), head.origin)
	_cur.add_child(sl)
	# Cable along the ground toward the shack.
	var cable := Color(0.05, 0.05, 0.05, PAINT)
	var p: Vector3 = base + Vector3(0, 0.015, 0)
	var goal := Vector3(-CityLayout.YARD_HALF + 0.5, 0.015, base.z)
	var steps: int = 24
	var prev: Vector3 = p
	for k: int in range(1, steps + 1):
		var t: float = float(k) / steps
		var q: Vector3 = p.lerp(goal, t) + Vector3(0, 0, sin(t * 17.0) * 0.12 + 0.25 * sin(t * PI))
		_deco.rod(prev, q, 0.012, cable)
		prev = q


## Weeds and wildflowers in the yard cracks, along the fence and in the gutters.
func _build_weeds() -> void:
	var ids: Array[String] = ["grass_medium_01", "weed_plant_02", "dandelion_01", "celandine_01", "flower_gazania"]
	var add: Callable = func(p: Vector3, scl: float) -> void:
		var id: String = ids[_rng.randi() % ids.size()] if _rng.randf() < 0.55 else ids[_rng.randi() % 2]
		if not _weeds.has(id):
			_weeds[id] = []
		(_weeds[id] as Array).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scl * _rng.randf_range(0.6, 1.1)), p))
	for pts: PackedVector2Array in _cracks:
		for s: int in pts.size():
			if _rng.randf() < 0.45:
				add.call(Vector3(pts[s].x, 0.0, pts[s].y) + Vector3(_rng.randf_range(-0.1, 0.1), 0, _rng.randf_range(-0.1, 0.1)), 0.55)
	var h: float = CityLayout.YARD_HALF - 0.15
	for k: int in 70:
		var t: float = _rng.randf_range(-h, h)
		var side: int = _rng.randi() % 4
		var p2: Vector2 = [Vector2(t, -h), Vector2(h, t), Vector2(t, h), Vector2(-h, t)][side]
		add.call(Vector3(p2.x, 0.0, p2.y), 0.7)


# --- Flush ---------------------------------------------------------------------------------

func _flush() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://art/shaders/deco.gdshader")
	mat.set_shader_parameter("grime_tex", AssetLib.tex("dirty_concrete", "diff"))
	mat.set_shader_parameter("grime_nrm", AssetLib.tex("dirty_concrete", "nor_gl"))
	if not _deco.empty():
		var mi := MeshInstance3D.new()
		mi.mesh = _deco.mesh()
		mi.material_override = mat
		mi.name = "Deco"
		_cur.add_child(mi)
	if not _tubes.empty():
		var nm := ShaderMaterial.new()
		nm.shader = preload("res://art/shaders/neon.gdshader")
		nm.set_shader_parameter("energy", 5.0)
		var ti := MeshInstance3D.new()
		ti.mesh = _tubes.mesh()
		ti.material_override = nm
		ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ti.name = "Neon"
		_cur.add_child(ti)
		if _cur == _layers.get("Base"):
			_shop_neon = nm
	if not _bulbs.is_empty():
		var bm := ShaderMaterial.new()
		bm.shader = preload("res://art/shaders/neon.gdshader")
		bm.set_shader_parameter("energy", 3.2)
		bm.set_shader_parameter("twinkle", 1.0)
		bm.set_shader_parameter("instance_seed", true)
		var bulb := _bulb_mesh()
		_mm("Bulbs", bulb, _bulbs, bm, false)
	var fabric := ShaderMaterial.new()
	fabric.shader = preload("res://art/shaders/fabric.gdshader")
	if not _pennants.is_empty():
		_mm("Bunting", _pennant_mesh(), _pennants, fabric, true)
	var cloth_meshes: Array = [_cloth_mesh(0), _cloth_mesh(1), _cloth_mesh(2)]
	for k: int in 3:
		if not (_cloth[k] as Array).is_empty():
			_mm("Laundry%d" % k, cloth_meshes[k], _cloth[k], fabric, true)
	if not _crates.is_empty():
		_mm("Crates", _crate_mesh(), _crates, mat, true)
	if not _drums.is_empty():
		_mm("Drums", _drum_mesh(), _drums, mat, true)
	if not _barrels.is_empty():
		_mm("Barrels", _barrel_mesh(), _barrels, mat, true)
	if not _pots.is_empty():
		_mm("Pots", _pot_mesh(), _pots, mat, true)
	if not _twigs.is_empty():
		_mm("DeadPlants", _twig_mesh(), _twigs, mat, true)
	if not _puddles.is_empty():
		var pm := ShaderMaterial.new()
		pm.shader = preload("res://art/shaders/puddle.gdshader")
		var items: Array = []
		for xf: Transform3D in _puddles:
			items.append([xf, Color.WHITE])
		var qm := PlaneMesh.new()
		qm.size = Vector2(1, 1)
		_mm("Puddles", qm, items, pm, false, false)
	if not _flags.is_empty():
		var flag_mat := ShaderMaterial.new()
		flag_mat.shader = preload("res://art/shaders/fabric.gdshader")
		flag_mat.set_shader_parameter("sway", 0.16)
		_mm("Flags", _flag_mesh(), _flags, flag_mat, true)
	for id: String in _props:
		var items3: Array = []
		for xf: Transform3D in _props[id]:
			items3.append([xf, Color.WHITE])
		_mm("Prop_" + id, AssetLib.model_mesh_lite(id, 1500), items3, null, true, false)
	for id: String in _weeds:
		var items2: Array = []
		for xf: Transform3D in _weeds[id]:
			items2.append([xf, Color.WHITE])
		var mi2: MultiMeshInstance3D = _mm("Weeds_" + id, AssetLib.model_mesh_lite(id, 400), items2, null, false, false)
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi2.visibility_range_end = 70.0


func _mm(nm: String, mesh: Mesh, items: Array, mat: Material, shadows: bool, colors: bool = true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i: int in items.size():
		mm.set_instance_transform(i, items[i][0])
		if colors:
			mm.set_instance_color(i, items[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 160.0
	_cur.add_child(mmi)
	return mmi


# --- Small meshes ---------------------------------------------------------------------------

func _bulb_mesh() -> ArrayMesh:
	var g := Geo.new()
	var sm := ProcMesh.sphere(0.055, 8, 4)
	var arr: Array = sm.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for k: int in range(0, ix.size(), 3):
		for q: int in 3:
			var vi: int = ix[k + q]
			g.v.append(vs[vi] * Vector3(1.0, 1.35, 1.0))
			g.n.append(ns[vi])
			g.c.append(Color.WHITE)
			g.u.append(Vector2.ZERO)
	return g.mesh()


func _pennant_mesh() -> ArrayMesh:
	var g := Geo.new()
	# Two rows so the tip can sway.
	var a := Vector3(-0.15, 0, 0)
	var b := Vector3(0.15, 0, 0)
	var m1 := Vector3(-0.075, -0.17, 0)
	var m2 := Vector3(0.075, -0.17, 0)
	var tip := Vector3(0, -0.34, 0)
	g.quad(a, b, m2, m1, Color.WHITE, Vector2.ZERO, Vector3.BACK)
	g.tri(m1, m2, tip, Vector3.BACK, Color.WHITE)
	return g.mesh()


func _cloth_mesh(kind: int) -> ArrayMesh:
	var g := Geo.new()
	var rects: Array = []  # [x0, x1, y0, y1] hanging down from y = 0
	match kind:
		0:
			rects = [[-0.27, 0.27, -0.75, 0.0]]
		1:
			rects = [[-0.2, 0.2, -0.62, 0.0], [-0.34, -0.2, -0.22, 0.0], [0.2, 0.34, -0.22, 0.0]]
		_:
			rects = [[-0.2, 0.2, -0.14, 0.0], [-0.2, -0.02, -0.85, -0.14], [0.02, 0.2, -0.85, -0.14]]
	for r: Array in rects:
		var rows: int = maxi(1, int((float(r[3]) - float(r[2])) / 0.15))
		for j: int in rows:
			var y0: float = lerpf(r[3], r[2], float(j) / rows)
			var y1: float = lerpf(r[3], r[2], float(j + 1) / rows)
			g.quad(Vector3(r[0], y0, 0), Vector3(r[1], y0, 0), Vector3(r[1], y1, 0), Vector3(r[0], y1, 0), Color.WHITE, Vector2.ZERO, Vector3.BACK)
	return g.mesh()


func _crate_mesh() -> ArrayMesh:
	var g := Geo.new()
	var w: float = 0.6
	var d: float = 0.4
	var h: float = 0.32
	var t: float = 0.03
	var dark := Color(0.55, 0.55, 0.55, PLAST)
	var wht := Color(1, 1, 1, PLAST)
	var rib := Color(0.85, 0.85, 0.85, PLAST)
	# Four walls and a floor: an open-top crate.
	g.box(Transform3D(Basis(), Vector3(0, 0, d * 0.5 - t * 0.5)), Vector3(w, h, t), wht)
	g.box(Transform3D(Basis(), Vector3(0, 0, -d * 0.5 + t * 0.5)), Vector3(w, h, t), wht)
	g.box(Transform3D(Basis(), Vector3(w * 0.5 - t * 0.5, 0, 0)), Vector3(t, h, d), wht)
	g.box(Transform3D(Basis(), Vector3(-w * 0.5 + t * 0.5, 0, 0)), Vector3(t, h, d), wht)
	g.box(Transform3D(Basis(), Vector3(0, -h * 0.5 + 0.02, 0)), Vector3(w, 0.04, d), dark)
	# Ribs and handle slots.
	for x: float in [-0.15, 0.0, 0.15]:
		g.box(Transform3D(Basis(), Vector3(x, 0, d * 0.5 + 0.005)), Vector3(0.025, h * 0.9, 0.012), rib)
		g.box(Transform3D(Basis(), Vector3(x, 0, -d * 0.5 - 0.005)), Vector3(0.025, h * 0.9, 0.012), rib)
	for sx: float in [-1.0, 1.0]:
		g.box(Transform3D(Basis(), Vector3(sx * (w * 0.5 + 0.003), h * 0.28, 0)), Vector3(0.012, 0.05, 0.16), Color(0.1, 0.1, 0.1, PLAST))
	return g.mesh()


func _barrel_mesh() -> ArrayMesh:
	var parts: Array = [
		ProcMesh.part(ProcMesh.cyl(0.29, 0.29, 0.9, 14), ProcMesh.xf(Vector3(0, 0.45, 0)), Color(1, 1, 1, PLAST)),
		ProcMesh.part(ProcMesh.cyl(0.305, 0.305, 0.05, 14), ProcMesh.xf(Vector3(0, 0.3, 0)), Color(0.85, 0.85, 0.85, PLAST)),
		ProcMesh.part(ProcMesh.cyl(0.305, 0.305, 0.05, 14), ProcMesh.xf(Vector3(0, 0.62, 0)), Color(0.85, 0.85, 0.85, PLAST)),
		ProcMesh.part(ProcMesh.cyl(0.05, 0.05, 0.04, 8), ProcMesh.xf(Vector3(0.14, 0.91, 0.05)), Color(0.2, 0.2, 0.2, PLAST)),
	]
	return ProcMesh.merge(parts)


func _drum_mesh() -> ArrayMesh:
	var m := Color(1, 1, 1, STEEL)
	var parts: Array = [
		ProcMesh.part(ProcMesh.cyl(0.29, 0.29, 0.88, 16), ProcMesh.xf(Vector3(0, 0.44, 0)), m),
		ProcMesh.part(ProcMesh.cyl(0.3, 0.3, 0.03, 16), ProcMesh.xf(Vector3(0, 0.29, 0)), m),
		ProcMesh.part(ProcMesh.cyl(0.3, 0.3, 0.03, 16), ProcMesh.xf(Vector3(0, 0.59, 0)), m),
		ProcMesh.part(ProcMesh.cyl(0.3, 0.3, 0.025, 16), ProcMesh.xf(Vector3(0, 0.875, 0)), Color(0.8, 0.8, 0.8, STEEL)),
	]
	return ProcMesh.merge(parts)


func _pot_mesh() -> ArrayMesh:
	var parts: Array = [
		ProcMesh.part(ProcMesh.cyl(0.2, 0.14, 0.32, 12), ProcMesh.xf(Vector3(0, 0.16, 0)), Color(1, 1, 1, PAINT)),
		ProcMesh.part(ProcMesh.cyl(0.225, 0.225, 0.06, 12), ProcMesh.xf(Vector3(0, 0.31, 0)), Color(0.9, 0.9, 0.9, PAINT)),
		ProcMesh.part(ProcMesh.cyl(0.19, 0.19, 0.02, 12), ProcMesh.xf(Vector3(0, 0.335, 0)), Color(0.16, 0.12, 0.09, PAINT)),
	]
	return ProcMesh.merge(parts)


func _twig_mesh() -> ArrayMesh:
	var g := Geo.new()
	var r := RandomNumberGenerator.new()
	r.seed = 5150
	for k: int in 6:
		var a := Vector3(r.randf_range(-0.05, 0.05), 0.03, r.randf_range(-0.05, 0.05))
		var lean := Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2))
		var b: Vector3 = a + Vector3(0, r.randf_range(0.25, 0.55), 0) + lean
		g.rod(a, b, 0.008, Color(1, 1, 1, PAINT))
		var m: Vector3 = a.lerp(b, r.randf_range(0.4, 0.7))
		g.rod(m, m + Vector3(r.randf_range(-0.12, 0.12), r.randf_range(0.0, 0.12), r.randf_range(-0.12, 0.12)), 0.006, Color(1, 1, 1, PAINT))
		# Drooping dead leaf.
		g.quad(b, b + Vector3(0.05, -0.02, 0), b + Vector3(0.06, -0.09, 0.01), b + Vector3(0.0, -0.06, 0), Color(0.8, 0.7, 0.45, PAINT))
	return g.mesh()


# --- Per-district style ------------------------------------------------------------------

func _shuffled(arr: Array) -> Array:
	var b: Array = arr.duplicate()
	for k: int in range(b.size() - 1, 0, -1):
		var j: int = _style.randi() % (k + 1)
		var t: Variant = b[k]
		b[k] = b[j]
		b[j] = t
	return b


func _style_flag(p: float) -> bool:
	return _style.randf() < p


## Palette, paint, sign and drift for this district, all from its seed.
func _pick_style() -> void:
	_pennant.assign(PENNANT)
	_plastic.assign(PLASTIC)
	_awning_cols.assign(AWNING)
	_tarp_cols.assign([Color(0.13, 0.32, 0.62), Color(0.55, 0.5, 0.2)])
	match biome:
		"dust_dunes":
			_drift = 0.8
			_drift_col = Color(0.88, 0.74, 0.52)
		"frostcap":
			_drift = 0.85
			_drift_col = Color(0.9, 0.93, 0.97)
		"neon_coast", "lake":
			_drift = 0.45
			_drift_col = Color(0.86, 0.79, 0.62)
		"fungal_marsh":
			_drift = 0.5
			_drift_col = Color(0.24, 0.27, 0.15)
		"rustlands":
			_drift = 0.35
			_drift_col = Color(0.56, 0.36, 0.22)
	if start_base:
		return
	_pennant.assign(_shuffled(PENNANT).slice(0, _style.randi_range(3, 5)))
	_plastic.assign(_shuffled(PLASTIC).slice(0, _style.randi_range(3, 4)))
	_awning_cols.assign(_shuffled(AWNING).slice(0, 3))
	var paints: Array = [Color(0.98, 0.78, 0.1, 0.92), Color(0.95, 0.94, 0.9, 0.88), Color(1.0, 0.5, 0.12, 0.92),
		Color(0.15, 0.75, 0.7, 0.9), Color(0.88, 0.22, 0.16, 0.9), Color(0.35, 0.6, 0.95, 0.9)]
	_paint_main = paints[(hub_index + _style.randi()) % paints.size()]
	_hazard_a = _paint_main
	var tarps: Array = _shuffled([Color(0.13, 0.32, 0.62), Color(0.55, 0.5, 0.2), Color(0.6, 0.18, 0.14),
		Color(0.2, 0.4, 0.25), Color(0.8, 0.45, 0.15), Color(0.35, 0.4, 0.5)])
	_tarp_cols.assign(tarps.slice(0, 2))
	if biome == "dust_dunes":
		for i: int in _tarp_cols.size():
			_tarp_cols[i] = _tarp_cols[i].lerp(Color(0.93, 0.88, 0.78), 0.6)
	_sign_bg = [Color(0.12, 0.25, 0.22), Color(0.55, 0.12, 0.1), Color(0.1, 0.16, 0.35), Color(0.85, 0.75, 0.55),
		Color(0.2, 0.2, 0.2), Color(0.18, 0.4, 0.5), Color(0.92, 0.9, 0.84)][_style.randi() % 7]
	_lm_col = [Color(0.35, 0.55, 0.62), Color(0.7, 0.32, 0.25), Color(0.82, 0.78, 0.68), Color(0.3, 0.45, 0.3),
		Color(0.85, 0.6, 0.2), Color(0.45, 0.42, 0.6)][_style.randi() % 6]
	_warm = _style.randf_range(0.35, 0.95)
	_sign_x = [-4.2, -3.4, 3.4, 4.2][_style.randi() % 4]


func _prop(id: String, xf: Transform3D) -> void:
	if not _props.has(id):
		_props[id] = []
	(_props[id] as Array).append(xf)


func _label(text: String, xf: Transform3D, font: int, pixel: float, col: Color, unshaded: bool = false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font
	l.pixel_size = pixel
	l.outline_size = 0
	l.modulate = col
	l.shaded = not unshaded
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED if unshaded else Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.transform = xf
	l.visibility_range_end = 120.0
	_cur.add_child(l)
	return l


var _lm_body: StaticBody3D


func _col(pos: Vector3, size: Vector3, b: Basis = Basis()) -> void:
	if field and field.hex_at(pos) >= 0 and field.hex_hub[field.hex_at(pos)] == 0:
		return  # never block junk
	if _lm_body == null:
		_lm_body = StaticBody3D.new()
		_cur.add_child(_lm_body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(b, pos)
	_lm_body.add_child(cs)


func _facing(p: Vector3) -> Vector3:
	var f: Vector3 = Vector3(0, 0, 6) - p
	f.y = 0.0
	return f.normalized()


## Lattice mast/boom from a to b: `legs` chords (3 or 4), width w0 -> w1, braced every `step` m.
func _truss(a: Vector3, b: Vector3, w0: float, w1: float, legs: int, col: Color, step: float, r: float = 0.06) -> void:
	var axv: Vector3 = b - a
	var l: float = axv.length()
	var dir: Vector3 = axv / l
	var x: Vector3 = dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var y: Vector3 = dir.cross(x).normalized()
	var levels: int = maxi(1, roundi(l / step))
	var k_r: float = 1.414 if legs == 4 else 1.15
	var corner: Callable = func(k: int, t: float) -> Vector3:
		var w: float = lerpf(w0, w1, t) * 0.5 * k_r
		var ang: float = TAU * k / legs + PI * 0.25
		return a + axv * t + (x * cos(ang) + y * sin(ang)) * w
	for k: int in legs:
		_deco.rod(corner.call(k, 0.0), corner.call(k, 1.0), r, col)
	for lv: int in levels:
		var t0: float = float(lv) / levels
		var t1: float = float(lv + 1) / levels
		for k: int in legs:
			var k2: int = (k + 1) % legs
			_deco.rod(corner.call(k, t1), corner.call(k2, t1), r * 0.6, col)
			_deco.rod(corner.call(k, t0), corner.call(k2, t1), r * 0.5, col)


## A low heap (sand, snow, mud) as a lumpy draped grid.
func _mound(xf: Transform3D, size: Vector2, h: float, col: Color) -> void:
	var n: int = 7
	var pts: Array = []
	for j: int in n + 1:
		var row: Array = []
		for i: int in n + 1:
			var u: float = float(i) / n * 2.0 - 1.0
			var v: float = float(j) / n * 2.0 - 1.0
			var d: float = clampf(Vector2(u, v).length(), 0.0, 1.0)
			row.append(xf * Vector3(u * size.x * 0.5, h * (1.0 - d * d) * _rng.randf_range(0.85, 1.05) - 0.02, v * size.y * 0.5))
		pts.append(row)
	for j: int in n:
		for i: int in n:
			var sh: float = _rng.randf_range(0.93, 1.0)
			_deco.quad(pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i], Color(col.r * sh, col.g * sh, col.b * sh, PAINT))


## Sand / snow / silt heaped against the inside of the fence (more on a neglected base).
func _build_drifts(amount: float) -> void:
	if _drift <= 0.0 or biome == "rustlands":
		return
	var h: float = CityLayout.YARD_HALF - 0.7
	for k: int in int(10 * amount * _drift):
		var side: int = _rng.randi() % 3  # back, left, right
		var t: float = _rng.randf_range(-h + 1.8, h - 1.8)
		var p: Vector3 = [Vector3(t, 0, -h), Vector3(-h, 0, t), Vector3(h, 0, t)][side]
		if absf(p.x) < 2.5 and p.z > 0.0:
			continue
		var sz := Vector2(_rng.randf_range(1.6, 3.4), _rng.randf_range(0.9, 1.5))
		var yaw: float = 0.0 if side == 0 else PI * 0.5
		_mound(Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.2, 0.2)), p), sz, _rng.randf_range(0.15, 0.35) * (0.7 + amount * 0.5), _drift_col)


# --- Landmark: one big silhouette per base, just outside the yard --------------------------

func _build_landmark() -> void:
	var city_kinds: Array[String] = ["water_tower", "crane", "ferris_wheel", "radio_mast", "smokestack", "old_bus"]
	match biome:
		"":
			_lm_kind = city_kinds[hub_index % city_kinds.size()]
		"dust_dunes":
			_lm_kind = "windpump"
		"frostcap":
			_lm_kind = "radio_mast"
		"neon_coast", "lake":
			_lm_kind = "lighthouse"
		"fungal_marsh":
			_lm_kind = "ferris_wheel"
		"rustlands":
			_lm_kind = ["crane", "windpump", "water_tower", "smokestack", "radio_mast", "old_bus"][hub_index % 6]
		_:
			_lm_kind = "water_tower"
	var side: float = 1.0 if start_base or _style.randi() % 2 == 0 else -1.0
	# Out past the junk field (its collision must never cover junk), in the default view.
	var foot: float = {"ferris_wheel": 7.0, "old_bus": 6.0, "smokestack": 7.0, "lighthouse": 3.0}.get(_lm_kind, 3.5)
	_lm_pos = _far_spot(side, foot, 0.12, 0.55)
	match _lm_kind:
		"water_tower":
			_water_tower(_lm_pos)
		"crane":
			_crane(_lm_pos)
		"ferris_wheel":
			_ferris(_lm_pos)
		"radio_mast":
			_radio_mast(_lm_pos)
		"smokestack":
			_smokestack(_lm_pos)
		"old_bus":
			_old_bus(_lm_pos)
		"windpump":
			_windpump(_lm_pos)
		"lighthouse":
			_lighthouse(_lm_pos)
	# Biome wrecks and camp buildings: the old camp, out on the other side.
	if biome == "dust_dunes":
		var cp: Vector3 = _far_spot(-side, 3.5, 0.1, 0.5)
		_caravan(cp, atan2(cp.x, cp.z) + PI * 0.5 + 0.3)
	elif biome == "neon_coast" or biome == "lake":
		_beach_shack(_far_spot(-side, 3.0, 0.1, 0.5))


## A seeded ground spot beyond the junk field, `a0..a1` radians off the -z view axis on `side`,
## clear of junk hexes (and of city buildings) for `r` metres around.
func _far_spot(side: float, r: float, a0: float, a1: float) -> Vector3:
	var best := Vector3(side * 20.0, 0, -52.0)
	for attempt: int in 60:
		var ang: float = -PI * 0.5 + side * _style.randf_range(a0, a1 + attempt * 0.01)
		var d0: float = maxf(47.0, field.hex_size * (field.radius + 0.6) * 1.732) if field and field.radius > 3 else 47.0  # [biomes] bigger frontier fields
		var dist: float = _style.randf_range(d0, d0 + 13.0 + attempt * 0.3)
		var p := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var ok: bool = true
		for o: Vector3 in [Vector3.ZERO, Vector3(r, 0, r), Vector3(-r, 0, r), Vector3(r, 0, -r), Vector3(-r, 0, -r), Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
			if field and field.hex_at(p + o) >= 0:
				ok = false
				break
			if not layout.wild and layout.surface_at(p.x + o.x, p.z + o.z) == CityLayout.Surface.BUILDING:
				ok = false
				break
		if ok:
			return p
	return best


func _water_tower(p: Vector3) -> void:
	var leg := Color(0.3, 0.29, 0.28, STEEL)
	var tank := Color(_lm_col.r, _lm_col.g, _lm_col.b, STEEL)
	var cs: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var at: Callable = func(c: Vector2, y: float) -> Vector3:
		var w: float = lerpf(2.3, 1.7, y / 12.0)
		return p + Vector3(c.x * w, y, c.y * w)
	for c: Vector2 in cs:
		_deco.rod(at.call(c, 0.0), at.call(c, 12.0), 0.13, leg)
		_col(at.call(c, 1.0), Vector3(0.5, 2.0, 0.5))
	for lv: int in 3:
		var y0: float = lv * 4.0
		var y1: float = y0 + 4.0
		for i: int in 4:
			var c0: Vector2 = cs[i]
			var c1: Vector2 = cs[(i + 1) % 4]
			_deco.rod(at.call(c0, y1), at.call(c1, y1), 0.06, leg)
			_deco.rod(at.call(c0, y0), at.call(c1, y1), 0.035, leg)
			_deco.rod(at.call(c1, y0), at.call(c0, y1), 0.035, leg)
	_deco.cyl(p + Vector3(0, 11.9, 0), p + Vector3(0, 12.05, 0), 3.7, 3.7, leg, 20)
	_deco.ring(p + Vector3(0, 13.0, 0), Vector3.RIGHT, Vector3.BACK, 3.65, 24, 0.035, leg)
	for i: int in 12:
		var a: float = TAU * i / 12.0
		_deco.rod(p + Vector3(cos(a) * 3.65, 12.05, sin(a) * 3.65), p + Vector3(cos(a) * 3.65, 13.0, sin(a) * 3.65), 0.03, leg)
	_deco.cyl(p + Vector3(0, 12.05, 0), p + Vector3(0, 16.6, 0), 3.0, 3.0, tank, 20)
	_deco.cyl(p + Vector3(0, 16.6, 0), p + Vector3(0, 18.2, 0), 3.15, 0.2, tank.darkened(0.2), 20)
	for y: float in [13.6, 15.4]:
		_deco.cyl(p + Vector3(0, y, 0), p + Vector3(0, y + 0.12, 0), 3.05, 3.05, leg, 20, false)
	var lp: Vector3 = at.call(cs[2], 0.0)
	for e: float in [-0.25, 0.25]:
		_deco.rod(lp + Vector3(e, 0, 0.3), lp + Vector3(e, 12.0, 0.3), 0.025, leg)
	for k: int in 30:
		_deco.rod(lp + Vector3(-0.25, k * 0.4, 0.3), lp + Vector3(0.25, k * 0.4, 0.3), 0.018, leg)
	var f: Vector3 = _facing(p)
	var txt: String = district.to_upper()
	var ink: Color = Color(0.96, 0.94, 0.86) if _lm_col.get_luminance() < 0.55 else Color(0.25, 0.12, 0.08)
	_label(txt, Transform3D(Basis(Vector3.UP.cross(f), Vector3.UP, f), p + Vector3(0, 14.4, 0) + f * 3.04), 128, minf(0.011, 4.6 / (txt.length() * 128 * 0.62)), ink)
	_lm_top = p + Vector3(0, 18.4, 0)


func _radio_mast(p: Vector3) -> void:
	var red := Color(0.78, 0.2, 0.15, STEEL)
	var wht := Color(0.88, 0.88, 0.85, STEEL)
	for sg: int in 7:
		var h0: float = sg * 4.0
		_truss(p + Vector3(0, h0, 0), p + Vector3(0, h0 + 4.0, 0), lerpf(2.8, 0.55, h0 / 28.0), lerpf(2.8, 0.55, (h0 + 4.0) / 28.0), 3, red if sg % 2 == 0 else wht, 2.0, 0.07)
	_deco.rod(p + Vector3(0, 28, 0), p + Vector3(0, 33, 0), 0.06, wht)
	var f: Vector3 = _facing(p)
	for spec: Array in [[18.0, 1.5], [22.5, 0.9]]:
		var c: Vector3 = p + Vector3(0, float(spec[0]), 0) + f * 0.5
		_deco.cyl(c, c + f * 0.55, 0.15, float(spec[1]), wht, 16)
	var away: float = atan2(p.z, p.x)
	for k: int in 3:
		var a: float = away + (k - 1) * 1.1
		_deco.rod(p + Vector3(0, 20, 0), p + Vector3(cos(a) * 10.0, 0.0, sin(a) * 10.0), 0.02, Color(0.2, 0.2, 0.2, STEEL))
	_col(p + Vector3(0, 1.5, 0), Vector3(2.6, 3.0, 2.6))
	_lm_top = p + Vector3(0, 33.3, 0)


func _crane(p: Vector3) -> void:
	var yel := Color(0.9, 0.66, 0.1, STEEL)
	var grey := Color(0.55, 0.54, 0.52, PAINT)
	_deco.box(Transform3D(Basis(), p + Vector3(0, 0.4, 0)), Vector3(3.2, 0.8, 3.2), grey)
	_col(p + Vector3(0, 1.0, 0), Vector3(3.2, 2.0, 3.2))
	_truss(p + Vector3(0, 0.8, 0), p + Vector3(0, 20.8, 0), 1.6, 1.6, 4, yel, 2.0, 0.07)
	var tc: Vector3 = p + Vector3(0, 21.2, 0)
	_deco.box(Transform3D(Basis(), tc), Vector3(2.2, 0.7, 2.2), Color(0.2, 0.2, 0.22, STEEL))
	var jd: Vector3 = Vector3(-signf(p.x), 0, _style.randf_range(0.1, 0.6)).normalized()
	var cab := Transform3D(Basis.looking_at(-jd), tc + Vector3(0, 0.9, 0) + jd.cross(Vector3.UP) * 1.2)
	_deco.box(cab, Vector3(1.3, 1.4, 1.5), yel)
	_deco.box(cab.translated_local(Vector3(0, 0.2, 0.76)), Vector3(1.1, 0.7, 0.03), GLASS)
	var apex: Vector3 = tc + Vector3(0, 4.2, 0)
	for c: Vector2 in [Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.8), Vector2(-0.8, 0.8)]:
		_deco.rod(tc + Vector3(c.x, 0.35, c.y), apex, 0.06, yel)
	var j0: Vector3 = tc + Vector3(0, 0.6, 0)
	_truss(j0 + jd * 1.1, j0 + jd * 21.0, 1.3, 0.7, 3, yel, 2.0, 0.05)
	_truss(j0 - jd * 1.1, j0 - jd * 7.5, 1.3, 1.3, 3, yel, 2.0, 0.05)
	var cw := Transform3D(Basis.looking_at(jd), j0 - jd * 6.6 - Vector3(0, 0.9, 0))
	_deco.box(cw, Vector3(1.6, 1.8, 1.8), grey)
	_deco.rod(apex, j0 + jd * 21.0, 0.03, Color(0.2, 0.2, 0.2, STEEL))
	_deco.rod(apex, j0 - jd * 7.5, 0.03, Color(0.2, 0.2, 0.2, STEEL))
	var tr: Vector3 = j0 + jd * 13.0 - Vector3(0, 0.7, 0)
	_deco.box(Transform3D(Basis.looking_at(jd), tr), Vector3(0.9, 0.3, 0.9), Color(0.2, 0.2, 0.22, STEEL))
	_deco.rod(tr, Vector3(tr.x, 7.5, tr.z), 0.02, Color(0.15, 0.15, 0.15, STEEL))
	_deco.box(Transform3D(Basis(), Vector3(tr.x, 7.2, tr.z)), Vector3(0.5, 0.7, 0.4), Color(0.85, 0.5, 0.1, STEEL))
	_lm_top = apex + Vector3(0, 0.3, 0)


func _ferris(p: Vector3) -> void:
	var rim := Color(_lm_col.r, _lm_col.g, _lm_col.b, STEEL)
	var leg := Color(0.82, 0.8, 0.76, STEEL)
	var hubp: Vector3 = p + Vector3(0, 11.0, 0)
	var big_r: float = 9.5
	var gap0: float = _style.randf() * TAU
	var gap: float = 1.3
	var in_gap: Callable = func(a: float) -> bool: return fposmod(a - gap0, TAU) < gap
	var pt: Callable = func(a: float, r: float, z: float) -> Vector3: return hubp + Vector3(cos(a) * r, sin(a) * r, z)
	for z: float in [-1.0, 1.0]:
		for i: int in 36:
			var a0: float = TAU * i / 36.0
			var a1: float = TAU * (i + 1) / 36.0
			if in_gap.call(a0) or in_gap.call(a1):
				continue
			_deco.rod(pt.call(a0, big_r, z), pt.call(a1, big_r, z), 0.12, rim)
			_deco.rod(pt.call(a0, big_r * 0.55, z), pt.call(a1, big_r * 0.55, z), 0.07, rim)
	for i: int in 16:
		var a: float = TAU * i / 16.0
		if in_gap.call(a):
			continue
		for z: float in [-1.0, 1.0]:
			_deco.rod(pt.call(a, 0.4, z), pt.call(a, big_r, z), 0.045, leg)
		_deco.rod(pt.call(a, big_r, -1.0), pt.call(a, big_r, 1.0), 0.05, rim)
		if i % 2 == 0:
			var g: Vector3 = pt.call(a, big_r, 0.0)
			_deco.rod(g, g - Vector3(0, 0.7, 0), 0.03, leg)
			var gc: Color = _pennant[i % _pennant.size()].lerp(Color(0.8, 0.78, 0.72), 0.35)
			gc.a = STEEL
			_deco.box(Transform3D(Basis(Vector3.UP, 0.2), g - Vector3(0, 1.25, 0)), Vector3(1.3, 1.1, 1.0), gc)
	for z: float in [-1.6, 1.6]:
		for x: float in [-5.0, 5.0]:
			var foot: Vector3 = p + Vector3(x, 0, z * 1.8)
			_deco.rod(hubp + Vector3(0, 0, z), foot, 0.18, leg)
			_col(foot + Vector3(0, 1.0, 0), Vector3(0.6, 2.0, 0.6))
	_deco.cyl(hubp + Vector3(0, 0, -1.9), hubp + Vector3(0, 0, 1.9), 0.45, 0.45, Color(0.25, 0.25, 0.27, STEEL), 12)
	var fallen := Color(_pennant[0].r, _pennant[0].g, _pennant[0].b, STEEL).lerp(Color(0.6, 0.55, 0.5, STEEL), 0.4)
	_deco.box(Transform3D(Basis(Vector3(0.3, 0.2, 1).normalized(), 1.2), p + Vector3(3.5, 0.5, 3.0)), Vector3(1.3, 1.1, 1.0), fallen)
	_lm_top = hubp + Vector3(0, big_r + 0.4, 0)


func _lighthouse(p: Vector3) -> void:
	var red := Color(0.8, 0.18, 0.14, PAINT)
	var cream := Color(0.93, 0.9, 0.82, PAINT)
	for i: int in 8:
		var h0: float = i * 2.0
		_deco.cyl(p + Vector3(0, h0, 0), p + Vector3(0, h0 + 2.0, 0), lerpf(2.3, 1.5, h0 / 16.0), lerpf(2.3, 1.5, (h0 + 2.0) / 16.0), red if i % 2 == 0 else cream, 18, i == 0)
	var dark := Color(0.15, 0.15, 0.16, STEEL)
	_deco.cyl(p + Vector3(0, 16.0, 0), p + Vector3(0, 16.25, 0), 2.45, 2.45, dark, 18)
	_deco.ring(p + Vector3(0, 17.0, 0), Vector3.RIGHT, Vector3.BACK, 2.4, 20, 0.03, dark)
	for i: int in 12:
		var a: float = TAU * i / 12.0
		_deco.rod(p + Vector3(cos(a) * 2.4, 16.25, sin(a) * 2.4), p + Vector3(cos(a) * 2.4, 17.0, sin(a) * 2.4), 0.025, dark)
	_deco.cyl(p + Vector3(0, 16.25, 0), p + Vector3(0, 17.9, 0), 1.15, 1.15, GLASS, 16)
	_deco.cyl(p + Vector3(0, 17.9, 0), p + Vector3(0, 19.2, 0), 1.4, 0.12, red, 16)
	var f: Vector3 = _facing(p)
	_deco.box(Transform3D(Basis.looking_at(-f), p + f * 2.25 + Vector3(0, 1.0, 0)), Vector3(1.0, 2.0, 0.12), dark)
	for y: float in [5.0, 9.0, 13.0]:
		_deco.box(Transform3D(Basis.looking_at(-f), p + f * lerpf(2.25, 1.55, y / 16.0) + Vector3(0, y, 0)), Vector3(0.5, 0.8, 0.1), GLASS)
	_col(p + Vector3(0, 2.0, 0), Vector3(4.2, 4.0, 4.2))
	_lm_top = p + Vector3(0, 17.1, 0)


func _windpump(p: Vector3) -> void:
	var galv := Color(0.62, 0.63, 0.6, STEEL)
	_truss(p, p + Vector3(0, 10.5, 0), 2.6, 0.5, 4, galv, 1.75, 0.06)
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_col(p + Vector3(c.x * 1.3, 1.0, c.y * 1.3), Vector3(0.4, 2.0, 0.4))
	var f: Vector3 = _facing(p)
	var rt: Vector3 = Vector3.UP.cross(f).normalized()
	_deco.box(Transform3D(Basis.looking_at(-f), p + Vector3(0, 10.8, 0)), Vector3(0.5, 0.45, 1.1), galv)
	var c0: Vector3 = p + Vector3(0, 11.0, 0) + f * 0.6
	var blade := Color(0.75, 0.74, 0.7, STEEL)
	for i: int in 18:
		var a: float = TAU * i / 18.0
		var d: Vector3 = rt * cos(a) + Vector3.UP * sin(a)
		if i == 4 or i == 11:
			continue  # a couple of blades lost to the wind
		_deco.rod(c0 + d * 0.45, c0 + d * 2.2, 0.09, blade)
	_deco.ring(c0, rt, Vector3.UP, 1.2, 18, 0.025, galv)
	_deco.ring(c0, rt, Vector3.UP, 2.15, 24, 0.03, galv)
	_deco.rod(c0 - f * 0.3, c0 - f * 3.0, 0.04, galv)
	_deco.box(Transform3D(Basis.looking_at(rt), c0 - f * 3.0), Vector3(0.04, 0.9, 1.4), Color(_lm_col.r, _lm_col.g, _lm_col.b, STEEL))
	var tp: Vector3 = p + rt * 3.4
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_deco.rod(tp + Vector3(c.x * 1.1, 0, c.y * 1.1), tp + Vector3(c.x * 1.1, 1.6, c.y * 1.1), 0.06, galv)
	_deco.cyl(tp + Vector3(0, 1.6, 0), tp + Vector3(0, 3.1, 0), 1.7, 1.7, Color(0.46, 0.28, 0.16, STEEL), 18)
	_col(tp + Vector3(0, 1.5, 0), Vector3(3.4, 3.0, 3.4))
	_lm_top = c0 + Vector3(0, 2.4, 0)


func _smokestack(p: Vector3) -> void:
	var brick := Color(0.55, 0.3, 0.22, PAINT)
	var dark := Color(0.12, 0.11, 0.1, STEEL)
	_deco.cyl(p, p + Vector3(0, 27.0, 0), 1.9, 1.25, brick, 16)
	for y: float in [9.0, 18.0, 25.8]:
		var r: float = lerpf(1.9, 1.25, y / 27.0) + 0.08
		_deco.cyl(p + Vector3(0, y, 0), p + Vector3(0, y + 0.4, 0), r, r, dark, 16, false)
	_deco.cyl(p + Vector3(0, 27.0, 0), p + Vector3(0, 27.4, 0), 1.35, 1.35, dark, 16)
	var f: Vector3 = _facing(p)
	var rt: Vector3 = Vector3.UP.cross(f).normalized() * signf(p.x)
	var hc: Vector3 = p + rt * 4.8 + Vector3(0, 2.3, 0)
	var hb := Basis.looking_at(-f)
	_deco.box(Transform3D(hb, hc), Vector3(6.5, 4.6, 5.0), Color(0.62, 0.58, 0.52, PAINT))
	_deco.box(Transform3D(hb, hc + Vector3(0, 2.4, 0)), Vector3(6.8, 0.25, 5.3), dark)
	_deco.box(Transform3D(hb, hc + Vector3(0, 0.8, 0) + f * 2.52), Vector3(5.6, 1.0, 0.05), GLASS)
	_col(p + Vector3(0, 2.0, 0), Vector3(3.8, 4.0, 3.8))
	_col(hc, Vector3(6.5, 4.6, 5.0), hb)
	_lm_top = p + Vector3(0, 27.6, 0)


func _old_bus(p: Vector3) -> void:
	var b := Basis(Vector3.UP, PI * 0.5 + _style.randf_range(-0.35, 0.35)) * Basis(Vector3.BACK, deg_to_rad(4.0))
	var xf := Transform3D(b, p)
	var body := Color(_lm_col.r, _lm_col.g, _lm_col.b, STEEL).lerp(Color(0.75, 0.7, 0.6, STEEL), 0.25)
	_deco.box(xf.translated_local(Vector3(0, 2.45, 0)), Vector3(2.5, 4.2, 10.5), body)
	for y: float in [2.0, 3.75]:
		_deco.box(xf.translated_local(Vector3(0, y, 0)), Vector3(2.56, 0.85, 9.9), GLASS)
	_deco.box(xf.translated_local(Vector3(0, 4.6, 0)), Vector3(2.4, 0.12, 10.3), body.lightened(0.2))
	_deco.box(xf.translated_local(Vector3(0, 1.2, 0)), Vector3(2.54, 0.25, 10.52), Color(0.85, 0.82, 0.74, STEEL))
	for k: int in 6:
		_deco.box(xf.translated_local(Vector3(_rng.randf_range(-1.0, 1.0) * 1.27, _rng.randf_range(0.6, 4.2), _rng.randf_range(-5.0, 5.0))), Vector3(0.08, _rng.randf_range(0.2, 0.6), _rng.randf_range(0.3, 1.0)), Color(0.45, 0.25, 0.13, STEEL))
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var wc: Vector3 = xf * Vector3(c.x * 1.1, 0.55, c.y * 3.6)
		_deco.cyl(wc - b.x * 0.18, wc + b.x * 0.18, 0.55, 0.55, Color(0.08, 0.08, 0.08, PLAST), 12)
	_deco.box(xf.translated_local(Vector3(0, 4.15, 5.27)), Vector3(1.8, 0.35, 0.05), Color(0.05, 0.05, 0.05, STEEL))
	_label(district.to_upper(), xf.translated_local(Vector3(0, 4.15, 5.31)), 64, 0.004, Color(1.0, 0.6, 0.15))
	for k: int in 5:
		var wp: Vector3 = xf * Vector3(_rng.randf_range(-0.9, 0.9), 4.66, _rng.randf_range(-4.5, 4.5))
		if not _weeds.has("grass_medium_01"):
			_weeds["grass_medium_01"] = []
		(_weeds["grass_medium_01"] as Array).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), wp))
	_col(xf * Vector3(0, 2.4, 0), Vector3(2.5, 4.4, 10.5), b)
	_lm_top = xf * Vector3(0, 4.8, 0)


func _caravan(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, deg_to_rad(-7.0))
	var xf := Transform3D(b, p)
	var cream := Color(0.9, 0.86, 0.76, STEEL)
	_deco.box(xf.translated_local(Vector3(0, 1.55, 0)), Vector3(2.2, 2.1, 5.0), cream)
	var stripe: Color = _tarp_cols[0]
	stripe.a = STEEL
	_deco.box(xf.translated_local(Vector3(0, 1.15, 0)), Vector3(2.24, 0.25, 5.04), stripe)
	_deco.box(xf.translated_local(Vector3(0, 2.66, 0)), Vector3(2.0, 0.14, 4.8), cream.darkened(0.08))
	for sx: float in [-1.0, 1.0]:
		for z: float in [-1.4, 1.2]:
			_deco.box(xf.translated_local(Vector3(sx * 1.11, 1.9, z)), Vector3(0.05, 0.6, 1.1), GLASS)
	_deco.box(xf.translated_local(Vector3(1.11, 1.4, 0.0)), Vector3(0.06, 1.8, 0.7), cream.darkened(0.2))
	for sx: float in [-1.15, 1.15]:
		var wc: Vector3 = xf * Vector3(sx, 0.25, 0.3)
		_deco.cyl(wc - b.x * 0.12, wc + b.x * 0.12, 0.42, 0.42, Color(0.08, 0.08, 0.08, PLAST), 12)
	for sx: float in [-0.6, 0.6]:
		_deco.rod(xf * Vector3(sx, 0.6, 2.5), xf * Vector3(0, 0.35, 3.6), 0.04, Color(0.3, 0.3, 0.3, STEEL))
	_mound(Transform3D(Basis(Vector3.UP, yaw), p + b.x * 1.6), Vector2(1.8, 5.2), 0.6, _drift_col)
	_col(p + Vector3(0, 1.4, 0), Vector3(2.2, 2.8, 5.0), Basis(Vector3.UP, yaw))


func _beach_shack(p: Vector3) -> void:
	var out := Vector3(-signf(p.x), 0, 0)
	var al: Vector3 = Vector3.UP.cross(out).normalized()
	var b := Basis(al, Vector3.UP, out)
	var xf := Transform3D(b, p)
	var plank := Color(0.42, 0.62, 0.62, PAINT)
	for k: int in 9:
		var y: float = 0.15 + k * 0.3
		_deco.box(xf.translated_local(Vector3(0, y, -1.3)), Vector3(3.2, 0.27, 0.06), plank.darkened(_rng.randf_range(0.0, 0.2)))
		for sx: float in [-1.6, 1.6]:
			_deco.box(xf.translated_local(Vector3(sx, y, -0.2)), Vector3(0.06, 0.27, 2.2), plank.darkened(_rng.randf_range(0.0, 0.2)))
	_deco.box(xf.translated_local(Vector3(0, 0.55, 0.7)), Vector3(3.2, 1.1, 0.1), Color(0.9, 0.86, 0.75, PAINT))
	var roof := Transform3D(b * Basis(Vector3.RIGHT, -0.18), p + b * Vector3(0, 3.05, -0.2))
	_deco.box(roof, Vector3(3.6, 0.05, 2.9), Color(0.55, 0.55, 0.56, STEEL))
	_awning(p + out * 0.75, al, out, 3.0, _awning_cols[0])
	_label("BAIT & BOLTS", xf.translated_local(Vector3(0, 0.62, 0.76)), 72, 0.0045, Color(0.12, 0.3, 0.42))
	_prop("lifebuoy", Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), p + b * Vector3(1.66, 1.6, 0.4)).scaled_local(Vector3.ONE * 0.9))
	_col(p + Vector3(0, 1.4, 0), Vector3(3.3, 2.8, 2.6), b)


# --- Ruined base (level 1) -------------------------------------------------------------------

func _build_ruin() -> void:
	_build_fence(true)
	_build_name_sign(true)
	# The light poles: most have toppled into the yard; one still stands, trailing dead wires.
	var tops: Array[Vector3] = _pole_tops()
	var stand: int = _rng.randi() % 2
	var stand_top: Vector3 = tops[stand]
	for i: int in 4:
		var bp := Vector3(tops[i].x, 0, tops[i].z)
		if i == stand:
			_pole(bp, 5.6)
			continue
		var dir: Vector3 = (-bp).normalized().rotated(Vector3.UP, _rng.randf_range(-0.7, 0.7))
		_fallen_pole(bp, dir, 5.6)
		if i < 2:  # only along the back: a wire to a front pole would hang across the view
			var tip: Vector3 = bp + dir * 5.2 + Vector3(0, 0.15, 0)
			_dead_wire(stand_top, tip, 0.4)
	_dead_wire(stand_top, Vector3(stand_top.x * 0.4, 0.02, stand_top.z * 0.5), 0.2)
	# Junk drifted onto the slab: rubble, planks, toppled drums, crates on their sides, broken pallets.
	var h: float = CityLayout.YARD_HALF - 0.6
	var placed: int = 0
	for k: int in 80:
		if placed >= 34:
			break
		var p: Vector3
		if _rng.randf() < 0.7:
			var t: float = _rng.randf_range(-h, h)
			var inset: float = _rng.randf_range(0.0, 1.6)
			p = [Vector3(t, 0, -h + inset), Vector3(-h + inset, 0, t), Vector3(h - inset, 0, t), Vector3(t, 0, h - inset)][_rng.randi() % 4]
		else:
			p = Vector3(_rng.randf_range(-h, h), 0, _rng.randf_range(-h, h))
		if (absf(p.x) < 2.4 and p.z > -1.0) or p.distance_to(Vector3(0, 0, -2.2)) < 3.2 or p.distance_to(Vector3(-4.9, 0, 2.2)) < 2.6 or p.distance_to(Vector3(7.0, 0, -0.8)) < 1.6:
			continue
		placed += 1
		var yaw: float = _rng.randf() * TAU
		match _rng.randi() % 6:
			0, 1:
				var sz := Vector3(_rng.randf_range(0.25, 0.7), _rng.randf_range(0.12, 0.3), _rng.randf_range(0.25, 0.6))
				_deco.box(Transform3D(Basis(Vector3.UP, yaw).rotated(Vector3(1, 0, 1).normalized(), _rng.randf_range(-0.3, 0.3)), p + Vector3(0, sz.y * 0.4, 0)), sz, Color(0.55, 0.53, 0.5, PAINT).darkened(_rng.randf_range(0.0, 0.3)))
			2:
				_deco.box(Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0.03, 0)), Vector3(0.16, 0.04, _rng.randf_range(0.9, 1.8)), Color(0.5, 0.4, 0.28, PAINT).darkened(_rng.randf_range(0.0, 0.3)))
			3:
				_drums.append([Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, yaw), p + Vector3(0, 0.29, 0)), Color(0.45, 0.26, 0.15).lerp(Color(0.2, 0.25, 0.35), _rng.randf())])
			4:
				_crate(Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, yaw), p + Vector3(0, 0.2, 0)), _plastic[_rng.randi() % _plastic.size()].darkened(0.3))
			5:
				_pallet(Transform3D(Basis(Vector3.UP, yaw).rotated(Vector3(1, 0, 0), _rng.randf_range(0.05, 0.25)), p + Vector3(0, 0.08, 0)))
	_build_drifts(1.6)
	# Overgrown: weeds all over the edges and up through the slab.
	var ids: Array[String] = ["grass_medium_01", "weed_plant_02", "nettle_plant", "grass_medium_02"]
	for k: int in 60:
		var p2 := Vector3(_rng.randf_range(-h, h), 0, _rng.randf_range(-h, h))
		if absf(p2.x) < 1.8 and p2.z > 0.0:
			continue
		var id: String = ids[_rng.randi() % ids.size()]
		if not _weeds.has(id):
			_weeds[id] = []
		(_weeds[id] as Array).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.5, 1.0)), p2))


func _fallen_pole(base: Vector3, dir: Vector3, h: float) -> void:
	var wood := Color(0.36, 0.27, 0.2, PAINT)
	var side: Vector3 = Vector3.UP.cross(dir).normalized()
	var b := Basis(side, dir, side.cross(dir).normalized())
	_deco.box(Transform3D(b, base + dir * h * 0.5 + Vector3(0, 0.09, 0)), Vector3(0.16, h, 0.16), wood)
	_deco.box(Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).rotated(dir, 0.4), base + dir * (h - 0.25) + Vector3(0, 0.2, 0)), Vector3(0.08, 0.7, 0.08), wood.darkened(0.2))
	_deco.box(Transform3D(Basis(Vector3.UP, _rng.randf()), base + Vector3(0, 0.2, 0)), Vector3(0.2, 0.4, 0.2), wood.darkened(0.3))


## A dead festoon run: sagging wire, cold bulbs, one end on the ground.
func _dead_wire(a: Vector3, b: Vector3, sag: float) -> void:
	var len: float = a.distance_to(b)
	var segs: int = maxi(6, int(len / 1.0))
	var wire := Color(0.08, 0.08, 0.08, STEEL)
	for i: int in segs:
		_deco.rod(_catenary(a, b, sag, float(i) / segs), _catenary(a, b, sag, float(i + 1) / segs), 0.008, wire)
	var n: int = int(len / 0.6)
	for i: int in range(1, n):
		if _rng.randf() < 0.3:
			continue
		var pp: Vector3 = _catenary(a, b, sag, float(i) / n) - Vector3.UP * 0.07
		_bulbs.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), pp), Color(0.06, 0.06, 0.055)])


# --- Fence and name sign (ruined / patched) ----------------------------------------------------

func _fence_style() -> String:
	if not layout.wild:
		return "chain"
	return "scrap" if biome in ["rustlands", "sprawl", "old_capital"] else "wire"


## Back and side fences of the yard (the front stays open). Ruined: posts missing or leaning,
## rails down, panels fallen flat. Patched: every post up, rails whole, a few fresh patch sheets.
func _build_fence(ruined: bool) -> void:
	var hh: float = CityLayout.YARD_HALF + 0.15
	var style: String = _fence_style()
	var edges: Array = [[Vector2(-hh, -hh), Vector2(hh, -hh)], [Vector2(-hh, -hh), Vector2(-hh, hh)], [Vector2(hh, -hh), Vector2(hh, hh)]]
	var steel := Color(0.42, 0.43, 0.45, STEEL)
	var wood := Color(0.42, 0.32, 0.22, PAINT)
	var rope: Color = Color(0.7, 0.62, 0.45, PAINT) if biome in ["neon_coast", "lake"] else Color(0.25, 0.24, 0.22, STEEL)
	var post_h: float = 1.8 if style != "wire" else 1.3
	for e: Array in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector3 = -_xz((a + b) * 0.5, 0.0).normalized()
		var n: int = int(a.distance_to(b) / 2.5)
		var tops: Array = []  # top point of each post, or null if it is down
		for k: int in n + 1:
			var p2: Vector2 = a.lerp(b, float(k) / n)
			var bp: Vector3 = _xz(p2, 0.0)
			var state: int = 0
			if ruined:
				var r: float = _rng.randf()
				state = 0 if r < 0.45 else (1 if r < 0.75 else 2)
			if state == 2:
				_deco.box(Transform3D(Basis(Vector3.UP, _rng.randf()), bp + Vector3(0, 0.12, 0)), Vector3(0.1, 0.24, 0.1), wood if style == "wire" else steel)
				tops.append(null)
				continue
			var lean := Vector3.ZERO
			if state == 1:
				lean = (inward * (1.0 if _rng.randf() < 0.6 else -1.0) + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))).normalized() * post_h * _rng.randf_range(0.3, 0.7)
			var top: Vector3 = bp + Vector3(0, post_h, 0) + lean
			var fresh: bool = not ruined and not start_base and _rng.randf() < 0.3
			var pc: Color = (wood if style == "wire" else steel)
			if fresh:
				pc = pc.lightened(0.3)
			_deco.rod(bp, top, 0.06 if style == "wire" else 0.035, pc)
			if biome == "frostcap":
				_deco.box(Transform3D(Basis(), top + Vector3(0, 0.03, 0)), Vector3(0.16, 0.06, 0.16), SNOW)
			tops.append(top if state == 0 else null)
		for k: int in n:
			var t0: Variant = tops[k]
			var t1: Variant = tops[k + 1]
			var pa: Vector3 = _xz(a.lerp(b, float(k) / n), 0.0)
			var pb: Vector3 = _xz(a.lerp(b, float(k + 1) / n), 0.0)
			match style:
				"chain":
					if t0 != null and t1 != null and (not ruined or _rng.randf() < 0.6):
						_deco.rod(t0, t1, 0.022, steel)
						if not ruined:
							_deco.rod(pa + Vector3(0, 0.9, 0), pb + Vector3(0, 0.9, 0), 0.016, steel)
							# Chain-link mesh, suggested by a diagonal lattice of thin wires.
							for q: int in 8:
								var tq: float = q / 8.0
								var x0: Vector3 = pa.lerp(pb, tq)
								var x1: Vector3 = pa.lerp(pb, minf(tq + 0.25, 1.0))
								_deco.rod(x0 + Vector3(0, 0.08, 0), x1 + Vector3(0, 1.7, 0), 0.006, steel.darkened(0.2))
								_deco.rod(x1 + Vector3(0, 0.08, 0), x0 + Vector3(0, 1.7, 0), 0.006, steel.darkened(0.2))
							if not start_base and _rng.randf() < 0.22:
								var pc2: Color = _paint_main.lerp(Color(0.6, 0.6, 0.6), 0.3)
								pc2.a = STEEL
								_deco.box(Transform3D(Basis.looking_at(inward).rotated(inward, _rng.randf_range(-0.08, 0.08)), (pa + pb) * 0.5 + Vector3(0, 0.75, 0) + inward * 0.06), Vector3(2.3, 1.15, 0.03), pc2)
					elif ruined and _rng.randf() < 0.5:
						var m: Vector3 = (pa + pb) * 0.5 + inward * _rng.randf_range(0.3, 1.2)
						_deco.rod(m - (pb - pa) * 0.4 + Vector3(0, 0.03, 0), m + (pb - pa) * 0.35 + Vector3(0, 0.03, 0), 0.022, steel)
				"wire":
					for y: float in [0.6, 1.1]:
						if t0 != null and t1 != null:
							_deco.rod(pa + Vector3(0, y, 0), pb + Vector3(0, y, 0), 0.012 if rope.a < 0.1 else 0.008, rope)
						elif ruined and _rng.randf() < 0.6:
							_deco.rod(pa + Vector3(0, y * 0.5, 0), (pa + pb) * 0.5 + inward * 0.3 + Vector3(0, 0.02, 0), 0.008, rope)
				"scrap":
					var cols: Array[Color] = [Color(0.45, 0.26, 0.15), Color(0.3, 0.4, 0.5), Color(0.32, 0.42, 0.3), Color(0.5, 0.48, 0.45)]
					var pc3: Color = cols[_rng.randi() % cols.size()].darkened(_rng.randf_range(0.0, 0.2))
					pc3.a = STEEL
					var r2: float = _rng.randf() if ruined else 1.0
					var mid: Vector3 = (pa + pb) * 0.5
					var bb := Basis.looking_at(inward)
					if r2 < 0.3:
						continue
					elif r2 < 0.55:
						_deco.box(Transform3D(bb.rotated(bb.x, -PI * 0.5 + 0.05), mid + inward * 0.9 + Vector3(0, 0.05, 0)), Vector3(2.4, 1.7, 0.03), pc3)
					else:
						_deco.box(Transform3D(bb.rotated(inward, _rng.randf_range(-0.06, 0.06)).rotated(bb.x, _rng.randf_range(-0.2, 0.1) if ruined else 0.0), mid + Vector3(0, 0.85, 0)), Vector3(2.45, 1.7, 0.03), pc3)
						for q: int in 5:
							var rx: Vector3 = pa.lerp(pb, 0.1 + q * 0.2) + Vector3(0, 0.05, 0) - inward * 0.02
							_deco.rod(rx, rx + Vector3(0, 1.6, 0), 0.012, pc3.darkened(0.2))
	if ruined:
		return
	if biome in ["neon_coast", "lake"]:
		_nets(-hh)


## Fishing nets hung over the back fence, with floats.
func _nets(z: float) -> void:
	var col := Color(0.18, 0.28, 0.22, PAINT)
	for spec: Array in [[-6.5, 3.5], [1.5, 3.0]]:
		var x0: float = spec[0]
		var w: float = spec[1]
		for i: int in int(w / 0.25) + 1:
			var x: float = x0 + i * 0.25
			var drop: float = 1.2 + 0.3 * sin(i * 0.9)
			_deco.rod(Vector3(x, 1.75, z + 0.08), Vector3(x + 0.05, 1.75 - drop, z + 0.14), 0.006, col)
		for j: int in 5:
			var y: float = 1.75 - j * 0.25
			_deco.rod(Vector3(x0, y, z + 0.1), Vector3(x0 + w, y - 0.05, z + 0.1), 0.006, col)
		for i: int in int(w / 0.6):
			_deco.box(Transform3D(Basis(), Vector3(x0 + 0.3 + i * 0.6, 1.72, z + 0.12)), Vector3(0.12, 0.1, 0.1), Color(0.95, 0.45, 0.12, PLAST))


## The district's name board over the back fence. Broken: one post snapped, the board hanging
## off the other, letters peeled away.
func _build_name_sign(broken: bool) -> void:
	var z: float = -(CityLayout.YARD_HALF + 0.45)
	var x: float = _sign_x
	var wild: bool = layout.wild
	var post: Color = Color(0.4, 0.3, 0.21, PAINT) if wild else Color(0.3, 0.31, 0.33, STEEL)
	for sx: float in [-2.45, 2.45]:
		var hgt: float = 3.6 if not (broken and sx > 0.0) else 1.3
		_deco.box(Transform3D(Basis(), Vector3(x + sx, hgt * 0.5, z)), Vector3(0.16, hgt, 0.16), post)
		if broken and sx > 0.0:
			_deco.box(Transform3D(Basis(Vector3.BACK, 1.45).rotated(Vector3.UP, 0.4), Vector3(x + sx + 0.9, 0.1, z + 0.6)), Vector3(0.16, 2.2, 0.16), post)
	var board_xf := Transform3D(Basis(), Vector3(x, 2.85, z + 0.1))
	if broken:
		var pivot := Vector3(x - 2.4, 3.45, z + 0.1)
		board_xf = Transform3D(Basis(Vector3.BACK, -0.62).rotated(Vector3.UP, 0.12), pivot) * Transform3D(Basis(), Vector3(2.4, -0.62, 0))
	var bg: Color = _sign_bg.lerp(Color(0.62, 0.6, 0.55), 0.45 if broken else 0.12)
	bg.a = PAINT
	_deco.box(board_xf, Vector3(4.8, 1.3, 0.08), bg)
	var trim: Color = post.lightened(0.1)
	_deco.box(board_xf.translated_local(Vector3(0, 0.67, 0.02)), Vector3(4.9, 0.07, 0.1), trim)
	_deco.box(board_xf.translated_local(Vector3(0, -0.67, 0.02)), Vector3(4.9, 0.07, 0.1), trim)
	var txt: String = district.to_upper()
	if broken:
		var chars: PackedStringArray = txt.split("")
		for i: int in chars.size():
			if chars[i] != " " and _rng.randf() < 0.35:
				chars[i] = " "
		txt = "".join(chars)
	var ink: Color = Color(0.96, 0.92, 0.78) if _sign_bg.get_luminance() < 0.5 else Color(0.35, 0.12, 0.08)
	ink.a = 0.6 if broken else 0.92
	_label(txt, board_xf.translated_local(Vector3(0, 0.14, 0.05)), 96, minf(0.0058, 4.3 / (txt.length() * 96 * 0.62)), ink)
	if not broken:
		var slogan: String = "BRIGHTER DAYS AHEAD" if start_base else SIGN_SLOGANS[(hub_index * 5 + 3) % SIGN_SLOGANS.size()]
		_label(slogan, board_xf.translated_local(Vector3(0, -0.4, 0.05)), 64, minf(0.0032, 4.3 / (slogan.length() * 64 * 0.62)), ink.darkened(0.1))


## Clamp lamps on the two back light poles while the base is patched up (level 2).
func _build_pole_lamps() -> void:
	var tops: Array[Vector3] = _pole_tops()
	for i: int in 2:
		var t: Vector3 = tops[i] - Vector3(0, 0.6, 0)
		var aim: Vector3 = (Vector3(0, -2.0, 0) - t).normalized()
		var head := Transform3D(Basis.looking_at(-aim), t - Vector3(t.x, 0, t.z).normalized() * 0.25)
		_deco.box(head, Vector3(0.36, 0.26, 0.2), Color(0.12, 0.12, 0.13, STEEL))
		_tubes.box(head.translated_local(Vector3(0, 0, 0.105)), Vector3(0.3, 0.2, 0.01), Color(1.0, 0.9, 0.75), Vector2(7.3 + i, 0.0))
		if i == 0:
			var sl := SpotLight3D.new()
			sl.light_color = Color(1.0, 0.88, 0.72)
			sl.light_energy = 2.2
			sl.spot_range = 16.0
			sl.spot_angle = 45.0
			sl.shadow_enabled = false
			sl.transform = Transform3D(Basis.looking_at(aim), head.origin)
			_cur.add_child(sl)


# --- Camp dressing (wilderness) ----------------------------------------------------------------

func _build_camp() -> void:
	match biome:
		"neon_coast", "lake", "fungal_marsh":
			# Plank deck in the front-left corner (pier planks / marsh boardwalk).
			var wood: Color = Color(0.55, 0.45, 0.33, PAINT) if biome != "fungal_marsh" else Color(0.33, 0.27, 0.2, PAINT)
			for i: int in 12:
				var x: float = -8.2 + i * 0.29
				_deco.box(Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.015, 0.015)), Vector3(x, 0.035, 6.2)), Vector3(0.26, 0.05, 3.7 - (i % 3) * 0.15), wood.darkened(_rng.randf_range(0.0, 0.25)))
			for c: Vector2 in [Vector2(-8.35, 4.35), Vector2(-4.75, 4.35)]:
				_deco.box(Transform3D(Basis(), Vector3(c.x, 0.45, c.y)), Vector3(0.18, 0.9, 0.18), wood.darkened(0.3))
			_deco.rod(Vector3(-8.35, 0.82, 4.35), Vector3(-4.75, 0.78, 4.35), 0.02, Color(0.7, 0.62, 0.45, PAINT))
		"rustlands":
			for k: int in 3:
				_prop("old_tyre", Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, 0.1 * k), Vector3(-7.6, 0.45, -3.6 + k * 0.32)))


func _heater_barrel(p: Vector3) -> void:
	_drums.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p), Color(0.4, 0.22, 0.12)])
	var top: Vector3 = p + Vector3(0, 0.88, 0)
	_tubes.cyl(top, top + Vector3(0, 0.03, 0), 0.26, 0.26, Color(1.0, 0.45, 0.1), 10, true, Vector2(3.3, 1.0))
	for k: int in 4:
		var a: float = TAU * k / 4.0 + 0.4
		var b0: Vector3 = top + Vector3(cos(a), 0, sin(a)) * 0.12
		_tubes.rod(b0, b0 + Vector3(0, _rng.randf_range(0.2, 0.4), 0), 0.04, Color(1.0, 0.6 + k * 0.08, 0.15), Vector2(3.3 + k, 1.0))
	var lt := OmniLight3D.new()
	lt.light_color = Color(1.0, 0.55, 0.2)
	lt.light_energy = 1.4
	lt.omni_range = 4.5
	lt.position = top + Vector3(0, 0.5, 0)
	_cur.add_child(lt)


## Sun-bleached tarp stretched between four poles over a corner.
func _tarp_shade(c: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var wood := Color(0.5, 0.42, 0.32, PAINT)
	var corners: Array[Vector3] = []
	for q: Vector2 in [Vector2(-1.1, -1.1), Vector2(1.1, -1.1), Vector2(1.1, 1.1), Vector2(-1.1, 1.1)]:
		var hgt: float = 2.3 if q.y < 0 else 1.9
		var bp: Vector3 = c + b * Vector3(q.x, 0, q.y)
		_deco.rod(bp, bp + Vector3(0, hgt, 0), 0.035, wood)
		corners.append(bp + Vector3(0, hgt, 0))
	var col: Color = _tarp_cols[0]
	var n: int = 5
	for j: int in n:
		for i: int in n:
			var pt: Callable = func(u: float, v: float) -> Vector3:
				var top: Vector3 = corners[0].lerp(corners[1], u)
				var bot: Vector3 = corners[3].lerp(corners[2], u)
				return top.lerp(bot, v) - Vector3(0, 0.18 * sin(u * PI) * sin(v * PI), 0)
			var sh: float = _rng.randf_range(0.9, 1.0)
			_deco.quad(pt.call(float(i) / n, float(j) / n), pt.call(float(i + 1) / n, float(j) / n), pt.call(float(i + 1) / n, float(j + 1) / n), pt.call(float(i) / n, float(j + 1) / n), Color(col.r * sh, col.g * sh, col.b * sh, FABRIC))


## Marsh lanterns on short posts around the yard (lit with the festoons).
func _lanterns() -> void:
	var h: float = CityLayout.YARD_HALF - 0.4
	for p: Vector3 in [Vector3(-h, 0, -3.0), Vector3(-h, 0, 3.5), Vector3(h, 0, 3.0), Vector3(-2.5, 0, -h), Vector3(2.5, 0, -h)]:
		_lantern_post(p)


func _lantern_post(p: Vector3) -> void:
	var wood := Color(0.33, 0.26, 0.19, PAINT)
	_deco.box(Transform3D(Basis(), p + Vector3(0, 0.8, 0)), Vector3(0.1, 1.6, 0.1), wood)
	var arm: Vector3 = p + Vector3(0, 1.55, 0) - Vector3(p.x, 0, p.z).normalized() * 0.4
	_deco.rod(p + Vector3(0, 1.55, 0), arm, 0.02, wood)
	_deco.box(Transform3D(Basis(), arm - Vector3(0, 0.08, 0)), Vector3(0.18, 0.02, 0.18), Color(0.15, 0.15, 0.15, STEEL))
	_bulbs.append([Transform3D(Basis().scaled(Vector3(2.6, 2.2, 2.6)), arm - Vector3(0, 0.3, 0)), Color(0.75, 1.0, 0.45) if _rng.randf() < 0.5 else WARM])


# --- Restored base: the futuristic kit (levels 3-5) -----------------------------------------

## White panel fence with dark glass and cyan light strips (replaces the patched fence).
func _build_future_fence() -> void:
	var hh: float = CityLayout.YARD_HALF + 0.15
	var edges: Array = [[Vector2(-hh, -hh), Vector2(hh, -hh)], [Vector2(-hh, -hh), Vector2(-hh, hh)], [Vector2(hh, -hh), Vector2(hh, hh)]]
	for e: Array in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector3 = -_xz((a + b) * 0.5, 0.0).normalized()
		var bb := Basis.looking_at(-inward)
		var n: int = int(a.distance_to(b) / 2.5)
		for k: int in n + 1:
			var bp: Vector3 = _xz(a.lerp(b, float(k) / n), 0.0)
			_deco.box(Transform3D(bb, bp + Vector3(0, 0.95, 0)), Vector3(0.16, 1.9, 0.16), GLOSS)
			_deco.box(Transform3D(bb, bp + Vector3(0, 1.93, 0)), Vector3(0.2, 0.08, 0.2), Color(_accent.r, _accent.g, _accent.b, PLAST))
			if k < n:
				var pb: Vector3 = _xz(a.lerp(b, float(k + 1) / n), 0.0)
				var mid: Vector3 = (bp + pb) * 0.5
				var w: float = bp.distance_to(pb) - 0.16
				_deco.box(Transform3D(bb, mid + Vector3(0, 0.55, 0)), Vector3(w, 0.9, 0.06), GLOSS)
				_deco.box(Transform3D(bb, mid + Vector3(0, 1.38, 0)), Vector3(w, 0.62, 0.04), GLASS)
		var a3: Vector3 = _xz(a, 0.0) + inward * 0.05
		var b3: Vector3 = _xz(b, 0.0) + inward * 0.05
		_tubes.rod(a3 + Vector3(0, 1.72, 0), b3 + Vector3(0, 1.72, 0), 0.025, CYAN, Vector2(11.0, 0.0))
		_tubes.rod(a3 + Vector3(0, 0.08, 0), b3 + Vector3(0, 0.08, 0), 0.02, CYAN, Vector2(11.3, 0.0))
	# The light poles get white sleeves with a cyan strip and an orange cap light.
	for t: Vector3 in _pole_tops():
		var bp2 := Vector3(t.x, 0, t.z)
		var inw: Vector3 = -bp2.normalized()
		_deco.box(Transform3D(Basis(), bp2 + Vector3(0, 2.6, 0)), Vector3(0.26, 5.2, 0.26), GLOSS)
		_tubes.box(Transform3D(Basis.looking_at(-inw), bp2 + inw * 0.135 + Vector3(0, 2.6, 0)), Vector3(0.05, 4.8, 0.01), CYAN, Vector2(12.0, 0.0))
		_tubes.box(Transform3D(Basis(), t + Vector3(0, 0.3, 0)), Vector3(0.18, 0.1, 0.18), _accent, Vector2(12.5, 0.0))


## Holographic name sign: a white projector pylon pair throwing the district name in cyan.
func _build_holo_sign() -> void:
	var z: float = -(CityLayout.YARD_HALF + 0.45)
	var x: float = _sign_x
	for sx: float in [-2.5, 2.5]:
		var bp := Vector3(x + sx, 0, z)
		_deco.box(Transform3D(Basis(), bp + Vector3(0, 1.4, 0)), Vector3(0.3, 2.8, 0.3), GLOSS)
		_deco.box(Transform3D(Basis(), bp + Vector3(0, 2.86, 0)), Vector3(0.4, 0.12, 0.4), GLASS)
		_tubes.box(Transform3D(Basis(), bp + Vector3(0, 1.4, 0.155)), Vector3(0.05, 2.5, 0.01), CYAN, Vector2(13.0, 0.0))
		_tubes.box(Transform3D(Basis(), bp + Vector3(0, 2.94, 0)), Vector3(0.3, 0.03, 0.3), _accent, Vector2(13.4, 0.0))
	var holo := Node3D.new()
	holo.name = "HoloSign"
	holo.position = Vector3(x, 3.7, z + 0.1)
	holo.set_meta("base", holo.position)
	holo.set_meta("nospin", true)
	_cur.add_child(holo)
	_hover.append(holo)
	var g := Geo.new()
	var w: float = 5.0
	var hh: float = 1.35
	for c: Array in [[Vector3(-w, -hh, 0), Vector3(w, -hh, 0)], [Vector3(-w, hh, 0), Vector3(w, hh, 0)], [Vector3(-w, -hh, 0), Vector3(-w, hh, 0)], [Vector3(w, -hh, 0), Vector3(w, hh, 0)]]:
		g.rod((c[0] as Vector3) * 0.5, (c[1] as Vector3) * 0.5, 0.025, CYAN, Vector2(14.0, 0.0))
	for k: int in 6:
		g.rod(Vector3(-w * 0.5 + 0.1, -hh * 0.5 + 0.1 + k * 0.22, -0.02), Vector3(w * 0.5 - 0.1, -hh * 0.5 + 0.1 + k * 0.22, -0.02), 0.004, Color(0.2, 0.6, 0.7), Vector2(14.5, 0.0))
	var frame := MeshInstance3D.new()
	frame.mesh = g.mesh()
	var nm := ShaderMaterial.new()
	nm.shader = preload("res://art/shaders/neon.gdshader")
	nm.set_shader_parameter("energy", 4.0)
	frame.material_override = nm
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holo.add_child(frame)
	var panel := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, hh)
	panel.mesh = qm
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(0.02, 0.1, 0.16, 0.55)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	panel.material_override = pm
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holo.add_child(panel)
	var txt: String = district.to_upper()
	var prev: Node3D = _cur
	_cur = holo
	var l := _label(txt, Transform3D(Basis(), Vector3(0, 0.15, 0.02)), 110, minf(0.0062, 4.5 / (txt.length() * 110 * 0.62)), Color(0.55, 1.6, 2.0, 0.95), true)
	l.outline_size = 10
	l.outline_modulate = Color(0.1, 0.5, 0.8, 0.5)
	var slogan: String = "BRIGHTER DAYS AHEAD" if start_base else SIGN_SLOGANS[(hub_index * 5 + 3) % SIGN_SLOGANS.size()]
	_label(slogan, Transform3D(Basis(), Vector3(0, -0.42, 0.02)), 64, minf(0.0034, 4.5 / (slogan.length() * 64 * 0.62)), Color(2.0, 1.0, 0.35, 0.9), true)
	_cur = prev


## Glowing guide studs along the walkway and a landing ring by the rocket pad.
func _build_guide_lights() -> void:
	var z: float = 0.8
	var i: int = 0
	while z < 7.9:
		for x: float in [-1.1, 1.1]:  # small, sparse studs (rows of big ones read as thick lines)
			_tubes.box(Transform3D(Basis(), Vector3(x, 0.015, z)), Vector3(0.05, 0.012, 0.05), CYAN, Vector2(15.0 + i * 0.37, 0.0))
		z += 1.8
		i += 1
	var pad := Vector3(-7.0, 0.03, 6.5)
	_tubes.ring(pad, Vector3.RIGHT, Vector3.BACK, 1.9, 32, 0.025, CYAN, Vector2(16.0, 0.0))
	for k: int in 8:
		var a: float = TAU * k / 8.0
		_tubes.box(Transform3D(Basis(Vector3.UP, a), pad + Vector3(cos(a), 0, sin(a)) * 2.15), Vector3(0.16, 0.04, 0.16), _accent, Vector2(16.5 + k * 0.4, 0.0))
	# A cyan line to the depot scale.
	_tubes.ring(Vector3(0, 0.03, -1.8), Vector3.RIGHT, Vector3.BACK, 2.25, 36, 0.02, CYAN, Vector2(17.0, 0.0))


## White planter pods with flowers, and flags on the pole tops (level 4+).
func _build_planters() -> void:
	var spots: Array[Vector3] = [Vector3(-5.2, 0, 7.8), Vector3(5.2, 0, 7.8), Vector3(_sign_x - 3.1, 0, -7.75), Vector3(_sign_x + 3.1, 0, -7.75), Vector3(7.8, 0, 1.8)]
	var flowers: Array[String] = ["flower_gazania", "flower_heliophila", "celandine_01", "dandelion_01"]
	for sp: Vector3 in spots:
		_deco.cyl(sp, sp + Vector3(0, 0.55, 0), 0.38, 0.46, GLOSS, 16)
		_deco.cyl(sp + Vector3(0, 0.5, 0), sp + Vector3(0, 0.52, 0), 0.42, 0.42, Color(0.16, 0.12, 0.09, PAINT), 16)
		_tubes.cyl(sp + Vector3(0, 0.12, 0), sp + Vector3(0, 0.16, 0), 0.4, 0.4, CYAN, 16, false, Vector2(18.0, 0.0))
		for k: int in 6:
			var a: float = TAU * k / 6.0 + _rng.randf()
			var fp: Vector3 = sp + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(0.0, 0.28) + Vector3(0, 0.52, 0)
			var id: String = flowers[_rng.randi() % flowers.size()]
			if not _weeds.has(id):
				_weeds[id] = []
			(_weeds[id] as Array).append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.9, 1.4)), fp))
	var wind: Vector3 = Vector3(1.0, 0, 0.35).normalized()
	var fb := Basis(Vector3.UP, -wind, Vector3.UP.cross(-wind))
	var tops: Array[Vector3] = _pole_tops()
	for i: int in tops.size():
		var t: Vector3 = tops[i] + Vector3(0, 0.35, 0)
		_deco.rod(t, t + Vector3(0, 1.6, 0), 0.025, GLOSS)
		var fc: Color = _pennant[i % _pennant.size()] if i % 2 == 0 else _accent
		_flags.append([Transform3D(fb, t + Vector3(0, 1.55, 0) + wind * 0.02), fc])


## Little hover drones circling the yard (level 4+): white shells, dark glass eye, cyan ring.
func _build_drones() -> void:
	for i: int in 3:
		var d := Node3D.new()
		d.name = "Drone%d" % i
		var base := Vector3(0, 4.3 + i * 0.5, -0.5)
		d.position = base
		d.set_meta("base", base)
		d.set_meta("orbit", 5.5 + i * 0.8)
		_cur.add_child(d)
		_hover.append(d)
		var g := Geo.new()
		g.cyl(Vector3(0, -0.12, 0), Vector3(0, 0.12, 0), 0.28, 0.22, GLOSS, 14)
		g.cyl(Vector3(0, 0.12, 0), Vector3(0, 0.2, 0), 0.22, 0.05, GLOSS, 14)
		g.box(Transform3D(Basis(), Vector3(0, 0.0, 0.25)), Vector3(0.22, 0.1, 0.06), GLASS)
		for s2: float in [-1.0, 1.0]:
			g.box(Transform3D(Basis(), Vector3(s2 * 0.4, 0.05, 0)), Vector3(0.28, 0.03, 0.06), Color(_accent.r, _accent.g, _accent.b, PLAST))
		var mi := MeshInstance3D.new()
		mi.mesh = g.mesh()
		mi.material_override = _deco_mat()
		d.add_child(mi)
		var t := Geo.new()
		t.ring(Vector3(0, -0.14, 0), Vector3.RIGHT, Vector3.BACK, 0.3, 16, 0.018, CYAN, Vector2(19.0 + i, 0.0))
		t.box(Transform3D(Basis(), Vector3(0, 0.0, 0.285)), Vector3(0.12, 0.03, 0.01), CYAN, Vector2(19.5 + i, 0.0))
		var ti := MeshInstance3D.new()
		ti.mesh = t.mesh()
		ti.material_override = _glow_mat(4.0)
		ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.add_child(ti)


## Level 5: a floating ring of light over the yard and a beacon on the landmark.
func _build_beacon() -> void:
	var ring := Node3D.new()
	ring.name = "LightRing"
	var base := Vector3(0, 7.6, -1.0)
	ring.position = base
	ring.set_meta("base", base)
	_cur.add_child(ring)
	_hover.append(ring)
	var t := Geo.new()
	t.ring(Vector3.ZERO, Vector3.RIGHT, Vector3.BACK, 3.4, 64, 0.05, CYAN, Vector2(20.0, 0.0))
	t.ring(Vector3(0, -0.15, 0), Vector3.RIGHT, Vector3.BACK, 2.9, 48, 0.03, _accent, Vector2(20.5, 0.0))
	var ti := MeshInstance3D.new()
	ti.mesh = t.mesh()
	ti.material_override = _glow_mat(5.0)
	ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.add_child(ti)
	var g := Geo.new()
	for k: int in 6:
		var a: float = TAU * k / 6.0
		g.box(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a), 0, sin(a)) * 3.15), Vector3(0.22, 0.16, 0.7), GLOSS)
	var mi := MeshInstance3D.new()
	mi.mesh = g.mesh()
	mi.material_override = _deco_mat()
	ring.add_child(mi)
	var lt := OmniLight3D.new()
	lt.light_color = Color(0.4, 0.9, 1.0)
	lt.light_energy = 1.6
	lt.omni_range = 12.0
	lt.shadow_enabled = false
	ring.add_child(lt)
	if _lm_top != Vector3.ZERO:
		_tubes.cyl(_lm_top, _lm_top + Vector3(0, 0.5, 0), 0.28, 0.28, _accent, 12, true, Vector2(21.0, 0.0))
		_tubes.ring(_lm_top + Vector3(0, 0.25, 0), Vector3.RIGHT, Vector3.BACK, 0.7, 16, 0.03, CYAN, Vector2(21.5, 0.0))
		var bl := OmniLight3D.new()
		bl.light_color = _accent
		bl.light_energy = 2.0
		bl.omni_range = 9.0
		bl.position = _lm_top + Vector3(0, 0.4, 0)
		_cur.add_child(bl)


var _deco_mat_cache: ShaderMaterial


func _deco_mat() -> ShaderMaterial:
	if _deco_mat_cache == null:
		_deco_mat_cache = ShaderMaterial.new()
		_deco_mat_cache.shader = preload("res://art/shaders/deco.gdshader")
		_deco_mat_cache.set_shader_parameter("grime_tex", AssetLib.tex("dirty_concrete", "diff"))
		_deco_mat_cache.set_shader_parameter("grime_nrm", AssetLib.tex("dirty_concrete", "nor_gl"))
	return _deco_mat_cache


func _glow_mat(energy: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/neon.gdshader")
	m.set_shader_parameter("energy", energy)
	return m


func _flag_mesh() -> ArrayMesh:
	var g := Geo.new()
	for j: int in 4:
		var y0: float = -j * 0.3
		var y1: float = -(j + 1) * 0.3
		g.quad(Vector3(-0.35, y0, 0), Vector3(0.35, y0, 0), Vector3(0.35, y1, 0), Vector3(-0.35, y1, 0), Color.WHITE, Vector2.ZERO, Vector3.BACK)
	return g.mesh()
