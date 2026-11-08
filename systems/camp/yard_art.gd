class_name YardArt
extends RefCounted
## [yard] Art for the start yard and the Hub builds (owner: "Moon Sweepers hub quality": chunky,
## colourful, bevelled, greebled, nicely lit). Local helpers until the shared kit (art/kit/**,
## docs/ART_KIT.md) lands on main; then the shapes and materials here move onto it.
##
## Everything is built with a Kit: bevelled boxes and cylinders, bolts, vents, pipes and hazard
## stripes, collected per material into ONE MeshInstance3D with a few surfaces:
##   paint   systems/camp/yard_paint.gdshader; vertex colour = paint, alpha 0 = bare metal;
##           `wear` 0..1 adds rust, chips and faded paint (broken builds ~0.7, fresh ~0.12)
##   hazard  the same shader with diagonal stripes (vertex colour + near-black)
##   glow    systems/camp/yard_glow.gdshader: lenses, LEDs and screens; dark until powered
##   glass   dark glass
## Powered state: YardArt.set_powered(node, on) lights every glow surface and every small light
## made by a Kit under `node`. When you land nothing glows: a build lights up only when it is
## built (and, for lamps, powered).
##
## Models (all positions in the node's local frame, origin on the ground):
##   dress_board(world, bits)   restyles the lean-to, workbench, yard lamp and generator in place
##                              (scenes/slice.gd _build_board makes the nodes; names/paths stay)
##   bench_state(bench, ok, animate)   broken (rusty, pegboard slumped, drawer hanging, dark) or fixed
##   bin_body(level) -> {root, size, mouth_y, ram}   the trash bin by level (automation/depot.gd)
##   depot_pad(radius) / depot_scale(...)            the weigh plate and the dial post


# Palette: cosy, saturated, cohesive. Alpha 0 = bare metal.
const TEAL := Color(0.18, 0.56, 0.6)
const TEAL_D := Color(0.15, 0.4, 0.45)
const ORANGE := Color(0.96, 0.5, 0.14)
const YELLOW := Color(0.98, 0.74, 0.16)
const CREAM := Color(0.93, 0.89, 0.8)
const RED := Color(0.84, 0.25, 0.18)
const GREEN := Color(0.32, 0.6, 0.32)
const OLIVE := Color(0.33, 0.42, 0.26)
const BLUE := Color(0.22, 0.4, 0.68)
const WOOD := Color(0.66, 0.45, 0.26)
const DARK := Color(0.2, 0.21, 0.23)
const RUBBER := Color(0.07, 0.07, 0.08)
const STEEL := Color(0.66, 0.68, 0.7, 0.0)
const GUNMETAL := Color(0.3, 0.32, 0.35, 0.0)
const BRASS := Color(0.8, 0.62, 0.32, 0.0)
# Light colours.
const WARM := Color(1.0, 0.8, 0.52)
const AMBER := Color(1.0, 0.6, 0.16)
const MINT := Color(0.45, 1.0, 0.7)
const CYAN := Color(0.45, 0.88, 1.0)

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}


# --- Wear -> kit state ------------------------------------------------------------------------------

## Kit state for a wear value: >= 0.5 broken, >= 0.25 repaired, else restored (art/kit, docs/ART_KIT.md).
static func state_for(wear: float) -> String:
	return "broken" if wear >= 0.5 else ("repaired" if wear >= 0.25 else "restored")


# --- Meshes ---------------------------------------------------------------------------------------

## Bevelled box (smooth chamfered edges), cached by size.
static func bbox(size: Vector3, bev: float) -> Mesh:
	var key: String = "b%.3f_%.3f_%.3f_%.3f" % [size.x, size.y, size.z, bev]
	if not _mesh_cache.has(key):
		_mesh_cache[key] = ProcMesh.rounded_box(size, maxf(bev, 0.002), 1)
	return _mesh_cache[key]


# --- The Kit builder --------------------------------------------------------------------------------

class Kit:
	extends RefCounted
	## Thin adapter over the shared kit's KitMesh.Builder (art/kit/kit_mesh.gd): the yard models
	## keep their colour-based calls, the kit gives the shaders (edge wear, baked AO, grime, rust
	## per state), trims, decals and one draw call per material.
	var b := KitMesh.Builder.new(17, {}, "repaired")
	var lights: Array = []  # [pos, color, energy, range]
	var _stack: Array[Transform3D] = [Transform3D.IDENTITY]

	func push(xf: Transform3D) -> void:
		_stack.append(_stack.back() * xf)

	func pop() -> void:
		if _stack.size() > 1:
			_stack.pop_back()

	func _t(xf: Transform3D) -> Transform3D:
		return _stack.back() * xf

	## The kit key for one of the palette colours (alpha 0 = bare metal).
	static func key_of(col: Color, key: String) -> String:
		match key:
			"glow":
				return "trim:#" + Color(col.r, col.g, col.b).to_html(false)
			"hazard", "glass", "concrete", "rusty", "rubber":
				return key
		if col.a < 0.5:
			return "steel" if col.get_luminance() > 0.45 else "dark_steel"
		if col.is_equal_approx(YardArt.RUBBER):
			return "rubber"
		return "paint:#" + Color(col.r, col.g, col.b).to_html(false)

	func _add_key(key: String, col: Color) -> String:
		var k: String = key_of(col, key)
		if k == "hazard":
			b.palette["hazard"] = "#" + Color(col.r, col.g, col.b).to_html(false)
		return k

	## Bevelled box. bev < 0 = auto (about a fifth of the thinnest side, at most 4 cm).
	func box(size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, bev: float = -1.0, key: String = "paint") -> void:
		var bv: float = bev if bev >= 0.0 else minf(0.04, minf(size.x, minf(size.y, size.z)) * 0.2)
		b.box(_add_key(key, col), size, _t(ProcMesh.xf(pos, rot)), bv)

	## Bevelled cylinder centred on pos (Y axis before `rot`); r_top tapers it.
	func cyl(r: float, h: float, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, bev: float = -1.0, segs: int = 14, key: String = "paint", r_top: float = -1.0) -> void:
		var bv: float = bev if bev >= 0.0 else minf(0.03, minf(r, h) * 0.2)
		var t: Transform3D = _t(ProcMesh.xf(pos, rot)) * Transform3D(Basis(), Vector3(0, -h * 0.5, 0))
		var k: String = _add_key(key, col)
		if r_top >= 0.0 and absf(r_top - r) > 0.002:
			var p := PackedVector3Array([Vector3(0, 0, 1), Vector3(r, 0, 1), Vector3(r_top, h, 1), Vector3(0, h, 1)])
			b.add(k, KitMesh.lathe(p, segs), t)
		else:
			b.cyl(k, r, h, t, bv, segs)

	func hazard(size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO, col: Color = YardArt.YELLOW) -> void:
		box(size, pos, col, rot, -1.0, "hazard")

	func glow_box(size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
		box(size, pos, col, rot, minf(0.012, minf(size.x, minf(size.y, size.z)) * 0.3), "glow")

	func glow_cyl(r: float, h: float, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, segs: int = 14) -> void:
		cyl(r, h, pos, col, rot, minf(0.01, minf(r, h) * 0.3), segs, "glow")

	## An atlas decal (art/kit/decals: arrow, chevrons, warn, power, logo, num_01.., label_*) on a
	## face looking along +Z after `rot`.
	func decal(nm: String, size: Vector2, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
		b.decal(nm, size, _t(ProcMesh.xf(pos, rot)))

	## A small light that only shines when the build is powered (YardArt.set_powered).
	func light(pos: Vector3, col: Color, energy: float, rng: float) -> void:
		lights.append([_stack.back() * pos, col, energy, rng])

	## A hex bolt head standing out of a face with outward normal `nrm`.
	func bolt(pos: Vector3, nrm: Vector3, col: Color = YardArt.STEEL, r: float = 0.022) -> void:
		var n: Vector3 = nrm.normalized()
		b.cyl(key_of(col, "paint"), r, r * 0.9, _t(KitMesh.look_y(pos, n)), r * 0.25, 6)

	## Bolts at the four corners of a rectangle: centre c, half-extents along u and v, face normal n.
	func bolts4(c: Vector3, u: Vector3, v: Vector3, n: Vector3, col: Color = YardArt.STEEL, r: float = 0.022) -> void:
		for su: float in [-1.0, 1.0]:
			for sv: float in [-1.0, 1.0]:
				bolt(c + u * su + v * sv, n, col, r)

	## A panel on a face: back plate, a slightly smaller raised inset, corner bolts. The panel lies
	## in the local XY plane facing +Z before `rot`.
	func panel(w: float, h: float, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, inset_col: Color = Color(-1, 0, 0), t: float = 0.04) -> void:
		push(ProcMesh.xf(pos, rot))
		box(Vector3(w, h, t), Vector3.ZERO, col)
		var ic: Color = inset_col if inset_col.r >= 0.0 else col.lightened(0.08)
		box(Vector3(w - 0.12, h - 0.12, t * 0.6), Vector3(0, 0, t * 0.45), ic, Vector3.ZERO, 0.012)
		bolts4(Vector3(0, 0, t * 0.5), Vector3(w * 0.5 - 0.035, 0, 0), Vector3(0, h * 0.5 - 0.035, 0), Vector3.BACK, YardArt.STEEL, 0.016)
		pop()

	## A louvred vent facing +Z before `rot`.
	func vent(w: float, h: float, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, slats: int = 5) -> void:
		push(ProcMesh.xf(pos, rot))
		box(Vector3(w, h, 0.03), Vector3.ZERO, YardArt.DARK)
		box(Vector3(w + 0.04, 0.04, 0.05), Vector3(0, h * 0.5, 0.01), col)
		box(Vector3(w + 0.04, 0.04, 0.05), Vector3(0, -h * 0.5, 0.01), col)
		box(Vector3(0.04, h, 0.05), Vector3(w * 0.5, 0, 0.01), col)
		box(Vector3(0.04, h, 0.05), Vector3(-w * 0.5, 0, 0.01), col)
		for i: int in slats:
			var y: float = lerpf(-h * 0.5 + h / (slats * 2.0), h * 0.5 - h / (slats * 2.0), float(i) / maxf(1.0, slats - 1))
			box(Vector3(w - 0.03, h / slats * 0.55, 0.018), Vector3(0, y, 0.02), col.darkened(0.25), Vector3(-35, 0, 0), 0.005)
		pop()

	## A straight pipe from a to b with flange collars at both ends.
	func pipe(a: Vector3, e: Vector3, r: float, col: Color, flanges: bool = true, key: String = "paint") -> void:
		var pa: Vector3 = _stack.back() * a
		var pe: Vector3 = _stack.back() * e
		var d: Vector3 = pe - pa
		if d.length() < 0.001:
			return
		b.rod(key_of(col, key), pa, pe, r, 10)
		if flanges:
			var dn: Vector3 = d.normalized()
			for p: Vector3 in [pa + dn * 0.005, pe - dn * 0.055]:
				b.cyl("steel", r * 1.45, 0.05, KitMesh.look_y(p, dn), 0.012, 10)

	## A sagging cable through points (rubber unless coloured).
	func cable(pts: Array, r: float = 0.025, col: Color = YardArt.RUBBER) -> void:
		var pv := PackedVector3Array()
		for p: Vector3 in pts:
			pv.append(_stack.back() * p)
		b.tube(key_of(col, "paint"), pv, r, 8, 0.4)

	## Builds the MeshInstance3D. `wear` picks the kit state (YardArt.state_for); unpowered.
	func mi(wear: float = 0.15, name: String = "") -> MeshInstance3D:
		var m := MeshInstance3D.new()
		if name != "":
			m.name = name
		into(m, wear)
		return m

	## Puts the mesh into an existing MeshInstance3D (keeps its name, transform and children).
	func into(m: MeshInstance3D, wear: float = 0.15) -> void:
		var st: String = YardArt.state_for(wear)
		b.state = st
		m.mesh = b.commit()
		m.material_override = null
		KitMat.apply(m, st, false)
		m.set_meta("kit_state", st)
		m.set_meta("kit_powered", false)
		for l: Array in lights:
			var ol := OmniLight3D.new()
			ol.position = l[0]
			ol.light_color = l[1]
			ol.light_energy = l[2]
			ol.omni_range = l[3]
			ol.omni_attenuation = 1.6
			ol.shadow_enabled = false
			ol.visible = false
			ol.set_meta("yard_light", true)
			m.add_child(ol)


# --- States ---------------------------------------------------------------------------------------

## Lights (or kills) every trim and Kit light under `root` (never lit while broken).
static func set_powered(root: Node, on: bool) -> void:
	if root == null:
		return
	if root is MeshInstance3D and root.has_meta("kit_state"):
		var st: String = str(root.get_meta("kit_state"))
		KitMat.apply(root as MeshInstance3D, st, on)
		root.set_meta("kit_powered", on)
	if root is Light3D and root.has_meta("yard_light"):
		(root as Light3D).visible = on
	for c: Node in root.get_children():
		set_powered(c, on)


## The "it comes back on" moment for a Kit build (world3's stutter, planet/power_fx.gd): after
## `delay` s a spark, a few stutters, then steady light.
static func flicker_on(host: Node, node: Node, delay: float = 0.0) -> void:
	if host == null or node == null:
		return
	set_powered(node, false)
	var tw: Tween = host.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		if node is Node3D and (node as Node3D).is_inside_tree():
			Vfx.burst("sparkle", (node as Node3D).global_position + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.5), 0.4)
		Audio.play("clunk", randf_range(1.6, 2.0), -14.0))
	for s: Array in PowerFx.STUTTER:
		var on: bool = float(s[0]) > 0.5
		tw.tween_callback(func() -> void:
			if is_instance_valid(node):
				set_powered(node, on))
		if float(s[1]) > 0.0:
			tw.tween_interval(float(s[1]))


