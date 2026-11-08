class_name KitBuilding
extends Node3D
## [kit] Kit building: a cached, state-aware building with its own ground patch, clutter and lights.
##   var hub := KitBuilding.create("module_small", "broken", 7, {"main": "cream", "accent": "teal"})
##   add_child(hub)
##   hub.set_state("repaired")   # rebuilds from cache: broken | repaired | restored
##   hub.set_powered(true)       # emissive trims, lit windows and lamps (never while broken)
## Kinds: module_small, module_medium, module_large, tower, hangar, tank_farm, machine_housing.
## Geometry per (kind, state, seed) is cached; materials per (state, palette, powered) are cached.
## A building is ~8-14 surfaces (draw calls) + 2 MultiMeshes + its patch, whatever its detail.

const KINDS: PackedStringArray = ["module_small", "module_medium", "module_large", "tower", "hangar", "tank_farm", "machine_housing", "dome", "greenhouse"]

## Palette roles -> KitMat colours. Override any role per building/planet.
const DEFAULT_PALETTE: Dictionary = KitMat.ROLES

## Footprint (ground patch size) per kind.
const FOOTPRINT: Dictionary = {
	"module_small": Vector2(9, 8), "module_medium": Vector2(12, 10), "module_large": Vector2(16, 14),
	"tower": Vector2(9, 9), "hangar": Vector2(15, 17), "tank_farm": Vector2(14, 11), "machine_housing": Vector2(10, 8),
	"dome": Vector2(13, 14), "greenhouse": Vector2(14, 10),
}

var kind: String = "module_small"
var state: String = "broken"
var powered: bool = true
var seed_: int = 1
var palette: Dictionary = {}
var _mi: MeshInstance3D
var _patch: Node3D
var _lights: Array[OmniLight3D] = []


static func create(kind_: String, state_: String = "broken", seed__: int = 1, palette_: Dictionary = {}, powered_: bool = true) -> KitBuilding:
	var k := KitBuilding.new()
	k.kind = kind_
	k.state = state_
	k.seed_ = seed__
	k.powered = powered_
	k.palette = DEFAULT_PALETTE.duplicate()
	k.palette.merge(palette_, true)
	k.name = "Kit_" + kind_
	k._rebuild()
	return k


func set_state(s: String) -> void:
	if s == state and _mi != null:
		return
	state = s
	_rebuild()


func set_powered(p: bool) -> void:
	powered = p
	_apply_materials()


func is_lit() -> bool:
	return powered and state != "broken"


func _rebuild() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.free()
	_lights.clear()
	var data: BuildData = mesh_for(kind, state, seed_, palette)
	_patch = KitMesh.ground_patch(FOOTPRINT.get(kind, Vector2(10, 10)), state, seed_ + 100, {"palette": palette})
	add_child(_patch)
	_mi = MeshInstance3D.new()
	_mi.name = "Body"
	_mi.mesh = data.mesh
	add_child(_mi)
	for l: Dictionary in data.lights:
		var o := OmniLight3D.new()
		o.position = l["pos"]
		o.light_color = l["color"]
		o.omni_range = float(l["range"])
		o.light_energy = float(l["energy"])
		o.shadow_enabled = false
		o.add_to_group("kit_light")
		add_child(o)
		_lights.append(o)
	_apply_materials()


func _apply_materials() -> void:
	if _mi == null:
		return
	KitMat.apply(_mi, state, powered)
	for o: OmniLight3D in _lights:
		o.visible = is_lit()


class BuildData:
	extends Resource
	var mesh: ArrayMesh
	var lights: Array[Dictionary] = []
	var tris: int = 0


## Cached geometry for a kind/state/seed/palette (paint colours are baked per vertex).
static func mesh_for(kind_: String, state_: String, seed__: int, palette_: Dictionary = {}) -> BuildData:
	return KitMesh.cached("bld:%s:%s:%d:%d" % [kind_, state_, seed__, palette_.hash()], func() -> Resource:
		var b := KitMesh.Builder.new(seed__ * 7919 + KINDS.find(kind_), palette_, state_)
		match kind_:
			"module_small":
				_module_small(b, state_)
			"module_medium":
				_module_medium(b, state_)
			"module_large":
				_module_large(b, state_)
			"tower":
				_tower(b, state_)
			"hangar":
				_hangar(b, state_)
			"tank_farm":
				_tank_farm(b, state_)
			"machine_housing":
				_machine_housing(b, state_)
			"dome":
				_dome(b, state_)
			"greenhouse":
				_greenhouse(b, state_)
			_:
				push_warning("[kit] unknown building kind " + kind_)
		var d := BuildData.new()
		d.tris = b.tri_count()
		d.mesh = b.commit(null, true)
		d.lights = b.lights
		return d) as BuildData


