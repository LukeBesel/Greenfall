class_name LedgerArc
extends Node3D
## The Ledger: an old corporate waste-management AI still running its contract.
##   Act 1 (after a few clean hexes): cold intercepted messages on the uplink, absurd "coupons".
##   Act 2 (after the first sprout): dump drones now and then drop a little junk back onto a clean,
##         unplanted hex. Signal Jammers at the base block drops in their radius; helpers tidy up.
##   Act 3 (hub level 3): WREN traces the relay; a relay terminal appears in this district.
##   Act 4 (Patch jacks in, short cinematic): the contract is rewritten; drones deliver seeds.
## State lives in GameState.flags (global) and GameState.world["ledger_jammers"] (per district).
## Drops edit the field's alive/clean bits directly, so saves stay consistent at any moment.

const JAMMER_SPOTS: Array[Vector3] = [Vector3(-8.2, 0, -1.4), Vector3(8.4, 0, 1.4), Vector3(-8.0, 0, 6.6)]

var world: Node
var cfg: Dictionary
var uplink: LedgerUplink
var drone: LedgerDrone
var relay: Node3D
var busy: bool = false
var rng := RandomNumberGenerator.new()

var _relay_screen: StandardMaterial3D
var _relay_light: OmniLight3D
var _relay_beacon: StandardMaterial3D
var _relay_beam: MeshInstance3D
var _relay_label: Label3D
var _jammers: Array[Node3D] = []
var _drop_timer: float = 0.0
var _coupon_timer: float = 0.0
var _seed_timer: float = 0.0
var _check_t: float = 0.0
var _t: float = 0.0
var _letterbox: CanvasLayer
var _bars: Array[ColorRect] = []


func setup() -> void:
	add_to_group("ledger")
	cfg = Economy.planet_table("ledger")
	StorySfx.ensure()
	rng.randomize()
	uplink = LedgerUplink.new()
	add_child(uplink)
	for i: int in (jammer_count() if _jam_here() else 0):  # [orbB] the jammers stand at the base (hub 0)
		_build_jammer(i, false)
	_coupon_timer = _range("coupon_every_s", 300.0) * 0.5
	_drop_timer = float(cfg.get("drop", {}).get("first_after_s", 45.0))
	_seed_timer = _range_of(cfg.get("seed_drop", {}).get("every_s", [200, 320]))
	_place_relay()
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: _check_acts())
	_dev_hooks.call_deferred()


func _dev_hooks() -> void:
	if DevHooks.has("ledger-act"):
		var a: int = int(DevHooks.get_f("ledger-act", 2.0))
		if a >= 2:
			GameState.flags["first_sprout"] = true
			GameState.flags["seeds_unlocked"] = true
		if a >= 3:
			GameState.flags["ledger_relay_hub"] = hub_index  # [orbB]
		GameState.flags["ledger_act"] = a
		GameState.flags["wren_awake"] = true
		_place_relay()
	if DevHooks.has("ledger-drop"):
		if act() < 2:
			GameState.flags["ledger_act"] = 2
			GameState.flags["wren_awake"] = true
		get_tree().create_timer(DevHooks.get_f("ledger-drop", 2.0), false).timeout.connect(func() -> void:
			if drop_candidates(world.field, is_planted).is_empty():
				_dev_clean_nearest()
			if not start_drop(true):
				print("[ledger] no hex to drop on"))
	if DevHooks.has("ledger-resolve") and relay:
		get_tree().create_timer(DevHooks.get_f("ledger-resolve", 2.0), false).timeout.connect(resolve)


## Dev only: clean the junk hex nearest to Patch so a drop has somewhere to land.
func _dev_clean_nearest() -> void:
	var field: SphereField = world.field
	var best: int = -1
	for id: int in frame_cells:  # [orbB] the hub region, made cells
		if field.hex_hub[id] != 0 or field.is_water(id) or field.is_clean(id) or field.materialized[id] == 0:
			continue
		if best < 0 or field.hex_center(id).distance_to(world.patch.global_position) < field.hex_center(best).distance_to(world.patch.global_position):
			best = id
	if best < 0:
		return
	for pid: int in field.hex_pieces[best]:
		if field.piece_alive[pid] == 1:
			world.collect_piece(pid)
	print("[ledger] dev: cleaned hex %d for the drop" % best)


# --- State --------------------------------------------------------------------------

static func act() -> int:
	return int(GameState.flags.get("ledger_act", 0))


static func resolved() -> bool:
	return act() >= 4


## Pure act progression rule (tested): returns the act the story should be in now.
static func next_act(cur: int, hexes_cleaned: int, first_sprout: bool, hub_level: int, a1_hexes: int = 3, a3_level: int = 3) -> int:
	var a: int = cur
	if a < 1 and hexes_cleaned >= a1_hexes:
		a = 1
	if a == 1 and first_sprout:
		a = 2
	if a == 2 and hub_level >= a3_level:
		a = 3
	return a


func _check_acts() -> void:
	if world == null or busy:
		return
	var cur: int = act()
	var hub_level: int = world.hub.level if world.get("hub") != null else 1
	var nxt: int = next_act(cur, int(GameState.stats.get("hexes_cleaned", 0)), bool(GameState.flags.get("first_sprout", false)), hub_level, int(cfg.get("act1_hexes", 3)), int(cfg.get("act3_hub_level", 3)))
	if nxt == cur:
		return
	GameState.flags["ledger_act"] = nxt
	EventBus.ledger_event.emit("act", {"act": nxt})
	if cur < 1 and nxt >= 1:
		for l: String in _act_lines("act1"):
			uplink.show_line(tr(l).format({"district": str(world.district_name).to_upper()}))
		_wren_later("ledger_intercept", 9.0)
	if cur < 2 and nxt >= 2:
		for l: String in _act_lines("act2"):
			uplink.show_line(l)
		_drop_timer = float(cfg.get("drop", {}).get("first_after_s", 45.0))
		_wren_later("ledger_drones", 7.0)
		get_tree().create_timer(14.0, false).timeout.connect(func() -> void:
			EventBus.toast.emit(tr("New at the workbench, Build tab: Signal Jammer. It scrambles the Ledger's drones near the base."), "hint"))
	if cur < 3 and nxt >= 3:
		GameState.flags["ledger_relay_hub"] = hub_index  # [orbB]
		_place_relay()
		for l: String in _act_lines("act3"):
			uplink.show_line(l)
		_wren_later("ledger_relay", 8.0)
		get_tree().create_timer(12.0, false).timeout.connect(func() -> void:
			if relay:
				EventBus.toast.emit(tr("WREN traced the Ledger's relay: %s of the hub. Look for the red beacon.") % compass_label(relay.position), "story"))  # [orbB] from the hub (frame-local)


