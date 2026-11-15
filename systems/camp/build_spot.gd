class_name BuildSpot
extends Node3D
## [v10pace] A marked place for something the player has not built yet (owner: "all bases need to
## have spots to build new workbench and locker and bot builder", and the shuttle is built "at a
## marked spot"): hazard-striped corner blocks, a dashed painted outline between them and the
## thing's picture sign on a post (systems/camp/machine_art.gd). It shows while `shown` says so and
## goes away for good once `built` is true. No E prompt of its own: things are bought at the
## workbench's Build tab; the spot only says "this goes here".
##   var s := BuildSpot.mark(parent, "bot_bay", BotBay.SIZE, func() -> bool: return BotBay.built(key),
##       func() -> bool: return Camp.bench_ok(), "bot_bay")
##   s.transform = local_xf        # under any parent (a site's prefab, the world); or global_transform
## The node is named "BuildSpot_<id>"; `built` and `shown` are the caller's (no state in here).
## `sign_id` is a data/machine_art.json sign ("" = no sign post).

const CHECK_S: float = 0.5

var id: String = ""
var built: Callable
var shown: Callable
var _t: float = 0.0


static func mark(parent: Node, p_id: String, size: Vector2, p_built: Callable, p_shown: Callable = Callable(), sign_id: String = "") -> BuildSpot:
	var s := BuildSpot.new()
	s.id = p_id
	s.name = "BuildSpot_%s" % p_id
	s.built = p_built
	s.shown = p_shown
	s.add_child(outline(size).mi(0.12, "Outline"))
	if sign_id != "":
		var post: MeshInstance3D = MachineArt.sign_post(sign_id, 2.1).mi(0.12, "Sign")
		post.position = Vector3(-size.x * 0.5 - 0.1, 0.0, size.y * 0.5 + 0.1)
		s.add_child(post)
	parent.add_child(s)
	s._refresh()
	return s


## The outline: four L-shaped hazard kerbs at the corners and cream dashes along the sides.
static func outline(size: Vector2) -> YardArt.Kit:
	var k := YardArt.Kit.new()
	var hx: float = size.x * 0.5
	var hz: float = size.y * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.hazard(Vector3(0.7, 0.1, 0.16), Vector3(sx * (hx - 0.35), 0.05, sz * hz))
			k.hazard(Vector3(0.16, 0.1, 0.7), Vector3(sx * hx, 0.05, sz * (hz - 0.35)))
			k.cyl(0.07, 0.34, Vector3(sx * hx, 0.17, sz * hz), YardArt.ORANGE, Vector3.ZERO, 0.02, 10)
			k.glow_cyl(0.05, 0.05, Vector3(sx * hx, 0.36, sz * hz), YardArt.CYAN, Vector3.ZERO, 10)
	var nx: int = maxi(1, int((size.x - 1.6) / 0.6))
	for i: int in nx:
		var x: float = lerpf(-hx + 1.0, hx - 1.0, (float(i) + 0.5) / float(nx)) if nx > 1 else 0.0
		for sz: float in [-1.0, 1.0]:
			k.box(Vector3(0.34, 0.025, 0.1), Vector3(x, 0.0125, sz * hz), YardArt.CREAM, Vector3.ZERO, 0.005)
	var nz: int = maxi(1, int((size.y - 1.6) / 0.6))
	for i: int in nz:
		var z: float = lerpf(-hz + 1.0, hz - 1.0, (float(i) + 0.5) / float(nz)) if nz > 1 else 0.0
		for sx: float in [-1.0, 1.0]:
			k.box(Vector3(0.1, 0.025, 0.34), Vector3(sx * hx, 0.0125, z), YardArt.CREAM, Vector3.ZERO, 0.005)
	return k


func _refresh() -> void:
	if built.is_valid() and bool(built.call()):
		queue_free()
		return
	var on: bool = not shown.is_valid() or bool(shown.call())
	if on != visible:
		visible = on
		if on:
			for c: Node in get_children():
				YardArt.set_powered(c, true)


func _process(delta: float) -> void:
	_t += delta
	if _t >= CHECK_S:
		_t = 0.0
		_refresh()
