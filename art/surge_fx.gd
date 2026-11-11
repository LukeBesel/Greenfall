class_name SurgeFx
extends Node
## What a Surge (systems/surge.gd) looks and sounds like. It only listens: surge_charged,
## surge_released and surge_ended on EventBus.
##   charged    Lumi's core flashes, a chime, and for the first few charges a line that names the
##              release key
##   released   a column of light, three coloured rings racing out over the ground, sparkles, a
##              charge-up and fanfare, a camera shake, a pad rumble, the screen's edge lit up, and
##              Lumi's core glowing hard; with a growth wave, a green front sweeping out as far
##              as the wave reached
##   running    a trail of sparkles and a ground ring at the sweep's width, the edge glow draining
##              with the time left, ticks over the last seconds
##   ended      a soft vent of steam and the core back to its own glow
## Shake goes through EventBus.shake_requested (the camera honours the Shake setting); Reduced
## motion stills the edge glow's rays and drops the flash.
## Dev: with --surge-demo the game clock stops at the burst's peak (--surge-demo-peak=0.35 seconds
## after the release), so a slow software render can take its screenshot of that instant.

## Saturated on purpose: the burst is drawn over sunlit ground, where pale light washes out.
const CYAN := Color(0.05, 0.78, 1.0)
const GREEN := Color(0.15, 0.95, 0.4)
const GOLD := Color(1.0, 0.72, 0.1)
const EDGE_SHADER: Shader = preload("res://art/shaders/surge_edge.gdshader")
## Charges whose toast names the release key; after that the gauge's own prompt is enough.
const HINTS: int = 3
const HINT_FLAG: String = "surge_hints"
const GLOW_PEAK: float = 2.6
const TRAIL_S: float = 0.16
const RING_S: float = 0.9
const LAST_TICKS_S: float = 3.0
const EDGE_STRENGTH: float = 0.55
const CELL_M: float = PlanetDefinition.CELL_M
const FLAG_DEMO_PEAK: String = "surge-demo-peak"

var _lumi: Patch
var _surge: Surge
var _edge: ShaderMaterial
var _flash: float = 0.0
var _trail_t: float = 0.0
var _ring_t: float = 0.0
var _tick_at: int = 0
var _trail_i: int = 0
var _freeze_in: float = -1.0


## The key (or the pad's two buttons) that releases a Surge, for prompts.
static func release_glyph() -> String:
	if Settings.last_input_pad:
		return "%s + %s" % [Settings.glyph(Surge.PAD_CHORD[0]), Settings.glyph(Surge.PAD_CHORD[1])]
	return Settings.glyph(Surge.ACTION)


func setup(lumi: Patch, surge: Surge) -> void:
	_lumi = lumi
	_surge = surge


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SurgeEdge"
	layer.layer = 0  # over the world, under the HUD
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge = ShaderMaterial.new()
	_edge.shader = EDGE_SHADER
	rect.material = _edge
	layer.add_child(rect)
	EventBus.surge_charged.connect(_on_charged)
	EventBus.surge_released.connect(_on_released)
	EventBus.surge_ended.connect(_on_ended)


func _exit_tree() -> void:
	EventBus.surge_charged.disconnect(_on_charged)
	EventBus.surge_released.disconnect(_on_released)
	EventBus.surge_ended.disconnect(_on_ended)


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 1.6)
	if _freeze_in >= 0.0:
		_freeze_in -= delta
		if _freeze_in < 0.0:
			Engine.time_scale = 0.0
	var running: bool = _surge != null and _surge.active()
	var left: float = _surge.time_left() / maxf(_surge.duration(), 0.001) if running else 0.0
	_edge.set_shader_parameter("strength", EDGE_STRENGTH * (0.45 + 0.55 * left) if running else 0.0)
	_edge.set_shader_parameter("flash", _flash)
	_edge.set_shader_parameter("motion", 0.0 if Settings.reduced_motion else 1.0)
	if not running or _lumi == null:
		return
	var pos: Vector3 = _lumi.global_position
	var up: Vector3 = _lumi.up()
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = TRAIL_S
		_trail_i += 1
		Vfx.burst("sparkle", pos + up * 0.5, [CYAN, GREEN, GOLD][_trail_i % 3], 0.4)
	_ring_t -= delta
	if _ring_t <= 0.0:
		_ring_t = RING_S
		Vfx.ring(pos, maxf(_lumi.stat("scoop_width"), 1.0) * 1.2, Color(GREEN, 0.7), 0.6)
	var whole_left: int = ceili(_surge.time_left())
	if _surge.time_left() <= LAST_TICKS_S and whole_left != _tick_at:
		_tick_at = whole_left
		Audio.play("tick", 1.0 + 0.15 * float(int(LAST_TICKS_S) - whole_left), -10.0, 0.0)


