extends GutTest
## [v2map] Owner note 40: travel is only at the rocket. The rocket's list (ui/rocket_picker.gd)
## offers the hubs it is given and hands the pick back.


func test_picker_lists_hubs_and_hands_back_the_pick() -> void:
	var p := RocketPicker.new()
	add_child_autofree(p)
	p.entries_fn = func() -> Array: return [{"site": 3, "name": "Brindle", "km": 1.2}, {"site": 5, "name": "Moss", "km": 2.5}]
	watch_signals(p)
	p.open()
	assert_eq(p.offered_sites(), [3, 5])
	var fly: Array = p._list.find_children("*", "Button", true, false)
	assert_eq(fly.size(), 2, "one Fly button per hub and nothing else")
	(fly[1] as Button).pressed.emit()
	assert_signal_emitted_with_parameters(p, "picked", [5])
	assert_false(p.is_open)


# With nowhere to fly yet (only the first city is unlocked) the list says what opens the next one.
func test_an_empty_list_says_what_opens_the_next_city() -> void:
	var p := RocketPicker.new()
	add_child_autofree(p)
	p.open()
	var plain: Array = p._list.find_children("*", "Label", true, false)
	assert_eq((plain[0] as Label).text, "No other hubs found yet.", "the plain line when nobody says more")
	p.close()
	p.empty_fn = func() -> String: return "Nowhere to fly yet. Get Old Town to Sustained to open Ironside."
	p.open()
	await wait_process_frames(2)  # the old rows are freed
	var labels: Array = p._list.find_children("*", "Label", true, false)
	assert_eq(labels.size(), 1)
	assert_eq((labels[0] as Label).text, "Nowhere to fly yet. Get Old Town to Sustained to open Ironside.")
	assert_eq(p._list.find_children("*", "Button", true, false).size(), 0, "nothing to fly to")
	p.close()
