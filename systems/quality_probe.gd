class_name QualityProbe
extends Node
## [deck] First-play frame-time probe. When the preset was auto-detected (Settings.quality_auto)
## and the probe hasn't run, it waits for the game scene to settle (shaders compiled), measures
## the average frame rate for a few seconds and steps the preset down while it is under
## TARGET_FPS, then remembers it ran. A preset the player picked is never touched.
## DevHooks runs (tools, screenshots) skip it unless `--probe` is passed.

const TARGET_FPS: float = 45.0
const SETTLE_S: float = 6.0
const SAMPLE_S: float = 6.0
const GAME_SCENE: String = "res://scenes/slice.tscn"

var _scene: Node
var _phase: int = 0  # 0 waiting for the game scene, 1 settling, 2 sampling
var _t0: int = 0
var _frames: int = 0
var _worst_ms: float = 0.0
var _last_ms: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Whether a probe should run now (pure, for tests).
static func wanted(auto: bool, done: bool, quality: int, headless: bool, dev_run: bool) -> bool:
	return auto and not done and quality > 0 and not headless and not dev_run


## The preset to use after measuring `fps` (one step down when too slow, never below Low).
static func next_quality(quality: int, fps: float, target: float = TARGET_FPS) -> int:
	return quality - 1 if fps < target and quality > 0 else quality


func _process(_delta: float) -> void:
	var dev: bool = not DevHooks.args.is_empty() and not DevHooks.has("probe")
	if not wanted(Settings.quality_auto, Settings.quality_probe_done, Settings.quality, DisplayServer.get_name() == "headless", dev):
		set_process(false)
		return
	var cur: Node = get_tree().current_scene
	var now: int = Time.get_ticks_msec()
	if cur == null or cur.scene_file_path != GAME_SCENE or get_tree().paused:
		_phase = 0
		return
	if cur != _scene or _phase == 0:
		_scene = cur
		_phase = 1
		_t0 = now
		return
	if _phase == 1:
		if now - _t0 >= SETTLE_S * 1000.0:
			_phase = 2
			_t0 = now
			_frames = 0
			_last_ms = now
		return
	_frames += 1
	_last_ms = now
	var el: float = (now - _t0) / 1000.0
	if el < SAMPLE_S:
		return
	var fps: float = _frames / el
	var target: float = TARGET_FPS
	var hz: float = DisplayServer.screen_get_refresh_rate()
	if Settings.vsync and hz > 0.0 and hz < 50.0:
		target = hz * 0.85  # 30/40 Hz screens (Deck's 40 Hz mode): judge against the refresh rate
	var q: int = next_quality(Settings.quality, fps, target)
	print("[quality] probe: %.1f fps at %s (target %.0f)" % [fps, QualityDetect.preset_name(Settings.quality), target])
	if q != Settings.quality:
		Settings.quality = q
		Settings.quality_note += ("; " if Settings.quality_note != "" else "") + "stepped down after a frame-rate check"
		Settings.apply_quality_to_tree(cur)
		Settings.save_settings()
		EventBus.toast.emit("Graphics set to %s to keep things smooth. You can change it in Settings." % QualityDetect.preset_name(q), "info")
		_phase = 1  # settle and measure again at the new preset
		_t0 = now
		return
	Settings.quality_probe_done = true
	Settings.save_settings()
	set_process(false)
