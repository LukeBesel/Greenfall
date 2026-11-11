extends GutTest
## B35: a lambda that uses nothing of its node is not tied to the node, so its EventBus connection
## outlives the node. Every world built (a reload, a hub hop) then left one more listener behind
## and one event paid research data, counted a stat or played a sting once per world built.
## The world's systems connect methods instead: the engine drops those with the node.

const SIGNALS: Array[String] = ["hex_cleaned", "hex_restored", "junk_scooped", "upgrade_bought", "robot_built",
	"research_completed"]

var _cur: Dictionary
var _flags: Dictionary
var _stats: Dictionary


func before_each() -> void:
	_cur = GameState.currencies.duplicate()
	_flags = GameState.flags.duplicate(true)
	_stats = GameState.stats.duplicate(true)
	GameState.flags = {}
	GameState.currencies = {}
	GameState.stats = {}


func after_each() -> void:
	GameState.currencies = _cur
	GameState.flags = _flags
	GameState.stats = _stats


func _counts() -> Dictionary:
	var out: Dictionary = {}
	for s: String in SIGNALS:
		out[s] = EventBus.get_signal_connection_list(s).size()
	return out


## Stands in for one world: the system joins the tree, then leaves it with its world.
func _build_and_free(script: GDScript) -> void:
	var n: Node = script.new() as Node
	add_child(n)
	await wait_process_frames(1)
	n.free()


## Field notes logged so far (Research.award_data counts them whatever a note pays on this planet).
func _notes() -> float:
	return float(GameState.stats.get("data_earned", 0.0))


func test_world_systems_leave_no_event_listener_behind() -> void:
	for script: GDScript in [Research, Goals, Achievements, MusicHooks]:
		var before: Dictionary = _counts()
		await _build_and_free(script)
		assert_eq(_counts(), before, "%s leaves no EventBus listener behind" % script.get_global_name())


func test_clean_hex_pays_research_data_once_after_two_worlds() -> void:
	await _build_and_free(Research)
	var r := Research.new()
	add_child_autofree(r)
	await wait_process_frames(1)
	var want: float = Research.reward("hex_cleaned")
	assert_gt(want, 0.0, "a clean hex logs field notes")
	var n0: float = _notes()
	EventBus.hex_cleaned.emit(0, Vector3.ZERO, BigNum.from_float(0.0))
	assert_almost_eq(_notes() - n0, want, 0.001, "one clean hex logs its notes once")
	want = FieldData.stage_reward(3)
	n0 = _notes()
	EventBus.hex_level_changed.emit(0, 3)
	assert_almost_eq(_notes() - n0, want, 0.001, "one hex stage logs its field data once")


func test_scooped_piece_counts_once_after_two_worlds() -> void:
	await _build_and_free(Goals)
	var g := Goals.new()
	add_child_autofree(g)
	await wait_process_frames(1)
	EventBus.junk_scooped.emit("can", Vector3.ZERO)
	assert_eq(float(GameState.stats.get("junk_scooped", 0.0)), 1.0, "one piece scooped is counted once")


func test_restored_hex_counts_once_after_two_worlds() -> void:
	await _build_and_free(Achievements)
	var a := Achievements.new()
	add_child_autofree(a)
	await wait_process_frames(1)
	EventBus.hex_restored.emit(0)
	assert_eq(float(GameState.stats.get("hexes_restored", 0.0)), 1.0, "one restored hex is counted once")
