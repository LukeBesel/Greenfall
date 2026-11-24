extends GutTest
## [v11film] Owner (20 Nov): "fully revamp the starting scene... the rocket design is bad and make
## sure the entire story makes full sense and is emotional and not cheesy... Also add rewatch
## option to cut scene for a little bit after it happens". What can be held by a unit test: the
## story's one voice and its facts, the redesigned pod and ark, the vault set, and when the
## rewatch is offered. That a rewatch changes nothing is played in the real game
## (tools/check_rewatch.sh); how it looks was judged on rendered frames.

class StubWorld:
	extends Node
	var patch: Node3D
	var intro: Intro


func test_wren_is_the_only_voice_and_says_the_whole_chain() -> void:
	var lines: Dictionary = Intro.lines()
	var all: String = ""
	for key: String in lines:
		var l: Array = lines[key]
		assert_eq(str(l[1]), "wren", "%s: no narrator, WREN says it" % key)
		assert_lt(str(l[0]).length(), 115, "%s: one short line" % key)
		all += " " + str(l[0]).to_lower()
	assert_lte(lines.size(), 10, "few lines: the pictures carry it")
	# Who sleeps and why, what Lumi keeps, why she lets go, why she cannot follow, the first job.
	for need: String in ["green", "trash", "people sleep", "last plants", "glass", "tray", "pod", "let you go", "engines", "find you", "workbench", "signal tower"]:
		assert_true(all.contains(need), "the film says: %s" % need)
	for gone: String in ["ledger", "hull breach", "came apart", "for days", "little seed-keeper"]:
		assert_false(all.contains(gone), "not in the film any more: %s" % gone)


func test_the_story_text_agrees_with_the_film() -> void:
	# The fall happens in the game's own time: the Homecoming no longer says it was 300 years ago.
	var home: String = ""
	for l: Array in Homecoming.VAULT_LINES:
		home += " " + str(l[0])
	assert_true(home.contains("climbed into a pod to save that tray"))
	assert_false(home.contains("Three hundred years later"))
	var brief: Array = Intro.brief_lines()
	assert_eq(brief.size(), 2)
	assert_true(str(brief[0]).contains("WREN"))
	assert_true(str(brief[1]).begins_with("Fix the old workbench"), "her last message starts with the game's first job")


func test_the_pod_is_a_drop_capsule_not_a_toy_rocket() -> void:
	var widest: Vector2 = Vector2.ZERO
	for p: Vector2 in EscapePod.PROFILE:
		if p.x > widest.x:
			widest = p
	assert_lt(widest.y, 0.4, "it is widest at the heat shield, at the bottom")
	assert_gt(EscapePod._door_r(2.05), 0.3, "a flat shoulder, not a cone tip")
	assert_lt(EscapePod.HEIGHT, 2.4, "squat")
	var pod: Node3D = EscapePod.build()
	add_child_autofree(pod)
	for n: String in ["Body", "Hatch", "Canopy", "Skirt", "Legs", "Fittings", "Beacon", "Fin0/Lamp", "Fin1/Lamp", "Fin2/Lamp", "Cabin"]:
		assert_not_null(pod.get_node_or_null(n), n)
	assert_lt((pod.get_node("Beacon") as Node3D).position.y, EscapePod.HEIGHT + 0.1, "no aerial: the beacon sits on the cap")
	# The cabin still fits inside the shell where Lumi rides.
	for y: float in [0.6, 1.0, 1.4]:
		assert_gt(EscapePod._door_r(y), 0.68, "room for Lumi at %.1f m" % y)


func test_the_crashed_pod_keeps_the_tray() -> void:
	var holder := Node3D.new()
	add_child_autofree(holder)
	var site: CrashSite = CrashSite.attach(holder, EscapePod.build(), Vector3.ZERO, 0.5)
	var tray: Node3D = site.pod.get_node_or_null("SeedTray")
	assert_not_null(tray, "the seedlings Lumi saved are in the cabin")
	assert_between(tray.position.y, EscapePod.DOOR_Y0, EscapePod.DOOR_Y1, "seen through the open hatch")
	assert_not_null(site.pod.get_node_or_null("TrayGlow"))


func test_the_ark_can_be_broken_and_go_dark() -> void:
	var ark := CradleShip.new()
	add_child_autofree(ark)
	ark.alarm = 1.0
	ark.thrust = 0.0
	ark.power = 0.4
	ark.breach = 1.0
	ark._process(0.1)
	assert_almost_eq(float(ark._dome_mat.get_shader_parameter("breach")), 1.0, 0.001)
	assert_almost_eq(float(ark._hull_mat.get_shader_parameter("power")), 0.4, 0.001)
	assert_almost_eq(ark._engine.emission_energy_multiplier, 0.0, 0.001, "dead engines give no light")
	var z0: float = ark._ring.rotation.z
	ark._process(1.0)
	assert_ne(ark._ring.rotation.z, z0, "the ring turns")
	assert_lt(ark.pod_world(0).y, ark.global_position.y - 6.0, "the pods hang under the keel")