static func _x(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return KitMesh.xf(pos, rot)


# ---------------------------------------------------------------------------------------------
# Shared pieces
# ---------------------------------------------------------------------------------------------

## A module block (cabin) of size (w, h, d), bottom centre at pos. Panelled walls on all sides,
## chunky accent corner columns, a rounded roof cap, a glowing trim under the eave on the front,
## windows on the front. Returns the roof height (top of cap).
static func _cabin(b: KitMesh.Builder, pos: Vector3, size: Vector3, state: String, opts: Dictionary = {}) -> float:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	var broken: bool = state == "broken"
	var wall_opts: Dictionary = {
		"key": "paint:main", "key2": opts.get("key2", ""), "panel": opts.get("panel", Vector2(1.1, 1.0)),
		"missing": 0.22 if broken else 0.0, "tilt": 1.0 if broken else 0.0, "patch": 0.18 if state == "repaired" else 0.0,
		"hazard": opts.get("hazard", false), "depth": 0.14,
	}
	var base: float = pos.y + 0.32
	# plinth
	b.box("concrete", Vector3(w + 0.5, 0.34, d + 0.5), _x(pos + Vector3(0, 0.17, 0)), 0.07, 2)
	# dark core so missing panels show depth, not sky
	b.box("dark_steel", Vector3(w - 0.3, h - 0.1, d - 0.3), _x(pos + Vector3(0, base - pos.y + h * 0.5, 0)), 0.05)
	var front := wall_opts.duplicate()
	front["trim"] = "trim:cool" if opts.get("trim", true) else ""
	KitMesh.panel_wall(b, w, h, _x(Vector3(pos.x - w * 0.5, base, pos.z + d * 0.5)), front)
	KitMesh.panel_wall(b, w, h, _x(Vector3(pos.x + w * 0.5, base, pos.z - d * 0.5), Vector3(0, 180, 0)), wall_opts)
	KitMesh.panel_wall(b, d, h, _x(Vector3(pos.x - w * 0.5, base, pos.z - d * 0.5), Vector3(0, -90, 0)), wall_opts)
	KitMesh.panel_wall(b, d, h, _x(Vector3(pos.x + w * 0.5, base, pos.z + d * 0.5), Vector3(0, 90, 0)), wall_opts)
	# corner columns
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.box("paint:accent", Vector3(0.36, h + 0.3, 0.36), _x(Vector3(pos.x + sx * w * 0.5, base + (h + 0.3) * 0.5 - 0.1, pos.z + sz * d * 0.5)), 0.08, 2)
	# roof cap: chunky rounded slab + inner deck
	var roof_rot := Vector3.ZERO
	if broken:
		roof_rot = Vector3(b.rng.randf_range(-2.5, 2.5), 0, b.rng.randf_range(-3.0, 3.0))
	var top: float = base + h + 0.14
	b.box("paint:accent", Vector3(w + 0.5, 0.36, d + 0.5), _x(Vector3(pos.x, top, pos.z), roof_rot), 0.14, 2)
	b.box("dark_steel", Vector3(w - 0.2, 0.1, d - 0.2), _x(Vector3(pos.x, top + 0.18, pos.z), roof_rot), 0.03)
	# windows on the front
	var nwin: int = int(opts.get("windows", maxi(1, int(w / 2.4))))
	var door_x: float = float(opts.get("door_x", 9999.0))
	for k: int in nwin:
		var wx: float = pos.x - w * 0.5 + (k + 0.5) * w / nwin
		if absf(wx - (pos.x + door_x)) < 1.2:
			continue
		_window(b, _x(Vector3(wx, base + h * 0.58, pos.z + d * 0.5 + 0.08)), Vector2(minf(1.3, w / nwin - 0.5), minf(0.9, h * 0.3)), state)
	if door_x < 999.0:
		var dh: float = minf(2.2, h - 0.5)
		var dp := Vector3(pos.x + door_x, base - 0.02, pos.z + d * 0.5 + 0.12)
		KitProps.hatch(b, _x(dp), Vector2(1.2, dh), state)
		# canopy over the door: sloped accent hood on two struts (breaks the box silhouette)
		var droop := Vector3(-14, 0, 6) if state == "broken" else Vector3(-14, 0, 0)
		b.box("paint:accent", Vector3(2.1, 0.14, 1.3), _x(dp + Vector3(0, dh + 0.62, 0.55), droop), 0.05, 2)
		b.box("dark_steel", Vector3(1.9, 0.06, 1.1), _x(dp + Vector3(0, dh + 0.53, 0.55), droop), 0.02)
		for sx: float in [-0.85, 0.85]:
			b.rod("dark_steel", dp + Vector3(sx, dh + 0.15, 0.0), dp + Vector3(sx, dh + 0.5, 1.05), 0.03, 6)
	return top + 0.18


## Window unit facing +Z centred at t: protruding frame, glass, sill, and boards when broken.
static func _window(b: KitMesh.Builder, t: Transform3D, size: Vector2, state: String) -> void:
	b.box("dark_steel", Vector3(size.x + 0.24, size.y + 0.24, 0.2), t, 0.05, 2)
	b.box("glass", Vector3(size.x, size.y, 0.06), t * _x(Vector3(0, 0, 0.09)), 0.02)
	b.box("paint:accent", Vector3(size.x + 0.4, 0.1, 0.3), t * _x(Vector3(0, -size.y * 0.5 - 0.15, 0.06)), 0.03)
	b.box("dark_steel", Vector3(0.05, size.y, 0.05), t * _x(Vector3(0, 0, 0.12)), 0.01)
	if state == "broken":
		for k: int in 2:
			b.box("rusty", Vector3(size.x + 0.3, 0.16, 0.04), t * _x(Vector3(0, (k - 0.5) * size.y * 0.5, 0.16), Vector3(0, 0, b.rng.randf_range(-14, 14))), 0.01)


## Rooftop AC/fan unit at t: box + round fan shroud + grille.
static func _roof_unit(b: KitMesh.Builder, t: Transform3D, state: String) -> void:
	b.box("paint:main", Vector3(1.4, 0.7, 1.1), t * _x(Vector3(0, 0.35, 0)), 0.08, 2)
	b.cyl("dark_steel", 0.42, 0.12, t * _x(Vector3(0.0, 0.7, 0)), 0.03, 16)
	b.cyl("steel", 0.08, 0.16, t * _x(Vector3(0.0, 0.7, 0)), 0.02, 8)
	var spin: float = 0.0 if state != "broken" else 20.0
	for k: int in 4:
		b.box("steel", Vector3(0.7, 0.02, 0.07), t * _x(Vector3(0, 0.8, 0), Vector3(0, 45 * k + spin, 0)), 0.005)
	KitProps.vent(b, t * _x(Vector3(0, 0.12, 0.56)), Vector2(1.0, 0.42), "paint:main")


## Clutter around a building: barrels, crates, a lamp post, planters (restored), debris (broken).
static func _clutter(b: KitMesh.Builder, state: String, spots: Array, lamp_at: Vector3, planters: Array = []) -> void:
	var broken: bool = state == "broken"
	for k: int in spots.size():
		var p: Vector3 = spots[k]
		if k % 2 == 0:
			for q: int in 3:
				var tip: bool = broken and q == 1
				KitProps.barrel(b, _x(p + Vector3(q * 0.7 - 0.7 + (1.2 if tip else 0.0), 0, b.rng.randf_range(-0.2, 0.2) + (0.5 if tip else 0.0)), Vector3(0, b.rng.randf() * 90, 0)), "paint:barrel" if q != 2 else "paint:accent", tip)
		else:
			KitProps.crate_stack(b, _x(p, Vector3(0, b.rng.randf_range(-20, 20), 0)), 4 if not broken else 3, state)
	KitProps.lamp_post(b, _x(lamp_at, Vector3(0, b.rng.randf_range(-30, 30), 0)), 4.2, state)
	if state != "broken":
		for pl: Variant in planters:
			var pp: Vector3 = pl
			KitProps.planter(b, _x(pp), 2.0, state)
	else:
		KitProps.debris(b, Transform3D.IDENTITY, 6.0, 14)


# ---------------------------------------------------------------------------------------------
# Assemblers
# ---------------------------------------------------------------------------------------------

static func _module_small(b: KitMesh.Builder, state: String) -> void:
	var top: float = _cabin(b, Vector3.ZERO, Vector3(4.6, 3.0, 3.6), state, {"door_x": -0.9, "windows": 2})
	_roof_unit(b, _x(Vector3(0.9, top, -0.3)), state)
	KitProps.antenna(b, _x(Vector3(-1.5, top, -1.0)), 2.2, state)
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(2.45, 0.6, 1.2), Vector3(2.45, 2.6, 1.2), Vector3(2.45, 2.6, -1.0), Vector3(2.45, top + 0.4, -1.0)]), 0.1)
	b.decal("label_hub", Vector2(1.4, 0.35), _x(Vector3(1.1, 2.75, 1.93)))
	b.decal("num_01", Vector2(0.55, 0.55), _x(Vector3(-2.0, 1.2, 1.93)))
	_clutter(b, state, [Vector3(3.6, 0, -1.6), Vector3(-3.6, 0, -0.8)], Vector3(-3.4, 0, 2.6), [Vector3(1.5, 0, 3.0)])


