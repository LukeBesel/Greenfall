class_name EasterEggs
extends Node3D
## Small original secrets spread through the districts (data/eggs.json). Each district gets a
## deterministic set of eggs at deterministic spots (seeded by the district's field seed).
## Found eggs give a toast, a small reward, a WREN line, flags["egg_<id>"] and stats.eggs_found;
## they stay in the world afterwards as little landmarks you can still poke.

var world: Node
var defs: Dictionary = {}
var order: Array[String] = []
var placed: Array[Dictionary] = []  # {id, part, node, def, hex, final}
var _tick: float = 0.0
var _t: float = 0.0
var _stars: Node3D
var _star_mat: StandardMaterial3D
var _jukebox_player: AudioStreamPlayer3D
var _jukebox_node: Node3D
var _note_t: float = 0.0
var _watch: Dictionary = {}  # id -> seconds watched
var _ring_cd: float = 0.0
var _scoop_cd: Dictionary = {}


func setup() -> void:
	var data: Dictionary = Economy.read_json("res://data/eggs.json")
	for e: Dictionary in data.get("eggs", []):
		defs[str(e["id"])] = e
		order.append(str(e["id"]))
	StorySfx.ensure()
	var ids: Array[String] = district_eggs(order, defs, GameState.current_hub, world.field.seed_value, int(data.get("per_district", 9)))
	var avoid: Array[Vector3] = [Vector3.ZERO, FirstSeed.GREENHOUSE_POS, Intro.POD_POS]
	avoid.append((LedgerArc.relay_spot(world.field)["pos"] as Vector3))
	var plan: Array[Dictionary] = plan_spots(world.field, ids, defs, avoid)
	for p: Dictionary in plan:
		_spawn(p)
	print("[eggs] district %d: %d eggs, %d props placed" % [GameState.current_hub, ids.size(), placed.size()])
	if _jukebox_node:
		StorySfx.prewarm_music_box()
	_build_stars()
	EventBus.junk_scooped.connect(_on_scooped)
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: _refresh_visibility())
	_refresh_visibility()
	if DevHooks.has("spawn-egg"):
		_dev_spawn.call_deferred(DevHooks.get_s("spawn-egg", "duck"))


# --- Placement (pure, deterministic) -------------------------------------------------

## Which eggs live in a district: Old Town (hub 0) gets the starter set; others a seeded pick.
static func district_eggs(all_ids: Array[String], all_defs: Dictionary, hub: int, seed_v: int, per_district: int) -> Array[String]:
	var out: Array[String] = []
	if hub == 0:
		for id: String in all_ids:
			if bool(all_defs[id].get("starter", false)):
				out.append(id)
		return out
	var r := RandomNumberGenerator.new()
	r.seed = seed_v + 313
	var pool: Array[String] = all_ids.duplicate()
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = r.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for i: int in mini(per_district, pool.size()):
		out.append(pool[i])
	return out