func _on_charged() -> void:
	Audio.play("chime", 1.5, -8.0)
	Audio.play("charge", 1.6, -14.0)
	if _lumi != null:
		_lumi.model.flash()
		Vfx.burst("sparkle", _lumi.global_position + _lumi.up() * 0.9, GREEN, 0.8)
	var shown: int = int(GameState.flags.get(HINT_FLAG, 0))
	if shown < HINTS:
		GameState.flags[HINT_FLAG] = shown + 1
		# TRANSLATORS: %s is the key, or the two pad buttons, that release the Surge.
		EventBus.toast.emit(tr("Bloom Core full. Press %s to release a Surge.") % release_glyph(), "info")


func _on_released(_district_id: String, output: float, wave_rings: int) -> void:
	Audio.play("charge", 1.0, -3.0, 0.0)
	Audio.play("fanfare", 1.5, -8.0, 0.0)
	Audio.play("sweep", 0.7, -5.0)
	EventBus.shake_requested.emit(0.3)
	Input.start_joy_vibration(0, 0.6, 0.8, 0.4)
	_flash = 0.0 if Settings.reduced_motion else 1.0
	_trail_t = 0.0
	_ring_t = RING_S * 0.5
	_tick_at = 0
	if DevHooks.has(Surge.FLAG_DEMO):
		_freeze_in = DevHooks.get_f(FLAG_DEMO_PEAK, 0.35)
	if _lumi == null:
		return
	var pos: Vector3 = _lumi.global_position
	var up: Vector3 = _lumi.up()
	Vfx.pillar(pos, GREEN, 10.0, 1.8)
	Vfx.pillar(pos, CYAN, 6.0, 1.2)
	Vfx.ring(pos, 6.0, CYAN, 0.5)
	Vfx.ring(pos, 6.3, CYAN, 0.5)
	Vfx.ring(pos, 10.0, GREEN, 0.8)
	Vfx.ring(pos, 10.4, GREEN, 0.8)
	Vfx.ring(pos, 14.0, GOLD, 1.1)
	Vfx.ring(pos, 14.5, GOLD, 1.1)
	Vfx.burst("big_sparkle", pos + up * 1.0, CYAN, 1.6)
	Vfx.burst("sparkle", pos + up * 1.4, GOLD, 1.5)
	# TRANSLATORS: %s is how many times Lumi's sweep output a Surge gives, e.g. 3.2.
	Vfx.float_text(pos + up * 2.2, tr("SURGE  x%s") % ("%.1f" % output), GREEN, 2.0)
	_lumi.model.flash()
	_lumi.model.set_happy(1.0)
	_glow_to(GLOW_PEAK, 0.25)
	if wave_rings > 0:
		var reach: float = (float(wave_rings) + 0.5) * CELL_M
		Vfx.sweep(pos, reach, reach / 1.4, Color(0.55, 1.0, 0.5, 0.7), true)
		Vfx.ring(pos, reach, Color(GREEN, 0.9), 1.4)
		Audio.play("sparkle", 0.9, -6.0)
		Audio.play("chime", 0.8, -8.0)


func _on_ended() -> void:
	Audio.play("steam", 0.9, -10.0)
	Audio.play("thunk", 1.2, -12.0)
	_glow_to(CoreCharge.glow_for_flags(), 0.8)
	if _lumi == null:
		return
	Vfx.ring(_lumi.global_position, 3.0, Color(CYAN, 0.6), 0.5)
	for vent: Vector3 in _lumi.model.vent_points:
		Vfx.burst("steam", _lumi.to_global(vent), Color(0.92, 0.98, 0.95, 0.5), 0.5)


func _glow_to(value: float, seconds: float) -> void:
	if _lumi == null:
		return
	_lumi.model.create_tween().tween_property(_lumi.model, "core_glow", value, seconds)
