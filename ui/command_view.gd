class_name CommandView
extends CanvasLayer
## Command mode: a tactical, RTS-style view of the real district. The camera lifts into an
## angled overhead shot (cool, desaturated grade so the overlay reads); hexes, zones, robots and
## map markers are drawn as a crisp 2D overlay projected from the ground plane:
##  - junk hexes get a hatched heat tint, growing hexes a soft green wash (clean ones stay clear);
##  - thin glowing grid lines only around the cursor and the selected zone, fading with distance;
##  - the selected crew's / robot's zone: soft fill, bright animated border and corner brackets;
##  - robots: role-coloured badges with heading chevron and a status pip;
##  - labelled markers for the base, Patch and anything added with set_map_marker() (outposts).
## Pick a crew (cleaners / haulers / planters / waterers) or one robot in the panel, then mark
## hexes on the ground to give it a work zone. Modes: Priority (zone first, then roam), Stay
## (zone only), Follow me (hexes around Patch) or Recall (park at the base).

signal closed

const ROLE_COLORS: Dictionary = {
	"clean": Color(1.0, 0.7, 0.3),
	"haul": Color(0.55, 0.75, 1.0),
	"plant": Color(0.55, 0.92, 0.45),
	"water": Color(0.4, 0.85, 0.95),
	"skim": Color(0.45, 1.0, 0.75),
}
const ROLE_NAMES: Dictionary = {"clean": "Cleaners", "haul": "Haulers", "plant": "Planters", "water": "Waterers", "skim": "Skimmers"}  # l10n
const MODE_NAMES: Dictionary = {"priority": "Priority", "stay": "Stay", "follow": "Follow me", "recall": "Recall"}  # l10n
# l10n:begin
const MODE_HELP: Dictionary = {
	"priority": "Works the marked hexes first, then the rest of the district.",
	"stay": "Works only the marked hexes, and waits there when they are done.",
	"follow": "Works the hexes around you, wherever you go.",
	"recall": "Comes back and parks at the base.",
}
# l10n:end

# Tactical palette for the overlay.
const GRID_COL := Color(0.62, 0.86, 1.0)
const JUNK_COL := Color(1.0, 0.56, 0.22)
const JUNK_HOT := Color(1.0, 0.3, 0.2)
const CLEANING_COL := Color(0.4, 0.7, 1.0)
const GROW_COL := Color(0.45, 0.95, 0.5)
const PANEL_BG := Color(0.045, 0.05, 0.06, 0.86)
const ROW_BG := Color(1, 1, 1, 0.035)

# Camera.
const PITCH_DEG: float = 54.0
const ZOOM_MIN: float = 30.0
const ZOOM_MAX: float = 240.0
const ZOOM_DEFAULT: float = 100.0

var world: Node
var is_open: bool = false

var _root: Control
var _input_area: Control
var _map: Control  # 2D overlay canvas (under the panels)
var _list: VBoxContainer
var _title: Label
var _title_icon: RoleIcon
var _title_chip: PanelContainer
var _mode_row: HBoxContainer
var _mode_help: Label
var _info_name: Label
var _info_count: Label
var _info_bar: ProgressBar
var _info_bots: Label
var _sel_key: String = "clean"
var _sel_bot: bool = false
var _paint: int = 0  # 0 none, 1 add, -1 remove
var _pan_drag: bool = false
var _hover_hex: int = -1
var _hover_world := Vector3.INF
var _list_t: float = 0.0
var _tank_btn: Button
var _overlay_t: float = 0.0
var _tip: PanelContainer
var _tip_title: Label
var _tip_body: Label
var _tip_bar: ProgressBar

# 3D camera
var _cam: Camera3D
var _prev_cam: Camera3D
var _focus := Vector3.ZERO
var _look := Vector3.ZERO
var _height: float = ZOOM_DEFAULT  # camera distance to the focus point (zoom)
var _cam_pos := Vector3.ZERO

# Overlay caches (world space). Rebuilt on open / zone change / every half second.
var _corners: Array[PackedVector3Array] = []  # per hex: 6 ground corners
var _fill_cols := PackedColorArray()
var _zone_set: Dictionary = {}
var _zone_edges: Array = []  # [a: Vector3, b: Vector3] boundary edges of the selected zone
var _other_edges: Array = []  # [a, b, col] boundary edges of other crews' zones
var _hatch: ImageTexture
var _proj: Array[PackedVector2Array] = []
var _proj_ok := PackedByteArray()

## Extra labelled markers (outposts, landmarks...): id -> {pos: Vector3, label: String, color: Color, kind: String}.
var map_markers: Dictionary = {}

# Controller: D-pad / A drive the side panel through focus; moving the left stick switches to
# the map, where the hex under the screen-centre reticle is painted with A and erased with X.
const PAD_KEYS: String = "D-pad  panel      Left stick  move      A  mark      X  unmark      LB / RB  zoom      B  back"
const MOUSE_KEYS: String = "Left drag  mark      Right drag  unmark      WASD / middle drag  move      Wheel  zoom      B  back"
## [deck] The live prompt line (glyphs follow the device and pad family).
const KEYS_TEMPLATE: String = "[p]{@dpad}  panel      {@move}  move      {pad:#0}  mark      {pad:#2}  unmark      {pad:zoom_out}{pad:zoom_in}  zoom      {pad:ui_cancel}  back[/p][k]Left drag  mark      Right drag  unmark      {@move} / middle drag  move      Wheel  zoom      {kbd:open_command}  back[/k]"  # l10n
var _using_pad: bool = false
var _pad_paint: int = 0  # 1 while A is held on the map, -1 while X is held
var _reticle_hex: int = -1
var _reticle: Control
var _keys: PromptLabel
var _last_focus_id: Array = []  # [meta key, value] of the panel control that had focus


## Small vector glyph per crew role (also drawn on the map badges).
class RoleIcon extends Control:
	var role: String = "clean"
	var col: Color = Color.WHITE

	func _init(p_role: String = "clean", p_col: Color = Color.WHITE, px: float = 18.0) -> void:
		role = p_role
		col = p_col
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_role(p_role: String, p_col: Color) -> void:
		role = p_role
		col = p_col
		queue_redraw()

	func _draw() -> void:
		CommandView.draw_role_glyph(self, role, size * 0.5, minf(size.x, size.y) * 0.5, col)


