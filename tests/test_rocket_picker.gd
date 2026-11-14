extends GutTest
## [v2map] Owner note 40: travel is only at the rocket. The solar-system map opened as a map has no
## Launch button; opened from the rocket (travel mode) it does. The rocket's list (ui/rocket_picker.gd)
## offers the hubs it is given and hands the pick back.

var _profile: Dictionary
var _flags: Dictionary


func before_each() -> void:
	_profile = CradleMode.profile.duplicate(true)
	_flags = GameState.flags.duplicate(true)
	CradleMode.persist = false
	CradleMode.profile = CradleMode.default_profile()
	(Homeward.state()["pct"] as Dictionary)["verdance"] = 1.0
	(Homeward.state()["pct"] as Dictionary)["ochre"] = 0.3


func after_each() -> void:
	CradleMode.profile = _profile
	GameState.flags = _flags


func _texts(n: Node) -> Array:
	var out: Array = []
	for b: Node in n.find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return out


func test_map_view_has_no_launch() -> void:
	var m := SystemMap.new()
	add_child_autofree(m)
	m.open_map()
	m._select(1)
	assert_false(_texts(m._cards).has("Launch"), "a map, not a launcher")
	m.close_map()
	m.open_map(false, true)
	m._select(1)
	m._rebuild_cards()
	assert_true(m.travel)
	assert_false(_texts(m._cards).has("Launch from the rocket pad"), "travel mode offers the real launch")
	m.close_map()


func test_picker_lists_hubs_and_hands_back_the_pick() -> void:
	var p := RocketPicker.new()
	add_child_autofree(p)
	p.entries_fn = func() -> Array: return [{"site": 3, "name": "Brindle", "km": 1.2}, {"site": 5, "name": "Moss", "km": 2.5}]
	watch_signals(p)
	p.open()
	assert_eq(p.offered_sites(), [3, 5])
	var fly: Array = p._list.find_children("*", "Button", true, false)
	assert_eq(fly.size(), 2, "one Fly button per hub, no planets before the system opens")
	(fly[1] as Button).pressed.emit()
	assert_signal_emitted_with_parameters(p, "picked", [5])
	assert_false(p.is_open)

