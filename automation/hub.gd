class_name Hub
extends Node3D
## The base at the center of a district. Level 1 is the lean-to (built by the slice scene);
## higher levels add structures, each arriving with a fast-build sequence. Also hosts air scrubbers.

## Emitted after an upgrade raises the level (the yard dressing plays its fix-up flourish).
signal level_changed(new_level: int)
signal leveled(level: int)

var data: Dictionary
var level: int = 1
var scrubbers: int = 0
var _parts: Array[Node3D] = []
var _fans: Array[Node3D] = []
var _demo_t: float = 0.0  # [steam]
## [orbB] false on the globe: the hub site's prefab shows each level (orbD's SitePrefab.set_stage),
## so the flat yard's lean-to/office/solar/turbine pieces aren't built.
var visuals: bool = true


func _ready() -> void:
	data = Economy.read_json("res://data/hub.json")
	level = int(GameState.world.get("hub_level", 1))
	if DevHooks.has("hub-level"):  # screenshots: --hub-level=5 builds the base up to that level
		level = maxi(level, int(DevHooks.get_f("hub-level", 1.0)))
		GameState.world["hub_level"] = level
	scrubbers = int(GameState.world.get("hub_scrubbers", 0))
	for l: int in range(2, level + 1):
		_build_level(l, false)
	for i: int in scrubbers:
		_build_scrubber(i, false)


## [biomes] Frontier bases cost more cubes per level (data/frontiers.json cost_mult; set before _ready).
var cost_mult: float = 1.0


func level_def(l: int) -> Dictionary:
	for d: Dictionary in data.get("levels", []):
		if int(d["level"]) == l:
			if is_equal_approx(cost_mult, 1.0) or not (d.get("cost", {}) as Dictionary).has("cubes"):
				return d
			var dd: Dictionary = d.duplicate(true)  # [biomes]
			dd["cost"]["cubes"] = float(dd["cost"]["cubes"]) * cost_mult
			return dd
	return {}


func sell_mult() -> float:
	return float(level_def(level).get("bonus", {}).get("sell_mult", 0.0))


## [v6pace] The base level that brings the rocket (data/hub.json "rocket_level"). It was level 5
## in code: on the globe that put the first hop to another hub past the planet's whole arc.
static var _cfg: Dictionary = {}
static var _rocket_step: int = -2
static func _hub_cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json("res://data/hub.json")
	return _cfg


static func rocket_level() -> int:
	return int((_hub_cfg().get("rocket", {}) as Dictionary).get("level", 5))


## Whether a base at `level` has its rocket: the level, and the story objective named in the data
## done (flags.objective_step past it; a save from before the objectives counts as past it).
static func rocket_open(level: int) -> bool:
	if level < rocket_level():
		return false
	var after: String = str((_hub_cfg().get("rocket", {}) as Dictionary).get("after_objective", ""))
	if after == "":
		return true
	if _rocket_step == -2:
		_rocket_step = -1
		var ch: Array = Economy.read_json("res://data/objectives.json").get("objectives", [])
		for i: int in ch.size():
			if str((ch[i] as Dictionary).get("id", "")) == after:
				_rocket_step = i
	return _rocket_step < 0 or int(GameState.flags.get("objective_step", 0)) > _rocket_step


## Why there is no rocket yet (translated), "" when rocket_open(level).
static func rocket_lock_text(level: int) -> String:
	if rocket_open(level):
		return ""
	if level < rocket_level():
		return TranslationServer.translate("Locked. Upgrade your base to level %d to build the launch pad.") % rocket_level()
	return TranslationServer.translate("The launch pad is still buried. Put your first robot to work to clear it.")


## The level a restored far hub stands at, and what restoring one costs when `n` far hubs are
## already restored ({"cubes", "parts"}).
static func far_cfg() -> Dictionary:
	var c: Dictionary = (_hub_cfg().get("far_hub", {}) as Dictionary).duplicate()
	var po: Variant = Homeward.planet_def(Homeward.current_planet()).get("far_hub", {})
	if po is Dictionary:
		c.merge(po as Dictionary, true)
	return c


