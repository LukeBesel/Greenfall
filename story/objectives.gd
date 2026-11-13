class_name Objectives
extends Node
## [onboard] Why Lumi cleans, and what to do next: the first-minutes story objectives.
## Right after the intro WREN, the Cradle's caretaker AI, sends one last crackly message
## (data/objectives.json "brief"): the pod and relay are down, bale junk to power the old base,
## build a signal tower so she can reach him. Then she is silent until the tower stands
## (story/signal_tower.gd, Wren's signal gate). The card carries the reasons from there.
## Then one objective at a time shows on the HUD card (ui/objective_card.gd) with a one-line why.
## Objectives that target a hex outline it on the ground (story/objective_hex.gd) with its % clean
## and, for the last few pieces, point at what is left (TutorialMarker).
## Also explains the part detector's signal the first time it matters.
## Persisted in GameState.flags: objective_step, onboard_brief, signal_explained.

signal changed(index: int)
signal completed(index: int)

const PATH: String = "res://data/objectives.json"
const REFRESH_S: float = 0.25
## The card waits this long after a completion before the next objective slides in.
const NEXT_DELAY_S: float = 1.5
## The last pieces of a target hex get the amber pointer once this much is clean.
const POINT_AT: float = 0.7

var world: Node
var chain: Array = []
var brief_lines: Array = []
var wren_brief: Array = []  ## [v2guide] WREN's briefing once the tower carries her
var step: int = 0
var revealed: bool = false
var target_hex: int = -1
var outline: ObjectiveHex
var focus_outline: ObjectiveHex  ## the hex Lumi stands in: a dimmer laser border, no label
var waypoint: Waypoint
var marker: TutorialMarker
var _t: float = 0.0
var _hold: float = 0.0
var _dev_cleaned: bool = false


## [onboard2] Objectives added in front of "power" (see _ready's save migration).
const EARLY_ADDED: int = 4


func _ready() -> void:
	EventBus.upgrade_bought.connect(_on_upgrade_bought)  # [v1guide] the bale how-to
	var cfg: Dictionary = Economy.read_json(PATH)
	chain = PlanetSteps.objectives(cfg.get("objectives", []))  # [v7planet] a planet's own hub steps (story/planet_steps.gd); Verdance's as they are
	brief_lines = (cfg.get("brief", {}) as Dictionary).get("lines", [])
	wren_brief = (cfg.get("wren_brief", {}) as Dictionary).get("lines", [])  # [v2guide]
	step = int(GameState.flags.get("objective_step", 0))
	# [onboard2] Four early objectives (bin, Scoop Size, Compartment, Baler) were put in front: a save
	# from before keeps its place in the chain; a save that never sold a bale starts at them.
	if not GameState.flags.has("objectives_v2"):
		if GameState.flags.has("objective_step") and (step > 0 or int(GameState.stats.get("cubes_cashed", 0)) > 0):
			step += EARLY_ADDED
			GameState.flags["objective_step"] = step
		GameState.flags["objectives_v2"] = true
	_drop_zone_step()  # [v8bot]
	if DevHooks.has("objective"):  # dev: jump to objective N (shots)
		step = clampi(int(DevHooks.get_f("objective", 0.0)), 0, chain.size())
		GameState.flags["objective_step"] = step
		GameState.flags["onboard_brief"] = true
		GameState.flags["tutorial_step"] = Tutorial.STEPS.size()  # [v1guide] past the checklist: the waypoint shows
	if DevHooks.has("near-part"):  # dev: start a few metres from a buried part (signal shots)
		_dev_near_part.call_deferred()
	outline = ObjectiveHex.new()
	outline.world = world
	add_child(outline)
	focus_outline = ObjectiveHex.new()
	focus_outline.world = world
	focus_outline.strength = 0.5
	add_child(focus_outline)
	waypoint = Waypoint.new()
	waypoint.world = world
	add_child(waypoint)
	if not GameState.flags.get("onboard_brief", false) and _veteran():
		GameState.flags["onboard_brief"] = true  # an older save: no brief, no toasts for the backlog
	if GameState.flags.get("onboard_brief", false):
		revealed = true
		_catch_up()
	else:
		var intro: Variant = world.get("intro") if world else null
		if intro is Intro and (intro as Intro).should_play():
			# [intro3] The intro plays the brief at the crash itself; afterwards only the card shows
			# (or the brief plays here if the intro was skipped before it).
			(intro as Intro).finished.connect(func() -> void:
				if (intro as Intro).brief_played:
					_reveal()
				else:
					_brief_after(1.2))
		else:
			_brief_after(2.0)


## [v8bot] Owner: a Scoopie just goes and cleans on its own, so the story no longer asks the
## player to paint it a zone. The "zone" step stood right before "hex2"; a save from before that
## sits on it (now "hex2": the step is skipped) or past it (one step fewer in front: step - 1).
func _drop_zone_step() -> void:
	if GameState.flags.has("objectives_v3"):
		return
	GameState.flags["objectives_v3"] = true
	if not GameState.flags.has("objective_step"):
		return
	var at: int = -1
	for i: int in chain.size():
		if str((chain[i] as Dictionary).get("id", "")) == "hex2":
			at = i
			break
	if at >= 0 and step > at:
		step -= 1
		GameState.flags["objective_step"] = step


## A save from before the objectives existed (or well past them).
func _veteran() -> bool:
	return int(GameState.stats.get("cubes_cashed", 0)) >= 3 or int(GameState.flags.get("tutorial_step", 0)) >= Tutorial.STEPS.size()


## Completes, silently, every objective that already holds (loading a save).
func _catch_up() -> void:
	while step < chain.size() and value_of(chain[step]) >= target_of(chain[step]):
		step += 1
	GameState.flags["objective_step"] = step


func _brief_after(delay: float) -> void:
	if not is_inside_tree():
		return
	get_tree().create_timer(delay).timeout.connect(_play_brief)