static func _module_medium(b: KitMesh.Builder, state: String) -> void:
	var broken: bool = state == "broken"
	var top: float = _cabin(b, Vector3(0, 0, 0), Vector3(7.0, 3.2, 5.0), state, {"door_x": 2.0, "windows": 3, "hazard": true})
	# upper module cantilevered to the left, on struts
	var up_pos := Vector3(-1.3, top - 0.18, -0.4)
	var top2: float = _cabin(b, up_pos, Vector3(4.6, 2.6, 3.8), state, {"windows": 2, "key2": "paint:accent"})
	for sz: float in [-1.0, 1.0]:
		b.rod("paint:accent", Vector3(-3.4, 0.35, -0.4 + sz * 1.6), Vector3(-3.4, top, -0.4 + sz * 1.6), 0.12, 10)
	# deck on the right part of the lower roof, with railing and stairs up from the ground
	KitProps.railing(b, Transform3D.IDENTITY, Vector3(1.1, top, 2.5), Vector3(3.5, top, 2.5), 1.0, "paint:rail", state)
	KitProps.railing(b, Transform3D.IDENTITY, Vector3(3.5, top, 2.5), Vector3(3.5, top, -2.5), 1.0, "paint:rail", state)
	KitProps.stairs(b, _x(Vector3(4.3, 0.0, 3.2), Vector3(0, 180, 0)), top - 0.05, 5.4, 0.9, "paint:rail", state)
	for k: int in 2:
		KitProps.solar_panel(b, _x(Vector3(-2.4 + k * 2.2, top2, -0.4)), Vector2(1.9, 1.2), state, 0.5)
	KitProps.tank(b, _x(Vector3(4.6, 0.0, -1.6)), 0.9, 2.6, "paint:accent", state)
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(4.6, 2.9, -1.6), Vector3(4.6, 3.4, -1.6), Vector3(3.55, 3.4, -1.6), Vector3(3.55, 1.0, -1.6)]), 0.09)
	KitProps.cable(b, Transform3D.IDENTITY, Vector3(-3.5, top2 - 0.4, 1.4), Vector3(-6.2, 4.0, 3.4), 0.7)
	b.decal("label_power", Vector2(1.6, 0.4), _x(Vector3(-1.3, top - 0.6 + 2.0, 1.56)))
	b.decal("num_02", Vector2(0.6, 0.6), _x(Vector3(-2.8, 1.6, 2.58)))
	_clutter(b, state, [Vector3(-4.8, 0, -2.0), Vector3(1.0, 0, -3.6)], Vector3(-6.2, 0, 3.4), [Vector3(-1.8, 0, 3.9)])
	if broken:
		b.box("paint:main", Vector3(1.1, 0.07, 0.95), _x(Vector3(-4.3, 0.1, 2.0), Vector3(8, 30, 4)), 0.02)


static func _module_large(b: KitMesh.Builder, state: String) -> void:
	var broken: bool = state == "broken"
	var top: float = _cabin(b, Vector3(-1.0, 0, -0.5), Vector3(9.0, 4.6, 7.0), state, {"windows": 0, "panel": Vector2(1.5, 1.15), "hazard": true})
	var top_w: float = _cabin(b, Vector3(5.6, 0, 0.8), Vector3(4.4, 3.0, 4.6), state, {"windows": 1, "door_x": 0.9})
	# big roll-up door in the main block front
	var dz: float = -0.5 + 3.5 + 0.12
	var dw: float = 4.2
	var dh: float = 3.4
	b.box("hazard", Vector3(dw + 0.7, 0.35, 0.36), _x(Vector3(-1.0, 0.32 + dh + 0.2, dz)), 0.06)
	for sx: float in [-1.0, 1.0]:
		b.box("hazard", Vector3(0.35, dh + 0.2, 0.36), _x(Vector3(-1.0 + sx * (dw * 0.5 + 0.18), 0.32 + dh * 0.5, dz)), 0.06)
	var shut: float = 1.0 if broken else 0.62
	var slats: int = int(dh * shut / 0.28)
	for k: int in slats:
		var y: float = 0.32 + dh - 0.14 - k * 0.28
		var rz: float = b.rng.randf_range(-2.0, 2.0) if broken else 0.0
		b.box("paint:main" if k % 5 != 2 else "paint:accent", Vector3(dw, 0.25, 0.1), _x(Vector3(-1.0, y, dz - 0.04), Vector3(0, 0, rz)), 0.03)
	if not broken:
		b.box("dark_steel", Vector3(dw, dh * (1.0 - shut), 0.04), _x(Vector3(-1.0, 0.32 + dh * (1.0 - shut) * 0.5, dz - 0.4)), 0.01)
		b.box("trim:warm", Vector3(dw - 0.4, 0.05, 0.05), _x(Vector3(-1.0, 0.32 + dh + 0.05, dz + 0.2)), 0.01)
	b.decal("chevrons", Vector2(1.6, 0.8), _x(Vector3(-1.0, 0.12, dz + 1.1), Vector3(-90, 0, 90)))
	_window(b, _x(Vector3(-4.6, 0.32 + 3.0, dz - 0.02)), Vector2(1.4, 0.9), state)
	_window(b, _x(Vector3(2.6, 0.32 + 3.0, dz - 0.02)), Vector2(1.1, 0.9), state)
	b.decal("label_hub", Vector2(2.4, 0.6), _x(Vector3(-1.0, 0.32 + dh + 0.75, dz + 0.02)))
	# chimney stack + skylights + roof units
	var sp := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.65, 0, 1), Vector3(0.65, 0.5, 0), Vector3(0.5, 0.8, 1), Vector3(0.45, 3.2, 0), Vector3(0.58, 3.3, 1), Vector3(0.58, 3.55, 1), Vector3(0.36, 3.55, 1), Vector3(0.36, 3.2, 0)])
	b.add("paint:accent", KitMesh.lathe(sp, 16), _x(Vector3(-4.0, top, -2.6), Vector3(0, 0, 4 if broken else 0)))
	for k: int in 3:
		b.box("paint:accent", Vector3(1.5, 0.35, 1.1), _x(Vector3(-2.2 + k * 1.9, top + 0.17, 0.4)), 0.06)
		b.box("glass", Vector3(1.3, 0.12, 0.9), _x(Vector3(-2.2 + k * 1.9, top + 0.38, 0.4), Vector3(-12, 0, 0)), 0.03)
	_roof_unit(b, _x(Vector3(1.8, top, -2.4)), state)
	_roof_unit(b, _x(Vector3(5.6, top_w, 0.2)), state)
	KitProps.ladder(b, _x(Vector3(-5.5, 0.3, 0.6), Vector3(0, -90, 0)), top - 0.3)
	# pipe runs between blocks and down the wall
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(3.4, 0.7, -2.4), Vector3(3.4, 3.8, -2.4), Vector3(5.0, 3.8, -2.4), Vector3(5.0, 3.8, -1.2)]), 0.14)
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(3.6, 0.5, -3.0), Vector3(3.6, 2.6, -3.0), Vector3(7.6, 2.6, -3.0), Vector3(7.6, 0.5, -3.0)]), 0.1, "paint:accent")
	KitProps.dish(b, _x(Vector3(-6.8, 0, -3.6), Vector3(0, 30, 0)), 1.1, state)
	_clutter(b, state, [Vector3(-6.6, 0, 2.2), Vector3(8.0, 0, 3.6)], Vector3(2.4, 0, 5.2), [Vector3(-4.4, 0, 3.9), Vector3(5.6, 0, 3.9)])


