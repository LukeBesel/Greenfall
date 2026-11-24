class_name CdFinds
extends Node3D
## [tunes] CDs in the rubble: now and then a cleaned hex turns up an old CD in a cracked jewel
## case (only where junk was, never out of thin air). Walk over it to pick it up: the song joins
## the CD player and the shuffle (Tunes.grant, toast "New CD: <song> by <artist>").
## - Each planet's CDs are found on that planet (data/songs.json found_on); songs without an MP3
##   never drop.
## - A bit rarer than ordinary finds, with a pity counter so every CD turns up in time: the chance
##   grows with each cleaned hex since the last CD and is certain after cd_find.guarantee_hexes.
## - A CD left lying stays where it surfaced (flags.songs.pending) until Lumi picks it up.
## - Scratched CDs: rarer still, 5-10 per planet, of songs you don't own yet (other planets'
##   first; never an owned one, skipped when none qualify). Picking one up asks "Play now?" or
##   keeps it in the CD case (ui/scratched_cd_ui.gd). It plays once, then breaks.
## State: GameState.flags.songs {found, pity, pending: {song id or "s:"+id: {hub, hex, planet,
## scratched}}, scratch_left: {planet: n}, scratch_cool, scratched (held), plays}.

const PICK_R: float = 1.7
## [v10snd] The first CD (owner: "the first song should play when you find a cd in the rubble close
## by at the start"): it lies in the junk by the start pad from the first second of a new game,
## in the nearest dirty hex to the trash bin that is at least FIRST_MIN_M away, on reachable ground
## (TargetReach), hovering and glinting so it is seen over the junk. Coming within FIRST_PICK_R
## (walking or scooping there) picks it up: Tunes.find_first_cd() plays its song at once and says
## how to play CDs at will. Its hex is saved (flags.songs.pending) so it stays put over a reload.
const FIRST_KEY: String = "first:"
const FIRST_PICK_R: float = 2.4
const FIRST_MIN_M: float = 5.0
const FIRST_RINGS: int = 5
const FIRST_DISC_R: float = 0.6  # the first CD shows as a big disc on edge, turning over the junk: seen from the pad
const FIRST_DISC_UP: float = 1.0  # over the hovering spot: its middle is about Lumi's head height
const FIRST_RAY_H: float = 9.0
const OFFSET := Vector3(-0.9, 0.04, 1.1)

var world: Node
var rng := RandomNumberGenerator.new()
var _discs: Dictionary = {}  # song id -> Node3D
var _t: float = 0.0
var _spin: float = 0.0
var _first_t: float = 0.0
var _first_done: bool = false


func _ready() -> void:
	name = "CdFinds"
	rng.randomize()
	EventBus.hex_cleaned.connect(func(hid: int, _p: Vector3, _b: BigNum) -> void: on_hex_cleaned(hid))
	_restore.call_deferred()


# --- Rules (static) ----------------------------------------------------------------------

static func tuning() -> Dictionary:
	return Tunes.cfg().get("cd_find", {})


static func pending() -> Dictionary:
	var st: Dictionary = Tunes.st()
	if not (st.get("pending") is Dictionary):
		st["pending"] = {}
	return st["pending"]


static func pity() -> int:
	return int(Tunes.st().get("pity", 0))


## Chance that the next cleaned hex turns up a CD after `since` hexes without one.
static func chance(since: int) -> float:
	var c: Dictionary = tuning()
	if since + 1 >= int(c.get("guarantee_hexes", 18)):
		return 1.0
	return clampf(float(c.get("base_chance", 0.05)) + float(c.get("pity_step", 0.035)) * since, 0.0, 1.0)


## CDs that may drop here now: this planet's, not owned and not already lying in this district.
static func candidates(planet: String, hub: int) -> Array[String]:
	var out: Array[String] = []
	var pend: Dictionary = pending()
	for id: String in Tunes.cds_left(planet):
		var p: Variant = pend.get(id)
		if p is Dictionary and int((p as Dictionary).get("hub", -1)) == hub and str((p as Dictionary).get("planet", "")) == planet:
			continue
		out.append(id)
	return out