## [money] Only the first uplink_lines_per_act lines of an act take the uplink banner (rarer,
## shorter intercepts).
func _act_lines(key: String) -> Array:
	var all: Array = cfg.get(key, [])
	return all.slice(0, maxi(int(cfg.get("uplink_lines_per_act", 1)), 0))


## [money] A small notify-stack entry instead of the big uplink banner.
func _note(text: String) -> void:
	EventBus.toast.emit(tr("Ledger: %s") % tr(text), "info" if Once.take("toast_ledger_note") else "reward")  # [v4calm] item 49: the first one only


func _wren_later(trigger: String, delay: float) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func() -> void:
		if world and world.get("wren") != null:
			world.wren.say(trigger, 1.0, true))


const COMPASS: Array[String] = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]


## English compass name (stable for logic and tests); compass_label() is the display copy.
static func compass(p: Vector3) -> String:
	# +X east, -Z north (CityLayout: x east, z south).
	var a: float = rad_to_deg(atan2(p.x, -p.z))
	return COMPASS[int(round(fposmod(a, 360.0) / 45.0)) % 8]


## [i18n] Translated compass direction for messages ("%s of you").
static func compass_label(p: Vector3) -> String:
	# TRANSLATORS: compass directions fill "%s of the hub" / "%s of you" ("north of you").
	var labels: Array[String] = [TranslationServer.translate("north"), TranslationServer.translate("north-east"),
		TranslationServer.translate("east"), TranslationServer.translate("south-east"),
		TranslationServer.translate("south"), TranslationServer.translate("south-west"),
		TranslationServer.translate("west"), TranslationServer.translate("north-west")]
	return labels[COMPASS.find(compass(p))]


func _range(key: String, default: float) -> float:
	var r: Variant = cfg.get(key, [default, default])
	return _range_of(r)


func _range_of(r: Variant) -> float:
	if r is Array and (r as Array).size() >= 2:
		return rng.randf_range(float(r[0]), float(r[1]))
	return float(r)


func _process(delta: float) -> void:
	_t += delta
	_animate_relay(delta)
	for j: Node3D in _jammers:
		var dish: Node3D = j.get_node_or_null("Dish")
		if dish:
			dish.rotate_y(delta * 0.8)
	if world == null or busy:
		return
	if world.get("intro") != null and world.intro.running:
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 2.0
		_check_acts()
	var a: int = act()
	if a >= 1 and a <= 3:
		_coupon_timer -= delta
		if _coupon_timer <= 0.0:
			_coupon_timer = _range("coupon_every_s", 300.0)
			_send_coupon()
	if (a == 2 or a == 3) and drone == null:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			var ok: bool = start_drop()
			_drop_timer = drop_interval() if ok else 40.0
	if a >= 4 and drone == null and GameState.flags.get("seeds_unlocked", false) and bool(cfg.get("seed_drop", {}).get("enabled", true)):  # [pace] no spontaneous crates
		_seed_timer -= delta
		if _seed_timer <= 0.0:
			_seed_timer = _range_of(cfg.get("seed_drop", {}).get("every_s", [200, 320]))
			start_seed_drop()


func _send_coupon() -> void:
	var all: Array = cfg.get("coupons", [])
	if all.is_empty():
		return
	var seen: Array = GameState.flags.get("ledger_coupons", [])
	var unseen: Array = []
	for i: int in all.size():
		if not (i in seen):
			unseen.append(i)
	var pick: int = int(unseen[rng.randi() % unseen.size()]) if not unseen.is_empty() else rng.randi() % all.size()
	if not (pick in seen):
		seen.append(pick)
	GameState.flags["ledger_coupons"] = seen
	_note(str(all[pick]))  # [money] a notify-stack line, not the uplink banner
	if world and world.get("wren") != null:
		world.wren.say("ledger_coupon", 0.25)


# --- Jammers ------------------------------------------------------------------------

func jammer_def() -> Dictionary:
	return cfg.get("jammer", {})


static func jammer_count() -> int:
	return int(GameState.world.get("ledger_jammers", 0))


func jammer_radius() -> float:
	var n: int = jammer_count()
	var radii: Array = jammer_def().get("radius", [22.0, 34.0, 48.0])
	return 0.0 if n <= 0 else float(radii[mini(n, radii.size()) - 1])


func jammer_cost_mult() -> float:
	return pow(float(jammer_def().get("growth", 2.2)), jammer_count())


func jammer_visible() -> bool:
	return act() >= 2 or jammer_count() > 0


func can_build_jammer() -> bool:
	var d: Dictionary = jammer_def()
	return _jam_here() and act() >= 2 and not resolved() and jammer_count() < int(d.get("max", 3)) and Hub.can_pay(d.get("cost", {}), jammer_cost_mult())


func build_jammer() -> bool:
	if not can_build_jammer():
		return false
	var d: Dictionary = jammer_def()
	if not Hub.pay(d.get("cost", {}), jammer_cost_mult()):
		return false
	var i: int = jammer_count()
	GameState.world["ledger_jammers"] = i + 1
	if world != null:  # (rule-only instances have no yard to stand it in)
		_build_jammer(i, true)
	EventBus.toast.emit(tr("Signal Jammer online. Drones within %d m of the base will get an earful of static.") % int(jammer_radius()), "story")
	EventBus.ledger_event.emit("jammer", {"count": i + 1})
	if world and world.get("wren") != null:
		world.wren.say("jammer_built", 1.0, true)
	return true


## Hub tab text (ui/hub_panel.gd shows it).
func jammer_text() -> String:
	var d: Dictionary = jammer_def()
	var n: int = jammer_count()
	var s: String = tr("%s   ·   %d / %d built\n%s") % [tr(str(d.get("name", "Signal Jammer"))), n, int(d.get("max", 3)), tr(str(d.get("desc", "")))]
	if n > 0:
		s += tr("\nCovering %d m around the base.") % int(jammer_radius())
	if resolved():
		s += tr("\nThe Ledger is on our side now. The jammers just hum along to the music.")
	elif n < int(d.get("max", 3)):
		s += "\n" + tr("Needs %s") % HubPanel.cost_text(d.get("cost", {}), jammer_cost_mult())
	return s


