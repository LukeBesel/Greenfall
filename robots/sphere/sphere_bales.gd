class_name SphereBales
extends Node3D
## [orbC] The crew's bales in 3D on the globe. A bale is a record in SphereCrew.bales (cell, dir,
## value) wherever it is; within NEAR_M of Lumi it is also a real JunkCube (the flat game's bale:
## physics, radial gravity, Lumi can carry it, the Depot takes it), parked under this node. Haul
## Bugs fetch it (the cube goes) and carry their load on their back (a strapped bale mesh).
## When Lumi picks a crew bale up (or the Depot claims it), it is his: the record is dropped and
## the cube lives on as a normal loose cube. Records only, far away, so hundreds stay cheap.

const NEAR_M: float = 110.0
const FAR_M: float = 140.0  # hysteresis: a cube goes back to a record past this
const MAX_CUBES: int = 60

var crew: SphereCrew
var _cubes: Dictionary = {}  # bale id -> JunkCube
var _t: float = 0.0
static var _cargo_mesh: ArrayMesh
static var _strap: ArrayMesh


## Bale colours from the dominant junk type (data/junk.json cube_color), like the flat bales.
static func bale_info(units: float) -> Dictionary:
	var ids: Array = Economy.junk_ids
	var dom: String = str(ids[randi() % ids.size()]) if not ids.is_empty() else "metal"
	var base := Color.html(str(Economy.junk_types.get(dom, {}).get("cube_color", "#8a8378")))
	return {"fill": clampf(units / 12.0, 0.4, 1.0), "dominant": dom,
		"colors": [base, base.darkened(0.25), Color(0.5, 0.47, 0.43)]}


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.3:
		return
	sync()
	_t = 0.0


## Spawns cubes for near bales, retires far ones, and hands over the ones Lumi or a Depot took.
func sync() -> void:
	if crew == null:
		return
	var fd: Vector3 = crew.surface.up_at(crew.focus.global_position) if crew.focus != null and is_instance_valid(crew.focus) else Vector3.ZERO
	var live: Dictionary = {}
	for b: Dictionary in crew.bales:
		live[int(b["id"])] = b
	# Cubes first: taken by Lumi / a Depot, moved, freed, or too far.
	for id: int in _cubes.keys():
		var c: JunkCube = _cubes[id]
		var b: Dictionary = live.get(id, {})
		if not is_instance_valid(c):
			_cubes.erase(id)
			if not b.is_empty():
				crew.bales.erase(b)  # gone with whoever took it
			continue
		if c.carried or c.claimed or c.get_parent() != self:
			_cubes.erase(id)  # Lumi's (or the Depot's) now
			if not b.is_empty():
				crew.bales.erase(b)
			continue
		if b.is_empty():  # a hauler took it
			_cubes.erase(id)
			c.queue_free()
			continue
		var d: Vector3 = crew.surface.up_at(c.global_position)
		if fd != Vector3.ZERO and fd.angle_to(d) * crew.surface.radius > FAR_M:
			b["dir"] = d
			b["cell"] = crew.grid.cell_at(d)
			_cubes.erase(id)
			c.queue_free()
		elif (b["dir"] as Vector3).angle_to(d) * crew.surface.radius > 1.0:
			b["dir"] = d  # nudged (Lumi bumped it): the record follows
			b["cell"] = crew.grid.cell_at(d)
	if fd == Vector3.ZERO:
		return
	for b: Dictionary in crew.bales:
		var id: int = int(b["id"])
		if _cubes.has(id) or _cubes.size() >= MAX_CUBES or str(b.get("claimed", "")) != "":
			continue
		var d: Vector3 = b.get("dir", crew.grid.centers[int(b["cell"])])
		if fd.angle_to(d) * crew.surface.radius > NEAR_M:
			continue
		_cubes[id] = _spawn_cube(b, d)


func _spawn_cube(b: Dictionary, d: Vector3) -> JunkCube:
	var c := JunkCube.create(BigNum.from_float(float(b["value"])), b.get("info", bale_info(float(b.get("units", 10.0)))))
	add_child(c)
	var up: Vector3 = d
	var p: Vector3 = crew.surface.ground(d) + up * (c.size * 0.5 + 0.04)
	c.global_transform = Transform3D(SphereMath.basis_from_up_fwd(up, SphereMath.any_perpendicular(up)), p)
	return c


## A hauler arrived for bale `b`: the cube (if any) goes.
func take(id: int) -> void:
	var c: JunkCube = _cubes.get(id)
	_cubes.erase(id)
	if c != null and is_instance_valid(c) and not c.carried:
		c.queue_free()


func cube_of(id: int) -> JunkCube:
	var c: JunkCube = _cubes.get(id)
	return c if c != null and is_instance_valid(c) else null


## The load on a Haul Bug's back (n bales, stacked), or none.
static func dress_cargo(bot: SphereBot, n: int) -> void:
	if bot == null:
		return
	var holder: Node3D = bot.get_node_or_null("Cargo") as Node3D
	if n <= 0:
		if holder:
			holder.queue_free()
		return
	if holder == null:
		holder = Node3D.new()
		holder.name = "Cargo"
		bot.add_child(holder)
		var rv: RobotVisual = bot.visual as RobotVisual
		holder.position = (rv.hopper_point if rv else Vector3(0, 0.6, 0)) + Vector3(0, 0.12, 0)
	if holder.get_child_count() == n:
		return
	for ch: Node in holder.get_children():
		ch.queue_free()
	if _cargo_mesh == null:
		_cargo_mesh = JunkCube.bale_mesh()
		_strap = JunkCube.strap_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://art/shaders/cube.gdshader")
	var info: Dictionary = bale_info(10.0)
	mat.set_shader_parameter("color_a", info["colors"][0])
	mat.set_shader_parameter("color_b", info["colors"][1])
	mat.set_shader_parameter("color_c", info["colors"][2])
	mat.set_shader_parameter("mix_b", 0.35)
	mat.set_shader_parameter("mix_c", 0.18)
	mat.set_shader_parameter("detail_nrm", AssetLib.tex("rubble", "nor_gl"))
	for k: int in n:
		var mi := MeshInstance3D.new()
		mi.mesh = _cargo_mesh
		mi.material_override = mat
		mi.scale = Vector3.ONE * 0.38
		mi.position = Vector3(0, 0.2 + k * 0.38, 0)
		mi.rotation.y = 0.2 * k
		holder.add_child(mi)
		var st := MeshInstance3D.new()
		st.mesh = _strap
		st.material_override = Mats.metal("dark_steel")
		st.scale = mi.scale
		st.position = mi.position
		st.rotation = mi.rotation
		holder.add_child(st)
