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
var _last_recipe: Array = []


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
	_desc = UITheme.label(tr(str(Economy.robots[type_id].get("desc", ""))), 14, UITheme.MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_desc)
	_crew = UITheme.label("", 13, UITheme.CREAM)
	_crew.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_crew)
	vb.add_child(UITheme.label(tr("PARTS"), 12, UITheme.MUTED))
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
	_title.text = tr("%s   ·   %s   ·   %d built") % [tr(str(def["name"])), Economy.tier_name(t), fleet.count(type_id)]
	_refresh_slots(fleet.recipe_status(type_id))
	var crew: String = Fleet.crew_of_type(type_id)
	var cap: int = fleet.crew_cap()
	var n: int = fleet.crew_size(crew)
	_crew.text = tr("Crew: %d / %d  (hub level %d: +%d per level)") % [n, cap, fleet.base_level(), int(Economy.robot_cfg.get("crew_cap", {}).get("per_level", 3))]
	_crew.add_theme_color_override("font_color", UITheme.GOLD if n >= cap else UITheme.CREAM)
	if role_is_water() and fleet.water_net:
		var wn: WaterNet = fleet.water_net
		_crew.text += tr("\nWater Tanks: %d / %d placed · next %s cubes (Command view: Place refill tank)") % [wn.tanks.size(), int(WaterNet.cfg().get("max", 6)), Settings.fmt(wn.tank_cost())]
	var why: String = fleet.build_block_reason(type_id)
	_build.text = tr("Build   %s cubes") % Settings.fmt(fleet.build_cost(type_id)) if why == "" or why == tr("Not enough cubes") else tr("Build   (%s)") % why
	_build.disabled = not fleet.can_build(type_id)
	if not Research.robot_unlocked(type_id):
		# Blueprint not researched yet (data/robots.json "requires_research").
		_build.text = tr("Locked  ·  research %s") % tr(str(Research.def(Research.robot_requirement(type_id)).get("name", "?")))
		_build.disabled = true
	var req: Dictionary = fleet.tier_requirements(type_id)
	if req.get("maxed", false):
		_tier.text = tr("Fleet tier: %s (max)") % Economy.tier_name(t)
		_tier_req.text = ""
		_tier_btn.visible = false
	else:
		var nt: Dictionary = req["next"]
		_tier.text = tr("Next: %s  ·  x%.1f work speed  ·  %s look") % [tr(str(nt["name"])), float(nt["mult"]), str(nt["look"])]
		_tier_req.text = tr("Needs %s cubes, %s parts and a %s Control Core.  %s") % [Settings.fmt(req["cost"]), Settings.fmt(req["parts"]), tr(str(Economy.rarity(int(req["core_rarity"])).get("name", "?"))), req["reason"]]
		_tier_btn.visible = true
		_tier_btn.text = tr("Upgrade fleet to %s") % tr(str(nt["name"]))
		_tier_btn.disabled = not req["ok"]


## Recipe rows are built once and updated in place; nothing happens when the recipe is unchanged.
func _refresh_slots(recipe: Array) -> void:
	if recipe == _last_recipe and _slots.get_child_count() == recipe.size():
		return
	_last_recipe = recipe.duplicate(true)
	while _slots.get_child_count() > recipe.size():
		var old: Node = _slots.get_child(_slots.get_child_count() - 1)
		_slots.remove_child(old)
		old.queue_free()
	while _slots.get_child_count() < recipe.size():
		_slots.add_child(UITheme.label("", 14))
	for i: int in recipe.size():
		var r: Dictionary = recipe[i]
		var row: Label = _slots.get_child(i) as Label
		if r["have"]:
			var rar: Dictionary = Economy.rarity(int(r["rarity"]))
			row.text = "■  %s  ·  %s" % [tr(str(r["name"])), tr(str(rar.get("name", "")))]
			row.add_theme_color_override("font_color", UITheme.rarity_color(int(r["rarity"])))
		else:
			row.text = tr("□  %s  ·  missing  (detector, or salvage from electronics junk)") % tr(str(r["name"]))
			row.add_theme_color_override("font_color", UITheme.MUTED)


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
