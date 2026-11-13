class_name StreetPower
extends Node3D
## [world3] Owner rule: "When you land there can't be working things like streetlamps. Only
## broken-down things you fix with parts and cubes." Every street light of the district starts
## dead: street lamp heads are cold glass, neon shop signs are dark tubes (several hang askew off
## one bracket), string lights across the streets are dark bulbs. They come back through progress
## you pay for, each with a little moment (the sign swings level, a few stutters, then on):
##   - a light on a hex whose HexLevels reach Sustained (4) comes on (the district's own grid),
##   - the block round a base comes on with that base at hub level 3 ("Restored": its own feed).
## The yard's own lights are Hub builds (the "Yard Lamps", data/camp.json) and hub-level layers in
## planet/street_dressing.gd; they flicker on with PowerFx too. Nothing is saved here: the state is
## derived from hex levels and the hub level, so old saves keep what they had earned.
##
## A group is one light (or a few bits that share a hex): {at, hex, node, mats, lights, tilt, on}.
## mats are neon-shader materials (their `power` uniform), lights are Light3Ds (shown when on),
## node (optional) gets `tilt` while dead and swings back to its home transform when powered.

const SUSTAINED: int = 4
const HUB_LEVEL: int = 3
const HUB_RADIUS: float = 30.0

var field: HexField
var hex_levels: HexLevels
var hub_level: int = 1
var _groups: Array[Dictionary] = []
var _wave: int = 0


## Registers lights collected by a builder (CityView.power_groups, StreetDressing.power_groups).
func add_groups(list: Array) -> void:
	for g: Dictionary in list:
		if not g.has("hex"):
			g["hex"] = field.owner_hex(g["at"]) if field else -1
		g["on"] = false
		g["init"] = false  # the first apply() puts it in its real state, whatever that is
		_groups.append(g)


## Lamp heads ([Transform3D, Color], e.g. CityView.lamp_bulbs): one dead-bulb MultiMesh per hex.
func add_bulbs(list: Array) -> void:
	var by: Dictionary = {}
	for it: Array in list:
		var h: int = field.owner_hex((it[0] as Transform3D).origin) if field else -1
		if not by.has(h):
			by[h] = []
		(by[h] as Array).append(it)
	var mesh: Mesh = ProcMesh.sphere(0.055, 10, 6)
	for h: int in by:
		var items: Array = by[h]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = items.size()
		var c := Vector3.ZERO
		for i: int in items.size():
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_color(i, items[i][1])
			c += (items[i][0] as Transform3D).origin
		var m := ShaderMaterial.new()
		m.shader = preload("res://art/shaders/neon.gdshader")
		m.set_shader_parameter("energy", 3.0)
		m.set_shader_parameter("twinkle", 1.0)
		m.set_shader_parameter("instance_seed", true)
		m.set_shader_parameter("power", 0.0)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "LampHeads%d" % h
		mmi.multimesh = mm
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 200.0
		mmi.visibility_range_end_margin = StreetDressing.VIS_MARGIN  # [v8bld]
		mmi.set_meta("street_power", true)
		add_child(mmi)
		add_groups([{"at": c / float(items.size()), "hex": h, "mats": [m], "lights": []}])


func setup(p_field: HexField, p_levels: HexLevels, p_hub_level: int) -> void:
	field = p_field
	hex_levels = p_levels
	hub_level = p_hub_level
	if not EventBus.hex_level_changed.is_connected(_on_hex_level):
		EventBus.hex_level_changed.connect(_on_hex_level)


func group_count() -> int:
	return _groups.size()


func lit_count() -> int:
	var n: int = 0
	for g: Dictionary in _groups:
		if g["on"]:
			n += 1
	return n


func powered(g: Dictionary) -> bool:
	if hub_level >= HUB_LEVEL and Vector2(g["at"].x, g["at"].z).length() <= HUB_RADIUS:
		return true
	var h: int = int(g["hex"])
	return h >= 0 and hex_levels != null and hex_levels.level_of(h) >= SUSTAINED


func set_hub_level(l: int, animate: bool) -> void:
	hub_level = l
	apply(animate)


func _on_hex_level(_hid: int, _level: int) -> void:
	apply(true)


## Switches every group to its state; live (animate) ones flicker on one after another.
func apply(animate: bool) -> void:
	var k: int = 0
	_wave += 1
	for g: Dictionary in _groups:
		var want: bool = powered(g)
		if want == g["on"] and g["init"]:
			continue
		var live: bool = g["init"]
		g["on"] = want
		g["init"] = true
		if animate and live and want:
			PowerFx.flicker_on(self, g["mats"], g["lights"], 0.25 + k * 0.35 + randf() * 0.2, g.get("node"), g.get("home"), g["at"])
			k += 1
		else:
			PowerFx.set_power(g["mats"], g["lights"], want)
			var n: Variant = g.get("node")
			if n is Node3D and is_instance_valid(n):
				(n as Node3D).transform = g["home"] if want else g.get("tilt", g["home"])
