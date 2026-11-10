class_name HoverSled
extends Node3D
## [orbD] Lumi's hover-sled for the long ground between hubs on a walkable globe: a buyable
## Upgrades entry ("hover_sled", 3 tiers, globe only) and a parked sled near the start pad.
## Riding it is Lumi's own SphereMotor retuned: a higher top speed (speed_mult), heavier inertia
## (lower accel / decel, slower turns), a softer boost on top (Shift / LS, the Settings "boost"
## action). Interact (E / A) by the parked sled to get on; interact again to get off where you are.
## Tiers keep the big later planets quick (owner, Nov 8): tier 1 cruises ~14 m/s and boosts to
## ~30 m/s (a 1.7 km hop in about a minute), tier 3 ~20 / ~48 m/s for the largest globe's 2.5 km.
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
var _mesh: MeshInstance3D
var _exhaust: Array[MeshInstance3D] = []
var _lamp: SpotLight3D
var _glow_mat: StandardMaterial3D
var _t: float = 0.0
var _lit: bool = false
var _bank: float = 0.0
var _pitch: float = 0.0
var _prev_fwd := Vector3.ZERO
var _prev_spd: float = 0.0
var _own_t: float = 0.0


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
	visible = owned_tier() > 0  # [v1yard]


func _process(delta: float) -> void:
	_t += delta
	_own_t -= delta
	if _own_t <= 0.0:  # [v1yard] no vehicle at the start: the parked sled shows once it is bought
		_own_t = 0.5
		visible = mounted or owned_tier() > 0
	if not visible:
		return
	_set_lit(mounted)
	if mounted and lumi and lumi.sphere_motor:
		_ride(delta)
	else:
		_model.position = Vector3(0, sin(_t * 1.6) * 0.02, 0)
		_model.rotation = Vector3.ZERO
		_glow_mat.albedo_color.a = 0.0


## Ride animation: the sled floats under Lumi with a hover bob, banks into turns, noses up as it
## speeds up and dips as it brakes; the exhaust glow stretches with speed and flares on boost.
func _ride(delta: float) -> void:
	var m: SphereMotor = lumi.sphere_motor
	var spd: float = m.hv.length()
	var fwd: Vector3 = m.fwd
	var turn: float = 0.0
	if _prev_fwd != Vector3.ZERO and delta > 0.0:
		turn = _prev_fwd.signed_angle_to(fwd, lumi.up()) / delta  # rad/s, + = left
	_prev_fwd = fwd
	var acc: float = (spd - _prev_spd) / maxf(delta, 0.001)
	_prev_spd = spd
	var k: float = 1.0 - exp(-6.0 * delta)
	_bank = lerpf(_bank, clampf(turn * spd * 0.012, -0.32, 0.32), k)
	_pitch = lerpf(_pitch, clampf(-acc * 0.012, -0.12, 0.08), k)
	_model.position = Vector3(0, -RIDE_LIFT - 0.12 + sin(_t * 3.2) * 0.02 * (1.0 - minf(spd / 25.0, 0.7)), 0)
	_model.rotation = Vector3(_pitch, 0, _bank)
	var boost: float = m.boost_t
	var heat: float = clampf(0.25 + spd / 30.0 + boost * 0.6, 0.0, 1.3)
	_glow_mat.albedo_color.a = clampf(heat * 0.55, 0.0, 0.8)
	for c: MeshInstance3D in _exhaust:
		c.scale = Vector3(1.0 + boost * 0.4, 0.6 + heat * 1.4 + sin(_t * 31.0) * 0.06, 1.0 + boost * 0.4)


## Trims, headlamp and tail lights are lit only while it runs (kit rule: nothing glows when off).
func _set_lit(on: bool) -> void:
	if on == _lit or _mesh == null:
		return
	_lit = on
	KitMat.apply(_mesh, "restored", on)
	_lamp.light_energy = 1.6 if on else 0.0


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
	if lumi == null or mounted or owned_tier() <= 0 or global_position.distance_to(lumi.global_position) > REACH:
		return ""  # [v1yard] not there until it is bought
	return tr("Ride the hover-sled")


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
	_prev_fwd = Vector3.ZERO
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

