class_name HubPurpose
extends Node
## [v6hubs] Runs every hub's purpose (planet/sites/hub_plan.gd, data/planets.json) on the globe:
## - arriving at a far hub (a rocket hop or a walk): its name on screen once, then a small card
##   with the first local step (clean N hexes here, repair an outpost, wake the landmark);
## - E at the hub's landmark once the local steps are done: pays the wake price, restores the hub
##   (SiteManager.set_level(i, 2) + set_built(i)), lights the landmark's beacon, gives the hub's
##   rocket piece, gift and boosts, and stands a field bench by the rocket pad;
## - a woken hub's level then follows its region's clean share (hub_defaults.level_at), so the
##   robots left there restore the town while Lumi is away;
## - the HUD's lines: this base's clean % and "Bases n/6" (hud_lines()).
## Use: HubPurpose.attach(orbit_sites) once the hop and the site manager exist.
## Dev: --hub-wake=N wakes hub N for free at start; --hub-report prints each hub's line;
## --hub-dev-chain[=T] does a hub's chain and wake after each arrival; --hub-dev-save=T saves;
## --hub-walkthrough[=T] flies to and wakes every main-path hub in order and checks each (HubWalk).

signal woke(site: int)

const POLL_S: float = 0.5
const BEACON_H: float = 110.0
const LANDMARK_REACH_M: float = 11.0  # how near the landmark's foot E wakes it
const GOLD := Color(1.0, 0.82, 0.42)
const TEAL := Color(0.47, 0.86, 0.78)
const CREAM := Color(0.98, 0.93, 0.8)

var sites: OrbitSites
var so: SliceOrbit
var sm: SiteManager
var planet: String = "verdance"
var site: int = -1          # the hub Lumi is at (-1: between hubs)
var card_text: String = ""  # what the card shows now (tests, the clarity log)
var title_reason: String = ""  # the arrival title's "why we came" line (tests, the walkthrough)
var _t: float = 0.0
var _lvl_t: float = 0.0
var _spot: Node3D           # the landmark's interact anchor
var _beacon: Node3D
var _bench: Node3D
var _way: Waypoint
var _layer: CanvasLayer
var _card: PanelContainer
var _card_title: Label
var _card_body: Label
var _title: Control
var _lm_site: int = -1


static func attach(p_sites: OrbitSites) -> HubPurpose:
	var h := HubPurpose.new()
	h.name = "HubPurpose"
	h.sites = p_sites
	h.so = p_sites.so
	h.sm = p_sites.sm
	h.planet = p_sites.sm.planet_id if p_sites.sm else "verdance"
	p_sites.add_child(h)
	return h


func _ready() -> void:
	HubPlan.active_planet = planet
	if sm == null or not HubPlan.has_plan(planet):
		set_process(false)
		return
	_spot = Node3D.new()
	_spot.name = "LandmarkSpot"
	_spot.visible = false
	add_child(_spot)
	_register_spot()
	_way = Waypoint.new()
	_way.world = so.w
	add_child(_way)
	_way.set_target(null)
	_build_ui()
	sites.hop.hopped.connect(_on_hopped)
	_apply_saved()
	if DevHooks.has("hub-wake"):
		for s: String in DevHooks.get_s("hub-wake", "").split(",", false):
			wake(int(s), true)
	if DevHooks.has("hub-dev-save"):  # dev: save after T s (a walkthrough across a reload)
		get_tree().create_timer(DevHooks.get_f("hub-dev-save", 30.0)).timeout.connect(func() -> void:
			print("[hubs] dev: saved %s (bases %d/%d, rocket at site %d)" % [SaveManager.save_game(), HubPlan.restored_main(planet), HubPlan.main_total(planet), sites.rocket_site()]))
	if DevHooks.has("hub-report"):
		get_tree().create_timer(DevHooks.get_f("hub-report", 5.0)).timeout.connect(report)
	if DevHooks.has("hub-walkthrough"):  # dev: fly to and wake every main-path hub, check each (planet/sites/hub_walk.gd)
		HubWalk.run_dev(self)


