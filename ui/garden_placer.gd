class_name GardenPlacer
extends CanvasLayer
## [late] Garden Mode: place, move and remove decorations (systems/decor.gd) on a 1 m grid.
## Opens with the "garden_mode" action (H) or Pause > Garden Mode. While open Lumi stands still,
## the camera follows a cursor that the move stick / WASD slides over the ground, and a ghost of
## the selected decoration shows where it would go (green = fits, red = it doesn't, with why).
##   Place: interact (E / A)      Rotate: cube (C / X)      Previous / next: 2 / 3, D-pad left / right
##   Pick up (to move it) or remove: scoop (LMB, Space / RT)      Leave: drop (Q / B) or pause
## A picked-up decoration is refunded and selected, so placing it again moves it for free.

signal opened
signal closed

const CURSOR_SPEED: float = 6.5

var world: Node
var decor: Decor
var is_open: bool = false
var sel: int = 0
var rot: int = 0
var cell := Vector2i.ZERO
var _cursor: Node3D
var _cursor_pos := Vector3.ZERO
var _ghost: Node3D
var _ghost_type: String = ""
var _tiles: MultiMeshInstance3D
var _ok_mat: StandardMaterial3D
var _bad_mat: StandardMaterial3D
var _tile_mat: StandardMaterial3D
var _root: Control
var _title: Label
var _name: Label
var _info: Label
var _reason: Label
var _hint: Label
var _cam_target: Node3D
var _cam_dist: float = 6.2
var _cam_pitch: float = -0.3


func _ready() -> void:
	layer = 12
	_ok_mat = _ghost_material(Color(0.55, 1.0, 0.65, 0.42))
	_bad_mat = _ghost_material(Color(1.0, 0.42, 0.35, 0.42))
	_tile_mat = StandardMaterial3D.new()
	_tile_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tile_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tile_mat.albedo_color = Color(0.7, 1.0, 0.75, 0.28)
	_tile_mat.no_depth_test = false
	_build_ui()
	_root.visible = false


static func _ghost_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM, UITheme.RUST, 1, 6, 12))
	top.position = Vector2(24, 22)
	_root.add_child(top)
	_title = UITheme.label("", 15, UITheme.GREEN)
	top.add_child(_title)
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM, UITheme.RUST, 1, 6, 14))
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = -330
	bottom.offset_right = 330
	bottom.offset_top = -150
	bottom.offset_bottom = -22
	_root.add_child(bottom)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	bottom.add_child(vb)
	_name = UITheme.label("", 20, UITheme.CREAM)
	vb.add_child(_name)
	_info = UITheme.label("", 13, UITheme.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_info)
	_reason = UITheme.label("", 13, UITheme.GOLD)
	vb.add_child(_reason)
	_hint = UITheme.label("", 12, UITheme.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_hint)


func type_id() -> String:
	var ids: Array[String] = Decor.type_ids()
	return ids[wrapi(sel, 0, ids.size())]


func select(id: String) -> void:
	var i: int = Decor.type_ids().find(id)
	if i >= 0:
		sel = i
	_refresh()


func open() -> bool:
	if is_open or world == null or decor == null:
		return false
	if not Decor.unlocked():
		EventBus.toast.emit(tr("Garden Mode opens when this base reaches level 5, or once the Cradle comes home."), "info")
		Audio.play("buzz", 1.2, -10.0)
		return false
	is_open = true
	var patch: Node3D = world.patch
	var fwd: Vector3 = -patch.global_transform.basis.z
	_cursor_pos = patch.global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 3.0
	_cursor_pos.y = 0.0
	if _cursor == null:
		_cursor = Node3D.new()
		_cursor.name = "GardenCursor"
		world.add_child(_cursor)
	_cursor.global_position = _cursor_pos + Vector3(0, 0.5, 0)
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = false
	_cam_target = world.cam.target
	_cam_dist = world.cam.distance
	_cam_pitch = world.cam.pitch
	world.cam.target = _cursor
	world.cam.distance = 8.5
	world.cam.pitch = -0.62
	_root.visible = true
	_update_cell(true)
	Audio.play("click", 1.1, -6.0)
	EventBus.ui_modal_changed.emit(true)
	GameState.inc_stat("garden_mode_opened")
	opened.emit()
	return true


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_type = ""
	if _tiles:
		_tiles.visible = false
	world.cam.target = _cam_target if is_instance_valid(_cam_target) else world.patch
	world.cam.distance = _cam_dist
	world.cam.pitch = _cam_pitch
	if world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = true
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


