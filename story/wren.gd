class_name Wren
extends Node
## WREN: the ark Cradle's AI, whispering to Lumi over a failing relay. Speaks in short subtitled lines.
## Her memory returns with restoration (stage 0..2 pick the line pools); every line is shown clean
## on the one subtitle line (ui/subtitles.gd). Lines never repeat until a pool is exhausted.

signal line_started(text: String, stage: int)
## [onboard] What actually reaches the subtitles: line_started passes the signal gate first. With no
## Signal Tower (story/signal_tower.gd) WREN is silent: story lines sent meanwhile wait in a small
## backlog and come through when the tower is rebuilt. Intro lines and speak(force) always pass.
signal line_out(text: String, stage: int)

## [onboard] Tips, idle remarks and other chatter: much rarer, and never closer than this.
const CHATTER_MULT: float = 0.35
const CHATTER_GAP_S: float = 150.0
const BACKLOG_MAX: int = 6
## [v4calm] Owner item 49 ("far too many messages"): reward chatter and stat remarks are cut. These
## triggers never speak; story beats, goals and warnings still do.
const MUTED: Array[String] = ["hex_clean", "perfect", "upgrade", "idle", "part_rare", "milestone", "streak_max", "ledger_coupon", "egg_found", "bloom_milestone", "event_won"]
## [v4calm] Owner item 47: these speak once per save (Once flags), never again.
const ONCE: Array[String] = ["robot_built", "first_robot_hint", "globe", "jammer_built", "greenhouse_built", "outpost_repaired", "outpost_upgraded"]

var lines: Dictionary = {}
var _queue: Array[Dictionary] = []
var _cooldown: float = 0.0
var _idle_said: bool = false
var world: Node
var _pass: Dictionary = {}  # [onboard] lines allowed through without a tower (her last message)
var _chatter_t: float = 0.0


func _ready() -> void:
	lines = Economy.read_json("res://data/wren_lines.json")
	line_started.connect(_gate)  # [onboard]
	EventBus.hex_cleaned.connect(_on_hex)
	EventBus.milestone_reached.connect(func(_id: String) -> void: say("milestone", 0.0, true))
	EventBus.cube_made.connect(func(info: Dictionary) -> void:
		if info.get("perfect", false):
			say("perfect", 0.35))
	EventBus.upgrade_bought.connect(func(_id: String, _l: int) -> void:
		say("upgrade", 0.3)
		if GameState.get_currency("parts").to_float() < 40.0 and not GameState.flags.get("wren_hint_robot", false):  # [ui2] parts are a currency
			GameState.flags["wren_hint_robot"] = true
			say("first_robot_hint", 1.0, true))
	EventBus.robot_built.connect(func(rname: String) -> void: say("robot_built", 1.0, true, {"robot": rname}))
	EventBus.part_found.connect(func(_t: int, rarity: int) -> void:
		if rarity >= 3:
			say("part_rare", 1.0, true))


## [onboard] She can talk once a Signal Tower carries her (was: after the first clean hex).
func awake() -> bool:
	return SignalTower.tier() > 0


## [onboard] Clarity follows the relay signal: tower tier 1 crackly, 2 clearer, 3+ clear.
func stage() -> int:
	return clampi(SignalTower.tier() - 1, 0, 2)


func _on_hex(_h: int, _p: Vector3, _b: BigNum) -> void:
	say("hex_clean", 0.4)


## [onboard] Queue a scripted line (already translated), whether or not she is "awake" yet.
## force: passes even with no tower (her last message in the crash).
func speak(text: String, stage: int = 1, force: bool = false) -> void:
	if text != "":
		if force:
			_pass[text] = true
		_queue.append({"text": text, "stage": stage})


## [onboard] The signal gate between line_started and the subtitles.
func _gate(text: String, st: int) -> void:
	var intro: Variant = world.get("intro") if world else null
	var cine: bool = intro is Intro and (intro as Intro).busy()
	if awake() or cine or _pass.has(text):
		_pass.erase(text)
		line_out.emit(text, st)
		return
	var bl: Array = GameState.flags.get("wren_backlog", [])
	if not (text in bl):
		bl.append(text)
		while bl.size() > BACKLOG_MAX:
			bl.pop_front()
	GameState.flags["wren_backlog"] = bl


## [onboard] The tower went up a tier: first contact (or a clearer line), then what she couldn't send.
func on_signal_raised(tier_: int) -> void:
	GameState.flags["wren_awake"] = true
	say("wake" if tier_ == 1 else "signal_up", 1.0, true)
	var bl: Array = GameState.flags.get("wren_backlog", [])
	if tier_ == 1:  # [v2guide] first contact: her briefing (story/objectives.gd) leads; only the last two missed lines
		bl = bl.slice(maxi(0, bl.size() - 2))
	for t: Variant in bl:
		_queue.append({"text": str(t), "stage": stage()})
	GameState.flags["wren_backlog"] = []


## Queue a line from a trigger pool. chance < 1 lets frequent events stay sparse.
## [worlds2] stage_override >= 0 speaks from that signal stage (Cradle Mode worlds: WREN talks over the
## ark's own relay, clear from the first line).
func say(trigger: String, chance: float = 1.0, important: bool = false, vars: Dictionary = {}, stage_override: int = -1) -> void:
	if not awake() and stage_override < 0:  # [onboard] no tower, no WREN (other worlds: the ark's relay)
		return
	if trigger in MUTED or (trigger.begins_with("event_") and stage_override < 0):  # [v4calm] item 49 (events: their toast says it)
		return
	if trigger in ONCE and not Once.take("wren_" + trigger):  # [v4calm] item 47
		return
	if not important:  # [onboard] chatter: much rarer, spaced out
		chance *= CHATTER_MULT
		if _chatter_t > 0.0:
			return
	if randf() > chance:
		return
	if not important and (_cooldown > 0.0 or _queue.size() > 1):
		return
	if not important:
		_chatter_t = CHATTER_GAP_S
	var pools: Array = lines.get(trigger, [])
	if pools.is_empty():
		return
	var st: int = mini(stage() if stage_override < 0 else stage_override, pools.size() - 1)
	var pool: Array = pools[st]
	if pool.is_empty():
		return
	var used_key: String = "wren_used_%s_%d" % [trigger, st]
	var used: Array = GameState.flags.get(used_key, [])
	var options: Array = []
	for i: int in pool.size():
		if not (i in used):
			options.append(i)
	if options.is_empty():
		used = []
		options = range(pool.size())
	var pick: int = options[randi() % options.size()]
	used.append(pick)
	GameState.flags[used_key] = used
	var text: String = tr(str(pool[pick])).format({"name": GameState.flags.get("patch_name", "Lumi")}.merged(vars))
	if stage_override >= 0:
		_pass[text] = true
	_queue.append({"text": text, "stage": st if stage_override < 0 else stage_override})


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_chatter_t = maxf(0.0, _chatter_t - delta)
	var modal: bool = world != null and world.has_method("any_modal_open") and bool(world.call("any_modal_open"))
	if _cooldown <= 0.0 and not _queue.is_empty() and not modal:  # [v2guide] nothing during modals
		var l: Dictionary = _queue.pop_front()
		line_started.emit(l["text"], int(l["stage"]))
		_cooldown = Subtitles.total_time(str(l["text"])) + 0.6  # [intro2] the line is fully read before the next
	# Idle remark once per idle stretch.
	if world and world.patch:
		var idle: float = world.patch._idle_time
		if idle > 50.0 and not _idle_said:
			_idle_said = true
			say("idle", 1.0)
		elif idle < 1.0:
			_idle_said = false
