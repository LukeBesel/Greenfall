extends GutTest
## Regression tests for QA fixes: modal-close press leaking into gameplay,
## saved_unix tracking.


class _Probe extends Node:
	var input: PlayerInput
	var results: Array[bool] = []

	func _physics_process(_delta: float) -> void:
		results.append(input.drop_pressed())


func test_reenabled_input_ignores_the_closing_press() -> void:
	var pi := PlayerInput.new()
	var probe := _Probe.new()
	probe.input = pi
	pi.enabled = false
	add_child_autofree(probe)
	await get_tree().physics_frame
	# The press that closes a modal arrives, and the modal re-enables input in the same frame.
	Input.action_press("drop")
	pi.enabled = true
	probe.results.clear()
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("drop")
	assert_false(probe.results.has(true), "closing press must not reach gameplay: %s" % str(probe.results))
	# A later, fresh press does register.
	await get_tree().physics_frame
	await get_tree().physics_frame
	probe.results.clear()
	Input.action_press("drop")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("drop")
	assert_true(probe.results.has(true), "a fresh press works: %s" % str(probe.results))


func test_to_dict_updates_saved_unix() -> void:
	var old: float = GameState.saved_unix
	GameState.saved_unix = 1000.0
	var d: Dictionary = GameState.to_dict()
	assert_gt(GameState.saved_unix, 1000.0)
	assert_eq(float(d["saved_unix"]), GameState.saved_unix)
	GameState.saved_unix = old
