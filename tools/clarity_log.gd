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
var _cut: int = 0  # [v4calm]
var _wren_n: int = 0  # [v4calm]
var _wren_hooked: bool = false
var _fleet_t: float = 0.0
var _last_fleet: String = "-"
var _last_beam: String = "-"  # [v7play] the purple beam's target, as a place name


func _init(w: Node = null) -> void:
	world = w
	name = "ClarityLog"


func _ready() -> void:
	if DevHooks.has("clarity-bench2"):  # dev: start with the Bot Bay (robot step checks)
		GameState.flags["bench_tier"] = 2
		Research.grant("salvage_logic")
		GameState.add_currency("parts", BigNum.from_float(500.0))
	EventBus.toast.connect(func(text: String, kind: String) -> void:
		if Subtitles.cut(text, kind):  # [v4calm] cut toasts never show; listed so the audit sees them
			_cut += 1
			_say("cut(%s): %s" % [kind, text])
			return
		_toasts += 1
		_say("toast(%s): %s" % [kind, text]))
	get_tree().root.tree_exiting.connect(_summary)
	get_tree().create_timer(3.0).timeout.connect(_bin_check)
	if DevHooks.has("clarity-bench"):  # dev: open the workbench after S s (workbench shots)
		get_tree().create_timer(DevHooks.get_f("clarity-bench", 20.0), true, false, true).timeout.connect(func() -> void:
			if Camp.of(world):
				Camp.of(world).repair_now()
			world.call("open_upgrades"))


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
			(wr as Wren).line_out.connect(func(text: String, _st: int) -> void:  # [v4calm] what reaches the screen
				_wren_n += 1
				_say("WREN: " + text))
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
	var beam: String = beam_text(world)  # [v7play] the header promised the beam's target: log it
	if beam != _last_beam:
		_last_beam = beam
		_say("beam: " + beam)
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
		var rd: Array[String] = oc.read()  # [v9d] title, why, hint or cost chips, count
		var wl: Label = oc.get("_why")
		parts.append(rd[0])
		if wl and wl.visible and wl.text != "":
			parts.append(wl.text)
		if rd[2] != "":
			parts.append("> " + rd[2])
		if with_count and rd[3] != "":
			parts.append("[" + rd[3] + "]")
	var ck: ChecklistCard = gp.checklist
	if ck and ck.visible:
		var tx: Variant = ck.get("_text")
		if tx is RichTextLabel:
			parts.append("checklist: " + ChecklistCard._strip_bb((tx as RichTextLabel).text))
	return " | ".join(parts)


## [v7play] Where the purple beam stands, named by the nearest yard object (bin, bench, rocket,
## a hub's pad) within 6 m, else "site N (x, z)" in that site's metres; "none" when no beam shows.
static func beam_text(w: Node) -> String:
	var ob: Variant = w.get("objectives") if w else null
	if not ob is Objectives:
		return "none"
	var t: Variant = (ob as Objectives).waypoint_target()
	if not t is Vector3:
		return "none"
	var pos: Vector3 = t
	var named: Array = []
	var bp: Variant = Objectives.bin_point(w)
	if bp is Vector3:
		named.append(["bin", bp])
	var so: Variant = w.get("orbit")
	if so is SliceOrbit:
		named.append(["bench", (so as SliceOrbit).bench_position()])
	var os_: OrbitSites = OrbitSites.of(w)
	if os_ and os_.rocket_spot and os_.rocket_spot.visible:
		named.append(["rocket", os_.rocket_spot.global_position])
	if os_ and os_.purpose:
		var fb: Variant = os_.purpose.bench_point()
		if fb is Vector3:
			named.append(["field bench", fb])
	for n: Array in named:
		if (n[1] as Vector3).distance_to(pos) < 6.0:
			return str(n[0])
	if os_ and os_.sm:
		var best: int = -1
		var bd: float = INF
		for i: int in os_.sm.sites.size():
			var d: float = os_.sm.pad_xf(i).origin.distance_to(pos)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			var lp: Vector3 = os_.sm.pad_xf(best).affine_inverse() * pos
			return "site %d (%.0f, %.0f)" % [best, lp.x, lp.z]
	return "(%.0f, %.0f, %.0f)" % [pos.x, pos.y, pos.z]


func _summary() -> void:
	_say("summary: %d card changes, %d toasts (%d cut), %d WREN lines, longest empty card %.0f s" % [_cards, _toasts, _cut, _wren_n, _worst_empty])