## Seconds until the next drone (rarer with every jammer).
func drop_interval() -> float:
	var base: float = _range_of(cfg.get("drop", {}).get("every_s", [170, 280]))
	return base * (1.0 + float(jammer_def().get("rarer_per_jammer", 0.35)) * jammer_count())


func _build_jammer(i: int, animate: bool) -> void:
	var n := Node3D.new()
	n.name = "Jammer%d" % i
	add_child(n)
	n.position = jammer_spot(i)
	# [yard] Kit base, mast and dish (systems/camp/yard_art.gd); the Dish turns, the Tip glows.
	var base_mi: MeshInstance3D = YardArt.jammer_base().mi(0.15, "Base")
	n.add_child(base_mi)
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.5, 0.12, 0.02)), Mats.lamp(Color(0.3, 0.8, 1.0), 1.4), Vector3(0, 0.42, 0.485)))
	var dish := Node3D.new()
	dish.name = "Dish"
	dish.position = Vector3(0, 3.0, 0)
	n.add_child(dish)
	dish.add_child(YardArt.jammer_dish().mi(0.15, "Bowl"))
	var tip := EggProps.mesh(ProcMesh.sphere(0.06, 8, 4), Mats.lamp(Color(0.3, 0.8, 1.0), 4.0), Vector3(0, 0.2, 0.58))
	tip.name = "Tip"
	dish.add_child(tip)
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 0.8, 1.0)
	l.light_energy = 0.8
	l.omni_range = 3.0
	l.position = Vector3(0, 3.2, 0.4)
	n.add_child(l)
	EggProps.collider(n, Vector3(0.9, 0.6, 0.9), Vector3(0, 0.3, 0))
	_jammers.append(n)
	if animate:
		n.scale = Vector3(1, 0.01, 1)
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK)
		tw.tween_callback(func() -> void:
			Vfx.burst("sparkle", n.to_global(Vector3(0, 3.0, 0)), Color(0.4, 0.85, 1.0))
			Vfx.ring(n.global_position, jammer_radius(), Color(0.4, 0.85, 1.0, 0.7), 1.4)
			Audio.play("servo", 1.0, -6.0))


# --- Drops --------------------------------------------------------------------------

func is_planted(hid: int) -> bool:
	if world == null or world.get("garden") == null:
		return false
	var g: Garden = world.garden
	for s: int in g.hex_slots.get(hid, PackedInt32Array()):
		if g.slot_species[s] >= 0:
			return true
	return false


## Clean, unplanted, dry, non-hub hexes that still have removed pieces to bring back.
static func drop_candidates(field: HexField, planted: Callable = Callable(), cells: Variant = null) -> Array[int]:
	var out: Array[int] = []
	var sf: SphereField = field as SphereField
	for id: int in (cells if cells != null else range(field.hex_count())):  # [orbB] a hub region's cells on the globe
		if field.hex_hub[id] != 0 or field.is_water(id) or not field.is_clean(id):
			continue
		if sf and sf.materialized[id] == 0:  # [orbB] only cells Lumi's ring made have pieces to bring back
			continue
		if planted.is_valid() and bool(planted.call(id)):
			continue
		out.append(id)
	return out


## A small cluster of removed pieces in one hex: enough volume to dirty it again (a few % of the
## hex), never more than max_pieces. Clustered around one dead piece so it reads as one dump.
static func pick_drop_pieces(field: HexField, hid: int, r: RandomNumberGenerator, frac: float = 0.045, min_n: int = 3, max_n: int = 14) -> PackedInt32Array:
	var dead: Array[int] = []
	for pid: int in field.hex_pieces[hid]:
		if field.piece_alive[pid] == 0:
			dead.append(pid)
	var out := PackedInt32Array()
	if dead.size() < min_n:
		return out
	var seed_pid: int = dead[r.randi() % dead.size()]
	var c: Vector3 = field.piece_pos[seed_pid]
	dead.sort_custom(func(a: int, b: int) -> bool: return field.piece_pos[a].distance_squared_to(c) < field.piece_pos[b].distance_squared_to(c))
	var need: float = maxf(frac, (1.0 - field.clean_threshold) * 1.3) * field.hex_total[hid]
	var vol: float = 0.0
	for pid: int in dead:
		if out.size() >= max_n or (vol >= need and out.size() >= min_n):
			break
		out.append(pid)
		vol += field.piece_vol[pid]
	return out


func _ground(x: float, z: float) -> float:
	return to_local((world.field as SphereField).terrain.ground(to_global(Vector3(x, 0.0, z)).normalized())).y


## Starts a dump run. Returns false if there is nothing to drop on.
func start_drop(force: bool = false) -> bool:
	if drone != null or world == null:
		return false
	var field: HexField = world.field
	var cands: Array[int] = drop_candidates(field, is_planted, frame_cells)
	if cands.is_empty():
		return false
	var pp: Vector3 = world.patch.global_position
	# Prefer hexes near Patch so the event is seen; pick among the closest few.
	cands.sort_custom(func(a: int, b: int) -> bool: return field.hex_center(a).distance_squared_to(pp) < field.hex_center(b).distance_squared_to(pp))
	var dc: Dictionary = cfg.get("drop", {})
	var pids := PackedInt32Array()
	var hid: int = -1
	for k: int in mini(cands.size(), 6):
		var h: int = cands[rng.randi() % mini(cands.size(), 3)] if k < 3 else cands[k]
		pids = pick_drop_pieces(field, h, rng, float(dc.get("volume_frac", 0.045)), int(dc.get("min_pieces", 3)), int(dc.get("max_pieces", 14)))
		if not pids.is_empty():
			hid = h
			break
	if hid < 0:
		return false
	var spot := Vector3.ZERO
	for pid: int in pids:
		spot += field.piece_pos[pid]
	spot /= pids.size()
	spot = to_local(spot)  # [orbB] frame-local from here on
	spot.y = _ground(spot.x, spot.z)
	var jammed: bool = jammer_count() > 0 and _jam_here() and Vector2(spot.x, spot.z).length() < jammer_radius() and not force
	_fly_dump(hid, pids, spot, jammed)
	return true


