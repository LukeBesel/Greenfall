class_name BuilderPanel
extends HBoxContainer
## [drones] Workbench "Builder" tab. Left: the fleet (pick a robot). Middle: a rotating 3D preview
## of the selected robot with its parts, name tag and trait, and its stats. Right: the five part
## slots, the parts that fit the chosen slot (focus or hover one to preview it and see the stat
## changes before fitting it; press to fit, craft or buy), crew presets and the parts bin.
## Every control is a focusable Button / LineEdit, so a gamepad walks the whole panel with the
## d-pad and A; LB/RB still switch tabs.

const PREVIEW_SIZE := Vector2i(360, 190)
const BAD := Color(1.0, 0.55, 0.45)
# l10n:begin
const ROLE_STATS: Dictionary = {
	"clean": [["speed", "Speed", " m/s"], ["scoop_rate", "Scoop rate", "/s"], ["capacity", "Hopper", ""], ["efficiency", "Cube quality", "x"], ["scan", "Scan", "%"]],
	"skim": [["speed", "Speed", " m/s"], ["scoop_rate", "Net rate", "/s"], ["capacity", "Hopper", ""], ["efficiency", "Cube quality", "x"], ["scan", "Scan", "%"]],
	"haul": [["speed", "Speed", " m/s"], ["carry", "Forks", " bales"], ["scan", "Scan", "%"]],
	"plant": [["speed", "Speed", " m/s"], ["work_rate", "Planting", "/s"], ["scan", "Scan", "%"]],
	"water": [["speed", "Speed", " m/s"], ["work_rate", "Spray rate", "/s"], ["tank", "Tank", ""], ["spray_radius", "Spray reach", " m"], ["refill_rate", "Refill", "/s"], ["scan", "Scan", "%"]],
}
# l10n:end
const CREW_NAMES: Dictionary = {"clean": "Clean", "haul": "Haul", "plant": "Plant", "water": "Water", "skim": "Skim"}  # l10n

var fleet: Fleet
## [ui2] Inside the Locker: no fleet list (the Locker's selector picks the robot), no stat table,
## presets or shop line; parts are cosmetics, so only the look, name and personality show.
var locker_mode: bool = false
var _left: Control
var _sel: Robot
var _slot: String = "chassis"
var _robot_list: VBoxContainer
var _robot_btns: Array[Button] = []
var _slot_btns: Dictionary = {}
var _opts: VBoxContainer
var _opt_ids: Array[String] = []
var _info: Label
var _stats: VBoxContainer
var _name_edit: LineEdit
var _trait: Label
var _title: Label
var _bin: Label
var _preset_save: Button
var _preset_apply: Button
var _preset_info: Label
var _haggle: Label
var _empty: Label
var _mid: VBoxContainer
var _right: VBoxContainer
# Preview
var _vp: SubViewport
var _pivot: Node3D
var _pv: RobotVisual
var _pv_key: String = ""
var _t: float = 0.0
var _bin_t: float = 0.0
var _sel_key: String = ""
var _dev_done: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 455)
	_build_left()
	_build_mid()
	_build_right()
	if locker_mode:  # [ui2]
		_left.visible = false
		_stats.visible = false
		_preset_save.get_parent().visible = false
		_preset_info.visible = false
		_haggle.visible = false
	var bots: Array[Robot] = _bots()
	if not bots.is_empty():
		_sel = bots[0]
	_rebuild_robot_list()
	_refresh_all()


func _bots() -> Array[Robot]:
	var out: Array[Robot] = []
	if fleet:
		out = fleet.robots()
	out.sort_custom(func(a: Robot, b: Robot) -> bool:
		var ra: int = Fleet.ROLES.find(a.role())
		var rb: int = Fleet.ROLES.find(b.role())
		return ra < rb if ra != rb else a.robot_name < b.robot_name)
	return out


# --- Layout --------------------------------------------------------------------------------