## The landmark's E entry. The site manager (and this node) come up before the yard's Interactables
## exist, so this is retried from _process until it takes (before: E at a landmark did nothing).
func _register_spot() -> bool:
	if _spot_registered:
		return true
	var ia: Variant = so.w.get("interactables")
	if ia is Interactables:
		(ia as Interactables).register(_spot, LANDMARK_REACH_M, landmark_prompt, use_landmark, func() -> bool: return _spot.visible and not sites.hop.flying)
		_spot_registered = true
	return _spot_registered


var _spot_registered: bool = false


func _exit_tree() -> void:
	if HubPlan.active_planet == planet:
		HubPlan.active_planet = ""


## A loaded save: the woken hubs count for the planet again and stand at their level.
func _apply_saved() -> void:
	for e: Dictionary in HubPlan.entries(planet):
		var i: int = int(e["site"])
		if i > 0 and i < sm.sites.size() and HubPlan.woken(i):
			sm.set_built(i)
			if sm.levels[i] < 2:
				sm.set_level(i, 2)


# --- Where Lumi is ---------------------------------------------------------------------------------

func _current_site() -> int:
	var hf: HubFrame = so.hub_frame
	if hf and hf.hub >= 0:
		return hf.hub
	return -1


func _process(delta: float) -> void:
	_t += delta
	if _t < POLL_S:
		return
	_t = 0.0
	_register_spot()
	var now: int = -1 if sites.hop.flying else _current_site()
	if now != site:
		site = now
		if site >= 0:
			_enter(site, false)
	_lvl_t += POLL_S
	if _lvl_t >= 3.0:
		_lvl_t = 0.0
		_update_levels()
	_refresh()


func _on_hopped(to_i: int) -> void:
	site = to_i
	_enter(to_i, true)
	_refresh()


func _enter(i: int, by_rocket: bool) -> void:
	var e: Dictionary = HubPlan.entry(planet, i)
	if e.is_empty():
		return
	if HubPlan.is_home(planet, i) and not by_rocket:
		return  # the start of the game, or a walk back: nothing to announce
	var st: Dictionary = HubPlan.state(i)
	var first: bool = not bool(st.get("seen", false))
	if first:
		st["seen"] = true
		st["base"] = clean_cells(i)
		if not HubPlan.is_home(planet, i):
			GameState.inc_stat("hubs_seen")  # goal steps: "fly to the next hub" = stat hubs_seen >= n
	var clean: float = sm.region_clean(i)
	if by_rocket or first:
		show_title(i, first)
	if HubPlan.is_home(planet, i):
		if by_rocket:
			EventBus.toast.emit(tr("Home. The workbench is by the pod."), "info")
	elif first:
		if str(e.get("hint", "")) != "":
			EventBus.toast.emit(tr(str(e["hint"])), "story")
		if not GameState.flags.get("hub_home_hint", false):
			GameState.flags["hub_home_hint"] = true
			EventBus.toast.emit(tr("The rocket waits on the pad. Home is first on its list."), "info")
	elif by_rocket:
		var was: float = float(st.get("last_clean", clean))
		var gain: int = int(round((clean - was) * 100.0))
		var line: String = crew_line(i)
		if gain >= 1:
			EventBus.toast.emit(tr("%s: %d%% clean, up %d%% while you were away.") % [HubPlan.hub_name(planet, i), int(clean * 100.0), gain], "info")
		elif line != "":
			EventBus.toast.emit("%s: %s" % [HubPlan.hub_name(planet, i), line], "info")
	st["last_clean"] = clean
	if DevHooks.has("hub-dev-chain") and i > 0:
		_dev_chain(i)


# --- Progress ----------------------------------------------------------------------------------------

## Clean junk cells of hub i's region (water and hub ground left out).
func clean_cells(i: int) -> int:
	if sm.cells == null or i < 0 or i >= sm.regions.size():
		return 0
	var n: int = 0
	var cs: SphereCells = sm.cells
	for c: int in sm.regions[i]:
		if cs.state[c] == 5 or (cs.flags[c] & SphereCells.F_HUB) != 0:
			continue
		if not cs.is_dirty(c):
			n += 1
	return n


## Hexes cleaned at hub i since Lumi first arrived.
func cleaned_here(i: int) -> int:
	var st: Dictionary = HubPlan.peek(i)
	if not st.has("base"):
		return 0
	return maxi(0, clean_cells(i) - int(st["base"]))


