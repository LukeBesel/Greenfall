class_name Outposts
extends Node3D
## Ruined frontier outposts that Patch repairs into extra depots (data/outposts.json).
## Each district has 3-4 at fixed, seeded spots on the outer hex rings (plan()). A ruin can be
## repaired (E at its kiosk) once its hex is mostly clean; repair costs cubes + building stock
## (Hub.pay) and plays a fast-build. A repaired outpost is a working scale (Depot in bare mode:
## same value logic + its level bonus), a Drip refill point (robots/water_net.gd) and a parking
## spot for idle robots; Haul Bugs deliver to the nearest working scale (robots/robot.gd, marked
## [outposts]). Upgrades: 2 = Big Skip, 3 = Recharge Pad (robots passing over run faster).
## State: GameState.world["outposts"] = {"levels": [lv per outpost]} (per district).
## Dev hooks: --outposts=repaired|all:L|I:L[+I:L]  pre-set levels (+ --outpost-clean clears their hexes); --outpost-spawn=N  put Patch
## in front of outpost N; --outpost-repair=N  play the repair sequence on N shortly after start.

const CFG_PATH: String = "res://data/outposts.json"

var world: Node
var cfg: Dictionary = {}
var spots: Array[Dictionary] = []
var items: Array[Outpost] = []
var _reported: bool = false

static var _cfg_cache: Dictionary = {}


static func load_cfg() -> Dictionary:
	if _cfg_cache.is_empty():
		_cfg_cache = Economy.read_json(CFG_PATH)
	return _cfg_cache


static func level_def(lv: int) -> Dictionary:
	for d: Dictionary in load_cfg().get("levels", []):
		if int(d["level"]) == lv:
			return d
	return {}


static func max_level() -> int:
	return (load_cfg().get("levels", []) as Array).size()


func _ready() -> void:
	add_to_group("outposts")


func setup() -> void:
	cfg = load_cfg()
	spots = plan(world.field, cfg)
	var lv: Array = levels()
	while lv.size() < spots.size():
		lv.append(0)
	_apply_dev_levels(lv)
	for i: int in spots.size():
		var o := Outpost.new()
		add_child(o)
		o.global_position = spots[i]["pos"]
		o.rotation.y = float(spots[i]["yaw"])
		o.setup(i, int(lv[i]), world)
		items.append(o)
		if world.get("interactables") != null:
			world.interactables.register(o.anchor, 3.0, prompt.bind(i), use.bind(i))
	var where: Array[String] = []
	for sp: Dictionary in spots:
		where.append("hex%d@(%.0f,%.0f)" % [int(sp["hex"]), (sp["pos"] as Vector3).x, (sp["pos"] as Vector3).z])
	print("[outposts] district %d: %d outposts %s levels %s" % [GameState.current_hub, items.size(), " ".join(where), str(levels())])
	if DevHooks.has("outpost-spawn"):
		var k: int = clampi(int(DevHooks.get_f("outpost-spawn", 0.0)), 0, maxi(items.size() - 1, 0))
		if k < items.size() and world.get("patch") != null:
			var o: Outpost = items[k]
			world.patch.global_position = o.to_global(Vector3(DevHooks.get_f("outpost-dx", 1.2), 0.25, DevHooks.get_f("outpost-dist", 8.5)))
			world.patch.rotation.y = o.rotation.y + DevHooks.get_f("outpost-yaw", 0.0)
			if world.get("cam") != null:
				world.cam.yaw = world.patch.rotation.y
				world.cam.snap()
	if DevHooks.has("outpost-repair"):
		var r: int = int(DevHooks.get_f("outpost-repair", 0.0))
		get_tree().create_timer(DevHooks.get_f("outpost-repair-at", 3.0)).timeout.connect(func() -> void: repair(r, true, true))


func _process(_delta: float) -> void:
	# Dev runs (--robots / --outposts with --quit-after): report deliveries just before the end.
	if _reported or not (DevHooks.has("robots") or DevHooks.has("outposts")) or not DevHooks.has("quit-after"):
		return
	if DevHooks._elapsed >= DevHooks.get_f("quit-after", 5.0) - 1.0:
		_reported = true
		report()