static func draw_role_glyph(ci: CanvasItem, role: String, c: Vector2, r: float, col: Color) -> void:
	var w: float = maxf(1.5, r * 0.2)
	match role:
		"clean":  # scoop bucket with a handle
			var pts := PackedVector2Array([c + Vector2(-0.8, -0.2) * r, c + Vector2(0.8, -0.2) * r, c + Vector2(0.5, 0.75) * r, c + Vector2(-0.5, 0.75) * r])
			ci.draw_colored_polygon(pts, col)
			ci.draw_line(c + Vector2(0.0, -0.2) * r, c + Vector2(0.55, -0.9) * r, col, w, true)
		"haul":  # crate
			var rc := Rect2(c - Vector2(0.75, 0.6) * r, Vector2(1.5, 1.2) * r)
			ci.draw_rect(rc, col, false, w, true)
			ci.draw_line(rc.position + Vector2(0, rc.size.y * 0.35), rc.position + Vector2(rc.size.x, rc.size.y * 0.35), col, w, true)
			ci.draw_rect(Rect2(c + Vector2(-0.2, -0.6) * r, Vector2(0.4, 0.5) * r), col)
		"plant":  # leaf with a stem
			var leaf := PackedVector2Array()
			for i: int in 9:
				var t: float = float(i) / 8.0
				leaf.append(c + Vector2(-0.7 + 1.4 * t, 0.6 - 1.4 * t) * r + Vector2(-1, -1).normalized() * sin(t * PI) * r * 0.45)
			for i: int in range(7, 0, -1):
				var t2: float = float(i) / 8.0
				leaf.append(c + Vector2(-0.7 + 1.4 * t2, 0.6 - 1.4 * t2) * r + Vector2(1, 1).normalized() * sin(t2 * PI) * r * 0.45)
			ci.draw_colored_polygon(leaf, col)
			ci.draw_line(c + Vector2(-0.7, 0.6) * r, c + Vector2(-0.95, 0.9) * r, col, w, true)
		"water":  # droplet
			ci.draw_circle(c + Vector2(0, 0.25) * r, r * 0.6, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.95) * r, c + Vector2(0.55, 0.0) * r, c + Vector2(-0.55, 0.0) * r]), col)
		_:  # waves (skimmers)
			for k: int in 2:
				var pl := PackedVector2Array()
				for i: int in 9:
					var t3: float = float(i) / 8.0
					pl.append(c + Vector2(-0.85 + 1.7 * t3, -0.25 + 0.55 * float(k) + sin(t3 * TAU) * 0.18) * r)
				ci.draw_polyline(pl, col, w, true)


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	# Whole screen catches map input; the panels sit on top of it.
	_input_area = Control.new()
	_input_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_input_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_area.gui_input.connect(_map_input)
	_root.add_child(_input_area)
	# Slight edge vignette: frames the tactical view without darkening the centre.
	var vig := TextureRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.08, 1.08)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.0, 0.02, 0.05, 0.08), Color(0.0, 0.02, 0.05, 0.62)])
	g.gradient = grad
	vig.texture = g
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(vig)
	# 2D tactical overlay.
	_map = Control.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_map.draw.connect(_draw_map)
	_root.add_child(_map)
	_hatch = _make_hatch()

	var side := PanelContainer.new()
	var side_sb := UITheme.box(PANEL_BG, Color(1, 1, 1, 0.09), 1, 10, 16)
	side_sb.border_width_top = 2
	side_sb.border_color = Color(1, 1, 1, 0.09)
	side_sb.shadow_color = Color(0, 0, 0, 0.35)
	side_sb.shadow_size = 18
	side.add_theme_stylebox_override("panel", side_sb)
	side.position = Vector2(20, 20)
	side.custom_minimum_size = Vector2(330, 0)
	_root.add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 9)
	side.add_child(sv)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	sv.add_child(head)
	var accent := ColorRect.new()
	accent.color = UITheme.GOLD
	accent.custom_minimum_size = Vector2(3, 12)
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(accent)
	var cap := UITheme.label(tr("COMMAND"), 12, UITheme.MUTED)
	cap.add_theme_constant_override("shadow_outline_size", 0)
	head.add_child(cap)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 10)
	sv.add_child(trow)
	_title_icon = RoleIcon.new("clean", ROLE_COLORS["clean"], 26.0)
	trow.add_child(_title_icon)
	_title = UITheme.label("", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	trow.add_child(_title)
	_title_chip = _chip("", UITheme.CREAM, 13)
	_title_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(_title_chip)
	# Modes: a segmented control.
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 3)
	sv.add_child(_mode_row)
	for m: String in Fleet.MODES:
		var b := Button.new()
		b.text = tr(MODE_NAMES[m])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_mode.bind(m))
		b.set_meta("mode", m)
		_style_button(b, UITheme.GOLD, false)
		_mode_row.add_child(b)
	_mode_help = UITheme.label("", 13, UITheme.MUTED)
	_mode_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_help.custom_minimum_size = Vector2(298, 36)
	sv.add_child(_mode_help)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	sv.add_child(row)
	var here := Button.new()
	here.text = tr("Mark around me")
	here.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	here.add_theme_font_size_override("font_size", 14)
	here.pressed.connect(func() -> void:
		for h: int in world.field.hexes_near(world.patch.global_position, 1):
			if world.field.hex_hub[h] == 0 and world.field.is_water(h) == (_sel_key == "skim" and not _sel_bot):
				world.fleet.toggle_zone_hex(_sel_key, _sel_bot, h, true)
		Audio.play("blip", 1.0, -8.0)
		_refresh()
		_rebuild_zone())
	_style_button(here, UITheme.CREAM, false)
	row.add_child(here)
	var clear := Button.new()
	clear.text = tr("Clear")
	clear.add_theme_font_size_override("font_size", 14)
	clear.pressed.connect(func() -> void:
		world.fleet.clear_order(_sel_key, _sel_bot)
		Audio.play("click", 0.9, -8.0)
		_refresh()
		_rebuild_zone())
	_style_button(clear, UITheme.CREAM, false)
	row.add_child(clear)
	# Water Tank: a refill station for waterers, built where Patch stands.
	_tank_btn = Button.new()
	_tank_btn.add_theme_font_size_override("font_size", 13)
	_tank_btn.pressed.connect(func() -> void:
		var net: WaterNet = world.fleet.water_net
		if net and net.place_tank(world.patch.global_position):
			Audio.play("buy", 1.0, -4.0)
		else:
			Audio.play("buzz", 1.2, -8.0)
		_refresh_build())
	_style_button(_tank_btn, ROLE_COLORS["water"], false)
	sv.add_child(_tank_btn)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.08)
	sep.custom_minimum_size = Vector2(0, 1)
	sv.add_child(sep)
	var crew_cap := UITheme.label(tr("CREWS"), 11, UITheme.MUTED)
	crew_cap.add_theme_constant_override("shadow_outline_size", 0)
	sv.add_child(crew_cap)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)

	# Top-right district readout: name, progress bar, legend.
	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", UITheme.box(PANEL_BG, Color(1, 1, 1, 0.09), 1, 10, 14))
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.offset_right = -20
	info_panel.offset_top = 20
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(info_panel)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 6)
	iv.custom_minimum_size = Vector2(300, 0)
	info_panel.add_child(iv)
	var ih := HBoxContainer.new()
	iv.add_child(ih)
	_info_name = UITheme.label("", 17)
	_info_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ih.add_child(_info_name)
	_info_bots = UITheme.label("", 13, UITheme.MUTED)
	ih.add_child(_info_bots)
	_info_bar = ProgressBar.new()
	_info_bar.show_percentage = false
	_info_bar.custom_minimum_size = Vector2(0, 5)
	_info_bar.add_theme_stylebox_override("fill", UITheme.box(GROW_COL, Color(0, 0, 0, 0), 0, 2, 0))
	_info_bar.add_theme_stylebox_override("background", UITheme.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 2, 0))
	iv.add_child(_info_bar)
	_info_count = UITheme.label("", 13, UITheme.MUTED)
	iv.add_child(_info_count)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	iv.add_child(legend)
	for pair: Array in [["junk", "junk"], ["cleaning", "cleaning"], ["clean", "clean"], ["growing", "growing"]]:
		var lh := HBoxContainer.new()
		lh.add_theme_constant_override("separation", 5)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(9, 9)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.color = _legend_color(pair[0])
		lh.add_child(sw)
		lh.add_child(UITheme.label(pair[1], 12, UITheme.MUTED))
		legend.add_child(lh)

	var keys_panel := PanelContainer.new()
	keys_panel.add_theme_stylebox_override("panel", UITheme.box(PANEL_BG, Color(1, 1, 1, 0.07), 1, 14, 9))
	keys_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	keys_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	keys_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys_panel.offset_bottom = -14
	keys_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(keys_panel)
	_keys = PromptLabel.new(tr(KEYS_TEMPLATE), 13)
	keys_panel.add_child(_keys)
	# Hover tooltip.
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.045, 0.055, 0.92), Color(1, 1, 1, 0.12), 1, 6, 9))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_root.add_child(_tip)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	tv.custom_minimum_size = Vector2(170, 0)
	_tip.add_child(tv)
	_tip_title = UITheme.label("", 13, UITheme.CREAM)
	tv.add_child(_tip_title)
	_tip_bar = ProgressBar.new()
	_tip_bar.show_percentage = false
	_tip_bar.custom_minimum_size = Vector2(0, 4)
	_tip_bar.add_theme_stylebox_override("fill", UITheme.box(JUNK_COL, Color(0, 0, 0, 0), 0, 2, 0))
	_tip_bar.add_theme_stylebox_override("background", UITheme.box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 0, 2, 0))
	tv.add_child(_tip_bar)
	_tip_body = UITheme.label("", 12, UITheme.MUTED)
	tv.add_child(_tip_body)
	# Screen-centre reticle for controller painting (hidden while using the mouse).
	_reticle = Control.new()
	_reticle.set_anchors_preset(Control.PRESET_CENTER)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.visible = false
	_reticle.draw.connect(func() -> void:
		var col: Color = UITheme.GOLD
		for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_reticle.draw_line(d * 6.0, d * 16.0, col, 2.0, true)
		_reticle.draw_arc(Vector2.ZERO, 3.0, 0.0, TAU, 12, col, 2.0, true))
	_root.add_child(_reticle)