static func far_level() -> int:
	return int(far_cfg().get("level", 2))


## Owner note 63: prices multiply. base x growth^n, kept to two leading digits (1.5K, 6K, 24K...).
static func far_cost(n: int) -> Dictionary:
	var c: Dictionary = far_cfg()
	var ov: Variant = (c.get("cost_override", {}) as Dictionary).get(str(n))
	if ov is Dictionary:
		return (ov as Dictionary).duplicate()
	var out: Dictionary = {}
	var base: Dictionary = c.get("cost_base", {})
	var gr: Dictionary = c.get("cost_growth", {})
	for k: String in base:
		out[k] = nice(float(base[k]) * pow(float(gr.get(k, 1.0)), float(maxi(n, 0))))
	return out


## v rounded to two leading digits (4056 -> 4100).
static func nice(v: float) -> float:
	if v < 100.0:
		return roundf(v)
	var mag: float = pow(10.0, floorf(log(v) / log(10.0) + 0.000001) - 1.0)
	return roundf(v / mag) * mag


## Far hubs restored on the round planet Lumi is on (SiteManager.built past the start hub).
static var _far_n: int = 0
static var _far_frame: int = -1
static func far_restored() -> int:
	var f: int = Engine.get_process_frames()
	if f == _far_frame:
		return _far_n
	_far_frame = f
	_far_n = 0
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var os_: OrbitSites = OrbitSites.of(tree.current_scene) if tree and tree.current_scene else null
	if os_ != null and os_.sm != null:
		for i: int in range(1, os_.sm.built.size()):
			_far_n += 1 if os_.sm.built[i] != 0 else 0
	return _far_n


## What every sale is multiplied by: sell_growth for each restored far hub (its trade route).
static func trade_mult() -> float:
	# [v6pace] far_hub.pace: the one knob for the whole planet's speed. Every sale (bin, scale, crew
	# bales) pays 1/pace, so every cube price takes about pace times as long to save for.
	var pace: float = maxf(0.05, float(far_cfg().get("pace", 1.0)))
	return pow(float(far_cfg().get("sell_growth", 1.0)), float(far_restored())) / pace


static func can_pay(cost: Dictionary, mult: float = 1.0) -> bool:
	return GameState.can_afford_all(cost, mult)  # [money] legacy keys folded into the three


static func pay(cost: Dictionary, mult: float = 1.0) -> bool:
	return GameState.spend_all(cost, mult)  # [money]


func upgrade() -> bool:
	if not Demo.can_raise_base(level):  # [steam] demo cap
		Demo.block("base")
		return false
	var next: Dictionary = level_def(level + 1)
	if next.is_empty() or not pay(next.get("cost", {})):
		return false
	level += 1
	GameState.world["hub_level"] = level
	_build_level(level, true)
	level_changed.emit(level)
	EventBus.toast.emit(tr("Hub upgraded: %s.") % tr(str(next["name"])), "story")
	leveled.emit(level)
	return true


## [steam] Demo: at the cap and able to pay for the next level (the player has "finished" the demo).
func demo_finished() -> bool:
	var next: Dictionary = level_def(level + 1)
	return Demo.is_demo() and level >= Demo.MAX_BASE_LEVEL and not next.is_empty() and can_pay(next.get("cost", {}))


func scrubber_def() -> Dictionary:
	for b: Dictionary in data.get("buildings", []):
		if b["id"] == "air_scrubber":
			return b
	return {}


func scrubber_cost_mult() -> float:
	return pow(float(scrubber_def().get("growth", 1.8)), scrubbers)


