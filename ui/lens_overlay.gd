class_name LensOverlay
extends CanvasLayer
## First-person lens view dressing: vignette/grain shader, corner brackets, reticle and a small
## diegetic readout (zoom, iris, hopper, signal). Shown only while the camera is in lens view.

var cam: CameraRig
var patch: Patch
var _root: Control
var _readout: Label
var _signal: Label
var _t: float = 0.0


func _ready() -> void:
	layer = 4
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var fx := ColorRect.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/lens_overlay.gdshader")
	fx.material = m
	_root.add_child(fx)
	_root.draw.connect(_draw_frame)
	_readout = UITheme.label("", 13, Color(0.85, 0.95, 0.85, 0.85))
	_readout.position = Vector2(60, 50)
	_root.add_child(_readout)
	_signal = UITheme.label("", 14, Color(1, 0.35, 0.3))
	_root.add_child(_signal)
	_root.visible = false


func _draw_frame() -> void:
	var s: Vector2 = _root.size
	var col := Color(0.85, 0.95, 0.85, 0.55)
	var m: float = 40.0
	var l: float = 34.0
	for corner: Vector2 in [Vector2(m, m), Vector2(s.x - m, m), Vector2(m, s.y - m), Vector2(s.x - m, s.y - m)]:
		var dx: float = l if corner.x < s.x * 0.5 else -l
		var dy: float = l if corner.y < s.y * 0.5 else -l
		_root.draw_line(corner, corner + Vector2(dx, 0), col, 1.5)
		_root.draw_line(corner, corner + Vector2(0, dy), col, 1.5)
	var c: Vector2 = s * 0.5
	_root.draw_arc(c, 16.0, 0.0, TAU, 32, Color(col, 0.4), 1.0)
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_root.draw_line(c + d * 22.0, c + d * 34.0, col, 1.0)


func _process(delta: float) -> void:
	_t += delta
	var on: bool = cam != null and cam.lens_view
	_root.visible = on
	if not on or patch == null:
		return
	_root.queue_redraw()
	var fill: float = patch.compartment.ratio(patch.capacity()) * 100.0
	_readout.text = "LM-1  OPTICAL   %s\nIRIS  f/%.1f      HOPPER  %d%%\n%s" % [
		"REC" if fmod(_t, 1.2) < 0.7 else "   ",
		lerpf(8.0, 2.0, patch.model._iris_now if "_iris_now" in patch.model else 0.5), int(fill),
		"BALE READY" if patch.compartment.ratio(patch.capacity()) >= 0.9 else ""]
	_signal.text = ""
	if patch.detector and patch.detector.target >= 0:
		_signal.text = "◢ SIGNAL %d%%" % int(patch.detector.strength * 100.0)
	_signal.position = Vector2(_root.size.x * 0.5 - 50.0, _root.size.y * 0.5 + 44.0)