## One cleaned hex: maybe a CD (returns its id, or ""). Pure apart from the saved pity counter.
static func roll(planet: String, hub: int, r: float, pick: float) -> String:
	if float(GameState.stats.get("hexes_cleaned", 0.0)) < float(tuning().get("min_hexes", 4)):
		return ""
	var cand: Array[String] = candidates(planet, hub)
	if cand.is_empty():
		return ""
	var since: int = pity()
	if r >= chance(since):
		Tunes.st()["pity"] = since + 1
		return ""
	Tunes.st()["pity"] = 0
	return cand[clampi(int(pick * cand.size()), 0, cand.size() - 1)]


static func take(id: String) -> bool:
	pending().erase(id)
	return Tunes.grant(id)


## Scratched CDs left to find on a planet (5-10, rolled the first time it is asked).
static func scratch_left(planet: String, r: float = 0.5) -> int:
	var st: Dictionary = Tunes.st()
	if not (st.get("scratch_left") is Dictionary):
		st["scratch_left"] = {}
	var d: Dictionary = st["scratch_left"]
	if not d.has(planet):
		var span: Array = Tunes.scratch_cfg().get("per_planet", [5, 10])
		d[planet] = int(roundf(lerpf(float(span[0]), float(span[1]), clampf(r, 0.0, 1.0))))
	return int(d[planet])


## One cleaned hex: maybe a scratched CD (its song id, or ""). Rare, with a few hexes' cooldown.
static func roll_scratched(planet: String, hub: int, r: float, pick: float) -> String:
	var c: Dictionary = Tunes.scratch_cfg()
	var st: Dictionary = Tunes.st()
	if float(GameState.stats.get("hexes_cleaned", 0.0)) < float(c.get("min_hexes", 12)):
		return ""
	var cool: int = int(st.get("scratch_cool", 0))
	if cool > 0:
		st["scratch_cool"] = cool - 1
		return ""
	if scratch_left(planet, pick) <= 0 or r >= float(c.get("chance", 0.025)):
		return ""
	var cand: Array[String] = []
	for id: String in Tunes.scratch_candidates(planet):
		if not pending().has("s:" + id):
			cand.append(id)
	if cand.is_empty():
		return ""  # nothing you don't own yet: skip, and keep the quota
	(st["scratch_left"] as Dictionary)[planet] = scratch_left(planet) - 1
	st["scratch_cool"] = int(c.get("cooldown_hexes", 6))
	return cand[clampi(int(pick * cand.size()), 0, cand.size() - 1)]


# --- Live --------------------------------------------------------------------------------

func on_hex_cleaned(hid: int) -> void:
	if world == null or world.get("field") == null:
		return
	# [v10snd] The first CD can't be missed: its hex coming clean (a robot, the 95% sweep) gives it too.
	for id: String in _discs.keys():
		var fp: Variant = pending().get(id)
		if id.begins_with(FIRST_KEY) and fp is Dictionary and int((fp as Dictionary).get("hex", -1)) == hid:
			_take_first(id)
	var planet: String = SolarSystem.current_id()
	var id: String = roll(planet, GameState.current_hub, rng.randf(), rng.randf())
	if id != "":
		pending()[id] = {"hub": GameState.current_hub, "hex": hid, "planet": planet}
		_show(id, hid, true)
		return
	id = roll_scratched(planet, GameState.current_hub, rng.randf(), rng.randf())
	if id != "":
		pending()["s:" + id] = {"hub": GameState.current_hub, "hex": hid, "planet": planet, "scratched": true}
		_show("s:" + id, hid, true)


func _restore() -> void:
	if world == null or world.get("field") == null:
		return
	var planet: String = SolarSystem.current_id()
	for id: Variant in pending().keys():
		var p: Dictionary = pending()[id]
		if Tunes.is_found(str(id).trim_prefix("s:")):
			pending().erase(id)
			continue
		if int(p.get("hub", -1)) == GameState.current_hub and str(p.get("planet", "")) == planet:
			var hid: int = int(p.get("hex", -1))
			if hid >= 0 and hid < world.field.hex_count() and world.field.is_clean(hid) and not str(id).begins_with(FIRST_KEY):
				_show(str(id), hid, false)


