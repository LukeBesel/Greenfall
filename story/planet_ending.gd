class_name PlanetEnding
extends Node
## The ending of the planet being played: on `launch_ready` (systems/restoration.gd) it waits for a
## quiet moment, plays the cinematic the planet's launch rule names, rolls the credits (once per
## profile), then shows the end screen (ui/end_screen.gd). Once per save: Restoration keeps
## "ending seen" in the planet's save section, set when the end screen opens. A save that reached
## the launch point but quit before the end screen plays the ending again on its next load.
## After "Keep playing" the game simply goes on.
##
## Sequences by id (the table's launch.sequence): "bloom" = story/bloom_finale.gd. An unknown or
## empty id goes straight to the end screen.
##
## Use: var e := PlanetEnding.new(); e.setup(world, restoration); world.add_child(e)

## The player chose "Keep playing": the world gives the controls back.
signal kept_playing

const SEQUENCE_BLOOM: String = "bloom"
const TITLE_SCENE: String = "res://scenes/main_menu.tscn"
const CHECK_S: float = 1.0
const CREDITS_DELAY_S: float = 1.5

## Speed of the cinematic (1 = as written). The dev flag --launch-ready raises it.
var pace: float = 1.0
## Skips the credits roll (dev runs and the bot).
var skip_credits: bool = false
## Seconds after which the end screen answers "Keep playing" by itself (0 = wait for the player).
## The bot sets it so an unattended run goes on.
var auto_keep_s: float = 0.0

var _world: Node
var _restoration: Restoration
var _pending: bool = false
var _running: bool = false
var _t: float = 0.0


func setup(world: Node, restoration: Restoration) -> void:
	_world = world
	_restoration = restoration


func _ready() -> void:
	EventBus.launch_ready.connect(_on_launch_ready)
	if _restoration and _restoration.is_launched() and not _restoration.is_ending_seen():
		_pending = true


func _process(delta: float) -> void:
	if not _pending or _running:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = CHECK_S
	if not Bloom.story_busy(_world):
		_run()


## Whether the ending owns the screen right now.
func is_running() -> bool:
	return _running


func _on_launch_ready(_planet_id: String) -> void:
	if _restoration and not _restoration.is_ending_seen():
		_pending = true
		_t = 0.0


func _run() -> void:
	_pending = false
	_running = true
	match _restoration.launch_sequence():
		SEQUENCE_BLOOM:
			var finale := BloomFinale.new()
			finale.world = _world
			finale.pace = pace
			_world.add_child(finale)
			print("[ending] sequence '%s' starting" % SEQUENCE_BLOOM)
			finale.play()
			await finale.finished
	if not skip_credits and not GameState.flags.get("credits_seen", false):
		GameState.flags["credits_seen"] = true
		await get_tree().create_timer(CREDITS_DELAY_S).timeout
		await CreditsRoll.play(_world).finished
	_show_end_screen()


func _show_end_screen() -> void:
	_restoration.mark_ending_seen()
	var screen: EndScreen = EndScreen.open(_world, {
		"planet": Planets.current().display_name,
		"time_played": float(GameState.stats.get("time_played", 0.0)),
		"hexes_cleaned": int(GameState.stats.get("hexes_cleaned", 0)),
		"cities_restored": _restoration.districts_restored(),
		"cities_total": _restoration.districts.count() if _restoration.districts else 0,
		"robots_built": int(GameState.stats.get("robots_built", 0)),
	})
	print("[ending] end screen open")
	EventBus.ending_shown.emit(_restoration.planet_id)
	screen.kept_playing.connect(_on_kept_playing)
	screen.quit_to_title.connect(_on_quit_to_title)
	if auto_keep_s > 0.0:
		get_tree().create_timer(auto_keep_s, true, false, true).timeout.connect(screen.keep_playing)


func _on_kept_playing() -> void:
	_running = false
	print("[ending] keep playing")
	SaveManager.save_game()
	kept_playing.emit()


func _on_quit_to_title() -> void:
	_running = false
	SaveManager.save_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Loader.goto(TITLE_SCENE)
