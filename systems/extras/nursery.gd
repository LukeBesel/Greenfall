class_name Nursery
extends Node3D
## [extras] The robot nursery. Old or low-tier robots can retire (Builder tab "Retire"); they
## become garden caretakers in a small nursery garden at the base: they potter between the flower
## beds, water them, and wave at Lumi. They keep their names, looks (Builder parts) and
## personalities (systems/robot_builder.gd traits). Retiring refunds a few Parts, and every
## caretaker adds a tiny permanent plant-growth bonus (capped), through CradleMode.stat_mod.
## State: GameState.flags.nursery = [{name, type, tier, trait, build, unix, from}] and
## flags.nursery_service = {robot name: time_played when first seen} (how long a robot has served).

const MAX_SHOWN: int = 10
const BONUS_PER: float = 0.01
const BONUS_CAP: float = 0.06
## A robot can retire at Mk I-II, or after this long in service (play time).
const OLD_S: float = 3600.0
const LOW_TIER: int = 1
const SIZE := Vector2(5.0, 3.4)
## Places tried for the garden, nearest first (base yard edge; the hub ground is always clean).
const SPOTS: Array[Vector3] = [Vector3(-1.3, 0, 6.0), Vector3(1.6, 0, 8.6), Vector3(-1.8, 0, 9.4), Vector3(9.0, 0, 4.0), Vector3(-9.2, 0, -3.0), Vector3(3.0, 0, -9.5)]

var world: Node
var center := Vector3.ZERO
var keepers: Array[Caretaker] = []
var _t: float = 0.0
var _beds: Array[Vector3] = []


# --- Rules (static) ---------------------------------------------------------------------

static func list() -> Array:
	var v: Variant = GameState.flags.get("nursery")
	if not (v is Array):
		v = []
		GameState.flags["nursery"] = v
	for r: Variant in v:  # JSON loads ints back as floats
		if r is Dictionary and (r as Dictionary).get("tier") is float:
			r["tier"] = int(r["tier"])
			r["from"] = int(r.get("from", 0))
	return v


static func count() -> int:
	return list().size()


static func garden_bonus(n: int = -1) -> float:
	return minf(float(count() if n < 0 else n) * BONUS_PER, BONUS_CAP)


## Economy.stat hook (via CradleMode.stat_mod): caretakers make plants grow a little faster.
static func stat_mult(stat_id: String) -> float:
	if stat_id != "plant_growth":
		return 1.0
	var v: Variant = GameState.flags.get("nursery")
	return 1.0 + (minf(float((v as Array).size()) * BONUS_PER, BONUS_CAP) if v is Array else 0.0)


static func service() -> Dictionary:
	var v: Variant = GameState.flags.get("nursery_service")
	if not (v is Dictionary):
		v = {}
		GameState.flags["nursery_service"] = v
	return v


static func served_s(rname: String) -> float:
	var t0: float = float(service().get(rname, float(GameState.stats.get("time_played", 0.0))))
	return maxf(0.0, float(GameState.stats.get("time_played", 0.0)) - t0)


static func note_service(fleet: Fleet) -> void:
	if fleet == null:
		return
	var sv: Dictionary = service()
	for r: Robot in fleet.robots():
		if not sv.has(r.robot_name):
			sv[r.robot_name] = float(GameState.stats.get("time_played", 0.0))


## Parts back for retiring (pure): a few, more for higher tiers.
static func refund_for(tier: int) -> int:
	return 2 + 2 * maxi(tier, 0)


## "" if this robot may retire now, else why not.
static func retire_block_reason(r: Robot) -> String:
	if r == null or not is_instance_valid(r):
		return "none"
	if not YardBuilds.built("nursery"):  # [camp] the nursery is a Hub-tab build now
		return TranslationServer.translate("Build the Robot Nursery in the Build tab first.")
	if r.tier <= LOW_TIER or served_s(r.robot_name) >= OLD_S:
		return ""
	var left: int = int(ceil((OLD_S - served_s(r.robot_name)) / 60.0))
	return TranslationServer.translate("Only Mk I-II robots retire early. %s can retire in %d min.") % [r.robot_name, left]