static func _make_hatch() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y: int in 32:
		for x: int in 32:
			var d: int = (x + y) % 16
			var a: float = 0.3 + 0.7 * clampf(1.0 - absf(float(d) - 2.0) / 2.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _legend_color(kind: String) -> Color:
	if UITheme.colorblind():
		return UITheme.progress_color(kind)
	match kind:
		"junk":
			return JUNK_COL
		"cleaning":
			return CLEANING_COL
		"growing":
			return GROW_COL
	return Color(0.85, 0.9, 0.95, 0.6)


## Rounded status chip: [PanelContainer > Label].
func _chip(text: String, col: Color, fs: int = 11) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := UITheme.box(Color(col.r, col.g, col.b, 0.14), Color(col.r, col.g, col.b, 0.35), 1, 9, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.label(text, fs, col)
	l.add_theme_constant_override("shadow_outline_size", 0)
	pc.add_child(l)
	return pc


func _set_chip(pc: PanelContainer, text: String, col: Color) -> void:
	var l: Label = pc.get_child(0)
	l.text = text
	l.add_theme_color_override("font_color", col)
	var sb: StyleBoxFlat = pc.get_theme_stylebox("panel")
	sb.bg_color = Color(col.r, col.g, col.b, 0.14)
	sb.border_color = Color(col.r, col.g, col.b, 0.35)


## Visible amber focus ring for controller / keyboard navigation.
static func focus_box() -> StyleBoxFlat:
	var sb := UITheme.box(Color(UITheme.GOLD, 0.12), UITheme.GOLD, 2, 4, 6)
	sb.content_margin_left = 10
	return sb


## Slate button with a hairline border; pressed lights up in the given colour.
## Crew buttons get a coloured stripe on the left.
func _style_button(b: Button, col: Color, stripe: bool) -> void:
	var mk := func(bg: Color, border: Color) -> StyleBoxFlat:
		var sb := UITheme.box(bg, border, 1, 5, 6)
		if stripe:
			sb.border_width_left = 3
		sb.content_margin_left = 10
		return sb
	var edge: Color = col if stripe else Color(1, 1, 1, 0.08)
	b.add_theme_stylebox_override("normal", mk.call(Color(0.12, 0.13, 0.145, 0.85), edge))
	b.add_theme_stylebox_override("hover", mk.call(Color(0.17, 0.18, 0.2, 0.92), col if stripe else Color(1, 1, 1, 0.25)))
	var pressed_bg := Color(col.r * 0.26, col.g * 0.26, col.b * 0.26, 0.95)
	b.add_theme_stylebox_override("pressed", mk.call(pressed_bg, col))
	b.add_theme_stylebox_override("hover_pressed", mk.call(pressed_bg.lightened(0.05), col))
	b.add_theme_stylebox_override("disabled", mk.call(Color(0.08, 0.085, 0.09, 0.6), Color(1, 1, 1, 0.04)))
	b.add_theme_stylebox_override("focus", focus_box())
	b.add_theme_color_override("font_color", UITheme.CREAM)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)


# --- Open / close ------------------------------------------------------------------------

func open_view() -> void:
	if world == null:
		return
	if _cam == null:
		_build_overlay()
	is_open = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	Audio.play("whoosh", 1.2, -10.0)
	if world.get("hud") != null:
		world.hud.visible = false
	# Lift from the play camera into the tactical view.
	_prev_cam = get_viewport().get_camera_3d()
	_focus = world.patch.global_position
	_focus.y = 0.0
	_cam_pos = _prev_cam.global_position if _prev_cam else _focus + Vector3(0, 10, 10)
	_look = _focus
	_cam.global_position = _cam_pos
	_cam.current = true
	if _sel_bot and world.fleet.find_robot(_sel_key) == null:
		_sel_key = "clean"
		_sel_bot = false
	_rebuild_overlay()
	_refresh()
	_set_pad(_using_pad)
	if _using_pad:
		_focus_panel.call_deferred()


func close_view() -> void:
	if not is_open:
		return
	is_open = false
	_paint = 0
	_pad_paint = 0
	var fo: Control = get_viewport().gui_get_focus_owner()
	if fo and _root.is_ancestor_of(fo):
		fo.release_focus()
	_root.visible = false
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.current = true
	if world.get("hud") != null:
		world.hud.visible = true
	Audio.play("whoosh", 0.9, -12.0)
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


func _select(key: String, is_bot: bool) -> void:
	_sel_key = key
	_sel_bot = is_bot
	Audio.play("click", 1.1, -10.0)
	_refresh()
	_rebuild_zone()
	if is_bot:
		var r: Robot = world.fleet.find_robot(key)
		if r:
			_focus = Vector3(r.global_position.x, 0, r.global_position.z)


func _on_mode(m: String) -> void:
	world.fleet.set_mode(_sel_key, _sel_bot, m)
	Audio.play("servo", 1.4, -10.0)
	_refresh()
	_rebuild_zone()


func _sel_role() -> String:
	if _sel_bot:
		var r: Robot = world.fleet.find_robot(_sel_key)
		return r.role() if r else "clean"
	return _sel_key


func _sel_color() -> Color:
	if _sel_bot:
		var r: Robot = world.fleet.find_robot(_sel_key)
		return ROLE_COLORS.get(r.role(), Color.WHITE) if r else Color.WHITE
	return ROLE_COLORS.get(_sel_key, Color.WHITE)


func _sel_order() -> Dictionary:
	var f: Fleet = world.fleet
	if f.has_order(_sel_key, _sel_bot):
		return f.order(_sel_key, _sel_bot)
	return {}


func _sel_zone() -> Array:
	var od: Dictionary = _sel_order()
	if od.is_empty():
		return []
	if str(od.get("mode", "")) == "follow":
		return world.field.hexes_near(world.patch.global_position, 1)
	return od.get("zone", [])


# --- Panel ---------------------------------------------------------------------------------

func _refresh() -> void:
	var f: Fleet = world.fleet
	var od: Dictionary = _sel_order()
	var mode: String = str(od.get("mode", "")) if not od.is_empty() else ""
	if _sel_bot:
		var r: Robot = f.find_robot(_sel_key)
		_title.text = _sel_key
		_set_chip(_title_chip, Economy.tier_name(r.tier) if r else "", _sel_color())
		if od.is_empty() and r:
			_mode_help.text = tr("Following the %s orders. Mark hexes or pick a mode to give it its own.") % tr(ROLE_NAMES.get(r.role(), "crew")).to_lower()
	else:
		_title.text = tr(ROLE_NAMES[_sel_key])
		_set_chip(_title_chip, "%d / %d" % [f.robots_with_role(_sel_key).size(), f.crew_cap()], _sel_color())
	_title.add_theme_color_override("font_color", _sel_color())
	_title_icon.set_role(_sel_role(), _sel_color())
	if mode != "":
		_mode_help.text = tr(str(MODE_HELP.get(mode, "")))
	elif not _sel_bot:
		_mode_help.text = tr("No orders yet: roaming the district. Drag on the ground to mark where to work.")
	for b: Node in _mode_row.get_children():
		(b as Button).button_pressed = str(b.get_meta("mode")) == mode
	_rebuild_list()


func _rebuild_list() -> void:
	# The list buttons are rebuilt on every refresh: remember which one had focus.
	var fo: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var refocus: bool = fo != null and _list.is_ancestor_of(fo)
	if refocus:
		_last_focus_id = _focus_id(fo)
	for c: Node in _list.get_children():
		c.queue_free()
	_fill_list()
	if refocus:
		_restore_focus()


## Content row laid over a Button (the Button keeps focus, toggle and metas).
func _button_content(b: Button, left: float) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = left
	hb.offset_right = -8
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	return hb


func _mode_chip_color(label: String, role_col: Color) -> Color:
	match label:
		"roaming":
			return UITheme.MUTED
		"recall":
			return Color(0.75, 0.8, 0.9)
	return role_col


func _fill_list() -> void:
	var f: Fleet = world.fleet
	if f.robots().is_empty():
		var l := UITheme.label(tr("No robots yet. Build one at the workbench."), 14, UITheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		return
	for role_id: String in Fleet.ROLES:
		var bots: Array[Robot] = f.robots_with_role(role_id)
		if bots.is_empty() and Fleet.types_for_role(role_id).is_empty():
			continue
		var col: Color = ROLE_COLORS[role_id]
		var gb := Button.new()
		gb.custom_minimum_size = Vector2(0, 38)
		_style_button(gb, col, true)
		gb.toggle_mode = true
		gb.button_pressed = not _sel_bot and _sel_key == role_id
		gb.tooltip_text = "%s  %d/%d  %s" % [tr(ROLE_NAMES[role_id]), bots.size(), f.crew_cap(), _mode_label(role_id)]
		gb.pressed.connect(_select.bind(role_id, false))
		gb.set_meta("role", role_id)
		_list.add_child(gb)
		var hb: HBoxContainer = _button_content(gb, 12)
		hb.add_child(RoleIcon.new(role_id, col, 18.0))
		var nl := UITheme.label(tr(ROLE_NAMES[role_id]), 15, UITheme.CREAM)
		nl.add_theme_constant_override("shadow_outline_size", 0)
		hb.add_child(nl)
		var cl := UITheme.label("%d/%d" % [bots.size(), f.crew_cap()], 13, UITheme.MUTED)
		cl.add_theme_constant_override("shadow_outline_size", 0)
		hb.add_child(cl)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(sp)
		var ml: String = _mode_label(role_id)
		var chip: PanelContainer = _chip(ml.to_upper(), _mode_chip_color(ml, col), 10)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(chip)
		_add_build_row(role_id)
		for r: Robot in bots:
			var rb := Button.new()
			rb.flat = false
			rb.toggle_mode = true
			rb.custom_minimum_size = Vector2(0, 26)
			rb.button_pressed = _sel_bot and _sel_key == r.robot_name
			rb.set_meta("bot", r.robot_name)
			rb.tooltip_text = _bot_line(r).strip_edges()
			var empty := UITheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, 4)
			rb.add_theme_stylebox_override("normal", empty)
			rb.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 4, 4))
			var psb := UITheme.box(Color(col.r, col.g, col.b, 0.12), col, 0, 4, 4)
			psb.border_width_left = 2
			rb.add_theme_stylebox_override("pressed", psb)
			rb.add_theme_stylebox_override("hover_pressed", psb)
			rb.add_theme_stylebox_override("focus", focus_box())
			rb.pressed.connect(_select.bind(r.robot_name, true))
			_list.add_child(rb)
			var bh: HBoxContainer = _button_content(rb, 22)
			bh.add_theme_constant_override("separation", 7)
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(6, 6)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bh.add_child(dot)
			var nm := UITheme.label(r.robot_name, 13, col if rb.button_pressed else UITheme.CREAM)
			nm.add_theme_constant_override("shadow_outline_size", 0)
			bh.add_child(nm)
			var tc: PanelContainer = _chip(Economy.tier_name(r.tier), UITheme.MUTED, 10)
			tc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bh.add_child(tc)
			var st := UITheme.label("", 12, UITheme.MUTED)
			st.add_theme_constant_override("shadow_outline_size", 0)
			st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			st.clip_text = true
			st.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			bh.add_child(st)
			rb.set_meta("dot", dot)
			rb.set_meta("st", st)
			_update_bot_row(rb, r)


