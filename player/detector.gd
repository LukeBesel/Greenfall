class_name PartDetector
extends Node3D
## Patch's part detector. Beeps faster and blinks a red lamp as he closes in on a buried robot
## part; near it, the lens readout shows the signal's rarity color. Interact to dig it up.
## It hears one more kind of thing when the world gives it `cache_fn`: a buried find lying in
## cleared soil (a paint tin, a lens chip; systems/find_sites.gd). That signal uses the same lamp,
## beep and readout, comes before a part's, and is dug up by using the spot itself.

signal readout_changed(text: String, color: Color, strength: float)

var patch: Node3D
var field: HexField
var target: int = -1
var strength: float = 0.0  # 0..1 signal strength
var digging: float = 0.0
## func(pos: Vector3, range_m: float) -> Dictionary: the nearest buried find in range as
## {id, pos, label, color} ({} when none). Set by the world.
var cache_fn: Callable
## The buried find the detector is on now ({} when it is on a part or on nothing).
var cache: Dictionary = {}

var _cfg: Dictionary
var _beep_timer: float = 0.0
var _sound_t: float = 0.0  # [v2feel] time to the next audible beep
const SOUND_NEAR_M: float = 3.0  # [v4calm] the beep is heard only this close to the part
const SOUND_GAP_S: float = 2.0  # [v4calm] shortest gap between audible beeps (was 0.45)
const SOUND_DB: float = -24.0  # [v4calm] quiet
const NEAR_M: float = 4.0  # the readout names the thing and its distance this close
const SOIL := Color(0.42, 0.34, 0.27)
const DIG_BURSTS: int = 3
var _flash: float = 0.0


func _ready() -> void:
	_cfg = Economy.parts.get("detector", {})


func range_m() -> float:
	# Base 16 m lives in data/patch.json; the Detector Coil upgrade and Research mods scale it.
	var r: float = Economy.stat("detector_range")
	return r if r > 0.0 else float(_cfg.get("range", 16.0))


func _process(delta: float) -> void:
	if patch == null or field == null:
		return
	# [hero] The red lamp is the model's head-mounted beacon (PatchModel.set_beacon): it rides the
	# head through every animation instead of floating at a fixed spot on Patch.
	_flash = maxf(0.0, _flash - delta * 9.0)
	var model: Variant = patch.get("model")
	if model is PatchModel:
		(model as PatchModel).set_beacon(_flash)
	if digging > 0.0:
		return
	if not active():  # [onboard] quiet during the restart checklist: one new thing at a time
		target = -1
		cache = {}
		strength = 0.0
		readout_changed.emit("", Color.WHITE, 0.0)
		return
	var r: float = range_m()
	cache = cache_fn.call(patch.global_position, r) if cache_fn.is_valid() else {}
	if not cache.is_empty():
		target = -1
		_ping_cache(delta, r)
		return
	target = field.nearest_part(patch.global_position, r)
	if target < 0:
		strength = 0.0
		readout_changed.emit("", Color.WHITE, 0.0)
		return
	var d: float = field.part_distance(target, patch.global_position)  # [orbB] along the ground (flat: x/z)
	var sig: float = float(Economy.rarity(field.part_rarity[target]).get("signal", 1.0))
	strength = clampf(1.0 - d / (r * sig), 0.0, 1.0)
	_blink(delta, d)
	var rar: Dictionary = Economy.rarity(field.part_rarity[target])
	var text: String = ""
	var col := Color(1, 0.3, 0.25)
	if d < NEAR_M:
		# [onboard] "BURIED PART" says what the signal is (it read "SIGNAL 62%", unexplained).
		text = tr("BURIED PART  %s  ·  %.1f m") % [tr(str(rar.get("name", "?"))).to_upper(), d]
		col = UITheme.rarity_color(field.part_rarity[target])
	elif strength > 0.0:
		text = tr("BURIED PART  ·  SIGNAL %d%%") % int(strength * 100.0)
	readout_changed.emit(text, col, strength)


