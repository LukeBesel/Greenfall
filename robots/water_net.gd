class_name WaterNet
extends Node3D
## Refill points for Drip (water) robots:
##   barrel: the base water barrel beside the depot (pumped, never runs dry).
##   tank:   Water Tanks the player places on clean ground (cost cubes). Each holds a reserve
##           that tops itself up slowly (rain catcher + condenser); a gauge shows the level.
##   lake:   any clean lake hex (only once its floating junk is gone).
## Also owns the spray-arc effect waterers use. Tanks are saved in GameState.world["water_tanks"].

const BARREL_OFFSET := Vector3(2.5, 0, 2.5)  # from the depot

var world: Node
## Placed tanks: {pos: Vector3, water: float, node: Node3D, gauge: Node3D}
var tanks: Array[Dictionary] = []
var _barrel: Node3D
var _drop_mesh: SphereMesh
var _drop_mat: StandardMaterial3D
var _t: float = 0.0


func _ready() -> void:
	add_to_group("persist")
	_drop_mesh = ProcMesh.sphere(0.045, 8, 4)
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.albedo_color = Color(0.55, 0.85, 1.0, 0.75)
	_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_mat.emission_enabled = true
	_drop_mat.emission = Color(0.35, 0.7, 1.0)
	_drop_mat.emission_energy_multiplier = 0.6
	_drop_mat.roughness = 0.05
	if world == null:
		return
	_build_barrel()
	for d: Variant in GameState.world.get("water_tanks", []):
		if d is Dictionary:
			var p: Array = (d as Dictionary).get("pos", [0.0, 0.0])
			_add_tank(Vector3(float(p[0]), 0.0, float(p[1])), float((d as Dictionary).get("water", cfg().get("capacity", 80.0))), false)


static func cfg() -> Dictionary:
	return Economy.robot_cfg.get("water_tank", {})


func barrel_pos() -> Vector3:
	return (world.depot.global_position if world and world.get("depot") else Vector3.ZERO) + BARREL_OFFSET


## Every refill point a waterer can use right now: [{kind, pos, index}].
func refill_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null:
		return out
	out.append({"kind": "barrel", "pos": barrel_pos(), "index": -1})
	var op: Variant = world.get("outposts")  # [outposts] water drums at repaired outposts
	if op is Outposts:
		out.append_array((op as Outposts).refill_points())
	for i: int in tanks.size():
		if float(tanks[i]["water"]) >= 1.0:
			out.append({"kind": "tank", "pos": tanks[i]["pos"], "index": i})
	var f: HexField = world.field
	for id: int in f.hex_count():
		if f.is_water(id) and f.is_clean(id):
			out.append({"kind": "lake", "pos": f.hex_center(id), "index": id})
	return out


