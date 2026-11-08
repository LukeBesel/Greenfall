class_name Camp
extends Node
## [camp] The landing yard (owner playtest #2, "Landing site / start area"). A fresh base starts
## with only the escape pod (story/crash_site.gd, intro2), a BROKEN workbench and the trash bin;
## the rest of the yard is clear and the world beyond is fully trashed.
##   - The workbench starts broken (tilted on a buckled leg, tools in the dirt, sparking). The first
##     E there plays a short repair: Lumi turns to it and welds it back together with the claw
##     beam. After that E opens the workbench as before. State: GameState.world.camp.bench.
##   - Old Town's lean-to, generator and street lamp, and the yard's poles, crates and festoons
##     (planet/street_dressing.gd "Yard" layer) arrive with hub level 2.
##   - The composter stays hidden until something has grown (it only works then anyway).
##   - The radio and the robot nursery are Hub-tab builds (systems/camp/yard_builds.gd).
##   - The trash bin (automation/trash_bin.gd) upgrades with E at the bin.
##   - Every yard interactable sits at least data/camp.json min_gap metres from the next one, and
##     every prompt names the thing it opens. `--camp-report` prints the yard's interactables.
## Dev: --camp-broken (start with the bench broken even on a loaded save), --camp-fixed (repaired),
##      --camp-repair (start the repair after 1 s), --camp-built=radio+nursery (build them free),
##      --camp-bin=N (trash bin level), --camp-report, --camp-buy=conveyor+auto_baler[+recycler]
##      (buy stations live after --camp-buy-at=S s, with their reveal).

const BIN_ANCHOR := Vector3(2.0, 0.0, -3.2)  # [camp2] front-right of the bin, off the plate, clear of the signal tower
const BIN_REACH: float = 1.6

var world: Node
var repairing: bool = false
var _bench: Node3D
var _bench_xf: Transform3D
var _tools: Array = []  # [node, home transform, broken transform]
var _spark_t: float = 0.0
var _bin_anchor: Node3D


static func attach(slice: Node) -> Camp:
	var c := Camp.new()
	c.name = "Camp"
	c.world = slice
	slice.add_child(c)
	c._setup()
	return c


static func of(slice: Node) -> Camp:
	return slice.get_node_or_null("Camp") as Camp if slice else null


static func cfg() -> Dictionary:
	return YardBuilds.cfg()


# --- State ------------------------------------------------------------------------------------

## Whether this base's workbench works. Saves from before the camp rework (a district that was
## already played) count as repaired, and so does any base where something was bought already.
static func bench_ok() -> bool:
	var st: Dictionary = YardBuilds.state()
	if not st.has("bench"):
		st["bench"] = GameState.world.has("field") or int(GameState.stats.get("upgrades_bought", 0)) > 0 or int(GameState.world.get("hub_level", 1)) > 1
	return bool(st["bench"])


static func set_bench_ok(on: bool) -> void:
	YardBuilds.state()["bench"] = on


## Old saves keep what they had: the radio and nursery count as built where the player could
## already use them (the radio was always on the bench; a nursery with caretakers in it).
static func migrate() -> void:
	var st: Dictionary = YardBuilds.state()
	if st.has("migrated"):
		return
	st["migrated"] = true
	if not GameState.world.has("field"):
		return  # a fresh district
	if int(GameState.world.get("hub_level", 1)) >= 2 or str(Radio.st().get("song", "")) != "":
		YardBuilds.mark_built("radio")
	if not Nursery.list().is_empty():
		YardBuilds.mark_built("nursery")


## [camp2] Second pass (everything became a Hub build): whatever already stood in a played
## district counts as built. Before camp2 the lean-to, generator and lamps stood from hub level 2
## at Old Town (always at the other bases), and the compost press once something had grown.
static func migrate2() -> void:
	var st: Dictionary = YardBuilds.state()
	if st.has("migrated2"):
		return
	st["migrated2"] = true
	if not GameState.world.has("field"):
		return  # a fresh district
	if GameState.current_hub != 0 or int(GameState.world.get("hub_level", 1)) >= 2:
		for id: String in ["shack", "generator", "lamps"]:
			YardBuilds.mark_built(id)
	if bool(GameState.flags.get("first_sprout", false)):
		YardBuilds.mark_built("composter")