## Retires a robot: it leaves the fleet and moves into the nursery. Returns the caretaker record.
static func retire(fleet: Fleet, r: Robot) -> Dictionary:
	if retire_block_reason(r) != "":
		return {}
	var rec: Dictionary = {"name": r.robot_name, "type": r.type_id, "tier": r.tier, "trait": RobotBuilder.trait_of(r),
		"build": r.build.duplicate(), "unix": Time.get_unix_time_from_system(), "from": GameState.current_hub}
	list().append(rec)
	var parts: int = refund_for(r.tier)
	GameState.add_currency("parts", BigNum.from_float(float(parts)))
	GameState.inc_stat("robots_retired")
	service().erase(r.robot_name)
	if fleet:
		fleet.clear_order(r.robot_name, true)
	# Bales on its forks are set down where it stood.
	var w: Node = r.world
	for c: JunkCube in r.carried:
		if is_instance_valid(c):
			c.set_carried(false)
			if w and w.has_method("add_cube"):
				c.reparent(w.get("_cubes_root") as Node, true)
	r.carried.clear()
	Vfx.burst("sparkle", r.global_position + Vector3(0, 0.6, 0), Color(0.6, 1.0, 0.7), 0.5)
	if r.get_parent():
		r.get_parent().remove_child(r)
	r.queue_free()
	EventBus.toast.emit(TranslationServer.translate("%s retires to the nursery garden. +%d parts, and the flowers get a caretaker.") % [rec["name"], parts], "story")
	var nu: Nursery = of(w)
	if nu:
		nu.rebuild()
	return rec


static func of(slice: Node) -> Nursery:
	return slice.get_node_or_null("Nursery") as Nursery if slice else null


# --- Live node --------------------------------------------------------------------------

func setup(p_world: Node) -> void:
	world = p_world
	name = "Nursery"
	center = _pick_spot()
	position = center
	_build_garden()
	rebuild()
	visible = YardBuilds.built("nursery")  # [camp] nothing until it's built (Hub tab)


## [camp] Shows the garden once it's built (live: it rises out of the ground with sparkles).
func set_built(on: bool, animate: bool) -> void:
	visible = on
	if not on or not animate:
		return
	scale = Vector3(1, 0.02, 1)
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for q: int in 5:
		Vfx.burst("sparkle", global_position + Vector3(randf_range(-2, 2), 0.5, randf_range(-1.5, 1.5)), Color(0.6, 1.0, 0.7), 0.6)
	Audio.play("chime", 1.0, -6.0)


func _pick_spot() -> Vector3:
	var f: HexField = world.get("field") as HexField
	for p: Vector3 in SPOTS:
		if f == null:
			return p
		var ok: bool = true
		for dx: float in [-SIZE.x * 0.5, 0.0, SIZE.x * 0.5]:
			for dz: float in [-SIZE.y * 0.5, 0.0, SIZE.y * 0.5]:
				var q: Vector3 = p + Vector3(dx, 0, dz)
				var h: int = f.hex_at(q)
				if h < 0 or f.is_water(h) or (f.hex_hub[h] == 0 and not f.is_clean(h)):
					ok = false
				elif f.layout != null and f.layout.surface_at(q.x, q.z) == CityLayout.Surface.BUILDING:
					ok = false
		if ok:
			return p
	return SPOTS[0]


