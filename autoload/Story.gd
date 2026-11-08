extends Node
## Story beats and companion lines. M1 only has Patch's own little reactions (beeps + toasts);
## WREN's dialogue system arrives in M4 and will live here.



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
	# [first] The restart checklist teaches carrying the bale; these only name the bonuses, once.
	if info.get("perfect", false):
		once("first_perfect", tr("Perfect bale: filled right to the gold line."), "hint")
	elif info.get("pure", false):
		once("first_pure", tr("Pure bale: one kind of junk is worth double."), "hint")


func _on_hex_cleaned(_hex_id: int, _pos: Vector3, _bonus: BigNum) -> void:
	once("first_hex", tr("Hex clean! Green can grow here now."), "story")  # [v3clear] plain words


func _on_upgrade_bought(_id: String, _level: int) -> void:
	once("first_upgrade", tr("Upgraded! Lumi is a little stronger now."), "hint")