## Deterministic spots for every part of every egg. Open ground (lots, sidewalks; roads only as
## a fallback), away from the hub yard, buildings, junk mounds, water, landmarks and each other.
static func plan_spots(field: HexField, ids: Array[String], all_defs: Dictionary, avoid: Array[Vector3]) -> Array[Dictionary]:
	var r := RandomNumberGenerator.new()
	r.seed = field.seed_value + 9091
	var used: Array[Vector3] = avoid.duplicate()
	var out: Array[Dictionary] = []
	var hexes: Array[int] = []
	for id: int in field.hex_count():
		if field.hex_hub[id] == 0 and not field.is_water(id):
			hexes.append(id)
	if hexes.is_empty():
		return out
	for egg_id: String in ids:
		var d: Dictionary = all_defs[egg_id]
		var n_parts: int = int(d.get("parts", 1))
		var has_final: bool = d.has("final")
		var wide: float = 2.8 if str(d.get("kind", "")) in ["mural", "bench_bots"] else 0.8
		for part: int in n_parts + (1 if has_final else 0):
			var best := Vector3.INF
			var best_hex: int = -1
			for attempt: int in 90:
				var hid: int = hexes[r.randi() % hexes.size()]
				var p: Vector3 = field.hex_center(hid) + Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)) * field.hex_size * 0.7
				if field.hex_at(p) != hid or Vector2(p.x, p.z).length() < 15.0:
					continue
				if not _open_ground(field, p, wide, attempt > 60):
					continue
				var min_d: float = 9.0 if attempt < 50 else 5.0
				var clash: bool = false
				for u: Vector3 in used:
					if Vector2(u.x - p.x, u.z - p.z).length() < min_d:
						clash = true
						break
				if not clash:
					for lm: Dictionary in field.landmarks:
						if (lm["pos"] as Vector3).distance_to(Vector3(p.x, (lm["pos"] as Vector3).y, p.z)) < 3.5:
							clash = true
							break
				if not clash:
					for pile: Vector4 in field.hex_piles[hid]:
						if Vector2(p.x - pile.x, p.z - pile.y).length() < pile.z + 1.0:
							clash = true
							break
				if clash:
					continue
				best = p
				best_hex = hid
				break
			if best == Vector3.INF:
				continue
			best.y = clampf(field.layout.height_at(best.x, best.z), 0.0, 0.3) if field.layout else 0.0
			used.append(best)
			# Face back toward the hub (where Patch usually comes from), with a little wobble.
			var yaw: float = atan2(-best.x, -best.z) + r.randf_range(-0.35, 0.35)
			out.append({"id": egg_id, "part": part, "final": has_final and part == n_parts, "pos": best, "yaw": yaw, "hex": best_hex})
	return out


static func _open_ground(field: HexField, p: Vector3, wide: float, allow_road: bool) -> bool:
	if field.layout == null:
		return true
	var probes: Array[Vector3] = [Vector3.ZERO, Vector3(wide, 0, 0), Vector3(-wide, 0, 0), Vector3(0, 0, wide), Vector3(0, 0, -wide)]
	# Keep clear of facades too (gaps between buildings read as doorways): a ring at 2.4 m.
	for k: int in 8:
		probes.append(Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * maxf(2.4, wide + 0.8))
	for o: Vector3 in probes:
		var s: int = field.layout.surface_at(p.x + o.x, p.z + o.z)
		if s == CityLayout.Surface.BUILDING or s == CityLayout.Surface.YARD:
			return false
		if s == CityLayout.Surface.ROAD and not allow_road and o == Vector3.ZERO:
			return false
	return true


# --- Spawning ------------------------------------------------------------------------

static func is_found(id: String) -> bool:
	return bool(GameState.flags.get("egg_" + id, false))


static func found_count() -> int:
	return (GameState.flags.get("eggs_found", []) as Array).size()


func _parts_seen(id: String) -> Array:
	return GameState.flags.get("egg_%s_parts" % id, [])


func _spawn(p: Dictionary) -> void:
	var d: Dictionary = defs[str(p["id"])]
	var kind: String = str(d.get("final", "")) if bool(p["final"]) else str(d.get("kind", ""))
	var node: Node3D = EggProps.build(kind, int(p["part"]))
	node.name = "Egg_%s_%d" % [p["id"], p["part"]]
	add_child(node)
	node.global_position = p["pos"]
	node.rotation.y = float(p["yaw"])
	var e: Dictionary = p.duplicate()
	e["node"] = node
	e["def"] = d
	e["kind"] = kind
	placed.append(e)
	if kind == "jukebox":
		_jukebox_node = node
	var prompt: String = str(d.get("final_prompt", "")) if bool(p["final"]) else str(d.get("prompt", ""))
	if prompt != "" and world.get("interactables") != null:
		world.interactables.register(node, float(d.get("use_range", 2.6)), prompt, _use.bind(e))