func _build_garden() -> void:
	var hx: float = SIZE.x * 0.5
	var hz: float = SIZE.y * 0.5
	# [yard] Soil bed with dense grass, segmented kerbs (gap on the yard side), a charging shelter.
	var hard: MeshInstance3D = YardArt.nursery(SIZE).mi(0.15, "Garden")
	add_child(hard)
	YardArt.set_powered(hard, true)  # only shows once built
	add_child(YardArt.nursery_grass(SIZE))
	# Flower beds the caretakers tend.
	for p: Vector3 in [Vector3(-1.25, 0, -0.85), Vector3(1.25, 0, -0.85), Vector3(-0.4, 0, 0.75)]:
		var bed: Node3D = DecorProps.flower_bed()
		bed.position = p
		add_child(bed)
		_beds.append(p)
	var sign: Label3D = EggProps.label("NURSERY", 46, Color(0.24, 0.42, 0.26), Vector3(hx - 0.45, 1.0, hz - 0.165))
	add_child(sign)


## Rebuilds the caretakers from GameState (after a retire, or on load).
func rebuild() -> void:
	for k: Caretaker in keepers:
		if is_instance_valid(k):
			k.queue_free()
	keepers.clear()
	var recs: Array = list()
	var shown: int = mini(recs.size(), MAX_SHOWN)
	for i: int in shown:
		var rec: Dictionary = recs[recs.size() - 1 - i]  # the newest retirees are out in the garden
		var k := Caretaker.new()
		k.rec = rec
		k.nursery = self
		k.seed_v = float(i) * 1.37
		add_child(k)
		k.position = Vector3(randf_range(-1.8, 1.8), 0, randf_range(-1.0, 1.2))
		keepers.append(k)
		if world.get("interactables") != null:
			var kk: Caretaker = k
			(world.interactables as Interactables).register(k, 1.6,
				func() -> String: return tr("E   Say hi to %s") % str(kk.rec.get("name", "")),
				func() -> void: kk.greet(true))


func bed_points() -> Array[Vector3]:
	return _beds


func patch_pos() -> Vector3:
	var p: Node3D = world.get("patch") as Node3D if world else null
	return p.global_position if p else Vector3(INF, 0, INF)


func _process(delta: float) -> void:
	_t += delta
	if _t < 5.0:
		return
	_t = 0.0
	note_service(world.get("fleet") as Fleet)