func _update_bot_row(rb: Button, r: Robot) -> void:
	var st: Label = rb.get_meta("st") if rb.has_meta("st") else null
	var dot: ColorRect = rb.get_meta("dot") if rb.has_meta("dot") else null
	var s: String = r.status_text()
	if st:
		st.text = r.status_label()  # [l10n] translated; s (English) drives the pip colour
	if dot:
		dot.color = _status_color(s)
	rb.tooltip_text = _bot_line(r).strip_edges()


## Build + Upgrade fleet buttons under a crew (they work at the workbench only).
func _add_build_row(role_id: String) -> void:
	for t: String in Fleet.types_for_role(role_id):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.set_meta("build_type", t)
		b.pressed.connect(func() -> void:
			var r: Robot = world.fleet.build(t, world.upgrades.build_at.call() if world.get("upgrades") else world.depot.global_position + Vector3(0, 0.2, 3))
			Audio.play("buy" if r else "buzz", 1.0, -4.0 if r else -8.0)
			_refresh())
		_style_button(b, ROLE_COLORS[role_id], false)
		row.add_child(b)
		var u := Button.new()
		u.add_theme_font_size_override("font_size", 12)
		u.set_meta("tier_type", t)
		u.pressed.connect(func() -> void:
			Audio.play("buy" if world.fleet.upgrade_tier(t) else "buzz", 0.9, -4.0)
			_refresh())
		_style_button(u, UITheme.GOLD, false)
		row.add_child(u)
		_list.add_child(row)
		var info := UITheme.label("", 11, Color(UITheme.MUTED, 0.85))
		info.add_theme_constant_override("shadow_outline_size", 0)
		info.set_meta("build_info", t)
		_list.add_child(info)
	_refresh_build()


