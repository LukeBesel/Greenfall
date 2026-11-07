class_name ExtrasDirector
extends Node
## [extras] Wires the keepsake features into a district (one call from scenes/slice.gd): the base
## radio (radio.gd), the robot nursery (nursery.gd), the photo album (album.gd), the welcome-back
## card (welcome_back.gd), the Seed of the Week run (weekly.gd / weekly_run.gd) and the Keepsakes
## panel (ui/extras_panel.gd, Pause > Keepsakes). Dev hooks:
##   --extras=radio|album|nursery|weekly   open the Keepsakes panel on that tab (after --extras-at=S s)
##   --extras-welcome[=H]   fake an H-hour break (default 3) and show the welcome-back card
##   --album-snap=before+m50+thriving+base5   take those album pictures now (after --album-at=S s)
##   --album-adopt          list album pictures already on disk for this slot (staged shots with --save-dir)
##   --nursery-sample=N     N retired caretakers in the nursery;  --radio-all unlocks every song
##   --radio-play=ID        play a song;  --weekly starts this week's challenge
##   --extras-cam=x,z,yaw,dist,pitch   fixed camera (shots); --extras-nohud hides the HUD

var world: Node
var radio: Radio
var nursery: Nursery
var album: PhotoAlbum
var panel: ExtrasPanel
var run: WeeklyRun


static func attach(slice: Node) -> ExtrasDirector:
	var d := ExtrasDirector.new()
	d.name = "ExtrasDirector"
	d.world = slice
	slice.add_child(d)
	d._setup()
	return d


static func of(slice: Node) -> ExtrasDirector:
	return slice.get_node_or_null("ExtrasDirector") as ExtrasDirector if slice else null


func _setup() -> void:
	add_to_group("persist")
	GameState.stats["weekly_chips"] = float(WeeklyChallenge.chip_count())  # profile-wide, mirrored for achievements
	radio = Radio.new()
	world.add_child(radio)
	radio.setup(world)
	nursery = Nursery.new()
	world.add_child(nursery)
	if DevHooks.has("nursery-sample"):
		_sample_nursery(int(DevHooks.get_f("nursery-sample", 4.0)))
	nursery.setup(world)
	album = PhotoAlbum.new()
	add_child(album)
	album.setup(world)
	if DevHooks.has("album-adopt"):  # shots: pick up pictures a previous --save-dir run left on disk
		album.dev_adopt()
	panel = ExtrasPanel.new()
	panel.name = "ExtrasPanel"
	panel.world = world
	world.add_child(panel)
	if WeeklyChallenge.active:
		run = WeeklyRun.new()
		run.name = "WeeklyRun"
		run.world = world
		world.add_child(run)
	if DevHooks.has("radio-all"):
		for s: Dictionary in Radio.songs():
			if s.has("cond") and not (str(s["id"]) in (Radio.st()["unlocked"] as Array)):
				(Radio.st()["unlocked"] as Array).append(str(s["id"]))
	if DevHooks.has("radio-play"):
		Radio.play(DevHooks.get_s("radio-play", "verdance_sweep"))
	if DevHooks.has("extras-welcome"):
		var h: float = DevHooks.get_f("extras-welcome", 3.0)
		var bots: Array = GameState.world.get("robots", [])
		if bots.is_empty():
			bots = [{"type": "scoopie", "tier": 1}, {"type": "scoopie", "tier": 1}, {"type": "haulbug", "tier": 0}, {"type": "drip", "tier": 0}]
		WelcomeBack.offer(Offline.simulate({"robots": bots}, h * 3600.0, 400.0, 1), h * 3600.0, bots)
	(func() -> void: WelcomeBack.resolve(world)).call_deferred()
	if DevHooks.has("weekly") and not WeeklyChallenge.active:
		get_tree().create_timer(0.5).timeout.connect(func() -> void: WeeklyChallenge.start(get_tree()))
	if DevHooks.has("album-snap"):
		get_tree().create_timer(DevHooks.get_f("album-at", 8.0), false).timeout.connect(func() -> void:
			album.dev_snap(Array(DevHooks.get_s("album-snap", "before").split("+", false))))
	if DevHooks.has("extras"):
		get_tree().create_timer(DevHooks.get_f("extras-at", 1.0), true).timeout.connect(func() -> void:
			ExtrasPanel.open_for(world, DevHooks.get_s("extras", "radio")))
	if DevHooks.has("extras-cam"):
		_cam.call_deferred()
	if DevHooks.has("extras-nohud") and world.get("hud") != null:
		(func() -> void: world.hud.visible = false).call_deferred()


## Saved with the district: what junk is left, so Offline.simulate can cap a district that
## isn't loaded (remote progress) without its field.
func persist_save() -> void:
	var f: HexField = world.get("field") as HexField
	if f == null:
		return
	var left: float = 0.0
	for h: int in f.hex_count():
		if not f.is_clean(h):
			left += f.hex_left[h]
	GameState.world["junk_left"] = left


## Dev / shots: a few retired caretakers with varied types, tiers and traits.
func _sample_nursery(n: int) -> void:
	var types: Array[String] = ["scoopie", "haulbug", "drip", "seedling", "scoopie", "skimmer"]
	var names: Array[String] = ["Bobbin-07", "Tansy-21", "Pip-88", "Marlo-14", "Juniper-02", "Cog-55"]
	var tl: Array = RobotBuilder.traits()
	Nursery.list().clear()
	for i: int in mini(n, types.size()):
		Nursery.list().append({"name": names[i], "type": types[i] if types[i] != "skimmer" else "scoopie", "tier": i % 3,
			"trait": str(tl[i % tl.size()]["id"]) if not tl.is_empty() else "", "build": {}, "unix": 0.0, "from": 0})


func _cam() -> void:
	var v: PackedStringArray = DevHooks.get_s("extras-cam", "0,14,3.14,9,-0.5").split(",")
	var anchor := Node3D.new()
	world.add_child(anchor)
	anchor.global_position = Vector3(float(v[0]), 0.8, float(v[1]))
	world.cam.target = anchor
	world.cam.yaw = float(v[2]) if v.size() > 2 else 0.0
	world.cam.distance = float(v[3]) if v.size() > 3 else 9.0
	world.cam.pitch = float(v[4]) if v.size() > 4 else -0.5
	world.cam.snap()
