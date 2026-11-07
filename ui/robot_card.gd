class_name RobotCard
extends PanelContainer
## [ui2] Bots tab card for one robot type, built like the Lumi cards: role icon, name, one line
## of what it does, its spots (crew spots filled / free, Mk steps) and two big buttons:
## Build (Parts + cubes) and Upgrade to the next Mk (Parts + cubes). A type that still needs
## research shows one Unlock line and a button to the Research tab.

signal goto_tab(id: String)

const ROLE_ICON: Dictionary = {"clean": "scoop", "haul": "cube", "plant": "plant", "water": "water", "skim": "water", "any": "star"}

var type_id: String
var fleet: Fleet
var build_at: Callable

var _title: Label
var _tier_lbl: Label
var _desc: Label
var _crew_pips: BenchKit.Pips
var _crew_lbl: Label
var _mk_pips: BenchKit.Pips
var _mk_lbl: Label
var _extra: Label
var _build: Button
var _build_cost: BenchKit.CostRow
var _tier_btn: Button
var _tier_cost: BenchKit.CostRow
var _why: Label
var _spots: VBoxContainer
var _actions: HBoxContainer
var _lock_row: VBoxContainer
var _lock_lbl: Label
var _lock_btn: Button
var _col: Color


func _init(p_type: String, p_fleet: Fleet, p_build_at: Callable) -> void:
	type_id = p_type
	fleet = p_fleet
	build_at = p_build_at


func _ready() -> void:
	custom_minimum_size = Vector2(420, 0)
	var role: String = str(Economy.robots[type_id].get("role", "clean"))
	_col = RobotBuilder.CREW_COLORS.get(role, UITheme.GOLD)
	add_theme_stylebox_override("panel", UITheme.box(BenchKit.CARD_BG, Color(1, 1, 1, 0.1), 1, 12, 16))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	top.add_child(BenchKit.Glyph.new(str(ROLE_ICON.get(role, "star")), 52, _col))
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	top.add_child(tv)
	var tr_row := HBoxContainer.new()
	tv.add_child(tr_row)
	_title = BenchKit.title(tr(str(Economy.robots[type_id]["name"])))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_row.add_child(_title)
	_tier_lbl = UITheme.label("", 20, _col)
	tr_row.add_child(_tier_lbl)
	_desc = BenchKit.body(tr(str(Economy.robots[type_id].get("desc", ""))), UITheme.MUTED, BenchKit.SMALL_SIZE + 1)
	tv.add_child(_desc)
	# Spots: crew (built / free) and Mk steps.
	_spots = VBoxContainer.new()
	_spots.add_theme_constant_override("separation", 6)
	vb.add_child(_spots)
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 12)
	_spots.add_child(cr)
	var cl: Label = UITheme.label(tr("Crew"), BenchKit.SMALL_SIZE + 1, UITheme.CREAM)
	cl.custom_minimum_size = Vector2(64, 0)
	cr.add_child(cl)
	_crew_pips = BenchKit.Pips.new(3, false, _col)
	cr.add_child(_crew_pips)
	_crew_lbl = UITheme.label("", BenchKit.SMALL_SIZE, UITheme.MUTED)
	_crew_lbl.clip_text = true
	_crew_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cr.add_child(_crew_lbl)
	var mr := HBoxContainer.new()
	mr.add_theme_constant_override("separation", 12)
	_spots.add_child(mr)
	var ml: Label = UITheme.label(tr("Tier"), BenchKit.SMALL_SIZE + 1, UITheme.CREAM)
	ml.custom_minimum_size = Vector2(64, 0)
	mr.add_child(ml)
	_mk_pips = BenchKit.Pips.new(Economy.robot_tiers.size(), true, _col)
	mr.add_child(_mk_pips)
	_mk_lbl = UITheme.label("", BenchKit.SMALL_SIZE, UITheme.MUTED)
	_mk_lbl.clip_text = true
	_mk_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mr.add_child(_mk_lbl)
	_extra = BenchKit.body("", UITheme.MUTED, BenchKit.SMALL_SIZE)
	_extra.visible = false
	vb.add_child(_extra)
	# Actions: Build and Upgrade, each with its cost under it.
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 12)
	vb.add_child(_actions)
	var bcol := VBoxContainer.new()
	bcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bcol.add_theme_constant_override("separation", 6)
	_actions.add_child(bcol)
	_build = BenchKit.big_button(tr("Build"))
	_build.pressed.connect(_on_build)
	bcol.add_child(_build)
	_build_cost = BenchKit.CostRow.new(20, 18)
	_build_cost.alignment = BoxContainer.ALIGNMENT_CENTER
	bcol.add_child(_build_cost)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.add_theme_constant_override("separation", 6)
	_actions.add_child(tcol)
	_tier_btn = BenchKit.soft_button("")
	_tier_btn.pressed.connect(_on_tier)
	tcol.add_child(_tier_btn)
	_tier_cost = BenchKit.CostRow.new(20, 18)
	_tier_cost.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_child(_tier_cost)
	_why = UITheme.label("", BenchKit.SMALL_SIZE, BenchKit.SHORT)
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.custom_minimum_size.x = 100
	vb.add_child(_why)
	# Locked: one line and a way to the Research tab.
	_lock_row = VBoxContainer.new()
	_lock_row.add_theme_constant_override("separation", 8)
	vb.add_child(_lock_row)
	_lock_lbl = BenchKit.body("", UITheme.CREAM)
	_lock_row.add_child(_lock_lbl)
	_lock_btn = BenchKit.soft_button(tr("Open Research"))
	_lock_btn.pressed.connect(func() -> void: goto_tab.emit("research"))
	_lock_row.add_child(_lock_btn)
	refresh()