## The sled from the shared art kit (art/kit, docs/ART_KIT.md): a bevelled two-tone hull (cream
## with an orange nose and teal skirts), panel seams and bolts, hazard-striped bumper, a padded
## saddle, a handlebar with rubber grips and a small dash, side number decals and nose chevrons,
## a rear rack with a crate, two hover pods with thin cool trim rings, a warm headlamp and red
## tail lights (lit only while it runs), and twin exhaust nozzles with a soft additive glow.
func _build_model() -> Node3D:
	var root := Node3D.new()
	root.name = "SledModel"
	var b := KitMesh.Builder.new(4242, {"main": "cream", "accent": "orange", "trim": "teal"}, "restored")
	# Hull: deck, raised spine, nose wedge, skirts.
	b.box("paint:main", Vector3(1.15, 0.3, 2.2), KitMesh.xf(Vector3(0, 0.38, 0.05)))
	b.box("paint:main", Vector3(0.66, 0.2, 1.15), KitMesh.xf(Vector3(0, 0.6, 0.3)))
	b.box("paint:accent", Vector3(1.05, 0.28, 0.62), KitMesh.xf(Vector3(0, 0.43, -1.1), Vector3(-14, 0, 0)))
	for sx: float in [-1.0, 1.0]:
		b.box("paint:teal", Vector3(0.1, 0.2, 1.8), KitMesh.xf(Vector3(sx * 0.6, 0.3, 0.1)))
		# Panel seams and bolts along each side.
		for z: float in [-0.5, 0.15, 0.8]:
			b.box("dark_steel", Vector3(0.02, 0.22, 0.025), KitMesh.xf(Vector3(sx * 0.585, 0.4, z)), 0.005)
		for z: float in [-0.8, -0.2, 0.45, 0.95]:
			b.add("steel", KitMesh.bolt(0.022, 0.02), KitMesh.xf(Vector3(sx * 0.58, 0.47, z), Vector3(0, 0, sx * -90.0)))
		# Side number and a power label, as decals.
		b.decal("num_01" if sx < 0.0 else "num_02", Vector2(0.26, 0.26), KitMesh.xf(Vector3(sx * 0.585, 0.42, -0.3), Vector3(0, sx * 90.0, 0)))
	b.decal("chevrons", Vector2(0.5, 0.16), KitMesh.xf(Vector3(0, 0.58, -1.1), Vector3(-104, 0, 0)))
	# Bumper with hazard stripes, rear rack with a crate.
	b.box("hazard", Vector3(1.0, 0.13, 0.14), KitMesh.xf(Vector3(0, 0.26, -1.43)))
	b.box("dark_steel", Vector3(0.9, 0.05, 0.5), KitMesh.xf(Vector3(0, 0.56, 1.05)))
	for sx: float in [-0.42, 0.42]:
		b.rod("dark_steel", Vector3(sx, 0.56, 1.3), Vector3(sx, 0.78, 1.3), 0.022)
	b.rod("dark_steel", Vector3(-0.42, 0.78, 1.3), Vector3(0.42, 0.78, 1.3), 0.022)
	KitProps.crate(b, KitMesh.xf(Vector3(0.1, 0.585, 1.02), Vector3(0, 8, 0)), Vector3(0.42, 0.3, 0.36), "paint:crate")
	# Saddle, handlebar, grips, dash.
	b.box("rubber", Vector3(0.48, 0.11, 0.66), KitMesh.xf(Vector3(0, 0.75, 0.35)))
	b.rod("dark_steel", Vector3(0, 0.6, -0.42), Vector3(0, 1.02, -0.62), 0.035)
	b.rod("dark_steel", Vector3(-0.4, 1.04, -0.62), Vector3(0.4, 1.04, -0.62), 0.03)
	for sx: float in [-0.36, 0.36]:
		b.cyl("rubber", 0.045, 0.14, KitMesh.xf(Vector3(sx - 0.07 * signf(sx), 1.04, -0.62), Vector3(0, 0, 90)))
	b.box("dark_steel", Vector3(0.26, 0.1, 0.14), KitMesh.xf(Vector3(0, 0.98, -0.58), Vector3(-30, 0, 0)))
	b.box("trim:cool", Vector3(0.18, 0.012, 0.06), KitMesh.xf(Vector3(0, 1.03, -0.6), Vector3(-30, 0, 0)), 0.003)
	# Lights: warm headlamp lens, red tail lights.
	b.box("dark_steel", Vector3(0.38, 0.14, 0.08), KitMesh.xf(Vector3(0, 0.5, -1.42)))
	b.box("trim:warm", Vector3(0.3, 0.08, 0.02), KitMesh.xf(Vector3(0, 0.5, -1.465)), 0.006)
	for sx: float in [-0.45, 0.45]:
		b.box("trim:red", Vector3(0.14, 0.05, 0.02), KitMesh.xf(Vector3(sx, 0.47, 1.16)), 0.004)
	# Hover pods with thin cool rings underneath; twin exhaust nozzles at the back.
	for z: float in [-0.75, 0.75]:
		b.box("dark_steel", Vector3(1.0, 0.17, 0.5), KitMesh.xf(Vector3(0, 0.14, z)))
		for sx: float in [-0.3, 0.3]:
			b.cyl("trim:cool", 0.16, 0.02, KitMesh.xf(Vector3(sx, 0.045, z)), 0.004, 20)
	for sx: float in [-0.24, 0.24]:
		b.cyl("steel", 0.075, 0.2, KitMesh.xf(Vector3(sx, 0.35, 1.2), Vector3(90, 0, 0)), 0.012, 12)
		b.cyl("dark_steel", 0.055, 0.02, KitMesh.xf(Vector3(sx, 0.35, 1.305), Vector3(90, 0, 0)), 0.004, 12)
	_mesh = KitMesh.instance(b, "restored", false)
	_mesh.name = "Body"
	root.add_child(_mesh)
	# Exhaust glow: soft additive cones behind the nozzles, scaled by speed and boost.
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_mat.albedo_color = Color(GLOW.r, GLOW.g, GLOW.b, 0.0)
	for sx: float in [-0.24, 0.24]:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.0
		cm.height = 0.5
		cm.radial_segments = 10
		cm.rings = 1
		cone.mesh = cm
		cone.material_override = _glow_mat
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.position = Vector3(sx, 0.35, 1.55)
		cone.rotation_degrees = Vector3(90, 0, 0)
		root.add_child(cone)
		_exhaust.append(cone)
	# Headlamp: a real light while it runs (thin, warm).
	_lamp = SpotLight3D.new()
	_lamp.light_color = Color(1.0, 0.86, 0.66)
	_lamp.light_energy = 0.0
	_lamp.spot_range = 14.0
	_lamp.spot_angle = 32.0
	_lamp.position = Vector3(0, 0.5, -1.5)
	root.add_child(_lamp)
	return root