## WREN's plan, then the card. The card shows when her last line starts (or after a while).
func _play_brief() -> void:
	if revealed:
		return
	GameState.flags["onboard_brief"] = true
	var w: Wren = _wren()
	if w == null or brief_lines.is_empty():
		_reveal()
		return
	var last: String = tr(str(brief_lines[-1]))
	# [intro3] Not CONNECT_ONE_SHOT: that dropped the handler on the first line, so the card only
	# came after the 30 s fallback.
	var on_line := func(text: String, _st: int) -> void:
		if text == last:
			_reveal()
	w.line_started.connect(on_line)
	changed.connect(func(_s: int) -> void:
		if w.line_started.is_connected(on_line):
			w.line_started.disconnect(on_line), CONNECT_ONE_SHOT)
	for l: Variant in brief_lines:
		w.speak(tr(str(l)), 0, true)  # her last message: crackly (stage 0), and it gets through
	get_tree().create_timer(30.0).timeout.connect(_reveal)


func _reveal() -> void:
	if revealed:
		return
	revealed = true
	_catch_up()
	changed.emit(step)


func _wren() -> Wren:
	var w: Variant = world.get("wren") if world else null
	return w as Wren if w is Wren else null


# --- State ------------------------------------------------------------------------------------

func done() -> bool:
	return step >= chain.size() and _goal_index() < 0


# --- [v1guide] One goal timeline ---------------------------------------------------------------
# Owner 2026-11-08: ONE list of goals. The story objectives come first; after them the goal chain
# (data/goals.json) continues on the same card, one step at a time. Goals that already hold when a
# step finishes are folded into it (their rewards paid with it), so nothing completes on its own
# in the background.

func goals() -> Goals:
	return world.get("goals") as Goals if world else null


## The goal chain index on the card once the story objectives are done (-1: none / not yet).
func _goal_index() -> int:
	var g: Goals = goals()
	if g == null or step < chain.size():
		return -1
	var c: Array[int] = g.current()
	return c[0] if not c.is_empty() else -1


## A position on the timeline that changes with every finished step (the card's fade key).
func position() -> int:
	var g: Goals = goals()
	return step + (g.done_count() if g else 0)


## Quietly completes every goal that already holds; "" or "  +N cubes" for the notice.
func _fold_goals() -> String:
	var g: Goals = goals()
	if g == null:
		return ""
	var r: Dictionary = g.absorb()
	var txt: String = GoalsPanel.reward_text(r, 1.0) if not r.is_empty() else ""
	return ("    " + txt) if txt != "" else ""


## The step on the card ({} when there is none: not revealed yet, or all done). A goal step is a
## copy of its goals.json entry with "_goal" (its index) and its reward as the why line.
func current() -> Dictionary:
	if not revealed:
		return {}
	if step < chain.size():
		return chain[step]
	var gi: int = _goal_index()
	if gi < 0:
		return {}
	var g: Goals = goals()
	var d: Dictionary = (g.chain[gi] as Dictionary).duplicate()
	d["_goal"] = gi
	var rw: String = GoalsPanel.reward_text(g.reward_of(gi), 1.0)
	d["desc"] = (tr("Reward: %s") % rw) if rw != "" else ""
	var why: String = goal_reason(d)  # [v6story] the in-world reason first, then the reward
	if why != "":
		d["desc"] = TranslationServer.translate(why) + ("\n" + str(d["desc"]) if str(d["desc"]) != "" else "")
	return d


## [v6story] Owner item 60: every goal says why. The English reason line for a goals.json entry
## (data/story_reasons.json goal_reasons): by id, else by kind ("type:key"), else by type, else the default.
static var _reasons: Dictionary = {}
static func goal_reason(g: Dictionary) -> String:
	if _reasons.is_empty():
		_reasons = (Economy.read_json("res://data/story_reasons.json") as Dictionary).get("goal_reasons", {})
	var by_id: Dictionary = _reasons.get("by_id", {})
	var by_kind: Dictionary = _reasons.get("by_kind", {})
	var by_type: Dictionary = _reasons.get("by_type", {})
	var typ: String = str(g.get("type", "stat"))
	var kind: String = "%s:%s" % [typ, str(g.get("key", ""))]
	if by_id.has(str(g.get("id", ""))):
		return str(by_id[str(g.get("id", ""))])
	var by_prefix: Dictionary = _reasons.get("by_prefix", {})
	for pre: String in by_prefix:
		if str(g.get("id", "")).begins_with(pre):
			return str(by_prefix[pre])
	if by_kind.has(kind):
		return str(by_kind[kind])
	return str(by_type.get(typ, _reasons.get("default", "")))


func target_of(def: Dictionary) -> float:
	if def.has("_goal") and goals():
		return goals().target_of(int(def["_goal"]))
	return float(def.get("target", 1))


func value_of(def: Dictionary) -> float:
	if def.has("_goal") and goals():
		return goals().value_of(int(def["_goal"]))
	var key: String = str(def.get("key", ""))
	match str(def.get("type", "stat")):
		"stat":
			var v: Variant = GameState.stats.get(key, 0.0)
			return float(v) if (v is float or v is int) else 0.0
		"robot":
			var fl: Node = world.get("fleet") if world else null
			if fl == null:
				return 0.0
			return float(fl.call("robot_total")) if key == "any" else float(fl.call("count", key))  # [v3qa] globe crews count
		"zone":
			return float(Goals.zone_hex_count())
		"hub_level":
			return float(GameState.world.get("hub_level", 1))
		"flag":
			return 1.0 if GameState.flags.get(key, false) else 0.0
		"core":
			return float(GameState.flags.get("core_charge", 0.0))
		"tower":
			return float(SignalTower.tier())
		"upgrade":  # [onboard2] an upgrade's level (Scoop Size, Compartment, the Baler)
			return float(GameState.level_of(key))
		"bench":  # [v1guide] the workbench's tier (ui/bench_tiers.gd)
			return float(BenchTiers.tier())
	return 0.0