func _spawn_drone(friendly: bool, from: Vector3) -> LedgerDrone:
	var d := LedgerDrone.new()
	d.friendly = friendly
	d.ground_y = _ground
	add_child(d)
	d.position = from  # [orbB] the Ledger's frame (its parent's; the world on the flat game)
	return d


func _marker(spot: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = ProcMesh.torus(2.2, 2.45, 40, 4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.disable_receive_shadows = true
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = Vector3(1, 0.05, 1)
	add_child(m)
	m.position = spot + Vector3(0, 0.06, 0)  # [orbB]
	var tw := m.create_tween().set_loops()
	tw.tween_property(m, "scale", Vector3(0.8, 0.05, 0.8), 0.45)
	tw.tween_property(m, "scale", Vector3(1.05, 0.05, 1.05), 0.45)
	return m


func _fly_dump(hid: int, pids: PackedInt32Array, spot: Vector3, jammed: bool) -> void:
	var warn: Array = cfg.get("drop_warn", [])
	var first: bool = int(GameState.stats.get("ledger_drops", 0)) == 0 and int(GameState.stats.get("ledger_jammed", 0)) == 0
	EventBus.toast.emit(tr("Ledger drone inbound, %s! It's heading for a clean hex.") % compass_label(spot - to_local(world.patch.global_position)) if not first
		else tr("A Ledger drone is coming to dump junk on a clean hex (%s of you). It can't touch planted ground.") % compass_label(spot - to_local(world.patch.global_position)),
		"story" if first or BeepGate.take("toast_ledger_drone", 600.0) else "reward")  # [v4calm] item 49: at most one warning per 10 min
	if not warn.is_empty() and first:  # [money] only the very first drone gets the uplink banner
		uplink.show_line(str(warn[rng.randi() % warn.size()]))
	Audio.play("glitch", 0.8, -8.0)
	var marker: MeshInstance3D = _marker(spot, Color(1.0, 0.25, 0.15, 0.55))
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.BACK
	# (Screenshot runs render at a fraction of real time: start the approach close by.)
	var from: Vector3 = spot + dir * 70.0 + Vector3(0, 22, 0)
	var hover: Vector3 = spot + Vector3(0, 6.5, 0)
	var warn_s: float = float(cfg.get("drop", {}).get("warn_s", 6.5))
	if DevHooks.has("shot"):
		# Screenshot runs render at a fraction of real time: start right next to the spot.
		from = hover + dir * 4.0 + Vector3(0, 1.0, 0)
		warn_s = 1.5
	drone = _spawn_drone(false, from)
	var tw := drone.create_tween()
	if jammed:
		# Stop at the edge of the jammer field (a few meters outside it).
		var edge_flat: Vector3 = Vector3(spot.x, 0, spot.z).normalized() * (jammer_radius() + 4.0)
		var edge := Vector3(edge_flat.x, hover.y + 2.0, edge_flat.z)
		if Vector2(from.x, from.z).length() < jammer_radius() + 4.0:
			edge = from.lerp(hover, 0.3)
		tw.tween_property(drone, "position", edge, warn_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void: _jammed(marker, from))
	else:
		tw.tween_property(drone, "position", hover, warn_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func() -> void: _dump(hid, pids, marker, from))


func _jammed(marker: MeshInstance3D, exit_from: Vector3) -> void:
	var d: LedgerDrone = drone
	if d == null:
		return
	Vfx.burst("bits", d.global_position, Color(0.4, 0.85, 1.0), 1.5)
	Vfx.float_text(to_global(d.position + Vector3(0, 1.2, 0)), tr("SIGNAL JAMMED"), Color(0.45, 0.9, 1.0), 1.6, 1.2)
	Audio.play("buzz", 0.7, -4.0)
	Audio.play("glitch", 1.2, -6.0)
	for j: Node3D in _jammers:
		Vfx.ring(j.global_position, 3.0, Color(0.4, 0.85, 1.0, 0.8), 0.8)
	Vfx.ring(to_global(Vector3.ZERO), jammer_radius(), Color(0.4, 0.85, 1.0, 0.5), 1.2)
	var j_lines: Array = cfg.get("jammed", [])
	if not j_lines.is_empty() and rng.randf() < float(cfg.get("jammed_line_chance", 0.35)):  # [money]
		_note(str(j_lines[rng.randi() % j_lines.size()]))
	GameState.inc_stat("ledger_jammed")
	EventBus.ledger_event.emit("jammed", {})
	if world.get("wren") != null:
		world.wren.say("ledger_jammed", 0.8, true)
	marker.queue_free()
	var tw := d.create_tween()
	tw.tween_property(d, "rotation:z", 0.5, 0.15)
	tw.tween_property(d, "rotation:z", -0.5, 0.2)
	tw.tween_property(d, "rotation:z", 0.0, 0.15)
	tw.tween_property(d, "position", exit_from + Vector3(0, 8, 0), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_drone_done.bind(d))


func _dump(hid: int, pids: PackedInt32Array, marker: MeshInstance3D, exit_from: Vector3) -> void:
	var d: LedgerDrone = drone
	if d == null:
		return
	var field: HexField = world.field
	# Re-check: Patch may have planted here (or the hex got dirty) during the approach.
	if not field.is_clean(hid) or is_planted(hid):
		marker.queue_free()
		uplink.show_line(tr("Target re-classified as ASSET. Aborting. ...Interesting."))
		var tw0 := d.create_tween()
		tw0.tween_property(d, "position", exit_from, 6.0).set_trans(Tween.TRANS_SINE)
		tw0.tween_callback(_drone_done.bind(d))
		return
	d.set_beam(3.0)
	var tw := d.create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(d.open_bin.bind(true))
	tw.tween_interval(0.4)
	tw.tween_callback(func() -> void: _release(hid, pids, marker))
	tw.tween_interval(2.4)
	tw.tween_callback(d.open_bin.bind(false))
	tw.tween_callback(d.set_beam.bind(0.0))
	tw.tween_property(d, "position", exit_from + Vector3(0, 10, 0), 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_drone_done.bind(d))


## Junk falls out of the bin onto the hex. The field is updated first (so a save mid-fall is
## consistent); the multimesh pieces are shown when everything has landed.
func _release(hid: int, pids: PackedInt32Array, marker: MeshInstance3D) -> void:
	var field: HexField = world.field
	var view: FieldView = world.view
	var origin: Vector3 = to_global(drone.position + Vector3(0, -0.7, 0)) if drone else to_global(to_local(field.hex_center(hid)) + Vector3(0, 6, 0))
	field.revive_pieces(pids)
	# [orbB] The cell's numbers follow (dirty again: the save and the ground texture).
	var so: SliceOrbit = world.orbit
	if field.hex_clean[hid] == 0:
		so.globe.cells.set_state(hid, 0)
	so.globe.write_cell(hid)
	var last: float = 0.0
	var falling: Array[Node3D] = []
	for i: int in pids.size():
		var pid: int = pids[i]
		var target: Transform3D = view.piece_transform(pid)
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh_lite(field.piece_model[pid], 700)
		add_child(mi)
		falling.append(mi)
		var start := Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)).scaled(Vector3.ONE * field.piece_scale[pid]), origin + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)))
		mi.global_transform = start
		var delay: float = i * 0.07
		var dur: float = rng.randf_range(0.65, 0.9)
		last = maxf(last, delay + dur)
		var tw := mi.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(mi, "global_transform", target, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			Vfx.burst("dust", target.origin + OrbitUp.up(target.origin) * 0.1, Color(0.6, 0.55, 0.5, 0.6), 0.4)
			if i % 3 == 0:
				Audio.play("clink", rng.randf_range(0.8, 1.1), -10.0))
	get_tree().create_timer(last + 0.05, false).timeout.connect(func() -> void: _landed(hid, pids, marker, falling))


