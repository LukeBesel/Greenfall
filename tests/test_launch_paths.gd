extends GutTest
## The game only runs on the round globe: nothing may still reach for a member the world (the
## slice, scenes/slice.gd) no longer has. Rocket travel is only at the rocket (ui/rocket_picker.gd
## -> OrbitSites.hop_to); the workbench's rocket section shows status and upgrades, no launch list.

const SLICE: String = "res://scenes/slice.gd"
## Folders whose scripts are not game or tool code that talks to the slice.
const SKIP_DIRS: Array[String] = ["res://addons", "res://tests", "res://.godot", "res://parked"]
## `world.<name>` reads that are not the slice's members, each with why it is safe.
const ALLOWED: Dictionary = {
	"res://planet/hex_field.gd": ["x", "z"],  # `world` is a Vector3 parameter there
	"res://story/star_peek.gd": ["env"],  # read only after `world.get("env") is Environment`
	"res://planet/world_look_view.gd": ["layout"],  # read only after `world.get("layout") != null`
	"res://planet/future_layer.gd": ["layout"],  # the flat layer's setup; the globe uses its static helpers
}

var _flags: Dictionary
var _orbit: Dictionary


func before_each() -> void:
	_flags = GameState.flags.duplicate(true)
	_orbit = GameState.orbit.duplicate(true)


func after_each() -> void:
	GameState.flags = _flags
	GameState.orbit = _orbit


## The slice as the game makes it, but never entered into the tree (so no globe is built).
func _slice() -> Node3D:
	var w: Node3D = (load(SLICE) as GDScript).new()
	autofree(w)
	return w


func _slice_members() -> Dictionary:
	var sc: GDScript = load(SLICE)
	var out: Dictionary = {}
	for list: Array in [sc.get_script_property_list(), sc.get_script_method_list(), sc.get_script_signal_list()]:
		for e: Dictionary in list:
			out[str(e["name"])] = true
	for k: String in sc.get_script_constant_map():
		out[k] = true
	return out


func _scripts(dir: String, out: Array[String]) -> void:
	if dir in SKIP_DIRS:
		return
	for d: String in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))


func _on_node(member: String) -> bool:
	if ClassDB.class_has_method("Node3D", member) or ClassDB.class_has_signal("Node3D", member):
		return true
	for p: Dictionary in ClassDB.class_get_property_list("Node3D"):
		if str(p["name"]) == member:
			return true
	return false


func test_no_script_reads_a_member_the_world_does_not_have() -> void:
	var members: Dictionary = _slice_members()
	assert_true(members.has("rocket_status") and members.has("launching"), "the slice's members were read")
	var files: Array[String] = []
	_scripts("res://", files)
	assert_gt(files.size(), 200, "the scan saw the game's scripts")
	var re := RegEx.new()
	re.compile("(?<![\\w.])(?:world|so\\.w)\\.(\\w+)")
	var missing: Array[String] = []
	for path: String in files:
		var allowed: Array = ALLOWED.get(path, [])
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			var code: String = lines[i].get_slice("#", 0)
			for m: RegExMatch in re.search_all(code):
				var member: String = m.get_string(1)
				if members.has(member) or member in allowed or _on_node(member):
					continue
				missing.append("%s:%d world.%s" % [path, i + 1, member])
	assert_eq(missing, [] as Array[String], "every world member a script reads exists on the slice")


func test_workbench_rocket_section_has_no_launch_button() -> void:
	var w: Node3D = _slice()
	w.set("planet", PlanetData.new())
	var panel := RocketsPanel.new()
	panel.world = w
	add_child_autofree(panel)
	var buttons: Array[Node] = panel.find_children("*", "Button", true, false)
	for b: Node in buttons:
		assert_ne((b as Button).text, tr("Launch"), "travel is only at the rocket")
	# Every button the section does offer runs against the real world without an error.
	for b: Node in buttons:
		if not (b as Button).disabled:
			(b as Button).pressed.emit()
	assert_true(is_instance_valid(panel))


func test_rocket_calls_are_safe_before_the_globe_is_built() -> void:
	var w: Node3D = _slice()
	assert_ne(str(w.call("rocket_status")), "", "no rocket to fly before the sites exist")
	w.call("refresh_rocket")
	assert_false(bool(w.get("launching")))


func test_picker_fly_hands_the_site_to_the_globe_hop() -> void:
	var p := RocketPicker.new()
	add_child_autofree(p)
	p.entries_fn = func() -> Array: return [{"site": 2, "name": "Brindle", "km": 1.2}]
	watch_signals(p)
	p.open()
	var fly: Array[Node] = p._list.find_children("*", "Button", true, false)
	assert_eq(fly.size(), 1)
	(fly[0] as Button).pressed.emit()
	assert_signal_emitted_with_parameters(p, "picked", [2])
	# What the slice wires that signal to exists (planet/sites/orbit_sites.gd).
	var os := OrbitSites.new()
	autofree(os)
	assert_true(os.has_method("hop_to"))
	assert_eq(os.site_of_hub(0), -1, "no hub has a site before the survey is wired")
	assert_false(os.can_hop_to_hub(0), "so the bot's hub hop has nowhere to go yet")


# Hopping away frees a hub's site and its street power with it; hopping back builds the site again.
func test_site_power_of_a_freed_site_is_dropped_cleanly() -> void:
	var sm := SiteManager.new()
	autofree(sm)
	var gone := Node.new()
	sm.power[0] = gone
	gone.free()
	sm._drop_power(0)
	assert_false(sm.power.has(0))
	var live := Node.new()
	add_child_autofree(live)
	sm.power[1] = live
	sm._drop_power(1)
	assert_true(live.is_queued_for_deletion())
	assert_false(sm.power.has(1))