static func _tower(b: KitMesh.Builder, state: String) -> void:
	var broken: bool = state == "broken"
	# octagonal plinth
	b.add("concrete", KitMesh.bevel_cylinder(3.0, 0.8, 0.12, 8), _x(Vector3.ZERO, Vector3(0, 22.5, 0)))
	var lean := Vector3(0, 0, 2.5) if broken else Vector3.ZERO
	var tt: Transform3D = _x(Vector3(0, 0.8, 0), lean)
	# core shaft with bands
	b.add("paint:main", KitMesh.bevel_cylinder(1.5, 8.0, 0.1, 20), tt)
	for k: int in 4:
		b.add("paint:accent", KitMesh.bevel_cylinder(1.58, 0.3, 0.06, 20), tt * _x(Vector3(0, 0.4 + k * 2.0, 0)))
	# vertical seams/ribs
	for k: int in 8:
		var a: float = TAU * k / 8.0
		b.box("dark_steel", Vector3(0.14, 7.6, 0.14), tt * _x(Vector3(cos(a) * 1.5, 4.0, sin(a) * 1.5), Vector3(0, -rad_to_deg(a), 0)), 0.03)
	# balcony ring
	b.add("dark_steel", KitMesh.bevel_cylinder(2.5, 0.25, 0.06, 24), tt * _x(Vector3(0, 6.0, 0)))
	b.add("hazard", KitMesh.bevel_cylinder(2.52, 0.08, 0.02, 24), tt * _x(Vector3(0, 6.08, 0)))
	for k: int in 12:
		var a0: float = TAU * k / 12.0
		var a1: float = TAU * (k + 1) / 12.0
		if broken and k % 5 == 2:
			continue
		KitProps.railing(b, tt, Vector3(cos(a0) * 2.4, 6.25, sin(a0) * 2.4), Vector3(cos(a1) * 2.4, 6.25, sin(a1) * 2.4), 0.9, "paint:rail", state)
	# braces under the balcony
	for k: int in 6:
		var a: float = TAU * k / 6.0
		b.rod("paint:accent", tt * Vector3(cos(a) * 1.5, 4.8, sin(a) * 1.5), tt * Vector3(cos(a) * 2.3, 6.0, sin(a) * 2.3), 0.07, 6)
	# upper drum (control room) with window band
	var up: Transform3D = tt * _x(Vector3(0, 8.0, 0))
	b.add("paint:accent", KitMesh.bevel_cylinder(2.0, 0.45, 0.12, 24), up)
	b.add("glass", KitMesh.bevel_cylinder(1.88, 1.2, 0.04, 24), up * _x(Vector3(0, 0.45, 0)))
	for k: int in 10:
		var a: float = TAU * k / 10.0
		b.box("paint:main", Vector3(0.16, 1.25, 0.2), up * _x(Vector3(cos(a) * 1.92, 1.05, sin(a) * 1.92), Vector3(0, -rad_to_deg(a), 0)), 0.04)
	if broken:
		for k: int in 4:
			var a: float = TAU * (k * 2 + 1) / 10.0
			b.box("rusty", Vector3(0.9, 0.14, 0.05), up * _x(Vector3(cos(a) * 1.98, 0.9 + k * 0.1, sin(a) * 1.98), Vector3(0, -rad_to_deg(a) + 90, b.rng.randf_range(-20, 20))), 0.01)
	b.box("trim:cool", Vector3(0.05, 0.05, 0.05), up * _x(Vector3(0, 0.0, 0)), 0.01)
	b.add("trim:cool", KitMesh.bevel_cylinder(2.02, 0.05, 0.015, 24), up * _x(Vector3(0, 0.4, 0)))
	# roof cap (cone with lip)
	var cap := PackedVector3Array([Vector3(0, 0, 0), Vector3(2.25, 0, 1), Vector3(2.25, 0.25, 1), Vector3(1.6, 0.7, 0), Vector3(0.5, 1.1, 0), Vector3(0, 1.15, 0)])
	b.add("paint:main", KitMesh.lathe(cap, 24), up * _x(Vector3(0, 1.65, 0)))
	KitProps.antenna(b, up * _x(Vector3(0.4, 2.7, 0)), 2.6, state)
	KitProps.dish(b, up * _x(Vector3(-1.0, 2.4, 0.6), Vector3(0, 140, 0)), 0.6, state, false)
	# ladder up the shaft, door at the base, pipes running up
	KitProps.ladder(b, tt * _x(Vector3(0, 0.0, 1.45)), 6.0)
	KitProps.hatch(b, tt * _x(Vector3(1.0, 0.0, 1.2), Vector3(0, 40, 0)), Vector2(1.1, 2.1), state)
	KitProps.pipe_run(b, tt, PackedVector3Array([Vector3(-1.75, 0.3, -0.5), Vector3(-1.75, 5.6, -0.5), Vector3(-1.2, 6.4, -0.3)]), 0.12)
	b.decal("num_03", Vector2(1.0, 1.0), tt * _x(Vector3(0, 3.0, 1.62)))
	b.decal("logo", Vector2(1.2, 1.2), tt * _x(Vector3(0, 3.0, -1.62), Vector3(0, 180, 0)))
	_clutter(b, state, [Vector3(3.4, 0, -2.0), Vector3(-3.6, 0, 1.6)], Vector3(-2.6, 0, 3.6), [Vector3(2.6, 0, 3.2)])


## Closed rectangular profile (radial r0..r1, along y0..y1) for lathed shells/ribs, with edge
## mask 1 only at the corners and 0 a little inside, so paint survives on the faces.
static func _shell(r0: float, r1: float, y0: float, y1: float) -> PackedVector3Array:
	var e: float = minf(0.08, (y1 - y0) * 0.3)
	var er: float = minf(0.08, (r1 - r0) * 0.3)
	return PackedVector3Array([Vector3(r0, y0, 1), Vector3(r0 + er, y0, 0), Vector3(r1 - er, y0, 0), Vector3(r1, y0, 1),
		Vector3(r1, y0 + e, 0), Vector3(r1, y1 - e, 0), Vector3(r1, y1, 1), Vector3(r1 - er, y1, 0), Vector3(r0 + er, y1, 0),
		Vector3(r0, y1, 1), Vector3(r0, y1 - e, 0), Vector3(r0, y0 + e, 0), Vector3(r0, y0, 1)])