## [v6pace] The English why line of a story step: its own desc, else (the hub, wake and rocket steps,
## which carry none) its reason from data/story_reasons.json, the same line the goal steps show.
static func step_why(def: Dictionary) -> String:
	var d: String = str(def.get("desc", ""))
	if d != "" or def.has("_goal"):
		return d
	if str(def.get("why", "")) != "":  # [v7planet] a generated hub step's own reason (story/planet_steps.gd)
		return str(def["why"])
	var r: String = goal_reason(def)
	return "" if r == str(_reasons.get("default", "")) else r


## [v6pace] WREN's lines as a story step starts: its own, else (a step with no desc) its story reason.
static func step_lines(def: Dictionary) -> Array:
	var ls: Array = def.get("lines", [])
	if ls.is_empty() and not def.has("desc") and step_why(def) != "":
		return [step_why(def)]
	return ls


## Card text for an objective: [title, why]. The why is the "hint" until its wait_flag is set.
static func texts(def: Dictionary) -> Array[String]:
	var why: String = step_why(def)
	var wf: String = str(def.get("wait_flag", ""))
	if wf != "" and not GameState.flags.get(wf, false) and def.has("hint"):
		why = str(def["hint"])
	return [TranslationServer.translate(str(def.get("text", ""))), glyphs(TranslationServer.translate(why))]


## [v1guide] "{cube}" style action names in a why line become the current key glyph ([C], [X]...).
static func glyphs(text: String) -> String:
	var i: int = text.find("{")
	while i >= 0:
		var j: int = text.find("}", i)
		if j < 0:
			break
		var act: String = text.substr(i + 1, j - i - 1)
		if not InputMap.has_action(act):
			i = text.find("{", j)
			continue
		var g: String = "[%s]" % Settings.glyph(act)
		text = text.substr(0, i) + g + text.substr(j + 1)
		i = text.find("{", i + g.length())
	return text


## Progress of the current objective: [0..1 or -1 for none, label]. Hex objectives show the target
## hex's % clean; counts show "1 / 3".
## [v7play] Stat keys whose target is an ordinal (the Nth station, tier N), not a count to fill.
const ORDINAL_KEYS: Array[String] = ["hubs_woken", "hubs_seen", "drive_tier", "rocket_tier"]


func progress() -> Array:
	var def: Dictionary = current()
	if def.is_empty():
		return [-1.0, ""]
	if def.get("hex", false):
		var f: float = hex_fraction()
		return [f, "%d%%" % int(floor(f * 100.0))] if target_hex >= 0 else [0.0, ""]
	var wf: String = str(def.get("wait_flag", ""))
	if wf != "" and not GameState.flags.get(wf, false):
		return [-1.0, ""]
	if str(def.get("type", "")) == "bench" and BenchTiers.tier() < int(def.get("target", 2)):  # [v1guide] saving up: cubes toward the tier
		var need: float = float(BenchTiers.next_cost().get("cubes", 0.0))
		if need > 0.0:
			var have: float = minf(GameState.get_currency("cubes").to_float(), need)
			return [have / need, "%s / %s" % [Settings.fmt(BigNum.from_float(have)), Settings.fmt(BigNum.from_float(need))]]
	var tgt: float = target_of(def)
	var v: float = minf(value_of(def), tgt)
	if v < tgt and str(def.get("type", "")) in ["stat", "robot", "hub_level", "upgrade", "tower"]:
		# [v6pace] Saving up for the step's price: cubes toward it, a number that goes up (owner: a
		# visible goal with a number at all times). Once it's covered, the step's own count again.
		var pc: Dictionary = _step_price()
		var need_c: float = float(pc.get("cubes", 0.0))
		var have_c: float = GameState.get_currency("cubes").to_float()
		if need_c > 0.0 and have_c < need_c:
			return [have_c / need_c, "%s / %s" % [Settings.fmt(BigNum.from_float(have_c)), Settings.fmt(BigNum.from_float(need_c))]]
	if str(def.get("type", "")) == "core":
		return [v / maxf(tgt, 0.0001), "%d%%" % int(floor(v * 100.0))]
	if v < tgt and str(def.get("key", "")) in ORDINAL_KEYS and not _step_price().is_empty():
		# [v7play] One action left (wake this station, build this drive): its target is a station or tier
		# number, so "Wake station 6 of 6 [4 / 5]" and "Build the Mk V drive [0 / 5]" read wrong. Price covered: full bar, no count.
		return [1.0, ""]
	return [v / maxf(tgt, 0.0001), ("%d / %d" % [int(v), int(tgt)]) if tgt > 1.0 else ""]


func hex_fraction() -> float:
	if target_hex < 0 or world == null or world.field == null:
		return 0.0
	return (world.field as HexField).removed_fraction(target_hex)


# --- Frame ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null:
		return
	_update_focus()
	var gl: Goals = goals()
	if gl and not gl.driven:
		gl.driven = true  # [v1guide] the card drives the goals: one step at a time
	if not revealed:
		return
	_explain_signal()
	_narrate()  # [v2guide]
	_bale_reminder(delta)
	_hold = maxf(0.0, _hold - delta)
	_t -= delta
	if _t > 0.0:
		return
	_t = REFRESH_S
	var def: Dictionary = current()
	situation = situation_hint(REFRESH_S)  # [v3clear]
	waypoint.set_target(waypoint_target())
	if def.is_empty() or _hold > 0.0:
		_set_hex(-1)
		return
	if value_of(def) >= target_of(def):
		complete()
		return
	if def.get("hex", false) or str(step_target(def).get("to", "")) == "hex":  # [v1guide] every step on dirty ground gets its hex
		_set_hex(_pick_hex())
		if DevHooks.has("objective-clean") and target_hex >= 0 and not _dev_cleaned:  # dev: part-clean it
			_dev_cleaned = true
			_dev_clean(clampf(DevHooks.get_f("objective-clean", 0.4), 0.0, 0.95))
		_point_at_last()
	else:
		_set_hex(-1)


