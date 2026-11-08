class_name HoverSled
extends Node3D
## [orbD] Lumi's hover-sled for the long ground between hubs on a walkable globe: a buyable
## Upgrades entry ("hover_sled", 3 tiers, globe only) and a parked sled near the start pad.
## Riding it is Lumi's own SphereMotor retuned: a higher top speed (speed_mult), heavier inertia
## (lower accel / decel, slower turns), a softer boost on top (Shift / LS, the Settings "boost"
## action). Interact (E / A) by the parked sled to get on; interact again to get off where you are.
## Tiers keep the big later planets quick (owner, Nov 8): tier 1 cruises ~14 m/s and boosts to
## ~30 m/s (a 1.7 km Verdance hop in about a minute), tier 3 ~20 / ~48 m/s for Anvil's 2.5 km.
## Dev: --orbit-sled[=TIER] (owned and mounted at the start), --orbit-sled-lap (drive a lap).

signal mounted_changed(on: bool)

const UPGRADE_ID: String = "hover_sled"
const STAT: String = "sled_tier"
const TIERS: Array[Dictionary] = [
	{"speed_mult": 3.0, "boost_mult": 2.2, "accel": 6.0, "decel": 4.5, "turn": 3.5},
	{"speed_mult": 3.6, "boost_mult": 2.3, "accel": 7.0, "decel": 5.0, "turn": 3.8},
	{"speed_mult": 4.3, "boost_mult": 2.4, "accel": 8.0, "decel": 5.5, "turn": 4.0},
]
## Lumi floats this much higher on the sled (the deck sits under him).
const RIDE_LIFT: float = 0.55
const REACH: float = 3.0
const PEARL := Color(0.92, 0.91, 0.88)
const ACCENT := Color(1.0, 0.5, 0.16)
const GLOW := Color(0.3, 0.88, 1.0)

var lumi: Patch
var tier: int = 1
var mounted: bool = false
var _saved: Dictionary = {}
var _model: Node3D
var _pods: Array[MeshInstance3D] = []
var _glow_mat: StandardMaterial3D
var _t: float = 0.0


## Adds the hover-sled to the Upgrades list for this session (globe scenes only, so the flat
## game's list is unchanged). Idempotent.
static func register_upgrade() -> void:
	if Economy.upgrade_defs.has(UPGRADE_ID):
		return
	var def: Dictionary = {
		"id": UPGRADE_ID, "name": "Hover Sled", "tab": "patch", "icon": "tread",
		"desc": "A hover-sled for the long roads between hubs. Each level: faster and steadier. E by the sled to ride.",
		"stat": STAT, "mode": "add", "amount": 1.0, "unit": "", "base_cost": 2500, "growth": 6.0, "max_level": 3,
	}
	Economy.upgrade_defs[UPGRADE_ID] = def
	Economy.upgrade_order.append(UPGRADE_ID)
	Economy._index_upgrades()


## Owned tier (0 = not bought).
static func owned_tier() -> int:
	return int(round(Economy.stat(STAT))) if Economy.upgrade_defs.has(UPGRADE_ID) else 0


static func tune(t: int) -> Dictionary:
	return TIERS[clampi(t, 1, TIERS.size()) - 1]


func _ready() -> void:
	_model = _build_model()
	add_child(_model)


func _process(delta: float) -> void:
	_t += delta
	if mounted and lumi:
		var spd: float = lumi.sphere_motor.hv.length() if lumi.sphere_motor else 0.0
		_glow_mat.emission_energy_multiplier = 0.6 + minf(spd / 20.0, 1.0) * 0.9
		_model.position.y = -RIDE_LIFT - 0.12 + sin(_t * 3.0) * 0.015
		_model.rotation.x = clampf(-spd * 0.004, -0.08, 0.0)
	else:
		_glow_mat.emission_energy_multiplier = 0.0 if tier <= 0 else 0.25
		_model.position.y = sin(_t * 1.6) * 0.02