static func _hangar(b: KitMesh.Builder, state: String) -> void:
	var broken: bool = state == "broken"
	var r: float = 5.0
	var length: float = 12.0
	var z0: float = length * 0.5
	# arched shell: lathe around Y, rotated so Y runs along -Z and the arch stands up
	var shell := _shell(r, r + 0.22, 0.0, length)
	var arch_xf: Transform3D = _x(Vector3(0, 0.3, z0), Vector3(-90, 0, 0))
	if broken:
		# roof has holes: build it in strips and skip some
		var strips: int = 6
		for k: int in strips:
			if k == 2 or k == 4:
				continue
			var y0: float = length * k / strips
			var y1: float = length * (k + 1) / strips - 0.05
			var p := _shell(r, r + 0.22, y0, y1)
			b.add("paint:main", KitMesh.lathe(p, 18, 180.0), arch_xf, -1.0, 0.0)
		for k: int in 2:
			var y0: float = length * (2 + k * 2) / 6.0
			var p2 := _shell(r, r + 0.22, y0, y0 + 1.2)
			b.add("rusty", KitMesh.lathe(p2, 18, 120.0), arch_xf * _x(Vector3.ZERO, Vector3(0, 30, 0)), -1.0, 0.0)
	else:
		b.add("paint:main", KitMesh.lathe(shell, 22, 180.0), arch_xf, -1.0, 0.0)
	# ribs
	var nrib: int = 5
	for k: int in nrib:
		var y: float = length * k / (nrib - 1)
		y = clampf(y, 0.15, length - 0.35)
		var rp := _shell(r - 0.05, r + 0.5, y, y + 0.35)
		b.add("paint:accent", KitMesh.lathe(rp, 22, 180.0), arch_xf, -1.0, 0.0)
		# buttress feet
		for sx: float in [-1.0, 1.0]:
			b.box("concrete", Vector3(1.0, 0.9, 0.8), _x(Vector3(sx * (r + 0.4), 0.45, z0 - y - 0.17)), 0.08, 2)
	# skylight strip along the ridge
	if not broken:
		b.box("glass", Vector3(1.2, 0.1, length - 1.0), _x(Vector3(0, r + 0.42, 0)), 0.03)
		b.box("dark_steel", Vector3(1.5, 0.12, length - 0.8), _x(Vector3(0, r + 0.36, 0)), 0.03)
	# end walls: vertical strips under the arch; front has a big door opening
	for e: int in 2:
		var zf: float = z0 - 0.1 if e == 0 else -z0 + 0.1
		var strips2: int = 10
		for k: int in strips2:
			var x0: float = -r + 2.0 * r * k / strips2
			var x1: float = x0 + 2.0 * r / strips2
			var xc: float = (x0 + x1) * 0.5
			var hh: float = sqrt(maxf(r * r - maxf(absf(x0), absf(x1)) ** 2, 0.0)) + 0.1
			if e == 0 and absf(xc) < 3.0:
				# above the door only
				var dtop: float = 3.6
				if hh > dtop:
					b.box("paint:main" if k % 3 else "paint:accent", Vector3(x1 - x0 - 0.04, hh - dtop, 0.16), _x(Vector3(xc, 0.3 + dtop + (hh - dtop) * 0.5, zf)), 0.03)
				continue
			if broken and b.rng.randf() < 0.2:
				continue
			b.box("paint:main" if k % 3 else "paint:accent", Vector3(x1 - x0 - 0.04, hh, 0.16), _x(Vector3(xc, 0.3 + hh * 0.5, zf)), 0.03)
	# door: frame + sliding leaves (open when repaired)
	var fz: float = z0 + 0.05
	b.box("hazard", Vector3(6.4, 0.4, 0.4), _x(Vector3(0, 0.3 + 3.75, fz)), 0.06)
	for sx: float in [-1.0, 1.0]:
		b.box("hazard", Vector3(0.4, 3.6, 0.4), _x(Vector3(sx * 3.1, 0.3 + 1.8, fz)), 0.06)
	var open: float = 0.0 if broken else 1.6
	for sx: float in [-1.0, 1.0]:
		var lx: float = sx * (0.75 + open)
		var rot := Vector3(0, 0, 3.0 * sx) if broken else Vector3.ZERO
		b.box("paint:accent", Vector3(1.45, 3.4, 0.14), _x(Vector3(lx, 0.3 + 1.72, fz + 0.18), rot), 0.05, 2)
		b.box("dark_steel", Vector3(1.0, 0.6, 0.05), _x(Vector3(lx, 0.3 + 2.6, fz + 0.27), rot), 0.02)
	b.box("trim:warm", Vector3(5.4, 0.05, 0.06), _x(Vector3(0, 0.3 + 3.5, fz + 0.24)), 0.01)
	b.lights.append({"pos": Vector3(0, 3.0, z0 + 1.2), "color": KitMat.GLOW["warm"], "range": 8.0, "energy": 1.6})
	# interior glow floor + a parked crate stack visible through the door
	b.box("concrete", Vector3(2 * r, 0.3, length), _x(Vector3(0, 0.15, 0)), 0.05)
	KitProps.crate_stack(b, _x(Vector3(-2.0, 0.3, 1.0)), 5, state)
	b.decal("num_04", Vector2(0.9, 0.9), _x(Vector3(-4.0, 1.7, z0 - 0.015)))
	b.decal("label_dock", Vector2(2.4, 0.6), _x(Vector3(0, 0.3 + 4.5, z0 - 0.0)))
	b.decal("chevrons", Vector2(2.0, 1.0), _x(Vector3(0, 0.32, z0 + 1.6), Vector3(-90, 0, 90)))
	_clutter(b, state, [Vector3(6.6, 0, 4.6), Vector3(-6.8, 0, -3.0)], Vector3(4.2, 0, 7.6), [Vector3(-4.0, 0, 7.4)])