func complete() -> void:
	if done():
		return
	if step >= chain.size():
		_complete_goal()
		return
	var i: int = step
	var t: Array[String] = texts(chain[i])
	step += 1
	GameState.flags["objective_step"] = step
	if DevHooks.has("autoplay"):  # pacing log
		print("[onboard] objective %s done at %.1f min" % [str(chain[i].get("id", "")), float(GameState.stats.get("time_played", 0.0)) / 60.0])
	_hold = NEXT_DELAY_S
	_set_hex(-1)
	var folded: String = _fold_goals()  # [v1guide] goals that already hold ride along
	var hud: Variant = world.get("hud") if world else null
	if hud != null and (hud as Object).has_method("notify"):
		hud.call("notify", (tr("Objective complete  ·  %s") % t[0]) + folded, "goal")
	Audio.play("chime", 1.2, -8.0)
	completed.emit(i)
	if not done():
		get_tree().create_timer(NEXT_DELAY_S).timeout.connect(func() -> void:
			changed.emit(step))  # [v2guide] WREN's line for the step: _narrate
	else:
		changed.emit(step)


## [v1guide] A goal step is done: pay it (Goals.complete), fold in the ones that already hold, and
## bring the next step after the beat.
func _complete_goal() -> void:
	var gi: int = _goal_index()
	var g: Goals = goals()
	if gi < 0 or g == null:
		return
	var text: String = tr(str(g.chain[gi].get("text", "")))
	var rw: String = GoalsPanel.reward_text(g.reward_of(gi), 1.0)
	g.complete(gi)
	var folded: String = ""  # [v5play] a goal step pays itself only: goals that already hold come up next, one per step
	if DevHooks.has("autoplay"):
		print("[onboard] goal %s done at %.1f min" % [str(g.chain[gi].get("id", "")), float(GameState.stats.get("time_played", 0.0)) / 60.0])
	_hold = NEXT_DELAY_S
	_set_hex(-1)
	var hud: Variant = world.get("hud") if world else null
	if hud != null and (hud as Object).has_method("notify"):
		hud.call("notify", tr("Goal complete  ·  %s") % text + (("    " + rw) if rw != "" else "") + folded, "goal")
	completed.emit(step)
	get_tree().create_timer(NEXT_DELAY_S).timeout.connect(func() -> void: changed.emit(step))


# --- The target hex -----------------------------------------------------------------------------

func _hex_ok(h: int) -> bool:
	var f: HexField = world.field
	return h >= 0 and h < f.hex_count() and not f.is_clean(h) and f.hex_hub[h] == 0 and not f.is_water(h) and not f.locked.has(h) and Pace.hex_clearable(f, h)  # [v2feel] clearable now


## The hex to finish: kept while it is unfinished, so the outline doesn't flicker as Lumi walks.
## Moves to the hex Lumi is working on once that one is clearly further along, or when Lumi has
## wandered off; otherwise the most-cleared unfinished hex near him.
func _pick_hex() -> int:
	var f: HexField = world.field
	var p: Patch = world.patch
	if f == null or p == null:
		return -1
	var at: Vector3 = p.global_position
	var fh: int = p.focus_hex()
	var h: int = target_hex
	if _hex_ok(h):
		if fh != h and _hex_ok(fh) and f.removed_fraction(fh) > f.removed_fraction(h) + 0.15:
			h = fh
		elif OrbitUp.ground_dist(at, f.hex_center(h)) > f.hex_size * 6.0:  # [orbB] along the ground
			h = -1
	else:
		h = -1
	if h < 0:
		if _hex_ok(fh):
			h = fh
		else:
			var best: float = -INF
			for hid: int in f.hexes_near(at, 2):
				if not _hex_ok(hid):
					continue
				var score: float = f.removed_fraction(hid) - f.hex_center(hid).distance_to(at) * 0.01
				if score > best:
					best = score
					h = hid
			if h < 0:  # [v9c] a far station's pad stands in its town: its junk starts 4+ hexes out, so look wider (nearest first)
				var bd: float = INF
				for hid: int in f.hexes_near(at, 6):
					if not _hex_ok(hid):
						continue
					var dd: float = OrbitUp.ground_dist(at, f.hex_center(hid))
					if dd < bd:
						bd = dd
						h = hid
	return h


func _set_hex(h: int) -> void:
	target_hex = h
	if outline:
		outline.set_hex(h)
	if h < 0 and marker:
		marker.clear()


## The last few pieces of the target hex: the amber pointer, so the last can is never a hunt.
## [v2guide] Owner playtest 2 #37: no pointer on the last pieces of a hex (the outline is enough),
## so this only clears the old amber pointer (saves made while it showed).
func _point_at_last() -> void:
	if marker:
		marker.clear()


# --- Focus outline and waypoint ------------------------------------------------------------------

## The hex Lumi is standing in gets a soft laser border while it still has junk (not the
## objective's hex: that one has its own, brighter one).
func _update_focus() -> void:
	var p: Patch = world.get("patch") as Patch
	var f: HexField = world.get("field") as HexField
	if p == null or f == null or focus_outline == null:
		return
	var h: int = p.focus_hex()
	var ok: bool = h >= 0 and h < f.hex_count() and f.hex_hub[h] == 0 and not f.is_clean(h) and not f.is_water(h)
	focus_outline.set_hex(h if ok and h != target_hex else -1)


## [v1guide] Every step guides the player (owner 2026-11-08): where the beam and trail point, and
## which workbench row opens. {"to": "bench" | "depot" | "hex" | "place" | "", "pos": Vector3 or
## null, "row": [tab, row id] or []}. "hex" = the nearest dirty hex (outlined too).
const BENCH_STATS: Array[String] = ["upgrades_bought", "robots_built", "research_done", "builder_full_custom", "builder_parts_fitted",
	"decor_placed", "decor_kinds", "decor_charm_best", "greenhouses_built", "water_tanks", "heaters_placed", "drive_tier", "robots_retired", "radio_plays"]
