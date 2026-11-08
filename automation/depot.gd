class_name Depot
extends Node3D
## The Depot Intake: a rusty pad with a big hungry chute. Patch rolls onto the pad and his carried
## cubes hop off his back into the chute one by one. Loose cubes pushed onto the pad get sucked in.

const PAD_RADIUS: float = 1.7
const FEED_INTERVAL: float = 0.16

var patch: Node3D  # Patch (set by the scene)
## [outposts] Outpost scales reuse this class: `bare` skips the main depot's visuals (the outpost
## builds its own and sets `mouth_local`), `world` names the slice when the parent isn't it, and
## `value_bonus` adds to the hub's sell multiplier.
var bare: bool = false
var world: Node
var pad_radius: float = PAD_RADIUS
var value_bonus: float = 0.0
var mouth_local := Vector3.ZERO
var cashed: int = 0  ## bales cashed here this session (dev reports)
var _chute: Node3D
var _chute_mouth: Vector3
var _feed_timer: float = 0.0
var _combo: int = 0
var _combo_timer: float = 0.0
var _scale_post: Node3D  # [yard]
var _needle: MeshInstance3D
var _needle_t: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	add_to_group("depot")
	if bare:
		_chute_mouth = mouth_local
	else:
		_build()


func _build() -> void:
	# A steel scrap skip on a platform weigh scale. Bales dropped on the scale plate are tipped
	# into the skip and weighed; the dial swings and the payout is logged.
	add_child(YardArt.depot_pad(PAD_RADIUS))  # [yard] tread plate, drain, hazard border, bumpers
	_chute = Node3D.new()
	_chute.position = Vector3(0, 0, -2.7)
	add_child(_chute)
	_build_body(TrashBin.level())  # [camp] the bin's body follows its level (automation/trash_bin.gd)
	TrashBin.events.changed.connect(_on_bin_changed)
	# Scale head: a teal post with a cream dial cabinet facing the plate ([yard] YardArt.depot_scale).
	var post_at := Vector3(PAD_RADIUS * 1.05, 0.0, -PAD_RADIUS * 0.6)
	_scale_post = YardArt.depot_scale()
	_scale_post.position = post_at
	add_child(_scale_post)
	YardArt.set_powered(_scale_post, YardBuilds.built("generator"))  # [world3] [yard]
	var pcs := CollisionShape3D.new()  # [world2] the dial post is solid (local frame, shared shape)
	pcs.shape = PropColliders.cyl_shape(0.12, 1.4)
	pcs.position = post_at + Vector3(0, 0.7, 0)
	var pbody := StaticBody3D.new()
	pbody.collision_layer = PhysLayers.PROP
	pbody.add_child(pcs)
	add_child(pbody)
	var face := Label3D.new()
	face.text = "kg"
	face.font_size = 24
	face.pixel_size = 0.004
	face.modulate = Color(0.15, 0.15, 0.15)
	face.shaded = true
	face.position = post_at + Vector3(0, YardArt.SCALE_DIAL_Y - 0.08, 0.125)
	add_child(face)
	_needle = MeshInstance3D.new()
	_needle.mesh = YardArt.bbox(Vector3(0.018, 0.16, 0.012), 0.004)
	_needle.material_override = Mats.rubber(Color(0.75, 0.1, 0.05))  # [world3] painted, not lit
	_needle.position = post_at + Vector3(0, YardArt.SCALE_DIAL_Y, 0.13)
	add_child(_needle)
	# [world3] A dead bulb (nothing works when you land) until the generator is built (Hub tab).
	YardBuilds.events.built.connect(func(id: String) -> void:
		if id == "generator" and is_inside_tree():
			YardArt.flicker_on(self, _scale_post, 1.0))  # [yard] the scale lamp's glow and light

func pad_contains(world_pos: Vector3) -> bool:
	var d: Vector3 = _local(world_pos)  # [orbit] the pad's own up (a depot on a round planet is tilted)
	d.y = 0.0
	return d.length() <= pad_radius


## A world point in the depot's frame (unscaled): y is height above the pad.
func _local(world_pos: Vector3) -> Vector3:
	return global_basis.orthonormalized().inverse() * (world_pos - global_position)


## What a bale is worth here relative to its base value (hub level bonus + this scale's bonus).
func sell_factor() -> float:
	var w: Node = world if world else get_parent()
	var m: float = 1.0 + value_bonus
	if not bare:
		m *= TrashBin.value_mult()  # [camp] the bin's level
	if w and w.get("hub") != null:
		m += float(w.hub.sell_mult())
	if w and w.get("field") != null:  # [biomes] frontier junk sells for more (data/frontiers.json value_mult)
		m *= float(Frontiers.def_for_biome(str(w.field.biome)).get("value_mult", 1.0))
	return m


func mouth_world() -> Vector3:
	return to_global(_chute_mouth)


