class_name Tutorial
extends Node
## Patch's restart checklist: a diegetic, step-by-step tutorial told by his own systems.
## Each step completes on a gameplay event; progress persists in GameState.flags.

const STEPS: Array[Dictionary] = [
	{"id": "scoop", "text": "Hold  {scoop}  to scoop junk into the hopper", "goal": 8},
	{"id": "bale", "text": "Fill the hopper near the line, then  {cube}  to compress a bale"},
	{"id": "carry", "text": "{interact}  to pick up the bale"},
	{"id": "cash", "text": "Set it on the scale by the green skip"},
	{"id": "upgrade", "text": "Walk into the shack.  {interact}  at the workbench to install an upgrade"},
	{"id": "hex", "text": "Clear this whole hex. Every last can."},
]

var world: Node
var step: int = 0
var _count: int = 0


func _ready() -> void:
	step = int(GameState.flags.get("tutorial_step", 0))
	EventBus.junk_scooped.connect(func(_t: String, _p: Vector3) -> void: _progress("scoop"))
	EventBus.cube_made.connect(func(_i: Dictionary) -> void: _progress("bale"))
	EventBus.cube_cashed.connect(func(_v: BigNum, _p: Vector3) -> void: _progress("cash"))
	EventBus.upgrade_bought.connect(func(_id: String, _l: int) -> void: _progress("upgrade"))
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: _progress("hex"))
	_announce.call_deferred()
	Settings.input_device_changed.connect(func(_p: bool) -> void:  # [deck] prompts follow the device
		if not done():
			EventBus.tutorial_changed.emit(current_text()))


## [deck] "{action}" -> the binding's name on the device in use ("LMB" / "RT" / "R2").
static func glyphs(t: String) -> String:
	var out: String = t
	while "{" in out and "}" in out:
		var a: int = out.find("{")
		var b: int = out.find("}", a)
		if b < 0:
			break
		out = out.substr(0, a) + Settings.glyph(out.substr(a + 1, b - a - 1)) + out.substr(b + 1)
	return out


func done() -> bool:
	return step >= STEPS.size()


func current_text() -> String:
	if done():
		return ""
	var s: Dictionary = STEPS[step]
	var t: String = glyphs(s["text"])
	if s.has("goal"):
		t += "   %d/%d" % [mini(_count, int(s["goal"])), int(s["goal"])]
	return t


func _process(_delta: float) -> void:
	if done() or world == null:
		return
	# Steps that depend on state rather than an event.
	if STEPS[step]["id"] == "carry" and not world.patch.carried.is_empty():
		_advance()
	elif STEPS[step]["id"] == "upgrade" and GameState.level_of("compartment_size") + GameState.level_of("scoop_width") + GameState.stats.get("upgrades_bought", 0) > 0:
		_advance()


func _progress(id: String) -> void:
	if done() or STEPS[step]["id"] != id:
		# Out-of-order completions still count (e.g. the player cashes before being told).
		return
	var s: Dictionary = STEPS[step]
	if s.has("goal"):
		_count += 1
		EventBus.tutorial_changed.emit(current_text())
		if _count < int(s["goal"]):
			return
	_advance()


func _advance() -> void:
	step += 1
	_count = 0
	GameState.flags["tutorial_step"] = step
	Audio.play("ding", 1.2, -12.0)
	_announce()


func _announce() -> void:
	EventBus.tutorial_changed.emit(current_text())
	if done():
		EventBus.toast.emit("Restart checklist complete. Lumi is back on the job.", "story")