func _outposts_here(i: int) -> int:
	var op: Variant = so.w.get("outposts")
	var kept: int = int(HubPlan.peek(i).get("outposts", 0))
	if op is Outposts and (op as Outposts).hub_index == i:
		return maxi(kept, (op as Outposts).repaired_count())
	return kept


## The hub's steps with their progress: [{do, have, need, done}].
func steps(i: int) -> Array:
	var out: Array = []
	var ok_so_far: bool = true
	for s: Dictionary in HubPlan.chain(planet, i):
		var d: Dictionary = {"do": str(s["do"]), "have": 0, "need": 1, "done": false}
		match str(s["do"]):
			"clean":
				d["need"] = int(s.get("hexes", 8))
				d["have"] = mini(cleaned_here(i), int(d["need"]))
			"outposts":
				d["need"] = int(s.get("count", 1))
				d["have"] = mini(_outposts_here(i), int(d["need"]))
				HubPlan.state(i)["outposts"] = int(d["have"])
			"wake":
				d["have"] = 1 if HubPlan.woken(i) else 0
		d["done"] = HubPlan.woken(i) or int(d["have"]) >= int(d["need"])
		d["open"] = ok_so_far and not bool(d["done"])
		ok_so_far = ok_so_far and bool(d["done"])
		out.append(d)
	return out


## The step to do now at hub i ({} when the hub is woken or has no chain).
func current_step(i: int) -> Dictionary:
	for d: Dictionary in steps(i):
		if not bool(d["done"]):
			return d
	return {}


func can_wake(i: int) -> bool:
	return str(current_step(i).get("do", "")) == "wake"


func step_text(i: int, d: Dictionary) -> String:
	match str(d.get("do", "")):
		"clean":
			return tr("Dig the landmark out. Clean hexes here: %d / %d") % [int(d["have"]), int(d["need"])]
		"outposts":
			return tr("Repair an outpost here: %d / %d") % [int(d["have"]), int(d["need"])]
		"wake":
			if HubPlan.at_limit(planet):
				return tr("Upgrade the rocket, then wake the %s") % HubPlan.landmark_name(planet, i)
			return tr("Wake the %s (%s)") % [HubPlan.landmark_name(planet, i), Outposts.cost_text(HubPlan.wake_cost(planet))]
	return ""


# --- The landmark ------------------------------------------------------------------------------------

## World transform of hub i's landmark foot and its top ({} until its town is built).
func landmark(i: int) -> Dictionary:
	var p: SitePrefab = sm.prefab(i)
	if p == null or not p.is_built or not p.is_inside_tree():
		return {}
	if p.content:
		for c: Node in p.content.get_children():
			var dr: Variant = c.get("dressing")
			if dr is StreetDressing and (dr as StreetDressing).is_inside_tree():
				var info: Dictionary = (dr as StreetDressing).landmark_info()
				if str(info["kind"]) != "":
					var xf: Transform3D = (dr as StreetDressing).global_transform
					var top: Vector3 = info["top"]
					if top == Vector3.ZERO:
						top = (info["pos"] as Vector3) + Vector3(0, 14.0, 0)
					return {"pos": xf * (info["pos"] as Vector3), "top": xf * top, "up": xf.basis.y.normalized()}
	var pad: Transform3D = sm.pad_xf(i)
	var at: Vector3 = pad * Vector3(-9.0, 0.0, -6.0)
	return {"pos": at, "top": at + pad.basis.y * 10.0, "up": pad.basis.y.normalized()}


func landmark_prompt() -> String:
	if site < 0 or HubPlan.woken(site):
		return ""
	var d: Dictionary = current_step(site)
	if str(d.get("do", "")) == "wake" and HubPlan.at_limit(planet):
		return limit_text()
	if str(d.get("do", "")) == "wake":
		return tr("E   Wake the %s  (%s)") % [HubPlan.landmark_name(planet, site), Outposts.cost_text(HubPlan.wake_cost(planet))]
	return tr("%s: asleep. %s") % [HubPlan.landmark_name(planet, site), step_text(site, d)]


## Why one more base can't be restored yet (the rocket's tier).
func limit_text() -> String:
	return tr("The rocket can carry supplies to %d bases. Upgrade it at the workbench.") % HubPlan.rocket_limit()


