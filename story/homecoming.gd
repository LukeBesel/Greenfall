class_name Homecoming
extends Node
## [home] The true ending, "Homecoming" (docs/DECISIONS.md, Homeward). Every planet of the Verdance
## system is restored; Lumi planted the last seed at the Homeward complex (Cradle Returns) and the
## Mk VII Homeward rocket has lifted off (automation/rocket.gd hands over at HOME). Letterboxed:
##   1. space: the rocket climbs out of a green Verdance; the four restored worlds glow far off;
##   2. the Cradle, holding orbit, wakes (green running lights) and takes the rocket into its bay;
##   3. the seed vault: Lumi sets the seedling tray back on its pedestal, three hundred years after
##      climbing into a pod to save it; the drawers light up; below decks, the Makers wake;
##   4. back on the ground: the ark finale (story/bloom_finale.gd) brings the Cradle down to
##      Verdance, "welcome home", then the end credits. The game carries on afterwards.
## Dev: --homecoming[=S] plays it S seconds after the district loads.

static var playing: bool = false

# l10n:begin
const SPACE_LINES: Array[Array] = [
	["Clear of the air. Look back, {name}. Look at it.", 4.5],
	["Five worlds, green. The Ledger left them as rubbish. You left them as gardens.", 5.5],
	["CRADLE:  SYSTEM SURVEY: FIVE WORLDS.  FIVE ALIVE.", 4.5],
	["CRADLE:  CHARTER CONDITION MET.  WAKING SLEEPERS.  OPENING BAY ONE.", 5.0],
	["It's opening the bay. It's actually opening the bay. Steady... steady...", 5.0],
]
const VAULT_LINES: Array[Array] = [
	["The vault. Your vault. It looks exactly like you left it.", 4.5],
	["You climbed into a cargo pod to save that tray. Three hundred years later, you brought it home.", 6.0],
	["Hear that? Below decks. Doors. Voices. They're waking up, {name}.", 5.0],
	["The first thing they'll see is a world that's green again. You did that. Small. Stubborn. Perfect.", 6.0],
]
# l10n:end

var world: Node
var _c: Cine


static func play_now(world: Node) -> Homecoming:
	var h := Homecoming.new()
	h.world = world
	world.add_child(h)
	h.play()
	return h


func play() -> void:
	if playing:
		return
	playing = true
	print("[home] homecoming: the rocket rises to the Cradle")
	Homeward.state()["launched"] = true
	Homeward.save()
	if Audio.has_method("set_mood"):  # [home] the sound pass's "homecoming" mood, if present
		Audio.call("set_mood", "homecoming")
	_c = Cine.new()
	_c.world = world
	add_child(_c)
	_c.begin()
	_c.fade_to(1.0, 0.3)
	await get_tree().create_timer(0.35).timeout
	if not _c.skipped:
		await _space()
	if not _c.skipped:
		await _vault()
	Homeward.state()["done"] = true
	CradleMode.profile["unlocked"] = true
	Homeward.mirror_stats()
	Homeward.save()
	GameState.inc_stat("homecoming")
	Codex.unlock("homeward:homecoming")
	await _c.end()
	_c = null
	_land_lumi()
	playing = false
	# The ark finale: the Cradle comes down to Verdance with the Makers aboard, then the credits.
	GameState.flags.erase("bloom_finale_seen")
	GameState.flags.erase("credits_seen")
	var f := BloomFinale.new()
	f.world = world
	world.add_child(f)
	f.play()
	print("[home] homecoming: the ark finale")
	queue_free()


func _say(lines: Array, i: int) -> void:
	var name_s: String = str(GameState.flags.get("patch_name", "Lumi"))
	_c.wren(tr(str(lines[i][0])).format({"name": name_s}), 2)


## Plays a line list over `extra` seconds while f(t) runs each frame. Returns true if skipped.
func _run(lines: Array, f: Callable, extra: float = 0.0) -> bool:
	var total: float = extra
	for l: Array in lines:
		total += float(l[1])
	var t: float = 0.0
	var next_line: float = 0.6
	var li: int = 0
	while t < total:
		if _c.skipped:
			return true
		if get_tree().paused:
			await get_tree().process_frame
			continue
		var dt: float = get_process_delta_time()
		t += dt
		if t >= next_line and li < lines.size():
			_say(lines, li)
			next_line += float(lines[li][1])
			li += 1
		f.call(t, total, dt)
		await get_tree().process_frame
	return false