## One retired robot pottering about the garden.
class Caretaker extends Node3D:
	var rec: Dictionary
	var nursery: Nursery
	var seed_v: float = 0.0
	var vis: RobotVisual
	var _tag: Label3D
	var _drops: CPUParticles3D
	var _target := Vector3.ZERO
	var _state: String = "walk"
	var _state_t: float = 0.0
	var _hop_t: float = -1.0
	var _wave_cool: float = 0.0
	var _def: Dictionary = {}

	func _ready() -> void:
		_def = RobotBuilder.trait_def(str(rec.get("trait", "")))
		vis = RobotVisual.new()
		add_child(vis)
		var tier: int = int(rec.get("tier", 0))
		var look: String = str(Economy.robot_tiers[tier].get("look", "salvage")) if tier < Economy.robot_tiers.size() else "salvage"
		vis.build(str(rec.get("type", "scoopie")), look)
		RobotKit.fit(vis, rec.get("build", {}), str(Economy.robots.get(str(rec.get("type", "")), {}).get("role", "clean")))
		vis.scale = Vector3.ONE * 0.82
		_tag = Label3D.new()
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag.font_size = 28
		_tag.outline_size = 8
		_tag.pixel_size = 0.0027
		_tag.font = UITheme.font()
		_tag.modulate = Color(0.95, 0.97, 0.9, 0.92)
		_tag.outline_modulate = Color(0.02, 0.03, 0.04, 0.75)
		_tag.position = Vector3(0, 1.2, 0)
		_tag.visibility_range_end = 9.0
		_tag.visibility_range_end_margin = 2.0
		_tag.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tag.text = "%s\n%s" % [str(rec.get("name", "")), tr("CARETAKER · %s") % tr(str(_def.get("name", ""))).to_upper()]
		add_child(_tag)
		_drops = CPUParticles3D.new()
		_drops.emitting = false
		_drops.amount = 24
		_drops.lifetime = 0.7
		_drops.direction = Vector3(0, 0.3, -1)
		_drops.spread = 14.0
		_drops.initial_velocity_min = 1.4
		_drops.initial_velocity_max = 1.9
		_drops.gravity = Vector3(0, -6.0, 0)
		_drops.scale_amount_min = 0.5
		_drops.scale_amount_max = 0.9
		var dm := SphereMesh.new()
		dm.radius = 0.018
		dm.height = 0.036
		dm.radial_segments = 6
		dm.rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.8, 1.0, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.material = mat
		_drops.mesh = dm
		_drops.position = Vector3(0, 0.55, -0.4)
		add_child(_drops)
		_pick_target()

	func _pick_target() -> void:
		var beds: Array[Vector3] = nursery.bed_points()
		if beds.is_empty() or randf() < 0.3:
			_target = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-1.2, 1.3))
			_state = "walk"
		else:
			var b: Vector3 = beds[randi() % beds.size()]
			_target = b + Vector3(randf_range(-0.8, 0.8), 0, 0.75 if randf() < 0.5 else -0.75)
			_state = "to_bed"
		_state_t = 0.0

	func greet(visit: bool = false) -> void:
		_hop_t = 0.0
		_wave_cool = 8.0
		Audio.play(str(_def.get("beep", "beep")), float(_def.get("pitch", 1.0)), -10.0)
		if visit:
			Vfx.burst("sparkle", global_position + Vector3(0, 1.1, 0), Color(1.0, 0.6, 0.75), 0.35)
			GameState.inc_stat("nursery_visits")
			var lines: Array[String] = [
				TranslationServer.translate("%s beeps hello and shows Lumi the marigolds."),
				TranslationServer.translate("%s is busy with the watering can, but waves anyway."),
				TranslationServer.translate("%s hums to the seedlings. Retirement suits it."),
				TranslationServer.translate("%s points proudly at a new bud."),
			]
			EventBus.toast.emit(lines[randi() % lines.size()] % str(rec.get("name", "")), "info")

	func _process(delta: float) -> void:
		if vis == null:
			return
		_state_t += delta
		_wave_cool = maxf(0.0, _wave_cool - delta)
		var lp: Vector3 = nursery.patch_pos()
		var near: bool = global_position.distance_to(lp) < 5.0
		var speed: float = 0.0
		var face: Vector3 = Vector3.ZERO
		if near and _wave_cool <= 0.0:
			greet()
		if _hop_t >= 0.0:
			# Waving at Lumi: turn to face him and hop twice.
			_hop_t += delta
			face = lp - global_position
			vis.position.y = absf(sin(_hop_t * TAU * 1.1)) * 0.09 if _hop_t < 0.9 else 0.0
			vis.rotation.z = sin(_hop_t * 14.0) * 0.08 if _hop_t < 0.9 else 0.0
			if _hop_t > 1.4:
				_hop_t = -1.0
				vis.rotation.z = 0.0
		elif _state == "water":
			face = _bed_dir()
			if _state_t > 3.2:
				_drops.emitting = false
				_pick_target()
		else:
			var to: Vector3 = _target - position
			to.y = 0.0
			if to.length() < 0.15:
				if _state == "to_bed":
					_state = "water"
					_state_t = 0.0
					_drops.emitting = true
				elif _state_t > 2.5:
					_pick_target()
			else:
				speed = 0.55 * float((_def.get("mods", {}) as Dictionary).get("speed", 1.0))
				position += to.normalized() * minf(speed * delta, to.length())
				face = to
		if face.length() > 0.01:
			var want: float = atan2(-face.x, -face.z)  # the visual faces -Z
			rotation.y = lerp_angle(rotation.y, want, clampf(delta * 4.0, 0.0, 1.0))
		vis.idle = speed <= 0.0 and _state != "water"
		vis.animate(speed, _state == "water", delta)

	func _bed_dir() -> Vector3:
		var best := Vector3.ZERO
		var bd: float = INF
		for b: Vector3 in nursery.bed_points():
			var d: float = b.distance_to(position)
			if d < bd:
				bd = d
				best = b - position
		best.y = 0.0
		return best