## Re-paints every Kit mesh under `root` at a new wear (broken -> repaired): a new kit state.
static func set_wear(root: Node, wear: float) -> void:
	if root == null:
		return
	if root is MeshInstance3D and root.has_meta("kit_state"):
		var st: String = state_for(wear)
		root.set_meta("kit_state", st)
		KitMat.apply(root as MeshInstance3D, st, bool(root.get_meta("kit_powered", false)))
	for c: Node in root.get_children():
		set_wear(c, wear)


## A solid box for a build (PROP layer: Lumi, robots and bales stop; the camera arm doesn't).
static func solid(parent: Node3D, size: Vector3, pos: Vector3, nm: String = "Solid") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = PhysLayers.PROP
	var cs := CollisionShape3D.new()
	cs.shape = PropColliders.box_shape(size)
	cs.position = pos
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


# --- The lean-to, workbench, yard lamp and generator ---------------------------------------------

## Restyles the yard pieces scenes/slice.gd _build_board made, in place: same nodes, names,
## transforms and colliders (camp.gd and the slice's ruin pass keep driving them).
static func dress_board(bits: Dictionary, world: Node3D = null) -> void:
	var frame: MeshInstance3D = bits.get("frame") as MeshInstance3D
	if frame:
		shack_frame().into(frame, 0.2)
		_shack_clutter(frame)
	var roof: MeshInstance3D = bits.get("roof") as MeshInstance3D
	if roof:
		shack_roof().into(roof, 0.2)
	var back: MeshInstance3D = bits.get("back") as MeshInstance3D
	if back:
		shack_back().into(back, 0.18)
		set_powered(back, true)  # only shows once the lean-to is built
	var side: MeshInstance3D = bits.get("side") as MeshInstance3D
	if side:
		shack_side().into(side, 0.2)
	var bulb: MeshInstance3D = bits.get("bulb") as MeshInstance3D
	if bulb:
		shack_bulb().into(bulb, 0.15)
		set_powered(bulb, true)  # shown only while the lean-to's lamp is on
	var bench: Node3D = bits.get("bench") as Node3D
	if bench and bench.get_child_count() > 0 and bench.get_child(0) is MeshInstance3D:
		dress_bench(bench)
	var sl: MeshInstance3D = bits.get("street_lamp") as MeshInstance3D
	if sl:
		street_lamp().into(sl, 0.15)
		var lt: Light3D = bits.get("street_light") as Light3D
		if lt:
			lt.position.y = LAMP_HEAD_Y - 0.12
			lt.light_energy = 2.6
			var follow := func() -> void: set_powered(sl, lt.visible)
			lt.visibility_changed.connect(follow)
			follow.call()
	var gen: MeshInstance3D = bits.get("generator") as MeshInstance3D
	if gen:
		# Out from under the lean-to's open side (it hid the bench), panel and cable toward the shack.
		gen.position = Vector3(-5.2, 0.0, -0.7)
		gen.rotation_degrees = Vector3(0, 90, 0)
		generator().into(gen, 0.15)
		set_powered(gen, true)  # it only shows once built: built = running
		solid(gen, Vector3(1.45, 1.1, 0.85), Vector3(0, 0.55, 0), "GeneratorBody")
	if world and world.is_inside_tree():
		var feet: Array = []
		for key: String in ["generator", "street_lamp"]:
			var n: Node3D = bits.get(key) as Node3D
			if n:
				feet.append(n.global_position)
		var dp: Node3D = world.get("depot") as Node3D
		if dp:
			feet.append(dp.global_position)
			feet.append(dp.global_position + Vector3(0, 0, -2.7))
		var fr: Node3D = bits.get("frame") as Node3D
		dress_ground(world, fr.get_parent() as Node3D if fr else null, 8.5, feet)


# Lean-to (shack-local: opens toward +Z, back wall at z -1.15, posts at x +-1.6).
static func shack_frame() -> Kit:
	var k := Kit.new()
	for p: Vector3 in [Vector3(-1.6, 0, -1.1), Vector3(1.6, 0, -1.1), Vector3(-1.6, 0, 1.0), Vector3(1.6, 0, 1.0)]:
		var hgt: float = 2.5 if p.z < 0 else 2.1
		k.box(Vector3(0.36, 0.06, 0.36), p + Vector3(0, 0.03, 0), GUNMETAL)  # base plate
		k.bolts4(p + Vector3(0, 0.06, 0), Vector3(0.13, 0, 0), Vector3(0, 0, 0.13), Vector3.UP)
		k.box(Vector3(0.15, hgt, 0.15), p + Vector3(0, hgt * 0.5, 0), TEAL)
		k.box(Vector3(0.2, 0.08, 0.2), p + Vector3(0, hgt - 0.04, 0), TEAL_D)  # cap
		k.box(Vector3(0.19, 0.12, 0.19), p + Vector3(0, 0.12, 0), TEAL_D)  # foot collar
		if p.z > 0:
			k.hazard(Vector3(0.165, 0.42, 0.165), p + Vector3(0, 0.55, 0))
	# Ring beams and the sloping side rails.
	k.box(Vector3(3.5, 0.16, 0.16), Vector3(0, 2.42, -1.1), TEAL)
	k.box(Vector3(3.5, 0.16, 0.16), Vector3(0, 2.02, 1.0), TEAL)
	var slope: float = rad_to_deg(atan2(0.4, 2.1))
	for x: float in [-1.6, 1.6]:
		k.box(Vector3(0.14, 0.14, 2.2), Vector3(x, 2.24, -0.05), TEAL, Vector3(-slope, 0, 0))
		# Knee braces.
		k.box(Vector3(0.08, 0.6, 0.08), Vector3(x, 2.05, -0.82), TEAL_D, Vector3(45, 0, 0))
		k.box(Vector3(0.08, 0.6, 0.08), Vector3(x, 1.68, 0.74), TEAL_D, Vector3(-45, 0, 0))
	for x: float in [-1.35, 1.35]:
		k.box(Vector3(0.6, 0.08, 0.08), Vector3(x, 1.8, 1.0), TEAL_D, Vector3(0, 0, 45.0 if x > 0 else -45.0))
	for x: float in [-1.0, 0.0, 1.0]:  # beam bolts
		k.bolt(Vector3(x, 2.02, 1.085), Vector3.BACK)
		k.bolt(Vector3(x, 2.42, -1.015), Vector3.BACK)
	# A conduit up the back-left post feeding the lamp.
	k.pipe(Vector3(-1.48, 0.1, -1.0), Vector3(-1.48, 2.3, -1.0), 0.03, GUNMETAL, false)
	k.box(Vector3(0.16, 0.22, 0.1), Vector3(-1.45, 1.3, -0.97), CREAM)  # junction box
	k.glow_box(Vector3(0.03, 0.03, 0.02), Vector3(-1.45, 1.36, -0.915), MINT)
	return k