## Live state of the Build / Upgrade buttons and the tank button.
func _refresh_build() -> void:
	var f: Fleet = world.fleet
	var at_bench: bool = world.near_bench() if world.has_method("near_bench") else false
	for c: Node in _list.get_children():
		if c is HBoxContainer:
			for b: Node in c.get_children():
				if b.has_meta("build_type"):
					var t: String = str(b.get_meta("build_type"))
					(b as Button).text = tr("Build %s  %s") % [tr(str(Economy.robots[t]["name"])), Settings.fmt(f.build_cost(t))]
					(b as Button).disabled = not (at_bench and f.can_build(t))
				elif b.has_meta("tier_type"):
					var req: Dictionary = f.tier_requirements(str(b.get_meta("tier_type")))
					var maxed: bool = req.get("maxed", false)
					(b as Button).text = tr("Max tier") if maxed else tr("Upgrade > %s") % tr(str(req["next"]["name"]))
					(b as Button).disabled = maxed or not (at_bench and req["ok"])
					(b as Button).tooltip_text = "" if maxed else tr("%s cubes, %s bolts, %s Control Core. %s") % [Settings.fmt(req["cost"]), Settings.fmt(req["bolts"]), tr(str(Economy.rarity(int(req["core_rarity"])).get("name", "?"))), req["reason"]]
		elif c.has_meta("build_info"):
			var t2: String = str(c.get_meta("build_info"))
			var have: int = 0
			var rs: Array = f.recipe_status(t2)
			for r: Dictionary in rs:
				if r["have"]:
					have += 1
			var why: String = f.build_block_reason(t2)
			(c as Label).text = tr("  parts %d/%d · %s") % [have, rs.size(), ("ready" if why == "" else why) if at_bench else tr("build at the workbench")]
	if _tank_btn:
		var net: WaterNet = f.water_net
		if net == null:
			_tank_btn.visible = false
		else:
			var why2: String = net.place_block_reason(world.patch.global_position)
			_tank_btn.text = tr("Place refill tank here  %s  (%d/%d)") % [Settings.fmt(net.tank_cost()), net.tanks.size(), int(WaterNet.cfg().get("max", 6))]
			_tank_btn.disabled = why2 != ""
			_tank_btn.tooltip_text = why2 if why2 != "" else tr("A Water Tank at your hex. Waterers refill at the nearest one.")


func _mode_label(role_id: String) -> String:
	var f: Fleet = world.fleet
	if not f.has_order(role_id, false):
		return "roaming"
	var od: Dictionary = f.order(role_id, false)
	if str(od.get("mode", "")) == "priority" and (od.get("zone", []) as Array).is_empty():
		return "roaming"
	return tr(MODE_NAMES[str(od.get("mode", "priority"))]).to_lower()


func _bot_line(r: Robot) -> String:
	return "     %s  %s · %s" % [r.robot_name, Economy.tier_name(r.tier), r.status_label()]


## Status pip colour from a robot's status line: working green, idle amber, travelling blue,
## blocked red.
func _status_color(s: String) -> Color:
	if s.begins_with("idle") or "waiting" in s or "nothing" in s or "clean," in s or "lake is clean" in s:
		return Color(1.0, 0.75, 0.3)
	if s.begins_with("out of") or "stuck" in s:
		return Color(1.0, 0.38, 0.32)
	if "parked" in s or "returning" in s or "refilling" in s or "looking" in s or "fetching" in s:
		return Color(0.5, 0.75, 1.0)
	return Color(0.45, 0.95, 0.55)


# --- Map overlay ------------------------------------------------------------------------------

func _build_overlay() -> void:
	_cam = Camera3D.new()
	_cam.fov = 44.0
	_cam.near = 0.5
	_cam.far = 900.0
	world.add_child(_cam)
	# Clear air and a cool, desaturated tactical grade so the overlay pops.
	var we: WorldEnvironment = world.get_node_or_null("WorldEnvironment")
	var src: Environment = we.environment if we else null
	if src == null and world.get("_env") != null:
		src = world._env
	if src:
		var env: Environment = src.duplicate()
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.sdfgi_enabled = false
		env.ssr_enabled = false
		env.adjustment_enabled = true
		env.adjustment_brightness = 0.8
		env.adjustment_contrast = 1.08
		env.adjustment_saturation = 0.45
		var lut := GradientTexture1D.new()
		var lg := Gradient.new()
		lg.set_color(0, Color(0.0, 0.015, 0.05))
		lg.set_color(1, Color(0.9, 0.96, 1.0))
		lut.gradient = lg
		env.adjustment_color_correction = lut
		_cam.environment = env
	_cache_corners()


func _ground_y(p: Vector3) -> float:
	var layout: CityLayout = world.field.layout
	# Sidewalk/curb height only: never climb onto roofs.
	return clampf(layout.height_at(p.x, p.z) if layout else 0.0, 0.0, 0.3) + 0.06


func _corner(c: Vector3, k: int, r: float) -> Vector3:
	var a: float = deg_to_rad(60.0 * k + 30.0)
	var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * r
	return Vector3(p.x, _ground_y(p), p.z)


func _cache_corners() -> void:
	var field: HexField = world.field
	_corners.clear()
	for id: int in field.hex_count():
		var c: Vector3 = field.hex_center(id)
		var pts := PackedVector3Array()
		for k: int in 6:
			pts.append(_corner(c, k, field.hex_size))
		_corners.append(pts)


## Fill colour per hex: hatched heat tint on junk (hotter = more junk left), blue while being
## cleaned, a soft wash on growing ground; clean ground stays clear.
func _progress_color(id: int) -> Color:
	var field: HexField = world.field
	if field.is_water(id) or field.hex_hub[id] != 0:
		return Color(0, 0, 0, 0)
	if not field.is_clean(id):
		var rem: float = 1.0 - field.removed_fraction(id)
		if UITheme.colorblind():
			return Color(UITheme.progress_color("junk" if rem > 0.97 else "cleaning"), 0.16 + 0.16 * rem)
		if rem > 0.97:
			return Color(JUNK_COL.lerp(JUNK_HOT, 0.3), 0.32)
		return Color(CLEANING_COL.lerp(JUNK_COL, rem * 0.5), 0.25 + 0.15 * rem)
	var life: float = float(world.garden.hex_life.get(id, 0.0)) if world.garden else 0.0
	if life > 0.0:
		return Color(UITheme.progress_color("growing") if UITheme.colorblind() else GROW_COL, 0.13)
	return Color(0, 0, 0, 0)


func _rebuild_overlay() -> void:
	var field: HexField = world.field
	if _corners.size() != field.hex_count():
		_cache_corners()
	_fill_cols.resize(field.hex_count())
	for id: int in field.hex_count():
		_fill_cols[id] = _progress_color(id)
	_rebuild_zone()


static func _edge_key(a: Vector3, b: Vector3) -> Vector2i:
	var m: Vector3 = (a + b) * 0.5
	return Vector2i(roundi(m.x * 4.0), roundi(m.z * 4.0))


## Boundary edges (edges not shared with another hex of the set).
func _boundary(ids: Array) -> Array:
	var count: Dictionary = {}
	var edges: Dictionary = {}
	for h: Variant in ids:
		var id: int = int(h)
		if id < 0 or id >= _corners.size():
			continue
		var pts: PackedVector3Array = _corners[id]
		for k: int in 6:
			var key: Vector2i = _edge_key(pts[k], pts[(k + 1) % 6])
			count[key] = int(count.get(key, 0)) + 1
			edges[key] = [pts[k], pts[(k + 1) % 6]]
	var out: Array = []
	for key: Vector2i in edges:
		if int(count[key]) == 1:
			out.append(edges[key])
	return out


func _rebuild_zone() -> void:
	if world == null or _corners.is_empty():
		return
	var zone: Array = _sel_zone()
	_zone_set.clear()
	for h: Variant in zone:
		_zone_set[int(h)] = true
	_zone_edges = _boundary(zone)
	_other_edges.clear()
	if not _sel_bot:
		for role_id: String in Fleet.ROLES:
			if role_id == _sel_key or not world.fleet.has_order(role_id, false):
				continue
			for e: Array in _boundary(world.fleet.order(role_id, false).get("zone", [])):
				_other_edges.append([e[0], e[1], ROLE_COLORS[role_id]])
	if _map:
		_map.queue_redraw()


func _project_all() -> void:
	var n: int = _corners.size()
	_proj.resize(n)
	_proj_ok.resize(n)
	for id: int in n:
		var pts: PackedVector3Array = _corners[id]
		var out := PackedVector2Array()
		out.resize(6)
		var ok: int = 1
		for k: int in 6:
			if _cam.is_position_behind(pts[k]):
				ok = 0
				break
			out[k] = _cam.unproject_position(pts[k])
		_proj[id] = out
		_proj_ok[id] = ok