func _unhandled_input(event: InputEvent) -> void:
	if lumi == null or not event.is_action_pressed("interact"):
		return
	if mounted:
		dismount()
		get_viewport().set_input_as_handled()
	elif owned_tier() > 0 and global_position.distance_to(lumi.global_position) < REACH:
		mount()
		get_viewport().set_input_as_handled()


## Prompt for the HUD when Lumi is near the parked sled ("" otherwise).
func prompt() -> String:
	if lumi == null or mounted or global_position.distance_to(lumi.global_position) > REACH:
		return ""
	return tr("Ride the hover-sled") if owned_tier() > 0 else tr("Hover-sled: buy it in Upgrades")


func mount() -> void:
	if mounted or lumi == null or lumi.sphere_motor == null:
		return
	tier = maxi(owned_tier(), 1)
	var m: SphereMotor = lumi.sphere_motor
	_saved = {"speed_mult": m.speed_mult, "boost_mult": m.boost_mult, "accel": m.accel, "decel": m.decel,
		"turn": m.turn_rate, "ride": m.ride_height}
	var k: Dictionary = tune(tier)
	m.speed_mult = float(k["speed_mult"])
	m.boost_mult = float(k["boost_mult"])
	m.accel = float(k["accel"])
	m.decel = float(k["decel"])
	m.turn_rate = float(k["turn"])
	m.ride_height = float(_saved["ride"]) + RIDE_LIFT
	get_parent().remove_child(self)
	lumi.add_child(self)
	transform = Transform3D.IDENTITY
	mounted = true
	Audio.play("whoosh", 1.4, -8.0)
	mounted_changed.emit(true)


func dismount() -> void:
	if not mounted or lumi == null:
		return
	var m: SphereMotor = lumi.sphere_motor
	m.speed_mult = float(_saved.get("speed_mult", 1.0))
	m.boost_mult = float(_saved.get("boost_mult", 4.0))
	m.accel = float(_saved.get("accel", 16.0))
	m.decel = float(_saved.get("decel", 22.0))
	m.turn_rate = float(_saved.get("turn", 9.0))
	m.ride_height = float(_saved.get("ride", 0.0))
	var up: Vector3 = lumi.up()
	var at: Vector3 = lumi.global_position - up * RIDE_LIFT
	var side: Vector3 = lumi.global_basis.x
	var root: Node = lumi.get_parent()
	lumi.remove_child(self)
	root.add_child(self)
	global_transform = Transform3D(lumi.global_basis, at)
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	lumi.global_position += side * 1.6
	mounted = false
	mounted_changed.emit(false)


# --- Model ------------------------------------------------------------------------------------

