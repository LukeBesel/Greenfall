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
const OFFSET := Vector3(-0.9, 0.04, 1.1)

var world: Node
var rng := RandomNumberGenerator.new()
var _discs: Dictionary = {}  # song id -> Node3D
var _t: float = 0.0
var _spin: float = 0.0


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
			if hid >= 0 and hid < world.field.hex_count() and world.field.is_clean(hid):
				_show(str(id), hid, false)


## Where a CD turns up in hex hid.
## [v4world] Owner playtest 3 #55: the offset lies in the hex's own ground frame and the disc goes to the nearest reachable open ground (TargetReach): never inside a building, a
## lake, a collider or on steep ground.
func spot(hid: int, scratched: bool = false) -> Vector3:
	var off: Vector3 = OFFSET if not scratched else Vector3(1.0, 0.04, -0.8)
	var t: TargetReach = TargetReach.for_world(world, true)
	var c: Vector3 = world.field.hex_center(hid)
	var fr: Basis = SphereGrid.frame(c.normalized())
	var g: Vector3 = t.open_spot((c + fr.x * off.x + fr.z * off.z).normalized())
	return g + g.normalized() * off.y


func _show(id: String, hid: int, fresh: bool) -> void:
	if _discs.has(id):
		return
	var scratched: bool = id.begins_with("s:")
	var node: Node3D = build_cd(scratched)
	add_child(node)
	var pos: Vector3 = spot(hid, scratched)
	var up: Vector3 = pos.normalized()  # [v4world] upright on the round ground
	node.global_transform = Transform3D(Basis(up, rng.randf() * TAU) * SphereGrid.frame(up), pos)
	_discs[id] = node
	print("[tunes] CD in the rubble: %s at hex %d%s" % [id, hid, "" if fresh else " (still there)"])
	if fresh:
		Vfx.burst("sparkle", pos + Vector3(0, 0.3, 0), Color(0.75, 0.9, 1.0), 0.6)
		Audio.play("detector", 1.25, -18.0)  # [v4calm] softer
		EventBus.toast.emit(tr("A scratched CD turned up in the rubble.") if scratched else tr("Something shiny turned up in the cleared rubble. An old CD!"), "hint" if Once.take("toast_cd_rubble") else "reward")  # [v4calm] the first only


func _process(delta: float) -> void:
	_spin += delta
	for id: String in _discs:
		var n: Node3D = _discs[id]
		var glint: OmniLight3D = n.get_node_or_null("Glint") as OmniLight3D
		if glint:
			glint.light_energy = 0.5 + 0.35 * maxf(0.0, sin(_spin * 2.4 + float(id.length())))
	_t += delta
	if _t < 0.12 or world == null:
		return
	_t = 0.0
	var patch: Node3D = world.get("patch") as Node3D
	if patch == null:
		return
	var d: Node = Tunes.director()
	if d and d.get("listener") == null:
		d.set("listener", patch)
	for id: String in _discs.keys():
		var n: Node3D = _discs[id]
		if n.global_position.distance_to(patch.global_position) < PICK_R:
			_discs.erase(id)
			Vfx.burst("sparkle", n.global_position + Vector3(0, 0.4, 0), Color(0.8, 0.95, 1.0), 0.8)
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