func _sp(p: Vector3) -> Vector2:
	return _cam.unproject_position(p)


func _draw_map() -> void:
	if not is_open or _cam == null or _corners.is_empty():
		return
	var t: float = Time.get_ticks_msec() * 0.001
	var field: HexField = world.field
	_project_all()
	var vr: Rect2 = _map.get_viewport_rect().grow(80.0)
	# 1. Hex state fills (world-locked hatching on junk).
	for id: int in _corners.size():
		if _proj_ok[id] == 0 or id >= _fill_cols.size():
			continue
		var col: Color = _fill_cols[id]
		if col.a <= 0.0:
			continue
		var pts: PackedVector2Array = _proj[id]
		if not vr.has_point(pts[0]):
			continue
		var uvs := PackedVector2Array()
		for k: int in 6:
			var w: Vector3 = _corners[id][k]
			uvs.append(Vector2(w.x, w.z) * 0.32)
		var cols := PackedColorArray([col, col, col, col, col, col])
		_map.draw_polygon(pts, cols, uvs, _hatch)
	# 2. Other crews' zones, faint.
	for e: Array in _other_edges:
		if _cam.is_position_behind(e[0]) or _cam.is_position_behind(e[1]):
			continue
		_map.draw_line(_sp(e[0]), _sp(e[1]), Color(e[2], 0.5), 1.5, true)
	# 3. Grid lines near the cursor, fading out with distance.
	var cursor: Vector3 = _hover_world
	if _using_pad:
		cursor = _ground_hit(_screen_centre())
	var sel_col: Color = _sel_color()
	if cursor != Vector3.INF:
		var reach: float = world.field.hex_size * 3.2 + _height * 0.1
		for id: int in _corners.size():
			if _proj_ok[id] == 0:
				continue
			var c: Vector3 = field.hex_center(id)
			var d: float = Vector2(c.x - cursor.x, c.z - cursor.z).length()
			if d > reach:
				continue
			var a: float = 1.0 - smoothstep(reach * 0.25, reach, d)
			var pts2: PackedVector2Array = _proj[id]
			var loop := PackedVector2Array(pts2)
			loop.append(pts2[0])
			_map.draw_polyline(loop, Color(GRID_COL, 0.10 * a), 4.0, true)
			_map.draw_polyline(loop, Color(GRID_COL, 0.55 * a), 1.0, true)
	# 4. Selected zone: soft fill, glowing animated border, corner brackets, label.
	if not _zone_set.is_empty():
		var pulse: float = 0.5 + 0.5 * sin(t * 2.4)
		for h: int in _zone_set:
			if h < _proj.size() and _proj_ok[h] == 1:
				_map.draw_colored_polygon(_proj[h], Color(sel_col, 0.1 + 0.05 * pulse))
		var bb := Rect2()
		var first: bool = true
		for e: Array in _zone_edges:
			if _cam.is_position_behind(e[0]) or _cam.is_position_behind(e[1]):
				continue
			var a2: Vector2 = _sp(e[0])
			var b2: Vector2 = _sp(e[1])
			var ph: float = 0.5 + 0.5 * sin(t * 3.0 - ((e[0] as Vector3).x + (e[0] as Vector3).z) * 0.25)
			_map.draw_line(a2, b2, Color(sel_col, 0.16 + 0.1 * pulse), 8.0, true)
			_map.draw_line(a2, b2, Color(sel_col.lightened(0.25 * ph), 0.8 + 0.2 * ph), 2.0, true)
			if first:
				bb = Rect2(a2, Vector2.ZERO)
				first = false
			bb = bb.expand(a2).expand(b2)
		if not first:
			bb = bb.grow(10.0)
			var tl: float = clampf(minf(bb.size.x, bb.size.y) * 0.2, 8.0, 22.0)
			var bc := Color(sel_col, 0.9)
			for cn: Vector2 in [bb.position, Vector2(bb.end.x, bb.position.y), bb.end, Vector2(bb.position.x, bb.end.y)]:
				var sx: float = 1.0 if cn.x <= bb.get_center().x else -1.0
				var sy: float = 1.0 if cn.y <= bb.get_center().y else -1.0
				_map.draw_line(cn, cn + Vector2(tl * sx, 0), bc, 2.0, true)
				_map.draw_line(cn, cn + Vector2(0, tl * sy), bc, 2.0, true)
			var txt: String = tr_n("%s · %d HEX", "%s · %d HEXES", _zone_set.size()) % [(_sel_key if _sel_bot else tr(ROLE_NAMES[_sel_key])).to_upper(), _zone_set.size()]
			_tag(Vector2(bb.position.x, bb.position.y - 8.0), txt, sel_col, false)
	# 5. Hovered / reticle hex.
	var hh: int = _reticle_hex if _using_pad else _hover_hex
	if hh >= 0 and hh < _proj.size() and _proj_ok[hh] == 1:
		var hp: PackedVector2Array = _proj[hh]
		var loop2 := PackedVector2Array(hp)
		loop2.append(hp[0])
		var hc: Color = UITheme.GOLD if _using_pad else Color(0.92, 0.97, 1.0)
		_map.draw_colored_polygon(hp, Color(hc, 0.08))
		_map.draw_polyline(loop2, Color(hc, 0.25), 6.0, true)
		_map.draw_polyline(loop2, Color(hc, 0.95), 1.6, true)
	# 6. Labelled markers: base, outposts, you.
	for m: Dictionary in _frame_markers():
		_draw_marker(m, t)
	# 7. Robots.
	for r: Robot in world.fleet.robots():
		_draw_robot(r, t)