## Per-depot delivery counts (dev runs).
func report() -> void:
	var main_n: int = int((world.depot as Depot).cashed) if world.get("depot") is Depot else 0
	var parts: Array[String] = ["main=%d" % main_n]
	for o: Outpost in items:
		parts.append("outpost%d(lv%d)=%d" % [o.index, o.level, o.scale_depot.cashed if o.scale_depot else 0])
	print("[outposts] bales cashed by depot: %s  outpost_bales stat=%d" % [" ".join(parts), int(GameState.stats.get("outpost_bales", 0.0))])


func _apply_dev_levels(lv: Array) -> void:
	if not DevHooks.has("outposts"):
		return
	var spec: String = DevHooks.get_s("outposts", "repaired")
	for tok: String in spec.split("+"):
		if tok == "repaired" or tok == "1":
			for i: int in lv.size():
				lv[i] = maxi(int(lv[i]), 1)
		elif tok.begins_with("all:"):
			for i: int in lv.size():
				lv[i] = clampi(int(tok.get_slice(":", 1)), 0, max_level())
		elif ":" in tok:
			var i2: int = int(tok.get_slice(":", 0))
			if i2 >= 0 and i2 < lv.size():
				lv[i2] = clampi(int(tok.get_slice(":", 1)), 0, max_level())
	var st: Dictionary = state()
	st["levels"] = lv.duplicate()
	for i: int in lv.size():
		if int(lv[i]) >= 1:
			_sweep(i)
			if DevHooks.has("outpost-clean"):  # also clear the whole hex, as a real repair would need
				for pid: int in world.field.hex_pieces[int(spots[i]["hex"])]:
					if world.field.piece_alive[pid] == 1:
						if world.has_method("collect_piece"):
							world.collect_piece(pid)
						else:
							world.field.remove_piece(pid)


static func of(n: Node) -> Outposts:
	if n == null or not n.is_inside_tree():
		return null
	return n.get_tree().get_first_node_in_group("outposts") as Outposts


static func _mgr(w: Node) -> Outposts:
	if w == null:
		return null
	var v: Variant = w.get("outposts")
	return v as Outposts if v is Outposts else null


func state() -> Dictionary:
	if not GameState.world.has("outposts") or not GameState.world["outposts"] is Dictionary:
		GameState.world["outposts"] = {}
	return GameState.world["outposts"]


func levels() -> Array:
	var out: Array = []
	for v: Variant in state().get("levels", []):
		out.append(int(v))
	return out


func level_of(i: int) -> int:
	var lv: Array = levels()
	return int(lv[i]) if i >= 0 and i < lv.size() else 0


func _set_level(i: int, lv: int) -> void:
	var arr: Array = levels()
	while arr.size() <= i:
		arr.append(0)
	arr[i] = lv
	state()["levels"] = arr


func repaired_count() -> int:
	var n: int = 0
	for v: int in levels():
		if v >= 1:
			n += 1
	return n


# --- Placement (pure, deterministic) -------------------------------------------------

## The district's outpost sites: [{pos, yaw, hex}]. Spread around the outer hex rings in
## seeded sectors, on open ground (no buildings, yard, water or road under the footprint).
static func plan(field: HexField, c: Dictionary = {}) -> Array[Dictionary]:
	if c.is_empty():
		c = load_cfg()
	var r := RandomNumberGenerator.new()
	r.seed = field.seed_value + 4242
	var cnt: Array = c.get("count", [3, 4])
	var n: int = r.randi_range(int(cnt[0]), int(cnt[1]))
	var foot: float = float(c.get("footprint", 3.6))
	var outer: int = field.radius
	var min_ring: int = maxi(1, outer - 1)
	var relay: Vector3 = LedgerArc.relay_spot(field)["pos"]
	# Best site in every frontier hex (seeded per hex, so it doesn't depend on the order).
	var sites: Array[Dictionary] = []
	for id: int in field.hex_count():
		var ring: int = Hex.distance(field.hex_axial[id], Vector2i.ZERO)
		if ring < min_ring or field.hex_hub[id] != 0 or field.is_water(id):
			continue
		var site: Dictionary = _site_in(field, id, foot, field.seed_value + 4242 + id * 31)
		if site.is_empty():
			continue
		if Vector2(site["pos"].x - relay.x, site["pos"].z - relay.z).length() < foot + 4.0:
			continue
		site["ring"] = ring
		sites.append(site)
	var out: Array[Dictionary] = []
	if sites.is_empty():
		return out
	var a0: float = r.randf() * TAU
	var used: Dictionary = {}
	for k: int in n:
		var want: float = a0 + TAU * float(k) / float(n)
		var best: int = -1
		var best_s: float = INF
		for si: int in sites.size():
			var s: Dictionary = sites[si]
			if used.has(si):
				continue
			var p: Vector3 = s["pos"]
			var clash: bool = false
			for o: Dictionary in out:
				if Vector2(p.x - o["pos"].x, p.z - o["pos"].z).length() < foot * 4.0:
					clash = true
					break
			if clash:
				continue
			var da: float = absf(angle_difference(atan2(p.z, p.x), want))
			var score: float = da + (0.35 if int(s["ring"]) < outer else 0.0) + (0.25 if s.get("relaxed", false) else 0.0)
			if score < best_s:
				best_s = score
				best = si
		if best < 0:
			continue
		used[best] = true
		var pick: Dictionary = sites[best]
		var pp: Vector3 = pick["pos"]
		out.append({"pos": pp, "yaw": atan2(-pp.x, -pp.z), "hex": int(pick["hex"])})
	return out