static func _tank_farm(b: KitMesh.Builder, state: String) -> void:
	b.box("concrete", Vector3(11.0, 0.3, 7.4), _x(Vector3(0, 0.15, 0)), 0.08, 2)
	# bund wall
	for sz: float in [-1.0, 1.0]:
		b.box("concrete", Vector3(11.0, 0.6, 0.3), _x(Vector3(0, 0.3, sz * 3.7)), 0.06, 2)
	var tanks: Array = [[Vector3(-3.4, 0.3, -0.6), 1.7, 4.8, "paint:main"], [Vector3(0.6, 0.3, -1.0), 1.3, 3.8, "paint:accent"], [Vector3(3.8, 0.3, 0.4), 1.5, 4.2, "paint:main"]]
	for tk: Array in tanks:
		KitProps.tank(b, _x(tk[0]), tk[1], tk[2], tk[3], state)
	# manifold pipes with elbows between tanks
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(-3.4, 1.0, 1.15), Vector3(-3.4, 1.0, 2.6), Vector3(3.8, 1.0, 2.6), Vector3(3.8, 1.0, 2.0)]), 0.16)
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(0.6, 1.0, 0.35), Vector3(0.6, 1.0, 2.6)]), 0.13)
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(5.5, 0.8, 2.6), Vector3(6.6, 0.8, 2.6), Vector3(6.6, 0.8, 4.4)]), 0.16, "paint:accent")
	# valves (hand wheels)
	for x: float in [-1.6, 2.2]:
		b.rod("dark_steel", Vector3(x, 1.0, 2.6), Vector3(x, 1.6, 2.6), 0.05, 6)
		var wheel := PackedVector3Array([Vector3(0.18, -0.03, 1), Vector3(0.26, -0.03, 1), Vector3(0.26, 0.03, 1), Vector3(0.18, 0.03, 1), Vector3(0.18, -0.03, 1)])
		b.add("paint:barrel", KitMesh.lathe(wheel, 14), _x(Vector3(x, 1.62, 2.6)))
	# catwalk across the tank tops
	var cy: float = 5.4
	b.box("dark_steel", Vector3(8.6, 0.12, 1.0), _x(Vector3(0.2, cy, -0.6)), 0.03)
	for x: float in [-1.2, 2.1]:
		b.box("paint:rail", Vector3(0.16, cy - 0.3, 0.16), _x(Vector3(x, 0.3 + (cy - 0.3) * 0.5, -0.6)), 0.03)
		b.rod("paint:rail", Vector3(x, 1.0, -0.6), Vector3(x + 0.8, cy - 0.1, -0.6), 0.05, 6)
	KitProps.railing(b, Transform3D.IDENTITY, Vector3(-4.0, cy + 0.06, -0.1), Vector3(4.4, cy + 0.06, -0.1), 1.0, "paint:rail", state)
	KitProps.railing(b, Transform3D.IDENTITY, Vector3(-4.0, cy + 0.06, -1.1), Vector3(4.4, cy + 0.06, -1.1), 1.0, "paint:rail", state)
	KitProps.ladder(b, _x(Vector3(-5.4, 0.3, -0.6), Vector3(0, -90, 0)), cy - 0.2)
	b.box("dark_steel", Vector3(1.2, 0.12, 1.0), _x(Vector3(-4.8, cy, -0.6)), 0.03)
	# pump house
	b.box("paint:accent", Vector3(1.6, 1.3, 1.2), _x(Vector3(-4.2, 0.95, 2.4)), 0.1, 2)
	b.cyl("dark_steel", 0.35, 0.5, _x(Vector3(-4.2, 1.6, 2.4)), 0.05, 12)
	b.box("trim:green", Vector3(0.2, 0.08, 0.04), _x(Vector3(-3.8, 1.25, 3.02)), 0.01)
	b.decal("warn", Vector2(0.6, 0.6), _x(Vector3(-4.6, 1.1, 3.02)))
	b.decal("label_water", Vector2(1.6, 0.4), _x(Vector3(0.0, 0.36, 3.86)))
	b.lights.append({"pos": Vector3(0.2, cy + 1.5, -0.6), "color": KitMat.GLOW["cool"], "range": 7.0, "energy": 1.0})
	b.box("trim:cool", Vector3(8.4, 0.03, 0.05), _x(Vector3(0.2, cy - 0.06, -0.1)), 0.01)
	_clutter(b, state, [Vector3(6.4, 0, -2.6), Vector3(-6.4, 0, -2.4)], Vector3(6.0, 0, 4.8), [Vector3(-2.4, 0, 4.6)])


static func _machine_housing(b: KitMesh.Builder, state: String) -> void:
	var broken: bool = state == "broken"
	# skid with I-beams
	for sz: float in [-1.0, 1.0]:
		b.box("dark_steel", Vector3(6.0, 0.35, 0.3), _x(Vector3(0, 0.175, sz * 1.5)), 0.03)
	b.box("dark_steel", Vector3(6.2, 0.12, 3.6), _x(Vector3(0, 0.41, 0)), 0.03)
	b.box("hazard", Vector3(6.25, 0.1, 0.12), _x(Vector3(0, 0.41, 1.82)), 0.02)
	# main body: rounded block with access panels
	var body_rot := Vector3(0, 0, 2.0) if broken else Vector3.ZERO
	var bt: Transform3D = _x(Vector3(-0.4, 0.47, 0), body_rot)
	b.box("paint:main", Vector3(4.2, 2.5, 3.0), bt * _x(Vector3(0, 1.25, 0)), 0.22, 3)
	b.box("paint:accent", Vector3(4.35, 0.4, 3.15), bt * _x(Vector3(0, 0.2, 0)), 0.1, 2)
	KitMesh.panel_wall(b, 3.6, 1.6, bt * _x(Vector3(-1.8, 0.55, 1.5)), {"key": "paint:main", "panel": Vector2(1.2, 0.8), "depth": 0.1, "missing": 0.3 if broken else 0.0, "tilt": 1.0 if broken else 0.0})
	KitMesh.panel_wall(b, 2.4, 1.6, bt * _x(Vector3(2.1, 0.55, 1.2), Vector3(0, 90, 0)), {"key": "paint:main", "panel": Vector2(1.2, 0.8), "depth": 0.1})
	# two fan shrouds on top
	for k: int in 2:
		var ft: Transform3D = bt * _x(Vector3(-1.0 + k * 2.0, 2.5, 0))
		b.cyl("paint:accent", 0.85, 0.45, ft, 0.12, 24)
		b.cyl("dark_steel", 0.7, 0.47, ft, 0.04, 20)
		b.cyl("steel", 0.14, 0.55, ft, 0.04, 10)
		var spin: float = 15.0 * k + (25.0 if broken else 0.0)
		for q: int in 5:
			b.box("steel", Vector3(1.25, 0.03, 0.18), ft * _x(Vector3(0, 0.48, 0), Vector3(12, 36 * q + spin, 0)), 0.01)
		for q: int in 4:
			b.box("dark_steel", Vector3(1.5, 0.04, 0.05), ft * _x(Vector3(0, 0.56, (q - 1.5) * 0.32)), 0.01)
	# exhaust stacks + pipes to the side
	for k: int in 2:
		var sp := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.22, 0, 1), Vector3(0.22, 2.4, 0), Vector3(0.3, 2.5, 1), Vector3(0.3, 2.75, 1), Vector3(0.17, 2.75, 1), Vector3(0.17, 2.5, 0)])
		b.add("paint:accent" if not broken else "rusty", KitMesh.lathe(sp, 14), bt * _x(Vector3(1.4 + k * 0.6, 2.4, -1.0)))
	KitProps.pipe_run(b, bt, PackedVector3Array([Vector3(2.1, 1.0, -0.6), Vector3(3.0, 1.0, -0.6), Vector3(3.0, 0.0, -0.6), Vector3(4.2, 0.0, -0.6)]), 0.15)
	# control cabinet with screen and buttons
	var ct: Transform3D = _x(Vector3(2.6, 0.47, 1.0))
	b.box("paint:accent", Vector3(1.0, 1.6, 0.6), ct * _x(Vector3(0, 0.8, 0)), 0.08, 2)
	b.box("dark_steel", Vector3(0.7, 0.45, 0.06), ct * _x(Vector3(0, 1.15, 0.3)), 0.02)
	b.box("trim:cool", Vector3(0.6, 0.36, 0.02), ct * _x(Vector3(0, 1.15, 0.33)), 0.005)
	for q: int in 3:
		b.cyl(["trim:green", "trim:red", "trim:warm"][q], 0.045, 0.04, ct * _x(Vector3(-0.2 + q * 0.2, 0.75, 0.3), Vector3(90, 0, 0)), 0.01, 8)
	b.box("paint:main", Vector3(1.15, 0.12, 0.75), ct * _x(Vector3(0, 1.66, 0.05)), 0.04)
	b.decal("warn", Vector2(0.5, 0.5), bt * _x(Vector3(-1.4, 1.9, 1.62)))
	b.decal("power", Vector2(0.6, 0.6), bt * _x(Vector3(1.1, 1.9, 1.62)))
	# cable tray to a pole
	KitProps.cable(b, Transform3D.IDENTITY, Vector3(-2.6, 2.4, -0.4), Vector3(-4.4, 3.6, -2.6), 0.6, 0.035)
	KitProps.cable(b, Transform3D.IDENTITY, Vector3(-2.6, 2.2, -0.2), Vector3(-4.4, 3.4, -2.5), 0.8, 0.03)
	b.rod("paint:pole", Vector3(-4.4, 0, -2.6), Vector3(-4.4, 3.9, -2.6), 0.1, 10)
	b.box("dark_steel", Vector3(0.6, 0.12, 0.12), _x(Vector3(-4.4, 3.7, -2.6)), 0.02)
	_clutter(b, state, [Vector3(3.8, 0, -2.4), Vector3(-3.4, 0, 2.6)], Vector3(4.2, 0, 3.0), [Vector3(-0.4, 0, 3.0)])