const DEPOT_STATS: Array[String] = ["cubes_cashed", "junk_dumps", "robot_bales", "bales_recycled"]
const HEX_STATS: Array[String] = ["hexes_cleaned", "junk_scooped", "cubes_made", "perfect_cubes", "hexes_restored", "hexes_thawed",
	"plants_planted", "plants_bloomed", "garden_stipend", "eggs_found", "cats_petted"]


func step_target(def: Dictionary) -> Dictionary:
	var out: Dictionary = {"to": "", "row": []}
	if def.is_empty():
		return out
	var p: Patch = world.get("patch") as Patch if world else null
	var key: String = str(def.get("key", ""))
	var typ: String = str(def.get("type", "stat"))
	var arc: Variant = _arc_beam(def, key)  # [v7play] station and drive steps: the rocket or the landmark
	if arc is Vector3:
		return _resolve({"to": "place", "pos": arc, "row": []})
	if arc is String:  # saving up for it: out to the junk
		return _resolve({"to": str(arc), "row": []})
	if not def.has("_goal"):  # the story objectives
		match str(def.get("id", "")):
			"dump3":  # a full-ish chest: to the bin; else out to the junk
				out["to"] = "bin" if p and p.compartment.fill >= p.capacity() * 0.5 else "hex"
			"compartment", "scoop_size", "baler":  # to the bench once affordable; else earn
				var aff: bool = GameState.can_afford("cubes", Economy.upgrade_cost(key))
				out = {"to": "bench" if aff else "hex", "row": ["patch", key]}
			"power":
				out["to"] = "depot" if p and not p.carried.is_empty() else "hex"
			"tower", "tower2":
				out["row"] = ["build", "signal_tower"] if SignalTower.tier() == 0 else ["patch", "hb_signal_tower"]
				var aff2: bool = GameState.can_afford_all(SignalTower.next_cost())
				out["to"] = "bench" if aff2 else ("depot" if p and not p.carried.is_empty() else "hex")
			"glim":  # [v4calm] item 43: the Repair Glim build once it's affordable; else earn
				var aff3: bool = GameState.can_afford_all(YardBuilds.def("glim").get("cost", {}))
				out = {"to": "bench" if aff3 else ("depot" if p and not p.carried.is_empty() else "hex"), "row": ["build", "glim"]}
			"hex", "hex2", "hex3", "hex10", "hex20":  # [v3clear] hex2, hex10, hex20 [v8bot] no "zone" step
				out["to"] = "hex"
			"bench2":
				out = {"to": "bench" if BenchTiers.block_reason(world) == "" else "hex", "row": ["patch", "bench_tier"]}
			"robot":
				out = {"to": "bench", "row": ["bots", ""]}
			"haul":  # [v4bots] waits for the Haul Bug plans (Research.check_story): clean meanwhile
				out = {"to": "bench", "row": ["bots", ""]} if Research.robot_unlocked("haulbug") else {"to": "hex", "row": []}
			"research1":  # [v3clear]
				out = {"to": "bench", "row": ["research", ""]}
			"base2", "base3":
				out = {"to": "bench", "row": ["patch", "hub_level"]}
			"rocket_tier_2", "rocket_tier_3":  # [v9c] the bench opens on the rocket's row (it opened on nothing)
				out = {"to": "bench", "row": ["patch", "rocket_tier"]}
			"seed":
				if GameState.flags.get("seed_signal", false) and not GameState.flags.get("seeds_unlocked", false):
					out = {"to": "place", "pos": (world.first_seed as FirstSeed).tin_point() if world.get("first_seed") != null else FirstSeed.GREENHOUSE_POS, "row": []}  # [orbB] [v4grow] on the tin
				elif GameState.flags.get("seeds_unlocked", false) and int(GameState.stats.get("plants_planted", 0)) == 0 and world.get("first_seed") != null:
					out = {"to": "place", "pos": (world.first_seed as FirstSeed).bed_point(), "row": []}  # [v8seed] the beacon on the greenhouse beds
				elif GameState.flags.get("seeds_unlocked", false):
					out["to"] = ""  # [v4grow] planting goes on clean ground: no dirty-hex outline, no beam
				else:
					out["to"] = "hex"
			_:
				out["to"] = "bench"
		return _resolve(out)
	match typ:
		"upgrade":
			out = {"to": "bench", "row": ["patch", key]}
		"robot", "tier":
			out = {"to": "bench", "row": ["bots", ""]}
		"research":
			out = {"to": "bench", "row": ["research", key]}
		"hub_level", "bases_l5", "frontier_base":
			out = {"to": "bench", "row": ["patch", "hub_level"]}
		"districts":  # [v5play] "Launch the rocket onward": the beam stands on the rocket (base level 5 builds it)
			var so: Variant = world.get("orbit")
			var spot: Variant = (so as SliceOrbit).sites.rocket_spot if so is SliceOrbit and (so as SliceOrbit).sites != null else null
			if spot is Node3D and (spot as Node3D).visible:
				out = {"to": "place", "pos": (spot as Node3D).global_position, "row": []}
			else:
				out = {"to": "bench", "row": ["patch", "hub_level"]}
		"earned":
			out["to"] = "depot" if p and not p.carried.is_empty() else "hex"
		"hex_level", "zone", "frontier_growing":
			out["to"] = "hex"
		"flag":
			if key == "seeds_unlocked" and world.get("first_seed") != null:
				out = {"to": "place", "pos": (world.first_seed as FirstSeed).greenhouse_point(), "row": []}
			else:
				out["to"] = "hex"
		"stat":
			if key == "rocket_tier":  # [v9c] "Upgrade the rocket to Mk III": to the bench, on the rocket's row (no beam before)
				out = {"to": "bench", "row": ["patch", "rocket_tier"]}
			elif key == "junk_dumps":  # [v2guide] the chest goes into the bin's body, not onto the scale
				out["to"] = "bin" if p and not p.compartment.is_empty() else "hex"
			elif key in DEPOT_STATS:
				out["to"] = "depot" if key != "cubes_cashed" or (p and not p.carried.is_empty()) else "hex"
			elif key in BENCH_STATS:
				out = {"to": "bench", "row": ["research", ""] if key == "research_done" else (["bots", ""] if key == "robots_built" else [])}
			elif key == "shards_found":
				var sh: Variant = world.get("shards")
				var wp: Variant = (sh as ShardSystem).waypoint(p.global_position).get("pos", null) if sh is ShardSystem and p else null
				out = {"to": "place" if wp is Vector3 else "hex", "pos": wp, "row": []}
			# [v2guide] #37: no beam on parts (the detector's signal finds them)
			else:
				out["to"] = "hex"
		_:
			out["to"] = "hex"
	return _resolve(out)