# --- Setup ------------------------------------------------------------------------------------

func _setup() -> void:
	add_to_group("persist")
	# Before anything reads the state: the slice has already loaded (or not) the district.
	migrate()
	migrate2()  # [camp2]
	if DevHooks.has("camp-broken"):
		set_bench_ok(false)
	elif DevHooks.has("camp-fixed"):
		set_bench_ok(true)
	if DevHooks.has("camp-built"):
		for id: String in DevHooks.get_s("camp-built", "radio+nursery").split("+", false):
			YardBuilds.mark_built(id)
	# The extras set themselves up before Camp: show what migration / dev hooks just marked built.
	var ex: ExtrasDirector = ExtrasDirector.of(world)
	if ex and ex.radio:
		ex.radio.set_built(YardBuilds.built("radio"), false)
	if ex and ex.nursery:
		ex.nursery.set_built(YardBuilds.built("nursery"), false)
	if DevHooks.has("camp-bin"):
		TrashBin.set_level(int(DevHooks.get_f("camp-bin", 1.0)))
	_bench = (world.get("_ruin_bits") as Dictionary).get("bench") as Node3D
	if _bench:
		_bench_xf = _bench.transform
		for c: Node in _bench.get_children():
			if c is MeshInstance3D and c.get_index() > 0:
				var n: Node3D = c
				var i: int = _tools.size()
				var broken := Transform3D(Basis.from_euler(Vector3(randf_range(-1.2, 1.2), i * 1.7, randf_range(-1.4, 1.4))),
					Vector3(-0.9 + i * 0.42, -0.62 + (0.06 if i % 2 == 0 else 0.0), 0.55 + (i % 3) * 0.12))
				_tools.append([n, n.transform, broken])
	_apply_bench(bench_ok(), false)
	var hub: Hub = world.get("hub") as Hub
	_apply_builds()  # [camp2] everything but the bench and the bin is a Hub build
	if hub:
		hub.level_changed.connect(func(_l: int) -> void: _apply_builds())  # after the slice's own ruin/level pass
	YardBuilds.events.built.connect(_on_built)
	_register_bin()
	if DevHooks.has("camp-repair"):
		get_tree().create_timer(1.0).timeout.connect(repair_bench)
	if DevHooks.has("camp-buy"):  # buy stations live (with their reveal), e.g. conveyor+auto_baler
		get_tree().create_timer(DevHooks.get_f("camp-buy-at", 2.0)).timeout.connect(_dev_buy)
	if DevHooks.has("camp-report"):
		get_tree().create_timer(DevHooks.get_f("camp-report", 2.0)).timeout.connect(func() -> void: print(report()))


func _dev_buy() -> void:
	var st: Stations = Stations.of(world)
	if st == null:
		return
	GameState.world["hub_level"] = maxi(int(GameState.world.get("hub_level", 1)), 3)
	for id: String in DevHooks.get_s("camp-buy", "conveyor+auto_baler").split("+", false):
		Research.grant(id)
		var c: Dictionary = st.def(id).get("cost", {})
		for k: String in c:
			GameState.add_currency(k if k in ["cubes", "parts", "seeds"] else "parts", BigNum.from_float(float(c[k]) * 2.0))
		print("[camp] buy %s: %s -> %s" % [id, st.block_reason(id), str(st.build(id))])


func persist_save() -> void:
	bench_ok()  # makes sure the key is written


# --- The workbench ----------------------------------------------------------------------------

## The prompt at the bench (names it, says what E does).
func bench_prompt() -> String:
	if repairing:
		return ""
	if not bench_ok():
		return tr("E   Workbench (broken): repair it")
	return tr("E   Workbench: upgrades")


