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
	var cfg: Dictionary = Economy.read_json(PATH)
	chain = cfg.get("objectives", [])
	brief_lines = (cfg.get("brief", {}) as Dictionary).get("lines", [])
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
	return step >= chain.size()


## The objective on the card ({} when there is none: not revealed yet, or all done).
func current() -> Dictionary:
	if not revealed or done():
		return {}
	return chain[step]


func target_of(def: Dictionary) -> float:
	return float(def.get("target", 1))


func value_of(def: Dictionary) -> float:
	var key: String = str(def.get("key", ""))
	match str(def.get("type", "stat")):
		"stat":
			var v: Variant = GameState.stats.get(key, 0.0)
			return float(v) if (v is float or v is int) else 0.0
		"robot":
			var fl: Node = world.get("fleet") if world else null
			if fl == null:
				return 0.0
			return float(fl.call("robots").size()) if key == "any" else float(fl.call("count", key))
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
	return 0.0


## Card text for an objective: [title, why]. The why is the "hint" until its wait_flag is set.
static func texts(def: Dictionary) -> Array[String]:
	var why: String = str(def.get("desc", ""))
	var wf: String = str(def.get("wait_flag", ""))
	if wf != "" and not GameState.flags.get(wf, false) and def.has("hint"):
		why = str(def["hint"])
	return [TranslationServer.translate(str(def.get("text", ""))), TranslationServer.translate(why)]


## Progress of the current objective: [0..1 or -1 for none, label]. Hex objectives show the target
## hex's % clean; counts show "1 / 3".
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
	var tgt: float = target_of(def)
	var v: float = minf(value_of(def), tgt)
	if str(def.get("type", "")) == "core":
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
	if not revealed:
		return
	_explain_signal()
	_hold = maxf(0.0, _hold - delta)
	_t -= delta
	if _t > 0.0:
		return
	_t = REFRESH_S
	var def: Dictionary = current()
	waypoint.set_target(waypoint_target())
	if def.is_empty() or _hold > 0.0:
		_set_hex(-1)
		return
	if value_of(def) >= target_of(def):
		complete()
		return
	if def.get("hex", false):
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
			changed.emit(step)
			var w: Wren = _wren()
			if w and not done():
				for l: Variant in chain[step].get("lines", []):
					w.speak(tr(str(l)), 1))
	else:
		changed.emit(step)


# --- The target hex -----------------------------------------------------------------------------

func _hex_ok(h: int) -> bool:
	var f: HexField = world.field
	return h >= 0 and h < f.hex_count() and not f.is_clean(h) and f.hex_hub[h] == 0 and not f.is_water(h) and not f.locked.has(h)


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
		elif Vector2(f.hex_center(h).x - at.x, f.hex_center(h).z - at.z).length() > f.hex_size * 6.0:
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
func _point_at_last() -> void:
	if target_hex < 0 or hex_fraction() < POINT_AT:
		if marker:
			marker.clear()
		return
	var f: HexField = world.field
	var at: Vector3 = world.patch.global_position
	var out: int = -1
	var bd: float = INF
	for pid: int in f.hex_pieces[target_hex]:
		if f.piece_alive[pid] == 0:
			continue
		var d: float = f.piece_pos[pid].distance_squared_to(at)
		if d < bd:
			bd = d
			out = pid
	if out < 0:
		return
	if marker == null:
		marker = TutorialMarker.new()
		marker.world = world
		add_child(marker)
	marker.set_target(f.piece_pos[out], "piece")


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


## Where the purple waypoint points: the current objective's place (the scale with a bale in
## hand, the workbench for builds, the greenhouse once WREN hears the seed tin), or with no
## objective running, the current goal's (a memory shard, the scale, the workbench, a buried part).
## null = nothing to point at (or the restart checklist's own marker is on).
func waypoint_target() -> Variant:
	if int(GameState.flags.get("tutorial_step", 0)) < Tutorial.STEPS.size():
		return null
	var p: Patch = world.get("patch") as Patch
	if p == null:
		return null
	var def: Dictionary = current()
	if not def.is_empty():
		match str(def.get("id", "")):
			"power":
				return _depot_pos() if not p.carried.is_empty() else null
			"dump3":  # [onboard2] a full-ish chest: to the bin
				return _depot_pos() if p.compartment.fill >= p.capacity() * 0.5 else null
			"scoop_size", "compartment", "baler":  # [onboard2] to the bench once it's affordable
				var uid: String = str(def.get("key", ""))
				return _bench_pos() if GameState.can_afford("cubes", Economy.upgrade_cost(uid)) else null
			"robot", "haul", "base2", "base3":
				return _bench_pos()
			"tower", "tower2":
				if SignalTower.tier() == 0:
					return _bench_pos()  # [camp2] the first tier is built from the workbench's Hub tab
				return SignalTower.pos() if SignalTower.tier() < int(def.get("target", 1)) else null
			"seed":
				if GameState.flags.get("seed_signal", false) and not GameState.flags.get("seeds_unlocked", false):
					return FirstSeed.GREENHOUSE_POS
		return null
	var gl: Goals = world.get("goals") as Goals
	if gl == null or gl.current().is_empty():
		return null
	var g: Dictionary = gl.chain[gl.current()[0]]
	match str(g.get("key", "")):
		"shards_found":
			var sh: Variant = world.get("shards")
			if sh is ShardSystem:
				var w: Dictionary = (sh as ShardSystem).waypoint(p.global_position)
				return w.get("pos", null)
		"cubes_cashed":
			return _depot_pos()
		"upgrades_bought", "compartment_size":
			return _bench_pos()
		"parts_found":
			if p.detector and p.detector.target >= 0:
				return world.field.part_pos[p.detector.target]
	return null


func _bench_pos() -> Variant:
	if world.has_method("bench_pos"):  # [orbB] the globe's bench anchor too
		return world.call("bench_pos")
	var sc: Script = world.get_script() as Script
	return sc.get_script_constant_map().get("BOARD_POS", null) if sc else null


func _depot_pos() -> Variant:
	var d: Variant = world.get("depot")
	return (d as Node3D).global_position if d is Node3D else null


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
		w.speak(tr("Hear that beeping? Your detector's found a robot part buried nearby. The faster it beeps, the closer you are."), 1)
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