func _resolve(t: Dictionary) -> Dictionary:
	match str(t.get("to", "")):
		"bench":
			t["pos"] = _bench_pos()
			var fb: Variant = field_bench()  # [v6pace] at a woken far base: its field bench by the pad
			if fb is Vector3:
				t["pos"] = fb
			elif away_rocket() is Vector3:  # at a far base with no bench: the rocket home
				t["pos"] = away_rocket()
				t["fly_home"] = true
		"depot":
			t["pos"] = _depot_pos()
		"bin":  # [v2guide]
			t["pos"] = bin_point(world)
		"hex":  # [v2guide] #37: cleaning a hex needs no beam (the hex outline shows it)
			t["pos"] = null
	return t



## The workbench row the current step asks for ([] when none).
func bench_row() -> Array:
	return step_target(current()).get("row", [])


## Where the purple beam points: the current step's target (null while the restart checklist runs:
## it has its own marker).
## [v2guide] One card, one beacon: while the restart checklist runs, its step is the card's text
## (ui/goals_panel.gd) and the beacon stands on that step's target.
func waypoint_target() -> Variant:
	if world == null or world.get("patch") == null:
		return null
	var tut: Tutorial = world.get("tutorial") as Tutorial
	if tut and not tut.done():  # #37: only places (bench, bin), never pieces
		var tt: Dictionary = tut.target()
		return tt.get("pos", null) if str(tt.get("kind", "")) in ["bench", "pad"] else null
	var pos: Variant = step_target(current()).get("pos", null)
	if pos == null and is_lost() and needs_home():  # [v3clear] lost on the way home: the beam stands on home (a place, owner #37)
		pos = away_rocket() if away_rocket() is Vector3 else home_pos()  # [v6pace] from a far base home is a rocket hop
	return pos


## [v6pace] The field bench of the woken far base Lumi is at (it works like the home one), else null.
func field_bench() -> Variant:
	var os_: OrbitSites = OrbitSites.of(world) if world else null
	if os_ == null or os_.purpose == null:
		return null
	return os_.purpose.bench_point()


## [v6pace] The rocket's spot while Lumi is at another hub than home (the way home is a hop, not a
## walk), else null.
func away_rocket() -> Variant:
	var os_: OrbitSites = OrbitSites.of(world) if world else null
	if os_ == null or os_.purpose == null or os_.purpose.site <= 0 or os_.rocket_spot == null or not os_.rocket_spot.visible:
		return null
	return os_.rocket_spot.global_position


func _bench_pos() -> Variant:
	if world.has_method("bench_pos"):  # [orbB] the globe's bench anchor too
		return world.call("bench_pos")
	var sc: Script = world.get_script() as Script
	return sc.get_script_constant_map().get("BOARD_POS", null) if sc else null


## [v2guide] The trash bin's body (the depot's chute), where the chest is emptied.
static func bin_point(w: Node) -> Variant:
	var d: Variant = w.get("depot") if w else null
	if d is Node3D and (d as Node3D).has_method("bin_world"):
		return (d as Node3D).call("bin_world")
	return (d as Node3D).global_position if d is Node3D else null


func _depot_pos() -> Variant:
	var d: Variant = world.get("depot")
	return (d as Node3D).global_position if d is Node3D else null


# --- [v2guide] WREN narrates the journey ----------------------------------------------------------
# Owner 2026-11-08 playtest 2 #34: once the signal tower carries her, WREN says who she is and the
# plan home (wren_brief), then gives one line (lines[0]) as each new story step starts. At most one
# line per step (flags.wren_steps), nothing while a modal is open (Wren holds its queue then too),
# and nothing before the tower (no backlog of step lines).

func _narrate() -> void:
	var w: Wren = _wren()
	if w == null or not w.awake() or _hold > 0.0:
		return
	if world.has_method("any_modal_open") and bool(world.call("any_modal_open")):
		return
	if not GameState.flags.get("wren_briefed", false):
		GameState.flags["wren_briefed"] = true
		for l: Variant in wren_brief:
			w.speak(tr(str(l)), w.stage())
		return
	if step >= chain.size():
		return
	var def: Dictionary = chain[step]
	if value_of(def) >= target_of(def):  # finishing right now (the tower that woke her): no line
		return
	var said: Array = GameState.flags.get("wren_steps", [])
	var id: String = str(def.get("id", ""))
	if id in said:
		return
	said.append(id)
	GameState.flags["wren_steps"] = said
	var ls: Array = step_lines(def)
	if not ls.is_empty():
		# [v6story] dropped unsaid if the step is already done when her turn comes
		w.speak(tr(str(ls[0])), w.stage(), false, func() -> bool:
			return step < chain.size() and str(chain[step].get("id", "")) == id)


# --- [v1guide] How to make a bale -----------------------------------------------------------------

## Owner 2026-11-08 #21: after the Baler there was no word on how to make a bale.
static func bale_howto() -> String:
	return TranslationServer.translate("Baler installed! Fill your chest, press [%s] to press a bale, then carry it to the scale.") % Settings.glyph("cube")


func _on_upgrade_bought(id: String, lv: int) -> void:
	if id != Pace.UP_BALER or lv < 1 or GameState.flags.get("bale_howto", false):
		return
	GameState.flags["bale_howto"] = true
	EventBus.toast.emit(bale_howto(), "hint")


var _bale_nag_t: float = 0.0


