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

const TABLE: String = "tutorial"
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
var _source_key: int = 0


## [onboard2] Objectives added in front of "power" (see _ready's save migration).
const EARLY_ADDED: int = 4


func _ready() -> void:
	EventBus.upgrade_bought.connect(_on_upgrade_bought)  # [v1guide] the bale how-to
	var cfg: Dictionary = Economy.planet_table(TABLE)
	chain = cfg.get("objectives", [])
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
# (data/goals.json) continues on the same card, one step at a time. A goal whose condition holds
# while another step is on the card pays at once (Goals.check) with its own short notice, so no
# reward waits for the card and none lands in a burst.

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
	return step + (g.done_count() if g else 0) + _source_card_key()


# --- A city's source job on the card (systems/sources.gd) ----------------------------------------
# Once the story objectives are done, the source job of the city the readouts follow takes the
# card while one of its steps is on offer: it is the city's capstone and only Lumi can do it. The
# goal chain keeps paying behind it and comes back when the job is done or waiting.

func _orbit() -> SliceOrbit:
	return world.get("orbit") as SliceOrbit if world else null


## The city whose source job is on the card now ("" when none).
func source_district() -> String:
	var so: SliceOrbit = _orbit()
	if so == null or so.sources == null or so.districts == null or step < chain.size():
		return ""
	var id: String = so.districts.focus_id()
	return id if so.sources.is_open(id) else ""


## The source step as a card entry: {_source, text, desc}. Empty when no job is on the card.
func _source_step() -> Dictionary:
	var id: String = source_district()
	if id == "":
		return {}
	var card: Dictionary = _orbit().sources.card(id)
	var why: String = tr(str(card["desc"]))
	if not bool(card["affordable"]):
		why = tr("Needs %s. Dig up more Parts.") % Currencies.cost_text(card["cost"])
	return {"_source": id, "text": str(card["text"]), "desc": why}


## A number that changes whenever the card's source step does (0 with no job on the card).
func _source_card_key() -> int:
	var id: String = source_district()
	var src: Sources = _orbit().sources if id != "" else null
	return 0 if src == null else 1000 * (src.ids().find(id) + 1) + src.steps_done()


func _source_progress(id: String) -> Array:
	var src: Sources = _orbit().sources
	var n: int = src.steps(id).size()
	return [src.job_share(id), "%d / %d" % [mini(src.step_index(id) + 1, n), n]]


func _source_target(id: String) -> Dictionary:
	var so: SliceOrbit = _orbit()
	return {"to": "place", "pos": so.source_sites.target_pos(id) if so.source_sites else null, "row": []}


## The step on the card ({} when there is none: not revealed yet, or all done). A goal step is a
## copy of its goals.json entry with "_goal" (its index) and its reward as the why line.
func current() -> Dictionary:
	if not revealed:
		return {}
	if step < chain.size():
		return chain[step]
	var job: Dictionary = _source_step()
	if not job.is_empty():
		return job
	var gi: int = _goal_index()
	if gi < 0:
		return {}
	var g: Goals = goals()
	var d: Dictionary = (g.chain[gi] as Dictionary).duplicate()
	d["_goal"] = gi
	var rw: String = GoalsPanel.reward_text(g.reward_of(gi), 1.0)
	d["desc"] = (tr("Reward: %s") % rw) if rw != "" else ""
	return d


func target_of(def: Dictionary) -> float:
	if def.has("_goal") and goals():
		return goals().target_of(int(def["_goal"]))
	return float(def.get("target", 1))


func value_of(def: Dictionary) -> float:
	if def.has("_goal") and goals():
		return goals().value_of(int(def["_goal"]))
	var key: String = str(def.get("key", ""))
	var planet_measure: float = Restoration.measure(str(def.get("type", "stat")), key)  # launch, city_stage, cities_restored
	if planet_measure >= 0.0:
		return planet_measure
	match str(def.get("type", "stat")):
		"stat":  # "also": more lifetime stats that count toward the step (no purchase closes it off)
			var total: float = _stat(key)
			for k: Variant in def.get("also", []):
				total += _stat(str(k))
			return total
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