func use_landmark() -> void:
	if site < 0 or HubPlan.woken(site):
		return
	if not can_wake(site):
		EventBus.toast.emit(step_text(site, current_step(site)), "info")
		return
	if HubPlan.at_limit(planet):
		Audio.play("blip", 0.7, -6.0)
		EventBus.toast.emit(limit_text(), "hint")
		return
	var cost: Dictionary = HubPlan.wake_cost(planet)
	if not GameState.can_afford_all(cost):
		Audio.play("blip", 0.7, -6.0)
		EventBus.toast.emit(tr("Waking the %s needs %s.") % [HubPlan.landmark_name(planet, site), Outposts.cost_text(cost)], "hint")
		return
	wake(site)


## Restores hub i (free: no price, the dev hook and tests). Returns whether it woke now.
func wake(i: int, free: bool = false) -> bool:
	if i <= 0 or i >= sm.sites.size() or HubPlan.woken(i) or HubPlan.entry(planet, i).is_empty():
		return false
	if not free and not GameState.spend_all(HubPlan.wake_cost(planet)):
		return false
	var st: Dictionary = HubPlan.state(i)
	if not st.has("base"):
		st["seen"] = true
		st["base"] = clean_cells(i)
	var lines: Array[String] = HubPlan.wake(planet, i)
	sm.set_built(i)
	sm.set_level(i, maxi(2, sm.levels[i]))
	var tl: String = HubPlan.trade_line()  # the per-hub multiplier (v6pace's Hub.trade_mult, off SiteManager.built)
	if tl != "":
		lines.append(tl)
	Audio.play("thud", 0.8, -4.0)
	Audio.music_sting("level_up")
	HubPlan.opt_static("res://systems/tunes.gd", "play_moment", ["base_restored"])  # v6sound: a song for the moment, once one is marked
	EventBus.shake_requested.emit(0.25)
	EventBus.toast.emit(tr("%s is awake. %s keeps cleaning when you fly on.") % [HubPlan.landmark_name(planet, i), HubPlan.hub_name(planet, i)], "story")
	if not lines.is_empty():
		EventBus.toast.emit(" · ".join(lines), "story")
	print("[hubs] woke site %d (%s): level %d, bases %d/%d, gave %s" % [i, str(HubPlan.entry(planet, i).get("id", "")), sm.levels[i], HubPlan.restored_main(planet), HubPlan.main_total(planet), str(lines)])
	woke.emit(i)
	_lm_site = -1
	_refresh()
	return true


## A woken hub's level follows its region's clean share (2 at the wake, then level_at).
func _update_levels() -> void:
	var at: Variant = HubPlan.defaults(planet).get("level_at", [0.2, 0.45, 0.75])
	for e: Dictionary in HubPlan.entries(planet):
		var i: int = int(e["site"])
		if i <= 0 or i >= sm.sites.size() or not HubPlan.woken(i):
			continue
		var share: float = sm.region_clean(i)
		var lv: int = 2
		if at is Array:
			for th: Variant in at:
				if share >= float(th):
					lv += 1
		lv = clampi(lv, 2, 5)
		if lv > sm.levels[i]:
			sm.set_level(i, lv)
			if i == site:
				EventBus.toast.emit(tr("%s grows: level %d.") % [HubPlan.hub_name(planet, i), lv], "info")
		if i == site:
			HubPlan.state(i)["last_clean"] = share


# --- Robots (v6crew's SphereCrew.hub_summary when present) ------------------------------------------

func crew_summary(i: int) -> Dictionary:
	var crew: Variant = so.crews.crew if so.crews else null
	if crew == null or i < 0 or i >= sm.sites.size():
		return {"robots": 0}
	var cell: int = int(sm.sites[i]["cell"])
	if (crew as Object).has_method("hub_summary"):
		var v: Variant = (crew as Object).call("hub_summary", cell)
		if v is Dictionary:
			return v
	var n: int = 0
	for u: Dictionary in (crew as SphereCrew).robots():
		if int(u.get("hub", -1)) == cell:
			n += 1
	return {"robots": n}


func crew_line(i: int) -> String:
	var s: Dictionary = crew_summary(i)
	if str(s.get("text", "")) != "":
		return str(s["text"])
	var n: int = int(s.get("robots", 0))
	return tr_n("%d robot working", "%d robots working", n) % n if n > 0 else ""