static func shack_roof() -> Kit:
	var k := Kit.new()
	k.box(Vector3(3.8, 0.07, 2.66), Vector3.ZERO, TEAL_D)
	for i: int in 10:  # corrugation ribs
		var x: float = -1.71 + i * 0.38
		k.box(Vector3(0.1, 0.06, 2.66), Vector3(x, 0.055, 0), TEAL, Vector3.ZERO, 0.025)
	k.box(Vector3(3.92, 0.12, 0.1), Vector3(0, 0.03, 1.36), ORANGE)  # front trim
	k.box(Vector3(3.92, 0.12, 0.1), Vector3(0, 0.03, -1.36), ORANGE)
	k.box(Vector3(0.1, 0.12, 2.8), Vector3(1.93, 0.03, 0), ORANGE)
	k.box(Vector3(0.1, 0.12, 2.8), Vector3(-1.93, 0.03, 0), ORANGE)
	k.pipe(Vector3(-1.9, -0.06, 1.46), Vector3(1.9, -0.06, 1.46), 0.06, GUNMETAL, true)  # gutter
	# A little solar panel and a stub antenna: the yard's first bit of the future.
	k.push(ProcMesh.xf(Vector3(-0.7, 0.14, -0.2), Vector3(6, 0, 0)))
	k.box(Vector3(1.3, 0.06, 0.9), Vector3.ZERO, GUNMETAL)
	k.box(Vector3(1.2, 0.03, 0.8), Vector3(0, 0.035, 0), Color(0.12, 0.2, 0.36), Vector3.ZERO, 0.008)
	for i: int in 3:
		k.box(Vector3(0.02, 0.035, 0.8), Vector3(-0.4 + i * 0.4, 0.04, 0), STEEL, Vector3.ZERO, 0.005)
	k.pop()
	k.cyl(0.05, 0.12, Vector3(1.4, 0.1, -0.9), GUNMETAL)
	k.cyl(0.012, 0.7, Vector3(1.4, 0.5, -0.9), STEEL, Vector3.ZERO, 0.004, 6)
	k.glow_cyl(0.025, 0.04, Vector3(1.4, 0.86, -0.9), RED)
	return k


static func shack_back() -> Kit:
	var k := Kit.new()
	# Three cream panels in a teal frame (wall centred, 3.3 x 2.3).
	for i: int in 3:
		var x: float = -1.1 + i * 1.1
		k.panel(1.04, 2.16, Vector3(x, 0, 0), CREAM if i != 1 else Color(0.86, 0.84, 0.76), Vector3.ZERO, Color(-1, 0, 0), 0.05)
		k.panel(1.04, 2.16, Vector3(x, 0, -0.02), TEAL_D, Vector3(0, 180, 0), Color(-1, 0, 0), 0.03)
	for x: float in [-1.65, -0.55, 0.55, 1.65]:
		k.box(Vector3(0.1, 2.3, 0.1), Vector3(x, 0, 0), TEAL)
	k.box(Vector3(3.4, 0.1, 0.12), Vector3(0, 1.12, 0), TEAL)
	k.box(Vector3(3.4, 0.14, 0.12), Vector3(0, -1.08, 0), TEAL_D)
	k.hazard(Vector3(3.3, 0.1, 0.13), Vector3(0, -0.95, 0))
	# A round vent fan high on the right, a porthole on the left.
	k.cyl(0.26, 0.08, Vector3(1.1, 0.7, 0.05), GUNMETAL, Vector3(90, 0, 0))
	k.cyl(0.2, 0.06, Vector3(1.1, 0.7, 0.07), DARK, Vector3(90, 0, 0))
	for a: int in 5:
		k.box(Vector3(0.05, 0.17, 0.015), Vector3(1.1, 0.7, 0.1) + Vector3(cos(a * TAU / 5), sin(a * TAU / 5), 0) * 0.1, STEEL, Vector3(20, 0, rad_to_deg(a * TAU / 5) + 90), 0.005)
	k.cyl(0.05, 0.05, Vector3(1.1, 0.7, 0.11), ORANGE, Vector3(90, 0, 0))
	k.cyl(0.22, 0.07, Vector3(-1.1, 0.72, 0.05), ORANGE, Vector3(90, 0, 0), -1.0, 18)
	k.glow_cyl(0.16, 0.04, Vector3(-1.1, 0.72, 0.08), Color(0.55, 0.75, 0.95), Vector3(90, 0, 0), 18)
	for a: int in 8:
		k.bolt(Vector3(-1.1, 0.72, 0.085) + Vector3(cos(a * TAU / 8), sin(a * TAU / 8), 0) * 0.19, Vector3.BACK, STEEL, 0.014)
	return k


static func shack_side() -> Kit:
	var k := Kit.new()
	k.panel(1.4, 1.6, Vector3.ZERO, TEAL_D, Vector3(0, 90, 0), TEAL, 0.05)
	k.panel(1.4, 1.6, Vector3(-0.02, 0, 0), TEAL_D, Vector3(0, -90, 0), Color(-1, 0, 0), 0.03)
	k.hazard(Vector3(0.07, 0.12, 1.42), Vector3(0.02, -0.72, 0))
	k.decal("logo", Vector2(0.55, 0.55), Vector3(-0.065, 0.15, 0), Vector3(0, -90, 0))
	k.decal("label_hub", Vector2(0.8, 0.2), Vector3(-0.065, -0.4, 0), Vector3(0, -90, 0))
	k.box(Vector3(0.09, 0.08, 1.46), Vector3(0, 0.82, 0), TEAL)
	return k


static func shack_bulb() -> Kit:
	var k := Kit.new()
	k.cyl(0.02, 0.16, Vector3(0, 0.16, 0), DARK, Vector3.ZERO, 0.005, 8)
	k.cyl(0.13, 0.1, Vector3(0, 0.06, 0), ORANGE, Vector3.ZERO, -1.0, 16, "paint", 0.06)
	k.glow_cyl(0.07, 0.05, Vector3(0, -0.01, 0), WARM)
	for a: int in 4:
		k.box(Vector3(0.012, 0.1, 0.012), Vector3(cos(a * TAU / 4) * 0.1, -0.04, sin(a * TAU / 4) * 0.1), DARK, Vector3.ZERO, 0.003)
	k.cyl(0.11, 0.015, Vector3(0, -0.09, 0), DARK, Vector3.ZERO, 0.004, 12)
	return k


## Crates, a barrel, a cable drum and a potted sprout tucked round the lean-to (children of the
## frame, so they come and go with the build). Visual only, small, against the walls.
static func _shack_clutter(frame: Node3D) -> void:
	var k := Kit.new()
	# Barrel outside the back-right corner.
	k.cyl(0.26, 0.78, Vector3(2.05, 0.39, -0.95), BLUE)
	for y: float in [0.16, 0.62]:
		k.cyl(0.272, 0.05, Vector3(2.05, y, -0.95), GUNMETAL)
	k.cyl(0.04, 0.03, Vector3(2.12, 0.79, -0.9), STEEL)
	# Two stacked crates beside it.
	k.box(Vector3(0.55, 0.42, 0.45), Vector3(2.12, 0.21, -0.25), ORANGE)
	k.box(Vector3(0.57, 0.06, 0.47), Vector3(2.12, 0.33, -0.25), DARK)
	k.box(Vector3(0.42, 0.34, 0.36), Vector3(2.08, 0.59, -0.28), CREAM, Vector3(0, 12, 0))
	# A cable drum on its side at the left front post.
	k.push(ProcMesh.xf(Vector3(-2.0, 0.28, 0.75), Vector3(90, 0, 15)))
	k.cyl(0.28, 0.05, Vector3(0, 0.16, 0), WOOD)
	k.cyl(0.28, 0.05, Vector3(0, -0.16, 0), WOOD)
	k.cyl(0.17, 0.28, Vector3.ZERO, RED)
	k.pop()
	# A sprout in a bucket by the right front post (cosy, lived-in).
	k.cyl(0.13, 0.22, Vector3(1.86, 0.11, 1.2), YELLOW, Vector3.ZERO, -1.0, 14, "paint", 0.16)
	k.cyl(0.14, 0.03, Vector3(1.86, 0.205, 1.2), DARK)
	for a: int in 5:
		k.box(Vector3(0.05, 0.16, 0.012), Vector3(1.86, 0.3, 1.2) + Vector3(cos(a * 1.3), 0, sin(a * 1.3)) * 0.04, GREEN, Vector3(rad_to_deg(sin(a * 1.3)) * 0.5, rad_to_deg(a * 1.3), rad_to_deg(cos(a * 1.3)) * 0.5), 0.005)
	frame.add_child(k.mi(0.25, "Clutter"))