static func _dome(b: KitMesh.Builder, state: String) -> void:
	var broken: bool = state == "broken"
	var r: float = 4.6
	var base_y: float = 0.6
	b.add("concrete", KitMesh.bevel_cylinder(r + 0.6, base_y, 0.12, 24), Transform3D.IDENTITY)
	b.add("hazard", KitMesh.bevel_cylinder(r + 0.62, 0.12, 0.03, 24), _x(Vector3(0, base_y - 0.2, 0)))
	var top_a: float = 74.0
	# 8 shell sectors (painted), with a glass band between 38 and 54 degrees
	for k: int in 8:
		for band: int in 3:
			var a0: float = [0.0, 38.0, 54.0][band]
			var a1: float = [38.0, 54.0, top_a][band]
			if broken and ((k == 2 and band == 2) or (k == 5 and band >= 1)):
				continue
			var p := PackedVector3Array()
			var steps: int = 4
			for q: int in steps + 1:
				var a: float = deg_to_rad(lerpf(a0, a1, float(q) / steps))
				p.append(Vector3(cos(a) * r, sin(a) * r, 1.0 if q == 0 or q == steps else 0.0))
			for q: int in range(steps, -1, -1):
				var a: float = deg_to_rad(lerpf(a0, a1, float(q) / steps))
				p.append(Vector3(cos(a) * (r - 0.16), sin(a) * (r - 0.16), 1.0 if q == 0 or q == steps else 0.0))
			p.append(p[0])
			var key: String = "paint:main" if band != 1 else ("glass" if not broken else "rusty")
			if band == 0 and k % 2 == 1:
				key = "paint:accent" if not broken else "paint:main"
			b.add(key, KitMesh.lathe(p, 4, 43.0), _x(Vector3(0, base_y, 0), Vector3(0, 45.0 * k + 1.0, 0)), -1.0, 0.0)
	# meridian ribs + ring bands
	for k: int in 8:
		var pts := PackedVector3Array()
		var ang: float = deg_to_rad(-45.0 * k)
		for q: int in 10:
			var a: float = deg_to_rad(lerpf(0.0, top_a + 4.0, q / 9.0))
			pts.append(Vector3(cos(ang) * cos(a) * (r + 0.05), base_y + sin(a) * (r + 0.05), sin(ang) * cos(a) * (r + 0.05)))
		b.tube("paint:accent", pts, 0.11, 8)
	for a_deg: float in [38.0, 54.0]:
		var ring := PackedVector3Array()
		var a: float = deg_to_rad(a_deg)
		for q: int in 33:
			var t: float = TAU * q / 32.0
			ring.append(Vector3(cos(t) * cos(a) * (r + 0.04), base_y + sin(a) * (r + 0.04), sin(t) * cos(a) * (r + 0.04)))
		b.tube("dark_steel", ring, 0.07, 6)
	# glowing ring under the glass band and a glass oculus cap with a beacon
	var gr := PackedVector3Array()
	for q: int in 33:
		var t: float = TAU * q / 32.0
		gr.append(Vector3(cos(t) * cos(deg_to_rad(37.0)) * (r + 0.1), base_y + sin(deg_to_rad(37.0)) * (r + 0.1), sin(t) * cos(deg_to_rad(37.0)) * (r + 0.1)))
	b.tube("trim:cool", gr, 0.035, 5)
	var cap_y: float = base_y + sin(deg_to_rad(top_a)) * r
	var cap_r: float = cos(deg_to_rad(top_a)) * r + 0.2
	b.add("paint:accent", KitMesh.bevel_cylinder(cap_r, 0.4, 0.1, 20), _x(Vector3(0, cap_y - 0.15, 0)))
	b.add("glass" if not broken else "rusty", KitMesh.lathe(PackedVector3Array([Vector3(cap_r - 0.2, 0, 1), Vector3(cap_r - 0.35, 0.35, 0), Vector3(0.4, 0.6, 0), Vector3(0, 0.62, 0)]), 20), _x(Vector3(0, cap_y + 0.25, 0)))
	KitProps.antenna(b, _x(Vector3(0.8, cap_y + 0.25, 0.3)), 1.6, state)
	# entrance tunnel (+Z): small arch with a door, hazard frame and lamp
	var tl: float = 2.4
	var tr: float = 1.5
	var tunnel := _shell(tr, tr + 0.18, 0.0, tl)
	b.add("paint:main", KitMesh.lathe(tunnel, 12, 180.0), _x(Vector3(0, base_y, r + tl - 0.5), Vector3(-90, 0, 0)), -1.0, 0.0)
	for zz: float in [r - 0.4, r + tl - 0.6]:
		b.add("paint:accent", KitMesh.lathe(_shell(tr - 0.02, tr + 0.32, 0.0, 0.3), 12, 180.0), _x(Vector3(0, base_y, zz + 0.3), Vector3(-90, 0, 0)), -1.0, 0.0)
	KitProps.hatch(b, _x(Vector3(0, base_y, r + tl - 0.55)), Vector2(1.3, 1.8), state)
	b.box("concrete", Vector3(3.2, base_y, tl + 0.4), _x(Vector3(0, base_y * 0.5, r + tl * 0.5 - 0.3)), 0.06)
	KitProps.stairs(b, _x(Vector3(0, 0, r + tl + 0.2)), base_y, 0.8, 1.6, "paint:rail", state)
	b.decal("logo", Vector2(1.4, 1.4), _x(Vector3(-3.0, base_y + 1.8, 3.25), Vector3(0, -40, 0)))
	b.decal("num_05", Vector2(0.9, 0.9), _x(Vector3(3.0, base_y + 1.8, 3.25), Vector3(0, 40, 0)))
	b.lights.append({"pos": Vector3(0, base_y + 2.5, 0), "color": KitMat.GLOW["warm"], "range": 7.0, "energy": 1.4})
	# interior: a tree and planters visible through the glass when restored
	if not broken:
		KitProps.bush(b, _x(Vector3(0, base_y, 0)), 1.6 if state == "restored" else 1.0)
		b.rod("paint:pole", Vector3(0, base_y, 0), Vector3(0, base_y + 1.6, 0), 0.15, 8)
	_clutter(b, state, [Vector3(5.6, 0, -3.8), Vector3(-6.0, 0, -2.6)], Vector3(2.6, 0, 7.6), [Vector3(-2.6, 0, 7.0)])


