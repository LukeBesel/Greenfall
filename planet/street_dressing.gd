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


func build(p_layout: CityLayout, p_field: HexField) -> void:
	layout = p_layout
	field = p_field
	_rng.seed = layout.seed_value * 7 + 90210
	if not layout.wild:
		_collect_facades()
		_build_shopfronts()
		_build_murals()
		_build_billboard()
		_build_street_lines()
	_build_yard_lights()
	_build_yard_paint()
	_build_puddles()
	_build_crates()
	_build_weeds()
	_flush()


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
		var col: Color = AWNING[_rng.randi() % AWNING.size()]
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
				_crate(Transform3D(Basis.looking_at(-al3).rotated(Vector3.UP, _rng.randf_range(-0.2, 0.2)), cp + Vector3.UP * 0.16), PLASTIC[_rng.randi() % PLASTIC.size()])
				if _rng.randf() < 0.5:
					_crate(Transform3D(Basis.looking_at(-al3).rotated(Vector3.UP, _rng.randf_range(-0.3, 0.3)), cp + Vector3.UP * 0.48), PLASTIC[_rng.randi() % PLASTIC.size()])
			else:
				_barrels.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), cp + out3 * 0.05), PLASTIC[_rng.randi() % PLASTIC.size()]])
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
	add_child(l)


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
		add_child(lt)


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
		add_child(mi)


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
	add_child(body)
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
	add_child(mi)
	# Pasted-up slogan along the bottom, half peeled.
	var l := Label3D.new()
	l.text = "BRIGHTER DAYS AHEAD"
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
	add_child(l)


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
		var col: Color = WARM if warm and _rng.randf() < 0.8 else BULB_COLORS[(i + _rng.randi_range(0, 1)) % BULB_COLORS.size()]
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
	var start: int = _rng.randi() % PENNANT.size()
	for i: int in range(1, n):
		if _rng.randf() < 0.07:
			continue  # torn off
		var p: Vector3 = _catenary(a, b, sag, float(i) / n)
		var col: Color = PENNANT[(start + i) % PENNANT.size()].darkened(_rng.randf_range(0.0, 0.15))
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