# Workbench (bench-local: front +Z, top surface at y 0.95). Child 0 of the bench keeps the body;
# the slumped pegboard and the drawer are children of it (camp.gd treats the bench's other direct
# MeshInstance3D children as its tools).
static func dress_bench(bench: Node3D) -> void:
	var body: MeshInstance3D = bench.get_child(0)
	bench_body().into(body, 0.15)
	var upper: MeshInstance3D = bench_upper().mi(0.15, "Upper")
	body.add_child(upper)
	var drawer: MeshInstance3D = bench_drawer().mi(0.15, "Drawer")
	drawer.position = Vector3(-0.65, 0.54, 0.0)
	body.add_child(drawer)
	var scraps: MeshInstance3D = bench_scraps().mi(0.6, "Scraps")
	body.add_child(scraps)
	body.set_meta("yard_bench", true)


static func bench_body() -> Kit:
	var k := Kit.new()
	k.box(Vector3(2.3, 0.08, 0.86), Vector3(0, 0.91, 0), WOOD, Vector3.ZERO, 0.025)  # butcher-block top
	for i: int in 6:
		k.box(Vector3(0.008, 0.012, 0.86), Vector3(-0.95 + i * 0.38, 0.95, 0), WOOD.darkened(0.3), Vector3.ZERO, 0.002)
	k.box(Vector3(2.34, 0.07, 0.05), Vector3(0, 0.89, 0.44), STEEL)  # front edge trim
	for x: float in [-1.05, 1.05]:
		for z: float in [-0.34, 0.34]:
			k.box(Vector3(0.1, 0.86, 0.1), Vector3(x, 0.43, z), TEAL)
			k.box(Vector3(0.17, 0.04, 0.17), Vector3(x, 0.02, z), RUBBER)
			k.bolt(Vector3(x, 0.8, z + 0.055 * signf(z)), Vector3(0, 0, signf(z)))
	k.box(Vector3(2.1, 0.11, 0.06), Vector3(0, 0.8, 0.36), TEAL)
	k.box(Vector3(2.1, 0.11, 0.06), Vector3(0, 0.8, -0.36), TEAL)
	k.box(Vector3(2.1, 0.05, 0.72), Vector3(0, 0.25, 0), TEAL_D)  # lower shelf
	k.hazard(Vector3(2.1, 0.07, 0.03), Vector3(0, 0.23, 0.37))
	# Drawer cabinet (the middle drawer is a separate part).
	k.box(Vector3(0.62, 0.54, 0.7), Vector3(-0.65, 0.54, 0), ORANGE)
	for y: float in [0.38, 0.7]:
		k.box(Vector3(0.54, 0.14, 0.03), Vector3(-0.65, y, 0.36), ORANGE.lightened(0.15))
		k.box(Vector3(0.2, 0.025, 0.035), Vector3(-0.65, y + 0.02, 0.385), STEEL, Vector3.ZERO, 0.008)
	# A bench vice at the right front corner.
	k.box(Vector3(0.2, 0.1, 0.18), Vector3(0.98, 1.0, 0.3), GUNMETAL)
	k.box(Vector3(0.2, 0.12, 0.05), Vector3(0.98, 1.06, 0.42), BLUE)
	k.box(Vector3(0.2, 0.12, 0.05), Vector3(0.98, 1.06, 0.26), BLUE)
	k.cyl(0.012, 0.3, Vector3(0.98, 1.02, 0.5), STEEL, Vector3(0, 0, 90), 0.003, 6)
	# Cable from the top down the back leg to the floor.
	k.cable([Vector3(0.9, 0.95, -0.4), Vector3(1.0, 0.7, -0.42), Vector3(1.05, 0.2, -0.44), Vector3(1.25, 0.03, -0.3)], 0.018)
	return k


## The pegboard, its shelf, the desk lamp and a little monitor (powered once the bench is fixed).
static func bench_upper() -> Kit:
	var k := Kit.new()
	for x: float in [-1.05, 1.05]:
		k.box(Vector3(0.08, 0.92, 0.08), Vector3(x, 1.4, -0.38), TEAL)
	k.box(Vector3(2.06, 0.64, 0.04), Vector3(0, 1.38, -0.4), TEAL_D)
	for i: int in 9:  # peg holes as tiny dark studs
		for j: int in 3:
			k.box(Vector3(0.025, 0.025, 0.01), Vector3(-0.9 + i * 0.225, 1.2 + j * 0.18, -0.375), DARK, Vector3.ZERO, 0.004)
	# Tools on the pegboard: wrench, hammer, saw, a coil of wire.
	k.box(Vector3(0.05, 0.36, 0.02), Vector3(-0.3, 1.4, -0.36), STEEL, Vector3(0, 0, 18), 0.008)
	k.cyl(0.05, 0.02, Vector3(-0.355, 1.57, -0.36), STEEL, Vector3(90, 0, 0), 0.005, 8)
	k.box(Vector3(0.04, 0.32, 0.03), Vector3(0.0, 1.38, -0.36), WOOD, Vector3.ZERO, 0.01)
	k.box(Vector3(0.16, 0.06, 0.05), Vector3(0.0, 1.55, -0.355), GUNMETAL, Vector3.ZERO, 0.012)
	k.box(Vector3(0.36, 0.12, 0.01), Vector3(0.36, 1.32, -0.37), STEEL, Vector3(0, 0, -8), 0.004)
	k.box(Vector3(0.1, 0.1, 0.04), Vector3(0.18, 1.34, -0.36), RED, Vector3(0, 0, -8), 0.012)
	k.cyl(0.09, 0.05, Vector3(0.75, 1.4, -0.36), ORANGE, Vector3(90, 0, 0), 0.015, 14)
	k.cyl(0.05, 0.055, Vector3(0.75, 1.4, -0.36), DARK, Vector3(90, 0, 0), 0.01, 10)
	# Parts bins.
	for i: int in 4:
		k.box(Vector3(0.18, 0.1, 0.12), Vector3(-0.85 + i * 0.2, 1.14, -0.32), [YELLOW, BLUE, RED, GREEN][i], Vector3.ZERO, 0.015)
	# Top shelf with jars.
	k.box(Vector3(2.12, 0.04, 0.22), Vector3(0, 1.82, -0.32), TEAL)
	for i: int in 5:
		k.cyl(0.045, 0.1, Vector3(-0.85 + i * 0.16, 1.89, -0.3), [CREAM, ORANGE, CREAM, BLUE, YELLOW][i], Vector3.ZERO, 0.01, 10)
	# Monitor on the shelf.
	k.box(Vector3(0.44, 0.3, 0.12), Vector3(0.55, 2.0, -0.32), CREAM)
	k.glow_box(Vector3(0.36, 0.22, 0.02), Vector3(0.55, 2.0, -0.255), MINT)
	k.box(Vector3(0.1, 0.04, 0.08), Vector3(0.55, 1.86, -0.32), DARK)
	# Desk lamp clamped to the right post.
	k.pipe(Vector3(1.0, 1.75, -0.36), Vector3(0.82, 1.92, 0.0), 0.018, ORANGE, false)
	k.pipe(Vector3(0.82, 1.92, 0.0), Vector3(0.68, 1.62, 0.14), 0.018, ORANGE, false)
	k.cyl(0.035, 0.05, Vector3(0.82, 1.92, 0.0), GUNMETAL, Vector3(0, 0, 90))
	k.cyl(0.09, 0.12, Vector3(0.68, 1.58, 0.14), ORANGE, Vector3(25, 0, 0), -1.0, 14, "paint", 0.04)
	k.glow_cyl(0.065, 0.02, Vector3(0.68, 1.52, 0.17), WARM, Vector3(25, 0, 0))
	k.light(Vector3(0.62, 1.35, 0.2), WARM, 0.7, 1.8)
	return k


static func bench_drawer() -> Kit:
	var k := Kit.new()
	k.box(Vector3(0.54, 0.14, 0.03), Vector3(0, 0, 0.36), ORANGE.lightened(0.15))
	k.box(Vector3(0.2, 0.025, 0.035), Vector3(0, 0.02, 0.385), STEEL, Vector3.ZERO, 0.008)
	k.box(Vector3(0.5, 0.11, 0.5), Vector3(0, -0.005, 0.1), DARK.lightened(0.1), Vector3.ZERO, 0.01)
	return k


## Bits that only lie about while the bench is broken: a torn-off panel, a spring, loose wire.
static func bench_scraps() -> Kit:
	var k := Kit.new()
	k.box(Vector3(0.54, 0.02, 0.4), Vector3(0.2, 0.012, 0.75), TEAL_D, Vector3(4, 25, 3), 0.008)
	k.box(Vector3(0.3, 0.02, 0.22), Vector3(-0.5, 0.012, 0.8), ORANGE, Vector3(0, -40, 5), 0.008)
	k.cable([Vector3(0.95, 0.88, 0.42), Vector3(1.05, 0.6, 0.55), Vector3(1.0, 0.25, 0.62), Vector3(0.8, 0.02, 0.75)], 0.012, RED)
	k.cable([Vector3(0.9, 0.86, 0.4), Vector3(0.95, 0.5, 0.48), Vector3(1.1, 0.02, 0.6)], 0.012, YELLOW)
	return k