func test_the_vault_is_a_room_with_plants() -> void:
	var st := SpaceStage.new()
	add_child_autofree(st)
	st.show_set("vault")
	var root: Node3D = st.root_of("vault")
	assert_not_null(root.get_node_or_null("Glass"), "under the dome's glass")
	assert_not_null(root.get_node_or_null("Floor"))
	assert_not_null(st.vault_planet, "the planet outside the glass")
	assert_gt(st._vault_plants.size(), 20, "planting beds of real plants")
	assert_not_null(st.tray.get_meta("leaf", null), "the seedlings can glow when Lumi hums")
	st.vault_breach = 1.0
	st.vault_wind = 1.0
	st._process(0.2)
	assert_true(st._vault_leaves.emitting, "the breach drags leaves toward the hole")
	assert_almost_eq(float(st._vault_dome.get_shader_parameter("breach")), 1.0, 0.001)
	assert_gt((SpaceStage.vault_hole() - SpaceStage.VAULT_AT).y, 1.5, "the hole is up in the glass")
	st.vault_wind = 0.0
	st._process(0.2)
	assert_false(st._vault_leaves.emitting)


func test_rewatch_is_offered_for_a_while_near_the_pod() -> void:
	var flags: Dictionary = GameState.flags.duplicate(true)
	var stats: Dictionary = GameState.stats.duplicate(true)
	var w := StubWorld.new()
	add_child_autofree(w)
	w.patch = Node3D.new()
	w.add_child(w.patch)
	var site := Node3D.new()
	w.add_child(site)
	w.set_meta("orbit_pod", site)
	w.intro = Intro.new()
	w.intro.world = w
	w.add_child(w.intro)
	GameState.flags["intro_done"] = true
	GameState.stats["time_played"] = 90.0
	assert_true(Intro.rewatch_offered(w), "a minute and a half in, by the pod")
	GameState.stats["time_played"] = Intro.REWATCH_S + 1.0
	assert_false(Intro.rewatch_offered(w), "the pause menu's entry goes after the window")
	assert_true(w.intro.can_replay(), "the Codex can still play it")
	GameState.stats["time_played"] = 90.0
	w.patch.position = Vector3(Intro.REWATCH_NEAR_M + 5.0, 0, 0)
	assert_false(Intro.rewatch_offered(w), "not far from the pod")
	w.patch.position = Vector3.ZERO
	w.intro.running = true
	assert_false(Intro.rewatch_offered(w), "not while the film plays")
	w.intro.running = false
	GameState.flags.erase("intro_done")
	assert_false(Intro.rewatch_offered(w), "not before the film has been seen")
	assert_between(Intro.REWATCH_S, 600.0, 3600.0, "a little while: ten minutes to an hour of play")
	GameState.flags = flags
	GameState.stats = stats


func test_pause_menu_has_the_entry_and_hides_it() -> void:
	var flags: Dictionary = GameState.flags.duplicate(true)
	var stats: Dictionary = GameState.stats.duplicate(true)
	var w := StubWorld.new()
	add_child_autofree(w)
	w.patch = Node3D.new()
	w.add_child(w.patch)
	var site := Node3D.new()
	w.add_child(site)
	w.set_meta("orbit_pod", site)
	w.intro = Intro.new()
	w.intro.world = w
	w.add_child(w.intro)
	var pm := PauseMenu.new()
	w.add_child(pm)
	var fb: Button = pm.find_child("FilmBtn", true, false) as Button
	assert_not_null(fb)
	assert_eq(fb.text, "Watch the opening again")
	GameState.flags["intro_done"] = true
	GameState.stats["time_played"] = 90.0
	pm.open_menu()
	assert_true(fb.visible)
	# Up and down from it lead to buttons that are shown (a controller never lands on a hidden one).
	for path: NodePath in [fb.focus_neighbor_top, fb.focus_neighbor_bottom]:
		var n: Button = fb.get_node_or_null(path) as Button
		assert_true(n != null and n.visible, "a shown neighbour")
	pm.close_menu()
	GameState.stats["time_played"] = Intro.REWATCH_S + 1.0
	pm.open_menu()
	assert_false(fb.visible, "gone after the window")
	for b: Button in pm._buttons:
		if b.visible:
			for path: NodePath in [b.focus_neighbor_top, b.focus_neighbor_bottom]:
				assert_true((b.get_node_or_null(path) as Button).visible, "%s: neighbours skip the hidden entry" % b.text)
	pm.close_menu()
	GameState.flags = flags
	GameState.stats = stats
