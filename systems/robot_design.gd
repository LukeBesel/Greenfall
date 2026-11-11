class_name RobotDesign
extends RefCounted
## [ui7] Robot looks are designed per robot TYPE (owner: "paint all planting bots green, and every
## planting bot, existing or newly built, wears it"). The Locker's Bots section edits a type's
## design; every robot of that type wears it, including ones built later (Fleet.spawn)
## and ones restored from a save.
##
## Design (GameState.flags["robot_designs"][type_id]):
##   {"parts": {slot: part_id}  (Robot Builder parts),
##    "livery": "" | mark id (a fleet mark: underglow, pennant, halo; systems/liveries.gd),
##    "glow": "" | light id (recolours the robot's light strips)}
## Every part, mark and light is a found piece (CrewLooks, data/cosmetics.json targets.crew): only
## found ones can be put on. A type with no design keeps the stock look (and the fleet-wide mark
## of a save from before found pieces, if one is equipped).


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
	var piece: String = CrewLooks.piece(CrewLooks.CREW, CrewLooks.GLOW, id)
	return CrewLooks.color_of(piece, Color(0, 0, 0, 0)) if piece != "" else Color(0, 0, 0, 0)


## Puts a fleet mark (CrewLooks.LIVERY) or a light colour (CrewLooks.GLOW) on a type ("" = stock).
## False when that look is not found yet.
static func set_look(fleet: Fleet, type_id: String, key: String, id: String) -> bool:
	if not (key in [CrewLooks.LIVERY, CrewLooks.GLOW]):
		return false
	if id != "" and not CrewLooks.has(CrewLooks.CREW, key, id):
		return false
	_set_field(fleet, type_id, key, id)
	return true


## Changes one field of a type's design and puts it on every robot of that type now.
static func _set_field(fleet: Fleet, type_id: String, key: String, value: Variant) -> void:
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
		if not RobotBuilder.owned(part_id):
			return TranslationServer.translate("Not found yet")
	var ps: Dictionary = parts(type_id).duplicate()
	if part_id == "":
		ps.erase(slot)
	else:
		ps[slot] = part_id
		GameState.inc_stat("builder_parts_fitted")
	_set_field(fleet, type_id, "parts", ps)
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


static var _hooked: bool = false


## [ui7] Globe robots (robots/sphere/) are dressed through SphereCrew.dress_hooks: the same type
## design (parts, livery, glow) as the flat fleet's robots. Idempotent; Fleet._ready calls it.
static func register_hooks() -> void:
	if _hooked:
		return
	_hooked = true
	SphereCrew.dress_hooks.append(dress_sphere)


static func dress_sphere(body: Node3D, visual: Node3D, type_id: String, _tier: int) -> void:
	var want: String = livery_for(type_id)
	var cur: Node = body.get_node_or_null(Liveries.NODE_NAME)
	if cur and str(cur.get_meta("livery", "")) != want:
		body.remove_child(cur)
		cur.queue_free()
		cur = null
	if cur == null and want != "":
		var n: Node3D = Liveries.build(want)
		if n:
			body.add_child(n)
	if visual == null:
		return
	if of(type_id).has("parts") and visual is RobotVisual:
		RobotKit.fit(visual as RobotVisual, parts(type_id), str(Economy.robots.get(type_id, {}).get("role", "clean")))
	var gid: String = str(of(type_id).get("glow", ""))
	if gid != "":
		var col: Color = glow_color(gid)
		var mats: Variant = visual.get("_glow_mats")
		if mats is Array:
			for m: Variant in mats:
				if m is StandardMaterial3D:
					(m as StandardMaterial3D).emission = col
					(m as StandardMaterial3D).albedo_color = col.darkened(0.3)
