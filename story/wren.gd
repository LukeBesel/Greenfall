class_name Wren
extends Node
## WREN: the ark Cradle's AI, whispering to Lumi over a failing relay. Speaks in short subtitled lines.
## Her memory (and text clarity) returns with restoration: stage 0 lines arrive glitched and
## resolve as they type; later stages are clean. Lines never repeat until a pool is exhausted.

signal line_started(text: String, stage: int)

var lines: Dictionary = {}
var _queue: Array[Dictionary] = []
var _cooldown: float = 0.0
var _idle_said: bool = false
var world: Node


func _ready() -> void:
	lines = Economy.read_json("res://data/wren_lines.json")
	EventBus.hex_cleaned.connect(_on_hex)
	EventBus.milestone_reached.connect(func(_id: String) -> void: say("milestone", 0.0, true))
	EventBus.cube_made.connect(func(info: Dictionary) -> void:
		if info.get("perfect", false):
			say("perfect", 0.35))
	EventBus.upgrade_bought.connect(func(_id: String, _l: int) -> void:
		say("upgrade", 0.3)
		if GameState.parts.size() < 2 and not GameState.flags.get("wren_hint_robot", false):
			GameState.flags["wren_hint_robot"] = true
			say("first_robot_hint", 1.0, true))
	EventBus.robot_built.connect(func(rname: String) -> void: say("robot_built", 1.0, true, {"robot": rname}))
	EventBus.part_found.connect(func(_t: int, rarity: int) -> void:
		if rarity >= 3:
			say("part_rare", 1.0, true))


func awake() -> bool:
	return GameState.flags.get("wren_awake", false)


func stage() -> int:
	var n: int = world.planet.restored_count() if world and world.get("planet") != null else 0
	return 0 if n < 6 else (1 if n < 20 else 2)


func _on_hex(_h: int, _p: Vector3, _b: BigNum) -> void:
	if not awake():
		GameState.flags["wren_awake"] = true
		say("wake", 1.0, true)
		return
	say("hex_clean", 0.4)


## Queue a line from a trigger pool. chance < 1 lets frequent events stay sparse.
## [worlds2] stage_override >= 0 speaks from that signal stage (Cradle Mode worlds: WREN talks over the
## ark's own relay, clear from the first line).
func say(trigger: String, chance: float = 1.0, important: bool = false, vars: Dictionary = {}, stage_override: int = -1) -> void:
	if not awake() and trigger != "wake":
		return
	if randf() > chance:
		return
	if not important and (_cooldown > 0.0 or _queue.size() > 1):
		return
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
	_queue.append({"text": text, "stage": st if stage_override < 0 else stage_override})


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown <= 0.0 and not _queue.is_empty():
		var l: Dictionary = _queue.pop_front()
		line_started.emit(l["text"], int(l["stage"]))
		_cooldown = 4.0 + str(l["text"]).length() * 0.045
	# Idle remark once per idle stretch.
	if world and world.patch:
		var idle: float = world.patch._idle_time
		if idle > 50.0 and not _idle_said:
			_idle_said = true
			say("idle", 1.0)
		elif idle < 1.0:
			_idle_said = false
