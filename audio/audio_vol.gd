class_name AudioVol
extends RefCounted
## [qafix] Crash fix (signal 11 on the audio mixer thread, "propagate_notification" from the crash
## handler): every volume_db write on a playing player makes the AudioServer build new per-playback
## bus details and retire the old ones a frame later. Writing every frame from several fading
## players kept that churn constant, and when the mixer thread was stalled (a busy machine) it
## could still be copying retired details (a freed bus StringName). Fades now write only when the
## level really moved, at most 20 times a second per player; big jumps go through at once.

const MIN_STEP_DB: float = 0.25
const MIN_GAP_MS: int = 50
const JUMP_DB: float = 6.0
const META: StringName = &"_qafix_vol_ms"


## Sets `player.volume_db` (AudioStreamPlayer / 2D / 3D) to `db` unless the change is too small
## or too soon. Returns true when it wrote.
static func set_db(player: Node, db: float) -> bool:
	if player == null:
		return false
	var cur: float = float(player.get("volume_db"))
	var d: float = absf(cur - db)
	if d < MIN_STEP_DB:
		return false
	var now: int = Time.get_ticks_msec()
	if d < JUMP_DB and now - int(player.get_meta(META, -MIN_GAP_MS)) < MIN_GAP_MS:
		return false
	player.set_meta(META, now)
	player.set("volume_db", db)
	return true
