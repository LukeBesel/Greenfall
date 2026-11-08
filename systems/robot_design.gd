class_name RobotDesign
extends RefCounted
## [ui7] Robot looks are designed per robot TYPE (owner: "paint all planting bots green, and every
## planting bot, existing or newly built, wears it"). The Locker's Bots section edits a type's
## design; every robot of that type wears it, including ones built later (Fleet.spawn, the
## Fabricator) and ones restored from a save.
##
## Design (GameState.flags["robot_designs"][type_id]):
##   {"parts": {slot: part_id}  (Robot Builder parts; owned parts fit every robot),
##    "livery": "" | livery id (the fleet paints won from Requests: underglow, pennant, halo),
##    "glow": "" | glow id (data below: recolours the robot's light strips)}
## A type with no design keeps the stock look (and the old fleet-wide livery, if one is equipped).

# l10n:begin
const GLOWS: Array = [
	["cyan", "Cyan", "#4cd8ff"], ["mint", "Mint", "#59f2b0"], ["amber", "Amber", "#ffb347"],
	["rose", "Rose", "#ff6f9a"], ["violet", "Violet", "#b98cff"], ["white", "Moonlight", "#e8f0ff"],
]
# l10n:end


static func _all() -> Dictionary:
	var v: Variant = GameState.flags.get("robot_designs")
	if not (v is Dictionary):
		v = {}
		GameState.flags["robot_designs"] = v
	return v


static func of(type_id: String) -> Dictionary:
	var d: Variant = _all().get(type_id, {})
	return d if d is Dictionary else {}


static func parts(type_id: String) -> Dictionary:
	return of(type_id).get("parts", {})


static func glow_color(id: String) -> Color:
	for g: Array in GLOWS:
		if str(g[0]) == id:
			return Color.html(str(g[2]))
	return Color(0, 0, 0, 0)


## Changes one field of a type's design and puts it on every robot of that type now.
static func set_field(fleet: Fleet, type_id: String, key: String, value: Variant) -> void:
	var d: Dictionary = of(type_id).duplicate(true)
	d[key] = value
	_all()[type_id] = d
	GameState.inc_stat("robot_designs_changed")
	apply_type(fleet, type_id)


## Fits a Builder part ("" = stock) into a slot of a type's design. Returns "" or why not.
static func set_part(fleet: Fleet, type_id: String, slot: String, part_id: String) -> String:
	if part_id != "":
		var p: Dictionary = RobotBuilder.part(part_id)
		if p.is_empty() or str(p.get("slot", "")) != slot:
			return TranslationServer.translate("Wrong slot")
		if not RobotBuilder.fits(part_id, type_id):
			return TranslationServer.translate("Doesn't fit a %s") % TranslationServer.translate(str(Economy.robots.get(type_id, {}).get("name", type_id)))
		if RobotBuilder.count(part_id) <= 0:
			return TranslationServer.translate("Not unlocked yet")
	var ps: Dictionary = parts(type_id).duplicate()
	if part_id == "":
		ps.erase(slot)
	else:
		ps[slot] = part_id
		GameState.inc_stat("builder_parts_fitted")
	set_field(fleet, type_id, "parts", ps)
	RobotBuilder.note_build(ps)
	return ""


## Puts the type's design on every robot of that type.
static func apply_type(fleet: Fleet, type_id: String) -> void:
	if fleet == null:
		return
	for r: Robot in fleet.robots():
		if r.type_id == type_id:
			apply(r)
	Liveries.sync(fleet)


## Puts its type's design on one robot (a fresh build, a restored save, a design change).
static func apply(r: Robot) -> void:
	if of(r.type_id).has("parts"):
		RobotBuilder.set_build(r, parts(r.type_id))  # rebuilds the visual; after_visual() recolours
	else:
		after_visual(r)


## Called after a robot's visual is (re)built: the type's glow colour on its light strips.
static func after_visual(r: Robot) -> void:
	var gid: String = str(of(r.type_id).get("glow", ""))
	if gid == "" or r.visual == null:
		return
	var col: Color = glow_color(gid)
	var mats: Variant = r.visual.get("_glow_mats")
	if mats is Array:
		for m: Variant in mats:
			if m is StandardMaterial3D:
				(m as StandardMaterial3D).emission = col
				(m as StandardMaterial3D).albedo_color = col.darkened(0.3)


## The livery a robot wears: its type's choice if the design has one, else the fleet-wide one.
static func livery_for(type_id: String) -> String:
	var d: Dictionary = of(type_id)
	return str(d["livery"]) if d.has("livery") else Liveries.equipped()