func _build_yard_lights() -> void:
	var y: float = CityLayout.YARD_HALF + 0.35
	var tops: Array[Vector3] = []
	for c: Vector2 in [Vector2(-y, -y), Vector2(y, -y), Vector2(y, y), Vector2(-y, y)]:
		tops.append(_pole(Vector3(c.x, 0, c.y), 5.6))
	# Perimeter and a cross over the yard: warm festoon lights.
	for i: int in 4:
		if i != 2:  # no run along the front edge: it would hang across the default camera view
			_string_lights(tops[i], tops[(i + 1) % 4], 1.0, true)
	_string_lights(tops[0], tops[2], 1.6, true, 0.6)
	_string_lights(tops[1], tops[3], 1.6, true, 0.6)
	# Bunting just under the back run.
	_bunting(tops[0] - Vector3(0, 0.45, 0), tops[1] - Vector3(0, 0.45, 0), 1.1)
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
	var yellow := Color(0.98, 0.78, 0.1, 0.92)
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
				img.set_pixelv(ij, Color(0.98, 0.76, 0.08, 0.9) if stripe else Color(0.07, 0.07, 0.07, 0.85))
	# Walkway: two yellow lines from the front edge in to the depot.
	line.call(Vector2(-1.1, half - 0.6), Vector2(-1.1, 0.4), 0.16, yellow)
	line.call(Vector2(1.1, half - 0.6), Vector2(1.1, 0.4), 0.16, yellow)
	# Numbered bays along the back fence.
	for k: int in 3:
		var x0: float = -3.9 + k * 2.6
		line.call(Vector2(x0, -half + 0.6), Vector2(x0, -half + 3.6), 0.15, yellow)
		line.call(Vector2(x0 + 2.6, -half + 0.6), Vector2(x0 + 2.6, -half + 3.6), 0.15, yellow)
		_paint_glyph(img, str(k + 1), Vector2(x0 + 1.3, -half + 2.4), 0.75, white, to_px, line)
	line.call(Vector2(-3.9, -half + 3.6), Vector2(3.9, -half + 3.6), 0.15, yellow)
	# Arrows: to the hopper on the right, and along the walkway to the depot.
	_paint_arrow(Vector2(2.6, -0.6), Vector2(1, 0), 1.6, white, line)
	_paint_arrow(Vector2(0.0, 6.2), Vector2(0, -1), 1.4, white, line)
	_paint_arrow(Vector2(-3.0, -half + 4.6), Vector2(0, -1), 1.0, yellow, line)
	# Cracks with moss, wandering in from the edges.
	for k: int in 9:
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
	mat.set_shader_parameter("bay", half * 2.0 / 6.0)
	mat.set_shader_parameter("seed", float(layout.seed_value % 97))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0, half * 2.0)
	mi.mesh = pm
	mi.name = "YardSlab"
	mi.position = Vector3(0, 0.012, 0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


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
	add_child(body)
	var corners: Array[Vector2] = [Vector2(-y, -y), Vector2(y, -y), Vector2(-y, y), Vector2(y, y)]
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
		var yaw: float = _rng.randf_range(-0.2, 0.2)
		# A pallet on the ground under everything.
		_pallet(Transform3D(Basis(Vector3.UP, yaw), base + Vector3(-out.x * 0.15, 0, -out.z * 0.15)))
		var top: float = 0.14
		match ci:
			0:  # crate stack and a plastic barrel
				var n: int = _rng.randi_range(2, 4)
				for k: int in n:
					_crate(Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.12, 0.12)), base + Vector3(_rng.randf_range(-0.04, 0.04), top + 0.16 + k * 0.32, 0.0)), PLASTIC[_rng.randi() % PLASTIC.size()])
				_barrels.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), base + Vector3(-out.x * 1.0, 0, 0)), PLASTIC[1]])
			1:  # steel drums and a tarp-covered heap
				for k: int in 3:
					var dp: Vector3 = base + Vector3(-out.x * (0.1 + (k % 2) * 0.62), top, -out.z * (k / 2) * 0.62 - out.z * 0.1)
					_drums.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), dp), [Color(0.55, 0.13, 0.08), Color(0.12, 0.25, 0.45), Color(0.2, 0.32, 0.18)][k]])
				_tarp(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)), base + Vector3(-out.x * 0.4, 0, -out.z * 1.5)), Vector2(1.8, 1.4), 0.75, Color(0.13, 0.32, 0.62))
			2:  # stacked pallets and a crate
				for k: int in range(1, 4):
					_pallet(Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.08, 0.08)), base + Vector3(-out.x * 0.15, k * 0.14, -out.z * 0.15)))
				_crate(Transform3D(Basis(Vector3.UP, yaw + 0.4), base + Vector3(-out.x * 1.05, 0.16, 0.1)), PLASTIC[_rng.randi() % PLASTIC.size()])
				_pot(base + Vector3(0.0, 0, -out.z * 1.1))
			3:  # tarp heap and a work light aimed into the yard
				_tarp(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, TAU)), base + Vector3(-out.x * 0.1, 0.0, -out.z * 0.1)), Vector2(1.6, 1.5), 0.9, Color(0.55, 0.5, 0.2))
				_crate(Transform3D(Basis(Vector3.UP, yaw - 0.3), base + Vector3(-out.x * 1.1, 0.16, 0.0)), PLASTIC[_rng.randi() % PLASTIC.size()])
				_work_light(base + Vector3(-out.x * 0.6, 0, -out.z * 1.4), Vector3(-out.x, 0, -out.z).normalized())
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.6, 1.0, 1.6)
		cs.shape = bs
		cs.position = base + Vector3(-out.x * 0.15, 0.5, -out.z * 0.15)
		body.add_child(cs)


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
	add_child(sl)
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
		add_child(mi)
	if not _tubes.empty():
		var nm := ShaderMaterial.new()
		nm.shader = preload("res://art/shaders/neon.gdshader")
		nm.set_shader_parameter("energy", 5.0)
		var ti := MeshInstance3D.new()
		ti.mesh = _tubes.mesh()
		ti.material_override = nm
		ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ti.name = "Neon"
		add_child(ti)
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
	add_child(mmi)
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