## Broken: rusty, the pegboard has slumped back against the wall, the middle drawer hangs out,
## scraps on the floor, everything dark. Fixed: clean paint, all in place, lamp and screen lit.
static func bench_state(bench: Node3D, ok: bool, animate: bool) -> void:
	if bench == null or bench.get_child_count() == 0:
		return
	var body: Node = bench.get_child(0)
	if not body.has_meta("yard_bench"):
		return
	var upper: Node3D = body.get_node_or_null("Upper") as Node3D
	var drawer: Node3D = body.get_node_or_null("Drawer") as Node3D
	var scraps: Node3D = body.get_node_or_null("Scraps") as Node3D
	var up_xf: Transform3D = Transform3D.IDENTITY if ok else Transform3D(Basis.from_euler(Vector3(-0.32, 0.04, 0.1)), Vector3(0.1, -0.42, -0.2))
	var dr_xf := Transform3D(Basis(), Vector3(-0.65, 0.54, 0.0)) if ok else Transform3D(Basis.from_euler(Vector3(0.5, 0.0, 0.22)), Vector3(-0.62, 0.42, 0.34))
	set_wear(body, 0.12 if ok else 0.72)
	set_powered(body, ok)
	if scraps:
		scraps.visible = not ok
	for pair: Array in [[upper, up_xf], [drawer, dr_xf]]:
		var n: Node3D = pair[0]
		if n == null:
			continue
		if animate and n.is_inside_tree():
			n.create_tween().tween_property(n, "transform", pair[1], 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			n.transform = pair[1]


# Yard street lamp (local: base at the origin, light under the head).
const LAMP_HEAD_Y: float = 3.62


static func street_lamp() -> Kit:
	var k := Kit.new()
	k.cyl(0.36, 0.14, Vector3(0, 0.07, 0), DARK, Vector3.ZERO, 0.03, 8)
	k.cyl(0.28, 0.24, Vector3(0, 0.26, 0), TEAL_D, Vector3.ZERO, 0.04, 8, "paint", 0.24)
	for a: int in 8:
		k.bolt(Vector3(cos(a * TAU / 8 + 0.39) * 0.3, 0.145, sin(a * TAU / 8 + 0.39) * 0.3), Vector3.UP)
	k.hazard(Vector3(0.22, 0.42, 0.22), Vector3(0, 0.6, 0))
	k.cyl(0.09, 3.0, Vector3(0, 1.98, 0), TEAL, Vector3.ZERO, 0.02, 12, "paint", 0.075)
	for y: float in [0.85, 2.4, 3.4]:
		k.cyl(0.11, 0.06, Vector3(0, y, 0), GUNMETAL, Vector3.ZERO, 0.015, 12)
	# Junction box with its status LED and a hatch.
	k.box(Vector3(0.2, 0.32, 0.14), Vector3(0, 1.35, 0.13), CREAM)
	k.box(Vector3(0.15, 0.22, 0.02), Vector3(0, 1.33, 0.205), CREAM.darkened(0.1), Vector3.ZERO, 0.006)
	k.glow_box(Vector3(0.03, 0.03, 0.02), Vector3(0.05, 1.47, 0.205), MINT)
	k.decal("power", Vector2(0.1, 0.1), Vector3(0, 1.3, 0.215))
	# Head: a chunky saucer with a warm lens ring underneath.
	k.cyl(0.13, 0.12, Vector3(0, 3.5, 0), GUNMETAL, Vector3.ZERO, 0.03, 12)
	k.cyl(0.42, 0.14, Vector3(0, LAMP_HEAD_Y, 0), CREAM, Vector3.ZERO, 0.05, 20, "paint", 0.36)
	k.cyl(0.3, 0.08, Vector3(0, LAMP_HEAD_Y + 0.11, 0), ORANGE, Vector3.ZERO, 0.03, 20, "paint", 0.18)
	k.cyl(0.05, 0.08, Vector3(0, LAMP_HEAD_Y + 0.18, 0), GUNMETAL, Vector3.ZERO, 0.015, 8)
	k.glow_cyl(0.3, 0.03, Vector3(0, LAMP_HEAD_Y - 0.075, 0), WARM, Vector3.ZERO, 20)
	return k


# Generator (local: skid on the ground, long side along X).
static func generator() -> Kit:
	var k := Kit.new()
	for z: float in [-0.34, 0.34]:
		k.box(Vector3(1.44, 0.1, 0.12), Vector3(0, 0.05, z), DARK)
		k.hazard(Vector3(0.2, 0.08, 0.125), Vector3(0.62, 0.06, z))
		k.hazard(Vector3(0.2, 0.08, 0.125), Vector3(-0.62, 0.06, z))
	k.box(Vector3(1.3, 0.06, 0.74), Vector3(0, 0.12, 0), GUNMETAL)
	# Body.
	k.box(Vector3(0.96, 0.66, 0.64), Vector3(0.05, 0.48, 0), ORANGE, Vector3.ZERO, 0.06)
	k.box(Vector3(1.0, 0.07, 0.68), Vector3(0.05, 0.83, 0), CREAM, Vector3.ZERO, 0.03)
	k.vent(0.56, 0.36, Vector3(0.12, 0.48, 0.325), DARK.lightened(0.15))
	k.vent(0.56, 0.36, Vector3(0.12, 0.48, -0.325), DARK.lightened(0.15), Vector3(0, 180, 0))
	k.bolts4(Vector3(0.05, 0.48, 0.325), Vector3(0.43, 0, 0), Vector3(0, 0.27, 0), Vector3.BACK)
	k.decal("power", Vector2(0.16, 0.16), Vector3(-0.3, 0.6, 0.33))
	k.decal("label_power", Vector2(0.5, 0.12), Vector3(0.12, 0.72, -0.35), Vector3(0, 180, 0))
	# Fuel tank on top, red, with a cap.
	k.cyl(0.17, 0.62, Vector3(0.05, 1.02, 0), RED, Vector3(0, 0, 90), 0.05, 16)
	k.cyl(0.05, 0.06, Vector3(0.2, 1.2, 0), YELLOW, Vector3.ZERO, 0.012, 10)
	for x: float in [-0.15, 0.25]:
		k.cyl(0.18, 0.03, Vector3(x, 1.02, 0), GUNMETAL, Vector3(0, 0, 90), 0.008, 16)
	# Tube roll cage.
	for z: float in [-0.36, 0.36]:
		k.pipe(Vector3(-0.58, 0.15, z), Vector3(-0.58, 1.18, z), 0.028, GUNMETAL, false)
		k.pipe(Vector3(0.66, 0.15, z), Vector3(0.66, 1.18, z), 0.028, GUNMETAL, false)
		k.pipe(Vector3(-0.58, 1.18, z), Vector3(0.66, 1.18, z), 0.028, GUNMETAL, false)
	k.pipe(Vector3(-0.58, 1.18, -0.36), Vector3(-0.58, 1.18, 0.36), 0.028, GUNMETAL, false)
	# Control panel at the -X end: dial, LEDs, a big switch.
	k.box(Vector3(0.08, 0.5, 0.56), Vector3(-0.47, 0.5, 0), DARK)
	k.cyl(0.08, 0.03, Vector3(-0.515, 0.6, 0.12), CREAM, Vector3(0, 0, 90), 0.008, 16)
	k.box(Vector3(0.01, 0.06, 0.012), Vector3(-0.535, 0.62, 0.13), RED, Vector3(30, 0, 0), 0.002)
	k.glow_box(Vector3(0.02, 0.04, 0.04), Vector3(-0.515, 0.62, -0.08), MINT)
	k.glow_box(Vector3(0.02, 0.04, 0.04), Vector3(-0.515, 0.62, -0.16), AMBER)
	k.box(Vector3(0.05, 0.12, 0.08), Vector3(-0.52, 0.38, -0.12), YELLOW)
	k.box(Vector3(0.05, 0.1, 0.1), Vector3(-0.52, 0.38, 0.12), BLUE)
	# Exhaust stack at the +X end.
	k.pipe(Vector3(0.58, 0.5, 0.16), Vector3(0.58, 1.38, 0.16), 0.05, GUNMETAL, true)
	k.cyl(0.075, 0.08, Vector3(0.58, 1.42, 0.16), DARK, Vector3.ZERO, 0.02, 10)
	# Power cable off toward the lean-to.
	k.cable([Vector3(-0.51, 0.4, 0.2), Vector3(-0.7, 0.2, 0.3), Vector3(-0.95, 0.03, 0.35), Vector3(-1.5, 0.03, 0.6)], 0.03)
	k.light(Vector3(-0.75, 0.62, -0.1), MINT, 0.25, 0.9)
	return k


# --- The trash bin (automation/depot.gd) ------------------------------------------------------------

## The bin's body for a level: {root: Node3D, size: Vector3 (collider), mouth_y, ram (Node3D or
## null), fill: [pos, scale] for the junk heap}. L1 a dented, rusty wheelie bin with its lid
## flopped open; L2 a fresh green skip; L3 ribs, rail and an amber beacon; L4 a compactor frame
## and ram; L5 a clean white smart shell with a thin cyan seam.
static func bin_body(l: int) -> Dictionary:
	if l <= 1:
		return _wheelie()
	return _skip(l)


static func _wheelie() -> Dictionary:
	var k := Kit.new()
	var col: Color = Color(0.24, 0.42, 0.28)
	var w: float = 0.86
	var d: float = 0.92
	k.box(Vector3(w * 0.9, 0.1, d * 0.9), Vector3(0, 0.1, 0), col.darkened(0.3), Vector3.ZERO, 0.03)
	k.box(Vector3(w, 0.98, d), Vector3(0, 0.62, 0), col, Vector3.ZERO, 0.07)
	for y: float in [0.34, 0.86]:
		k.box(Vector3(w + 0.04, 0.05, d + 0.04), Vector3(0, y, 0), col.darkened(0.15), Vector3.ZERO, 0.02)
	for x: float in [-0.22, 0.22]:  # moulded front ribs
		k.box(Vector3(0.07, 0.62, 0.04), Vector3(x, 0.62, d * 0.5 + 0.01), col.lightened(0.05), Vector3.ZERO, 0.02)
	k.box(Vector3(0.34, 0.26, 0.06), Vector3(0.14, 0.6, d * 0.5 - 0.01), col.darkened(0.35), Vector3(-10, 12, 8), 0.02)  # the dent
	k.box(Vector3(w + 0.1, 0.08, d + 0.1), Vector3(0, 1.14, 0), col.darkened(0.2), Vector3.ZERO, 0.03)  # rim
	k.box(Vector3(0.3, 0.12, 0.1), Vector3(0, 1.06, d * 0.5 + 0.06), col.darkened(0.2), Vector3.ZERO, 0.03)  # grip
	k.decal("label_scrap", Vector2(0.52, 0.13), Vector3(0, 0.48, d * 0.5 + 0.005))
	k.decal("num_01", Vector2(0.16, 0.16), Vector3(-0.32, 0.98, d * 0.5 + 0.005))
	# Lid flopped back over the hinge.
	k.push(ProcMesh.xf(Vector3(0, 1.16, -d * 0.5 - 0.06), Vector3(-118, 0, 4)))
	k.box(Vector3(w + 0.12, 0.06, d + 0.06), Vector3(0, 0, d * 0.5 + 0.03), col.lightened(0.04), Vector3.ZERO, 0.025)
	k.box(Vector3(w * 0.7, 0.03, d * 0.6), Vector3(0, 0.04, d * 0.5), col.darkened(0.1), Vector3.ZERO, 0.01)
	k.pop()
	for x: float in [-w * 0.42, w * 0.42]:
		k.cyl(0.13, 0.08, Vector3(x, 0.13, -d * 0.5 - 0.03), RUBBER, Vector3(0, 0, 90), 0.025, 14)
		k.cyl(0.06, 0.09, Vector3(x, 0.13, -d * 0.5 - 0.03), STEEL, Vector3(0, 0, 90), 0.012, 10)
	k.pipe(Vector3(-w * 0.45, 0.13, -d * 0.5 - 0.03), Vector3(w * 0.45, 0.13, -d * 0.5 - 0.03), 0.02, GUNMETAL, false)
	k.pipe(Vector3(-w * 0.42, 1.08, -d * 0.5 - 0.09), Vector3(w * 0.42, 1.08, -d * 0.5 - 0.09), 0.025, GUNMETAL, false)
	# Junk that missed: a crushed can and a bag at the foot.
	k.cyl(0.04, 0.06, Vector3(0.5, 0.03, 0.55), RED, Vector3(90, 30, 0), 0.01, 8)
	k.box(Vector3(0.26, 0.22, 0.24), Vector3(-0.58, 0.11, 0.42), DARK.lightened(0.05), Vector3(0, 20, 8), 0.08)
	var root := Node3D.new()
	root.name = "Wheelie"
	root.rotation = Vector3(0.0, 0.18, deg_to_rad(-3.0))  # a little crooked
	root.add_child(k.mi(0.72, "Body"))
	return {"root": root, "size": Vector3(w + 0.1, 1.25, d + 0.1), "mouth_y": 1.43, "ram": null,
		"fill": [Vector3(0, 1.12, 0), Vector3(0.4, 0.3, 0.42)]}


static func _skip(l: int) -> Dictionary:
	var smart: bool = l >= 5
	var body_col: Color = Color(0.92, 0.93, 0.92) if smart else Color(0.2, 0.5, 0.34)
	var trim: Color = TEAL if smart else YELLOW
	var k := Kit.new()
	var w: float = 2.6
	var d: float = 1.6
	var h: float = 1.25
	for z: float in [-0.5, 0.5]:  # skids
		k.box(Vector3(w * 0.84, 0.1, 0.16), Vector3(0, 0.05, z), DARK)
	k.box(Vector3(w * 0.8, 0.1, d - 0.04), Vector3(0, 0.13, 0), body_col.darkened(0.25))
	# Stepped trapezoid front and back walls, sloped ends.
	for i: int in 3:
		var bw: float = w * (0.86 + 0.07 * i)
		var y: float = 0.15 + h / 3.0 * (i + 0.5)
		for s: float in [-1.0, 1.0]:
			k.box(Vector3(bw, h / 3.0 + 0.02, 0.08), Vector3(0, y, s * d * 0.5), body_col, Vector3.ZERO, 0.025)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(0.08, h * 1.06, d), Vector3(s * w * 0.45, h * 0.5 + 0.12, 0), body_col.darkened(0.08), Vector3(0, 0, -s * 12.0), 0.03)
		k.hazard(Vector3(0.1, 0.2, d + 0.02), Vector3(s * (w * 0.45 + 0.13), h * 0.98, 0), Vector3(0, 0, -s * 12.0), trim)
		for z: float in [-0.5, 0.5]:  # lifting lugs
			k.cyl(0.08, 0.1, Vector3(s * (w * 0.5 + 0.02), h * 0.7, z), GUNMETAL, Vector3(0, 0, 90), 0.02, 10)
			k.cyl(0.035, 0.18, Vector3(s * (w * 0.5 + 0.04), h * 0.7, z), STEEL, Vector3(0, 0, 90), 0.008, 8)
	var rib_sides: Array = [1.0, -1.0] if l >= 3 else [1.0]
	for s: float in rib_sides:
		for x: float in [-0.9, 0.0, 0.9]:
			k.box(Vector3(0.1, h, 0.08), Vector3(x, h * 0.5 + 0.15, s * (d * 0.5 + 0.05)), body_col.darkened(0.12), Vector3.ZERO, 0.025)
	for s: float in [-1.0, 1.0]:
		k.box(Vector3(w + 0.1, 0.1, 0.14), Vector3(0, h + 0.17, s * (d * 0.5 + 0.03)), trim if l >= 3 else body_col.darkened(0.18), Vector3.ZERO, 0.03)
	for x: float in [-1.15, -0.45, 0.45, 1.15]:
		k.bolt(Vector3(x, h + 0.17, d * 0.5 + 0.1), Vector3.BACK)
	k.decal("label_scrap", Vector2(0.7, 0.18), Vector3(-0.45, h * 0.66, d * 0.5 + 0.045))
	k.decal("warn", Vector2(0.26, 0.26), Vector3(0.45, h * 0.66, d * 0.5 + 0.045))
	k.decal("num_0%d" % mini(l, 6), Vector2(0.22, 0.22), Vector3(-0.45, h * 0.36, d * 0.5 + 0.045))
	var top: float = h
	if l == 3 or l == 4:
		k.cyl(0.09, 0.08, Vector3(w * 0.5 - 0.15, h + 0.26, d * 0.5 - 0.1), DARK, Vector3.ZERO, 0.02, 12)
		k.glow_cyl(0.07, 0.12, Vector3(w * 0.5 - 0.15, h + 0.36, d * 0.5 - 0.1), AMBER, Vector3.ZERO, 12)
		k.cyl(0.075, 0.03, Vector3(w * 0.5 - 0.15, h + 0.435, d * 0.5 - 0.1), DARK, Vector3.ZERO, 0.01, 12)
	var ram_node: Node3D = null
	if l >= 4:
		var col_c: Color = CREAM if smart else TEAL_D
		for s: float in [-1.0, 1.0]:
			var x: float = s * (w * 0.5 + 0.12)
			k.box(Vector3(0.36, 0.08, 0.36), Vector3(x, 0.04, -0.1), GUNMETAL)
			k.box(Vector3(0.17, 2.5, 0.22), Vector3(x, 1.25, -0.1), col_c)
			k.hazard(Vector3(0.18, 0.5, 0.23), Vector3(x, 0.45, -0.1), Vector3.ZERO, trim)
			k.bolts4(Vector3(x, 0.08, -0.1), Vector3(0.13, 0, 0), Vector3(0, 0, 0.13), Vector3.UP)
		k.box(Vector3(w + 0.5, 0.24, 0.3), Vector3(0, 2.5, -0.1), col_c)
		k.box(Vector3(w + 0.3, 0.06, 0.32), Vector3(0, 2.62, -0.1), trim)
		k.cyl(0.12, 0.5, Vector3(0, 2.15, -0.1), GUNMETAL, Vector3.ZERO, 0.03, 14)
		k.pipe(Vector3(0.16, 2.35, -0.1), Vector3(0.16, 2.0, -0.1), 0.02, RUBBER, false)
		var rk := Kit.new()
		rk.box(Vector3(w * 0.7, 0.12, d * 0.6), Vector3.ZERO, Color(0.85, 0.87, 0.88) if smart else YELLOW, Vector3.ZERO, 0.035)
		rk.hazard(Vector3(w * 0.7 + 0.01, 0.05, 0.05), Vector3(0, 0, d * 0.3), Vector3.ZERO, trim)
		rk.cyl(0.05, 0.8, Vector3(0, 0.42, 0), STEEL, Vector3.ZERO, 0.01, 12)
		rk.bolts4(Vector3(0, 0.06, 0), Vector3(w * 0.3, 0, 0), Vector3(0, 0, d * 0.24), Vector3.UP)
		ram_node = rk.mi(0.1 if smart else 0.3, "Ram")
		ram_node.position = Vector3(0, 1.95, -0.1)
		top = 2.6
	if smart:
		k.glow_box(Vector3(w + 0.02, 0.03, 0.02), Vector3(0, h - 0.14, d * 0.5 + 0.1), CYAN)
		k.box(Vector3(0.44, 0.3, 0.06), Vector3(0.45, h * 0.32, d * 0.5 + 0.06), DARK)
		k.glow_box(Vector3(0.36, 0.22, 0.02), Vector3(0.45, h * 0.32, d * 0.5 + 0.095), CYAN)
		k.cyl(0.1, 0.08, Vector3(0, 2.7, -0.1), CREAM, Vector3.ZERO, 0.03, 14)
		k.glow_cyl(0.06, 0.04, Vector3(0, 2.76, -0.1), CYAN, Vector3.ZERO, 12)
	var root := Node3D.new()
	root.name = "Skip"
	var body: MeshInstance3D = k.mi(0.05 if smart else (0.32 if l == 2 else 0.2), "Body")
	root.add_child(body)
	if ram_node:
		root.add_child(ram_node)
	set_powered(root, true)
	return {"root": root, "size": Vector3(w, top + 0.2 if l >= 4 else h + 0.2, d), "mouth_y": h + 0.4, "ram": ram_node,
		"fill": [Vector3(0, h * 0.55, 0), Vector3(1.15, 0.5, 0.7)]}