static func _site_in(field: HexField, id: int, foot: float, seed_v: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var c: Vector3 = field.hex_center(id)
	for pass_i: int in 2:
		var relaxed: bool = pass_i == 1
		for attempt: int in 28:
			var off := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * field.hex_size * 0.42
			if attempt == 0:
				off = Vector3.ZERO
			var p: Vector3 = c + off
			if field.hex_at(p) != id:
				continue
			if _open(field, p, foot * (0.8 if relaxed else 1.0), relaxed):
				var y: float = clampf(field.layout.height_at(p.x, p.z), 0.0, 0.3) if field.layout else 0.0
				return {"pos": Vector3(p.x, y, p.z), "hex": id, "relaxed": relaxed}
	return {}


static func _open(field: HexField, p: Vector3, foot: float, relaxed: bool) -> bool:
	var probes: Array[Vector3] = [Vector3.ZERO]
	for k: int in 8:
		var a: float = TAU * k / 8.0
		probes.append(Vector3(cos(a), 0, sin(a)) * foot)
		probes.append(Vector3(cos(a), 0, sin(a)) * foot * 0.5)
	for o: Vector3 in probes:
		var q: Vector3 = p + o
		var h: int = field.hex_at(q)
		if h < 0 or field.is_water(h) or field.hex_hub[h] == HexField.HEX_HUB:
			return false
		for lm: Dictionary in field.landmarks:
			if Vector2((lm["pos"] as Vector3).x - q.x, (lm["pos"] as Vector3).z - q.z).length() < 1.6:
				return false
		if field.layout == null:
			continue
		var s: int = field.layout.surface_at(q.x, q.z)
		if s == CityLayout.Surface.BUILDING or s == CityLayout.Surface.YARD:
			return false
		# Never block a road: the centre and the inner ring stay off the carriageway always.
		if s == CityLayout.Surface.ROAD and (not relaxed or o.length() < foot * 0.6):
			return false
	return true


# --- Repair / upgrade ------------------------------------------------------------------

## Removed fraction of the outpost's hex (the repair gate).
func clean_fraction(i: int) -> float:
	if i < 0 or i >= spots.size():
		return 0.0
	return world.field.removed_fraction(int(spots[i]["hex"]))


func clean_needed() -> float:
	return float(cfg.get("clean_needed", 0.9))


func repair_cost(_i: int = 0) -> Dictionary:
	var base: Dictionary = cfg.get("repair_cost", {})
	var m: float = pow(float(cfg.get("repair_growth", 1.6)), repaired_count())
	var out: Dictionary = {}
	for k: String in base:
		out[k] = ceilf(float(base[k]) * m)
	return out


func upgrade_cost(i: int) -> Dictionary:
	return level_def(level_of(i) + 1).get("cost", {})


## "" when outpost i can be repaired now, else why not.
func repair_block(i: int) -> String:
	if i < 0 or i >= spots.size():
		return tr("No outpost.")
	if level_of(i) >= 1:
		return tr("Already repaired.")
	if items.size() > i and items[i].busy:
		return "Building..."
	if clean_fraction(i) < clean_needed():
		return tr("Clear the junk around it first (%d%% of %d%%).") % [int(clean_fraction(i) * 100.0), int(clean_needed() * 100.0)]
	if not Hub.can_pay(repair_cost(i)):
		return tr("Not enough cubes or parts.")  # [money]
	return ""


func upgrade_block(i: int) -> String:
	if i < 0 or i >= spots.size():
		return tr("No outpost.")
	var lv: int = level_of(i)
	if lv < 1:
		return tr("Repair it first.")
	if lv >= max_level():
		return tr("Fully upgraded.")
	if items.size() > i and items[i].busy:
		return "Building..."
	if not Hub.can_pay(upgrade_cost(i)):
		return tr("Not enough cubes or parts.")  # [money]
	return ""


func repair(i: int, animate: bool = true, free: bool = false) -> bool:
	if not free and repair_block(i) != "":
		return false
	if i < 0 or i >= spots.size() or level_of(i) >= 1:
		return false
	if not free and not Hub.pay(repair_cost(i)):
		return false
	_set_level(i, 1)
	_sweep(i)
	GameState.inc_stat("outposts_repaired")
	if i < items.size():
		Audio.play("buy", 1.0, -2.0)
		items[i].set_level(1, animate, func() -> void:
			EventBus.toast.emit(tr("Outpost %d repaired: a working scale on the frontier. Haul Bugs deliver to the nearest scale now.") % (i + 1), "story")
			Vfx.float_text(items[i].pad_world() + Vector3(0, 2.4, 0), tr("OUTPOST ONLINE"), Color(0.6, 1.0, 0.65), 1.6, 2.0)
			if world.get("wren") != null:
				world.wren.say("outpost_repaired", 1.0, true))
	return true


func upgrade(i: int, animate: bool = true, free: bool = false) -> bool:
	if not free and upgrade_block(i) != "":
		return false
	var lv: int = level_of(i)
	if lv < 1 or lv >= max_level():
		return false
	if not free and not Hub.pay(upgrade_cost(i)):
		return false
	_set_level(i, lv + 1)
	GameState.inc_stat("outposts_upgraded")
	if lv + 1 >= 3:
		GameState.inc_stat("outpost_pads")
	if i < items.size():
		Audio.play("buy", 1.0, -2.0)
		var nm: String = tr(str(level_def(lv + 1).get("name", "")))
		items[i].set_level(lv + 1, animate, func() -> void:
			EventBus.toast.emit(tr("Outpost %d upgraded: %s. %s") % [i + 1, nm, tr(str(level_def(lv + 1).get("desc", "")))], "story")
			if world.get("wren") != null:
				world.wren.say("outpost_upgraded", 1.0, true))
	return true


## The repair crew clears the slab: junk still lying inside the footprint is collected.
func _sweep(i: int) -> void:
	if world == null or world.get("field") == null or i >= spots.size():
		return
	var f: HexField = world.field
	var p: Vector3 = spots[i]["pos"]
	var foot: float = float(cfg.get("footprint", 3.6)) + 0.6
	for pid: int in f.pieces_within(p, foot):
		if f.piece_alive[pid] == 1 and not f.is_water(f.piece_hex[pid]):
			if world.has_method("collect_piece"):
				world.collect_piece(pid)
			else:
				f.remove_piece(pid)


static func cost_text(cost: Dictionary) -> String:
	return Currencies.cost_text(cost)  # [money] cubes / parts / seeds only


func prompt(i: int) -> String:
	var lv: int = level_of(i)
	if lv <= 0:
		if clean_fraction(i) < clean_needed():
			return tr("E   Ruined outpost · clear its hex first (%d%% / %d%%)") % [int(clean_fraction(i) * 100.0), int(clean_needed() * 100.0)]
		return tr("E   Repair outpost · %s%s") % [cost_text(repair_cost(i)), "" if Hub.can_pay(repair_cost(i)) else tr("  (need more)")]
	if lv >= max_level():
		return tr("E   Outpost %d · %s · bales +%d%%") % [i + 1, tr(str(level_def(lv).get("name", ""))), int(float(level_def(lv).get("sell_bonus", 0.0)) * 100.0)]
	return tr("E   Upgrade outpost: %s · %s%s") % [tr(str(level_def(lv + 1).get("name", ""))), cost_text(upgrade_cost(i)), "" if Hub.can_pay(upgrade_cost(i)) else tr("  (need more)")]


func use(i: int) -> void:
	var lv: int = level_of(i)
	if lv <= 0:
		var why: String = repair_block(i)
		if why == "":
			repair(i)
		else:
			EventBus.toast.emit(tr("Outpost %d: %s") % [i + 1, why], "info")
			Audio.play("error", 1.0, -8.0)
	elif lv < max_level():
		var why2: String = upgrade_block(i)
		if why2 == "":
			upgrade(i)
		else:
			EventBus.toast.emit(tr("Outpost %d upgrade: %s") % [i + 1, why2], "info")
			Audio.play("error", 1.0, -8.0)
	else:
		EventBus.toast.emit(tr("Outpost %d: %s. Bales sell for +%d%% here; robots crossing the pad get a speed charge.") % [i + 1, tr(str(level_def(lv).get("name", ""))), int(float(level_def(lv).get("sell_bonus", 0.0)) * 100.0)], "info")


# --- Queries for robots, water, HUD and Command view -----------------------------------

func working() -> Array[Outpost]:
	var out: Array[Outpost] = []
	for o: Outpost in items:
		if o.working():
			out.append(o)
	return out


## [outposts] The scale a Haul Bug at `pos` should deliver to: the nearest working one.
static func nearest_depot(w: Node, pos: Vector3) -> Depot:
	var best: Depot = w.depot as Depot if w and w.get("depot") is Depot else null
	var m: Outposts = _mgr(w)
	if m == null:
		return best
	var best_d: float = Vector2(best.global_position.x - pos.x, best.global_position.z - pos.z).length() if best else INF
	for o: Outpost in m.working():
		var p: Vector3 = o.scale_depot.global_position
		var d: float = Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = o.scale_depot
	return best


## True when `pos` is on a working outpost's scale plate (haulers leave those bales alone).
static func on_pad(w: Node, pos: Vector3) -> bool:
	var m: Outposts = _mgr(w)
	if m == null:
		return false
	for o: Outpost in m.items:
		if o.scale_depot and o.level >= 1 and o.scale_depot.pad_contains(pos):
			return true
	return false


## Park spot for an idle robot: in front of the nearest working outpost when that is closer than
## the base, else Vector3.INF.
static func idle_spot(w: Node, pos: Vector3, k: int) -> Vector3:
	var m: Outposts = _mgr(w)
	if m == null:
		return Vector3.INF
	var base_d: float = pos.distance_to(w.depot.global_position) if w.get("depot") != null else INF
	var best := Vector3.INF
	for o: Outpost in m.working():
		var d: float = pos.distance_to(o.global_position)
		if d < base_d:
			base_d = d
			best = o.idle_world(k)
	return best


## Speed factor for robot r: a Recharge Pad (level 3) charges any robot passing over it.
static func charge_mult(r: Node3D, w: Node, delta: float) -> float:
	var t: float = float(r.get_meta("charge_t", 0.0))
	var m: Outposts = _mgr(w)
	if m != null:
		var c: Dictionary = m.cfg
		var rad: float = float(c.get("charge_radius", 2.4))
		for o: Outpost in m.items:
			if o.level < 3 or o.busy:
				continue
			var cp: Vector3 = o.charger_world()
			if Vector2(cp.x - r.global_position.x, cp.z - r.global_position.z).length() < rad:
				if t < float(c.get("charge_s", 25.0)) - 1.0:
					Vfx.burst("sparkle", r.global_position + Vector3(0, 0.7, 0), Color(0.45, 0.9, 1.0), 0.6)
					Audio.play("chime", 1.6, -16.0)
				t = float(c.get("charge_s", 25.0))
				break
	if t <= 0.0:
		return 1.0
	t -= delta
	r.set_meta("charge_t", t)
	return float(m.cfg.get("charge_mult", 1.4)) if m else 1.4


## Refill points for Drips: the water drum at every working outpost (never runs dry).
func refill_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Outpost in working():
		out.append({"kind": "outpost", "pos": o.drum_world(), "index": o.index})
	return out


## Index of the outpost on hex h, or -1.
func outpost_on_hex(h: int) -> int:
	for i: int in spots.size():
		if int(spots[i]["hex"]) == h:
			return i
	return -1


## Short HUD note for the hex readout ("" if no outpost there).
func hex_note(h: int) -> String:
	var i: int = outpost_on_hex(h)
	if i < 0:
		return ""
	var lv: int = level_of(i)
	if lv <= 0:
		return tr("OUTPOST %d  RUINED · repair at %d%% clear") % [i + 1, int(clean_needed() * 100.0)]
	return tr("OUTPOST %d  %s") % [i + 1, tr(str(level_def(lv).get("name", ""))).to_upper()]