func _column(title: String, width: float) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(UITheme.CARD_BG, Color(1, 1, 1, 0.07), 1, 8, 12))
	pc.custom_minimum_size = Vector2(width, 0)
	add_child(pc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	pc.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	sc.add_child(vb)
	if title != "":
		vb.add_child(UITheme.label(title, 12, Color(0.4, 0.75, 1.0)))
	return vb


func _build_left() -> void:
	var vb: VBoxContainer = _column(tr("YOUR ROBOTS"), 214)
	_left = vb.get_parent().get_parent()
	_robot_list = VBoxContainer.new()
	_robot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_robot_list.add_theme_constant_override("separation", 5)
	vb.add_child(_robot_list)


func _build_mid() -> void:
	_mid = _column("", 380)
	_mid.get_parent().get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = UITheme.label("", 21, Color.WHITE)
	_mid.add_child(_title)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(PREVIEW_SIZE)
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mid.add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = PREVIEW_SIZE
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(_vp)
	_build_stage()
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 6)
	_mid.add_child(nr)
	_name_edit = LineEdit.new()
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(150, 36)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_stylebox_override("normal", UITheme.box(Color(0.04, 0.045, 0.05, 0.95), Color(1, 1, 1, 0.1), 1, 4, 8))
	_name_edit.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), UITheme.GOLD, 1, 4, 8))
	_name_edit.text_submitted.connect(func(t: String) -> void: _rename(t))
	_name_edit.focus_exited.connect(func() -> void:
		if _sel and _name_edit.text != _sel.robot_name:
			_rename(_name_edit.text))
	nr.add_child(_name_edit)
	var reroll := Button.new()
	reroll.text = tr("New name")
	reroll.custom_minimum_size = Vector2(0, 38)
	reroll.pressed.connect(func() -> void:
		if _sel:
			_rename(Fleet.NAMES[randi() % Fleet.NAMES.size()] + "-%02d" % (randi() % 100)))
	nr.add_child(reroll)
	_trait = UITheme.label("", 14, UITheme.GOLD)
	_trait.autowrap_mode = TextServer.AUTOWRAP_WORD
	_mid.add_child(_trait)
	_stats = VBoxContainer.new()
	_stats.add_theme_constant_override("separation", 1)
	_mid.add_child(_stats)
	_empty = UITheme.label(tr("No robots yet. Build one in the Bots tab, then style it here.\nYour first robot comes with treads and a bobble plant."), 16, UITheme.MUTED)  # [ui2]
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD
	_empty.visible = false
	_mid.add_child(_empty)


## Turntable stage: dark floor disc with a thin light ring, key + rim light, soft ambient.
func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.068, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 35, 0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.6, 0.8, 1.0)
	_vp.add_child(rim)
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.045, 0.05, 0.058)
	floor_m.roughness = 0.75
	floor_m.metallic = 0.0
	var disc := MeshInstance3D.new()
	disc.mesh = ProcMesh.cyl(1.05, 1.1, 0.06, 48)
	disc.material_override = floor_m
	disc.position = Vector3(0, -0.03, 0)
	_vp.add_child(disc)
	var ring := MeshInstance3D.new()
	ring.mesh = ProcMesh.torus(1.04, 1.055, 64, 3)
	ring.material_override = Mats.lamp(Color(0.35, 0.85, 1.0), 1.6)
	ring.position = Vector3(0, 0.005, 0)
	_vp.add_child(ring)
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.position = Vector3(0, 1.25, 3.0)
	_vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.6, 0), Vector3.UP)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)