## Text tag with a dark rounded backing. If centred, x is the tag's centre.
func _tag(pos: Vector2, text: String, col: Color, centred: bool, fs: int = 12) -> void:
	var font: Font = UITheme.font()
	var sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pad := Vector2(7, 3)
	var x0: float = pos.x - (sz.x * 0.5 if centred else 0.0)
	var rc := Rect2(Vector2(x0 - pad.x, pos.y - sz.y - pad.y), sz + pad * 2.0)
	var sb := UITheme.box(Color(0.03, 0.035, 0.045, 0.82), Color(col, 0.55), 1, 4, 0)
	_map.draw_style_box(sb, rc)
	_map.draw_string(font, Vector2(x0, pos.y - 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Base and Patch every frame, plus map_markers and anything world.command_markers() returns.
func _frame_markers() -> Array:
	var out: Array = []
	var dp: Vector3 = world.depot.global_position
	out.append({"pos": dp, "label": tr("BASE"), "color": UITheme.GOLD, "kind": "base"})
	for m: Variant in map_markers.values():
		out.append(m)
	if world.has_method("command_markers"):
		for m2: Variant in world.command_markers():
			if m2 is Dictionary:
				out.append(m2)
	out.append({"pos": world.patch.global_position, "label": tr("YOU"), "color": Color(0.55, 0.9, 1.0), "kind": "you"})
	return out


## Adds or moves a labelled map marker (e.g. an outpost). kind: "outpost", "base", "you" or any.
func set_map_marker(id: String, pos: Vector3, label: String, col: Color = Color(0.7, 0.95, 0.75), kind: String = "outpost") -> void:
	map_markers[id] = {"pos": pos, "label": label, "color": col, "kind": kind}


func remove_map_marker(id: String) -> void:
	map_markers.erase(id)


## Replaces all markers whose id starts with prefix with one per position (labels "NAME 1", ...).
## Entries can be Vector3 or {pos, label, color, kind} dictionaries.
func set_map_markers_from_list(prefix: String, list: Array, label: String = "OUTPOST", col: Color = Color(0.7, 0.95, 0.75)) -> void:
	for k: String in map_markers.keys():
		if k.begins_with(prefix):
			map_markers.erase(k)
	for i: int in list.size():
		var e: Variant = list[i]
		if e is Vector3:
			set_map_marker("%s%d" % [prefix, i], e, "%s %d" % [label, i + 1] if list.size() > 1 else label, col)
		elif e is Dictionary:
			var d: Dictionary = e
			set_map_marker("%s%d" % [prefix, i], d.get("pos", Vector3.ZERO), str(d.get("label", label)), d.get("color", col), str(d.get("kind", "outpost")))


func _draw_marker(m: Dictionary, t: float) -> void:
	var pos: Vector3 = m.get("pos", Vector3.ZERO)
	var g := Vector3(pos.x, _ground_y(pos), pos.z)
	if _cam.is_position_behind(g):
		return
	var col: Color = m.get("color", Color.WHITE)
	var kind: String = str(m.get("kind", "outpost"))
	var p: Vector2 = _sp(g)
	if kind == "you":
		var pr: float = 7.0 + 1.5 * sin(t * 4.0)
		_map.draw_arc(p, pr + 5.0, 0.0, TAU, 32, Color(col, 0.25), 3.0, true)
		_map.draw_circle(p, pr * 0.6, Color(col, 0.95))
		_map.draw_arc(p, pr, 0.0, TAU, 32, Color(col, 0.9), 1.5, true)
		_tag(p + Vector2(0, -16), str(m.get("label", "")), col, true, 11)
		return
	# Ground ring + stem + diamond head + label.
	var ring: float = 12.0 if kind == "base" else 9.0
	_map.draw_arc(p, ring, 0.0, TAU, 40, Color(col, 0.35), 4.0, true)
	_map.draw_arc(p, ring, 0.0, TAU, 40, Color(col, 0.95), 1.5, true)
	var head: Vector2 = p + Vector2(0, -34.0 if kind == "base" else -26.0)
	_map.draw_line(p, head, Color(col, 0.8), 1.5, true)
	var dsz: float = 7.0 if kind == "base" else 5.5
	var dia := PackedVector2Array([head + Vector2(0, -dsz), head + Vector2(dsz, 0), head + Vector2(0, dsz), head + Vector2(-dsz, 0)])
	_map.draw_colored_polygon(dia, Color(0.03, 0.035, 0.045, 0.9))
	var loop := PackedVector2Array(dia)
	loop.append(dia[0])
	_map.draw_polyline(loop, col, 2.0, true)
	_map.draw_circle(head, dsz * 0.38, col)
	_tag(head + Vector2(0, -dsz - 5.0), str(m.get("label", "")), col, true, 13 if kind == "base" else 12)


func _draw_robot(r: Robot, t: float) -> void:
	var gp := Vector3(r.global_position.x, _ground_y(r.global_position), r.global_position.z)
	if _cam.is_position_behind(gp):
		return
	var p: Vector2 = _sp(gp)
	var role: String = r.role()
	var col: Color = ROLE_COLORS.get(role, Color.WHITE)
	var selected: bool = (_sel_bot and r.robot_name == _sel_key) or (not _sel_bot and role == _sel_key)
	var rad: float = 10.0
	# Heading chevron, projected from the robot's forward.
	var fwd: Vector3 = -r.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.01:
		var tip2: Vector2 = _sp(gp + fwd.normalized() * 1.5) - p
		if tip2.length() > 0.01:
			var dir: Vector2 = tip2.normalized()
			var nrm := Vector2(-dir.y, dir.x)
			var base_c: Vector2 = p + dir * (rad + 2.0)
			_map.draw_colored_polygon(PackedVector2Array([base_c + dir * 7.0, base_c + nrm * 5.0, base_c - nrm * 5.0]), Color(col, 0.95 if selected else 0.7))
	if selected:
		var pulse: float = 0.5 + 0.5 * sin(t * 4.0)
		_map.draw_arc(p, rad + 4.0 + pulse * 2.0, 0.0, TAU, 32, Color(col, 0.28), 3.0, true)
	_map.draw_circle(p + Vector2(0, 2), rad + 1.0, Color(0, 0, 0, 0.35))
	_map.draw_circle(p, rad, Color(0.05, 0.055, 0.065, 0.92))
	_map.draw_arc(p, rad, 0.0, TAU, 32, Color(col, 1.0 if selected else 0.75), 2.0 if selected else 1.5, true)
	draw_role_glyph(_map, role, p, rad * 0.55, Color(col, 1.0 if selected else 0.85))
	# Status pip.
	var sc: Color = _status_color(r.status_text())
	var pp: Vector2 = p + Vector2(rad * 0.75, -rad * 0.75)
	_map.draw_circle(pp, 3.6, Color(0.03, 0.03, 0.04))
	_map.draw_circle(pp, 2.6, sc)
	if _sel_bot and r.robot_name == _sel_key:
		_tag(p + Vector2(0, -rad - 6.0), r.robot_name, col, true, 11)


func _update_tooltip() -> void:
	var h: int = _reticle_hex if _using_pad else _hover_hex
	if h < 0 or _paint != 0 or _pad_paint != 0:
		_tip.visible = false
		return
	var field: HexField = world.field
	var title: String = tr("HEX %d") % h
	var lines: Array[String] = []
	var bar: float = -1.0
	if field.hex_hub[h] != 0:
		title = tr("BASE YARD")
		lines.append(tr("Home ground, always clean"))
	elif field.is_water(h):
		title = tr("LAKE HEX %d") % h
		var f: float = field.removed_fraction(h)
		lines.append(tr("Clean") if field.is_clean(h) else tr("Floating junk  %d%% left") % int(round((1.0 - f) * 100.0)))
		bar = 0.0 if field.is_clean(h) else 1.0 - f
	elif field.is_clean(h):
		lines.append(tr("Clean"))
	else:
		var left: float = 1.0 - field.removed_fraction(h)
		lines.append(tr("Junk  %d%% left") % int(round(left * 100.0)))
		bar = left
	var hl: Variant = world.get("hex_levels")
	if hl != null:
		var l: int = (hl as HexLevels).level_of(h)
		if l >= 0:
			lines.append(tr("Level %d · %s") % [l, (hl as HexLevels).level_name(l)])
	if _zone_set.has(h):
		lines.append(tr("In %s zone") % (_sel_key if _sel_bot else tr(ROLE_NAMES[_sel_key])))
	_tip_title.text = title
	_tip_body.text = "\n".join(lines)
	_tip_bar.visible = bar >= 0.0
	_tip_bar.value = maxf(bar, 0.0) * 100.0
	var anchor: Vector2 = _screen_centre() if _using_pad else get_viewport().get_mouse_position()
	_tip.reset_size()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var pos: Vector2 = anchor + Vector2(22, 18)
	pos.x = minf(pos.x, vs.x - _tip.size.x - 10.0)
	pos.y = minf(pos.y, vs.y - _tip.size.y - 10.0)
	_tip.position = pos
	_tip.visible = true


# --- Frame ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open:
		return
	# WASD pans the camera.
	var mv := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
	_focus += Vector3(mv.x, 0, mv.y) * _height * 0.8 * delta
	var lim: float = (world.field.radius + 1.0) * world.field.hex_size * 1.8
	_focus.x = clampf(_focus.x, -lim, lim)
	_focus.z = clampf(_focus.z, -lim, lim)
	var pitch: float = deg_to_rad(PITCH_DEG)
	var target: Vector3 = _focus + Vector3(0, sin(pitch), cos(pitch)) * _height
	var k: float = clampf(delta * 5.0, 0.0, 1.0)
	_cam_pos = _cam_pos.lerp(target, k)
	_look = _look.lerp(_focus, k)
	_cam.global_position = _cam_pos
	if not _cam_pos.is_equal_approx(_look):
		_cam.look_at(_look, Vector3.UP)
	if _using_pad:
		var rh: int = _hex_under(_screen_centre())
		if rh != _reticle_hex:
			_reticle_hex = rh
			if _pad_paint != 0:
				_paint_hex(rh, _pad_paint)
	else:
		# Keep the hover hex right while the camera glides.
		_hover_world = _ground_hit(get_viewport().get_mouse_position())
		_hover_hex = world.field.hex_at(_hover_world) if _hover_world != Vector3.INF else -1
	_overlay_t += delta
	if _overlay_t > 0.5:
		_overlay_t = 0.0
		_rebuild_overlay()
	_map.queue_redraw()
	_update_tooltip()
	var f: Fleet = world.fleet
	_info_name.text = str(world.district_name)
	_info_bots.text = tr("%d robots") % f.robots().size()
	var total: int = maxi(world.field.junk_hex_count, 1)
	_info_bar.value = 100.0 * float(world.field.junk_hexes_cleaned()) / float(total)
	_info_count.text = tr("%d / %d hexes clean") % [world.field.junk_hexes_cleaned(), world.field.junk_hex_count]
	_list_t += delta
	if _list_t > 0.6:
		_list_t = 0.0
		for c: Node in _list.get_children():
			if c.has_meta("bot"):
				var r: Robot = f.find_robot(str(c.get_meta("bot")))
				if r:
					_update_bot_row(c as Button, r)
		_refresh_build()


func _ground_hit(sp: Vector2) -> Vector3:
	var o: Vector3 = _cam.project_ray_origin(sp)
	var d: Vector3 = _cam.project_ray_normal(sp)
	if absf(d.y) < 0.001:
		return Vector3.INF
	return o + d * (-o.y / d.y)


func _hex_under(sp: Vector2) -> int:
	var p: Vector3 = _ground_hit(sp)
	if p == Vector3.INF:
		return -1
	return world.field.hex_at(p)


func _zoom(factor: float, toward: Vector2) -> void:
	var before: float = _height
	_height = clampf(_height * factor, ZOOM_MIN, ZOOM_MAX)
	# Zoom toward the cursor a little, like an RTS.
	if _height < before and toward != Vector2.INF:
		var hit: Vector3 = _ground_hit(toward)
		if hit != Vector3.INF:
			_focus += Vector3(hit.x - _focus.x, 0, hit.z - _focus.z) * 0.15


func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_paint = 1 if mb.pressed else 0
				if mb.pressed:
					_paint_at(get_viewport().get_mouse_position())
			MOUSE_BUTTON_RIGHT:
				_paint = -1 if mb.pressed else 0
				if mb.pressed:
					_paint_at(get_viewport().get_mouse_position())
			MOUSE_BUTTON_MIDDLE:
				_pan_drag = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(1.0 / 1.12, get_viewport().get_mouse_position())
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(1.12, Vector2.INF)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		var h: int = _hex_under(get_viewport().get_mouse_position())
		if h != _hover_hex:
			_hover_hex = h
		if _pan_drag:
			_focus -= Vector3(mm.relative.x, 0, mm.relative.y) * _height * 0.0022
		elif _paint != 0:
			_paint_at(get_viewport().get_mouse_position())


func _paint_at(sp: Vector2) -> void:
	_paint_hex(_hex_under(sp), _paint)


## Mark (paint > 0) or unmark one hex in the selected crew's / robot's zone.
func _paint_hex(h: int, paint: int) -> void:
	var field: HexField = world.field
	if h < 0 or paint == 0 or field.hex_hub[h] != 0:
		return
	var od: Dictionary = world.fleet.order(_sel_key, _sel_bot)
	var has: bool = (od["zone"] as Array).has(h)
	if (paint > 0) == has:
		return
	if str(od.get("mode", "")) in ["recall", "follow"]:
		od["mode"] = "priority"  # marking ground means "work here"
	world.fleet.toggle_zone_hex(_sel_key, _sel_bot, h, paint > 0)
	Audio.play("blip", 1.3 if paint > 0 else 0.9, -14.0)
	_rebuild_zone()
	var mode: String = str(od.get("mode", ""))
	for b: Node in _mode_row.get_children():
		(b as Button).button_pressed = str(b.get_meta("mode")) == mode
	_mode_help.text = tr(str(MODE_HELP.get(mode, "")))


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	# D-pad down is open_command on a pad, but here it moves focus, so only B / Start close.
	var pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	if (event.is_action_pressed("open_command") and not pad) or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close_view()
		get_viewport().set_input_as_handled()


# --- Controller -------------------------------------------------------------------------------

func _screen_centre() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


func _set_pad(on: bool) -> void:
	_using_pad = on
	if not on:
		_pad_paint = 0
	if _reticle:
		_reticle.visible = on and is_open
	pass  # [deck] _keys (PromptLabel) follows Settings.last_input_pad by itself


## Runs before the GUI: tracks the input device and drives the map with the pad.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		if not _using_pad:
			_set_pad(true)
	elif event is InputEventMouseButton or event is InputEventKey or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 2.0):
		if _using_pad:
			_set_pad(false)
	if not is_open:
		return
	var vp: Viewport = get_viewport()
	var fo: Control = vp.gui_get_focus_owner()
	var panel_focus: bool = fo != null and _root.is_ancestor_of(fo)
	if event is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = event
		# Left stick pans the map (via the move_* axes in _process): leave the panel.
		if jm.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] and absf(jm.axis_value) > 0.5 and panel_focus:
			_last_focus_id = _focus_id(fo)
			fo.release_focus()
			vp.set_input_as_handled()
		return
	if not event is InputEventJoypadButton:
		return
	var jb: InputEventJoypadButton = event
	if event.is_action("zoom_in") or event.is_action("zoom_out"):
		if jb.pressed:
			_zoom(1.0 / 1.2 if event.is_action("zoom_in") else 1.2, Vector2.INF)
		vp.set_input_as_handled()
		return
	if panel_focus:
		return  # the GUI handles D-pad / A on the focused button
	match jb.button_index:
		JOY_BUTTON_A, JOY_BUTTON_X:
			var p: int = 1 if jb.button_index == JOY_BUTTON_A else -1
			if jb.pressed:
				_pad_paint = p
				_reticle_hex = _hex_under(_screen_centre())
				_paint_hex(_reticle_hex, p)
			elif _pad_paint == p:
				_pad_paint = 0
			vp.set_input_as_handled()
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			if jb.pressed:
				_pad_paint = 0
				_restore_focus()
			vp.set_input_as_handled()