## The weigh plate (radius = half its width): tread panels, a drain grate, hazard border, bumpers.
## Stays under 10 cm so bales and robots roll over it.
static func depot_pad(radius: float) -> MeshInstance3D:
	var k := Kit.new()
	var s: float = radius * 1.9
	k.box(Vector3(s, 0.07, s), Vector3(0, 0.035, 0), Color(0.36, 0.38, 0.39), Vector3.ZERO, 0.03)
	var q: float = s * 0.5 - 0.22
	for ix: float in [-1.0, 1.0]:
		for iz: float in [-1.0, 1.0]:
			var c := Vector3(ix * q * 0.5 + ix * 0.04, 0.075, iz * q * 0.5 + iz * 0.04)
			k.box(Vector3(q - 0.06, 0.02, q - 0.06), c, Color(0.5, 0.53, 0.55, 0.65), Vector3.ZERO, 0.008)
			for t: int in 5:  # tread bars
				k.box(Vector3(q - 0.2, 0.016, 0.05), c + Vector3(0, 0.014, -q * 0.36 + t * q * 0.18), Color(0.62, 0.64, 0.66, 0.5), Vector3(0, 45.0 * ix * iz, 0), 0.008)
			k.bolts4(c + Vector3(0, 0.01, 0), Vector3(q * 0.5 - 0.07, 0, 0), Vector3(0, 0, q * 0.5 - 0.07), Vector3.UP, STEEL, 0.018)
	k.box(Vector3(0.5, 0.02, 0.5), Vector3(0, 0.075, 0), DARK, Vector3.ZERO, 0.008)  # drain grate
	for t: int in 5:
		k.box(Vector3(0.42, 0.02, 0.03), Vector3(0, 0.085, -0.16 + t * 0.08), GUNMETAL, Vector3.ZERO, 0.005)
	for r: int in 4:  # hazard border
		k.push(Transform3D(Basis(Vector3.UP, r * PI * 0.5), Vector3.ZERO))
		k.hazard(Vector3(s - 0.3, 0.025, 0.14), Vector3(0, 0.075, s * 0.5 - 0.1))
		k.box(Vector3(0.24, 0.09, 0.24), Vector3(s * 0.5 - 0.1, 0.06, s * 0.5 - 0.1), YELLOW, Vector3.ZERO, 0.03)  # corner bumper
		k.pop()
	k.decal("chevrons", Vector2(1.0, 0.32), Vector3(0, 0.09, -s * 0.5 + 0.38), Vector3(-90, 0, 0))
	k.decal("arrow", Vector2(0.5, 0.5), Vector3(0, 0.09, s * 0.5 - 0.5), Vector3(-90, 180, 0))
	var m: MeshInstance3D = k.mi(0.35, "Plate")
	return m