func first_button() -> Button:
	return _build if _actions.visible else _lock_btn


func refresh() -> void:
	var t: int = fleet.tier_of(type_id)
	var n: int = fleet.count(type_id)
	_tier_lbl.text = Economy.tier_name(t)
	var locked: bool = not Research.robot_unlocked(type_id)
	_spots.visible = not locked
	_actions.visible = not locked
	_lock_row.visible = locked
	_tier_lbl.visible = not locked
	modulate = Color(1, 1, 1, 0.72) if locked else Color.WHITE
	if locked:
		_lock_lbl.text = tr("Unlock with research: %s") % tr(str(Research.def(Research.robot_requirement(type_id)).get("name", "?")))
		_why.visible = false
		_extra.visible = false
		add_theme_stylebox_override("panel", UITheme.box(BenchKit.CARD_BG, Color(1, 1, 1, 0.08), 1, 12, 16))
		return
	# Crew spots: robots in this type's crew vs the cap (a multibot can join any crew with room).
	var crew: String = Fleet.crew_of_type(type_id)
	var cap: int = fleet.crew_cap()
	var in_crew: int = fleet.crew_size(crew)
	_crew_pips.set_counts(mini(in_crew, cap), cap)
	_crew_lbl.text = (tr("%d built  ·  full: more spots with hub levels") % n) if in_crew >= cap else (tr("%d built  ·  %d free") % [n, cap - in_crew])
	_mk_pips.set_counts(t + 1, Economy.robot_tiers.size())
	if str(Economy.robots[type_id].get("role", "")) == "water" and fleet.water_net and n > 0:
		var wn: WaterNet = fleet.water_net
		_extra.text = tr("Water Tanks %d / %d  ·  place them from the Command view") % [wn.tanks.size(), int(WaterNet.cfg().get("max", 6))]
		_extra.visible = true
	else:
		_extra.visible = false
	var why: String = fleet.build_block_reason(type_id)
	_build.text = tr("Build") if n > 0 else tr("Build first")
	_build.disabled = why != ""
	_build_cost.set_cost({"cubes": fleet.build_cost(type_id).to_float(), "parts": fleet.build_parts(type_id).to_float()})
	var req: Dictionary = fleet.tier_requirements(type_id)
	var tier_ok: bool = false
	if req.get("maxed", false):
		_mk_lbl.text = tr("top tier")
		_tier_btn.text = tr("Top tier")
		_tier_btn.disabled = true
		_tier_cost.set_cost({}, " ")
	else:
		var nt: Dictionary = req["next"]
		_mk_lbl.text = tr("next: x%s work speed") % str(snappedf(float(nt["mult"]), 0.1))
		_tier_btn.text = tr("Upgrade to %s") % tr(str(nt["name"]))
		tier_ok = bool(req["ok"]) and n > 0
		_tier_btn.disabled = not tier_ok
		_tier_cost.set_cost({"cubes": (req["cost"] as BigNum).to_float(), "parts": (req["parts"] as BigNum).to_float()})
		_tier_btn.tooltip_text = "" if tier_ok or n == 0 else str(req["reason"])
	if tier_ok:
		UITheme.orange_button(_tier_btn)
	else:
		for st: String in ["normal", "hover", "pressed", "disabled"]:
			_tier_btn.remove_theme_stylebox_override(st)
	# One short line on what blocks the Build (crew full, short of parts / cubes).
	_why.text = why
	_why.visible = why != ""
	var ready: bool = why == "" or tier_ok
	add_theme_stylebox_override("panel", UITheme.box(BenchKit.CARD_BG, Color(_col, 0.55) if ready else Color(1, 1, 1, 0.1), 2 if ready else 1, 12, 16))


func _on_build() -> void:
	var r: Robot = fleet.build(type_id, build_at.call())
	if r:
		Audio.play("buy", 1.0, -2.0)
		Audio.play("confirm", 1.0, -6.0)
	else:
		Audio.play("buzz", 1.2, -8.0)
	refresh()


func _on_tier() -> void:
	if fleet.upgrade_tier(type_id):
		Audio.play("buy", 0.9, -2.0)
	else:
		Audio.play("buzz", 1.2, -8.0)
	refresh()
