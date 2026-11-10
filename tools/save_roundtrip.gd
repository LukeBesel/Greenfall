extends Node
## Save/load round-trip check for every system that persists.
## Run: godot --headless --path . res://tools/save_roundtrip.tscn -- --fresh
## Builds a mid-game state on the globe, saves to a temp slot, loads it into a second slice and
## compares (tools/orbit_roundtrip.gd). Prints PASS/FAIL lines and exits with code 1 on any failure.

var _fails: int = 0


func _check(name_: String, a: Variant, b: Variant) -> void:
	var ok: bool = str(a) == str(b)
	print("[roundtrip] %s %s: %s -> %s" % ["PASS" if ok else "FAIL", name_, str(a), str(b)])
	if not ok:
		_fails += 1


func _ready() -> void:
	await get_tree().process_frame
	SaveManager.slot = 7
	SaveManager.enabled = true
	await OrbitRoundtrip.run(self, _check)
	SaveManager.delete_save()
	print("[roundtrip] %s (%d failures)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
