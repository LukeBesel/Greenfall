extends Node
func _ready() -> void:
	var s: Node = load("res://scenes/slice.tscn").instantiate()
	get_tree().root.add_child.call_deferred(s)
	for i: int in 40:
		await get_tree().physics_frame
	var space := (s as Node3D).get_world_3d().direct_space_state
	for p: Vector3 in [Vector3(-18.7, 0.5, 22.0), Vector3(-19, 0.5, 19.9), Vector3(0.1, 0.5, 11.9), Vector3(-9.8, 0.5, 16.6), Vector3(-1.7,0.5,19.1)]:
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 1.5
		q.shape = sh
		q.transform = Transform3D(Basis(), p)
		q.collision_mask = 1 | 32 | 64
		var hits: Array = space.intersect_shape(q, 16)
		var names: Array = []
		for h: Dictionary in hits:
			var c: Node = h["collider"]
			names.append("%s/%s L%d" % [c.get_parent().name, c.name, (c as CollisionObject3D).collision_layer])
		print("[probe] ", p, " -> ", names)
	get_tree().quit()
