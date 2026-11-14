class_name Pace
extends RefCounted
## [pace] The slow start (playtest #2): Lumi begins small and weak and earns his tools.
##   - Lift Strength (upgrade "lift_strength", stat lift_class): which junk sizes Lumi can scoop.
##     0 = small only, 1 = + medium (jerrycans, crates, rims), 2 = + large (tyres, TVs, fridges).
##   - Baler (upgrade "baler", stat baler_unlocked): the bale press in Lumi's chest. Before it is
##     bought, scooped junk is emptied into the yard trash bin (camp's TrashBin, group "trash_bin",
##     `deposit(volume) -> cubes paid`) or, without one, onto the scrap skip's scale pad, for a small
##     payout (data/patch.json "dump").
## Sizes come from HexField.piece_size when the field has it (world2), else from the piece's model
## base volume in data/junk.json (same thresholds as HexField.size_class).

const UP_BALER: String = "baler"
const UP_LIFT: String = "lift_strength"
const UP_SCOOP_SIZE: String = "multi_lock"
const SIZE_SMALL: int = 0
const SIZE_MEDIUM: int = 1
const SIZE_LARGE: int = 2
const MEDIUM_VOL: float = 1.5
const LARGE_VOL: float = 2.5
## Save version that introduced these upgrades (older saves are granted them, see migrate_save).
const SAVE_VERSION: int = 3
## How close Lumi rolls to the trash bin to empty his chest.
const BIN_RADIUS: float = 2.2

static var _model_vol: Dictionary = {}
static var _hint_t: int = 0
## [v3clear] When a scoop last met a piece too heavy to lift (ms; the objective card says so).
static var heavy_at: int = 0


static func size_class(base_vol: float) -> int:
	return SIZE_LARGE if base_vol >= LARGE_VOL else (SIZE_MEDIUM if base_vol >= MEDIUM_VOL else SIZE_SMALL)


static func baler_unlocked() -> bool:
	return Economy.stat("baler_unlocked") >= 0.5


## Largest size class Lumi can lift right now.
static func lift_class() -> int:
	return clampi(int(round(Economy.stat("lift_class"))), SIZE_SMALL, SIZE_LARGE)


static func _model_base_vol(model_id: String) -> float:
	if _model_vol.is_empty():
		var jd: Dictionary = Economy.read_json("res://data/junk.json")
		for t: Dictionary in jd.get("types", []):
			for m: Variant in t.get("models", []):
				if m is Dictionary:
					_model_vol[str(m.get("id", ""))] = float(m.get("vol", 1.0))
		for b: Variant in (jd.get("biomes", {}) as Dictionary).values():
			if not (b is Dictionary):
				continue
			for lst: Variant in ((b as Dictionary).get("models", {}) as Dictionary).values():
				for m: Variant in lst:
					if m is Dictionary and not _model_vol.has(str(m.get("id", ""))):
						_model_vol[str(m.get("id", ""))] = float(m.get("vol", 1.0))
	return float(_model_vol.get(model_id, 1.0))


## Size class of a field piece.
static func piece_size(field: Object, pid: int) -> int:
	var ps: Variant = field.get("piece_size")
	if ps is PackedByteArray and pid < (ps as PackedByteArray).size():
		return int((ps as PackedByteArray)[pid])
	var sc: int = SIZE_SMALL
	var pm: Variant = field.get("piece_model")
	if pm != null and pid < (pm as Array).size():
		sc = size_class(_model_base_vol(str(pm[pid])))
	else:
		sc = size_class(float(field.get("piece_vol")[pid]))
	# Without world2's piece_size the starting hexes may still hold big models; world2 swaps them
	# for small/medium ones, so count them as medium here (a no-op once that lands).
	if sc == SIZE_LARGE and field.has_method("hex_center") and field.get("piece_hex") != null:
		var c: Vector3 = field.call("hex_center", int(field.get("piece_hex")[pid]))
		if Vector2(c.x, c.z).length() <= float(field.get("hex_size")) * 1.9:
			sc = SIZE_MEDIUM
	return sc


## [v2feel] Whether Lumi can clean hex `h` with his current Lift Strength: the pieces he can't lift
## add up to no more than the part that sweeps away by itself once the hex counts as clean
## (field.clean_threshold, 95% on the globe). Objectives only pick hexes that pass.
static func hex_clearable(field: HexField, h: int, max_size: int = -1) -> bool:
	var lc: int = lift_class() if max_size < 0 else max_size
	if lc >= SIZE_LARGE or h < 0 or h >= field.hex_pieces.size():
		return true
	var heavy: float = 0.0
	for pid: int in field.hex_pieces[h]:
		if field.piece_alive[pid] == 1 and piece_size(field, pid) > lc:
			heavy += field.piece_vol[pid]
	return heavy <= (1.0 - field.clean_threshold) * field.hex_total[h] + 0.001


