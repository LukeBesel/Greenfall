class_name PartDetector
extends Node3D
## Patch's part detector. Beeps faster and blinks a red lamp as he closes in on a buried robot
## part; near it, the lens readout shows the signal's rarity color. Interact to dig it up.

signal readout_changed(text: String, color: Color, strength: float)

var patch: Node3D
var field: HexField
var target: int = -1
var strength: float = 0.0  # 0..1 signal strength
var digging: float = 0.0

var _cfg: Dictionary
var _beep_timer: float = 0.0
var _lamp: MeshInstance3D
var _lamp_mat: StandardMaterial3D
var _light: OmniLight3D
var _flash: float = 0.0


func _ready() -> void:
	_cfg = Economy.parts.get("detector", {})
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.25, 0.02, 0.02)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.08, 0.05)
	_lamp_mat.emission_energy_multiplier = 0.0
	_lamp = MeshInstance3D.new()
	_lamp.mesh = ProcMesh.sphere(0.035, 10, 5)
	_lamp.material_override = _lamp_mat
	add_child(_lamp)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.1, 0.05)
	_light.omni_range = 2.5
	_light.light_energy = 0.0
	add_child(_light)


func range_m() -> float:
	# Base 16 m lives in data/patch.json; the Detector Coil upgrade and Research mods scale it.
	var r: float = Economy.stat("detector_range")
	return r if r > 0.0 else float(_cfg.get("range", 16.0))


func _process(delta: float) -> void:
	if patch == null or field == null:
		return
	# Lamp sits on the sensor head (lens point, a little up and to the side).
	# Small warning lamp on the crown, behind the antenna: never on the face, where it reads as an eye.
	position = Vector3(-0.15, 1.06, 0.16)
	_flash = maxf(0.0, _flash - delta * 9.0)
	_lamp_mat.emission_energy_multiplier = 0.15 + _flash * 6.0
	_light.light_energy = _flash * 1.6
	if digging > 0.0:
		return
	var r: float = range_m()
	target = field.nearest_part(patch.global_position, r)
	if target < 0:
		strength = 0.0
		readout_changed.emit("", Color.WHITE, 0.0)
		return
	var p: Vector3 = field.part_pos[target]
	var d: float = Vector2(p.x - patch.global_position.x, p.z - patch.global_position.z).length()
	var sig: float = float(Economy.rarity(field.part_rarity[target]).get("signal", 1.0))
	strength = clampf(1.0 - d / (r * sig), 0.0, 1.0)
	var interval: float = lerpf(float(_cfg.get("max_interval", 1.4)), float(_cfg.get("min_interval", 0.08)), pow(strength, 1.6))
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		_beep_timer = interval
		_flash = 1.0
		Audio.play("detector", lerpf(0.9, 1.5, strength), lerpf(-20.0, -7.0, strength), 0.0)
	var rar: Dictionary = Economy.rarity(field.part_rarity[target])
	var text: String = ""
	var col := Color(1, 0.3, 0.25)
	if d < 4.0:
		text = tr("SIGNAL  %s  ·  %.1f m") % [tr(str(rar.get("name", "?"))).to_upper(), d]
		col = UITheme.rarity_color(field.part_rarity[target])
	elif strength > 0.0:
		text = tr("SIGNAL  %d%%") % int(strength * 100.0)
	readout_changed.emit(text, col, strength)


func can_dig() -> bool:
	if target < 0 or digging > 0.0:
		return false
	var p: Vector3 = field.part_pos[target]
	return Vector2(p.x - patch.global_position.x, p.z - patch.global_position.z).length() <= float(_cfg.get("dig_range", 1.4))


## Starts digging; calls back on_found(part_index) when done.
func dig(on_found: Callable) -> void:
	if not can_dig():
		return
	var idx: int = target
	digging = float(_cfg.get("dig_time", 1.3))
	var p: Vector3 = field.part_pos[idx]
	Audio.play("dig", 1.0, -6.0)
	var tw := create_tween()
	for k: int in 3:
		tw.tween_callback(func() -> void:
			Vfx.burst("soil", p + Vector3(0, 0.05, 0), Color(0.42, 0.34, 0.27))
			Audio.play("dig", randf_range(0.9, 1.1), -9.0)
			if patch.model.has_method("shudder"):
				patch.model.shudder(0.15))
		tw.tween_interval(digging / 3.0)
	tw.tween_callback(func() -> void:
		digging = 0.0
		field.part_found[idx] = 1
		target = -1
		on_found.call(idx))