# --- What the HUD and the picker show ---------------------------------------------------------------

## The town type as built: the data's `town`, or a harbour where the lake reaches into the town.
func town_name(i: int) -> String:
	var actual: String = ""
	if PlanetCfg.uses_towns(planet) and i > 0 and i < sm.sites.size():  # [v7planet] towns kit: harbours
		if not _harbour.has(i):
			_harbour[i] = VerdanceSite.is_harbour(sm.water_fn(i))
		if bool(_harbour[i]):
			actual = "harbour"
	return HubPlan.town_name(planet, i, actual)


var _harbour: Dictionary = {}


## "New", "Asleep: 3 / 8 hexes", "Restored: 34% clean".
func status_text(i: int) -> String:
	if HubPlan.is_home(planet, i):
		return tr("Home: %d%% clean") % int(sm.region_clean(i) * 100.0)
	if HubPlan.woken(i):
		return tr("Restored: %d%% clean") % int(sm.region_clean(i) * 100.0)
	if not HubPlan.seen(i):
		return tr("New")
	var d: Dictionary = current_step(i)
	if str(d.get("do", "")) == "wake":
		return tr("Ready to wake")
	return tr("Asleep: %d / %d") % [int(d.get("have", 0)), int(d.get("need", 1))]


## The HUD's two lines on a planet with a hub plan: {"field", "frac", "planet"}.
func hud_lines() -> Dictionary:
	var i: int = site if site >= 0 else (sm.nearest if sm.nearest >= 0 else 0)
	var nm: String = HubPlan.hub_name(planet, i)
	if nm == "":
		return {}
	var share: float = sm.region_clean(i)
	return {
		"field": tr("%s   %d%% CLEAN") % [nm.to_upper(), int(floor(share * 100.0))],
		"frac": share,
		"planet": tr("%s   BASES %d/%d") % [tr(str(Economy.planet.get("name", "Verdance"))).to_upper(), HubPlan.restored_main(planet), HubPlan.main_total(planet)],
	}


## For goal steps (story/objectives.gd step targets): where the beam should stand for
## "rocket" (the parked rocket: fly to the next hub, or upgrade it) and "landmark" (the landmark of
## the far hub Lumi is at). Null when there is nothing to point at.
func goal_target(kind: String) -> Variant:
	match kind:
		"rocket":
			return sites.rocket_spot.global_position if sites.rocket_spot and sites.rocket_spot.visible else null
		"landmark":
			var lm: Dictionary = landmark(site) if site > 0 else {}
			return lm["pos"] if not lm.is_empty() else null
	return null


## Where the workbench is for Lumi now: the field bench of the woken far hub he is at, else null
## (the home bench).
func bench_point() -> Variant:
	if site > 0 and HubPlan.woken(site) and _bench and _bench.visible:
		return _bench.global_position
	return null


func _refresh() -> void:
	var far: bool = site > 0 and not HubPlan.entry(planet, site).is_empty()
	var lm: Dictionary = landmark(site) if far else {}
	# The landmark's anchor, beacon and beam.
	_spot.visible = far and not lm.is_empty() and not HubPlan.woken(site)
	if not lm.is_empty():
		_spot.global_position = lm["pos"]
	var ready_now: bool = far and not lm.is_empty() and can_wake(site)
	_way.set_target(lm["pos"] if ready_now else null)
	_show_beacon(far and not lm.is_empty() and HubPlan.woken(site), lm)
	_show_bench(far and HubPlan.woken(site))
	# The card.
	var title: String = ""
	var body: String = ""
	if far:
		title = HubPlan.hub_name(planet, site)
		var d: Dictionary = current_step(site)
		if not d.is_empty():
			body = step_text(site, d)
		else:
			var nx: int = HubPlan.next_site(planet)
			if nx >= 0 and HubPlan.is_main(planet, nx):
				body = tr("Restored. Next: take the rocket to %s.") % HubPlan.hub_name(planet, nx)
			elif HubPlan.is_main(planet, site) and HubPlan.restored_main(planet) >= HubPlan.main_total(planet):
				body = tr("All %d bases stand. Fly home and make the rocket ready to leave.") % HubPlan.main_total(planet)
	card_text = (title + ": " + body) if body != "" else ""
	_card.visible = body != "" and not bool(so.w.get("launching")) and not (_title != null and is_instance_valid(_title))  # the name first, then the step
	if _card.visible:
		_card_title.text = title.to_upper()
		_card_body.text = body