static func _stat(key: String) -> float:
	var v: Variant = GameState.stats.get(key, 0.0)
	return float(v) if (v is float or v is int) else 0.0


## The workbench tab a step works in ("" when none): the story step's bench_tab, and the Research
## tab for a goal about research.
static func step_tab(def: Dictionary) -> String:
	if def.has("bench_tab"):
		return str(def["bench_tab"])
	if def.has("_goal") and (str(def.get("type", "")) == "research" or str(def.get("key", "")) == "research_done"):
		return "research"
	return ""


## True while the step's workbench tab is still shut: the step then asks for the workbench tier
## that opens it (the Research Desk before "Finish a research project").
static func waits_for_tab(def: Dictionary) -> bool:
	var tab: String = step_tab(def)
	return tab != "" and not BenchTiers.tab_open(tab)


## Card text for an objective: [title, why]. The why is the "hint" until its wait_flag is set and
## its workbench tab is open; while the tier that opens the tab waits for something, it is that.
static func texts(def: Dictionary) -> Array[String]:
	var why: String = str(def.get("desc", ""))
	var wf: String = str(def.get("wait_flag", ""))
	var tab_shut: bool = waits_for_tab(def)
	if ((wf != "" and not GameState.flags.get(wf, false)) or tab_shut) and def.has("hint"):
		why = str(def["hint"])
	if tab_shut and BenchTiers.block_reason() != "":
		why = BenchTiers.block_reason()
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
func progress() -> Array:
	var def: Dictionary = current()
	if def.is_empty():
		return [-1.0, ""]
	if def.has("_source"):
		return _source_progress(str(def["_source"]))
	if def.get("hex", false):
		var f: float = hex_fraction()
		return [f, "%d%%" % int(floor(f * 100.0))] if target_hex >= 0 else [0.0, ""]
	var wf: String = str(def.get("wait_flag", ""))
	if wf != "" and not GameState.flags.get(wf, false):
		return [-1.0, ""]
	var tab_shut: bool = waits_for_tab(def)
	if tab_shut and BenchTiers.block_reason(world) != "":
		return [-1.0, ""]
	if tab_shut or (str(def.get("type", "")) == "bench" and BenchTiers.tier() < int(def.get("target", 2))):  # [v1guide] saving up: cubes toward the tier
		var need: float = float(BenchTiers.next_cost().get("cubes", 0.0))
		if need > 0.0:
			var have: float = minf(GameState.get_currency("cubes").to_float(), need)
			return [have / need, "%s / %s" % [Settings.fmt(BigNum.from_float(have)), Settings.fmt(BigNum.from_float(need))]]
	var tgt: float = target_of(def)
	var v: float = minf(value_of(def), tgt)
	if str(def.get("type", "")) in ["core", Restoration.MEASURE_LAUNCH]:
		return [v / maxf(tgt, 0.0001), "%d%%" % int(floor(v * 100.0))]
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
	if gl:
		gl.driven = true  # [v1guide] the card drives the goals: one step at a time
		gl.card_goal = _goal_index() if revealed and source_district() == "" else -1
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
	if _source_card_key() != _source_key:  # the job took the card, moved a step on, or left it
		_source_key = _source_card_key()
		changed.emit(step)
	if def.is_empty() or _hold > 0.0 or def.has("_source"):  # a source step is finished by Sources, not here
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
	var hud: Variant = world.get("hud") if world else null
	if hud != null and (hud as Object).has_method("notify"):
		hud.call("notify", tr("Objective complete  ·  %s") % t[0], "goal")
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
	if DevHooks.has("autoplay"):
		print("[onboard] goal %s done at %.1f min" % [str(g.chain[gi].get("id", "")), float(GameState.stats.get("time_played", 0.0)) / 60.0])
	_hold = NEXT_DELAY_S
	_set_hex(-1)
	var hud: Variant = world.get("hud") if world else null
	if hud != null and (hud as Object).has_method("notify"):
		hud.call("notify", tr("Goal complete  ·  %s") % text + (("    " + rw) if rw != "" else ""), "goal")
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
	"decor_placed", "decor_kinds", "decor_charm_best", "greenhouses_built", "water_tanks", "heaters_placed", "robots_retired", "radio_plays"]