func _build_right() -> void:
	_right = _column(tr("PART SLOTS"), 350)
	for s: String in RobotBuilder.SLOTS:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void:
			_set_slot(s)
			_focus_option(0))
		b.focus_entered.connect(func() -> void: _set_slot(s))
		_right.add_child(b)
		_slot_btns[s] = b
	_right.add_child(UITheme.label(tr("PARTS THAT FIT"), 12, Color(0.4, 0.75, 1.0)))
	_opts = VBoxContainer.new()
	_opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opts.add_theme_constant_override("separation", 4)
	_right.add_child(_opts)
	_info = UITheme.label("", 13, UITheme.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.custom_minimum_size = Vector2(0, 36)
	_right.add_child(_info)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 6)
	_right.add_child(pr)
	_preset_save = Button.new()
	_preset_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_save.pressed.connect(_on_save_preset)
	pr.add_child(_preset_save)
	_preset_apply = Button.new()
	_preset_apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_apply.pressed.connect(_on_apply_preset)
	pr.add_child(_preset_apply)
	_preset_info = UITheme.label("", 12, UITheme.MUTED)
	_preset_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_right.add_child(_preset_info)
	_haggle = UITheme.label("", 12, Color(0.75, 0.85, 0.6))
	_haggle.autowrap_mode = TextServer.AUTOWRAP_WORD
	_right.add_child(_haggle)
	_bin = UITheme.label("", 13, UITheme.GOLD)
	_right.add_child(_bin)


# --- Refresh -------------------------------------------------------------------------------

func _rebuild_robot_list() -> void:
	for c: Node in _robot_list.get_children():
		_robot_list.remove_child(c)
		c.queue_free()
	_robot_btns.clear()
	for r: Robot in _bots():
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 52)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.set_meta("robot", r)
		b.pressed.connect(func() -> void: _select(r))
		b.focus_entered.connect(func() -> void: _select(r))
		_robot_list.add_child(b)
		_robot_btns.append(b)
	_style_robot_list()


func _style_robot_list() -> void:
	for b: Button in _robot_btns:
		var r: Robot = b.get_meta("robot") as Robot
		if not is_instance_valid(r):
			continue
		var full: bool = RobotBuilder.is_full_custom(r.build)
		b.text = "%s%s\n%s %s · %s" % [r.robot_name, "  ★" if full else "", tr(str(Economy.robots.get(r.type_id, {}).get("name", r.type_id))), Economy.tier_name(r.tier), tr(str(RobotBuilder.trait_def(RobotBuilder.trait_of(r)).get("name", "")))]
		var on: bool = r == _sel
		var col: Color = RobotBuilder.CREW_COLORS.get(r.role(), UITheme.GOLD)
		b.add_theme_stylebox_override("normal", UITheme.box(Color(col.r * 0.15 + 0.03, col.g * 0.15 + 0.03, col.b * 0.15 + 0.03, 0.95) if on else UITheme.TEAL, col if on else Color(col, 0.25), 1, 6, 8))
		b.add_theme_color_override("font_color", Color.WHITE if on else UITheme.CREAM)


func _refresh_all() -> void:
	var has: bool = _sel != null and is_instance_valid(_sel)
	_empty.visible = not has
	for n: Control in [_name_edit.get_parent(), _trait, _stats]:
		n.visible = has and not (locker_mode and n == _stats)
	_right.get_parent().get_parent().visible = has
	if not has:
		_title.text = tr("ROBOT BUILDER")
		_show_preview({}, true)
		return
	var tdef: Dictionary = RobotBuilder.trait_def(RobotBuilder.trait_of(_sel))
	_sel_key = _key(_sel)
	_title.text = "%s  ·  %s" % [tr(str(Economy.robots.get(_sel.type_id, {}).get("name", ""))).to_upper(), Economy.tier_name(_sel.tier)]
	if not _name_edit.has_focus():
		_name_edit.text = _sel.robot_name
	_trait.text = "%s  —  %s" % [tr(str(tdef.get("name", ""))).to_upper(), tr(str(tdef.get("desc", "")))]  # [ui2] personality is flavour
	for s: String in RobotBuilder.SLOTS:
		var id: String = str(_sel.build.get(s, ""))
		var b: Button = _slot_btns[s]
		b.text = "%s   %s" % [RobotBuilder.slot_name(s).to_upper(), tr("Stock") if id == "" else tr(str(RobotBuilder.part(id).get("name", id)))]
		var on: bool = s == _slot
		b.add_theme_stylebox_override("normal", UITheme.box(Color(0.2, 0.15, 0.07, 0.9) if on else UITheme.TEAL, UITheme.GOLD if on else UITheme.RUST, 1, 4, 8))
		b.add_theme_color_override("font_color", UITheme.GOLD if on else (Color.WHITE if id != "" else UITheme.MUTED))
	_rebuild_options()
	_refresh_presets()
	_refresh_bin()
	_style_robot_list()
	_preview_candidate(str(_sel.build.get(_slot, "")))