func _show_beacon(on: bool, lm: Dictionary) -> void:
	if not on:
		if _beacon:
			_beacon.visible = false
		return
	if _beacon == null:
		_beacon = Node3D.new()
		_beacon.name = "LandmarkBeacon"
		add_child(_beacon)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.25
		cm.bottom_radius = 0.9
		cm.height = BEACON_H
		cm.radial_segments = 10
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		mi.mesh = cm
		mi.position = Vector3(0, BEACON_H * 0.5, 0)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(GOLD, 0.32)
		m.disable_fog = true
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beacon.add_child(mi)
		var lt := OmniLight3D.new()
		lt.light_color = GOLD
		lt.light_energy = 3.0
		lt.omni_range = 26.0
		lt.shadow_enabled = false
		lt.position = Vector3(0, 1.0, 0)
		_beacon.add_child(lt)
	_beacon.visible = true
	if _lm_site != site:
		_lm_site = site
		var up: Vector3 = lm["up"]
		_beacon.global_transform = Transform3D(_up_basis(up), lm["top"])


static func _up_basis(up: Vector3) -> Basis:
	var x: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, up, x.cross(up).normalized())


## The field bench the rocket carries: stands by the pad of a woken far hub.
func _show_bench(on: bool) -> void:
	if not on:
		if _bench:
			_bench.visible = false
		return
	if _bench == null:
		_bench = _make_bench()
		add_child(_bench)
	var pad: Transform3D = sm.pad_xf(site)
	var at: Vector3 = pad * Vector3(-5.5, 0.0, 4.0)
	var up: Vector3 = at.normalized()
	var g: Vector3 = sm.terrain.ground(up) if sm.terrain else at
	var b: Basis = _up_basis(up)
	if not _bench.visible or _bench.global_position.distance_to(g) > 0.3:
		_bench.global_transform = Transform3D(b, g)
	_bench.visible = true


func _make_bench() -> Node3D:
	var n := Node3D.new()
	n.name = "FieldBench"
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.86, 0.52, 0.22)
	body.roughness = 0.7
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.2, 0.22)
	dark.roughness = 0.6
	var glow := StandardMaterial3D.new()
	glow.albedo_color = TEAL
	glow.emission_enabled = true
	glow.emission = TEAL
	glow.emission_energy_multiplier = 1.6
	for part: Array in [
		[Vector3(1.7, 0.12, 0.9), Vector3(0, 0.92, 0), body],
		[Vector3(1.5, 0.8, 0.7), Vector3(0, 0.46, 0), dark],
		[Vector3(1.7, 0.1, 0.9), Vector3(0, 0.05, 0), body],
		[Vector3(0.9, 0.6, 0.06), Vector3(0, 1.35, -0.36), dark],
		[Vector3(0.78, 0.48, 0.02), Vector3(0, 1.35, -0.32), glow],
		[Vector3(0.3, 0.22, 0.3), Vector3(-0.6, 1.09, 0.1), body],
	]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		mi.mesh = bm
		mi.position = part[1]
		mi.material_override = part[2]
		n.add_child(mi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.7, 1.0, 0.9)
	cs.shape = bs
	cs.position = Vector3(0, 0.5, 0)
	sb.add_child(cs)
	n.add_child(sb)
	return n


# --- UI: the arrival title and the step card ---------------------------------------------------------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	_layer.add_child(root)
	_card = PanelContainer.new()
	_card.name = "HubCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.11, 0.1, 0.78), Color(TEAL, 0.5), 1, 8, 10))
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.offset_top = 64.0
	_card.visible = false
	root.add_child(_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	_card.add_child(vb)
	_card_title = UITheme.label("", 11, Color(TEAL, 0.95))
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_card_title)
	_card_body = UITheme.label("", 15, CREAM)
	_card_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_card_body)
	EventBus.ui_modal_changed.connect(func(open: bool) -> void: _layer.visible = not open)