static func can_lift(field: Object, pid: int, max_size: int = -1) -> bool:
	return piece_size(field, pid) <= (lift_class() if max_size < 0 else max_size)


## HexField.find_scoop_target, skipping pieces heavier than `max_size`. Same zone and scoring.
static func find_scoop_target(field: HexField, origin: Vector3, forward: Vector3, reach: float, width: float, max_size: int) -> int:
	if max_size >= SIZE_LARGE:
		return field.find_scoop_target(origin, forward, reach, width)
	if field is SphereField:  # [orbB] globe: pieces live per cell, "up" is radial
		return (field as SphereField).find_scoop_target_sized(origin, forward, reach, width, max_size)
	var fwd: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
	var right: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	var best: int = -1
	var best_d: float = INF
	var near: Dictionary = {}
	for o: Vector3 in [Vector3.ZERO, fwd * reach, fwd * reach * 0.5 + right * width, fwd * reach * 0.5 - right * width]:
		var h: int = field.hex_at(origin + o)
		if h >= 0:
			near[h] = true
	for hid: int in near:
		if field.locked.has(hid):
			continue
		for pid: int in field.hex_pieces[hid]:
			if field.piece_alive[pid] == 0:
				continue
			var d: Vector3 = field.piece_pos[pid] - origin
			var z: float = d.dot(fwd)
			if z < -0.3 or z > reach:
				continue
			var x: float = absf(d.dot(right))
			if x > width * 0.5 + maxf(z, 0.0) * 0.25:
				continue
			var dist: float = z * z + x * x * 1.5
			if dist < best_d and piece_size(field, pid) <= max_size:
				best_d = dist
				best = pid
	return best


## Called when a scoop pulse found nothing liftable: if something too heavy is in the beam, say so
## (at most every few seconds).
## [v9b] The piece in the beam is marked every pulse (Vfx.heavy_mark: a ring and "Needs Lift N"), so
## a child sees which one won't come and why; the line under it says what to do. When the beam
## finds nothing at all but the hex Lumi works is unfinished and only too-heavy pieces are left in
## it, the same mark goes on the nearest of them with "This hex needs Lift N to finish".
static var heavy_need: int = 0  ## the Lift level the last too-heavy piece needs (the card's line)
static var heavy_hex: bool = false  ## that line was about a whole hex


static func heavy_hint(patch: Node3D, field: HexField, origin: Vector3, forward: Vector3, reach: float, width: float) -> void:
	var pid: int = field.find_scoop_target(origin, forward, reach, width)
	if pid >= 0 and can_lift(field, pid):
		return
	var h: int = field.hex_at(origin)
	var stuck: bool = hex_stuck(field, h)
	if pid < 0 and stuck:
		pid = _nearest_alive(field, h, origin)
	if pid < 0:
		return
	var need: int = piece_size(field, pid)
	if stuck:
		need = hex_need(field, h)
	var at: Vector3 = field.piece_pos[pid]
	Vfx.heavy_mark(at, clampf(pow(maxf(field.piece_vol[pid], 0.05), 1.0 / 3.0) * 0.9, 0.6, 2.2), need)
	heavy_need = need
	heavy_hex = stuck
	heavy_at = Time.get_ticks_msec()  # [v3clear]
	var now: int = Time.get_ticks_msec()
	if now - _hint_t < 4000:
		return
	_hint_t = now
	heavy_at = now  # [v3clear]
	# [v9d] No floating sentence: the piece's own label ("Needs Lift 2") and the card's hint say it once.
	Audio.play("buzz", 0.8, -12.0)


## [v9b] Hex `h` is unfinished, nothing left in it fits the scoop now, and what is left keeps it
## under the clean line: it can't finish until a Lift upgrade.
static func hex_stuck(field: HexField, h: int) -> bool:
	if h < 0 or h >= field.hex_pieces.size() or field.is_clean(h) or field.locked.has(h) or field.is_water(h):
		return false
	for pid: int in field.hex_pieces[h]:
		if field.piece_alive[pid] == 1 and can_lift(field, pid):
			return false
	return not hex_clearable(field, h)


