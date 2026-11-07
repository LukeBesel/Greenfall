class_name MoundColliders
extends RefCounted
## [world2] Junk-pile mounds are solid for bales (PhysLayers.MOUND): a bale dropped on a landfill
## pile rests on the heap instead of sinking through it to the flat ground under it (the owner's
## "bale glitched in the ground"). Lumi and robots keep hovering/driving through mounds as before.
## One StaticBody3D per mound with a low-poly hemisphere hull, rescaled as the mound shrinks while
## its hex is cleaned (bales on it are woken so they settle) and switched off once the hex is clean.

const RINGS: int = 4
const SEGS: int = 10
## The visual mound is a noisy hemisphere (radius 1 +- 35%); the hull sits a little inside it so a
## bale beds into the heap instead of floating over its dips.
const INSET_R: float = 0.92
const INSET_H: float = 0.9

static var _unit: PackedVector3Array


static func _unit_points() -> PackedVector3Array:
	if _unit.is_empty():
		for r: int in RINGS:
			var phi: float = float(r) / RINGS * PI * 0.5
			for k: int in SEGS:
				var th: float = float(k) / SEGS * TAU
				_unit.append(Vector3(cos(th) * cos(phi), sin(phi), sin(th) * cos(phi)))
		_unit.append(Vector3.UP)
	return _unit


static func make(parent: Node3D, pile: Vector4) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = "MoundBody"
	b.collision_layer = PhysLayers.MOUND
	b.collision_mask = 0
	b.position = Vector3(pile.x, -0.02, pile.y)
	var cs := CollisionShape3D.new()
	cs.shape = ConvexPolygonShape3D.new()
	b.add_child(cs)
	parent.add_child(b)
	return b


## `scale` is the mound mesh's scale (radius, height, radius); <= 0 height switches it off.
static func update(b: StaticBody3D, scale: Vector3, visible: bool) -> void:
	if b == null:
		return
	var cs: CollisionShape3D = b.get_child(0)
	var on: bool = visible and scale.y > 0.03
	cs.disabled = not on
	if on:
		var pts := PackedVector3Array()
		var s := Vector3(scale.x * INSET_R, scale.y * INSET_H, scale.z * INSET_R)
		for p: Vector3 in _unit_points():
			pts.append(p * s)
		(cs.shape as ConvexPolygonShape3D).points = pts
	# Bales resting on the heap settle onto what is left of it.
	if b.is_inside_tree():
		var r2: float = (scale.x + 0.6) * (scale.x + 0.6)
		for n: Node in b.get_tree().get_nodes_in_group("junk_cube"):
			var c := n as RigidBody3D
			if c and not c.freeze and Vector2(c.global_position.x - b.position.x, c.global_position.z - b.position.z).length_squared() < r2:
				c.sleeping = false