func _landed(hid: int, pids: PackedInt32Array, marker: MeshInstance3D, falling: Array[Node3D]) -> void:
	for n: Variant in falling:
		if is_instance_valid(n):
			(n as Node).queue_free()
	if is_instance_valid(marker):
		marker.queue_free()
	var field: HexField = world.field
	world.view.refresh_hex(hid)
	EventBus.field_progress_changed.emit(field.cleaned_count, field.junk_hex_count)
	EventBus.shake_requested.emit(0.15)
	Audio.play("crunch", 0.8, -6.0)
	GameState.inc_stat("ledger_drops")
	print("[ledger] drop landed: hex %d, %d pieces, clean=%s" % [hid, pids.size(), str(field.is_clean(hid))])
	EventBus.ledger_event.emit("drop", {"hex": hid, "pieces": pids.size()})
	if int(GameState.stats.get("ledger_drops", 0)) <= 1:
		EventBus.toast.emit(tr("The drone dumped a little junk back. Scoop it up, or let your helpers tidy it. A Signal Jammer at the base keeps drones away."), "hint")
	if world.get("wren") != null and Once.take("wren_ledger_drop"):  # [v4calm] once per save
		world.wren.say("ledger_drop", 0.9, true)


func _drone_done(d: LedgerDrone) -> void:
	if is_instance_valid(d):
		d.queue_free()
	if drone == d:
		drone = null


# --- Seed deliveries (after the contract is rewritten) -------------------------------

func start_seed_drop(at: Vector3 = Vector3.INF) -> bool:
	if drone != null or world == null:
		return false
	var spot: Vector3 = at
	if spot == Vector3.INF:
		var pp: Vector3 = to_local(world.patch.global_position)  # [orbB]
		spot = pp
		for k: int in 20:
			var c: Vector3 = pp + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(5.0, 10.0)
			var h: int = world.field.hex_at(to_global(c))
			if h >= 0 and not world.field.is_water(h) and (world.field.layout == null or world.field.layout.surface_at(c.x, c.z) != CityLayout.Surface.BUILDING):
				spot = c
				break
	spot.y = _ground(spot.x, spot.z)
	var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	var from: Vector3 = spot + dir * 60.0 + Vector3(0, 20, 0)
	drone = _spawn_drone(true, from)
	var crate: Node3D = _seed_crate()
	drone.cargo.add_child(crate)
	var d: LedgerDrone = drone
	var tw := d.create_tween()
	tw.tween_property(d, "position", spot + Vector3(0, 5.5, 0), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(d.open_bin.bind(true))
	tw.tween_interval(0.35)
	tw.tween_callback(func() -> void: _drop_crate(crate, spot))
	tw.tween_interval(1.0)
	tw.tween_callback(d.open_bin.bind(false))
	tw.tween_property(d, "position", spot - dir * 60.0 + Vector3(0, 24, 0), 7.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_drone_done.bind(d))
	if rng.randf() < float(cfg.get("friendly_line_chance", 0.2)):  # [money] rarer, as a small note
		var fl: Array = cfg.get("friendly", [])
		if not fl.is_empty():
			_note(str(fl[rng.randi() % fl.size()]))
	return true


func _seed_crate() -> Node3D:
	var n := Node3D.new()
	n.set_meta("keep", true)
	var wood: StandardMaterial3D = AssetLib.pbr_material("painted_metal_shutter", 0.6, Color(0.5, 0.85, 0.55), true)
	n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(0.6, 0.45, 0.45), 0.04, 2), wood, Vector3(0, -0.2, 0)))
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.62, 0.06, 0.47)), Mats.lamp(Color(0.4, 1.0, 0.5), 1.2), Vector3(0, -0.2, 0)))
	n.add_child(EggProps.label(tr("SEEDS · PAID IN FULL"), 18, Color(0.1, 0.25, 0.12), Vector3(0, -0.12, 0.231)))
	return n