## The scale post beside the plate: a teal column with a cream dial cabinet and an amber lamp
## (lit from bin level 2: the dented bin is just a bin). Origin at the post's foot.
const SCALE_DIAL_Y: float = 1.45


static func depot_scale() -> MeshInstance3D:
	var k := Kit.new()
	k.box(Vector3(0.34, 0.06, 0.34), Vector3(0, 0.03, 0), GUNMETAL)
	k.bolts4(Vector3(0, 0.06, 0), Vector3(0.12, 0, 0), Vector3(0, 0, 0.12), Vector3.UP)
	k.box(Vector3(0.14, 1.24, 0.14), Vector3(0, 0.64, 0), TEAL)
	k.hazard(Vector3(0.15, 0.3, 0.15), Vector3(0, 0.3, 0))
	k.box(Vector3(0.54, 0.54, 0.18), Vector3(0, SCALE_DIAL_Y, 0), CREAM, Vector3.ZERO, 0.05)
	k.box(Vector3(0.58, 0.07, 0.2), Vector3(0, SCALE_DIAL_Y - 0.28, 0), ORANGE, Vector3.ZERO, 0.025)
	k.cyl(0.21, 0.04, Vector3(0, SCALE_DIAL_Y, 0.09), ORANGE, Vector3(90, 0, 0), 0.012, 24)
	k.cyl(0.18, 0.03, Vector3(0, SCALE_DIAL_Y, 0.1), Color(0.97, 0.96, 0.92), Vector3(90, 0, 0), 0.006, 24)
	for t: int in 9:
		var a: float = lerpf(-2.2, 2.2, t / 8.0)
		k.box(Vector3(0.012, 0.035, 0.01), Vector3(sin(a) * 0.145, SCALE_DIAL_Y + cos(a) * 0.145, 0.118), DARK, Vector3(0, 0, -rad_to_deg(a)), 0.002)
	k.cyl(0.02, 0.02, Vector3(0, SCALE_DIAL_Y, 0.125), DARK, Vector3(90, 0, 0), 0.005, 8)
	k.cyl(0.08, 0.06, Vector3(0, SCALE_DIAL_Y + 0.3, 0), DARK, Vector3.ZERO, 0.015, 12)
	k.glow_cyl(0.06, 0.08, Vector3(0, SCALE_DIAL_Y + 0.37, 0), AMBER, Vector3.ZERO, 12)
	k.light(Vector3(0, SCALE_DIAL_Y + 0.42, 0.1), AMBER, 0.35, 1.6)
	k.cable([Vector3(0.0, 1.2, -0.08), Vector3(0.0, 0.6, -0.1), Vector3(-0.05, 0.03, -0.25), Vector3(-0.4, 0.03, -0.5)], 0.02)
	return k.mi(0.3, "ScalePost")


# --- Yard ground ------------------------------------------------------------------------------------

## The yard is never a flat slab (owner): on top of the painted yard slab (planet/street_dressing.gd)
## this adds a cracked concrete footing under the lean-to and bench, broken slab plates, a kerb
## round the edge (gap at the walkway), drain covers, grit drifted against everything, and dry
## grass tufts in the corners and cracks. Visual only, at most ~5 cm proud (Lumi and bales pass).
## `half` = the yard's half-size; `feet` = world points of things that collect grit round their base.
static func dress_ground(world: Node3D, shack: Node3D, half: float = 8.5, feet: Array = []) -> Node3D:
	var root := Node3D.new()
	root.name = "YardGround"
	world.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7151
	var k := Kit.new()
	var conc := Color(0.66, 0.64, 0.6)
	# Footing under the lean-to/bench (in the shack's frame), split by a crack, with a kerb lip.
	if shack:
		k.push(world.global_transform.affine_inverse() * shack.global_transform)
		k.box(Vector3(2.0, 0.05, 2.9), Vector3(-0.92, 0.012, -0.05), conc, Vector3(0, 0, 0.3), 0.015, "concrete")
		k.box(Vector3(1.78, 0.05, 2.9), Vector3(1.0, 0.012, -0.05), conc.darkened(0.06), Vector3(0, 0, -0.4), 0.015, "concrete")
		k.box(Vector3(3.9, 0.08, 0.16), Vector3(0, 0.03, -1.42), conc.darkened(0.12), Vector3.ZERO, 0.03, "concrete")
		feet.append(shack.global_position)
		k.pop()
	# Broken slab plates in the open corners (each two pieces with a crack between).
	for p: Array in [[Vector2(-7.2, -7.4), 1.6], [Vector2(6.3, -6.6), 1.8], [Vector2(-6.9, -1.4), 1.6], [Vector2(3.7, 6.7), 1.7],
			[Vector2(-3.3, 6.8), 1.9], [Vector2(6.8, 6.6), 1.5], [Vector2(7.0, -2.6), 1.3]]:
		var c: Vector2 = p[0]
		var s: float = p[1]
		var yaw: float = rng.randf_range(-0.25, 0.25)
		var split: float = rng.randf_range(0.35, 0.65)
		var tint: Color = conc.darkened(rng.randf_range(-0.05, 0.15))
		k.push(Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, 0.0, c.y)))
		var w1: float = s * split - 0.03
		var w2: float = s * (1.0 - split) - 0.03
		k.box(Vector3(w1, 0.045, s), Vector3(-s * 0.5 + w1 * 0.5, 0.016, 0), tint, Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2)), 0.015, "concrete")
		k.box(Vector3(w2, 0.045, s * rng.randf_range(0.7, 1.0)), Vector3(s * 0.5 - w2 * 0.5, 0.016, 0), tint.darkened(0.05), Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-4, 4), rng.randf_range(-1.5, 1.5)), 0.015, "concrete")
		k.pop()
		feet.append(Vector3(c.x, 0, c.y))
	# Kerb stones along the edge; the front (walkway, +z) leaves a gap in the middle.
	for side: int in 4:
		var n: int = int(half * 2.0 / 1.0)
		for i: int in n:
			var t: float = -half + 0.5 + i * 1.0
			if side == 2 and absf(t) < 1.8:
				continue
			if rng.randf() < 0.08:
				continue  # a missing stone
			var pos: Vector3
			var rot: float
			match side:
				0:
					pos = Vector3(t, 0.05, -half + 0.08)
					rot = 0.0
				1:
					pos = Vector3(half - 0.08, 0.05, t)
					rot = 90.0
				2:
					pos = Vector3(t, 0.05, half - 0.08)
					rot = 0.0
				_:
					pos = Vector3(-half + 0.08, 0.05, t)
					rot = 90.0
			var tilt := Vector3(rng.randf_range(-2.0, 2.0), rot + rng.randf_range(-2.5, 2.5), rng.randf_range(-2.0, 2.0))
			if i % 2 == 0 and side == 2:
				k.hazard(Vector3(0.96, 0.12, 0.2), pos, tilt)
			else:
				k.box(Vector3(0.96, 0.12, 0.2), pos, conc.lightened(0.05).darkened(rng.randf_range(0.0, 0.15)), tilt, 0.03, "concrete")
	# Drain covers and a manhole.
	for d: Array in [[Vector3(3.9, 0.02, 3.4), 0.32], [Vector3(-6.2, 0.02, -3.9), 0.42], [Vector3(-2.0, 0.02, -5.6), 0.28]]:
		var at: Vector3 = d[0]
		var r: float = d[1]
		k.cyl(r + 0.05, 0.035, at, GUNMETAL, Vector3.ZERO, 0.01, 18)
		k.cyl(r, 0.04, at + Vector3(0, 0.006, 0), Color(0.36, 0.38, 0.4, 0.0), Vector3.ZERO, 0.008, 18)
		for i: int in 4:
			k.box(Vector3(r * 1.6, 0.012, 0.03), at + Vector3(0, 0.028, -r * 0.45 + i * r * 0.3), DARK, Vector3.ZERO, 0.004)
		for a: int in 6:
			k.bolt(at + Vector3(cos(a * TAU / 6) * (r - 0.03), 0.026, sin(a * TAU / 6) * (r - 0.03)), Vector3.UP, STEEL, 0.012)
	var ground: MeshInstance3D = k.mi(0.3, "Plates")
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	root.add_child(_grit(rng, half, feet))
	root.add_child(_tufts(rng, half, feet))
	return root