## [v9b] The Lift level that lets hex `h` reach the clean line.
static func hex_need(field: HexField, h: int) -> int:
	for lv: int in range(lift_class() + 1, SIZE_LARGE + 1):
		if hex_clearable(field, h, lv):
			return lv
	return SIZE_LARGE


static func _nearest_alive(field: HexField, h: int, at: Vector3) -> int:
	var best: int = -1
	var bd: float = INF
	for pid: int in field.hex_pieces[h]:
		if field.piece_alive[pid] == 1:
			var d: float = field.piece_pos[pid].distance_squared_to(at)
			if d < bd:
				bd = d
				best = pid
	return best


## The line for the last too-heavy find.
static func heavy_line() -> String:
	if heavy_hex:
		return TranslationServer.translate("This hex needs Lift %d to finish. Upgrade at the workbench.") % heavy_need
	return TranslationServer.translate("Too heavy: this needs Lift %d. Upgrade at the workbench.") % heavy_need



## [orbC] When pressing a bale is the move. The player may press at any fill once the Baler is
## bought; this decides when the game says so (the hint below) and when the bot presses, so nobody
## waits forever with a chest just under the press threshold: at PRESS_AT full, or at least
## PRESS_SOON full when nothing within PRESS_LOOK_M can go in (every piece there too heavy for Lift
## Strength, or none left).
const PRESS_AT: float = 0.9
const PRESS_SOON: float = 0.5
const PRESS_LOOK_M: float = 6.0


static func press_ready(patch: Node3D, field: HexField) -> bool:
	var comp: Compartment = patch.get("compartment")
	if comp == null or comp.is_empty() or comp.pending > 0.0 or not baler_unlocked():
		return false
	if float(patch.get("_cubing")) > 0.0:
		return false
	var r: float = comp.ratio(float(patch.call("capacity")))
	if r >= PRESS_AT:
		return true
	return press_rule(r, r >= PRESS_SOON and field != null and not liftable_near(field, patch.call("scoop_origin"), PRESS_LOOK_M))


## The decision itself: chest share `r`, and whether nothing near can go in.
static func press_rule(r: float, nothing_fits: bool) -> bool:
	return r >= PRESS_AT or (r >= PRESS_SOON and nothing_fits)


## True if a piece Lumi can lift lies within `r` metres of `at`.
static func liftable_near(field: HexField, at: Vector3, r: float) -> bool:
	for pid: int in field.pieces_within(at, r):
		if field.piece_alive[pid] == 1 and not field.locked.has(field.piece_hex[pid]) and can_lift(field, pid):
			return true
	return false


## The prompt for that state: shown (at most every few seconds) when the scoop finds nothing.
static func press_hint(patch: Node3D, field: HexField) -> bool:
	var now: int = Time.get_ticks_msec()
	if now - _hint_t < 4000 or not press_ready(patch, field):
		return false
	_hint_t = now
	Vfx.float_text(patch.global_position + patch.call("up") * 1.9, TranslationServer.translate("Nothing here fits. Press [%s] to make a bale.") % Settings.glyph("cube"), Color(0.85, 1.0, 0.7), 0.4, 0.8)
	Audio.play("ding", 1.2, -12.0)
	return true


## Pressed the bale key without a Baler: a short hint instead.
static func baler_hint(patch: Node3D) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _hint_t < 2500:
		return
	_hint_t = now
	Audio.play("buzz", 1.2, -10.0)
	Vfx.float_text(patch.global_position + OrbitUp.up(patch.global_position) * 1.9, TranslationServer.translate("No Baler yet. Bring your chest to the bin."), Color(1.0, 0.85, 0.5), 0.4, 0.7)


# --- Emptying the chest (before the Baler) -------------------------------------------------

## Cubes paid for dumping `contents` (type -> volume) loose, without the trash bin's own rate.
static func dump_value(contents: Dictionary) -> float:
	var cfg: Dictionary = Economy.read_json("res://data/patch.json").get("dump", {}) if _dump_cfg.is_empty() else _dump_cfg
	_dump_cfg = cfg
	var v: float = 0.0
	for t: String in contents:
		v += float(contents[t]) * float(Economy.junk_types.get(t, {}).get("value", 1.0))
	return v * float(cfg.get("mult", 0.5)) * Economy.stat("cube_value_mult") * Hub.trade_mult()  # [v6pace] restored far hubs

static var _dump_cfg: Dictionary = {}