## The lamp blinks faster the stronger the signal; the beep is heard only close by.
func _blink(delta: float, dist_m: float) -> void:
	var interval: float = lerpf(float(_cfg.get("max_interval", 1.4)), float(_cfg.get("min_interval", 0.08)), pow(strength, 1.6))
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		_beep_timer = interval
		_flash = 1.0
		# [v2feel] Owner item 32: the lamp's beep played nonstop (the globe always has a part in
		# range). Far off the lamp only blinks; it beeps once Lumi is homing in, and never faster
		# than SOUND_GAP_S.
		# [v4calm] Owner item 50: still too much. Silent unless Lumi is right on it (SOUND_NEAR_M),
		# one soft beep per SOUND_GAP_S at most.
		if beep_allowed(dist_m, _sound_t):
			_sound_t = SOUND_GAP_S
			Audio.play("detector", lerpf(1.0, 1.2, strength), SOUND_DB, 0.0)
	_sound_t = maxf(0.0, _sound_t - delta)


## The signal of a buried find: the same lamp, beep and readout line as a part's, in the find's
## own colour and with its own name ("BURIED TIN").
func _ping_cache(delta: float, r: float) -> void:
	var d: float = OrbitUp.ground_dist(patch.global_position, cache["pos"])
	strength = clampf(1.0 - d / r, 0.0, 1.0)
	_blink(delta, d)
	var label: String = str(cache.get("label", ""))
	var text: String = tr("%s  ·  %.1f m") % [label, d] if d < NEAR_M else tr("%s  ·  SIGNAL %d%%") % [label, int(strength * 100.0)]
	readout_changed.emit(text, cache.get("color", Color.WHITE), strength)


## [v4calm] An audible beep: only within SOUND_NEAR_M, and once the gap timer has run out.
static func beep_allowed(dist_m: float, gap_left: float) -> bool:
	return dist_m <= SOUND_NEAR_M and gap_left <= 0.0


## [onboard] The detector listens once the restart checklist is done (dev: --detector-on).
static func active() -> bool:
	return int(GameState.flags.get("tutorial_step", 0)) >= Tutorial.STEPS.size() or DevHooks.has("detector-on")


func can_dig() -> bool:
	if target < 0 or digging > 0.0:
		return false
	return field.part_distance(target, patch.global_position) <= float(_cfg.get("dig_range", 1.4))  # [orbB]


## Starts digging; calls back on_found(part_index) when done.
func dig(on_found: Callable) -> void:
	if not can_dig():
		return
	var idx: int = target
	dig_at(field.part_pos[idx], float(_cfg.get("dig_time", 1.3)), func() -> void:
		field.part_found[idx] = 1
		target = -1
		on_found.call(idx))


## The time a dig at a part takes (the planet's parts data).
func dig_time() -> float:
	return float(_cfg.get("dig_time", 1.3))


## A short dig at a spot: the dig sound, soil thrown up and Lumi's shudder for `seconds`, then
## `done` is called. The detector is deaf while it lasts. False when a dig is already running.
func dig_at(pos: Vector3, seconds: float, done: Callable, soil: Color = SOIL) -> bool:
	if digging > 0.0:
		return false
	digging = maxf(seconds, 0.05)
	var up: Vector3 = OrbitUp.up(pos)
	Audio.play("dig", 1.0, -6.0)
	var tw := create_tween()
	for k: int in DIG_BURSTS:
		tw.tween_callback(func() -> void:
			Vfx.burst("soil", pos + up * 0.05, soil)
			Audio.play("dig", randf_range(0.9, 1.1), -9.0)
			var model: Variant = patch.get("model") if patch else null
			if model is Node and (model as Node).has_method("shudder"):
				(model as Node).call("shudder", 0.15))
		tw.tween_interval(digging / float(DIG_BURSTS))
	tw.tween_callback(func() -> void:
		digging = 0.0
		done.call())
	return true