## [v10snd] Puts the first CD out (a new game, or a save that has not found it yet) on the start
## planet's first base.
func _place_first() -> void:
	var song: String = Tunes.first_cd_id()
	if song == "" or Tunes.first_cd_found() or GameState.current_hub != 0 \
			or SolarSystem.current_id() != str(Tunes.first_cd_cfg().get("planet", "verdance")):
		return
	var key: String = FIRST_KEY + song
	var hid: int = -1
	var p: Variant = pending().get(key)
	if p is Dictionary and int((p as Dictionary).get("hub", -1)) == 0:
		hid = int((p as Dictionary).get("hex", -1))
	if hid < 0 or hid >= world.field.hex_count():
		hid = first_hex()
	if hid < 0 or world.field.is_clean(hid):  # nowhere dirty to lie, or its hex came clean: given, never lost
		pending().erase(key)
		if Tunes.find_first_cd():
			_show_card(Tunes.first_cd_text(song))
		return
	pending()[key] = {"hub": 0, "hex": hid, "planet": SolarSystem.current_id(), "first": true}
	_show(key, hid, false)


## The hex the first CD lies in: the nearest land hex to the trash bin that still has its junk, is
## not part of the base or a lake, and whose CD spot is at least FIRST_MIN_M from the bin. -1 if none.
func first_hex() -> int:
	var f: HexField = world.field
	var bin: Node3D = world.get("depot") as Node3D  # the trash bin: Lumi comes back to it all the time
	var so: Node = world.get("orbit")
	var globe: OrbitPlanet = so.get("globe") as OrbitPlanet if so != null else null
	var cells: Variant = globe.grid.cells_around(globe.start_cell(), FIRST_RINGS) if globe != null else range(f.hex_count())
	var from: Vector3 = bin.global_position if bin != null else (f.hex_center(globe.start_cell()) if globe != null else Vector3.ZERO)
	var best: int = -1
	var best_d: float = INF
	var why: Array[int] = [0, 0, 0]
	for c: int in cells:
		if f.hex_hub[c] != 0 or f.is_water(c) or f.is_clean(c):
			why[0] += 1
			continue
		var d: float = f.hex_center(c).distance_to(from)
		if d >= best_d or d > 40.0:
			why[1] += 1
			continue
		var at: Vector3 = spot(c)
		if at.distance_to(from) < FIRST_MIN_M or at.distance_to(f.hex_center(c)) > 6.0:
			why[2] += 1
			continue
		best = c
		best_d = d
	if best < 0:
		print("[tunes] first CD: hex %d at %.1f m from the bin (%d cells: %d base / water / clean, %d farther or over 40 m, %d spot too near the bin or off its hex)" % [best, best_d, (cells as Variant).size(), why[0], why[1], why[2]])
	return best


## [v10snd] The first CD is taken: it flies to Lumi in plain sight, then its song starts and a card
## with a CD picture says how to play it again (ui: _show_card). Given at once if Lumi is gone.
func _take_first(id: String) -> void:
	if not _discs.has(id):
		return
	var n: Node3D = _discs[id]
	_discs.erase(id)
	pending().erase(id)
	var song: String = Tunes.first_cd_id()
	var patch: Node3D = world.get("patch") as Node3D
	var land: Callable = func() -> void:
		if is_instance_valid(n):
			Vfx.burst("sparkle", n.global_position, Color(0.8, 0.95, 1.0), 1.0)
			n.queue_free()
		if Tunes.find_first_cd():
			_show_card(Tunes.first_cd_text(song))
	if patch == null or not is_inside_tree():
		land.call()
		return
	var from: Vector3 = n.global_position
	var up: Vector3 = from.normalized() if world.field is SphereField else Vector3.UP
	var tw: Tween = create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(n) and is_instance_valid(patch):
			var to: Vector3 = patch.global_position + up * 0.9
			n.global_position = from.lerp(to, k) + up * sin(PI * k) * 1.6  # an arc up and into his chest
			n.scale = Vector3.ONE * lerpf(1.0, 0.3, k)
			_face_first(n), 0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(land)


