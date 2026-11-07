class_name Demo
extends RefCounted
## The Steam demo build. One check drives every limit: Demo.is_demo() is true in an export with the
## "demo" feature tag (the "* Demo" presets in export_presets.cfg) or when the game is started with
## the dev hook `-- --demo`. Limits (nothing else changes):
##   - the first district only: no rocket launches,
##   - the base caps at level MAX_BASE_LEVEL,
##   - an end-of-demo screen with a wishlist call to action (steam/demo_end_screen.gd) appears the
##     first time the player has earned the next base level, or when they hit a limit.
## Demo saves live in their own folder (SaveManager), and the full game imports them on first run.

const MAX_BASE_LEVEL: int = 2
const FEATURE: String = "demo"
const SAVE_DIR: String = "user://saves_demo"

## Tests (and tools) can force the demo on or off; -1 = decide from the feature tag / dev hook.
static var override: int = -1
static var _cached: int = -1


static func is_demo() -> bool:
	if override >= 0:
		return override == 1
	if _cached < 0:
		_cached = 1 if (OS.has_feature(FEATURE) or "--demo" in OS.get_cmdline_user_args()) else 0
	return _cached == 1


## Can the base be upgraded from `level` to level + 1?
static func can_raise_base(level: int) -> bool:
	return not is_demo() or level < MAX_BASE_LEVEL


static func rockets_allowed() -> bool:
	return not is_demo()


## Gate a full-game feature. Returns true (and shows the end-of-demo screen) when it is blocked.
## kind: "rocket" | "base" | "auto" (the player earned the next base level).
static func block(kind: String) -> bool:
	if not is_demo():
		return false
	show_end_screen(kind)
	return true


static func show_end_screen(kind: String = "auto") -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if tree.root.get_node_or_null("DemoEndScreen") != null:
		return
	if DisplayServer.get_name() == "headless":
		# Tests and CI: record it, no UI.
		if GameState.flags.get("demo_end_seen", false):
			return
		GameState.flags["demo_end_seen"] = true
		print("[demo] end of demo (%s)" % kind)
		return
	var s: Control = load("res://steam/demo_end_screen.gd").new()
	s.name = "DemoEndScreen"
	s.set("reason", kind)
	var layer := CanvasLayer.new()
	layer.name = "DemoEndScreen"
	layer.layer = 90
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(s)
	tree.root.add_child(layer)


## Text for the base panel when the demo cap is reached.
static func base_cap_text() -> String:
	return "Base level %d is the top of the demo. The full game goes all the way to level 5, then launches rockets to the rest of Verdance." % MAX_BASE_LEVEL
