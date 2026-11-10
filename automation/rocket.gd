class_name Rocket
extends Node3D
## Lumi's travel ship (ShipModel; the class keeps its old name) standing on its LaunchPad, with the
## vapour trail and far-away flare. A display piece for the ship and pad preview scenes
## (scenes/rocket_preview.gd, scenes/ship_preview.gd). In the game the rocket is the parked
## ShipModel that planet/sites/hub_hop.gd flies between hub pads.

## [ship] The ship parks nose-out along the take-off heading.
const PARK_YAW: float = 2.2143

var pad: LaunchPad
var model: ShipModel
var tier: int = 1
## [ship] The ship's look (ShipTiers, 1..7).
var look: int = 1
var _trail: CPUParticles3D
var _dust: CPUParticles3D
var _dot: MeshInstance3D
var _base_y: float = 0.0


## Builds the ship (and the pad unless `with_pad` is false: parked on the ground).
func setup(with_pad: bool) -> void:
	tier = RocketTiers.tier()
	look = ShipTiers.look()
	process_mode = Node.PROCESS_MODE_ALWAYS
	if with_pad:
		pad = LaunchPad.new()
		pad.rocket_tier = tier
		pad.look = look
		pad.ship_yaw = PARK_YAW
		add_child(pad)
		_base_y = LaunchPad.TOP_Y
	model = ShipModel.new()
	add_child(model)
	model.build(look)
	_park_pose()
	_build_colliders()


func _ship_scale() -> float:
	return ShipTiers.scale_of(look)


## Nose along the take-off heading, gear down on the deck.
func _park_pose() -> void:
	model.position = Vector3(0, _base_y, 0)
	model.basis = Basis(Vector3.UP, PARK_YAW).scaled(Vector3.ONE * _ship_scale())


## Ship-frame direction (nose = +Z) in this node's frame.
func _dir(v: Vector3) -> Vector3:
	return Basis(Vector3.UP, PARK_YAW) * v


func _build_colliders() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var sc: float = _ship_scale()
	var e: Vector2 = ShipModel.extent(look)
	if pad:
		var deck := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = pad.radius()
		cyl.height = _base_y
		deck.shape = cyl
		deck.position = Vector3(0, _base_y * 0.5, 0)
		body.add_child(deck)
		var mast := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(1.4, 3.0, 4.4)
		mast.shape = bx
		mast.basis = Basis(Vector3.UP, PARK_YAW)
		mast.position = _dir(Vector3(pad.radius() + 1.1, 1.5, -0.6))
		body.add_child(mast)
	# The hull (a box along the nose) and the wings (a thin slab), turned with the ship.
	var hull := CollisionShape3D.new()
	var hb := BoxShape3D.new()
	hb.size = Vector3(1.8, 1.0, e.x) * sc
	hull.shape = hb
	hull.basis = Basis(Vector3.UP, PARK_YAW)
	hull.position = Vector3(0, _base_y + 1.1 * sc, 0) + _dir(Vector3(0, 0, (e.x * 0.5 - 3.4) * sc))
	body.add_child(hull)
	var wing := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(e.y * 2.0, 0.25, 3.0) * sc
	wing.shape = wb
	wing.basis = Basis(Vector3.UP, PARK_YAW)
	wing.position = Vector3(0, _base_y + 1.05 * sc, 0) + _dir(Vector3(0, 0, -1.4 * sc))
	body.add_child(wing)


func _soft_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var soft := GradientTexture2D.new()
	soft.gradient = g
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	return soft


func _build_fx() -> void:
	if _trail:
		return
	var soft: GradientTexture2D = _soft_tex()
	# Vapour trail: stays in the world as the rocket climbs (a column, then a curving ribbon).
	_trail = CPUParticles3D.new()
	_trail.emitting = false
	_trail.amount = 70
	_trail.lifetime = 7.0
	_trail.local_coords = false
	_trail.direction = Vector3(0, 0, -1)
	_trail.spread = 12.0
	_trail.initial_velocity_min = 2.0
	_trail.initial_velocity_max = 4.0
	_trail.damping_min = 1.0
	_trail.damping_max = 2.0
	_trail.gravity = Vector3(0.25, 0.2, 0)
	_trail.scale_amount_curve = LaunchPad._grow_curve(0.5, 1.5, 2.6)
	_trail.color_ramp = LaunchPad._fade_ramp(0.8)
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 2.6)
	q.material = LaunchPad.vapour_material()
	_trail.mesh = q
	_trail.position = Vector3(0, 1.0, -5.5)  # [ship] behind the engines, past the hot cores
	model.add_child(_trail)
	# Ground dust ring when there is no pad (parked landings and take-offs).
	if pad == null:
		_dust = _trail.duplicate() as CPUParticles3D
		_dust.direction = Vector3(1, 0.1, 0)
		_dust.spread = 180.0
		_dust.flatness = 0.92
		_dust.initial_velocity_min = 6.0
		_dust.initial_velocity_max = 11.0
		_dust.damping_min = 2.5
		_dust.damping_max = 3.5
		_dust.lifetime = 4.0
		_dust.amount = 22
		_dust.gravity = Vector3(0, 0.15, 0)
		_dust.position = Vector3(0, 0.4, 0)
		add_child(_dust)
	# Bright dot: a fixed-size flare that keeps the rocket visible once it is far away.
	_dot = MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(0.06, 0.06)
	_dot.mesh = dq
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.fixed_size = true
	dm.albedo_texture = soft
	dm.albedo_color = Color(0.8, 0.97, 1.0, 0.0)
	_dot.material_override = dm
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dot.position = Vector3(0, 1.0, -3.6)
	_dot.visible = false
	model.add_child(_dot)