func _space() -> void:
	var st: SpaceStage = _c.open_stage()
	st.show_set("space")
	st.set_planet_green(1.0)
	var all_green: Dictionary = {}
	for d: Dictionary in Homeward.planets():
		all_green[str(d["id"])] = 1.0
	SystemProps.add_planets(st, Vector3.ZERO, all_green)
	var ark: CradleShip = st.ark
	ark.rotation = Vector3(0, -PI * 0.5, 0)
	ark.position = Vector3(0, 8, 0)
	ark.thrust = 0.25
	var rocket: RocketModel = SystemProps.add_rocket(st, Vector3(10, -46, 16))
	rocket.scale = Vector3.ONE * 0.55
	var dock := Vector3(0, 4.2, 0)
	st.shot(Vector3(24, -30, 40), Vector3(10, -40, 16), Vector3(30, -6, 46), Vector3(2, 0, 4), 16.0, 46.0, 42.0)
	_c.fade_to(0.0, 1.2)
	_c.caption(tr("Homecoming"))
	Audio.play("fanfare", 0.8, -8.0)
	var start: Vector3 = rocket.position
	var skipped: bool = await _run(SPACE_LINES, func(t: float, total: float, _dt: float) -> void:
		var k: float = clampf(t / (total - 3.0), 0.0, 1.0)
		var e: float = k * k * (3.0 - 2.0 * k)
		var p: Vector3 = start.lerp(dock, e)
		p.x += sin(e * PI) * 6.0
		rocket.position = p
		rocket.rotation.z = -sin(e * PI) * 0.35
		if rocket.plume:
			rocket.plume.power = lerpf(1.0, 0.15, e)
		SystemProps.wake_ark(ark, clampf((t - 9.0) / 8.0, 0.0, 1.0))
		if t > 4.0:
			_c.caption("")
		if k >= 1.0 and not rocket.has_meta("docked"):
			rocket.set_meta("docked", true)
			Audio.play("clunk", 0.8, -4.0)
			st.blast(dock + Vector3(0, 0.6, 0), 0.4, Color(0.6, 1.0, 0.7)), 2.5)
	if skipped:
		return
	_c.fade_to(1.0, 0.6)
	await get_tree().create_timer(0.65).timeout


func _vault() -> void:
	var st: SpaceStage = _c.stage
	if st == null:
		st = _c.open_stage()
	st.show_set("vault")
	var v: Vector3 = SpaceStage.VAULT_AT
	var lumi: PatchModel = st.lumi
	lumi.position = Vector3(0, 0.15, 2.4)
	lumi.rotation.y = PI
	lumi.set_happy(1.0)
	var tray: Node3D = st.tray
	tray.visible = false
	var carried: Node3D = SpaceStage.build_tray()
	st.root_of("vault").add_child(carried)
	st.shot(v + Vector3(2.6, 1.9, 4.6), v + Vector3(0, 0.9, 1.2), v + Vector3(1.8, 1.4, 2.6), v + Vector3(0, 0.9, 0), 12.0, 46.0, 40.0)
	_c.fade_to(0.0, 1.0)
	var placed: Array[bool] = [false]
	var skipped: bool = await _run(VAULT_LINES, func(t: float, _total: float, _dt: float) -> void:
		var k: float = clampf(t / 7.0, 0.0, 1.0)
		lumi.position = Vector3(0, 0.15, 2.4).lerp(Vector3(0, 0.15, 0.62), k * k * (3.0 - 2.0 * k))
		lumi.holding = not placed[0]
		if not placed[0]:
			carried.global_position = lumi.global_position + Vector3(0, 0.62, -0.42)
		if k >= 1.0 and not placed[0]:
			placed[0] = true
			carried.global_position = tray.global_position
			lumi.flash()
			Audio.play("chime", 1.0, -6.0)
			st.blast(v + Vector3(0, 1.2, 0), 0.25, Color(0.6, 1.0, 0.7))
		if placed[0]:
			st.env.ambient_light_energy = lerpf(st.env.ambient_light_energy, 0.9, 0.02)
			if randf() < 0.04:
				st.note(lumi.global_position + Vector3(0, 0.9, 0)), 2.0)
	if skipped:
		return
	_c.fade_to(1.0, 0.8)
	await get_tree().create_timer(0.85).timeout


## Lumi comes back down in the ark's beam (the finale films him on the ground).
func _land_lumi() -> void:
	var p: Node3D = world.get("patch") as Node3D
	if p == null:
		return
	p.visible = true
	p.scale = Vector3.ONE
	p.set_physics_process(true)
	var r: Node = world.get("rocket")
	if r != null and r is Node3D:
		p.global_position = (r as Node3D).global_position + Vector3(4.0, 0.3, 6.0)
		(r as Node3D).visible = true