func repair_bench() -> void:
	if repairing or bench_ok():
		return
	repairing = true
	var patch: Node3D = world.get("patch") as Node3D
	var p_in: Variant = patch.get("input") if patch else null
	if p_in is PlayerInput:
		(p_in as PlayerInput).enabled = false
	var target: Vector3 = _bench.global_position + Vector3(0, 0.9, 0) if _bench else world.BOARD_POS
	if patch:
		var d: Vector3 = target - patch.global_position
		patch.rotation.y = atan2(-d.x, -d.z)
	var model: Node = patch.get("model") if patch else null
	var dur: float = float(cfg().get("bench_repair_s", 2.6))
	var tw := create_tween()
	# Beam on, weld sparks along the bench, the bench rights itself, the tools hop back up.
	tw.tween_callback(func() -> void:
		if model:
			model.call("beam_at", target)
			model.call("shudder", 0.25)
		Audio.play("servo", 1.1, -6.0))
	var steps: int = 6
	for k: int in steps:
		tw.tween_callback(func() -> void:
			var at: Vector3 = target + (_bench.global_transform.basis.x * lerpf(-0.9, 0.9, float(k) / (steps - 1)) if _bench else Vector3.ZERO)
			if model:
				model.call("beam_at", at)
			Vfx.burst("sparkle", at, Color(1.0, 0.75, 0.35), 0.35)
			Audio.play("tick" if k % 2 == 0 else "clink", randf_range(0.9, 1.3), -8.0))
		tw.tween_interval(dur * 0.5 / steps)
	tw.tween_callback(func() -> void:
		Audio.play("hydraulic", 1.0, -6.0)
		_apply_bench(true, true))
	tw.tween_interval(dur * 0.5)
	tw.tween_callback(func() -> void:
		if model:
			model.call("beam_at", null)
			model.call("set_happy", 1.0)
		set_bench_ok(true)
		repairing = false
		if p_in is PlayerInput:
			(p_in as PlayerInput).enabled = true
		GameState.inc_stat("bench_repaired")
		Audio.play("chime", 1.0, -4.0)
		EventBus.toast.emit(tr("Workbench fixed. Press E at it to spend cubes on upgrades."), "info"))


## Instant repair (autoplay, tests).
func repair_now() -> void:
	set_bench_ok(true)
	_apply_bench(true, false)


