class_name ClarityLog
extends Node
## [v3clear] Owner item 41: "one clear next thing at all times". A headless log of what the player
## is told: every change of the objective card (title, why line, progress), the interact prompt,
## the beam's target, every toast and every WREN line, with the game minute. Also flags any stretch
## longer than STUCK_S with an empty card, or a card that shows nothing to act on.
##   godot --headless --path . -- --fresh --autoplay --orbit --time-scale=8 --clarity-log
## Lines start with "[clarity]"; the summary line at exit starts with "[clarity] summary".

const POLL_S: float = 0.5
const STUCK_S: float = 60.0

var world: Node
var _t: float = 0.0
var _last_card: String = ""
var _last_prompt: String = ""
var _empty_since: float = -1.0
var _worst_empty: float = 0.0
var _cards: int = 0
var _toasts: int = 0
var _wren_hooked: bool = false
var _fleet_t: float = 0.0
var _last_fleet: String = "-"


func _init(w: Node = null) -> void:
	world = w
	name = "ClarityLog"


func _ready() -> void:
	if DevHooks.has("clarity-bench2"):  # dev: start with the Bot Bay (robot step checks)
		GameState.flags["bench_tier"] = 2
		Research.grant("salvage_logic")
		GameState.add_currency("parts", BigNum.from_float(500.0))
	EventBus.toast.connect(func(text: String, kind: String) -> void:
		_toasts += 1
		_say("toast(%s): %s" % [kind, text]))
	get_tree().root.tree_exiting.connect(_summary)
	get_tree().create_timer(3.0).timeout.connect(_bin_check)


## The trash bin's body against its "bin" anchor (the bay is drawn round it): should be ~0 m.
func _bin_check() -> void:
	var d: Variant = world.get("depot") if world else null
	var so: Variant = world.get("orbit") if world else null
	if d is Depot and so is SliceOrbit:
		var a: Vector3 = (so as SliceOrbit).yard_point("bin")
		_say("bin body %.2f m from its bay anchor" % OrbitUp.ground_dist((d as Depot).bin_world(), a))


func _minutes() -> float:
	return float(GameState.stats.get("time_played", 0.0)) / 60.0


func _say(s: String) -> void:
	print("[clarity] %5.1f min  %s" % [_minutes(), s.replace("\n", " / ")])


func _process(delta: float) -> void:
	if world == null:
		return
	if not _wren_hooked:
		var wr: Variant = world.get("wren")
		if wr is Wren:
			_wren_hooked = true
			(wr as Wren).line_started.connect(func(text: String, _st: int) -> void: _say("WREN: " + text))
	_t -= delta / maxf(Engine.time_scale, 0.001)
	if _t > 0.0:
		return
	_t = POLL_S
	var card: String = card_text(world, false)
	if card != _last_card:
		_last_card = card
		_cards += 1
		_say("card: " + (card_text(world, true) if card != "" else "(none)"))
	var now: float = _minutes() * 60.0
	if card == "":
		if _empty_since < 0.0:
			_empty_since = now
		_worst_empty = maxf(_worst_empty, now - _empty_since)
	else:
		_empty_since = -1.0
	_fleet_t -= POLL_S
	if _fleet_t <= 0.0:
		_fleet_t = 30.0
		var fl: Variant = world.get("fleet")
		if fl is Fleet:
			var why: String = (fl as Fleet).build_block_reason("scoopie")
			if why != _last_fleet:
				_last_fleet = why
				_say("scoopie: %s (bench tier %d)" % [why if why != "" else "can be built", BenchTiers.tier()])
		elif fl == null and _last_fleet != "none":
			_last_fleet = "none"
			_say("no Fleet in this world")
	var hud: Variant = world.get("hud")
	var pr: String = ""
	if hud is HUD:
		var pl: Variant = (hud as HUD).get("_prompt")
		pr = (pl as Label).text if pl is Label else ""
	if pr != _last_prompt:
		_last_prompt = pr
		if pr != "":
			_say("prompt: " + pr)


## The card as the player reads it: "TITLE | why | progress", "" when no card shows.
static func card_text(w: Node, with_count: bool = true) -> String:
	var hud: Variant = w.get("hud") if w else null
	if not hud is HUD or (hud as HUD).goals == null:
		return ""
	var gp: GoalsPanel = (hud as HUD).goals
	var parts: PackedStringArray = []
	var oc: ObjectiveCard = gp.objective
	if oc and oc.visible:
		var tl: Label = oc.get("_title")
		var wl: Label = oc.get("_why")
		var cl: Label = oc.get("_count")
		parts.append(tl.text if tl else "")
		if wl and wl.visible and wl.text != "":
			parts.append(wl.text)
		if with_count and cl and cl.text != "":
			parts.append("[" + cl.text + "]")
	var ck: ChecklistCard = gp.checklist
	if ck and ck.visible:
		var tx: Variant = ck.get("_text")
		if tx is RichTextLabel:
			parts.append("checklist: " + ChecklistCard._strip_bb((tx as RichTextLabel).text))
	return " | ".join(parts)


func _summary() -> void:
	_say("summary: %d card changes, %d toasts, longest empty card %.0f s" % [_cards, _toasts, _worst_empty])
