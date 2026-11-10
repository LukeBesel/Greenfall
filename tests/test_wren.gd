extends GutTest

var wren: Wren
var _flags: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	GameState.flags = {}
	wren = Wren.new()
	add_child_autofree(wren)


func after_each() -> void:
	GameState.flags = _flags


func test_silent_until_awake() -> void:
	wren.say("perfect", 1.0, true)
	assert_eq(wren._queue.size(), 0)


func test_wake_when_the_signal_tower_goes_up() -> void:  # [onboard] was: on the first clean hex
	wren._on_hex(0, Vector3.ZERO, BigNum.zero())
	assert_false(wren.awake(), "a clean hex no longer wakes her: the tower does")
	assert_eq(wren._queue.size(), 0)
	GameState.flags["signal_tower"] = 1
	wren.on_signal_raised(1)
	assert_true(wren.awake())
	assert_eq(wren._queue.size(), 1)
	assert_string_contains(str(wren._queue[0]["text"]), "Lumi")  # the first line after the tower greets Lumi


func test_gate_holds_story_lines_until_the_tower() -> void:  # [onboard]
	var got: Array = []
	wren.line_out.connect(func(t: String, _s: int) -> void: got.append(t))
	wren.line_started.emit("A story beat.", 1)
	assert_eq(got.size(), 0, "silent without a tower")
	assert_eq(GameState.flags.get("wren_backlog", []), ["A story beat."])
	wren.speak("Her last message.", 0, true)
	wren._process(0.0)
	assert_eq(got, ["Her last message."], "her last message gets through")
	GameState.flags["signal_tower"] = 1
	wren.on_signal_raised(1)
	assert_eq(GameState.flags["wren_backlog"], [], "the backlog is delivered")
	assert_true(wren._queue.any(func(q: Dictionary) -> bool: return q["text"] == "A story beat."))


func test_chatter_is_rare_and_spaced() -> void:  # [onboard]
	GameState.flags["signal_tower"] = 3
	var n: int = 0
	for i: int in 200:
		wren._queue.clear()
		wren._cooldown = 0.0
		wren._chatter_t = 0.0
		wren.say("night", 1.0)  # [v4calm] hex_clean is muted now
		n += wren._queue.size()
	assert_between(n, 40, 110, "about a third of the old rate")
	wren._chatter_t = 0.0
	wren._queue.clear()
	for i: int in 50:
		wren._cooldown = 0.0
		wren.say("night", 1.0)
	assert_lte(wren._queue.size(), 1, "never two chatter lines within the gap")


func test_clarity_follows_the_tower() -> void:  # [onboard]
	for t: int in [1, 2, 3, 4]:
		GameState.flags["signal_tower"] = t
		assert_eq(wren.stage(), mini(t - 1, 2))


func test_no_repeats_until_pool_exhausted() -> void:
	GameState.flags["signal_tower"] = 1
	var pool: Array = wren.lines["ledger_drop"][0]  # [v4calm] hex_clean is muted now
	var seen: Dictionary = {}
	for i: int in pool.size():
		wren.say("ledger_drop", 1.0, true)
	for q: Dictionary in wren._queue:
		seen[q["text"]] = true
	assert_eq(seen.size(), pool.size())


func test_vars_formatted() -> void:
	GameState.flags["signal_tower"] = 1
	GameState.flags["stage_override"] = 1
	wren.say("robot_built", 1.0, true, {"robot": "Rivet-07"})
	assert_false(str(wren._queue[0]["text"]).contains("{robot}"))


## [v2guide] Owner playtest 2 #34: once the tower carries her, WREN briefs Lumi (who she is, the plan
## home), then speaks one line as each new story step starts; never twice for a step, never during
## a modal, never before the tower.
func test_wren_briefs_then_narrates_each_step_once() -> void:
	var flags0: Dictionary = GameState.flags.duplicate(true)
	var stats0: Dictionary = GameState.stats.duplicate(true)
	var src := GDScript.new()
	src.source_code = "extends Node\nvar wren\nvar modal := false\nfunc any_modal_open() -> bool:\n\treturn modal\n"
	src.reload()
	var w: Node = src.new()
	add_child_autofree(w)
	var wren := Wren.new()
	wren.world = w
	w.add_child(wren)
	w.set("wren", wren)
	wren.set_process(false)
	var ob := Objectives.new()
	ob.world = w
	var cfg: Dictionary = Economy.planet_table(Objectives.TABLE)
	ob.chain = cfg["objectives"]
	ob.wren_brief = (cfg["wren_brief"] as Dictionary)["lines"]
	for i: int in ob.chain.size():
		if str(ob.chain[i]["id"]) == "hex":
			ob.step = i
	GameState.stats["hexes_cleaned"] = 0
	GameState.flags.erase("wren_briefed")
	GameState.flags.erase("wren_steps")
	GameState.flags["signal_tower"] = 0
	ob._narrate()
	assert_eq(wren._queue.size(), 0, "no tower, no WREN")
	GameState.flags["signal_tower"] = 1
	w.set("modal", true)
	ob._narrate()
	assert_eq(wren._queue.size(), 0, "nothing during a modal")
	w.set("modal", false)
	ob._narrate()
	assert_eq(wren._queue.size(), 3, "the briefing: who she is, the ark, the way home")
	var brief: String = " ".join(wren._queue.map(func(l: Dictionary) -> String: return str(l["text"])))
	assert_true(brief.contains("Cradle") and brief.contains("Verdance") and brief.contains("home"))
	ob._narrate()
	assert_eq(wren._queue.size(), 4, "then the current step's line")
	ob._narrate()
	assert_eq(wren._queue.size(), 4, "one line per step")
	for d: Dictionary in ob.chain:
		var ls: Array = d.get("lines", [])
		assert_eq(ls.size(), 1, "%s: one short line" % d["id"])
		assert_lt(str(ls[0]).length(), 100, "%s: subtitle-sized" % d["id"])
	ob.free()
	GameState.flags = flags0
	GameState.stats = stats0
