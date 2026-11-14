class_name SphereBales
extends Node3D
## [orbC] The crew's bales in 3D on the globe. A bale is a record in SphereCrew.bales (cell, dir,
## value) wherever it is; within NEAR_M of Lumi it is also a real JunkCube (the flat game's bale:
## physics, radial gravity, Lumi can carry it, the Depot takes it), parked under this node. Haul
## Bugs fetch it (the cube goes) and carry their load on their back (a strapped bale mesh).
## When Lumi picks a crew bale up (or the Depot claims it), it is his: the record is dropped and
## the cube lives on as a normal loose cube. Records only, far away, so hundreds stay cheap.
## [v4bots] Owner item 52: bales Lumi makes (loose cubes resting on the ground near him) join the
## crew's bales once a Haul Bug works here, so haulers fetch his bales too (not ones on a feeder
## pad, a scale's pad, an outpost's pad or right by the Depot: he is cashing those himself).

const NEAR_M: float = 110.0
const FAR_M: float = 140.0  # hysteresis: a cube goes back to a record past this
const MAX_CUBES: int = 60
const ADOPT_REST_S: float = 3.0  # [v4bots] a loose bale lies still this long before haulers take it
const ADOPT_DEPOT_M: float = 6.0

var crew: SphereCrew
var _cubes: Dictionary = {}  # bale id -> JunkCube
var _t: float = 0.0
var _rest: Dictionary = {}  # [v4bots] loose cube instance id -> seconds lying still
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
	adopt_loose(_t)
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
	var c := JunkCube.create(BigNum.from_float(float(b.get("raw", b["value"]))),  # [v4bots] raw: an adopted bale of Lumi's
			b.get("info", bale_info(float(b.get("units", 10.0)))))
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


## [v4bots] Lumi's resting loose bales become crew bales (records + cubes under this node) while
## a Haul Bug is on the crew. dt: seconds since the last call (time lying still).
func adopt_loose(dt: float) -> int:
	if crew == null or crew.focus == null or not is_instance_valid(crew.focus) or not _has_hauler():
		_rest.clear()
		return 0
	var root: Node = crew.world.get("_cubes_root") as Node if crew.world != null else null
	if root == null:
		return 0
	var fd: Vector3 = crew.surface.up_at(crew.focus.global_position)
	var depot: Node3D = crew.world.get("depot") as Node3D
	var seen: Dictionary = {}
	var n: int = 0
	for ch: Node in root.get_children():
		var c: JunkCube = ch as JunkCube
		if c == null or c.carried or c.claimed or c.is_queued_for_deletion() or bool(c.get_meta("reserved", false)):
			continue
		var key: int = c.get_instance_id()
		if c.linear_velocity.length() > 0.25:
			continue  # still rolling: the clock starts again
		seen[key] = true
		_rest[key] = float(_rest.get(key, 0.0)) + dt
		if float(_rest[key]) < ADOPT_REST_S or _cubes.size() >= MAX_CUBES:
			continue
		var d: Vector3 = crew.surface.up_at(c.global_position)
		if fd.angle_to(d) * crew.surface.radius > NEAR_M or not keep_for_haulers(c, depot):
			continue
		adopt(c)
		seen.erase(key)
		n += 1
	for k: int in _rest.keys():
		if not seen.has(k):
			_rest.erase(k)
	return n


## False for a bale Lumi is cashing or feeding himself (a pad, or right by the Depot).
func keep_for_haulers(c: JunkCube, depot: Node3D = null) -> bool:
	if Stations.on_feeder(c) or Outposts.on_pad(crew.world, c.global_position):
		return false
	if depot != null and is_instance_valid(depot):
		if depot.has_method("pad_contains") and bool(depot.call("pad_contains", c.global_position)):
			return false
		if depot.global_position.distance_to(c.global_position) < ADOPT_DEPOT_M:
			return false
	return true


## One loose cube into the crew's bales: a record, and the cube parked here like a crew bale.
## The record pays what the Depot would (crew cash is raw value), so a hauled bale of Lumi's is
## worth the same as one he carries in; the cube keeps its own value if he picks it up again.
func adopt(c: JunkCube) -> int:
	crew._bale_seq += 1
	var id: int = crew._bale_seq
	var d: Vector3 = crew.surface.up_at(c.global_position)
	var depot: Node = crew.world.get("depot") as Node if crew.world != null else null
	var mult: float = float(depot.call("sell_factor")) if depot != null and depot.has_method("sell_factor") else 1.0
	if depot != null and depot.has_method("sell_factor"):
		mult /= maxf(Hub.trade_mult(), 0.0001)  # [v6pace] SphereCrew.cash() applies the far-hub multiplier; sell_factor has it too (it was paid twice: x150 became x22,500)
	crew.bales.append({"id": id, "cell": crew.grid.cell_at(d), "dir": d, "value": c.value.to_float() * mult,
		"units": float(c.info.get("volume", float(c.info.get("fill", 1.0)) * 12.0)), "claimed": "", "info": c.info, "raw": c.value.to_float()})
	c.reparent(self, true)
	_cubes[id] = c
	_rest.erase(c.get_instance_id())
	return id


func _has_hauler() -> bool:
	for u: Dictionary in crew.units:
		if str(u.get("role", "")) == "haul":
			return true
	return false