## The hub's name on screen for a few seconds (an arrival): the name, the town type and its
## landmark, and why Lumi came (HubPlan.reason). Timings and the first-arrival sting are data
## (hub_defaults.hop: title_in_s, title_hold_s, title_out_s, arrive_sting).
func show_title(i: int, first: bool = false) -> void:
	var nm: String = HubPlan.hub_name(planet, i)
	if nm == "" or _layer == null:
		return
	if _title and is_instance_valid(_title):
		_title.queue_free()
	# [v7look] Top centre, in a column narrower than the screen (the lines wrap), while the HUD's
	# top-right cards step aside (HUD.hold_corner): it used to sit 120 px above the middle at full
	# width and ran under the goal card. Below it, the subtitle bar keeps its own place.
	var vb := VBoxContainer.new()
	vb.name = "HubTitle"
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.anchor_top = TITLE_TOP
	vb.anchor_bottom = TITLE_TOP
	vb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vb.grow_vertical = Control.GROW_DIRECTION_END
	vb.add_theme_constant_override("separation", 4)
	var big: Label = UITheme.label(nm.to_upper(), 40, CREAM)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	big.add_theme_constant_override("outline_size", 8)
	big.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.05, 0.85))
	vb.add_child(big)
	var sub_t: String = town_name(i)
	if not HubPlan.is_home(planet, i):
		sub_t = tr("%s  ·  the %s") % [sub_t, HubPlan.landmark_name(planet, i)]
	var sub: Label = UITheme.label(sub_t, 17, TEAL)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_constant_override("outline_size", 5)
	sub.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.05, 0.85))
	vb.add_child(sub)
	title_reason = tr(HubPlan.reason(planet, i)) if HubPlan.reason(planet, i) != "" else ""
	if title_reason != "":
		var why: Label = UITheme.label(title_reason, 15, CREAM)
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.add_theme_constant_override("outline_size", 5)
		why.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.05, 0.85))
		why.modulate.a = 0.92
		vb.add_child(why)
	_layer.get_child(0).add_child(vb)
	_title = vb
	fit_title()
	var hud: Variant = so.w.get("hud") if so and so.w else null
	var up_s: float = float(HubPlan.hop_cfg("title_in_s", 0.5)) + float(HubPlan.hop_cfg("title_hold_s", 3.0)) + float(HubPlan.hop_cfg("title_out_s", 0.9)) * 0.5
	if hud is HUD:  # the HUD steps aside while the name is up (only the cube counter stays), then comes back
		(hud as HUD).hold_corner(up_s, true)
	if Subtitles.current:  # and WREN's bar: the line waits and plays on after
		Subtitles.current.hush(up_s)
	var sting: String = str(HubPlan.hop_cfg("arrive_sting", "motif"))
	if first and sting != "" and not HubPlan.is_home(planet, i):
		Audio.music_sting(sting)
	_title = vb
	vb.modulate.a = 0.0
	var tw := vb.create_tween()
	tw.tween_property(vb, "modulate:a", 1.0, float(HubPlan.hop_cfg("title_in_s", 0.5)))
	tw.tween_interval(float(HubPlan.hop_cfg("title_hold_s", 3.0)))
	tw.tween_property(vb, "modulate:a", 0.0, float(HubPlan.hop_cfg("title_out_s", 0.9)))
	tw.tween_callback(vb.queue_free)
	_card.visible = false
	print("[hubs] arrived at site %d: %s (%s) | %s" % [i, nm, sub_t, title_reason])
	if DevHooks.has("hop-shots"):  # dev: the arrival frame, and one 9 s later (the dev chain's wake)
		for wait: float in [1.6, 9.0]:
			get_tree().create_timer(wait, true, false, true).timeout.connect(func() -> void:
				await RenderingServer.frame_post_draw
				DevHooks.save_viewport("%s_land_%d.png" % [DevHooks.get_s("hop-shots", "screenshots/hop"), int(wait)])
				if wait > 5.0:  # then the rocket's list, and its picture
					sites.open_rocket()
					await DevHooks.wait_wall_for(6.0)  # [v7look] wall clock: the list was still fading in at 1 s
					await RenderingServer.frame_post_draw
					DevHooks.save_viewport("%s_picker.png" % DevHooks.get_s("hop-shots", "screenshots/hop"))
					print("[hubs] dev: shots done"))