func _drop_crate(crate: Node3D, spot: Vector3) -> void:
	var gp: Vector3 = crate.global_position
	crate.get_parent().remove_child(crate)
	add_child(crate)
	crate.global_position = gp
	var tw := crate.create_tween()
	tw.tween_property(crate, "position", spot + Vector3(0, 0.43, 0), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		var r: Array = cfg.get("seed_drop", {}).get("seeds", [3, 6])
		var n: int = rng.randi_range(int(r[0]), int(r[1]))
		GameState.add_currency("seeds", BigNum.from_float(n))
		GameState.inc_stat("ledger_seed_drops")
		Vfx.burst("sparkle", to_global(spot + Vector3(0, 0.6, 0)), Color(0.6, 1.0, 0.6))
		Vfx.float_text(to_global(spot + Vector3(0, 1.4, 0)), tr("+%d seeds") % n, Color(0.6, 1.0, 0.6), 1.3, 1.5)
		Audio.play("pop", 1.0, -4.0)
		EventBus.ledger_event.emit("seeds", {"seeds": n})
		if world.get("wren") != null:
			world.wren.say("ledger_seeds", 0.5))
	tw.tween_interval(18.0)
	tw.tween_property(crate, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
	tw.tween_callback(crate.queue_free)


# --- Relay terminal -------------------------------------------------------------------

func relay_visible() -> bool:
	return act() >= 3 and int(GameState.flags.get("ledger_relay_hub", -1)) == hub_index


func _place_relay() -> void:
	if relay != null or world == null or not relay_visible():
		return
	var spot: Dictionary = relay_spot_cells(self, world.field, frame_cells, hub_index)
	relay = _build_relay()
	add_child(relay)
	relay.transform = spot["xf"]  # [orbB] frame-local, upright on the ground's own up
	_set_relay_friendly(resolved(), false)
	if world.get("interactables") != null:
		world.interactables.register(relay, 3.2, func() -> String:
			return tr("E   jack in: rewrite the Ledger's contract") if act() == 3 else tr("E   read the amended contract"), _use_relay)


func _use_relay() -> void:
	if busy:
		return
	if act() == 3:
		resolve()
	elif resolved() and world.get("doc_view") != null:
		world.doc_view.show_doc(cfg.get("contract_doc", {}))


func _build_relay() -> Node3D:
	var n := Node3D.new()
	n.name = "LedgerRelay"
	var conc: StandardMaterial3D = AssetLib.pbr_material("concrete_floor_worn_001", 0.6, Color(0.75, 0.73, 0.7), true)
	var body: ShaderMaterial = Mats.worn_paint(Color(0.22, 0.23, 0.26), 0.85, 0.45, 81.0, 0.6)
	var steel: StandardMaterial3D = Mats.metal("dark_steel")
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(3.2, 0.3, 2.4)), conc, Vector3(0, 0.15, 0)))
	n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(1.6, 2.4, 0.9), 0.06, 2), body, Vector3(0, 1.5, -0.3)))
	n.add_child(EggProps.mesh(ProcMesh.rounded_box(Vector3(1.8, 0.2, 1.1), 0.05, 2), body, Vector3(0, 2.8, -0.3)))
	# Slanted console in front with the screen.
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.4, 0.9, 0.5)), body, Vector3(0, 0.75, 0.35)))
	_relay_screen = Mats.lamp(Color(1.0, 0.2, 0.12), 1.6)
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.2, 0.7, 0.03)), _relay_screen, Vector3(0, 1.85, 0.16)))
	_relay_label = EggProps.label(tr("LEDGER RELAY 07\nCONTRACT 0001: ACTIVE\nWASTE IS A LINE ITEM"), 30, Color(1.0, 0.85, 0.75), Vector3(0, 1.85, 0.18), Vector3.ZERO, true)
	_relay_label.font = LedgerUplink.mono_font()
	n.add_child(_relay_label)
	for k: int in 6:
		n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.12, 0.05, 0.02)), Mats.lamp([Color(1, 0.6, 0.1), Color(1, 0.2, 0.1)][k % 2], 1.5), Vector3(-0.45 + k * 0.18, 1.1, 0.61), Vector3(-30, 0, 0)))
	n.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.2, 0.04, 0.4)), steel, Vector3(0, 1.21, 0.38), Vector3(-30, 0, 0)))
	# Antenna mast with a blinking beacon, plus cables snaking off into the ground.
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.09, 5.0, 8), steel, Vector3(0.55, 5.4, -0.5)))
	for k: int in 3:
		n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.9 - k * 0.2, 0.04, 0.04)), steel, Vector3(0.55, 6.2 + k * 0.6, -0.5)))
	_relay_beacon = Mats.lamp(Color(1.0, 0.15, 0.1), 5.0)
	n.add_child(EggProps.mesh(ProcMesh.sphere(0.14, 10, 5), _relay_beacon, Vector3(0.55, 8.0, -0.5)))
	for k: int in 3:
		var cab := EggProps.mesh(ProcMesh.cyl(0.05, 0.05, 2.0 + k * 0.6, 6), Mats.rubber(), Vector3(-0.9 - k * 0.5, 0.32, -0.6 + k * 0.4), Vector3(0, 30.0 + k * 20.0, 88))
		n.add_child(cab)
	n.add_child(EggProps.label(tr("RELAY 07  ·  PROPERTY OF THE LEDGER  ·  NO UNSCHEDULED ACCESS"), 20, Color(0.9, 0.85, 0.7), Vector3(0, 0.75, 0.605)))
	_relay_light = OmniLight3D.new()
	_relay_light.light_color = Color(1.0, 0.25, 0.15)
	_relay_light.light_energy = 2.0
	_relay_light.omni_range = 7.0
	_relay_light.position = Vector3(0, 2.2, 1.4)
	n.add_child(_relay_light)
	# A faint vertical beam so it can be found from across the district.
	_relay_beam = MeshInstance3D.new()
	_relay_beam.mesh = ProcMesh.cyl(0.25, 0.25, 60.0, 10)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.disable_fog = true
	bm.albedo_color = Color(1.0, 0.3, 0.2, 0.3)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_relay_beam.material_override = bm
	_relay_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_relay_beam.position = Vector3(0.55, 38.0, -0.5)
	n.add_child(_relay_beam)
	EggProps.collider(n, Vector3(1.8, 2.9, 1.6), Vector3(0, 1.45, -0.1))
	return n


func _set_relay_friendly(v: bool, animate: bool) -> void:
	if relay == null:
		return
	var c: Color = Color(0.35, 1.0, 0.5) if v else Color(1.0, 0.2, 0.12)
	if animate:
		var tw := create_tween()
		tw.tween_method(func(x: float) -> void:
			var cc: Color = Color(1.0, 0.2, 0.12).lerp(Color(1.0, 0.7, 0.2), clampf(x * 2.0, 0.0, 1.0)).lerp(Color(0.35, 1.0, 0.5), clampf(x * 2.0 - 1.0, 0.0, 1.0))
			_relay_screen.emission = cc
			_relay_light.light_color = cc
			_relay_beacon.emission = cc, 0.0, 1.0, 2.5)
	else:
		_relay_screen.emission = c
		_relay_light.light_color = c
		_relay_beacon.emission = c
	_relay_label.text = tr("LEDGER RELAY 07\nCONTRACT 0001: AMENDED\nRESTORATION = ASSET") if v else tr("LEDGER RELAY 07\nCONTRACT 0001: ACTIVE\nWASTE IS A LINE ITEM")
	_relay_label.modulate = Color(0.8, 1.0, 0.85) if v else Color(1.0, 0.85, 0.75)
	_relay_beam.visible = not v