## Pebbles and grit: drifted along the kerb and round the feet of things, a light sprinkle elsewhere.
static func _grit(rng: RandomNumberGenerator, half: float, feet: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bbox(Vector3(1, 0.6, 0.8), 0.25)
	var n: int = 900
	mm.instance_count = n
	for i: int in n:
		var p: Vector3 = _scatter_point(rng, half, feet, 0.55)
		var s: float = rng.randf_range(0.03, 0.09) * (1.8 if rng.randf() < 0.1 else 1.0)
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3.ONE * s)
		mm.set_instance_transform(i, Transform3D(b, p + Vector3(0, s * 0.2, 0)))
		var g: float = rng.randf_range(0.32, 0.62)
		mm.set_instance_color(i, Color(g * rng.randf_range(1.0, 1.15), g, g * rng.randf_range(0.85, 1.0)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Grit"
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.92
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Dry grass tufts: in corners, along the kerb and against the footings.
static func _tufts(rng: RandomNumberGenerator, half: float, feet: Array) -> MultiMeshInstance3D:
	var parts: Array = []
	for b: int in 9:
		var a: float = b * TAU / 9.0 + rng.randf_range(-0.2, 0.2)
		var h: float = rng.randf_range(0.2, 0.42)
		var lean: float = rng.randf_range(12.0, 32.0)
		var col: Color = Color(0.45, 0.58, 0.24).lerp(Color(0.72, 0.66, 0.36), rng.randf())
		parts.append(ProcMesh.part(bbox(Vector3(0.035, h, 0.01), 0.004),
			Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(lean)), Vector3(cos(a), 0, sin(a)) * 0.03 + Vector3(0, h * 0.45, 0)), col))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = ProcMesh.merge(parts)
	var n: int = 220
	mm.instance_count = n
	var last := Vector3.ZERO
	for i: int in n:
		var p: Vector3 = _scatter_point(rng, half, feet, 0.6) if i % 3 == 0 else last + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
		last = p
		var s: float = rng.randf_range(0.6, 1.4)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), p))
		var g: float = rng.randf_range(0.75, 1.1)
		mm.set_instance_color(i, Color(g, g, g))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Tufts"
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


## A point that prefers the yard's edge band and the feet of things (edge_bias = share at edges).
static func _scatter_point(rng: RandomNumberGenerator, half: float, feet: Array, edge_bias: float) -> Vector3:
	var r: float = rng.randf()
	if r < edge_bias:
		var t: float = rng.randf_range(-half, half)
		var inset: float = 0.15 + absf(rng.randfn(0.0, 0.35))
		match rng.randi() % 4:
			0:
				return Vector3(t, 0.012, -half + inset)
			1:
				return Vector3(half - inset, 0.012, t)
			2:
				return Vector3(t, 0.012, half - inset)
			_:
				return Vector3(-half + inset, 0.012, t)
	if r < edge_bias + 0.3 and not feet.is_empty():
		var f: Vector3 = feet[rng.randi() % feet.size()]
		var a: float = rng.randf() * TAU
		var d: float = rng.randf_range(0.6, 1.8)
		return Vector3(f.x + cos(a) * d, 0.012, f.z + sin(a) * d)
	return Vector3(rng.randf_range(-half, half), 0.012, rng.randf_range(-half, half))


# --- The Locker (systems/camp/locker_cabinet.gd; ui6 owns the gameplay) ------------------------------

## Local: front +Z, origin on the ground. About 1.2 x 2.3 x 0.7 m.
static func locker() -> Kit:
	var k := Kit.new()
	k.box(Vector3(1.3, 0.14, 0.74), Vector3(0, 0.07, 0), DARK)  # plinth
	k.hazard(Vector3(1.31, 0.06, 0.745), Vector3(0, 0.09, 0))
	k.box(Vector3(1.2, 2.0, 0.66), Vector3(0, 1.14, -0.02), TEAL, Vector3.ZERO, 0.06)
	k.box(Vector3(1.28, 0.12, 0.72), Vector3(0, 2.18, -0.02), TEAL_D, Vector3.ZERO, 0.04)  # crown
	for s: float in [-1.0, 1.0]:
		var x: float = s * 0.29
		k.box(Vector3(0.54, 1.82, 0.05), Vector3(x, 1.12, 0.32), CREAM, Vector3.ZERO, 0.03)
		k.box(Vector3(0.44, 0.6, 0.02), Vector3(x, 0.62, 0.35), CREAM.darkened(0.06), Vector3.ZERO, 0.01)  # lower inset
		k.vent(0.36, 0.26, Vector3(x, 1.72, 0.345), CREAM.darkened(0.12), Vector3.ZERO, 4)
		k.box(Vector3(0.04, 0.26, 0.05), Vector3(-s * 0.04 + x - s * 0.18, 1.12, 0.37), STEEL, Vector3.ZERO, 0.015)  # handle
		k.box(Vector3(0.16, 0.06, 0.012), Vector3(x, 1.38, 0.352), ORANGE, Vector3.ZERO, 0.005)  # name tag
		for y: float in [0.4, 1.85]:  # hinges
			k.box(Vector3(0.04, 0.1, 0.04), Vector3(s * 0.57, y, 0.33), GUNMETAL, Vector3.ZERO, 0.01)
		k.bolts4(Vector3(x, 1.12, 0.35), Vector3(0.23, 0, 0), Vector3(0, 0.86, 0), Vector3.BACK, STEEL, 0.014)
	k.glow_box(Vector3(0.018, 1.7, 0.018), Vector3(0, 1.12, 0.36), CYAN)  # status seam
	k.box(Vector3(0.3, 0.14, 0.06), Vector3(0, 2.0, 0.33), DARK, Vector3.ZERO, 0.02)  # little screen
	k.glow_box(Vector3(0.24, 0.08, 0.02), Vector3(0, 2.0, 0.36), MINT)
	k.decal("logo", Vector2(0.22, 0.22), Vector3(0.5, 2.18, 0.33))
	# Helmet on top, coat hooks with a scarf on the side: someone's personal corner.
	k.cyl(0.2, 0.18, Vector3(0.25, 2.33, -0.05), ORANGE, Vector3(0, 0, 0), 0.08, 16)
	k.box(Vector3(0.34, 0.03, 0.2), Vector3(0.25, 2.26, 0.12), ORANGE.darkened(0.15), Vector3(-8, 0, 0), 0.01)
	k.glow_cyl(0.035, 0.03, Vector3(0.25, 2.38, 0.14), WARM, Vector3(70, 0, 0), 10)
	k.box(Vector3(0.05, 0.05, 0.5), Vector3(-0.62, 1.6, -0.02), GUNMETAL, Vector3.ZERO, 0.012)
	for z: float in [-0.15, 0.15]:
		k.cyl(0.015, 0.1, Vector3(-0.67, 1.6, z), STEEL, Vector3(0, 0, 90), 0.004, 6)
	k.box(Vector3(0.03, 0.6, 0.14), Vector3(-0.68, 1.3, -0.15), RED, Vector3(0, 0, 4), 0.012)
	k.hazard(Vector3(0.03, 0.08, 0.14), Vector3(-0.685, 1.06, -0.15), Vector3(0, 0, 4), CREAM)
	k.cable([Vector3(0.5, 2.24, -0.3), Vector3(0.62, 1.4, -0.36), Vector3(0.66, 0.2, -0.36), Vector3(0.9, 0.03, -0.3)], 0.02)
	k.light(Vector3(0, 1.4, 0.7), CYAN, 0.25, 1.4)
	return k