func _physics_process(delta: float) -> void:
	_t += delta
	_needle_t = maxf(0.0, _needle_t - delta * 0.8)
	if _needle:
		_needle.rotation.z = -_needle_t * 2.4 + sin(_t * 23.0) * 0.02 * _needle_t
	_combo_timer -= delta
	if _combo_timer <= 0.0:
		_combo = 0
	_feed_timer -= delta
	if patch and _feed_timer <= 0.0 and pad_contains(patch.global_position) and patch.has_method("pop_carried_cube"):
		var cube: JunkCube = patch.pop_carried_cube()
		if cube:
			_feed_timer = FEED_INTERVAL if bare else TrashBin.feed_interval()  # [camp]
			_swallow(cube)
	if patch and not bare and _feed_timer <= 0.0:  # [pace] no Baler yet: empty the chest loose
		var bin: Node3D = Pace.trash_bin(get_tree(), global_position)
		if bin:
			Pace.try_dump(patch, bin.global_position, Pace.BIN_RADIUS, bin)
		else:
			Pace.try_dump(patch, global_position, pad_radius)
	# Loose cubes on the pad get sucked in.
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var c: JunkCube = n
		if c.carried or c.claimed:
			continue
		var low: bool = c.global_position.y < 3.0 if JunkCube.planet_radius <= 0.0 else _local(c.global_position).y < 3.0  # [orbit]
		if pad_contains(c.global_position) and low:
			_swallow(c)


func _swallow(cube: JunkCube) -> void:
	cube.claimed = true
	cube.set_carried(true)
	var start: Vector3 = cube.global_position
	var end: Vector3 = mouth_world()
	var top: Vector3 = (start + end) * 0.5 + global_basis.y.normalized() * 2.2
	Audio.play("whoosh", 1.2, -8.0)
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var a: Vector3 = start.lerp(top, t)
		var b: Vector3 = top.lerp(end, t)
		cube.global_position = a.lerp(b, t)
		cube.rotation += Vector3(0.15, 0.2, 0.1)
		, 0.0, 1.0, 0.32).set_trans(Tween.TRANS_SINE)
	tw.tween_property(cube, "scale", Vector3.ONE * 0.2, 0.08)
	tw.tween_callback(_cash.bind(cube))


func _cash(cube: JunkCube) -> void:
	_combo += 1
	_combo_timer = 1.2
	cashed += 1
	var v: BigNum = cube.value
	v = v.mul_f(sell_factor())
	GameState.add_currency("cubes", v)
	GameState.inc_stat("cubes_cashed")
	if bare:
		GameState.inc_stat("outpost_bales")  # [outposts]
	EventBus.cube_cashed.emit(v, mouth_world())
	Audio.play_scale("coin", mini(_combo - 1, 8), -4.0)
	var col: Color = Color(1.0, 0.75, 0.35) if cube.info.get("perfect", false) else Color(0.9, 0.92, 0.88)
	Vfx.float_text(mouth_world() + Vector3(0, 0.3, 0), "+" + Settings.fmt(v), col, 0.5, 0.8)
	Vfx.burst("dust", mouth_world() - Vector3(0, 0.3, 0), Color(0.6, 0.55, 0.5, 0.5), 0.8)
	Audio.play("clunk", 0.8, -4.0)
	_needle_t = 1.0
	if _ram:  # [camp] the compactor presses each bale
		var tw := create_tween()
		tw.tween_property(_ram, "position:y", 1.35, 0.08)
		tw.tween_property(_ram, "position:y", 1.95, 0.3).set_trans(Tween.TRANS_SINE)
	EventBus.shake_requested.emit(0.05)
	cube.queue_free()


# --- [camp] The bin's body by level (data/trash_bin.json) ---------------------------------------

var _ram: Node3D  # level 4+: the compactor ram plate (bobs as a bale goes in)
var _body_level: int = 0


func _on_bin_changed(l: int) -> void:
	if bare or not is_inside_tree() or l == _body_level:
		return
	_build_body(l)
	Vfx.burst("dust", mouth_world(), Color(0.7, 0.65, 0.6, 0.6), 1.4)
	Vfx.burst("sparkle", mouth_world() + Vector3(0, 0.4, 0), Color(1.0, 0.85, 0.5), 0.8)
	Audio.play("clunk", 0.7, -2.0)
	_chute.scale = Vector3(1, 0.05, 1)
	create_tween().tween_property(_chute, "scale", Vector3.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_body(l: int) -> void:
	_body_level = l
	_ram = null
	for c: Node in _chute.get_children():
		c.queue_free()
	var size: Vector3 = _build_bin_art(l)  # [yard]
	var sb := StaticBody3D.new()
	sb.name = "BinBody"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	sb.add_child(cs)
	_chute.add_child(sb)


## [yard] The body comes from YardArt.bin_body (systems/camp/yard_art.gd): L1 a dented rusty
## wheelie bin, L2 a fresh skip, L3 ribs and an amber beacon, L4 a compactor frame and ram, L5 a
## clean white smart shell with a cyan seam. Returns the collider size.
func _build_bin_art(l: int) -> Vector3:
	var b: Dictionary = YardArt.bin_body(l)
	var root: Node3D = b["root"]
	_chute.add_child(root)
	_ram = b["ram"]
	var fill := MeshInstance3D.new()
	fill.mesh = FieldView._mound_mesh()
	fill.material_override = AssetLib.pbr_material("rubble", 1.0, Color(0.6, 0.55, 0.5), true)
	fill.position = (b["fill"] as Array)[0]
	fill.scale = (b["fill"] as Array)[1]
	root.add_child(fill)
	# [yard] labels are kit decals on the body now (images, never 3D text)
	_chute_mouth = _chute.position + Vector3(0, float(b["mouth_y"]), 0)
	return b["size"]