## The first CD's card: a CD picture and one line, top centre, for about ten seconds.
var first_card_text: String = ""
func _show_card(text: String) -> void:
	first_card_text = text
	var layer := CanvasLayer.new()
	layer.name = "FirstCdCard"
	layer.layer = 24
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	layer.add_child(root)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.065, 0.92), Color(1, 1, 1, 0.14), 1, 12, 14))
	pc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.offset_top = 120
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the card never takes a click meant for the world or a panel
	pc.add_child(hb)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(52, 52)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(func() -> void:
		var c := Vector2(26, 26)
		pic.draw_circle(c, 25.0, Color(0.86, 0.9, 0.95))
		pic.draw_arc(c, 19.0, -1.2, 0.2, 16, Color(0.6, 0.85, 1.0), 6.0)
		pic.draw_arc(c, 19.0, 1.9, 3.3, 16, Color(1.0, 0.8, 0.6), 6.0)
		pic.draw_circle(c, 9.0, Color(0.95, 0.62, 0.22))
		pic.draw_circle(c, 3.5, Color(0.05, 0.055, 0.065)))
	hb.add_child(pic)
	var lab: Label = UITheme.label(text, 18, UITheme.CREAM)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.custom_minimum_size = Vector2(430, 0)
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(lab)
	root.modulate.a = 0.0
	var tw: Tween = layer.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.3)
	tw.tween_interval(10.0)
	tw.tween_property(root, "modulate:a", 0.0, 0.8)
	tw.tween_callback(layer.queue_free)


## Where the first CD lies now (target audit); Vector3.INF when it is not out.
func first_spot() -> Vector3:
	for id: String in _discs:
		if id.begins_with(FIRST_KEY):
			return (_discs[id] as Node3D).global_position
	return Vector3.INF


## Where a CD turns up in hex hid.
## [v4world] Owner playtest 3 #55: on the globe the offset lies in the hex's own ground frame and
## the disc goes to the nearest reachable open ground (TargetReach): never inside a building, a
## lake, a collider or on steep ground.
func spot(hid: int, scratched: bool = false) -> Vector3:
	var off: Vector3 = OFFSET if not scratched else Vector3(1.0, 0.04, -0.8)
	if not (world.field is SphereField):
		return world.field.hex_center(hid) + off
	var t: TargetReach = TargetReach.for_world(world, true)
	var c: Vector3 = world.field.hex_center(hid)
	var fr: Basis = SphereGrid.frame(c.normalized())
	var g: Vector3 = t.open_spot((c + fr.x * off.x + fr.z * off.z).normalized())
	return g + g.normalized() * off.y


func _show(id: String, hid: int, fresh: bool) -> void:
	if _discs.has(id):
		return
	var scratched: bool = id.begins_with("s:")
	var node: Node3D = build_first_cd() if id.begins_with(FIRST_KEY) else build_cd(scratched)
	node.add_to_group("film_hide")  # [v11film] not in the opening film (Intro hides the group)
	add_child(node)
	var pos: Vector3 = spot(hid, scratched)
	if id.begins_with(FIRST_KEY):  # [v10snd] hovering over the junk so it is seen
		pos += (pos.normalized() if world.field is SphereField else Vector3.UP) * 0.55
	node.global_position = pos
	node.rotation.y = rng.randf() * TAU
	if world.field is SphereField:  # [v4world] upright on the round ground
		var up: Vector3 = pos.normalized()
		node.global_transform = Transform3D(Basis(up, node.rotation.y) * SphereGrid.frame(up), pos)
	_discs[id] = node
	print("[tunes] CD in the rubble: %s at hex %d%s" % [id, hid, "" if fresh else " (still there)"])
	if fresh:
		Vfx.burst("sparkle", pos + Vector3(0, 0.3, 0), Color(0.75, 0.9, 1.0), 0.6)
		Audio.play("detector", 1.25, -18.0)  # [v4calm] softer
		EventBus.toast.emit(tr("A scratched CD turned up in the rubble.") if scratched else tr("Something shiny turned up in the cleared rubble. An old CD!"), "hint" if Once.take("toast_cd_rubble") else "reward")  # [v4calm] the first only