static func _greenhouse(b: KitMesh.Builder, state: String) -> void:
	var broken: bool = state == "broken"
	var w: float = 5.6
	var l: float = 9.0
	var wall_h: float = 2.4
	var ridge: float = 1.6
	var y0: float = 0.5
	# concrete base wall with painted kick panels
	b.box("concrete", Vector3(w + 0.4, y0, l + 0.4), _x(Vector3(0, y0 * 0.5, 0)), 0.08, 2)
	for sx: float in [-1.0, 1.0]:
		b.box("paint:accent", Vector3(0.12, 0.5, l), _x(Vector3(sx * (w * 0.5 + 0.02), y0 + 0.25, 0)), 0.03)
	# frame: posts every bay, eaves, ridge
	var bays: int = 6
	var bay: float = l / bays
	for k: int in bays + 1:
		var z: float = -l * 0.5 + k * bay
		var tilt := Vector3(0, 0, 4.0 if broken and k == 2 else 0.0)
		for sx: float in [-1.0, 1.0]:
			b.box("paint:main", Vector3(0.14, wall_h, 0.14), _x(Vector3(sx * w * 0.5, y0 + wall_h * 0.5, z), tilt), 0.03)
			b.rod("paint:main", Vector3(sx * w * 0.5, y0 + wall_h, z), Vector3(0, y0 + wall_h + ridge, z), 0.07, 6)
	for sx: float in [-1.0, 1.0]:
		b.box("paint:main", Vector3(0.16, 0.16, l + 0.16), _x(Vector3(sx * w * 0.5, y0 + wall_h, 0)), 0.04)
	b.box("paint:accent", Vector3(0.26, 0.22, l + 0.5), _x(Vector3(0, y0 + wall_h + ridge, 0)), 0.06, 2)
	# glass panes: walls and roof slopes (some missing / grimy when broken)
	var slope_len: float = sqrt(ridge * ridge + w * w * 0.25)
	var slope_ang: float = rad_to_deg(atan2(ridge, w * 0.5))
	for k: int in bays:
		var zc: float = -l * 0.5 + (k + 0.5) * bay
		for sx: float in [-1.0, 1.0]:
			if broken and b.rng.randf() < 0.3:
				continue
			b.box("glasshouse", Vector3(0.03, wall_h - 0.12, bay - 0.14), _x(Vector3(sx * w * 0.5, y0 + wall_h * 0.5, zc)), 0.008)
			if broken and b.rng.randf() < 0.35:
				continue
			var vent_open: float = 18.0 if (state == "restored" and k % 3 == 1) else 0.0
			b.box("glasshouse", Vector3(slope_len - 0.1, 0.03, bay - 0.14), _x(Vector3(sx * w * 0.25, y0 + wall_h + ridge * 0.5, zc), Vector3(0, 0, -sx * slope_ang - sx * vent_open * 0.2)), 0.008)
	# gable ends: glass with a door at the front
	for e: int in 2:
		var z: float = (l * 0.5) * (1.0 if e == 0 else -1.0)
		for q: int in 4:
			var xc: float = -w * 0.5 + (q + 0.5) * w / 4.0
			if e == 0 and (q == 1 or q == 2):
				continue
			b.box("glasshouse", Vector3(w / 4.0 - 0.1, wall_h - 0.1, 0.03), _x(Vector3(xc, y0 + wall_h * 0.5, z)), 0.008)
		b.box("glasshouse", Vector3(w - 0.4, ridge * 0.9, 0.03), _x(Vector3(0, y0 + wall_h + ridge * 0.42, z)) * Transform3D(Basis().scaled(Vector3(1, 1, 1)), Vector3.ZERO), 0.008)
	KitProps.hatch(b, _x(Vector3(0, y0, l * 0.5 + 0.05)), Vector2(1.4, 2.1), state, "paint:accent")
	# beds with plants inside
	for sx: float in [-1.0, 1.0]:
		b.box("concrete", Vector3(1.4, 0.45, l - 1.2), _x(Vector3(sx * 1.6, y0 + 0.225, -0.3)), 0.05)
		b.box("dirt", Vector3(1.26, 0.04, l - 1.34), _x(Vector3(sx * 1.6, y0 + 0.45, -0.3)), 0.01)
		if not broken:
			var n: int = 9 if state == "restored" else 5
			for q: int in n:
				var z: float = -l * 0.5 + 0.9 + q * (l - 2.2) / (n - 1)
				KitProps.bush(b, _x(Vector3(sx * 1.6 + b.rng.randf_range(-0.25, 0.25), y0 + 0.45, z)), b.rng.randf_range(0.28, 0.42) * (1.0 if state == "restored" else 0.75))
				if state == "restored" and q % 2 == 0:
					b.add(["paint:flower_a", "paint:flower_b", "paint:yellow"][q % 3], KitMesh.pebble(q % 4), _x(Vector3(sx * 1.6 + 0.3, y0 + 0.9, z + 0.2)) * Transform3D(Basis().scaled(Vector3.ONE * 0.09), Vector3.ZERO), -1.0, 0.0)
		else:
			for q: int in 3:
				b.add("rusty", KitMesh.pebble(q), _x(Vector3(sx * 1.6, y0 + 0.47, -2.0 + q * 2.0)) * Transform3D(Basis().scaled(Vector3(0.25, 0.1, 0.25)), Vector3.ZERO), -1.0, 0.0)
	# grow lights along the ridge (thin warm strips) + sprinkler-free water tank and pipe
	for sx: float in [-1.0, 1.0]:
		b.box("trim:white", Vector3(0.05, 0.03, l - 1.0), _x(Vector3(sx * 1.6, y0 + wall_h + 0.2, 0)), 0.01)
		b.rod("dark_steel", Vector3(sx * 1.6, y0 + wall_h + 0.22, -l * 0.4), Vector3(sx * 1.3, y0 + wall_h + ridge * 0.6, -l * 0.4), 0.015, 4)
	b.lights.append({"pos": Vector3(0, y0 + wall_h, 0), "color": KitMat.GLOW["white"], "range": 7.5, "energy": 1.0})
	KitProps.tank(b, _x(Vector3(w * 0.5 + 1.4, 0, -l * 0.5 + 1.2)), 0.8, 2.0, "paint:accent", state)
	KitProps.pipe_run(b, Transform3D.IDENTITY, PackedVector3Array([Vector3(w * 0.5 + 1.4, 2.2, -l * 0.5 + 1.2), Vector3(w * 0.5 + 1.4, 2.8, -l * 0.5 + 1.2), Vector3(w * 0.5 + 0.3, 2.8, -l * 0.5 + 1.2)]), 0.08)
	b.decal("label_seeds", Vector2(1.6, 0.4), _x(Vector3(0, y0 + wall_h + 0.35, l * 0.5 + 0.03)))
	_clutter(b, state, [Vector3(-w * 0.5 - 1.6, 0, 2.6), Vector3(w * 0.5 + 1.6, 0, 2.8)], Vector3(-w * 0.5 - 1.4, 0, l * 0.5 + 0.8), [Vector3(2.6, 0, l * 0.5 + 1.2)])