func _apply_bench(ok: bool, animate: bool) -> void:
	if _bench == null:
		return
	var bxf: Transform3D = _bench_xf if ok else _bench_xf * Transform3D(Basis.from_euler(Vector3(0.06, 0.1, -0.2)), Vector3(0.15, -0.16, 0.05))
	if not animate:
		_bench.transform = bxf
	else:
		create_tween().tween_property(_bench, "transform", bxf, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var i: int = 0
	for t: Array in _tools:
		var n: Node3D = t[0]
		var xf: Transform3D = t[1] if ok else t[2]
		if not animate:
			n.transform = xf
		else:
			var tw := create_tween()
			tw.tween_interval(0.25 + i * 0.12)
			tw.tween_property(n, "transform", xf, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


func _process(delta: float) -> void:
	if bench_ok() or repairing or _bench == null:
		return
	# Broken: now and then a short spits sparks from under the top.
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = randf_range(1.6, 3.4)
		Vfx.burst("sparkle", _bench.global_position + _bench.global_transform.basis.x * 0.6 + Vector3(0, 0.75, 0), Color(1.0, 0.8, 0.4), 0.25)


# --- Yard by hub level --------------------------------------------------------------------------

## [camp2] Shows exactly what has been built: the lean-to (its frame, roof, walls and work lamp),
## the generator, the yard lamps (street lamp + the fence pole lamps) and the compost press.
## Nothing appears on its own. At the other bases the lean-to keeps its ruined look by hub level
## (scenes/slice.gd _apply_base_level) once it is built.
func _apply_builds() -> void:
	var bits: Dictionary = world.get("_ruin_bits")
	var shack: bool = YardBuilds.built("shack")
	for k: String in ["frame", "roof", "back", "side", "lamp", "bulb"]:
		var n: Node3D = bits.get(k) as Node3D
		if n:
			n.visible = shack and _was_shown(k)
	var lamps: bool = YardBuilds.built("lamps")
	for k: String in ["street_lamp", "street_light"]:
		var n2: Node3D = bits.get(k) as Node3D
		if n2:
			n2.visible = lamps and _was_shown(k)
	var gen: Node3D = bits.get("generator") as Node3D
	if gen:
		gen.visible = YardBuilds.built("generator")
	var dressing: Node = world.get("dressing")
	if dressing and dressing.has_method("set_level"):
		var hub: Hub = world.get("hub") as Hub
		dressing.call("set_level", hub.level if hub else 1, false)  # its "Lamps" layer reads YardBuilds
	var comp: Node3D = world.get("composter") as Node3D
	if comp:
		comp.visible = YardBuilds.built("composter")


## Whether the slice's own ruin pass would show this bit (hub level 2+, or Old Town).
func _was_shown(k: String) -> bool:
	var hub: Hub = world.get("hub") as Hub
	var ruined: bool = (hub.level if hub else 1) <= 1 and int(world.get("hub_index")) != 0
	return not (ruined and k in ["side", "lamp", "bulb", "street_light"])


func _on_built(id: String) -> void:
	var ex: ExtrasDirector = ExtrasDirector.of(world)
	match id:
		"radio":
			if ex and ex.radio:
				ex.radio.set_built(true, true)
		"nursery":
			if ex and ex.nursery:
				ex.nursery.set_built(true, true)
		_:
			_apply_builds()  # [camp2] lean-to, generator, lamps, compost press
	var at: Vector3 = YardBuilds.pos(id, Vector3.ZERO)
	var bits: Dictionary = world.get("_ruin_bits")
	match id:
		"nursery":
			if ex and ex.nursery:
				at = ex.nursery.global_position
		"shack":
			at = world.BOARD_POS
		"generator", "lamps":
			var n: Node3D = bits.get("generator" if id == "generator" else "street_lamp") as Node3D
			if n:
				at = n.global_position
		"composter":
			var c: Node3D = world.get("composter") as Node3D
			if c:
				at = c.global_position
	MachineReveal.reveal(world, tr(str(YardBuilds.def(id).get("name", id))), at)




# --- The trash bin --------------------------------------------------------------------------------

func _register_bin() -> void:
	var depot: Node3D = world.get("depot") as Node3D
	var ia: Interactables = world.get("interactables") as Interactables
	if depot == null or ia == null:
		return
	_bin_anchor = Node3D.new()
	_bin_anchor.name = "TrashBinReach"
	world.add_child(_bin_anchor)
	_bin_anchor.global_position = depot.global_position + (BIN_ANCHOR - Vector3(0, 0, -1.8))
	ia.register(_bin_anchor, BIN_REACH, bin_prompt, use_bin)


func hub_level() -> int:
	var hub: Hub = world.get("hub") as Hub
	return hub.level if hub else int(GameState.world.get("hub_level", 1))


func bin_prompt() -> String:
	var nm: String = tr(TrashBin.name_of())
	if TrashBin.next_def().is_empty():
		return tr("E   %s (Lv %d): fully upgraded") % [nm, TrashBin.level()]
	var why: String = TrashBin.block_reason(hub_level())
	if why != "" and why != tr("Not enough materials."):
		return tr("E   %s (Lv %d): %s") % [nm, TrashBin.level(), why]
	return tr("E   %s (Lv %d): upgrade to %s for %s") % [nm, TrashBin.level(), tr(TrashBin.name_of(TrashBin.level() + 1)), HubPanel.cost_text(TrashBin.next_cost())]


func use_bin() -> void:
	if TrashBin.upgrade(hub_level()):
		Audio.play("buy", 0.9, -2.0)
		EventBus.toast.emit(tr("Trash bin upgraded: %s. Bales sell for %d%% here.") % [tr(TrashBin.name_of()), int(round(TrashBin.value_mult() * 100.0))], "info")
	else:
		Audio.play("buzz", 1.2, -8.0)
		var why: String = TrashBin.block_reason(hub_level())
		EventBus.toast.emit(why if why != "" else tr("Not enough materials."), "info")


# --- Spacing ------------------------------------------------------------------------------------

## Every fixed interaction point in the yard: [name, position (xz), shown now]. Moving things
## (caretakers, robots, events) are left out.
func points() -> Array:
	var out: Array = []
	out.append(["workbench", world.BOARD_POS, true])
	if _bin_anchor:
		out.append(["trash_bin", _bin_anchor.global_position, true])
	var comp: Node3D = world.get("composter") as Node3D
	if comp:
		out.append(["composter", comp.global_position, comp.visible])
	out.append(["flower", world.FLOWER_POS, true])
	var ex: ExtrasDirector = ExtrasDirector.of(world)
	if ex and ex.radio:
		var ra: Node3D = world.get_node_or_null("RadioReach") as Node3D
		out.append(["radio", ra.global_position if ra else ex.radio.global_position, ex.radio.visible])
	var scope: Telescope = Telescope.of(world)
	if scope:
		out.append(["telescope", scope.door_point(), scope.built()])
	var tower: Node3D = world.get_node_or_null("SignalTower") as Node3D
	if tower:  # [camp2]
		out.append(["signal_tower", tower.global_position, tower.visible])
	return out


## [camp2] What visibly stands in the yard right now (the bench and the bin always; every
## other structure only once built). A fresh base lists exactly ["workbench", "trash_bin"].
func standing() -> Array[String]:
	var out: Array[String] = ["workbench", "trash_bin"]
	var bits: Dictionary = world.get("_ruin_bits")
	var checks: Dictionary = {"lean-to": bits.get("frame"), "generator": bits.get("generator"), "lamps": bits.get("street_lamp"),
		"composter": world.get("composter"), "signal_tower": world.get_node_or_null("SignalTower")}
	var ex: ExtrasDirector = ExtrasDirector.of(world)
	if ex:
		checks["cd_player"] = ex.radio
		checks["nursery"] = ex.nursery
	var st: Stations = Stations.of(world)
	if st:
		checks["conveyor"] = st.conveyor
		checks["auto_baler"] = st.baler
		checks["recycler"] = st.recycler
	for k: String in checks:
		var n: Node3D = checks[k] as Node3D
		if n and n.is_inside_tree() and n.is_visible_in_tree():
			out.append(k)
	var dressing: Node = world.get("dressing")
	var lay: Node3D = dressing.get_node_or_null("Lamps") as Node3D if dressing else null
	if lay and lay.is_visible_in_tree() and not ("lamps" in out):
		out.append("lamps")
	var scope: Telescope = Telescope.of(world)
	if scope and scope.built():
		out.append("telescope")
	if world.get_node_or_null("Museum") and Museum.built():
		out.append("museum")
	return out


## Pairs of points closer than min_gap (every point counted, built or not: they'll all be there).
func too_close() -> Array:
	var gap: float = float(cfg().get("min_gap", 3.0))
	var pts: Array = points()
	var out: Array = []
	for i: int in pts.size():
		for j: int in range(i + 1, pts.size()):
			var a: Vector3 = pts[i][1]
			var b: Vector3 = pts[j][1]
			var d: float = Vector2(a.x - b.x, a.z - b.z).length()
			if d < gap:
				out.append("%s-%s %.2f m" % [pts[i][0], pts[j][0], d])
	return out


func report() -> String:
	var lines: Array[String] = ["[camp] bench_ok=%s bin=L%d radio=%s nursery=%s hub=%d" % [str(bench_ok()), TrashBin.level(), str(YardBuilds.built("radio")), str(YardBuilds.built("nursery")), hub_level()]]
	for p: Array in points():
		var v: Vector3 = p[1]
		lines.append("[camp]   %-10s (%.1f, %.1f) shown=%s" % [p[0], v.x, v.z, str(p[2])])
	lines.append("[camp] too_close=%s" % str(too_close()))
	return "\n".join(lines)