func _rebuild_options() -> void:
	var keep: int = -1
	for i: int in _opts.get_child_count():
		if (_opts.get_child(i) as Control).has_focus():
			keep = i
	for c: Node in _opts.get_children():
		_opts.remove_child(c)
		c.queue_free()
	_opt_ids.clear()
	if _sel == null:
		return
	var ids: Array[String] = [""]
	for p: Dictionary in RobotBuilder.parts_for_slot(_slot):
		if RobotBuilder.fits(str(p["id"]), _sel.type_id):
			ids.append(str(p["id"]))
	var cur: String = str(_sel.build.get(_slot, ""))
	for id: String in ids:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 40)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		var line2: String = ""
		var col: Color = UITheme.CREAM
		if id == "":
			b.text = tr("Stock  ·  the %s look%s") % [Economy.tier_name(_sel.tier), tr("   (fitted)") if cur == "" else ""]
		else:
			var p: Dictionary = RobotBuilder.part(id)
			var n: int = RobotBuilder.count(id)
			if id == cur:
				line2 = "fitted"
				col = UITheme.GOLD
			elif n > 0:
				line2 = tr("Unlocked  ·  press to fit")  # [ui2] owned parts fit every robot
				col = Color.WHITE
			else:
				var why: String = RobotBuilder.get_block_reason(id)
				line2 = RobotBuilder.cost_text(id)
				if why != "":
					line2 += "  ·  " + why
					col = UITheme.MUTED
				else:
					line2 += tr("  ·  press to unlock + fit")
					col = UITheme.GREEN
			b.text = "%s%s\n%s" % [tr(str(p.get("name", id))), tr("  (Maker set)") if p.has("set") else "", line2]
		b.add_theme_color_override("font_color", col)
		b.focus_entered.connect(func() -> void: _preview_candidate(id))
		b.mouse_entered.connect(func() -> void: _preview_candidate(id))
		b.pressed.connect(func() -> void: _on_option(id))
		_opts.add_child(b)
		_opt_ids.append(id)
	if keep >= 0:
		_focus_option.call_deferred(mini(keep, _opts.get_child_count() - 1))


func _focus_option(i: int) -> void:
	if i >= 0 and i < _opts.get_child_count():
		(_opts.get_child(i) as Control).grab_focus()


func _refresh_presets() -> void:
	var crew: String = _sel.role()
	var cn: String = tr(str(CREW_NAMES.get(crew, crew.capitalize())))
	var pre: Dictionary = RobotBuilder.preset(crew)
	_preset_save.text = tr("Save as %s preset") % cn
	var n: int = fleet.robots_with_role(crew).size() if fleet else 0
	_preset_apply.text = tr("Fit preset on crew (%d)") % n
	_preset_apply.disabled = pre.is_empty()
	var names: Array[String] = []
	for s: String in RobotBuilder.SLOTS:
		if pre.has(s):
			names.append(tr(str(RobotBuilder.part(str(pre[s])).get("name", ""))))
	_preset_info.text = tr("%s crew preset: %s") % [cn, ", ".join(names) if not names.is_empty() else tr("none saved")]


func _refresh_bin() -> void:
	_bin.text = tr("%d styles unlocked   ·   Parts %s") % [RobotBuilder.inv().size(), Settings.fmt(GameState.get_currency("parts"))]  # [money] [ui2]
	_haggle.text = ""  # [ui2] no rotating stall: every shop part is always listed