const DEPOT_STATS: Array[String] = ["cubes_cashed", "junk_dumps", "robot_bales", "bales_recycled"]
const HEX_STATS: Array[String] = ["hexes_cleaned", "junk_scooped", "cubes_made", "perfect_cubes", "hexes_restored", "hexes_thawed",
	"plants_planted", "plants_bloomed", "garden_stipend", "eggs_found", "cats_petted"]


func step_target(def: Dictionary) -> Dictionary:
	var out: Dictionary = {"to": "", "row": []}
	if def.is_empty():
		return out
	if def.has("_source"):
		return _source_target(str(def["_source"]))
	var p: Patch = world.get("patch") as Patch if world else null
	var key: String = str(def.get("key", ""))
	var typ: String = str(def.get("type", "stat"))
	if waits_for_tab(def):  # the tab is shut: the workbench tier that opens it comes first
		return _resolve({"to": "bench" if BenchTiers.block_reason(world) == "" else "hex", "row": ["patch", "bench_tier"]})
	if not def.has("_goal"):  # the story objectives
		match str(def.get("id", "")):
			"dump3":  # a full-ish chest: to the bin; else out to the junk
				if Pace.dump_allowed():
					out["to"] = "bin" if p and p.compartment.fill >= p.capacity() * 0.5 else "hex"
				else:  # the Baler is fitted: the bin takes no loose loads, a sold bale counts
					out["to"] = "depot" if p and not p.carried.is_empty() else "hex"
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
			"hex", "hex2", "hex3", "street", "hex10", "hex20", "zone":  # [v3clear] hex2, hex10, hex20
				out["to"] = "hex"
			"bench2":
				out = {"to": "bench" if BenchTiers.block_reason(world) == "" else "hex", "row": ["patch", "bench_tier"]}
			"robot":
				out = {"to": "bench", "row": ["bots", ""]}
			"haul":  # [v4bots] waits for the Haul Bug plans (Research.check_story): clean meanwhile
				out = {"to": "bench", "row": ["bots", ""]} if Research.robot_unlocked("haulbug") else {"to": "hex", "row": []}
			"scoopie":  # [M3-21] the Scoopie's plans follow the first Haul Bug: clean meanwhile
				out = {"to": "bench", "row": ["bots", ""]} if Research.robot_unlocked("scoopie") else {"to": "hex", "row": []}
			"research1":  # [v3clear]
				out = {"to": "bench", "row": ["research", ""]}
			"base2", "base3":
				out = {"to": "bench", "row": ["patch", "hub_level"]}
			"seed":
				if GameState.flags.get("seed_signal", false) and not GameState.flags.get("seeds_unlocked", false):
					out = {"to": "place", "pos": (world.first_seed as FirstSeed).tin_point() if world.get("first_seed") != null else FirstSeed.GREENHOUSE_POS, "row": []}  # [orbB] [v4grow] on the tin
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
			if key == "junk_dumps":  # [v2guide] the chest goes into the bin's body, not onto the scale
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
		pos = home_pos()
	return pos


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
	var ls: Array = def.get("lines", [])
	if not ls.is_empty():
		w.speak(tr(str(ls[0])), w.stage())


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
	var tier_asked: bool = waits_for_tab(def) or (typ == "bench" and BenchTiers.tier() < int(def.get("target", 2)))
	if tier_asked and BenchTiers.block_reason(world) == "":
		return BenchTiers.next_cost()
	if typ == "tower" and SignalTower.tier() < int(def.get("target", 1)):
		return SignalTower.next_cost()
	return {}


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
	if far and needs_home():
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