## Until the first bale is pressed: a full chest with the Baler gets the key over Lumi's head.
func _bale_reminder(delta: float) -> void:
	_bale_nag_t -= delta
	if _bale_nag_t > 0.0 or not Pace.baler_unlocked() or int(GameState.stats.get("cubes_made", 0)) > 0:
		return
	var p: Patch = world.get("patch") as Patch
	if p == null or p.compartment == null or p.compartment.fill < p.capacity() * 0.95:
		return
	_bale_nag_t = 9.0
	Vfx.float_text(p.global_position + OrbitUp.up(p.global_position) * 2.0, tr("Your chest is full. Press [%s] to make a bale.") % Settings.glyph("cube"), Color(1.0, 0.86, 0.45), 0.55, 0.6)


# --- The part detector -------------------------------------------------------------------------

## The first time the detector picks up a buried part (after the restart checklist), WREN says
## what the beeping and the HUD's BURIED PART reading mean.
func _explain_signal() -> void:
	if GameState.flags.get("signal_explained", false):
		return
	var p: Patch = world.patch
	if p == null or p.detector == null or not PartDetector.active() or p.detector.target < 0 or p.detector.strength < 0.15:
		return
	GameState.flags["signal_explained"] = true
	var w: Wren = _wren()
	if w and w.awake():  # [qafix] WREN only gets through once a tower is up; otherwise the toast says it
		w.speak(tr("Your detector's found a robot part buried nearby. Follow the BURIED PART reading; it beeps once you're right on top of it."), 1)  # [v4calm] the lamp is quiet now
	else:  # [qafix] QA P1 #2: one line, not WREN and a toast saying the same thing
		EventBus.toast.emit(tr("BURIED PART: walk toward it until the reading peaks, then dig it up."), "hint")


# --- Dev ---------------------------------------------------------------------------------------

func _dev_clean(frac: float) -> void:
	var f: HexField = world.field
	var pids: PackedInt32Array = f.hex_pieces[target_hex]
	var n: int = int(pids.size() * frac)
	for k: int in n:
		if f.piece_alive[pids[k]] == 1 and world.has_method("collect_piece"):
			world.call("collect_piece", pids[k])


func _dev_near_part() -> void:
	var f: HexField = world.field
	var p: Patch = world.patch
	var best: int = -1
	var bd: float = INF
	for i: int in f.part_pos.size():
		if f.part_found[i] == 0:
			var d: float = f.part_pos[i].distance_to(p.global_position)
			if d < bd:
				bd = d
				best = i
	if best >= 0:
		var to: Vector3 = f.part_pos[best]
		var dir: Vector3 = (p.global_position - to) * Vector3(1, 0, 1)
		dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
		p.global_position = Vector3(to.x, p.global_position.y, to.z) + dir * 6.0
		p.look_at(Vector3(to.x, p.global_position.y, to.z), Vector3.UP)


# --- [v3clear] One clear next thing (owner item 41) -------------------------------------------------
# A short line for the card's "why" slot when the player's situation says what to do better than
# the step does: a full chest, a piece too heavy, not enough cubes for the step, nothing to pick up
# nearby, or being lost. "" when the step's own line is the right one.

## Lumi is this far (along the ground) from home before the card points the way back.
const LOST_M: float = 80.0
## No liftable piece within this many metres (away from home) = nothing to pick up here.
const EMPTY_R: float = 14.0
## ...for this long before the card says so.
const EMPTY_S: float = 6.0
## A "too heavy" pulse stays on the card this long (ms).
const HEAVY_MS: int = 6000

var situation: String = ""
var _empty_t: float = 0.0
var _was_full: bool = false


func _patch() -> Patch:
	return world.get("patch") as Patch if world else null


func home_pos() -> Variant:
	var b: Variant = bin_point(world)
	return b if b is Vector3 else _bench_pos()


## Lumi has to get home for what comes next: a full chest, bales on his back, or a step at the base.
func needs_home() -> bool:
	var p: Patch = _patch()
	if p == null:
		return false
	if not p.carried.is_empty() or (p.compartment and p.compartment.fill >= p.capacity() * 0.98):
		return true
	var to: String = str(step_target(current()).get("to", ""))
	return to in ["bench", "bin", "depot"]


func is_lost() -> bool:
	var p: Patch = _patch()
	var h: Variant = home_pos()
	return p != null and h is Vector3 and OrbitUp.ground_dist(p.global_position, h) > LOST_M


## The bench item the current step wants, when its price can't be paid yet: {cubes: n, ...}.
func _step_price() -> Dictionary:
	var def: Dictionary = current()
	if def.is_empty():
		return {}
	var typ: String = str(def.get("type", ""))
	var key: String = str(def.get("key", ""))
	if typ == "upgrade" and Economy.upgrade_defs.has(key) and GameState.level_of(key) < int(def.get("target", 1)):
		return {"cubes": Economy.upgrade_cost(key).to_float()}
	if typ == "bench" and BenchTiers.tier() < int(def.get("target", 2)) and BenchTiers.block_reason(world) == "":
		return BenchTiers.next_cost()
	if typ == "tower" and SignalTower.tier() < int(def.get("target", 1)):
		return SignalTower.next_cost()
	# [v5play] Base levels and robots cost cubes and parts: say what is still missing for them too
	# (the "Rebuild the base" steps gave no hint while the parts were short).
	if typ == "hub_level" and world != null and world.get("hub") is Hub:
		var hub: Hub = world.get("hub")
		if hub.level < int(def.get("target", 2)):
			return (hub.level_def(hub.level + 1).get("cost", {}) as Dictionary).duplicate()
	if typ == "stat" and world != null and value_of(def) < target_of(def):
		var arc: Dictionary = arc_price(world, key)  # [v6pace] the hub, wake, rocket and drive steps
		if not arc.is_empty():
			return arc
	if typ == "robot" and key == "any" and world != null and world.get("fleet") is Fleet:
		# [v6pace] "Build your first robot": the price of the first robot the bench can build, so the
		# card says how many Parts are still missing (a bot run waited 20 min on it with no hint).
		var fa: Fleet = world.get("fleet")
		if fa.robot_total() < int(def.get("target", 1)):
			for rid: String in Economy.robots:
				if Research.robot_unlocked(rid):
					return {"cubes": fa.build_cost(rid).to_float(), "parts": fa.build_parts(rid).to_float()}
	if typ == "robot" and world != null and world.get("fleet") is Fleet and Economy.robots.has(key) and Research.robot_unlocked(key):
		var fl: Fleet = world.get("fleet")
		if fl.count(key) < int(def.get("target", 1)):
			return {"cubes": fl.build_cost(key).to_float(), "parts": fl.build_parts(key).to_float()}
	return {}


