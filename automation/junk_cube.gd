class_name JunkCube
extends RigidBody3D
## A compacted junk cube. Physical, stackable, wobbly. Its value is cashed at a Depot.

static var _mesh: ArrayMesh
static var _strap_mesh: ArrayMesh

var value: BigNum = BigNum.zero()
var info: Dictionary = {}
var size: float = 0.55
var carried: bool = false
var claimed: bool = false  # being sucked into a depot
## [orbit] Radius of the round planet the cubes live on (0 = a flat district). Gravity there is
## radial (a point-gravity Area3D set up by the planet scene).
static var planet_radius: float = 0.0

var _visual: MeshInstance3D
var _mat: ShaderMaterial
var _shape: CollisionShape3D
var _land_cooldown: float = 0.0
var _spawn_time: float = 0.0
var _unstick_frames: int = 0  # [world2] check for a spawn/drop inside the ground for this many ticks
## [world2] What a loose bale must never be found inside.
const STICK_MASK: int = PhysLayers.WORLD | PhysLayers.PROP | PhysLayers.MOUND


static func create(p_value: BigNum, p_info: Dictionary) -> JunkCube:
	var c := JunkCube.new()
	c.value = p_value
	c.info = p_info
	var fill: float = clampf(float(p_info.get("fill", 1.0)), 0.25, 1.15)
	c.size = lerpf(0.36, 0.6, clampf(fill, 0.0, 1.0)) * (1.06 if p_info.get("lumpy", false) else 1.0)
	return c


func _ready() -> void:
	add_to_group("junk_cube")
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | PhysLayers.PROP | PhysLayers.MOUND  # [world2] props and junk mounds
	mass = 20.0 + 25.0 * float(info.get("fill", 1.0))
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true  # [world2] small and heavy: never tunnel through a curb or a slab when dropped
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.04
	pm.friction = 0.9
	physics_material_override = pm
	if _mesh == null:
		_mesh = bale_mesh()  # [world2] chunky pressed block (was a smooth rounded box)
	_visual = MeshInstance3D.new()
	_visual.mesh = _mesh
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://art/shaders/cube.gdshader")
	var cols: Array = info.get("colors", [])
	var c0: Color = cols[0] if cols.size() > 0 else Color(0.55, 0.52, 0.5)
	_mat.set_shader_parameter("color_a", c0)
	_mat.set_shader_parameter("color_b", cols[1] if cols.size() > 1 else c0.darkened(0.2))
	_mat.set_shader_parameter("color_c", cols[2] if cols.size() > 2 else c0.lightened(0.15))
	_mat.set_shader_parameter("mix_b", 0.0 if info.get("pure", false) else 0.35)
	_mat.set_shader_parameter("mix_c", 0.0 if info.get("pure", false) else 0.18)
	_mat.set_shader_parameter("perfect", 1.0 if info.get("perfect", false) else 0.0)
	# [world2] Labels in the dominant junk's accent colour; bare-metal glints only where metal went in.
	var dom: String = str(info.get("dominant", ""))
	var jt: Dictionary = Economy.junk_types.get(dom, {})
	if jt.has("flecks"):
		_mat.set_shader_parameter("fleck", Color.html(str(jt["flecks"])))
	_mat.set_shader_parameter("metal_share", 0.35 if dom == "metal" else (0.18 if dom == "electronics" else 0.08))
	_mat.set_shader_parameter("seed", randf() * 100.0)
	_mat.set_shader_parameter("detail_nrm", AssetLib.tex("rubble", "nor_gl"))
	_visual.material_override = _mat
	_visual.scale = Vector3.ONE * size
	if info.get("lumpy", false):
		_visual.scale = Vector3(size * 1.08, size * 0.9, size * 1.02)
		_visual.rotation_degrees = Vector3(0, 7, 0)  # [world2] no pitch/roll: a tilted mesh poked through the floor
	add_child(_visual)
	# Two steel strapping bands with crimp seals.
	if _strap_mesh == null:
		_strap_mesh = strap_mesh()
	var straps := MeshInstance3D.new()
	straps.mesh = _strap_mesh
	straps.material_override = Mats.metal("dark_steel")
	_visual.add_child(straps)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	# [world2] The box matches what is drawn (the rounded cube plus its straps) so a bale rests ON
	# the ground instead of a strap's width inside it; overstuffed bales get their wider, flatter box.
	box.size = (_visual.scale if info.get("lumpy", false) else Vector3.ONE * size) * Vector3(1.03, 1.045, 1.03)
	_shape.shape = box
	_shape.rotation = _visual.rotation
	add_child(_shape)
	_unstick_frames = 2
	body_entered.connect(_on_body_entered)
	_spawn_time = Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float) -> void:
	_land_cooldown = maxf(0.0, _land_cooldown - delta)
	if _unstick_frames > 0 and not carried and not freeze:
		_unstick_frames -= 1
		unstick()
	if planet_radius > 0.0:  # [orbit] round planet: fell into it (radial gravity, planet/orbit/)
		if not carried and global_position.length() < planet_radius - 40.0:
			var lumi: Node3D = get_tree().get_first_node_in_group("patch") as Node3D
			var u: Vector3 = (lumi.global_position if lumi else global_position).normalized()
			global_position = (lumi.global_position if lumi else u * planet_radius) + u * 2.0
			linear_velocity = Vector3.ZERO
			GameState.inc_stat("cubes_fell")
	elif global_position.y < -20.0 and not carried:
		# Fell out of the world: put it back near the hub.
		global_position = Vector3(randf_range(-1, 1), 2.0, randf_range(2, 4))
		linear_velocity = Vector3.ZERO
		GameState.inc_stat("cubes_fell")  # [beat] counted so long autoplay runs report it