func _refresh_visibility() -> void:
	for e: Dictionary in placed:
		var n: Node3D = e["node"]
		var id: String = e["id"]
		var trig: String = str(e["def"].get("trigger", ""))
		if trig == "clean":
			var was: bool = n.visible
			n.visible = is_found(id) or world.field.is_clean(int(e["hex"]))
			if n.visible and not was and not is_found(id):
				Vfx.burst("sparkle", n.global_position + Vector3(0, 0.5, 0), Color(0.6, 0.95, 1.0))
				EventBus.toast.emit("Something metal surfaced in the cleared ground.", "info")
		elif bool(e["final"]):
			n.visible = is_found(id) or _parts_seen(id).size() >= int(e["def"].get("parts", 1))


func _dev_spawn(id: String) -> void:
	for e: Dictionary in placed:
		if e["id"] == id and (not bool(e["final"]) or id != "lost_cat"):
			var n: Node3D = e["node"]
			n.visible = true
			var fwd: Vector3 = n.global_transform.basis.z
			var p: Vector3 = n.global_position + fwd * float(DevHooks.get_f("egg-dist", 2.4)) + n.global_transform.basis.x * 1.5
			world.patch.global_position = Vector3(p.x, n.global_position.y + 0.2, p.z)
			world.patch.rotation.y = atan2(p.x - n.global_position.x, p.z - n.global_position.z)  # -Z (forward) toward the egg
			world.cam.yaw = world.patch.rotation.y + DevHooks.get_f("egg-yaw", 0.4)
			world.cam.snap()
			if DevHooks.has("egg-poke"):
				get_tree().create_timer(DevHooks.get_f("egg-poke", 0.5), false).timeout.connect(func() -> void: _effect(e))
			print("[eggs] spawned next to %s at %s (patch %s, yaw %.2f)" % [id, str(n.global_position), str(world.patch.global_position), world.patch.rotation.y])
			return
	print("[eggs] egg '%s' is not placed in this district (placed: %s)" % [id, str(placed.map(func(e: Dictionary) -> String: return e["id"]))])


# --- Stars (the WREN constellation) -----------------------------------------------------

const STAR_PATTERN: Array = [
	# The bird: five stars.
	[0.0, 3.2], [1.2, 3.8], [2.2, 3.4], [3.0, 3.9], [1.6, 2.6],
]
const LETTERS: Dictionary = {
	"W": [[0, 4], [0.25, 2], [0.5, 0], [1, 2], [1.5, 0], [1.75, 2], [2, 4]],
	"R": [[0, 0], [0, 1.3], [0, 2.6], [0, 4], [1, 4], [1.6, 3.2], [1, 2.2], [0.8, 2.2], [1.6, 0]],
	"E": [[1.5, 4], [0.7, 4], [0, 4], [0, 2.7], [0, 1.3], [0, 0], [0.7, 0], [1.5, 0], [0.8, 2]],
	"N": [[0, 0], [0, 1.3], [0, 2.6], [0, 4], [0.7, 2.6], [1.3, 1.3], [2, 0], [2, 1.3], [2, 2.6], [2, 4]],
}