## Closest usable refill point to `from`. Lake points are moved to the near shore of the lake hex.
func nearest_refill(from: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for p: Dictionary in refill_points():
		var pos: Vector3 = p["pos"]
		if p["kind"] == "lake":
			var d0: Vector3 = Vector3(from.x - pos.x, 0, from.z - pos.z)
			if d0.length() > 0.01:
				pos += d0.normalized() * world.field.hex_size * 0.55
			p["pos"] = pos
		var d: float = Vector2(pos.x - from.x, pos.z - from.z).length()
		if d < best_d:
			best_d = d
			best = p
	return best


## Water handed to a robot from a refill point this tick (tanks hold a limited reserve).
func draw(point: Dictionary, want: float) -> float:
	if point.get("kind", "") != "tank":
		return want
	var i: int = int(point["index"])
	if i < 0 or i >= tanks.size():
		return 0.0
	var got: float = minf(want, float(tanks[i]["water"]))
	tanks[i]["water"] = float(tanks[i]["water"]) - got
	return got


# --- Placing tanks ---------------------------------------------------------------------

func tank_cost() -> BigNum:
	var c: Dictionary = cfg()
	return BigNum.from_float(float(c.get("cost", 150)) * pow(float(c.get("growth", 1.7)), tanks.size()))


## "" if a tank can go at pos, else the reason it can't.
func place_block_reason(pos: Vector3) -> String:
	if world == null:
		return "No world"
	var f: HexField = world.field
	var h: int = f.hex_at(pos)
	if tanks.size() >= int(cfg().get("max", 6)):
		return "Tank limit reached"
	if h < 0 or f.hex_hub[h] == 2:
		return "Can't build here"
	if f.is_water(h):
		return "Not on the lake"
	if not f.is_clean(h):
		return "Clean this hex first"
	var spacing: float = float(cfg().get("min_spacing", 4.0))
	if pos.distance_to(barrel_pos()) < spacing:
		return "Too close to the base barrel"
	for t: Dictionary in tanks:
		if pos.distance_to(t["pos"]) < spacing:
			return "Too close to another tank"
	if not GameState.can_afford("cubes", tank_cost()):
		return "Not enough cubes"
	return ""


func place_tank(pos: Vector3) -> bool:
	pos.y = 0.0
	if place_block_reason(pos) != "":
		return false
	GameState.spend("cubes", tank_cost())
	_add_tank(pos, float(cfg().get("capacity", 80.0)), true)
	EventBus.toast.emit("Water Tank placed. Waterers nearby will refill here.", "info")
	GameState.inc_stat("water_tanks")
	return true


func _add_tank(pos: Vector3, water: float, fx: bool) -> void:
	var n := Node3D.new()
	n.name = "WaterTank%d" % tanks.size()
	add_child(n)
	var y: float = world.field.layout.height_at(pos.x, pos.z) if world.field.layout else 0.0
	n.global_position = Vector3(pos.x, clampf(y, 0.0, 0.3), pos.z)
	n.rotation.y = randf() * TAU
	var gauge: Node3D = _build_tank(n)
	tanks.append({"pos": Vector3(pos.x, 0, pos.z), "water": water, "node": n, "gauge": gauge})
	if fx:
		Vfx.burst("big_sparkle", pos + Vector3(0, 1.0, 0), Color(0.5, 0.85, 1.0))
		Vfx.burst("dust", pos, Color(0.7, 0.65, 0.6, 0.7), 1.5)
		Audio.play("clunk", 0.8, -4.0)
		Audio.play("steam", 1.2, -10.0)
		n.scale = Vector3(1, 0.05, 1)
		n.create_tween().tween_property(n, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	var cap: float = float(cfg().get("capacity", 80.0))
	var regen: float = float(cfg().get("regen", 1.2))
	for t: Dictionary in tanks:
		t["water"] = minf(cap, float(t["water"]) + regen * delta)
		var g: Node3D = t["gauge"]
		if is_instance_valid(g):
			g.scale.y = lerpf(g.scale.y, maxf(0.02, float(t["water"]) / cap), clampf(delta * 4.0, 0.0, 1.0))


# --- Spray arc ----------------------------------------------------------------------------

## A parabolic stream of droplets from a nozzle to a plant, ending in a little splash.
func spray(from: Vector3, to: Vector3, dur: float = 0.55) -> void:
	var arc_h: float = 0.35 + from.distance_to(to) * 0.25
	for i: int in 7:
		var d := MeshInstance3D.new()
		d.mesh = _drop_mesh
		d.material_override = _drop_mat
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.scale = Vector3.ONE * randf_range(0.7, 1.2)
		add_child(d)
		d.global_position = from
		d.visible = false
		var jitter := Vector3(randf_range(-0.08, 0.08), 0, randf_range(-0.08, 0.08))
		var tw := d.create_tween()
		tw.tween_interval(i * dur * 0.07)
		tw.tween_callback(func() -> void: d.visible = true)
		tw.tween_method(func(t: float) -> void:
			var p: Vector3 = from.lerp(to + jitter, t)
			p.y += sin(t * PI) * arc_h
			d.global_position = p
			, 0.0, 1.0, dur)
		tw.tween_callback(d.queue_free)
	get_tree().create_timer(dur * 1.3, false).timeout.connect(func() -> void:
		Vfx.burst("soil", to + Vector3(0, 0.08, 0), Color(0.55, 0.8, 1.0, 0.85), 0.45))


# --- Models -------------------------------------------------------------------------------

func _build_barrel() -> void:
	_barrel = Node3D.new()
	_barrel.name = "WaterBarrel"
	add_child(_barrel)
	_barrel.global_position = barrel_pos()
	var body: Material = Mats.worn_paint(Color(0.22, 0.48, 0.72), 0.85, 0.45, 3.0, 0.5)
	var steel: Material = Mats.metal("steel")
	# A blue steel drum on a pallet, with hoops and a hand pump on the lid.
	_mi(_barrel, ProcMesh.box(Vector3(0.8, 0.1, 0.8)), Mats.worn_paint(Color(0.55, 0.42, 0.28), 0.3, 0.2, 2.0, 0.6), Vector3(0, 0.05, 0))
	_mi(_barrel, ProcMesh.cyl(0.32, 0.32, 0.9, 24), body, Vector3(0, 0.55, 0))
	for y: float in [0.25, 0.55, 0.85]:
		_mi(_barrel, ProcMesh.torus(0.315, 0.34, 28, 4), steel, Vector3(0, y, 0))
	_mi(_barrel, ProcMesh.cyl(0.3, 0.3, 0.02, 24), Mats.metal("dark_steel"), Vector3(0, 1.005, 0))
	_mi(_barrel, ProcMesh.cyl(0.03, 0.03, 0.35, 8), steel, Vector3(0.12, 1.17, 0))
	_mi(_barrel, ProcMesh.box(Vector3(0.3, 0.03, 0.03)), steel, Vector3(0.0, 1.34, 0), Vector3(0, 0, -12))
	_mi(_barrel, ProcMesh.cyl(0.02, 0.02, 0.18, 8), steel, Vector3(0.12, 1.25, -0.09), Vector3(90, 0, 0))
	# Tap, a bucket and a damp patch so it reads as "the water point".
	_mi(_barrel, ProcMesh.cyl(0.02, 0.02, 0.16, 8), Mats.metal("brass"), Vector3(0, 0.3, -0.38), Vector3(90, 0, 0))
	_mi(_barrel, ProcMesh.box(Vector3(0.05, 0.04, 0.03)), Mats.worn_paint(Color(0.85, 0.2, 0.12), 0.8, 0.3), Vector3(0, 0.35, -0.44))
	_mi(_barrel, ProcMesh.cyl(0.13, 0.1, 0.18, 14), Mats.worn_paint(Color(0.7, 0.7, 0.68), 0.4, 0.6), Vector3(0.05, 0.09, -0.6))
	var puddle := _mi(_barrel, ProcMesh.cyl(0.42, 0.42, 0.005, 20), _water_mat(0.55), Vector3(0, 0.012, -0.45), Vector3.ZERO, Vector3(1.0, 1.0, 0.7))
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tag: Label3D = Mats.stencil("H2O", 40, Color(0.92, 0.95, 1.0, 0.9))
	tag.position = Vector3(0, 0.62, -0.33)
	tag.rotation_degrees = Vector3(0, 180, 0)
	_barrel.add_child(tag)
	_collider(_barrel, 0.36, 1.0)


## Water Tank: a riveted cistern on four legs with hoops, a domed lid with a rain funnel,
## a glowing level window, a tap and a coiled hose. Returns the gauge node (scaled by level).
func _build_tank(n: Node3D) -> Node3D:
	var paint: Material = Mats.worn_paint(Color(0.2, 0.55, 0.78), 0.9, 0.35, randf() * 9.0, 0.4)
	var trim: Material = Mats.worn_paint(Color(0.95, 0.78, 0.2), 0.9, 0.3, randf() * 9.0, 0.3)
	var steel: Material = Mats.metal("steel")
	var dark: Material = Mats.metal("dark_steel")
	var r: float = 0.55
	var base_y: float = 0.45
	var h: float = 1.15
	# Legs and cross braces.
	for k: int in 4:
		var a: float = TAU * k / 4.0 + PI * 0.25
		var foot := Vector3(cos(a), 0, sin(a)) * (r * 0.95)
		_mi(n, ProcMesh.cyl(0.035, 0.04, base_y + 0.05, 8), dark, foot + Vector3(0, (base_y + 0.05) * 0.5, 0))
		_mi(n, ProcMesh.cyl(0.07, 0.07, 0.02, 10), dark, foot + Vector3(0, 0.01, 0))
	_mi(n, ProcMesh.torus(r * 0.9, r * 0.97, 24, 4), dark, Vector3(0, base_y * 0.45, 0))
	# Cistern body, bottom plate, hoops and rivets.
	_mi(n, ProcMesh.cyl(r + 0.02, r + 0.02, 0.06, 28), dark, Vector3(0, base_y, 0))
	_mi(n, ProcMesh.cyl(r, r, h, 28), paint, Vector3(0, base_y + h * 0.5, 0))
	for y: float in [0.12, h * 0.5, h - 0.12]:
		_mi(n, ProcMesh.torus(r - 0.005, r + 0.03, 32, 5), trim if is_equal_approx(y, h * 0.5) else steel, Vector3(0, base_y + y, 0))
	for k: int in 12:
		var a2: float = TAU * k / 12.0
		_mi(n, ProcMesh.sphere(0.012, 6, 3), steel, Vector3(cos(a2), 0, sin(a2)) * (r + 0.005) + Vector3(0, base_y + h - 0.2, 0))
	# Domed lid with a rain funnel on top.
	_mi(n, ProcMesh.hemisphere(r + 0.01, 28, 8), paint, Vector3(0, base_y + h, 0), Vector3.ZERO, Vector3(1.0, 0.35, 1.0))
	_mi(n, ProcMesh.cyl(0.05, 0.05, 0.14, 10), steel, Vector3(0, base_y + h + 0.24, 0))
	_mi(n, ProcMesh.cyl(0.26, 0.06, 0.16, 20), trim, Vector3(0, base_y + h + 0.36, 0))
	var rain := _mi(n, ProcMesh.cyl(0.235, 0.235, 0.005, 20), _water_mat(0.7), Vector3(0, base_y + h + 0.41, 0))
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Level window: dark slot with a glowing water column that rises and falls.
	var front := Vector3(0, 0, -(r + 0.012))
	_mi(n, ProcMesh.box(Vector3(0.14, h * 0.8, 0.02)), dark, front + Vector3(0, base_y + h * 0.5, 0))
	var gauge := Node3D.new()
	gauge.position = front + Vector3(0, base_y + h * 0.1, -0.006)
	n.add_child(gauge)
	_mi(gauge, ProcMesh.box(Vector3(0.09, h * 0.78, 0.02)), Mats.lamp(Color(0.35, 0.75, 1.0), 2.2), Vector3(0, h * 0.39, 0))
	for k: int in 4:
		_mi(n, ProcMesh.box(Vector3(0.18, 0.012, 0.022)), steel, front + Vector3(0, base_y + h * (0.1 + 0.195 * (k + 1)), -0.004))
	var tag: Label3D = Mats.stencil("WATER", 44, Color(0.95, 0.95, 0.9, 0.92))
	tag.rotation_degrees = Vector3(0, 90, 0)
	tag.position = Vector3(r + 0.015, base_y + h * 0.7, 0)
	n.add_child(tag)
	# Tap with a red wheel valve and a hose coiled on a hook.
	_mi(n, ProcMesh.cyl(0.03, 0.03, 0.2, 10), steel, Vector3(r * 0.7, base_y + 0.12, -r * 0.7 - 0.05), Vector3(90, -45, 0))
	_mi(n, ProcMesh.torus(0.04, 0.055, 14, 4), Mats.worn_paint(Color(0.85, 0.15, 0.1), 0.85, 0.3), Vector3(r * 0.75, base_y + 0.2, -r * 0.75 - 0.05))
	var hose: Material = Mats.rubber(Color(0.15, 0.55, 0.25))
	for k: int in 3:
		_mi(n, ProcMesh.torus(0.13 + k * 0.012, 0.155 + k * 0.012, 20, 5), hose, Vector3(-r - 0.04, base_y + 0.5, 0), Vector3(0, 0, 90))
	_mi(n, ProcMesh.box(Vector3(0.06, 0.06, 0.06)), dark, Vector3(-r - 0.02, base_y + 0.66, 0))
	# Base puddle and the collider (robots stop just short of it).
	var puddle := _mi(n, ProcMesh.cyl(0.8, 0.8, 0.005, 24), _water_mat(0.35), Vector3(0, 0.012, 0))
	puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collider(n, r * 0.95, base_y + h)
	return gauge


func _water_mat(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.5, 0.65, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.02
	m.metallic = 0.3
	return m


func _collider(parent: Node3D, radius: float, height: float) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	cs.position = Vector3(0, height * 0.5, 0)
	sb.add_child(cs)
	parent.add_child(sb)


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	parent.add_child(m)
	return m


func persist_save() -> void:
	var arr: Array = []
	for t: Dictionary in tanks:
		var p: Vector3 = t["pos"]
		arr.append({"pos": [p.x, p.z], "water": float(t["water"])})
	GameState.world["water_tanks"] = arr
