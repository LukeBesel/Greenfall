extends GutTest
## [world2] Every solid prop of the start district's city and street dressing has a collider
## (tools/collider_audit.gd; the full-scene run covers stations, outposts, eggs and frontiers).

var root: Node3D
var layout: CityLayout
var field: HexField


func before_all() -> void:
	layout = CityLayout.new(4471, 150.0, false)
	field = HexField.new(4, 10.0, 4471, layout)
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	field.generate(types, Vector2i(30, 40))


func _build(level: int) -> void:
	root = Node3D.new()
	add_child_autofree(root)
	var city := CityView.new()
	root.add_child(city)
	city.build(layout, StandardMaterial3D.new())
	var d := StreetDressing.new()
	root.add_child(d)
	d.build(layout, field, 0, "Old Town", "", level)
	await wait_physics_frames(3)


func test_start_district_props_all_collide() -> void:
	await _build(1)
	var leaks: Array = ColliderAudit.scan(root, root.get_world_3d().direct_space_state, layout, 60.0)
	for l: Dictionary in leaks:
		gut.p("leak: %s" % str(l))
	assert_eq(leaks.size(), 0, "solid props without colliders")


func test_futuristic_base_props_all_collide() -> void:
	await _build(5)
	var leaks: Array = ColliderAudit.scan(root, root.get_world_3d().direct_space_state, layout, 60.0)
	assert_eq(leaks.size(), 0)


func test_audit_catches_a_prop_without_a_collider() -> void:
	await _build(1)
	var crate := MeshInstance3D.new()
	crate.mesh = ProcMesh.box(Vector3(0.8, 1.0, 0.8))
	crate.position = Vector3(0.0, 0.5, 4.0)
	root.add_child(crate)
	var leaks: Array = ColliderAudit.scan(root, root.get_world_3d().direct_space_state, layout, 60.0)
	assert_eq(leaks.size(), 1, "an uncollided 1 m crate in the yard is reported")
