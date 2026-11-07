class_name CradleAnswers
extends Node
## [home] "The Cradle Answers": the Cradle Returns beat before the true ending (docs/DECISIONS.md,
## Homeward). The pad is green and the beacon is lit, so the ark comes, but it will not land: its
## Makers sleep aboard and the charter forbids waking them into a dying system. The whole Verdance
## system was strip-mined by the Ledger. So: restore every planet, then build the Homeward rocket.
## Plays once per profile (Homeward.answered); a quit midway replays it on the next load.
## Off-world shots use the SpaceStage; always hands the screen back (Cine).

static var playing: bool = false

# l10n:begin
const LINES: Array[Array] = [
	["Lumi. Look up. That star isn't moving like a star.", 4.0],
	["CRADLE:  BEACON RECEIVED.  GREEN DETECTED ON VERDANCE.  SEED-KEEPER LM-1 LOCATED.", 5.5],
	["CRADLE:  LANDING DENIED.  SYSTEM SURVEY: FIVE WORLDS.  ONE ALIVE.  SLEEPERS REMAIN UNDER.", 6.0],
	["It's the charter. The Makers sleep in the Cradle's lower decks, and it won't wake them into a dying system.", 6.0],
	["And it is dying. The Ledger mined every world out here hollow and left each one under its trash. Verdance was only the first.", 6.5],
	["So we fix all of it. Ochre, Tidewell, Rime, Anvil. One planet at a time.", 5.0],
	["Then we build a rocket big enough to reach the Cradle, and we carry the last seed up ourselves.", 5.5],
	["CRADLE:  ACKNOWLEDGED.  HOLDING ORBIT.  WE WILL WAIT FOR YOU, SMALL ROBOT.", 5.0],
]
# l10n:end

var world: Node


func play() -> void:
	if playing:
		return
	playing = true
	print("[home] the Cradle answers")
	var c := Cine.new()
	c.world = world
	add_child(c)
	c.begin()
	c.fade_to(1.0, 0.5)
	await get_tree().create_timer(0.55).timeout
	var st: SpaceStage = c.open_stage()
	st.show_set("space")
	st.set_planet_green(0.75)
	var ark: CradleShip = st.ark
	ark.rotation = Vector3(0, -PI * 0.5, 0)
	ark.position = Vector3(-60, 6, -10)
	ark.thrust = 1.4
	ark.create_tween().tween_property(ark, "position", Vector3(0, 2, 0), 14.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var pl: Array[MeshInstance3D] = SystemProps.add_planets(st, Vector3.ZERO, Homeward.state()["pct"])
	st.shot(Vector3(34, 10, 58), Vector3(-10, -6, 0), Vector3(20, 6, 44), Vector3(0, -2, 0), 14.0, 44.0, 40.0)
	c.fade_to(0.0, 1.5)
	c.caption(tr("Cradle Returns  ·  the ark answers"))
	var name_s: String = str(GameState.flags.get("patch_name", "Lumi"))
	var t: float = 0.0
	var next_line: float = 0.5
	var li: int = 0
	var total: float = 0.5
	for l: Array in LINES:
		total += float(l[1])
	var panned: bool = false
	while t < total and not c.skipped:
		if get_tree().paused:
			await get_tree().process_frame
			continue
		t += get_process_delta_time()
		if t >= next_line and li < LINES.size():
			c.wren(tr(str(LINES[li][0])).format({"name": name_s}), 2)
			if li == 2:
				c.caption("")
			next_line += float(LINES[li][1])
			li += 1
		if li >= 5 and not panned and not pl.is_empty():
			panned = true  # the rest of the system: four dusty worlds far off
			st.shot(Vector3(20, 6, 44), Vector3(0, -2, 0), Vector3(6, 14, 30), pl[1].position, 9.0, 40.0, 30.0)
		await get_tree().process_frame
	Homeward.state()["answered"] = true
	GameState.flags["cradle_answered"] = true
	Homeward.mirror_stats()
	Homeward.save()
	await c.end()
	playing = false
	EventBus.toast.emit(tr("The Cradle is holding orbit. Restore the whole system: the solar map is on the hologram (M). Build the Mk V Orbital drive to reach Ochre and Tidewell."), "story")
	Codex.unlock("homeward:charter")
	Codex.unlock("homeward:ledger_system")
	queue_free()