func build_scrubber() -> bool:
	var d: Dictionary = scrubber_def()
	if level < int(d.get("requires_level", 2)) or scrubbers >= int(d.get("max", 6)):
		return false
	if not pay(d.get("cost", {}), scrubber_cost_mult()):
		return false
	_build_scrubber(scrubbers, true)
	scrubbers += 1
	GameState.world["hub_scrubbers"] = scrubbers
	EventBus.toast.emit(tr("Air Scrubber online. The fans spin up with a long, dusty sigh."), "story")
	return true


func _process(delta: float) -> void:
	if Demo.is_demo():  # [steam] end of demo once the next base level is earned
		_demo_t += delta
		if _demo_t > 1.0:
			_demo_t = 0.0
			if demo_finished() and not GameState.flags.get("demo_end_seen", false):
				Demo.show_end_screen("auto")
	for f: Node3D in _fans:
		f.rotate_object_local(Vector3.FORWARD, delta * 9.0)
	if scrubbers > 0:
		GameState.inc_stat("air_filtered", float(scrubber_def().get("filter_per_s", 1.0)) * scrubbers * delta)


# --- Construction ---------------------------------------------------------------------

## Adds a piece with a fast-build drop-in: it starts high and spins in, lands with sparks.
func _piece(mesh: Mesh, mat: Material, xf: Transform3D, animate: bool, delay: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.transform = xf
	if animate:
		var final: Transform3D = xf
		mi.position = final.origin + Vector3(randf_range(-2, 2), 9.0, randf_range(-2, 2))
		mi.rotation = Vector3(randf_range(-1, 1), randf_range(-2, 2), randf_range(-1, 1))
		mi.visible = false
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void: mi.visible = true)
		tw.tween_property(mi, "transform", final, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			Vfx.burst("sparkle", to_global(final.origin) + Vector3(0, 0.3, 0), Color(1.0, 0.8, 0.4), 0.5)
			Audio.play("clunk", randf_range(0.9, 1.2), -10.0))
	_parts.append(mi)
	return mi