func _animate_relay(_delta: float) -> void:
	if relay == null:
		return
	var blink: bool = fmod(_t, 1.6) < 0.2
	_relay_beacon.emission_energy_multiplier = 7.0 if blink else 2.0
	_relay_light.light_energy = 1.6 + sin(_t * 3.0) * 0.4
	if _relay_beam.visible:
		(_relay_beam.material_override as StandardMaterial3D).albedo_color.a = 0.24 + 0.08 * sin(_t * 2.0)


# --- Resolution cinematic ------------------------------------------------------------

func _ensure_letterbox() -> void:
	if _letterbox:
		return
	_letterbox = CanvasLayer.new()
	_letterbox.layer = 25
	add_child(_letterbox)
	for top: bool in [true, false]:
		var r := ColorRect.new()
		r.color = Color.BLACK
		r.anchor_right = 1.0
		r.anchor_top = 0.0 if top else 1.0
		r.anchor_bottom = 0.0 if top else 1.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_letterbox.add_child(r)
		_bars.append(r)


func _bars_to(px: float) -> void:
	for i: int in _bars.size():
		var tw := create_tween()
		tw.tween_property(_bars[i], "offset_bottom" if i == 0 else "offset_top", px if i == 0 else -px, 0.8)


func _set_player(enabled: bool) -> void:
	(world.orbit as SliceOrbit).set_input(enabled)  # Lumi's input and the SphereCam
	world.hud.visible = enabled


## Patch jacks into the relay; WREN rewrites the contract. Ends in act 4.
func resolve() -> void:
	if busy or relay == null or act() != 3:
		return
	busy = true
	_ensure_letterbox()
	_set_player(false)
	if world.get("music") != null:
		world.music.set_cinematic(true)
	_bars_to(90.0)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	var prev: Camera3D = get_viewport().get_camera_3d()
	cam.current = true
	# [orbB] All in the Ledger's frame (the hub frame).
	var rp: Vector3 = relay.position
	var fwd: Vector3 = relay.transform.basis.z
	var right: Vector3 = relay.transform.basis.x
	var look := rp + Vector3(0, 1.7, 0)
	var orbit := func(a: float, dist: float, h: float) -> void:
		var off: Vector3 = (fwd * cos(a) + right * sin(a)) * dist
		cam.position = rp + off + Vector3(0, h, 0)
		cam.look_at(to_global(look), global_basis.y)
	orbit.call(0.9, 6.5, 2.2)
	# Patch steps up to the console.
	var pp: Vector3 = rp + fwd * 1.6 + Vector3(0, 0.05, 0)
	var ptw := create_tween()
	ptw.tween_property(world.patch, "global_position", to_global(pp), 1.2).set_trans(Tween.TRANS_SINE)
	var lines: Array = cfg.get("cinematic", [])
	var total: float = 0.0
	for l: Array in lines:
		total += float(l[2])
	var otw := create_tween()
	otw.tween_method(func(v: float) -> void: orbit.call(lerpf(0.9, -0.7, v), lerpf(6.5, 4.6, v), lerpf(2.2, 1.6, v)), 0.0, 1.0, total * 0.7).set_trans(Tween.TRANS_SINE)
	Audio.play("glitch", 0.7, -4.0)
	var pname: String = str(GameState.flags.get("patch_name", "Lumi"))
	for i: int in lines.size():
		var l: Array = lines[i]
		var who: String = str(l[0])
		var text: String = tr(str(l[1])).format({"name": pname})  # [l10n]
		var dur: float = float(l[2])
		dur = maxf(dur, Subtitles.total_time(text))  # [intro2] every line stays up long enough to read
		match who:
			"wren": uplink._bind().show_now(text, "wren")
			"ledger": uplink.show_now(text, false)
			"friendly": uplink.show_now(text, true)
		if str(l[1]).begins_with("RECALCULATING"):
			_set_relay_friendly(true, true)
			Vfx.burst("big_sparkle", to_global(rp + Vector3(0, 2.0, 0.4)), Color(0.5, 1.0, 0.6))
			Audio.play("chime", 0.8, -4.0)
			EventBus.shake_requested.emit(0.2)
		if who == "friendly":
			_cinematic_drones(rp, cam, look)
		await get_tree().create_timer(dur, false).timeout
	_bars_to(0.0)
	if is_instance_valid(prev):
		prev.current = true
	else:
		(world.orbit as SliceOrbit).cam.camera.current = true
	cam.queue_free()
	_set_player(true)
	if world.get("music") != null:
		world.music.set_cinematic(false)
	GameState.flags["ledger_act"] = 4
	GameState.flags["ledger_resolved"] = true
	var rew: Dictionary = cfg.get("resolve_reward", {})
	for k: String in rew:
		GameState.add_currency(k, BigNum.from_float(float(rew[k])))
	GameState.flags["seeds_unlocked"] = true
	Audio.music_sting("first_sprout")
	EventBus.toast.emit(tr("The Ledger's contract is rewritten. Its drones deliver seeds now. (+%d seeds)") % int(rew.get("seeds", 0)), "story")
	EventBus.ledger_event.emit("resolved", {})
	world.wren.say("ledger_resolved", 1.0, true)
	_seed_timer = 25.0
	busy = false
	print("[ledger] contract rewritten: act %d" % act())
	if (GameState.flags.get("ledger_coupons", []) as Array).size() >= (cfg.get("coupons", []) as Array).size():
		get_tree().create_timer(30.0, false).timeout.connect(func() -> void:
			uplink.show_line(str(cfg.get("lonely", "")), true, tr("<< LEDGER // OFF THE RECORD >>")))


