class_name RobotCard
extends PanelContainer
## Workshop card for one robot type: description, fleet size, parts recipe (have/missing with
## where-to-find hints), Build button, and the Mk tier panel (requirements + Upgrade).

var type_id: String
var fleet: Fleet
var build_at: Callable

var _title: Label
var _desc: Label
var _slots: VBoxContainer
var _crew: Label
var _build: Button
var _tier: Label
var _tier_req: Label
var _tier_btn: Button


func _init(p_type: String, p_fleet: Fleet, p_build_at: Callable) -> void:
	type_id = p_type
	fleet = p_fleet
	build_at = p_build_at


func _ready() -> void:
	custom_minimum_size = Vector2(330, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	_title = UITheme.label("", 21)
	vb.add_child(_title)
	_desc = UITheme.label(str(Economy.robots[type_id].get("desc", "")), 14, UITheme.MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_desc)
	_crew = UITheme.label("", 13, UITheme.CREAM)
	_crew.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_crew)
	vb.add_child(UITheme.label("PARTS", 12, UITheme.MUTED))
	_slots = VBoxContainer.new()
	vb.add_child(_slots)
	_build = Button.new()
	_build.custom_minimum_size = Vector2(0, 44)
	_build.pressed.connect(_on_build)
	vb.add_child(_build)
	var sep := HSeparator.new()
	vb.add_child(sep)
	_tier = UITheme.label("", 16, UITheme.CREAM)
	vb.add_child(_tier)
	_tier_req = UITheme.label("", 13, UITheme.MUTED)
	_tier_req.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_tier_req)
	_tier_btn = Button.new()
	_tier_btn.custom_minimum_size = Vector2(0, 40)
	_tier_btn.pressed.connect(_on_tier)
	vb.add_child(_tier_btn)
	refresh()


func first_button() -> Button:
	return _build


func refresh() -> void:
	var def: Dictionary = Economy.robots[type_id]
	var t: int = fleet.tier_of(type_id)
	_title.text = "%s   ·   %s   ·   %d built" % [def["name"], Economy.tier_name(t), fleet.count(type_id)]
	for c: Node in _slots.get_children():
		c.queue_free()
	for r: Dictionary in fleet.recipe_status(type_id):
		var row := UITheme.label("", 14)
		if r["have"]:
			var rar: Dictionary = Economy.rarity(int(r["rarity"]))
			row.text = "■  %s  ·  %s" % [r["name"], rar.get("name", "")]
			row.add_theme_color_override("font_color", Color.html(str(rar.get("color", "#ffffff"))))
		else:
			row.text = "□  %s  ·  missing  (detector, or salvage from electronics junk)" % r["name"]
			row.add_theme_color_override("font_color", UITheme.MUTED)
		_slots.add_child(row)
	var crew: String = Fleet.crew_of_type(type_id)
	var cap: int = fleet.crew_cap()
	var n: int = fleet.crew_size(crew)
	_crew.text = "Crew: %d / %d  (hub level %d: +%d per level)" % [n, cap, fleet.base_level(), int(Economy.robot_cfg.get("crew_cap", {}).get("per_level", 3))]
	_crew.add_theme_color_override("font_color", UITheme.GOLD if n >= cap else UITheme.CREAM)
	if role_is_water() and fleet.water_net:
		var wn: WaterNet = fleet.water_net
		_crew.text += "\nWater Tanks: %d / %d placed · next %s cubes (Command view: Place refill tank)" % [wn.tanks.size(), int(WaterNet.cfg().get("max", 6)), Settings.fmt(wn.tank_cost())]
	var why: String = fleet.build_block_reason(type_id)
	_build.text = "Build   %s cubes" % Settings.fmt(fleet.build_cost(type_id)) if why == "" or why == "Not enough cubes" else "Build   (%s)" % why
	_build.disabled = not fleet.can_build(type_id)
	if not Research.robot_unlocked(type_id):
		# Blueprint not researched yet (data/robots.json "requires_research").
		_build.text = "Locked  ·  research %s" % Research.def(Research.robot_requirement(type_id)).get("name", "?")
		_build.disabled = true
	var req: Dictionary = fleet.tier_requirements(type_id)
	if req.get("maxed", false):
		_tier.text = "Fleet tier: %s (max)" % Economy.tier_name(t)
		_tier_req.text = ""
		_tier_btn.visible = false
	else:
		var nt: Dictionary = req["next"]
		_tier.text = "Next: %s  ·  x%.1f work speed  ·  %s look" % [nt["name"], float(nt["mult"]), str(nt["look"])]
		_tier_req.text = "Needs %s cubes, %s bolts and a %s Control Core.  %s" % [Settings.fmt(req["cost"]), Settings.fmt(req["bolts"]), Economy.rarity(int(req["core_rarity"])).get("name", "?"), req["reason"]]
		_tier_btn.visible = true
		_tier_btn.text = "Upgrade fleet to %s" % nt["name"]
		_tier_btn.disabled = not req["ok"]


func role_is_water() -> bool:
	return str(Economy.robots[type_id].get("role", "")) == "water"


func _on_build() -> void:
	if not Research.robot_unlocked(type_id):
		Audio.play("buzz", 1.2, -8.0)
		return
	var r: Robot = fleet.build(type_id, build_at.call())
	if r:
		Audio.play("buy", 1.0, -2.0)
	else:
		Audio.play("buzz", 1.2, -8.0)
	refresh()


func _on_tier() -> void:
	if fleet.upgrade_tier(type_id):
		Audio.play("buy", 0.9, -2.0)
	else:
		Audio.play("buzz", 1.2, -8.0)
	refresh()