## Identity of a panel control that survives list rebuilds: [meta key, value].
func _focus_id(c: Control) -> Array:
	for k: String in ["mode", "role", "bot", "build_type", "tier_type"]:
		if c.has_meta(k):
			return [k, str(c.get_meta(k))]
	if c == _tank_btn:
		return ["tank", ""]
	return []


func _find_focusable(id: Array) -> Control:
	if id.is_empty():
		return null
	if id[0] == "tank":
		return _tank_btn if _tank_btn and _tank_btn.visible else null
	var stack: Array[Node] = [_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and n.has_meta(id[0]) and str(n.get_meta(id[0])) == id[1] and not n.is_queued_for_deletion() and (n as Control).is_visible_in_tree():
			return n as Control
		stack.append_array(n.get_children())
	return null


func _restore_focus() -> void:
	var c: Control = _find_focusable(_last_focus_id)
	if c:
		c.grab_focus()
	else:
		_focus_panel()


## On open: focus the selected crew's button, else the first mode button.
func _focus_panel() -> void:
	if not is_open:
		return
	var c: Control = _find_focusable(["bot", _sel_key] if _sel_bot else ["role", _sel_key])
	if c == null and _mode_row.get_child_count() > 0:
		c = _mode_row.get_child(0)
	if c:
		c.grab_focus()