## True while Lumi may empty his chest loose (no Baler yet, or data allows it after).
static func dump_allowed() -> bool:
	if not baler_unlocked():
		return true
	if _dump_cfg.is_empty():
		_dump_cfg = Economy.read_json("res://data/patch.json").get("dump", {})
	return bool(_dump_cfg.get("after_baler", false))


## Empties Lumi's chest into `into` (a TrashBin with deposit(volume), else pays dump_value) and
## shows the payout at `at`. Returns cubes paid (0 if nothing happened).
static func dump_compartment(patch: Node3D, at: Vector3, into: Object = null) -> float:
	var comp: Compartment = patch.get("compartment")
	if comp == null or comp.is_empty() or comp.pending > 0.0 or float(patch.get("_cubing")) > 0.0:
		return 0.0
	var vol: float = comp.fill
	var contents: Dictionary = comp.take_all()
	var paid: float = 0.0
	if into != null and into.has_method("deposit"):
		paid = float(into.call("deposit", vol))  # camp's TrashBin pays (its tier rate) and returns it
	else:
		paid = dump_value(contents)
		GameState.add_currency("cubes", BigNum.from_float(paid))
	GameState.inc_stat("junk_dumps")
	var cap: float = float(patch.call("capacity"))
	EventBus.compartment_changed.emit(0.0, cap)
	var model: Node = patch.get("model")
	if model and model.has_method("set_fill"):
		model.call("set_fill", 0.0, [0.9, 1.0])
	# [v1guide] Owner 2026-11-08 #19: the toss needs a glint and a sound you always hear, and the
	# cubes should visibly tick into the counter (not just vanish).
	var up: Vector3 = OrbitUp.up(at)
	Audio.play("thunk", 1.0, -3.0)
	Audio.play("crunch", 1.2, -7.0)
	Audio.play("coin", 1.15, -2.0, 0.0)
	Vfx.burst("dust", at, Color(0.6, 0.55, 0.5, 0.5), 0.6)
	Vfx.burst("sparkle", at + up * 0.25, Color(1.0, 0.82, 0.4), 1.4)
	Vfx.ring(at - up * 0.75, 1.5, Color(1.0, 0.8, 0.35, 0.85), 0.55)
	if paid > 0.0:
		Vfx.float_text(at + up * 0.6, TranslationServer.translate("+%s cubes") % Settings.fmt(BigNum.from_float(paid)), Color(1.0, 0.86, 0.45), 0.6, 1.0)
		CoinFlight.fly(at, paid)
	return paid


## [v9a] After the Baler the bin takes no loose trash. A chest walked up to it got no word at all
## (goal audit): say what to do instead, at most every few seconds.
static func bin_refused_hint(patch: Node3D, bin_pos: Vector3) -> void:
	var comp: Compartment = patch.get("compartment") if patch else null
	if comp == null or comp.is_empty() or dump_allowed():
		return
	var d: Vector3 = patch.global_position - bin_pos
	d -= bin_pos.normalized() * d.dot(bin_pos.normalized())
	var now: int = Time.get_ticks_msec()
	if d.length() > BIN_RADIUS or now - _hint_t < 5000:
		return
	_hint_t = now
	Audio.play("buzz", 1.2, -12.0)
	Vfx.float_text(patch.global_position + OrbitUp.up(patch.global_position) * 1.9, TranslationServer.translate("No loose trash now. Press [%s] for a bale, then put it on the scale.") % Settings.glyph("cube"), Color(1.0, 0.85, 0.5), 0.45, 0.8)


## Per-frame check from the depot (and anything else Lumi can empty into): dumps when Lumi is
## within `radius` of `pos` with junk in his chest and dumping is allowed.
static func try_dump(patch: Node3D, pos: Vector3, radius: float, into: Object = null) -> float:
	if patch == null or not dump_allowed():
		return 0.0
	var d: Vector3 = patch.global_position - pos
	if JunkCube.planet_radius > 0.0:  # [orbit] round planet: drop the local-up part
		d -= pos.normalized() * d.dot(pos.normalized())
	else:
		d.y = 0.0
	if d.length() > radius:
		return 0.0
	return dump_compartment(patch, pos + OrbitUp.up(pos) * 0.8, into)  # [v1guide] the bin's mouth on the globe too