func _process(delta: float) -> void:
	if not is_open:
		return
	var v: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v.length() > 0.05:
		var w: Vector3 = Basis(Vector3.UP, world.cam.yaw) * Vector3(v.x, 0.0, v.y)
		_cursor_pos += w.limit_length(1.0) * CURSOR_SPEED * delta
		var lim: float = float(world.field.radius + 1) * world.field.hex_size * 1.75
		_cursor_pos.x = clampf(_cursor_pos.x, -lim, lim)
		_cursor_pos.z = clampf(_cursor_pos.z, -lim, lim)
		_update_cell(false)
	_cursor.global_position = _cursor.global_position.lerp(Decor.center_of(type_id(), cell, rot) + Vector3(0, 0.5, 0), minf(delta * 10.0, 1.0))


## Moves the cursor to a cell directly (dev hooks, tests, the autoplay bot).
func move_to(c: Vector2i) -> void:
	_cursor_pos = Vector3((c.x + 0.5) * Decor.grid(), 0.0, (c.y + 0.5) * Decor.grid())
	_update_cell(true)


func _update_cell(force: bool) -> void:
	var c: Vector2i = Decor.cell_at(_cursor_pos)
	if c == cell and not force:
		return
	cell = c
	_refresh()


func _refresh() -> void:
	if not is_open:
		return
	var t: String = type_id()
	if _ghost_type != t:
		if _ghost:
			_ghost.queue_free()
		_ghost = DecorProps.build(t)
		_ghost.name = "GardenGhost"
		for sb: Node in _ghost.find_children("*", "StaticBody3D", true, false):
			sb.queue_free()
		for l: Node in _ghost.find_children("*", "Light3D", true, false):
			l.queue_free()
		world.add_child(_ghost)
		_ghost_type = t
	var why: String = decor.place_block_reason(t, cell, rot)
	var buy: String = Decor.buy_block_reason(t)
	var mat: StandardMaterial3D = _ok_mat if why == "" and buy == "" else _bad_mat
	for mi: Node in _ghost.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).material_override = mat
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var p: Vector3 = Decor.center_of(t, cell, rot)
	if world.get("layout") != null and world.layout:
		p.y = clampf(world.layout.height_at(p.x, p.z), 0.0, 0.3)
	_ghost.position = p + Vector3(0, 0.02, 0)
	_ghost.rotation.y = rot * PI * 0.5
	_draw_tiles(t, why == "")
	var d: Dictionary = Decor.def(t)
	var ids: Array[String] = Decor.type_ids()
	_name.text = "%s   %d / %d" % [tr(str(d.get("name", t))), sel % ids.size() + 1, ids.size()]
	_info.text = "%s\n%s   ·   %s" % [tr(str(d.get("desc", ""))), Decor.cost_text(t), tr("charm +%.1f") % float(d.get("charm", 0.0))]
	var under: int = decor.item_at(cell)
	if under >= 0:
		_reason.text = tr("%s here: %s to pick it up") % [tr(str(Decor.def(str(decor.items[under]["t"])).get("name", ""))), Settings.glyph("scoop")]
	else:
		_reason.text = why if why != "" else buy
	_title.text = tr("GARDEN MODE   ·   Charm %.1f   ·   +%.1f%% plant growth here") % [decor.charm(), Decor.charm_bonus(decor.charm()) * 100.0]
	_hint.text = tr("[%s] place   [%s] rotate   [%s / %s] item   [%s] pick up   [%s] done") % [Settings.glyph("interact"), Settings.glyph("cube"),
		Settings.glyph("tool_plant"), Settings.glyph("tool_water"), Settings.glyph("scoop"), Settings.glyph("drop")]


