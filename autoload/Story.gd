extends Node
## Story beats and companion lines. M1 only has Patch's own little reactions (beeps + toasts);
## WREN's dialogue system arrives in M4 and will live here.

var _shown: Dictionary = {}


func _ready() -> void:
	EventBus.cube_made.connect(_on_cube_made)
	EventBus.hex_cleaned.connect(_on_hex_cleaned)
	EventBus.upgrade_bought.connect(_on_upgrade_bought)


func once(id: String, text: String, kind: String = "story") -> void:
	if GameState.flags.get("beat_" + id, false):
		return
	GameState.flags["beat_" + id] = true
	EventBus.toast.emit(text, kind)


func _on_cube_made(info: Dictionary) -> void:
	once("first_cube", "Your first cube! Carry it to the Depot pad.", "hint")
	if info.get("perfect", false):
		once("first_perfect", "PERFECT CUBE! Filled right to the line.", "hint")
	if info.get("pure", false):
		once("first_pure", "A Pure Cube: one kind of junk is worth double.", "hint")


func _on_hex_cleaned(_hex_id: int, _pos: Vector3, _bonus: BigNum) -> void:
	once("first_hex", "A whole hex is clean! The ground remembers its colors.", "story")


func _on_upgrade_bought(_id: String, _level: int) -> void:
	once("first_upgrade", "Upgraded! Lumi feels a little less creaky.", "hint")
