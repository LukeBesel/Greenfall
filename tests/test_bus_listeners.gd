extends GutTest
## [v9a] Nodes the world builds again on every load must not leave EventBus listeners behind. A
## lambda that uses no member of its node is bound to the script, not to the node, so connected to
## an EventBus signal it outlived the node: every world load (Continue, a flight to another base)
## added one more. A robot's hex then paid its field notes once per load since the game started
## (home walk: 1,200 cubes instead of 100 after 12 loads), and scoops and restored hexes counted
## several times.


func _bus_connections() -> int:
	var n: int = 0
	for s: Dictionary in EventBus.get_signal_list():
		n += EventBus.get_signal_connection_list(str(s["name"])).size()
	return n


func _leaves_none(node: Node, what: String) -> void:
	var n0: int = _bus_connections()
	add_child(node)
	await get_tree().process_frame
	assert_gt(_bus_connections(), n0, "%s listens on EventBus while it lives" % what)
	node.free()
	await get_tree().process_frame
	assert_eq(_bus_connections(), n0, "%s leaves no EventBus listener behind once freed" % what)


func test_research_leaves_no_listener() -> void:
	await _leaves_none(Research.new(), "Research")


func test_goals_leave_no_listener() -> void:
	await _leaves_none(Goals.new(), "Goals")


func test_achievements_leave_no_listener() -> void:
	await _leaves_none(Achievements.new(), "Achievements")


func test_music_hooks_leave_no_listener() -> void:
	await _leaves_none(MusicHooks.new(), "MusicHooks")


func test_hex_notes_paid_once_after_reloads() -> void:
	for k: int in 3:  # three worlds come and go
		var r: Research = Research.new()
		add_child(r)
		await get_tree().process_frame
		r.free()
	var live: Research = Research.new()
	add_child_autofree(live)
	await get_tree().process_frame
	var c0: float = GameState.get_currency("cubes").to_float()
	EventBus.hex_cleaned.emit(0, Vector3.ZERO, BigNum.zero())
	var paid: float = GameState.get_currency("cubes").to_float() - c0
	assert_almost_eq(paid, Research.stat_mod("data_gain", 1.0) * Research.reward("hex_cleaned") * Research.note_cubes(), 0.01,
		"a cleaned hex pays its field notes once (%.2f)" % paid)
