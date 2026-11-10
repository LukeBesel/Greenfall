extends GutTest
## Regression: SiteManager._attach_power waits for the slice's HexLevels. When Lumi starts (or lands)
## far from a hub, that hub's prefab is freed during the wait; touching it was a script error.


class FakeWorld:
	extends Node3D
	var hex_levels: HexLevels = null
	var hub: Node = null


func test_attach_power_survives_a_prefab_freed_while_it_waits() -> void:
	var w := FakeWorld.new()
	add_child_autofree(w)
	var globe := Node3D.new()
	w.add_child(globe)
	var sm := SiteManager.new()
	sm.globe = globe
	sm.levels = PackedInt32Array([1])
	globe.add_child(sm)
	var p := SitePrefab.new()
	p.content = Node3D.new()
	p.add_child(p.content)
	globe.add_child(p)
	sm._attach_power(0, p)  # starts waiting: the world has no HexLevels yet
	await get_tree().process_frame
	p.free()
	var hl := HexLevels.new()
	autofree(hl)
	w.hex_levels = hl
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(sm.power.has(0), "no street power for a site that is gone")
	assert_true(is_instance_valid(sm), "the manager carried on")