## [v7look] Where the arrival title's top edge sits (a share of the screen height), and the widest
## its column gets (canvas px; also never more than TITLE_W_SHARE of the screen).
const TITLE_TOP: float = 0.1
const TITLE_MAX_W: float = 640.0
const TITLE_W_SHARE: float = 0.62


## [v7look] Sizes the arrival title's column to the screen (again whenever the screen changes size).
func fit_title() -> void:
	if _title == null or not is_instance_valid(_title):
		return
	var root: Control = _title.get_parent() as Control
	var vw: float = root.size.x if root and root.size.x > 1.0 else get_viewport().get_visible_rect().size.x
	var w: float = minf(TITLE_MAX_W, vw * TITLE_W_SHARE)
	_title.custom_minimum_size.x = w
	_title.offset_left = -w * 0.5
	_title.offset_right = w * 0.5
	if root and not root.resized.is_connected(fit_title):
		root.resized.connect(fit_title)


## The arrival title while it is up (tools/ui_audit_run.gd), else null.
func title_node() -> Control:
	return _title if _title != null and is_instance_valid(_title) and not _title.is_queued_for_deletion() else null


## Dev (--hub-dev-chain[=T]): T s after each arrival at a far hub, cleans the hexes its chain asks
## for (data only), gives the wake price and uses the landmark: the restore flow without playing.
func _dev_chain(i: int) -> void:
	await get_tree().create_timer(DevHooks.get_f("hub-dev-chain", 3.0)).timeout
	if i != site or HubPlan.woken(i):
		return
	var need: int = 0
	for s: Dictionary in HubPlan.chain(planet, i):
		if str(s["do"]) == "clean":
			need = int(s.get("hexes", 8))
	for c: int in sm.regions[i]:
		if need <= 0:
			break
		if sm.cells.is_dirty(c) and sm.cells.state[c] != 5:
			sm.cells.set_junk(c, 0.0)
			sm.cells.set_state(c, 1)
			need -= 1
	_refresh()
	print("[hubs] dev: %s | prompt '%s'" % [card_text, landmark_prompt()])
	for s: Dictionary in HubPlan.chain(planet, i):
		if str(s["do"]) == "outposts":
			HubPlan.state(i)["outposts"] = int(s.get("count", 1))
	GameState.add_all(HubPlan.wake_cost(planet))
	_refresh()
	var lmd: Dictionary = landmark(i)
	var reach: String = "MISSING"
	if not lmd.is_empty():
		var open_at: Vector3 = TargetReach.beacon_point(so.w, lmd["pos"])
		reach = "found, %.0f m from the pad, open ground %.1f m from its foot (reach %.0f m)" % [(lmd["pos"] as Vector3).distance_to(sm.pad_xf(i).origin), open_at.distance_to(lmd["pos"]), 11.0]
	print("[hubs] dev: %s | prompt '%s' | landmark %s" % [card_text, landmark_prompt(), reach])
	use_landmark()
	_refresh()
	print("[hubs] dev: after use: woken %s, level %d, built %d, card '%s', bench %s, hud %s" % [HubPlan.woken(i), sm.levels[i], sm.built[i], card_text, str(bench_point() != null), str(hud_lines())])


## Dev: one line per hub.
func report() -> void:
	for e: Dictionary in HubPlan.entries(planet):
		var i: int = int(e["site"])
		if i >= sm.sites.size():
			continue
		var real: String = ""
		var p: SitePrefab = sm.prefab(i)
		if p and p.content:
			for c: Node in p.content.get_children():
				if c is VerdanceSite:
					real = " built as " + (c as VerdanceSite).kind
		print("[hubs] %d site %d %s (%s%s, %s): %s, level %d, listed %s, %s" % [int(e.get("order", 0)), i, str(e.get("name", "")), str(e.get("town", "")), real,
			HubPlan.landmark_kind(planet, i), status_text(i), sm.levels[i], HubPlan.listed(planet, i), crew_line(i)])
	print("[hubs] bases %d/%d, card '%s', wake cost %s" % [HubPlan.restored_main(planet), HubPlan.main_total(planet), card_text, str(HubPlan.wake_cost(planet))])