## [v7play] The beam for the planet's arc steps (HubPurpose.goal_target was written for this but
## never called, so "Fly to the next station" and "Wake station N" pointed at the home bench, even
## from a far station): fly / the drive -> the parked rocket once the price is covered (else "hex":
## go and earn); wake -> the landmark of the far station Lumi is at, else the rocket. Null when the
## step is not one of these or there is nothing to point at.
func _arc_beam(def: Dictionary, key: String) -> Variant:
	var sid: String = str(def.get("id", ""))
	var kind: String = ""
	if key == "hubs_woken" or sid.begins_with("hub_wake_"):
		kind = "landmark"
	elif key == "hubs_seen" or sid.begins_with("hub_fly_") or key == "drive_tier":
		kind = "rocket"
	if kind == "":
		return null
	var os_: OrbitSites = OrbitSites.of(world) if world else null
	if os_ == null or os_.purpose == null:
		return null
	if kind == "landmark":
		# [v9c] At the far station, the beam follows its own chain: while it asks for clean hexes
		# the hex to clean is outlined (the beam stood on the landmark, which the hexes don't need);
		# while it asks for an outpost the beam stands on the ruined outpost; then on the landmark.
		var st: String = str(os_.purpose.current_step(os_.purpose.site).get("do", "")) if os_.purpose.site > 0 else ""
		if st == "clean":
			return "hex"
		if st == "outposts":
			var op: Variant = os_.purpose.outpost_target()
			return op if op is Vector3 else "hex"
		var lm: Variant = os_.purpose.goal_target("landmark")
		if lm is Vector3:
			return lm
	var price: Dictionary = _step_price()
	if not price.is_empty() and not GameState.can_afford_all(price):
		return "hex"
	return os_.purpose.goal_target("rocket")


## [v6pace] What a step of the planet's arc costs, by the stat it counts: the next far hub's wake
## (hubs_seen, hubs_woken; the next rocket tier first when this one can't keep another hub), the next
## rocket tier (rocket_tier), the next drive (drive_tier). {} before the rocket stands on the pad.
static func arc_price(w: Node, key: String) -> Dictionary:
	if key == "drive_tier":
		if Homeward.progress_blocker(Homeward.next_drive()) == "":
			return (Homeward.next_drive().get("cost", {}) as Dictionary).duplicate()
		return {}
	if not key in ["hubs_seen", "hubs_woken", "rocket_tier"]:
		return {}
	var os_: OrbitSites = OrbitSites.of(w)
	if os_ == null or os_.sm == null or not os_.rocket_unlocked():
		return {}
	var nf: int = 0
	for i: int in range(1, os_.sm.built.size()):
		nf += 1 if os_.sm.built[i] != 0 else 0
	if key == "rocket_tier" or nf + 2 > RocketTiers.hub_limit():
		return (RocketTiers.next_def().get("cost", {}) as Dictionary).duplicate()
	return Hub.far_cost(nf)


func situation_hint(dt: float = 0.0) -> String:
	var p: Patch = _patch()
	if p == null or p.compartment == null:
		return ""
	var f: HexField = world.get("field") as HexField
	var cap: float = p.capacity()
	var full: bool = p.compartment.fill >= cap * 0.98 and cap > 0.0
	var press: bool = Pace.baler_unlocked() and not Pace.dump_allowed()
	var full_line: String = (tr("Your chest is full. Press [%s] to make a bale.") % Settings.glyph("cube")) if press \
		else tr("Your chest is full. Bring it to the bin.")
	if full and not _was_full:  # the moment it fills: say it over Lumi too, with a sound
		Vfx.float_text(p.global_position + OrbitUp.up(p.global_position) * 2.0, full_line, Color(1.0, 0.86, 0.45), 0.55, 0.6)
		Audio.play("ding", 0.8, -8.0)
	_was_full = full
	var far: bool = is_lost()
	if full:
		return tr("Your chest is full. Head home: the bin is under the tall smoke.") if far and not press else full_line
	if not p.carried.is_empty():
		return tr("Carry your bale home: the scale is under the tall smoke.") if far else tr("Carry your bale to the scale by the bin.")
	if Time.get_ticks_msec() - Pace.heavy_at < HEAVY_MS and Pace.heavy_at > 0:
		return tr("Too heavy. Upgrade Lift at the bench.")
	var price: Dictionary = _step_price()
	if not price.is_empty() and not GameState.can_afford_all(price):
		return ListDetail.short_text(price)
	var bench_here: bool = field_bench() is Vector3 and str(step_target(current()).get("to", "")) == "bench"  # [v6pace]
	if far and needs_home() and not bench_here:
		if away_rocket() is Vector3:
			return tr("The rocket waits on the pad. Home is first on its list.")  # [v6pace] a far base: fly home
		return tr("Head home: follow the beam to the tall smoke.")
	# Nothing to pick up nearby (away from home, on a cleaning step)
	var home: Variant = home_pos()
	var at_home: bool = home is Vector3 and OrbitUp.ground_dist(p.global_position, home) < 25.0
	if f != null and not at_home and str(step_target(current()).get("to", "")) in ["hex", ""]:
		if Pace.liftable_near(f, p.global_position, EMPTY_R):
			_empty_t = 0.0
		else:
			_empty_t += dt
		if _empty_t >= EMPTY_S:
			return tr("Nothing to pick up here. Walk to more trash.")
	else:
		_empty_t = 0.0
	return ""