func _scaffold(center: Vector3, size: Vector3, duration: float) -> void:
	# Quick scaffolding cage that appears, then folds away when the build completes.
	var cage := Node3D.new()
	add_child(cage)
	cage.position = center
	var mat: StandardMaterial3D = Mats.metal("steel")
	for x: float in [-size.x * 0.5, size.x * 0.5]:
		for z: float in [-size.z * 0.5, size.z * 0.5]:
			var p := MeshInstance3D.new()
			p.mesh = ProcMesh.cyl(0.03, 0.03, size.y, 6)
			p.material_override = mat
			p.position = Vector3(x, size.y * 0.5, z)
			cage.add_child(p)
	for y: float in [size.y * 0.33, size.y * 0.66, size.y]:
		var r := MeshInstance3D.new()
		r.mesh = ProcMesh.box(Vector3(size.x, 0.04, 0.04))
		r.material_override = mat
		r.position = Vector3(0, y, -size.z * 0.5)
		cage.add_child(r)
	cage.scale = Vector3(1, 0.01, 1)
	var tw := create_tween()
	tw.tween_property(cage, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(duration)
	tw.tween_property(cage, "scale", Vector3(1, 0.01, 1), 0.3)
	tw.tween_callback(cage.queue_free)


## [vqa2] First panel of the level-4 solar row (yard front-right, out of the spawn camera's view).
const SOLAR_ROW := Vector3(3.2, 0.0, 7.5)


func _build_level(l: int, animate: bool) -> void:
	if not visuals:  # [orbB]
		return
	var iron: StandardMaterial3D = AssetLib.pbr_material("corrugated_iron", 0.6, Color(0.92, 0.9, 0.86), true)
	var paint: ShaderMaterial = Mats.worn_paint(Color(0.35, 0.55, 0.62), 0.8, 0.4, 20.0 + l, 0.4)
	var white: ShaderMaterial = Mats.worn_paint(Color(0.9, 0.9, 0.86), 0.9, 0.2, 30.0 + l, 0.2)
	var d: float = 0.0
	var pb: StaticBody3D = PropColliders.body(self, "Props%d" % l)  # [world2] solid walls, office, masts
	match l:
		2:
			# Enclose the lean-to: walls, a roll-up door, floodlights. (Shack sits at x=-4.9, z=2.2.)
			if animate:
				_scaffold(Vector3(-4.9, 0, 2.2), Vector3(4.0, 2.8, 3.2), 2.2)
			for spec: Array in [[Vector3(-4.9, 1.2, 0.6), Vector3(3.6, 2.4, 0.06)], [Vector3(-4.9, 1.2, 3.8), Vector3(3.6, 2.4, 0.06)], [Vector3(-6.7, 1.2, 2.2), Vector3(0.06, 2.4, 3.2)]]:
				_piece(ProcMesh.box(spec[1]), iron, Transform3D(Basis(), spec[0]), animate, d)
				PropColliders.add_box(pb, Transform3D(Basis(), to_global(spec[0])), (spec[1] as Vector3).max(Vector3(0.16, 0, 0.16)))  # [world2]
				d += 0.25
			_piece(ProcMesh.box(Vector3(4.0, 0.08, 3.6)), paint, Transform3D(Basis(), Vector3(-4.9, 2.5, 2.2)), animate, d)
			for z: float in [0.9, 3.5]:
				var lamp := _piece(ProcMesh.box(Vector3(0.3, 0.18, 0.12)), Mats.lamp(Color(1.0, 0.9, 0.7), 3.0), Transform3D(Basis(), Vector3(-3.0, 2.4, z)), animate, d + 0.3)
				var sl := SpotLight3D.new()
				sl.light_energy = 3.0
				sl.spot_range = 10.0
				sl.spot_angle = 60.0
				sl.rotation_degrees = Vector3(-60, 90, 0)
				lamp.add_child(sl)
		3:
			if animate:
				_scaffold(Vector3(5.5, 0, 4.5), Vector3(4.2, 3.2, 3.2), 2.4)
			_piece(ProcMesh.rounded_box(Vector3(4.0, 2.8, 3.0), 0.08, 2), white, Transform3D(Basis(), Vector3(5.5, 1.4, 4.5)), animate, 0.0)
			_piece(ProcMesh.box(Vector3(4.2, 0.12, 3.2)), paint, Transform3D(Basis(), Vector3(5.5, 2.86, 4.5)), animate, 0.3)
			_piece(ProcMesh.box(Vector3(0.9, 1.8, 0.05)), Mats.glass(Color(0.2, 0.3, 0.35, 0.7)), Transform3D(Basis(), Vector3(5.0, 1.0, 2.97)), animate, 0.5)
			_piece(ProcMesh.cyl(0.04, 0.06, 7.0, 6), Mats.metal("steel"), Transform3D(Basis(), Vector3(7.0, 3.5, 5.5)), animate, 0.8)
			PropColliders.add_box(pb, Transform3D(Basis(), to_global(Vector3(5.5, 1.4, 4.5))), Vector3(4.0, 2.8, 3.1))  # [world2] the office
			PropColliders.add_cyl(pb, to_global(Vector3(7.0, 0.0, 5.5)), 0.08, 7.0)
			_piece(ProcMesh.sphere(0.12, 8, 4), Mats.lamp(Color(1.0, 0.2, 0.15), 3.0), Transform3D(Basis(), Vector3(7.0, 7.05, 5.5)), animate, 1.0)
		4:
			# [vqa2] Solar row in the front-right of the yard, in front of the level-3 office. It used to
			# span the yard's front edge (x -3.5..3.5, z 7) right under the spawn camera, which saw
			# a dark glass slab across the bottom of the screen.
			if animate:
				_scaffold(Vector3(4.5, 0, 7.5), Vector3(4.6, 1.6, 2.4), 2.0)
			var panel: StandardMaterial3D = Mats.glass(Color(0.08, 0.12, 0.25, 1.0), 0.15)
			for i: int in 3:
				_piece(ProcMesh.box(Vector3(1.3, 0.04, 2.0)), panel, Transform3D(Basis(Vector3.RIGHT, -0.5), SOLAR_ROW + Vector3(i * 1.4, 1.1, 0)), animate, i * 0.15)
				_piece(ProcMesh.cyl(0.03, 0.03, 1.1, 6), Mats.metal("steel"), Transform3D(Basis(), SOLAR_ROW + Vector3(i * 1.4, 0.55, 0)), animate, i * 0.15)
			var body := StaticBody3D.new()  # Lumi, robots and the camera arm stop at the row
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(4.1, 1.6, 1.9)
			cs.shape = bs
			cs.position = SOLAR_ROW + Vector3(1.4, 0.8, 0)
			body.add_child(cs)
			add_child(body)
		5:
			if animate:
				_scaffold(Vector3(-7.0, 0, -5.0), Vector3(2.0, 9.0, 2.0), 2.6)
			_piece(ProcMesh.cyl(0.15, 0.3, 9.0, 10), white, Transform3D(Basis(), Vector3(-7.0, 4.5, -5.0)), animate, 0.0)
			PropColliders.add_cyl(pb, to_global(Vector3(-7.0, 0.0, -5.0)), 0.3, 9.0)  # [world2] the turbine mast
			_piece(ProcMesh.capsule(0.25, 0.9), white, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-7.0, 9.0, -4.7)), animate, 0.4)
			var rotor := Node3D.new()
			rotor.position = Vector3(-7.0, 9.0, -4.25)
			add_child(rotor)
			for k: int in 3:
				var blade := MeshInstance3D.new()
				blade.mesh = ProcMesh.box(Vector3(0.25, 3.2, 0.05))
				blade.material_override = white
				blade.rotation.z = TAU * k / 3.0
				blade.position = Vector3(0, 0, 0)
				var arm := Node3D.new()
				arm.rotation.z = TAU * k / 3.0
				rotor.add_child(arm)
				blade.position = Vector3(0, 1.6, 0)
				blade.rotation = Vector3.ZERO
				arm.add_child(blade)
			_fans.append(rotor)
	if animate:
		var tw := create_tween()
		tw.tween_interval(2.6)
		tw.tween_callback(func() -> void:
			Audio.play("fanfare", 1.0, -4.0)
			Vfx.burst("confetti", global_position + Vector3(0, 3.0, 0), Color.WHITE)
			EventBus.shake_requested.emit(0.12))