func _on_body_entered(_body: Node) -> void:
	if carried or _land_cooldown > 0.0:
		return
	var speed: float = linear_velocity.length()
	if speed > 1.2:
		_land_cooldown = 0.15
		Audio.play("clunk", clampf(1.3 - size, 0.7, 1.2), linear_to_db(clampf(speed / 5.0, 0.15, 1.0)))
		Vfx.burst("dust", global_position - Vector3(0, size * 0.45, 0), Color(0.6, 0.55, 0.5, 0.5), 0.6)


## [world2] Lifts the bale out of anything solid it was spawned or put down inside (the ground,
## a curb, a junk heap, a prop), in 5 cm steps up to 1.5 m. Returns how far it moved.
func unstick() -> float:
	if not is_inside_tree() or _shape == null:
		return 0.0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var probe := BoxShape3D.new()  # a hair smaller: resting contact is not "inside"
	probe.size = ((_shape.shape as BoxShape3D).size - Vector3.ONE * 0.05).max(Vector3.ONE * 0.05)
	q.shape = probe
	q.collision_mask = STICK_MASK
	q.exclude = [get_rid()]
	var start: Vector3 = global_position
	var up_v: Vector3 = global_position.normalized() if planet_radius > 0.0 else Vector3.UP  # [orbit] local up on a planet
	for k: int in 31:
		q.transform = Transform3D(global_basis * _shape.basis, start + up_v * (k * 0.05))
		if space.intersect_shape(q, 1).is_empty():
			if k > 0:
				global_position = start + up_v * (k * 0.05 + 0.01)
				var vu: float = linear_velocity.dot(up_v)
				if vu < 0.0:
					linear_velocity -= up_v * vu
			return k * 0.05
	return 0.0


## [world2] Where to put a bale down in front of `from` (facing `fwd`): 1.25 m ahead, or closer if
## a wall, prop or building is there; at worst right where the carrier stands. Ground-level point.
static func free_spot(space: PhysicsDirectSpaceState3D, from: Vector3, fwd: Vector3, size: float) -> Vector3:
	var q := PhysicsShapeQueryParameters3D.new()
	var probe := BoxShape3D.new()
	probe.size = Vector3.ONE * size * 0.95
	q.shape = probe
	q.collision_mask = PhysLayers.WORLD | PhysLayers.PROP  # PROP includes junk heaps: never into a heap
	var f := Vector3(fwd.x, 0, fwd.z).normalized()
	for d: float in [1.25, 0.95, 0.7]:
		var p: Vector3 = from + f * d
		q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, from.y + size * 0.5 + 0.2, p.z))
		if space.intersect_shape(q, 1).is_empty():
			return Vector3(p.x, from.y, p.z)
	return Vector3(from.x, from.y, from.z)