func _build_stars() -> void:
	_stars = Node3D.new()
	_stars.name = "WrenConstellation"
	add_child(_stars)
	_star_mat = StandardMaterial3D.new()
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_star_mat.disable_fog = true
	_star_mat.albedo_texture = LedgerDrone._shadow_tex()
	_star_mat.albedo_color = Color(0.85, 0.92, 1.0, 0.0)
	var q := QuadMesh.new()
	q.size = Vector2(3.2, 3.2)
	var pts: Array[Vector2] = []
	for s: Array in STAR_PATTERN:
		pts.append(Vector2(float(s[0]) * 6.0, float(s[1]) * 6.0))
	var x0: float = -6.0
	for ch: String in "WREN":
		for s: Array in LETTERS[ch]:
			pts.append(Vector2(x0 + float(s[0]) * 2.4, float(s[1]) * 2.4 - 4.0))
		x0 += 6.5
	# Big bird stars a bit brighter.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = pts.size()
	for i: int in pts.size():
		var sc: float = 1.6 if i < STAR_PATTERN.size() else 0.75
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3(pts[i].x, pts[i].y, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _star_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 400.0
	_stars.add_child(mmi)
	# High in the north-east sky over Old Town.
	_stars.position = Vector3(110, 170, -190)
	_stars.look_at_from_position(_stars.position, Vector3.ZERO, Vector3.UP)
	_stars.rotate_object_local(Vector3.UP, PI)


func _night_amount() -> float:
	if world.get("sky_director") == null:
		return 0.0
	var tod: float = world.sky_director.time_of_day
	# 0 = midnight. Fully visible 21:00-03:00, fading around dusk and dawn.
	var d: float = minf(tod, 1.0 - tod)  # distance from midnight in days
	return clampf((0.17 - d) / 0.06, 0.0, 1.0)


# --- Triggers ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_ring_cd = maxf(0.0, _ring_cd - delta)
	if _star_mat:
		var boost: float = 1.0 if is_found("stars") else 0.55
		_star_mat.albedo_color.a = _night_amount() * boost * (0.85 + 0.15 * sin(_t * 1.7))
	_animate(delta)
	_glint(delta)
	_tick += delta
	if _tick < 0.15 or world == null or world.patch == null:
		return
	var dt: float = _tick
	_tick = 0.0
	var pp: Vector3 = world.patch.global_position
	for e: Dictionary in placed:
		var n: Node3D = e["node"]
		if not n.visible:
			continue
		var d: Dictionary = e["def"]
		var id: String = e["id"]
		var dist: float = Vector2(n.global_position.x - pp.x, n.global_position.z - pp.z).length()
		match str(d.get("trigger", "")):
			"near":
				if dist < float(d.get("range", 4.0)) and not is_found(id):
					_effect(e)
					found(id)
			"chain":
				if not bool(e["final"]) and str(e["kind"]) == "gnome" and dist < float(d.get("range", 2.6)):
					_mark_part(e)
			"watched":
				if dist < float(d.get("range", 9.0)):
					_watch[id] = float(_watch.get(id, 0.0)) + dt
					if float(_watch[id]) >= float(d.get("hold", 5.0)) and not is_found(id):
						_effect(e)
						found(id)
				else:
					_watch[id] = 0.0
		if str(e["kind"]) == "payphone" and dist < 9.0 and dist > 2.5 and _ring_cd <= 0.0 and not is_found(id):
			_ring_cd = 7.0
			Audio.play("phone_ring", 1.0, -8.0)
			_wobble(n.get_node_or_null("Anim"), 0.06)


var _glint_t: float = 0.0


## Unfound curiosities near Patch catch the light now and then, so they can be noticed.
func _glint(delta: float) -> void:
	_glint_t -= delta
	if _glint_t > 0.0 or world == null or world.patch == null:
		return
	_glint_t = 3.5
	var pp: Vector3 = world.patch.global_position
	for e: Dictionary in placed:
		var n: Node3D = e["node"]
		if not n.visible or is_found(str(e["id"])) or n.global_position.distance_to(pp) > 28.0:
			continue
		if str(e["kind"]) == "gnome" and int(e["part"]) in _parts_seen(str(e["id"])):
			continue
		Vfx.burst("sparkle", n.global_position + Vector3(0, 1.1, 0), Color(1.0, 0.95, 0.75), 0.35)


func _on_scooped(_type_id: String, pos: Vector3) -> void:
	for e: Dictionary in placed:
		if str(e["def"].get("trigger", "")) != "scoop_near":
			continue
		var n: Node3D = e["node"]
		if n.global_position.distance_to(pos) > float(e["def"].get("range", 6.0)):
			continue
		var id: String = e["id"]
		if float(_scoop_cd.get(id, 0.0)) > _t:
			continue
		_scoop_cd[id] = _t + (20.0 if str(e["kind"]) == "jukebox" else 8.0)
		_effect(e)
		if str(e["kind"]) != "microwave":
			found(id)


func _mark_part(e: Dictionary) -> void:
	var id: String = e["id"]
	var seen: Array = _parts_seen(id)
	var part: int = int(e["part"])
	if part in seen:
		return
	seen.append(part)
	GameState.flags["egg_%s_parts" % id] = seen
	var total: int = int(e["def"].get("parts", 1))
	var n: Node3D = e["node"]
	_hop(n.get_node_or_null("Anim"))
	Audio.play_scale("blip", seen.size() * 2, -6.0)
	var label: String = "Gnome %d / %d" % [seen.size(), total] if str(e["kind"]) == "gnome" else "%d / %d" % [seen.size(), total]
	Vfx.float_text(n.global_position + Vector3(0, 1.3, 0), label, Color(1.0, 0.9, 0.6), 1.1, 1.0)
	if seen.size() >= total:
		if e["def"].has("final"):
			_refresh_visibility()
			for f: Dictionary in placed:
				if f["id"] == id and bool(f["final"]):
					Vfx.burst("sparkle", (f["node"] as Node3D).global_position + Vector3(0, 0.5, 0), Color(1.0, 0.8, 0.5))
			EventBus.toast.emit("The last poster points somewhere close. Something orange is curled up nearby.", "info")
		else:
			_chain_complete(e)
			found(id)


func _chain_complete(e: Dictionary) -> void:
	var id: String = e["id"]
	for f: Dictionary in placed:
		if f["id"] != id:
			continue
		var g: Node3D = f["node"]
		var to: Vector3 = world.patch.global_position - g.global_position
		var tw := g.create_tween()
		tw.tween_property(g, "rotation:y", atan2(to.x, to.z), 1.2).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(_hop.bind(g.get_node_or_null("Anim")))


## Patch pressed E next to an egg.
func _use(e: Dictionary) -> void:
	var d: Dictionary = e["def"]
	var id: String = e["id"]
	var kind: String = e["kind"]
	match str(d.get("trigger", "")):
		"night":
			if _night_amount() < 0.5:
				EventBus.toast.emit("Through the telescope: just a bright, dusty sky. Come back after dark.", "info")
				Audio.play("click", 0.8, -8.0)
				return
		"chain":
			if kind == "poster":
				var posters: Array = d.get("posters", [])
				var doc: Dictionary = (posters[int(e["part"]) % posters.size()] as Dictionary).duplicate() if not posters.is_empty() else {}
				doc["header"] = "A   P O S T E R   ·   %d  O F  %d" % [int(e["part"]) + 1, int(d.get("parts", 3))]
				_mark_part(e)
				if world.get("doc_view") != null and not doc.is_empty():
					world.doc_view.show_doc(doc)
				return
	if kind == "time_capsule" and d.has("doc") and world.get("doc_view") != null:
		var doc2: Dictionary = (d["doc"] as Dictionary).duplicate()
		doc2["header"] = "T I M E   C A P S U L E   ·   L E T T E R"
		_effect(e)
		found(id)
		world.doc_view.show_doc(doc2)
		return
	if kind == "vending" and is_found(id):
		Vfx.float_text((e["node"] as Node3D).global_position + Vector3(0, 2.2, 0), "SOLD OUT", Color(1.0, 0.4, 0.3), 1.2, 1.0)
		Audio.play("buzz", 1.3, -8.0)
		_wobble(e["node"], 0.04)
		return
	_effect(e)
	found(id)


## The fun part: each egg's little reaction (also replayed after it has been found).
func _effect(e: Dictionary) -> void:
	var n: Node3D = e["node"]
	var anim: Node3D = n.get_node_or_null("Anim")
	var top: Vector3 = n.global_position + Vector3(0, 1.6, 0)
	match str(e["kind"]):
		"duck":
			Audio.play("quack", 1.0, -2.0)
			_squash(anim)
			Vfx.float_text(top, "QUACK!", Color(1.0, 0.9, 0.3), 1.3, 1.2)
			EventBus.toast.emit(_duck_hint(), "hint")
		"jukebox":
			_play_jukebox()
		"mural":
			Vfx.burst("sparkle", n.global_position + Vector3(0, 1.6, 0.4), Color(1.0, 0.8, 0.5), 1.5)
		"gnome":
			_hop(anim)
		"time_capsule":
			if anim:
				var tw := anim.create_tween()
				tw.tween_property(anim, "position:y", 0.45, 0.4).set_trans(Tween.TRANS_BACK)
				tw.tween_property(anim, "rotation_degrees:z", 90.0, 0.4)
			Audio.play("dig", 1.0, -4.0)
			Vfx.burst("soil", n.global_position + Vector3(0, 0.2, 0), Color(0.5, 0.4, 0.3))
		"arcade":
			Audio.play("arcade", 1.0, -4.0)
			_flash(n.get_node_or_null("Screen"), Color(0.4, 1.0, 0.7), 3.0)
			Vfx.float_text(top + Vector3(0, 0.6, 0), "NEW CHALLENGER!", Color(0.5, 1.0, 0.7), 1.2, 1.0)
			get_tree().create_timer(2.2, false).timeout.connect(func() -> void:
				Audio.play("arcade", 0.6, -6.0)
				Vfx.float_text(top + Vector3(0, 0.6, 0), "GAME OVER  ·  SCORE 12", Color(1.0, 0.6, 0.4), 1.1, 1.0))
		"cat_shell":
			Audio.play("purr", 1.0, -3.0)
			var eye: OmniLight3D = n.get_node_or_null("Light")
			if eye:
				var tw2 := eye.create_tween()
				tw2.tween_property(eye, "light_energy", 1.2, 0.6)
			if anim:
				var tw3 := anim.create_tween().set_loops(3)
				tw3.tween_property(anim, "scale", Vector3(1.0, 1.06, 1.0), 0.5).set_trans(Tween.TRANS_SINE)
				tw3.tween_property(anim, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_SINE)
			Vfx.float_text(n.global_position + Vector3(0, 0.9, 0), "purrrr", Color(1.0, 0.8, 0.55), 1.0, 0.8)
		"vending":
			_wobble(n, 0.05)
			Audio.play("clunk", 0.8, -2.0)
			_dispense_can(n)
		"telescope":
			if anim:
				var tw4 := anim.create_tween()
				tw4.tween_property(anim, "rotation_degrees:z", 48.0, 1.0).set_trans(Tween.TRANS_SINE)
			_look_up()
			Audio.play("sparkle", 0.7, -6.0)
		"payphone":
			Audio.play("click", 0.9, -4.0)
			_wobble(anim, 0.08)
		"tv":
			Audio.play("tv_static", 1.0, -6.0)
			_flash(n.get_node_or_null("Screen"), Color(1.0, 1.0, 1.0), 2.0)
		"snail":
			_hop(anim)
			Vfx.float_text(n.global_position + Vector3(0, 1.3, 0), "hi, Gus", Color(0.9, 1.0, 0.8), 1.0, 0.8)
		"bench_bots":
			var fl: Node3D = n.get_node_or_null("Flower")
			if fl:
				fl.visible = true
				fl.scale = Vector3.ONE * 0.05
				var tw5 := fl.create_tween()
				tw5.tween_property(fl, "scale", Vector3.ONE * 0.5, 0.6).set_trans(Tween.TRANS_BACK)
			Vfx.burst("sparkle", n.global_position + Vector3(0, 0.9, 0), Color(1.0, 0.9, 0.6), 0.6)
			Audio.play("chime", 1.3, -10.0)
		"microwave":
			for k: int in 3:
				get_tree().create_timer(0.35 * k, false).timeout.connect(func() -> void: Audio.play("ding", 1.6, -6.0, 0.0))
			_flash(n.get_node_or_null("Screen"), Color(0.3, 1.0, 0.4), 4.0)
		"wet_floor":
			_wobble(anim, 0.1)
			if world.patch.get("model") != null and world.patch.model.has_method("shudder"):
				world.patch.model.shudder(0.4)
			Audio.play("squeak", 1.0, -6.0)
		"camera":
			var led: Node3D = anim.get_node_or_null("Led") if anim else null
			if led:
				var tw6 := led.create_tween().set_loops(2)
				tw6.tween_property(led, "visible", false, 0.15)
				tw6.tween_property(led, "visible", true, 0.15)
			Audio.play("servo", 1.4, -8.0)
		"tyre_tower":
			if anim:
				var tw7 := anim.create_tween()
				for k: int in 4:
					tw7.tween_property(anim, "rotation:z", 0.06 * (1.0 if k % 2 == 0 else -1.0) * (1.0 - k * 0.2), 0.25).set_trans(Tween.TRANS_SINE)
				tw7.tween_property(anim, "rotation:z", 0.0, 0.3)
			Audio.play("squeak", 0.7, -6.0)


func _duck_hint() -> String:
	var have: Array = GameState.flags.get("skins_unlocked", ["aurora"])
	for sid: String in CosmeticsPanel.UNLOCKS:
		if not (sid in have) and PatchModel.VARIANTS.has(sid):
			return "The duck squeaks a secret: \"%s\" unlocks the %s design." % [CosmeticsPanel.UNLOCKS[sid], PatchModel.VARIANTS[sid]["name"]]
	return "The duck has taught you everything it knows. Quack."


func _play_jukebox() -> void:
	if _jukebox_node == null:
		return
	if _jukebox_player and _jukebox_player.playing:
		return
	if _jukebox_player == null:
		_jukebox_player = AudioStreamPlayer3D.new()
		_jukebox_player.bus = "SFX"
		_jukebox_player.unit_size = 6.0
		_jukebox_player.max_distance = 45.0
		_jukebox_player.volume_db = 2.0
		_jukebox_player.position = Vector3(0, 1.0, 0.3)
		_jukebox_node.add_child(_jukebox_player)
	_jukebox_player.stream = StorySfx.music_box()
	_jukebox_player.play()
	var l: OmniLight3D = _jukebox_node.get_node_or_null("Light")
	if l:
		var tw := l.create_tween()
		tw.tween_property(l, "light_energy", 2.2, 0.8)
	Audio.play("clunk", 1.4, -10.0)


func _dispense_can(n: Node3D) -> void:
	var can := EggProps.model("can_rusted", Vector3.ZERO, 0.0, 1.2)
	add_child(can)
	var start: Vector3 = n.global_position + n.global_transform.basis * Vector3(-0.1, 0.32, 0.45)
	var end: Vector3 = n.global_position + n.global_transform.basis * Vector3(0.3, 0.06, 1.2)
	can.global_position = start
	var tw := can.create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(can, "global_position", end, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(can, "rotation:z", PI * 0.5, 0.3)
	tw.tween_callback(func() -> void: Audio.play("clink", 0.9, -4.0))
	var sign: MeshInstance3D = n.get_node_or_null("Screen")
	if sign:
		_flash(sign, Color(1.0, 0.3, 0.2), 2.0)


func _look_up() -> void:
	var cam: CameraRig = world.cam
	var p0: float = cam.pitch
	var was: bool = cam.lens_view
	# Lens view allows looking up; peek at the constellation for a few seconds.
	cam.lens_view = true
	var tw := create_tween()
	tw.tween_property(cam, "pitch", 0.5, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(3.5)
	tw.tween_property(cam, "pitch", p0, 1.0).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: cam.lens_view = was)


func _hop(n: Node3D) -> void:
	if n == null:
		return
	var y0: float = n.position.y
	var tw := n.create_tween()
	tw.tween_property(n, "position:y", y0 + 0.18, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "position:y", y0, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _squash(n: Node3D) -> void:
	if n == null:
		return
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3(1.25, 0.7, 1.25), 0.08)
	tw.tween_property(n, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _wobble(n: Node3D, amt: float) -> void:
	if n == null:
		return
	var tw := n.create_tween()
	for k: int in 4:
		tw.tween_property(n, "rotation:z", amt * (1.0 if k % 2 == 0 else -1.0), 0.06)
	tw.tween_property(n, "rotation:z", 0.0, 0.08)


func _flash(n: Node3D, col: Color, energy: float) -> void:
	var mi: MeshInstance3D = n as MeshInstance3D
	if mi == null or not (mi.material_override is StandardMaterial3D):
		return
	var m: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate()
	mi.material_override = m
	var e0: float = m.emission_energy_multiplier
	var c0: Color = m.emission
	m.emission = col
	var tw := mi.create_tween()
	tw.tween_property(m, "emission_energy_multiplier", energy, 0.1)
	tw.tween_interval(1.4)
	tw.tween_property(m, "emission_energy_multiplier", e0, 0.6)
	tw.tween_callback(func() -> void: m.emission = c0)


func _animate(delta: float) -> void:
	# Jukebox: disc spins and notes float up while it plays.
	if _jukebox_player and _jukebox_player.playing and _jukebox_node:
		var disc: Node3D = _jukebox_node.get_node_or_null("Disc")
		if disc:
			disc.rotate_object_local(Vector3.UP, delta * 4.0)
		_note_t -= delta
		if _note_t <= 0.0:
			_note_t = 0.6
			var p: Vector3 = _jukebox_node.global_position + Vector3(randf_range(-0.4, 0.4), 1.9, randf_range(-0.2, 0.3))
			Vfx.float_text(p, ["♪", "♫"][randi() % 2], Color(1.0, 0.85, 0.55), 1.0, 1.2)
	elif _jukebox_node:
		var l: OmniLight3D = _jukebox_node.get_node_or_null("Light")
		if l and l.light_energy > 0.0:
			l.light_energy = maxf(0.0, l.light_energy - delta * 0.6)
	# Security camera: swivels to follow Patch when near.
	for e: Dictionary in placed:
		if str(e["kind"]) != "camera" or world.patch == null:
			continue
		var head: Node3D = (e["node"] as Node3D).get_node_or_null("Anim")
		if head == null:
			continue
		var to: Vector3 = world.patch.global_position - head.global_position
		var want: float = atan2(to.x, to.z) - (e["node"] as Node3D).global_rotation.y if Vector2(to.x, to.z).length() < float(e["def"].get("range", 9.0)) else sin(_t * 0.4) * 0.8
		head.rotation.y = lerp_angle(head.rotation.y, want, minf(delta * 2.5, 1.0))


# --- Found ---------------------------------------------------------------------------

func found(id: String) -> void:
	if is_found(id) or not defs.has(id):
		return
	var d: Dictionary = defs[id]
	GameState.flags["egg_" + id] = true
	var list: Array = GameState.flags.get("eggs_found", [])
	if not (id in list):
		list.append(id)
	GameState.flags["eggs_found"] = list
	GameState.inc_stat("eggs_found")
	var rew: Dictionary = d.get("reward", {})
	var bits: Array[String] = []
	for k: String in rew:
		GameState.add_currency(k, BigNum.from_float(float(rew[k])))
		bits.append("+%d %s" % [int(rew[k]), k if int(rew[k]) != 1 else k.trim_suffix("s")])
	var pos: Vector3 = world.patch.global_position + Vector3(0, 1.8, 0) if world and world.patch else Vector3.ZERO
	Vfx.burst("confetti", pos, Color.WHITE, 0.5)
	Audio.play("sparkle", 1.0, -4.0)
	Audio.play("chime", 1.2, -8.0)
	EventBus.toast.emit(str(d.get("toast", "")), "story")
	EventBus.toast.emit("Curiosity found: %s  (%d / %d)   %s" % [d.get("name", id), found_count(), defs.size(), "  ".join(bits)], "hint")
	EventBus.easter_egg_found.emit(id)
	if world and world.get("wren") != null:
		var w: Wren = world.wren
		get_tree().create_timer(2.5, false).timeout.connect(func() -> void:
			if w.lines.has("egg_" + id):
				w.say("egg_" + id, 1.0, true)
			else:
				w.say("egg_found", 1.0, true))
	if found_count() == defs.size():
		get_tree().create_timer(6.0, false).timeout.connect(func() -> void:
			EventBus.toast.emit("Every curiosity on the list, found. Patch's collection compartment is very full of memories.", "story"))