func _draw_tiles(t: String, ok: bool) -> void:
	if _tiles == null:
		_tiles = MultiMeshInstance3D.new()
		_tiles.name = "GardenTiles"
		_tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var q := PlaneMesh.new()
		q.size = Vector2(0.92, 0.92) * Decor.grid()
		mm.mesh = q
		_tiles.multimesh = mm
		_tiles.material_override = _tile_mat
		world.add_child(_tiles)
	_tiles.visible = true
	_tile_mat.albedo_color = Color(0.7, 1.0, 0.75, 0.3) if ok else Color(1.0, 0.5, 0.4, 0.3)
	var cells: Array[Vector2i] = Decor.footprint(t, cell, rot)
	_tiles.multimesh.instance_count = cells.size()
	for i: int in cells.size():
		var c: Vector2i = cells[i]
		var p := Vector3((c.x + 0.5) * Decor.grid(), 0.0, (c.y + 0.5) * Decor.grid())
		if world.get("layout") != null and world.layout:
			p.y = clampf(world.layout.height_at(p.x, p.z), 0.0, 0.3)
		_tiles.multimesh.set_instance_transform(i, Transform3D(Basis(), p + Vector3(0, 0.04, 0)))


## Place the selected decoration at the cursor. Returns true if it went down.
func try_place() -> bool:
	var t: String = type_id()
	var why: String = decor.place_block_reason(t, cell, rot)
	if why == "":
		why = Decor.buy_block_reason(t)
	if why != "":
		EventBus.toast.emit(why, "info")
		Audio.play("buzz", 1.2, -10.0)
		return false
	decor.place(t, cell, rot)
	if world.get("wren") != null and int(GameState.stats.get("decor_placed", 0)) in [1, 10, 25]:
		world.wren.say("garden_place", 1.0, true)
	_refresh()
	return true


## Pick up the decoration under the cursor (refunded) and select it, ready to put down elsewhere.
func pick_up() -> bool:
	var i: int = decor.item_at(cell)
	if i < 0:
		return false
	var it: Dictionary = decor.remove(i)
	rot = int(it.get("r", 0))
	select(str(it["t"]))
	Audio.play("whoosh", 1.3, -8.0)
	EventBus.toast.emit(tr("Picked up: %s. Put it down somewhere else, or leave it in storage.") % tr(str(Decor.def(str(it["t"])).get("name", ""))), "hint")
	_refresh()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		if event.is_action_pressed("garden_mode") and world and not bool(world.get("launching")) \
				and not (world.has_method("any_modal_open") and world.any_modal_open()):
			if open():
				get_viewport().set_input_as_handled()
		return
	var used: bool = true
	if event.is_action_pressed("interact"):
		try_place()
	elif event.is_action_pressed("cube"):
		rot = (rot + 1) % 4
		Audio.play("click", 1.3, -8.0)
		_refresh()
	elif event.is_action_pressed("tool_water"):
		sel = wrapi(sel + 1, 0, Decor.type_ids().size())
		Audio.play("click", 1.0, -8.0)
		_refresh()
	elif event.is_action_pressed("tool_plant"):
		sel = wrapi(sel - 1, 0, Decor.type_ids().size())
		Audio.play("click", 1.0, -8.0)
		_refresh()
	elif event.is_action_pressed("scoop"):
		pick_up()
	elif event.is_action_pressed("drop") or event.is_action_pressed("pause") or event.is_action_pressed("garden_mode") or event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("open_upgrades") or event.is_action_pressed("open_command") or event.is_action_pressed("open_globe") \
			or event.is_action_pressed("open_codex") or event.is_action_pressed("photo_mode") or event.is_action_pressed("tool_scoop"):
		pass  # swallowed while placing
	else:
		used = false
	if used:
		get_viewport().set_input_as_handled()
