class_name Tutorial
extends Node
## Lumi's restart checklist: a diegetic, step-by-step tutorial told by his own systems.
## Each step teaches exactly one thing and points at it in the world (TutorialMarker: a soft ring and
## chevron on the junk, the bale, the scale, the workbench...). The HUD shows it as a compact card
## (ui/checklist_card.gd). Each step completes on a gameplay event; progress persists in GameState.flags.

# l10n:begin
const STEPS: Array[Dictionary] = [
	{"id": "repair", "text": "{interact}  at the workbench to repair it"},
	{"id": "scoop", "text": "Hold  {scoop}  to scoop junk", "goal": 8},
	{"id": "dump", "text": "Empty your chest into the trash bin"},
	{"id": "upgrade", "text": "{interact}  at the workbench to upgrade"},
]
# [onboard2] QA P2: every early step uses what Lumi has at the start (the broken bench, his scoop,
# the trash bin). Bales come later, with the Baler (story objectives, data/objectives.json).
# [onboard] "Clean this hex completely" is now the story objective "Clean a hex" (story/objectives.gd),
# which outlines its hex on the ground; an old save on that step simply counts the checklist as done.
const DONE_TEXT: String = "Lumi is back on the job"
# l10n:end

const TARGET_REFRESH_S: float = 0.2

var world: Node
var step: int = 0
var marker: TutorialMarker
var _count: int = 0
var _target_t: float = 0.0


func _ready() -> void:
	step = int(GameState.flags.get("tutorial_step", 0))
	EventBus.junk_scooped.connect(func(_t: String, _p: Vector3) -> void: _progress("scoop"))
	EventBus.upgrade_bought.connect(func(_id: String, _l: int) -> void: _progress("upgrade"))
	if not done():
		marker = TutorialMarker.new()
		marker.world = world
		add_child(marker)
	_announce.call_deferred()
	Settings.input_device_changed.connect(func(_p: bool) -> void:  # [deck] prompts follow the device
		if not done():
			EventBus.tutorial_changed.emit(current_text()))


## [deck] "{action}" -> the binding's name on the device in use ("LMB" / "RT" / "R2").
static func glyphs(t: String) -> String:
	return _glyphs(t, false)


## [first] Same, with each glyph as a coloured BBCode key for the checklist card.
static func glyphs_bb(t: String) -> String:
	return _glyphs(t, true)


static func _glyphs(t: String, bb: bool) -> String:
	var out: String = t
	while "{" in out and "}" in out:
		var a: int = out.find("{")
		var b: int = out.find("}", a)
		if b < 0:
			break
		var g: String = Settings.glyph(out.substr(a + 1, b - a - 1))
		if bb:
			g = "[color=#ffb347]%s[/color]" % g
		out = out.substr(0, a) + g + out.substr(b + 1)
	return out


func done() -> bool:
	return step >= STEPS.size()


func step_id() -> String:
	return "" if done() else str(STEPS[step]["id"])


## Step text with key glyphs (BBCode colour), no counter.
func current_text() -> String:
	if done():
		return ""
	return glyphs_bb(tr(str(STEPS[step]["text"])))


## Progress of the current step 0..1 and its label ("3 / 8", "62%"), or [-1, ""] for one-shot steps.
func step_progress() -> Array:
	if done():
		return [-1.0, ""]
	var s: Dictionary = STEPS[step]
	if s.has("goal"):
		var g: int = int(s["goal"])
		return [float(mini(_count, g)) / g, "%d / %d" % [mini(_count, g), g]]
	return [-1.0, ""]


func _process(delta: float) -> void:
	if done() or world == null:
		return
	# Steps that depend on state rather than an event.
	if STEPS[step]["id"] == "repair" and Camp.bench_ok() and not _camp_repairing():
		_advance()
		return
	elif STEPS[step]["id"] == "dump" and int(GameState.stats.get("junk_dumps", 0)) > 0:
		_advance()
		return
	elif STEPS[step]["id"] == "upgrade" and GameState.level_of("compartment_size") + GameState.level_of("scoop_width") + GameState.stats.get("upgrades_bought", 0) > 0:
		_advance()
		return
	_target_t -= delta
	if _target_t <= 0.0 and marker:
		_target_t = TARGET_REFRESH_S
		var t: Dictionary = target()
		if t.is_empty():
			marker.clear()
		else:
			marker.set_target(t["pos"], str(t["kind"]))


## Where the current step points in the world: {pos, kind} (kind: "piece", "self", "bale", "pad",
## "bench"), or {} when there is nothing to point at.
func target() -> Dictionary:
	if done() or world == null or world.patch == null:
		return {}
	var p: Patch = world.patch
	var at: Vector3 = p.global_position
	var f: HexField = world.field
	match str(STEPS[step]["id"]):
		"scoop":
			var pid: int = f.nearest_alive(at)
			if pid >= 0:
				return {"pos": f.piece_pos[pid], "kind": "piece"}
		"repair":
			return {"pos": world.BOARD_POS, "kind": "bench"}
		"dump":
			if p.compartment.is_empty():
				var pid2: int = f.nearest_alive(at)
				return {} if pid2 < 0 else {"pos": f.piece_pos[pid2], "kind": "piece"}
			if world.get("depot") != null:
				return {"pos": (world.depot as Node3D).global_position, "kind": "pad"}
		"upgrade":
			return {"pos": world.BOARD_POS, "kind": "bench"}
	return {}


func _camp_repairing() -> bool:
	var c: Variant = world.get_node_or_null("Camp") if world else null
	return c is Camp and (c as Camp).repairing


func _nearest_loose_cube(at: Vector3) -> JunkCube:
	var best: JunkCube = null
	var bd: float = INF
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n as JunkCube
		if c == null or c.carried or c.claimed:
			continue
		var d: float = c.global_position.distance_squared_to(at)
		if d < bd:
			bd = d
			best = c
	return best


func _progress(id: String) -> void:
	if done() or STEPS[step]["id"] != id:
		# Out-of-order completions still count (e.g. the player cashes before being told).
		return
	var s: Dictionary = STEPS[step]
	if s.has("goal"):
		_count += 1
		if _count < int(s["goal"]):
			return
	_advance()


func _advance() -> void:
	step += 1
	_count = 0
	_target_t = 0.0
	GameState.flags["tutorial_step"] = step
	if DevHooks.has("autoplay"):  # pacing log
		print("[onboard] checklist step %d done at %.1f min" % [step, float(GameState.stats.get("time_played", 0.0)) / 60.0])
	Audio.play("ding", 1.2, -12.0)
	_announce()


func _announce() -> void:
	EventBus.tutorial_changed.emit(current_text())
	if done() and marker:
		marker.finish()
		marker = null