## [world2] A pressed bale: a unit block whose faces bulge a little between the straps (pillowed by
## the press), with crushed lumps along it and pinched in under each strap, so the silhouette reads
## as a chunky compacted cube, not a smooth box. Displacement is radial and position-hashed, so the
## faces meet without cracks. Unit size; JunkCube scales it.
static func bale_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 10
	var faces: Array = [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f: Array in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		if u.cross(v).dot(nrm) < 0.0:
			v = -v
		var grid: Array = []
		for j: int in n + 1:
			var row: Array = []
			for i: int in n + 1:
				var p: Vector3 = nrm * 0.5 + u * (float(j) / n - 0.5) + v * (float(i) / n - 0.5)
				row.append(_bale_point(p))
			grid.append(row)
		for j: int in n:
			for i: int in n:
				var a: Vector3 = grid[j][i]
				var b: Vector3 = grid[j][i + 1]
				var c: Vector3 = grid[j + 1][i + 1]
				var d: Vector3 = grid[j + 1][i]
				for q: Vector3 in [a, b, c, a, c, d]:  # clockwise from outside: Godot's front faces
					st.add_vertex(q)
	st.generate_normals()
	return st.commit()


static func _bale_point(p: Vector3) -> Vector3:
	# Pillow: zero on the edges, up to ~3% out in the middle of each face (bottom stays flat).
	var bx: float = cos(p.x * PI)
	var by: float = cos(p.y * PI)
	var bz: float = cos(p.z * PI)
	var out := Vector3(signf(p.x) * by * bz * (1.0 if absf(p.x) > 0.499 else 0.0),
		signf(p.y) * bx * bz * (1.0 if p.y > 0.499 else 0.0),
		signf(p.z) * bx * by * (1.0 if absf(p.z) > 0.499 else 0.0)) * 0.03
	# Pinched under the straps (they cinch at x = -0.3, 0, 0.3 and z = -0.25, 0.25).
	var pinch: float = 0.0
	for sx: float in [-0.3, 0.0, 0.3]:
		pinch = maxf(pinch, 1.0 - smoothstep(0.0, 0.07, absf(p.x - sx)))
	for sz: float in [-0.25, 0.25]:
		pinch = maxf(pinch, (1.0 - smoothstep(0.0, 0.07, absf(p.z - sz))) * (1.0 if absf(p.x) < 0.499 else 0.0))
	out *= 1.0 - pinch * 0.9
	# Crushed lumps (hash of the position: identical where faces meet), kept off the bottom.
	var h: float = fmod(absf(sin(p.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453), 1.0)
	var lump: float = (h - 0.5) * 0.022 * (0.0 if p.y < -0.499 else 1.0)
	var edge: float = minf(minf(0.5 - absf(p.x), 0.5 - absf(p.y)), 0.5 - absf(p.z))
	lump *= 1.0 - pinch
	return p + out + p.normalized() * lump * (0.4 if edge < 0.01 else 1.0)


## [world2] Steel strapping: three bands around the sides and top/bottom (x), two crossing them (z),
## standing proud of the block, with crimp seals on the front. Unit size.
static func strap_mesh() -> ArrayMesh:
	var parts: Array = []
	var w: float = 0.055
	var t: float = 0.02
	var o: float = 0.515
	for x: float in [-0.3, 0.0, 0.3]:
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(w, 1.04, t)), ProcMesh.xf(Vector3(x, 0, o))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(w, 1.04, t)), ProcMesh.xf(Vector3(x, 0, -o))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(w, t, 1.04)), ProcMesh.xf(Vector3(x, o, 0))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(w, t, 1.04)), ProcMesh.xf(Vector3(x, -o, 0))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(w + 0.03, 0.06, 0.03)), ProcMesh.xf(Vector3(x, 0.18, o + 0.008))))
	for z: float in [-0.25, 0.25]:
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(t, 1.04, w)), ProcMesh.xf(Vector3(o + 0.004, 0, z))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(t, 1.04, w)), ProcMesh.xf(Vector3(-o - 0.004, 0, z))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(1.05, t, w)), ProcMesh.xf(Vector3(0, o + 0.012, z))))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(1.05, t, w)), ProcMesh.xf(Vector3(0, -o - 0.004, z))))
	return ProcMesh.merge(parts)


func squish(_amount: float) -> void:
	pass  # Realism pass: bales don't squash; impacts are told by sound and dust.


func flash() -> void:
	_mat.set_shader_parameter("flash", 1.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.3)


## Switches between physical and carried (kinematic, no collision).
func set_carried(on: bool) -> void:
	carried = on
	if on:
		# Off the ground: a hauler's reservation no longer applies (Patch may grab a bale a
		# Haul Bug was heading for, and put it down somewhere else).
		set_meta("reserved", false)
	freeze = on
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_shape.disabled = on
	if not on:
		sleeping = false
		_unstick_frames = 2  # [world2] put down inside a slab or a heap: lift it out


func to_dict() -> Dictionary:
	var cols: Array = []
	for c: Color in info.get("colors", []):
		cols.append(c.to_html())
	return {
		"value": value.serialize(),
		"pos": [global_position.x, global_position.y, global_position.z],
		"rot": [rotation.x, rotation.y, rotation.z],
		"pure": info.get("pure", false), "perfect": info.get("perfect", false),
		"lumpy": info.get("lumpy", false), "fill": info.get("fill", 1.0), "colors": cols,
		"dominant": str(info.get("dominant", "")), "volume": float(info.get("volume", 0.0)),
	}


static func from_dict(d: Dictionary) -> JunkCube:
	var cols: Array[Color] = []
	for h: Variant in d.get("colors", []):
		cols.append(Color.html(str(h)))
	var info_d: Dictionary = {
		"pure": d.get("pure", false), "perfect": d.get("perfect", false),
		"lumpy": d.get("lumpy", false), "fill": float(d.get("fill", 1.0)), "colors": cols,
		"dominant": str(d.get("dominant", "")),
	}
	# Only when saved: pre-fix saves fall back to fill * 12 in the recycler (0.0 would pay nothing).
	if d.has("volume") and float(d["volume"]) > 0.0:
		info_d["volume"] = float(d["volume"])
	return JunkCube.create(BigNum.from_serialized(d.get("value", [0.0, 0])), info_d)
