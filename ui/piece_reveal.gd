class_name PieceReveal
extends CanvasLayer
## A found piece is a moment (design spec section 13): for a few seconds Lumi wears the piece she
## just dug up, a plate at the top of the screen names it and its slot, and one line points to
## the Locker (to build it, before it stands). The last piece of a set gets a second plate with
## the set's name and bonus. Listens to EventBus.piece_found and set_completed; finds that come
## together play one after another. Nothing here changes what Lumi wears for good: the look goes
## back when the moment ends.

const LAYER: int = 55
const DEFAULT_HOLD_S: float = 3.5
const GAP_S: float = 0.35
const TOP_SHARE: float = 0.09
const PLATE_W: float = 460.0

var world: Node
var _queue: Array[Dictionary] = []
var _plate: FieldPlate
var _kind: Label
var _name: Label
var _line: Label
var _left: float = 0.0
var _showing: bool = false
var _dressed: Node


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.piece_found.connect(_on_piece_found)
	EventBus.set_completed.connect(_on_set_completed)
	_plate = FieldPlate.new(14)
	_plate.custom_minimum_size = Vector2(PLATE_W, 0)
	_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.theme = UITheme.get_theme()
	add_child(_plate)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(vb)
	_kind = FieldPlate.stencil("", FieldPlate.CYAN)
	vb.add_child(_kind)
	_name = FieldPlate.stencil("", FieldPlate.INK, 28)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vb.add_child(_name)
	vb.add_child(FieldPlate.rule())
	_line = FieldPlate.sentence("", FieldPlate.INK_DIM)
	vb.add_child(_line)
	_plate.visible = false


func _exit_tree() -> void:
	EventBus.piece_found.disconnect(_on_piece_found)
	EventBus.set_completed.disconnect(_on_set_completed)
	_undress()


## What is on the plate now: {kind, id} ({} when nothing shows). For tests and tools.
func showing() -> Dictionary:
	return _queue[0] if _showing and not _queue.is_empty() else {}


func queued() -> int:
	return _queue.size()


func _on_piece_found(piece: String, source: String) -> void:
	_queue.append({"kind": "piece", "id": piece, "source": source})


func _on_set_completed(design: String) -> void:
	_queue.append({"kind": "set", "id": design})


func _process(delta: float) -> void:
	if _showing:
		_left -= delta
		if _left <= 0.0:
			_end()
	elif not _queue.is_empty():
		_left -= delta
		if _left <= 0.0:
			_begin(_queue[0])


func _hold_s() -> float:
	var s: float = Finds.reveal_s(Planets.current())
	return s if s > 0.0 else DEFAULT_HOLD_S


func _begin(item: Dictionary) -> void:
	_showing = true
	_left = _hold_s()
	var id: String = str(item["id"])
	if item["kind"] == "set":
		_kind.text = tr("Set complete").to_upper()
		_kind.add_theme_color_override("font_color", FieldPlate.GREEN)
		_name.text = tr(Designs.name_of(id)).to_upper()
		_line.text = tr("Wear every piece at the Locker: %s.") % Designs.buff_text(id)
		Audio.play("fanfare", 1.0, -6.0)
	else:
		_kind.text = (tr("Found  ·  %s") % tr(str(Looks.slot_def(Looks.slot_of(id)).get("name", "")))).to_upper()
		_kind.add_theme_color_override("font_color", FieldPlate.CYAN)
		_name.text = tr(Looks.name_of(id)).to_upper()
		_line.text = tr("Wear it at the Locker.") if YardBuilds.built("locker") else tr("Build the Locker at the workbench to wear it.")
		Audio.play("chime", 1.25, -4.0)
		_dress(id)
	_plate.visible = true
	_plate.position.y = get_viewport().get_visible_rect().size.y * TOP_SHARE
	if not Settings.reduced_motion:
		_plate.modulate.a = 0.0
		var tw: Tween = _plate.create_tween()
		tw.tween_property(_plate, "modulate:a", 1.0, FieldPlate.EASE_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _end() -> void:
	_showing = false
	_left = GAP_S
	_plate.visible = false
	_queue.pop_front()
	_undress()


## Lumi wears the found piece over her look for the moment, with a burst in the piece's colour.
func _dress(piece: String) -> void:
	var player: Variant = world.get("patch") if world else null
	if not (player is Node3D):
		return
	var model: Variant = (player as Node3D).get("model")
	if not (model is PatchModel):
		return
	var style: Dictionary = LumiStyle.current()
	LumiStyle.wear_piece(style, piece)
	LumiStyle.apply(model as PatchModel, style)
	_dressed = model
	(model as PatchModel).set_happy(1.0)
	var at: Vector3 = (player as Node3D).global_position
	Vfx.burst("big_sparkle", at + (player as Node3D).global_basis.y * 0.9, LumiStyle.piece_tint(piece, FieldPlate.CYAN))


func _undress() -> void:
	if _dressed and is_instance_valid(_dressed):
		_dressed.remove_meta("lumi_style")
		LumiStyle.refresh_player(world)
	_dressed = null