# --- Preview + stats -----------------------------------------------------------------------

func _candidate(id: String) -> Dictionary:
	var b: Dictionary = _sel.build.duplicate()
	if id == "":
		b.erase(_slot)
	else:
		b[_slot] = id
	return b


func _preview_candidate(id: String) -> void:
	if _sel == null or not is_instance_valid(_sel):
		return
	var cand: Dictionary = _candidate(id)
	_show_preview(cand)
	_show_stats(cand)
	if id == "":
		_info.text = tr("Stock part: no changes. The %s look of this robot type.") % Economy.tier_name(_sel.tier)
	else:
		var p: Dictionary = RobotBuilder.part(id)
		_info.text = tr(str(p.get("desc", "")))  # [ui2] cosmetic: no stat changes
		if RobotBuilder.has_set(cand) and not RobotBuilder.has_set(_sel.build):
			_info.text += "   " + tr(str(RobotBuilder.cfg().get("set_bonus", {}).get("desc", "")))


func _mods_text(mods: Dictionary) -> String:
	var bits: Array[String] = []
	for k: String in mods:
		var pct: int = int(round((float(mods[k]) - 1.0) * 100.0))
		if pct != 0:
			bits.append("%s%d%% %s" % ["+" if pct > 0 else "", pct, RobotBuilder.stat_name(k)])
	return ("(" + ", ".join(bits) + ")") if not bits.is_empty() else ""


func _show_preview(build: Dictionary, empty: bool = false) -> void:
	var type_id: String = _sel.type_id if not empty else "scoopie"
	var tier: int = _sel.tier if not empty else 2
	var key: String = "%s/%d/%s" % [type_id, tier, JSON.stringify(build)]
	if key == _pv_key:
		return
	_pv_key = key
	if _pv:
		_pivot.remove_child(_pv)
		_pv.queue_free()
	_pv = RobotVisual.new()
	_pivot.add_child(_pv)
	_pv.build(type_id, str(Economy.robot_tiers[clampi(tier, 0, Economy.robot_tiers.size() - 1)].get("look", "salvage")))
	RobotKit.fit(_pv, build, _sel.role() if not empty else "clean")


func _show_stats(cand: Dictionary) -> void:
	for c: Node in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	var trait_id: String = RobotBuilder.trait_of(_sel)
	var now_m: Dictionary = RobotBuilder.concrete_mods(_sel.build, trait_id)
	var new_m: Dictionary = RobotBuilder.concrete_mods(cand, trait_id)
	var role: String = _sel.role()
	for row: Array in ROLE_STATS.get(role, ROLE_STATS["clean"]):
		var s: String = row[0]
		var cur: float
		var nxt: float
		if s == "scan":
			cur = 100.0 * float(now_m.get("scan", 1.0))
			nxt = 100.0 * float(new_m.get("scan", 1.0))
		else:
			cur = _sel.stat(s)
			nxt = cur / float(now_m.get(s, 1.0)) * float(new_m.get(s, 1.0))
		if s == "carry":
			cur = round(cur)
			nxt = round(nxt)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var nl := UITheme.label(tr(str(row[1])), 14, UITheme.CREAM)
		nl.custom_minimum_size = Vector2(120, 0)
		hb.add_child(nl)
		var fmt: String = "%.0f" if s in ["scan", "carry", "capacity", "tank"] else "%.2f"
		var vl := UITheme.label((fmt % cur) + str(row[2]), 14, Color.WHITE)
		vl.custom_minimum_size = Vector2(96, 0)
		hb.add_child(vl)
		var diff: float = nxt / maxf(cur, 0.0001) - 1.0
		if absf(nxt - cur) > 0.0001:
			hb.add_child(UITheme.label("→  " + (fmt % nxt) + str(row[2]), 14, UITheme.GREEN if diff > 0.0 else BAD))
			hb.add_child(UITheme.label("%s%d%%" % ["+" if diff > 0.0 else "", int(round(diff * 100.0))], 13, UITheme.GREEN if diff > 0.0 else BAD))
		_stats.add_child(hb)