## The nearest trash bin node (camp's TrashBin, group "trash_bin") or null.
static func trash_bin(tree: SceneTree, near: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	for n: Node in tree.get_nodes_in_group("trash_bin"):
		if n is Node3D and n.has_method("deposit"):
			var dd: float = (n as Node3D).global_position.distance_to(near)
			if dd < best_d:
				best_d = dd
				best = n
	return best


# --- Saves ---------------------------------------------------------------------------------

## Saves from before the slow start keep what they had: Baler, full Lift Strength, and enough
## Compartment Size / Scoop Speed levels to cover the lower base capacity and scoop rate.
static func migrate_save(d: Dictionary) -> Dictionary:
	var ups: Dictionary = d.get("upgrades", {})
	ups[UP_BALER] = maxi(1, int(ups.get(UP_BALER, 0)))
	ups[UP_LIFT] = maxi(2, int(ups.get(UP_LIFT, 0)))
	var grant: Dictionary = Economy.read_json("res://data/patch.json").get("old_save_grant", {})
	for id: String in grant:
		ups[id] = int(ups.get(id, 0)) + int(grant[id])
	d["upgrades"] = ups
	var flags: Dictionary = d.get("flags", {})
	flags["pace_migrated"] = true
	d["flags"] = flags
	return d


## Dev shortcuts that jump into the mid/late game (--hub-level, --future, late/cradle starts) grant
## the early unlocks too, so those runs can bale and lift as before.
static func grant_early_unlocks() -> void:
	GameState.upgrades[UP_BALER] = maxi(1, GameState.level_of(UP_BALER))
	GameState.upgrades[UP_LIFT] = maxi(2, GameState.level_of(UP_LIFT))


# --- Magnet Arm ----------------------------------------------------------------------------

static var _mag_pids: PackedInt32Array = PackedInt32Array()
static var _mag_pick_t: float = 0.0


## Magnet Arm, tamed: pulls at most a few loose surface pieces at a time (never pieces inside a
## heap, never pieces Lumi can't lift), easing them in so nothing jitters against the pile.
static func magnet_step(patch: Node3D, field: HexField, view: Object, origin: Vector3, radius: float, delta: float) -> void:
	_mag_pick_t -= delta
	if _mag_pick_t <= 0.0:
		_mag_pick_t = 0.35
		var cap: int = 2 + int(Economy.stat("magnet_radius") / 0.6)  # about one more piece per Magnet Arm level
		var cands: Array = []
		var embed: PackedFloat32Array = field.get("piece_embed") if field.get("piece_embed") is PackedFloat32Array else PackedFloat32Array()
		for pid: int in field.pieces_within(origin, radius):
			if pid < embed.size() and embed[pid] > 0.0:
				continue  # part of a heap: stays put, the scoop digs it out
			if not can_lift(field, pid):
				continue
			cands.append([field.piece_pos[pid].distance_squared_to(origin), pid])
		cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		_mag_pids = PackedInt32Array()
		for i: int in mini(cap, cands.size()):
			_mag_pids.append(int(cands[i][1]))
	for pid: int in _mag_pids:
		if pid >= field.piece_alive.size() or field.piece_alive[pid] == 0:
			continue
		var to_me: Vector3 = origin - field.piece_pos[pid]
		if JunkCube.planet_radius > 0.0:  # [orbB] round planet: along the ground
			var u: Vector3 = field.piece_pos[pid].normalized()
			to_me -= u * to_me.dot(u)
		else:
			to_me.y = 0.0
		var dist: float = to_me.length()
		if dist > 0.5:
			# Ease in: fast far away, gentle at the end (no snapping into the scoop).
			var step: float = minf(clampf(dist * 1.6, 0.4, 2.2) * delta, dist - 0.45)
			view.call("move_piece", pid, field.piece_pos[pid] + to_me / dist * step)


# --- Unlock flags (for flag-gated events, requests and goals) ------------------------------

## Mirrors the unlock upgrades into GameState.flags: has_baler, has_lift_medium, has_lift_large,
## has_signal_finder. data/events.json requires.flag and request templates' "requires" read these.
static func sync_flags() -> void:
	GameState.flags["has_baler"] = baler_unlocked()
	GameState.flags["has_lift_medium"] = lift_class() >= SIZE_MEDIUM
	GameState.flags["has_lift_large"] = lift_class() >= SIZE_LARGE
	GameState.flags["has_signal_finder"] = signal_finder()


## The Signal Finder upgrade: the detector can lock onto strong pings (the violet-beam Rare Part
## Signal event). The buddy's scanner tiers may take this over later (same flag).
static func signal_finder() -> bool:
	return Economy.stat("signal_finder") >= 0.5