func _process(delta: float) -> void:
	_spin += delta
	# [v11film] Hidden while the opening film plays: the first CD's ray of gold light stood over
	# the yard in the crash shots, like part of the crash. (A rewatch stops this node: Intro hides
	# the "film_hide" group itself then.)
	var it: Variant = world.get("intro") if world else null
	var film: bool = it is Intro and (it as Intro).busy()
	for id: String in _discs:
		var n: Node3D = _discs[id]
		n.visible = not film
		var glint: OmniLight3D = n.get_node_or_null("Glint") as OmniLight3D
		if id.begins_with(FIRST_KEY):
			_face_first(n)
		if glint:
			glint.light_energy = 0.5 + 0.35 * maxf(0.0, sin(_spin * 2.4 + float(id.length())))
	_t += delta
	if _t < 0.12 or world == null:
		return
	_t = 0.0
	var patch: Node3D = world.get("patch") as Node3D
	if patch == null:
		return
	if not _first_done:  # [v10snd] once the world is up (the bin stands, nothing is still building)
		var ld: Node = get_node_or_null("/root/Loader")
		if world.get("depot") is Node3D and not (ld != null and ld.has_method("busy") and bool(ld.call("busy"))):
			_first_done = true
			_place_first()
	var d: Node = Tunes.director()
	if d and d.get("listener") == null:
		d.set("listener", patch)
	for id: String in _discs.keys():
		var n: Node3D = _discs[id]
		var first: bool = id.begins_with(FIRST_KEY)
		if first:  # a sparkle now and then
			_first_t += 0.12
			if _first_t > 2.5:
				_first_t = 0.0
				Vfx.burst("sparkle", n.to_global(Vector3(0, FIRST_DISC_UP, 0)), Color(1.0, 0.9, 0.55), 0.7)
		if n.global_position.distance_to(patch.global_position) < (FIRST_PICK_R if first else PICK_R):
			_discs.erase(id)
			Vfx.burst("sparkle", n.global_position + Vector3(0, 0.4, 0), Color(0.8, 0.95, 1.0), 0.8)
			if first:
				_discs[id] = n  # still his until it has flown in
				_take_first(id)
				continue
			n.queue_free()
			if id.begins_with("s:"):
				_take_scratched(id.trim_prefix("s:"))
			else:
				take(id)


func _take_scratched(song_id: String) -> void:
	pending().erase("s:" + song_id)
	if Tunes.is_found(song_id):
		return
	var ui: Node = world.get_node_or_null("ScratchedCdUI") if world else null
	if ui and ui.has_method("ask"):
		ui.call("ask", song_id)
	elif not Tunes.hold(song_id):
		EventBus.toast.emit(tr("Your CD case is full."), "info")


## [v10snd] The first CD as the player sees it (the jewel case, even at 2.2x, was lost among the
## junk from the game camera): a big CD at head height, its flat side always to the camera, self-lit,
## dark-rimmed so it stands out against pale litter, bobbing, in a ray of gold light. Gold, not the
## guide's purple: it is a find, not the next step. No collider.
static func build_first_cd() -> Node3D:
	var root := Node3D.new()
	root.name = "CD"
	var face := Node3D.new()  # turned to the camera every frame (_face_first): never seen edge-on
	face.name = "Face"
	root.add_child(face)
	var disc := Node3D.new()
	disc.name = "Disc"
	disc.position = Vector3(0, FIRST_DISC_UP, 0)
	disc.rotation_degrees = Vector3(90, 0, 0)  # flat side to the camera
	face.add_child(disc)
	var r: float = FIRST_DISC_R
	var rings: Array = [  # radius, thickness, colour: each inner one a little thicker, so it lies in front
		[1.1, 0.020, Color(0.07, 0.09, 0.2)],
		[1.0, 0.026, Color(0.9, 0.96, 1.0)],
		[0.84, 0.032, Color(0.45, 0.85, 1.0)],
		[0.7, 0.038, Color(1.0, 0.6, 0.85)],
		[0.58, 0.044, Color(0.92, 0.97, 1.0)],
		[0.42, 0.050, Color(1.0, 0.6, 0.15)],
		[0.13, 0.056, Color(0.07, 0.09, 0.2)],
	]
	for row: Array in rings:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = row[2]
		disc.add_child(EggProps.mesh(ProcMesh.cyl(r * float(row[0]), r * float(row[0]), float(row[1]), 40), m))
	var q := QuadMesh.new()  # the ray: a strip of gold light behind the CD, strongest at the foot
	q.size = Vector2(1.3, FIRST_RAY_H)
	q.center_offset = Vector3(0, FIRST_RAY_H * 0.5, -0.1)
	var mi := MeshInstance3D.new()
	mi.name = "Ray"
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := ShaderMaterial.new()
	sm.shader = _ray_shader()
	mi.material_override = sm
	face.add_child(mi)
	var glint := OmniLight3D.new()
	glint.name = "Glint"
	glint.light_color = Color(1.0, 0.9, 0.6)
	glint.light_energy = 0.6
	glint.omni_range = 3.0
	glint.position = Vector3(0, FIRST_DISC_UP, 0)
	root.add_child(glint)
	return root