func _build_scrubber(i: int, animate: bool) -> void:
	if not visuals:  # [orbB]
		return
	var pos := Vector3(6.5 - i * 1.6, 0, -6.5)
	# [yard] A kit scrubber unit (systems/camp/yard_art.gd YardArt.scrubber); the fan spins in its shroud.
	var unit: MeshInstance3D = _piece(ArrayMesh.new(), null, Transform3D(Basis(Vector3.UP, i * 0.4), pos), animate, 0.0)
	YardArt.scrubber().into(unit, 0.15)
	YardArt.set_powered(unit, true)
	var fan := Node3D.new()
	fan.position = pos + Vector3(0, 1.95, 0)
	add_child(fan)
	for k: int in 4:
		var b := MeshInstance3D.new()
		b.mesh = ProcMesh.box(Vector3(0.9, 0.02, 0.16))
		b.material_override = Mats.metal("steel")
		b.rotation = Vector3(0.25, TAU * k / 4.0, 0)
		fan.add_child(b)
	fan.rotation.x = -PI * 0.5
	YardArt.kitify(fan)  # [yard]
	_fans.append(fan)
	if animate:
		Vfx.burst("dust", pos + Vector3(0, 2.2, 0), Color(0.7, 0.65, 0.6, 0.6), 1.5)
