class_name PieceReveal
extends CanvasLayer
## A found piece is a moment (design spec section 13): for a few seconds Lumi wears the piece she
## just dug up, a plate at the top of the screen names it and its slot, and one line points to
## the Locker (to build it, before it stands). The moment has its own light: a flash in the
## piece's colour over Lumi that settles to a glow for as long as the plate shows, a ring of
## sparks, and a chime answered by a second, higher one. A piece salvaged from a wreck says so.
## The last piece of a set gets a second plate with
## the set's name and bonus. Listens to EventBus.piece_found and set_completed; finds that come
## together play one after another. Nothing here changes what Lumi wears for good: the look goes
## back when the moment ends.

const LAYER: int = 55
const DEFAULT_HOLD_S: float = 3.5
const GAP_S: float = 0.35
const TOP_SHARE: float = 0.09
const PLATE_W: float = 460.0
const PLATE_PAD: int = 14
const LIGHT_UP_M: float = 1.7
const LIGHT_RANGE_M: float = 6.0
const LIGHT_FLASH: float = 5.0
const LIGHT_GLOW: float = 1.4
const LIGHT_SETTLE_S: float = 0.9
const ANSWER_S: float = 0.28
const RING_SPARKS: int = 6
const RING_R_M: float = 0.9
## The ring of light on the ground and the column through Lumi (they read in full sun).
const RING_W_M: float = 0.07
const RING_UP_M: float = 0.04
const RING_FLAT: float = 0.3
const RING_FROM: float = 0.35
const RING_OPEN_S: float = 0.45
const RING_ALPHA: float = 0.9
const COLUMN_R_M: float = 0.75
const COLUMN_TOP_R_M: float = 0.35
const COLUMN_H_M: float = 3.2
const COLUMN_ALPHA: float = 0.42
const COLUMN_SETTLE: float = 0.45

var world: Node
var _queue: Array[Dictionary] = []
var _plate: FieldPlate
var _kind: Label
var _name: Label
var _line: Label
var _left: float = 0.0
var _showing: bool = false
var _dressed: Node
var _light: OmniLight3D


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE
	EventBus.piece_found.connect(_on_piece_found)
	EventBus.set_completed.connect(_on_set_completed)
	_plate = FieldPlate.new(PLATE_PAD)
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
	# A wrapped line sizes its height from its width: without a set width the plate first lays out
	# one word a line and stays that tall (seen in the M3-15 render).
	_line.custom_minimum_size.x = PLATE_W - 2.0 * PLATE_PAD
	vb.add_child(_line)
	_plate.visible = false


func _exit_tree() -> void:
	EventBus.piece_found.disconnect(_on_piece_found)
	EventBus.set_completed.disconnect(_on_set_completed)
	_undress()
	_drop_light()


## What is on the plate now: {kind, id} ({} when nothing shows). For tests and tools.
func showing() -> Dictionary:
	return _queue[0] if _showing and not _queue.is_empty() else {}


## Keeps the moment that shows now on screen for `seconds` more (render tools: a slow software
## frame must not miss it). Nothing in play calls it.
func hold_for(seconds: float) -> void:
	if _showing:
		_left = maxf(_left, seconds)


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
		var slot_name: String = tr(str(Looks.slot_def(Looks.slot_of(id)).get("name", "")))
		var target: String = Looks.target_of(id)
		if target != Looks.LUMI:  # Glim's or the crew's: say whose it is
			slot_name = "%s  ·  %s" % [tr(str(Looks.target_def(target).get("name", target))), slot_name]
		_kind.text = ((tr("Salvaged  ·  %s") if str(item.get("source", "")) == Finds.WRECK else tr("Found  ·  %s")) % slot_name).to_upper()
		_kind.add_theme_color_override("font_color", FieldPlate.CYAN)
		_name.text = tr(Looks.name_of(id)).to_upper()
		_line.text = tr("Wear it at the Locker.") if YardBuilds.built("locker") else tr("Build the Locker at the workbench to wear it.")
		Audio.play("chime", 1.25, -4.0)
		get_tree().create_timer(ANSWER_S).timeout.connect(_answer)
		_dress(id)
	_plate.visible = true
	_place_plate()
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
	_drop_light()


## The plate shrinks to its text and sits centred near the top of the screen.
func _place_plate() -> void:
	_plate.reset_size()
	var view: Vector2 = get_viewport().get_visible_rect().size
	_plate.position = Vector2((view.x - _plate.size.x) * 0.5, view.y * TOP_SHARE)