func _process(delta: float) -> void:
	_t += delta
	if _pivot:
		_pivot.rotation.y = _t * 0.55
	if _pv:
		_pv.animate(0.0, false, delta)
	_bin_t -= delta
	if _bin_t <= 0.0 and fleet and fleet.robots().size() != _robot_btns.size() and not locker_mode:
		# Robots built or restored while the panel exists.
		if _sel == null or not is_instance_valid(_sel):
			var bl: Array[Robot] = _bots()
			_sel = bl[0] if not bl.is_empty() else null
		_pv_key = ""
		_rebuild_robot_list()
		_refresh_all()
	if _bin_t <= 0.0 and _sel:
		_bin_t = 1.0
		_refresh_bin()
		# Builds can change outside this panel (crew presets, save restore, dev hooks).
		if is_instance_valid(_sel) and _key(_sel) != _sel_key:
			_pv_key = ""
			_rebuild_robot_list()
			_refresh_all()
	if not _dev_done and DevHooks.has("builder-slot"):
		_dev_done = true
		var bots: Array[Robot] = _bots()
		var bi: int = int(DevHooks.get_f("builder-robot", 0.0))
		if bi < bots.size():
			_select(bots[bi])
		_set_slot(DevHooks.get_s("builder-slot", "mobility"))
		_focus_option(int(DevHooks.get_f("builder-opt", 1.0)))


func _key(r: Robot) -> String:
	return "%s|%s|%s" % [r.robot_name, JSON.stringify(r.build), r.trait_id]


# --- Actions -------------------------------------------------------------------------------

## [ui2] The Locker's bot selector picks the robot being edited.
func select_robot(r: Robot) -> void:
	_select(r)


func selected() -> Robot:
	return _sel


func _select(r: Robot) -> void:
	if r == _sel:
		return
	_sel = r
	_pv_key = ""
	_refresh_all()


func _set_slot(s: String) -> void:
	if s == _slot:
		return
	_slot = s
	_refresh_all()


func _on_option(id: String) -> void:
	if _sel == null:
		return
	if id != "" and id != str(_sel.build.get(_slot, "")) and RobotBuilder.count(id) <= 0:
		var why: String = RobotBuilder.obtain(id)
		if why != "":
			Audio.play("buzz", 1.2, -8.0)
			EventBus.toast.emit("%s: %s" % [tr(str(RobotBuilder.part(id).get("name", id))), why], "info")
			return
	var err: String = RobotBuilder.equip(_sel, _slot, id)
	if err != "":
		Audio.play("buzz", 1.2, -8.0)
		EventBus.toast.emit(err, "info")
		return
	_pv_key = ""
	_refresh_all()


func _on_save_preset() -> void:
	if _sel == null:
		return
	RobotBuilder.save_preset(_sel.role(), _sel.build)
	EventBus.toast.emit(tr("Saved %s's build as the %s crew preset.") % [_sel.robot_name, tr(str(CREW_NAMES.get(_sel.role(), "")))], "hint")
	_refresh_all()


func _on_apply_preset() -> void:
	if _sel == null:
		return
	var n: int = RobotBuilder.apply_preset(fleet, _sel.role())
	EventBus.toast.emit(tr_n("Fitted %d part across the %s crew.", "Fitted %d parts across the %s crew.", n) % [n, tr(str(CREW_NAMES.get(_sel.role(), "")))] if n > 0 else tr("Nothing to fit: the bin is short of those parts, or the crew already has them."), "hint")
	_pv_key = ""
	_refresh_all()


func _rename(t: String) -> void:
	if _sel == null:
		return
	var err: String = RobotBuilder.rename(fleet, _sel, t)
	if err != "":
		Audio.play("buzz", 1.2, -8.0)
		EventBus.toast.emit(err, "info")
	_name_edit.text = _sel.robot_name
	_refresh_all()
