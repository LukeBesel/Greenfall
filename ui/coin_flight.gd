class_name CoinFlight
extends Control
## [first] Selling feedback: when a bale is cashed, a few small amber cubes leap from the scale's
## screen position and arc into the currency counter (top-left). The counter holds the sale back
## (CurrencyCluster.in_flight) and counts up as each cube lands, with a soft rising tick.
## Off screen or with the HUD hidden it simply adds the value at once.

const DUR: float = 0.62
const STAGGER: float = 0.045

var cluster: CurrencyCluster
var _coins: Array[Dictionary] = []
var _combo: int = 0
var _combo_t: float = 0.0


static var _inst: CoinFlight  # [v1guide]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.cube_cashed.connect(_on_cashed)
	_inst = self


## [v1guide] Cubes from somewhere that isn't a bale sale (the trash bin before the Baler) fly into
## the counter the same way, without counting as a sold bale. Already added to the wallet.
static func fly(world_pos: Vector3, value: float) -> void:
	if is_instance_valid(_inst) and value > 0.0:
		_inst._on_cashed(BigNum.from_float(value), world_pos)


static func coin_count(value: float) -> int:
	return clampi(3 + int(floor(log(maxf(value, 1.0)) / log(10.0))), 3, 8)


func _on_cashed(v: BigNum, world_pos: Vector3) -> void:
	if cluster == null or not is_visible_in_tree() or not cluster.is_visible_in_tree():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos):
		return
	var from: Vector2 = cam.unproject_position(world_pos)
	var vs: Vector2 = get_viewport_rect().size
	if from.x < -40.0 or from.y < -40.0 or from.x > vs.x + 40.0 or from.y > vs.y + 40.0:
		return
	var value: float = v.to_float()
	if value >= 1.0e9:
		return
	var n: int = coin_count(value)
	var to: Vector2 = cluster.icon_center()
	cluster.in_flight += value
	_combo = _combo + 1 if _combo_t > 0.0 else 0
	_combo_t = 1.5
	for k: int in n:
		var ang: float = randf_range(-PI, 0.0)
		var kick: Vector2 = Vector2(cos(ang), sin(ang)) * randf_range(40.0, 90.0)
		_coins.append({"from": from, "kick": kick, "to": to, "t": -k * STAGGER, "share": value / n,
			"spin": randf_range(-6.0, 6.0), "size": randf_range(5.0, 7.0), "k": k})


func _process(delta: float) -> void:
	_combo_t -= delta
	if _coins.is_empty():
		return
	for i: int in range(_coins.size() - 1, -1, -1):
		var c: Dictionary = _coins[i]
		c["t"] = float(c["t"]) + delta
		if float(c["t"]) >= DUR:
			if cluster:
				cluster.land(float(c["share"]))
			Audio.play("tick", 1.0 + 0.06 * float(c["k"]) + 0.03 * mini(_combo, 6), -14.0, 0.0)
			_coins.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for c: Dictionary in _coins:
		var t: float = float(c["t"])
		if t < 0.0:
			continue
		var u: float = clampf(t / DUR, 0.0, 1.0)
		var from: Vector2 = c["from"]
		var to: Vector2 = c["to"]
		# Quick hop out of the scale, then an eased curve into the counter.
		var hop: Vector2 = from + (c["kick"] as Vector2)
		var e: float = u * u * (3.0 - 2.0 * u)
		var a: Vector2 = from.lerp(hop, minf(u * 3.0, 1.0))
		var ctrl: Vector2 = Vector2(lerpf(hop.x, to.x, 0.25), minf(hop.y, to.y) - 60.0)
		var b: Vector2 = hop.lerp(ctrl, e).lerp(ctrl.lerp(to, e), e)
		var p: Vector2 = a.lerp(b, smoothstep(0.1, 0.4, u))
		var s: float = float(c["size"]) * lerpf(1.0, 0.7, u)
		var alpha: float = minf(1.0, u * 8.0)
		var rot: float = float(c["spin"]) * t
		var xf := Transform2D(rot, p)
		draw_set_transform_matrix(xf)
		draw_rect(Rect2(-s - 1.5, -s - 1.5, (s + 1.5) * 2.0, (s + 1.5) * 2.0), Color(0, 0, 0, 0.3 * alpha))
		draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), Color(UITheme.GOLD, 0.95 * alpha))
		draw_rect(Rect2(-s, -s, s * 2.0, s * 0.7), Color(1.0, 0.9, 0.65, 0.6 * alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)