## The second note of the moment, a fifth above the first.
func _answer() -> void:
	if _showing:
		Audio.play("chime", 1.87, -8.0)
		Audio.play("sparkle", 1.1, -10.0)


## Whether the moment's light is on Lumi now (tests, tools).
func lit() -> bool:
	return _light != null and is_instance_valid(_light)


func _drop_light() -> void:
	if lit():
		_light.queue_free()
	_light = null


## A light in the piece's colour over Lumi: a flash that settles to a steady glow, and a ring of
## sparks round her.
func _light_up(player: Node3D, tint: Color) -> void:
	_drop_light()
	var up: Vector3 = player.global_basis.y
	_light = OmniLight3D.new()
	_light.name = "FoundLight"
	_light.light_color = tint.lightened(0.35)
	_light.omni_range = LIGHT_RANGE_M
	_light.shadow_enabled = false
	_light.light_energy = LIGHT_GLOW if Settings.reduced_motion else LIGHT_FLASH
	player.add_child(_light)
	_light.position = Vector3(0, LIGHT_UP_M, 0)
	if not Settings.reduced_motion:
		var tw: Tween = _light.create_tween()
		tw.tween_property(_light, "light_energy", LIGHT_GLOW, LIGHT_SETTLE_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for k: int in RING_SPARKS:
		var a: float = TAU * float(k) / float(RING_SPARKS)
		var out: Vector3 = (player.global_basis.x * cos(a) + player.global_basis.z * sin(a)) * RING_R_M
		Vfx.burst("sparkle", player.global_position + up * 0.5 + out, tint.lightened(0.2), 0.5)
	_glow_shapes(tint)


## A lamp does not show in full sun, so the moment also has shapes that glow by themselves: a
## ring of light on the ground round Lumi that opens out, and a soft column of the piece's colour
## rising through her that settles to a faint haze. They go with the light.
func _glow_shapes(tint: Color) -> void:
	var col: Color = tint.lightened(0.3)
	var ring_mat := _glow_mat(col, RING_ALPHA)
	var ring := MeshInstance3D.new()
	ring.name = "FoundRing"
	ring.mesh = ProcMesh.torus(RING_R_M - RING_W_M, RING_R_M, 40, 6)
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, RING_UP_M - LIGHT_UP_M, 0)
	ring.scale = Vector3(1.0, RING_FLAT, 1.0)
	_light.add_child(ring)
	var column_mat := _glow_mat(col, COLUMN_ALPHA)
	var column := MeshInstance3D.new()
	column.name = "FoundColumn"
	column.mesh = ProcMesh.cyl(COLUMN_TOP_R_M, COLUMN_R_M, COLUMN_H_M, 24)
	column.material_override = column_mat
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.position = Vector3(0, COLUMN_H_M * 0.5 - LIGHT_UP_M, 0)
	_light.add_child(column)
	if Settings.reduced_motion:
		column_mat.albedo_color.a = COLUMN_ALPHA * COLUMN_SETTLE
		return
	ring.scale = Vector3(RING_FROM, RING_FLAT, RING_FROM)
	var tw: Tween = ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(1.0, RING_FLAT, 1.0), RING_OPEN_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(column_mat, "albedo_color:a", COLUMN_ALPHA * COLUMN_SETTLE, LIGHT_SETTLE_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func _glow_mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = Color(col, alpha)
	return m


## Lumi wears the found piece over her look for the moment (one of hers; Glim's and the crew's
## pieces are only lit), with a burst in the piece's colour.
func _dress(piece: String) -> void:
	var player: Variant = world.get("patch") if world else null
	if not (player is Node3D):
		return
	var model: Variant = (player as Node3D).get("model")
	if not (model is PatchModel):
		return
	if Looks.target_of(piece) == Looks.LUMI:
		var style: Dictionary = LumiStyle.current()
		LumiStyle.wear_piece(style, piece)
		LumiStyle.apply(model as PatchModel, style)
		_dressed = model
	(model as PatchModel).set_happy(1.0)
	var at: Vector3 = (player as Node3D).global_position
	var tint: Color = CrewLooks.tint_of(piece, FieldPlate.CYAN)
	Vfx.burst("big_sparkle", at + (player as Node3D).global_basis.y * 0.9, tint)
	_light_up(player as Node3D, tint)


func _undress() -> void:
	if _dressed and is_instance_valid(_dressed):
		_dressed.remove_meta("lumi_style")
		LumiStyle.refresh_player(world)
	_dressed = null