## A chunky two-tone sled: rounded pearl hull with an orange nose and side skirts, panel seams,
## bolts, a saddle, a handlebar with grips, a headlamp, a rear rack, and two hover pods with thin
## cyan rings underneath (lit only while it runs). Bevelled everywhere; nothing is a raw box.
func _build_model() -> Node3D:
	var root := Node3D.new()
	root.name = "SledModel"
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.38
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.14)
	dark.roughness = 0.6
	dark.metallic = 0.4
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.55, 0.56, 0.58)
	metal.metallic = 0.85
	metal.roughness = 0.35
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = GLOW
	_glow_mat.emission_enabled = true
	_glow_mat.emission = GLOW
	_glow_mat.emission_energy_multiplier = 0.25
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.95, 0.85)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.9, 0.7)
	lamp.emission_energy_multiplier = 0.8
	var parts: Array = []
	# Hull: long rounded deck, raised spine, orange nose and skirts.
	parts.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(1.15, 0.32, 2.3), 0.14, 3), ProcMesh.xf(Vector3(0, 0.36, 0)), PEARL))
	parts.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.7, 0.22, 1.2), 0.1, 3), ProcMesh.xf(Vector3(0, 0.56, 0.25)), PEARL.darkened(0.06)))
	parts.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(1.05, 0.3, 0.6), 0.14, 3), ProcMesh.xf(Vector3(0, 0.42, -1.12), Vector3(-14, 0, 0)), ACCENT))
	for sx: float in [-1.0, 1.0]:
		parts.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.12, 0.2, 1.9), 0.05, 2), ProcMesh.xf(Vector3(sx * 0.6, 0.3, 0.05)), ACCENT))
	# Saddle.
	parts.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.5, 0.12, 0.7), 0.06, 3), ProcMesh.xf(Vector3(0, 0.72, 0.35)), Color(0.22, 0.2, 0.19)))
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = ProcMesh.merge(parts)
	hull.material_override = paint
	root.add_child(hull)
	# Panel seams, bumper, rack, handlebar (dark/metal), bolts.
	var dp: Array = []
	for z: float in [-0.55, 0.15, 0.8]:
		dp.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(1.17, 0.025, 0.03), 0.01, 1), ProcMesh.xf(Vector3(0, 0.52, z))))
	dp.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(1.0, 0.12, 0.14), 0.05, 2), ProcMesh.xf(Vector3(0, 0.26, -1.42))))
	dp.append(ProcMesh.part(ProcMesh.rounded_box(Vector3(0.9, 0.06, 0.5), 0.03, 2), ProcMesh.xf(Vector3(0, 0.58, 1.05))))
	for sx: float in [-0.42, 0.42]:
		dp.append(ProcMesh.part(ProcMesh.cyl(0.025, 0.025, 0.3, 8), ProcMesh.xf(Vector3(sx, 0.7, 1.05))))
	dp.append(ProcMesh.part(ProcMesh.cyl(0.035, 0.035, 0.55, 8), ProcMesh.xf(Vector3(0, 0.82, -0.5), Vector3(-25, 0, 0))))
	dp.append(ProcMesh.part(ProcMesh.cyl(0.03, 0.03, 0.8, 8), ProcMesh.xf(Vector3(0, 1.06, -0.62), Vector3(0, 0, 90))))
	for sx: float in [-0.36, 0.36]:
		dp.append(ProcMesh.part(ProcMesh.cyl(0.045, 0.045, 0.14, 10), ProcMesh.xf(Vector3(sx, 1.06, -0.62), Vector3(0, 0, 90))))
	var dk := MeshInstance3D.new()
	dk.mesh = ProcMesh.merge(dp)
	dk.material_override = dark
	root.add_child(dk)
	var bp: Array = []
	for sx: float in [-0.5, 0.5]:
		for z: float in [-0.8, -0.2, 0.45, 0.95]:
			bp.append(ProcMesh.part(ProcMesh.sphere(0.022, 6, 3), ProcMesh.xf(Vector3(sx, 0.52, z))))
	var bolts := MeshInstance3D.new()
	bolts.mesh = ProcMesh.merge(bp)
	bolts.material_override = metal
	root.add_child(bolts)
	# Headlamp.
	var hl := MeshInstance3D.new()
	hl.mesh = ProcMesh.rounded_box(Vector3(0.34, 0.12, 0.08), 0.04, 2)
	hl.material_override = lamp
	hl.position = Vector3(0, 0.5, -1.4)
	root.add_child(hl)
	# Hover pods: rounded housings with thin glow rings.
	for z: float in [-0.75, 0.75]:
		var pod := MeshInstance3D.new()
		pod.mesh = ProcMesh.rounded_box(Vector3(1.0, 0.18, 0.5), 0.08, 2)
		pod.material_override = dark
		pod.position = Vector3(0, 0.14, z)
		root.add_child(pod)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.2
		tm.outer_radius = 0.24
		tm.rings = 24
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = _glow_mat
		ring.position = Vector3(0, 0.04, z)
		ring.scale = Vector3(1.8, 1, 0.9)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		_pods.append(pod)
	return root