func _cinematic_drones(rp: Vector3, cam: Camera3D, look: Vector3) -> void:
	# Two repainted drones sweep over the relay; one leaves a seed crate beside it.
	for k: int in 2:
		var side: Vector3 = relay.transform.basis.x * (1.0 if k == 0 else -1.0)
		var d := _spawn_drone(true, rp - relay.transform.basis.z * 40.0 + side * 8.0 + Vector3(0, 14, 0))
		d.set_friendly(true)
		var tw := d.create_tween()
		tw.tween_property(d, "position", rp + relay.transform.basis.z * 3.0 + side * 3.0 + Vector3(0, 6.0 + k, 0), 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if k == 0:
			var crate := _seed_crate()
			d.cargo.add_child(crate)
			tw.tween_callback(d.open_bin.bind(true))
			tw.tween_callback(func() -> void: _drop_crate(crate, rp + relay.transform.basis.z * 3.0 + side * 2.2))
		tw.tween_interval(2.0)
		tw.tween_property(d, "position", rp + relay.transform.basis.z * 60.0 + Vector3(0, 25, 0), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(d.queue_free)
	# The camera lifts and tilts up to watch them come in.
	var ctw := create_tween()
	var from: Vector3 = cam.position
	ctw.tween_method(func(v: float) -> void:
		cam.position = from + Vector3(0, v * 1.5, 0)
		cam.look_at(to_global(look.lerp(rp + Vector3(0, 6.0, 0) + relay.transform.basis.z * 2.0, v)), global_basis.y), 0.0, 1.0, 3.0).set_trans(Tween.TRANS_SINE)


# --- [orbB] The globe: the Ledger per hub, in the hub frame (planet/orbit/hub_frame.gd) ----------
# Its acts, coupons and seeds are global (GameState.flags); drones, markers, crates and the relay
# live in the frame (site-local metres, +Y up), converting at the edges. The jammers stand at the
# base (hub 0); the relay appears at the hub where act 3 began.

var hub_index: int = 0  # the hub this Ledger runs at (set by the frame host)
var frame_cells := PackedInt32Array()  # that hub's region


func _jam_here() -> bool:
	return hub_index == 0


## The relay spot of a hub (frame-local {pos, yaw, hex, xf}): among the farthest open cells of
## its region, outside the site, clear of the outposts; upright on the ground's own up.
static func relay_spot_cells(frame: Node3D, f: SphereField, cells: PackedInt32Array, hub: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = f.seed_value + 555 + hub * 71
	var outposts: Array[Vector3] = []
	for o: Dictionary in Outposts.plan_cells(frame, f, cells, {}, hub):
		outposts.append(o["pos"])
	var cand: Array = []  # [distance, cell]
	for id: int in cells:
		if f.hex_hub[id] != 0 or f.is_water(id) or f.cells.has_flag(id, SphereCells.F_SITE):
			continue
		var c: Vector3 = frame.to_local(f.hex_center(id))
		cand.append([Vector2(c.x, c.z).length(), id])
	if cand.is_empty():
		return {"pos": Vector3(12, 0, 12), "yaw": 0.0, "hex": -1, "xf": Transform3D(Basis.IDENTITY, Vector3(12, 0, 12))}
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var far: Array = cand.slice(0, maxi(8, int(cand.size() / 10.0)))
	var best: Vector3 = frame.to_local(f.terrain.ground(f.hex_center(int(far[0][1])).normalized()))
	var best_hex: int = int(far[0][1])
	for attempt: int in 60:
		var id: int = int(far[r.randi() % far.size()][1])
		var c: Vector3 = frame.to_local(f.hex_center(id)) + Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * f.hex_size * 0.45
		var wp: Vector3 = f.terrain.ground(frame.to_global(c).normalized())
		if f.hex_at(wp) != id:
			continue
		var clash: bool = false
		var tr_: TargetReach = TargetReach.for_field(f)  # [v4world] #55: not in a town building or walled in
		if tr_ and tr_.reach(wp) != "":
			continue
		for o: Vector3 in outposts:
			if Vector2(o.x - c.x, o.z - c.z).length() < 12.0:
				clash = true
		for lm: Dictionary in f.landmarks:
			if OrbitUp.ground_dist(lm["pos"], wp) < 3.5:
				clash = true
		if clash:
			continue
		best = frame.to_local(wp)
		best_hex = id
		break
	var tr2: TargetReach = TargetReach.for_field(f)  # [v4world] #55: the fallback too
	if tr2 and tr2.reach(frame.to_global(best)) != "":
		best = frame.to_local(tr2.open_spot(frame.to_global(best)))
	var yaw: float = atan2(-best.x, -best.z)
	var up: Vector3 = (frame.global_basis.inverse() * f.up_at(frame.to_global(best))).normalized()
	var bas: Basis = Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)
	return {"pos": best, "yaw": yaw, "hex": best_hex, "xf": Transform3D(bas, best)}


const YARD_ANCHORS: Array[String] = ["bench", "depot", "bin", "pod", "signal_tower", "telescope", "radio", "locker", "nursery", "rocket_pad", "stations"]


## Jammer i's spot at the base, frame-local on the ground. The site prefab's yard has its own
## furniture, so the first free points on rings 9-15 m out are taken (clear of the yard anchors and
## the other jammers, nothing solid there). Deterministic.
func jammer_spot(i: int) -> Vector3:
	var so: SliceOrbit = world.orbit
	var taken: Array[Vector3] = []
	for nm: String in YARD_ANCHORS:
		taken.append(to_local(so.yard_point(nm)))
	var found: Array[Vector3] = []
	for rr: float in [9.0, 11.0, 13.0, 15.0]:
		for k: int in 24:
			var a: float = TAU * (float(k) + (0.5 if int(rr) % 2 == 1 else 0.0)) / 24.0 + 2.6
			var c := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
			c.y = _ground(c.x, c.z)
			var ok: bool = true
			for t: Vector3 in taken + found:
				if Vector2(t.x - c.x, t.z - c.z).length() < (4.0 if found.has(t) else 3.5):
					ok = false
					break
			if ok and not _solid_at(c):
				found.append(c)
				if found.size() > i:
					return found[i]
	return JAMMER_SPOTS[i % JAMMER_SPOTS.size()]


func _solid_at(c: Vector3) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var sh := CylinderShape3D.new()
	sh.radius = 0.8
	sh.height = 2.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(global_basis.orthonormalized(), to_global(c + Vector3(0, 1.5, 0)))
	q.collision_mask = 1 | PhysLayers.PROP  # the static world and props (the site prefabs' structures)
	return not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()