## Turns the first CD's face to the camera (about the ground's up) and bobs the disc.
func _face_first(n: Node3D) -> void:
	var face: Node3D = n.get_node_or_null("Face") as Node3D
	var cam: Camera3D = get_viewport().get_camera_3d()
	if face == null or cam == null:
		return
	var up: Vector3 = n.global_basis.y.normalized()
	var to: Vector3 = cam.global_position - n.global_position
	to -= up * to.dot(up)
	if to.length() > 0.05:
		to = to.normalized()
		face.global_basis = Basis(up.cross(to), up, to).scaled(n.scale)
	var disc: Node3D = face.get_node_or_null("Disc") as Node3D
	if disc:
		disc.visible = cam.global_position.distance_to(disc.global_position) > 2.6  # not a wall of CD when the camera passes through it
		disc.position.y = FIRST_DISC_UP + 0.1 * sin(_spin * 2.0)
		disc.rotation.z = 0.25 * sin(_spin * 1.3)  # a slow wobble


static var _ray: Shader
static func _ray_shader() -> Shader:
	if _ray == null:
		_ray = Shader.new()
		_ray.code = """shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() {
	float side = 1.0 - abs(UV.x - 0.5) * 2.0;
	float up = UV.y;  // 1 at the foot
	ALBEDO = vec3(1.0, 0.8, 0.25);
	ALPHA = 0.7 * smoothstep(0.0, 0.7, side) * up * smoothstep(2.0, 6.0, length(VERTEX));  // fades out near the camera: never a yellow screen
}
"""
	return _ray


## A CD in a cracked jewel case, lying half out of it in the dirt. Scratched: a duller, greyer
## disc with a pale, worn label.
static func build_cd(scratched: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "CD"
	var case_mat := StandardMaterial3D.new()
	case_mat.albedo_color = Color(0.82, 0.86, 0.9, 0.35)
	case_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	case_mat.roughness = 0.15
	case_mat.metallic_specular = 0.8
	var tray := DecorProps.paint(Color(0.08, 0.08, 0.09), 0.6)
	var disc := DecorProps.paint(Color(0.86, 0.88, 0.92) if not scratched else Color(0.6, 0.6, 0.62), 0.12 if not scratched else 0.55, 0.95 if not scratched else 0.5)
	var label := DecorProps.paint(Color(0.95, 0.62, 0.22) if not scratched else Color(0.62, 0.58, 0.52), 0.5 if not scratched else 0.85)
	var hub := DecorProps.paint(Color(0.92, 0.94, 0.97, 0.6), 0.2)
	var s: float = 1.9  # a real CD is tiny next to Lumi; a little larger so it reads
	var case_ := Node3D.new()
	case_.rotation_degrees = Vector3(0, 0, 4)
	root.add_child(case_)
	case_.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.142, 0.006, 0.125) * s), tray, Vector3(0, 0.003 * s, 0)))
	# The lid, cracked: two panes at a slight angle.
	case_.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.142, 0.004, 0.07) * s), case_mat, Vector3(0, 0.009 * s, -0.03 * s), Vector3(3, 0, 0)))
	case_.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.142, 0.004, 0.052) * s), case_mat, Vector3(0.004 * s, 0.013 * s, 0.037 * s), Vector3(-9, 4, 0)))
	# The disc slid half out, tipped onto the dirt.
	var d := Node3D.new()
	d.position = Vector3(0.07 * s, 0.012 * s, 0.01 * s)
	d.rotation_degrees = Vector3(0, 0, -7)
	root.add_child(d)
	d.add_child(EggProps.mesh(ProcMesh.cyl(0.06 * s, 0.06 * s, 0.0024 * s, 32), disc))
	d.add_child(EggProps.mesh(ProcMesh.cyl(0.052 * s, 0.052 * s, 0.0026 * s, 28), label, Vector3(0, 0.0003 * s, 0), Vector3.ZERO, Vector3(1, 1, 1)))
	d.add_child(EggProps.mesh(ProcMesh.cyl(0.019 * s, 0.019 * s, 0.003 * s, 16), hub))
	var glint := OmniLight3D.new()
	glint.name = "Glint"
	glint.light_color = Color(0.8, 0.92, 1.0)
	glint.light_energy = 0.6 if not scratched else 0.3
	glint.omni_range = 1.4
	glint.position = Vector3(0, 0.35, 0)
	root.add_child(glint)
	return root
