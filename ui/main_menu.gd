extends Node3D
## Title screen: Aurora hovering over a sunset junk lot, a slow orbiting camera and the front-end
## menu (Continue / New Game / Settings / Credits / Quit).
## Any DevHooks flag (e.g. tools/shot.sh's --fresh --shot=...) skips straight to the game so the
## existing tooling keeps working; pass --menu to stay here (title screenshots), or
## --menu=settings|credits|confirm to open that sub-screen.
##   xvfb-run ... godot --path . --rendering-driver vulkan -- --menu --shot=screenshots/title.png --shot-delay=30 --quit-after=34

const GAME_SCENE: String = "res://scenes/slice.tscn"

var _cam: Camera3D
var _pivot: Node3D
var _model: PatchModel
var _t: float = 0.0
var _ui: Control
var _menu_box: VBoxContainer
var _main: Control
var _fade: ColorRect
var _settings: SettingsPanel
var _credits: Control
var _confirm: Control
var _confirm_no: Button
var _continue: Button
var _new_game: Button
var _profiles_btn: Button  # [worlds2] save profiles, then worlds (ui/profile_picker.gd)
var _picker: ProfilePicker  # [worlds2]
var _leaving: bool = false
var _save: Dictionary = {}
## Intro fade start (wall clock: the first frames can be very slow while shaders compile, and
## engine delta is clamped then, so a tween could still be dark seconds later).
var _intro_ms: int = -1


func _ready() -> void:
	if not DevHooks.args.is_empty() and not DevHooks.has("menu"):
		_go.call_deferred(false)
		return
	# Nothing to save on the title screen: keep the autosave timer and focus-loss saves from
	# overwriting the player's slot with the blank in-memory state.
	SaveManager.enabled = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if SaveManager.has_save():
		_save = SaveManager.read_dict(SaveManager.slot_path())
	_build_stage()
	_build_ui()


# --- 3D stage -------------------------------------------------------------------------

func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := PhysicalSkyMaterial.new()
	sm.rayleigh_coefficient = 3.2
	sm.rayleigh_color = Color(0.32, 0.42, 0.8)
	sm.mie_coefficient = 0.012
	sm.mie_eccentricity = 0.86
	sm.mie_color = Color(1.0, 0.7, 0.45)
	sm.turbidity = 10.0
	sm.sun_disk_scale = 2.0
	sm.ground_color = Color(0.32, 0.26, 0.22)
	sm.energy_multiplier = 1.3
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.25
	env.glow_intensity = 0.45
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.95, 0.66, 0.46)
	env.fog_sun_scatter = 0.35
	env.fog_sky_affect = 0.25
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.95, 0.8, 0.68)
	env.volumetric_fog_anisotropy = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	Settings.apply_render_quality(env, get_viewport())
	env.ambient_light_energy *= 0.8

	# Low golden sun behind the robot (in view: warm rim and a glowing horizon), plus a cool fill
	# from the camera side so the face and paint still read.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-8, -30, 0)
	sun.light_color = Color(1.0, 0.66, 0.4)
	sun.light_energy = 2.4
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	Settings.apply_sun_quality(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 200, 0)
	fill.light_color = Color(0.62, 0.72, 1.0)
	fill.light_energy = 0.7
	add_child(fill)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	pm.material = AssetLib.pbr_material("dry_ground_rocks", 20.0)
	ground.mesh = pm
	add_child(ground)

	# Junk around the robot (near) and a few silhouettes further out.
	var props: Array = [
		["old_tyre", Vector3(1.5, 0.08, 0.7), Vector3(90, 0, 20)],
		["can_rusted", Vector3(0.9, 0, -0.9), Vector3(0, 40, 0)],
		["trashbag", Vector3(-1.6, 0, -0.6), Vector3(0, 70, 0)],
		["plastic_bottle_gallon", Vector3(-0.9, 0, 1.3), Vector3(0, 0, 90)],
		["cardboard_box_01", Vector3(2.3, 0, -1.6), Vector3(0, 25, 0)],
		["Barrel_01", Vector3(-2.6, 0, 1.8), Vector3(0, 0, 0)],
		["rusted_wheel_rim_01", Vector3(-1.9, 0.02, -2.2), Vector3(80, 0, 0)],
		["metal_trash_can", Vector3(3.2, 0, 1.9), Vector3(0, -30, 0)],
		["covered_car", Vector3(-7.5, 0, -6.0), Vector3(0, 35, 0)],
		["concrete_road_barrier", Vector3(6.5, 0, -5.0), Vector3(0, -20, 0)],
		["street_lamp_01", Vector3(-9.0, 0, 11.0), Vector3(0, 0, 0)],
		["dead_tree_trunk", Vector3(8.0, 0, 5.5), Vector3(0, 60, 0)],
		["utility_box_01", Vector3(4.6, 0, 6.8), Vector3(0, 200, 0)],
		# A little hope: the first flowers poking through.
		["flower_heliophila", Vector3(0.55, 0, 0.75), Vector3.ZERO],
		["dandelion_01", Vector3(-0.6, 0, 0.45), Vector3(0, 90, 0)],
		["grass_medium_01", Vector3(0.2, 0, 1.1), Vector3.ZERO],
	]
	for spec: Array in props:
		if not AssetLib.has_model(spec[0]):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = AssetLib.model_mesh(spec[0])
		mi.position = spec[1]
		mi.rotation_degrees = spec[2]
		add_child(mi)

	_scatter_junk()
	_build_skyline()

	_pivot = Node3D.new()
	add_child(_pivot)
	_model = PatchModel.new()
	_pivot.add_child(_model)
	var skin: String = str((_save.get("flags", {}) as Dictionary).get("patch_skin", ""))
	if skin != "":
		_model.set_variant(skin)
	_model.set_happy(0.55)  # [hero] signature C eyes on the title (0.9 sat mid-morph: C + ^ = "two sets of eyes")

	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.h_offset = -0.75  # shifts the robot to the right third, away from the menu
	add_child(_cam)
	_cam.current = true
	_place_camera()


## A carpet of litter and a few heaped piles: the world Aurora has come to clean.
func _scatter_junk() -> void:
	var ids: Array[String] = []
	for t: Dictionary in Economy.junk_types.values():
		for m: Dictionary in t.get("models", []):
			if AssetLib.has_model(str(m["id"])):
				ids.append(str(m["id"]))
	if ids.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var per: Dictionary = {}
	for i: int in 1400:
		var r: float = sqrt(rng.randf()) * 26.0
		var a: float = rng.randf() * TAU
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if p.length() < 1.3:
			continue  # keep a little clearing under the robot
		var id: String = ids[rng.randi() % ids.size()]
		var lie: bool = rng.randf() < 0.6
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		if lie:
			b = b * Basis(Vector3.RIGHT if rng.randf() < 0.5 else Vector3.FORWARD, PI * 0.5)
		var sc: float = rng.randf_range(0.85, 1.2)
		if not per.has(id):
			per[id] = []
		(per[id] as Array).append(Transform3D(b.scaled(Vector3.ONE * sc), p + Vector3(0, 0.03 if lie else 0.0, 0)))
	# Heaps: denser clusters stacked a little higher.
	for h: int in 9:
		var c := Vector3(rng.randf_range(-18, 18), 0, rng.randf_range(-6, 22))
		if c.length() < 4.0:
			continue
		for k: int in 70:
			var off := Vector3(rng.randf_range(-1.6, 1.6), 0, rng.randf_range(-1.6, 1.6))
			var y: float = maxf(0.0, 1.1 - off.length() * 0.65) * rng.randf()
			var id2: String = ids[rng.randi() % ids.size()]
			var b2 := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
			if not per.has(id2):
				per[id2] = []
			(per[id2] as Array).append(Transform3D(b2, c + off + Vector3(0, y, 0)))
	for id3: String in per:
		var xs: Array = per[id3]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = AssetLib.model_mesh_lite(id3, 900)
		mm.instance_count = xs.size()
		for j: int in xs.size():
			mm.set_instance_transform(j, xs[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


## Hazy ruined city silhouettes on the horizon.
func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.3, 0.28)
	mat.roughness = 0.95
	for i: int in 26:
		var a: float = rng.randf_range(-PI, PI)
		var d: float = rng.randf_range(32.0, 60.0)
		var size := Vector3(rng.randf_range(6, 14), rng.randf_range(8, 34), rng.randf_range(6, 14))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(sin(a) * d, size.y * 0.5 - rng.randf_range(0.0, 3.0), cos(a) * d)
		mi.rotation = Vector3(rng.randf_range(-0.04, 0.04), rng.randf() * TAU, rng.randf_range(-0.06, 0.06))
		add_child(mi)


func _place_camera() -> void:
	# Slow swing across the front of the robot, keeping the low sun in the background.
	var a: float = 0.2 + sin(_t * 0.07) * 0.55
	var r: float = 3.5
	_cam.position = Vector3(sin(a) * r, 1.15 + sin(_t * 0.21) * 0.08, -cos(a) * r)
	_cam.look_at(Vector3(0, 0.62, 0), Vector3.UP)


func _process(delta: float) -> void:
	if _cam == null:
		return
	_t += delta
	_pivot.position.y = 0.32 + sin(_t * 1.3) * 0.06
	_pivot.rotation.y = sin(_t * 0.35) * 0.35
	_pivot.rotation.z = sin(_t * 0.9) * 0.025
	_model.look_toward(_cam.global_position)
	_place_camera()
	if _intro_ms >= 0 and not _leaving:
		var s: float = (Time.get_ticks_msec() - _intro_ms) / 1000.0
		_fade.color.a = 1.0 - smoothstep(0.0, 1.1, s)
		_main.modulate.a = smoothstep(0.35, 1.15, s)
		if s > 1.2:
			_intro_ms = -1


# --- UI -------------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UITheme.get_theme()
	layer.add_child(_ui)

	# Soft dark wash on the left so the menu reads over the bright sky.
	var wash := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.03, 0.05, 0.72))
	g.set_color(1, Color(0.03, 0.03, 0.05, 0.0))
	g.add_point(0.45, Color(0.03, 0.03, 0.05, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	wash.texture = gt
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	wash.anchor_right = 0.62
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(wash)

	_main = MarginContainer.new()
	_main.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main.add_theme_constant_override("margin_left", 84)
	_main.add_theme_constant_override("margin_top", 70)
	_main.add_theme_constant_override("margin_bottom", 48)
	_ui.add_child(_main)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_main.add_child(col)

	var title := UITheme.label("GREENFALL", 92, Color(1.0, 0.95, 0.86))
	title.add_theme_font_override("font", _title_font())
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("shadow_offset_x", 0)
	col.add_child(title)
	var bar := ColorRect.new()
	bar.color = UITheme.GOLD
	bar.custom_minimum_size = Vector2(96, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bar)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	col.add_child(gap)
	col.add_child(UITheme.label(tr("One small robot. One very big cleanup."), 20, Color(0.92, 0.88, 0.8)))
	if Demo.is_demo():  # [steam]
		col.add_child(UITheme.label(tr("DEMO  ·  the first district"), 15, UITheme.GOLD))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 10)
	_menu_box.custom_minimum_size = Vector2(340, 0)
	_menu_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_menu_box)
	var buttons: Array[Button] = []
	if not _save.is_empty():
		_continue = _menu_button(tr("Continue"), _on_continue, _save_summary())
		buttons.append(_continue)
	if DevHooks.has("sample-worlds"):  # [worlds2] shots: a profile with some history
		WorldPicker.dev_sample(int(DevHooks.get_f("sample-worlds", 4.0)))
	# [worlds2] Save profiles (and each profile's worlds).
	var pname: String = ProfileSlots.display_name(CradleMode.profile, SaveManager.profile_slot)
	# TRANSLATORS: Profiles button subtitle: the active save profile's name and its number of planets.
	_profiles_btn = _menu_button(tr("Profiles"), _open_profiles, "%s  ·  %s" % [pname, tr_n("%d planet", "%d planets", CradleMode.worlds().size()) % CradleMode.worlds().size()])
	buttons.append(_profiles_btn)
	_new_game = _menu_button(tr("New Game"), _on_new_game)
	buttons.append(_new_game)
	if Demo.is_demo():  # [steam]
		buttons.append(_menu_button(tr("Wishlist on Steam"), SteamService.open_store_page))
	buttons.append(_menu_button(tr("Settings"), _open_settings))
	buttons.append(_menu_button(tr("Credits"), _open_credits))
	buttons.append(_menu_button(tr("Quit"), func() -> void: get_tree().quit()))
	_chain_focus(buttons)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 26)
	col.add_child(spacer2)
	var ver: String = str(ProjectSettings.get_setting("application/config/version", ""))
	col.add_child(UITheme.label(("v" + ver + "   ·   " if ver != "" else "") + tr("Made with Godot"), 12, Color(1, 1, 1, 0.4)))

	_settings = SettingsPanel.new()
	_settings.closed.connect(_on_sub_closed.bind(2))
	_ui.add_child(_settings)
	_build_credits()
	_build_confirm()
	_picker = ProfilePicker.new()  # [worlds2]
	_picker.go.connect(func() -> void: _go(true))
	_picker.closed.connect(_on_profiles_closed)
	_ui.add_child(_picker)

	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.03, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)
	_main.modulate.a = 0.0
	_intro_ms = Time.get_ticks_msec()
	buttons[0].call_deferred("grab_focus")
	# --menu=settings / --menu=credits / --menu=confirm open a sub-screen (screenshots).
	match DevHooks.get_s("menu", ""):
		"settings":
			_open_settings.call_deferred()
			_settings.select_tab(int(DevHooks.get_f("tab", 0.0)))
		"credits": _open_credits.call_deferred()
		"confirm": _on_new_game.call_deferred()
		"profiles":  # [worlds2]
			_open_profiles.call_deferred()
		"worlds":  # [worlds2] profile, then its worlds
			(func() -> void:
				_open_profiles()
				_picker._continue(SaveManager.profile_slot)).call_deferred()


func _title_font() -> FontVariation:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = 0.55
	f.spacing_glyph = 10
	return f


## A big left-aligned menu entry with an amber edge on hover. Optional second line underneath.
func _menu_button(text: String, cb: Callable, sub: String = "") -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(340, 56 if sub == "" else 76)
	b.add_theme_font_size_override("font_size", 21)
	var pad_l: int = 22
	var normal: StyleBoxFlat = UITheme.box(Color(0.05, 0.055, 0.06, 0.55), Color(1, 1, 1, 0.1), 1, 3, 12)
	var hover: StyleBoxFlat = UITheme.box(Color(0.1, 0.09, 0.07, 0.8), UITheme.GOLD, 1, 3, 12)
	hover.border_width_left = 4
	var pressed: StyleBoxFlat = hover.duplicate()
	pressed.bg_color = Color(0.22, 0.15, 0.06, 0.9)
	for sb: StyleBoxFlat in [normal, hover, pressed]:
		sb.content_margin_left = pad_l
		if sub != "":
			sb.content_margin_bottom = 30
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_color_override("font_focus_color", UITheme.GOLD)
	if sub != "":
		var l := UITheme.label(sub, 13, Color(0.8, 0.8, 0.76))
		l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		l.offset_left = pad_l
		l.offset_top = -32
		l.offset_bottom = -12
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -4.0)
		cb.call())
	b.focus_entered.connect(func() -> void: Audio.play("blip", 1.6, -18.0, 0.0))
	UITheme.juice(b, 1.03)
	_menu_box.add_child(b)
	return b


func _chain_focus(list: Array[Button]) -> void:
	for i: int in list.size():
		var b: Button = list[i]
		b.focus_neighbor_top = b.get_path_to(list[wrapi(i - 1, 0, list.size())])
		b.focus_neighbor_bottom = b.get_path_to(list[wrapi(i + 1, 0, list.size())])
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)


func _save_summary() -> String:
	var hub: int = int(_save.get("current_hub", 0)) + 1
	var stats: Dictionary = _save.get("stats", {})
	var secs: int = int(float(stats.get("time_played", 0.0)))
	@warning_ignore("integer_division")
	var played: String = tr("%dh %02dm") % [secs / 3600, (secs / 60) % 60] if secs >= 3600 else tr("%dm") % maxi(1, secs / 60)
	var cubes: String = "0"
	var cur: Dictionary = _save.get("currencies", {})
	if cur.has("cubes"):
		cubes = Settings.fmt(BigNum.from_serialized(cur["cubes"]))
	# TRANSLATORS: Continue button subtitle: base number, play time, cube count (e.g. "Hub 2 · 1h 05m · 3.4K cubes").
	var parts: Array[String] = [tr("Hub %d") % hub, played, tr("%s cubes") % cubes]
	if CradleMode.worlds().size() > 1:  # [worlds2] which world Continue goes to
		parts.insert(0, CradleMode.world_name())
	var saved: float = float(_save.get("saved_unix", 0.0))
	if saved > 0.0:
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(int(saved + Time.get_time_zone_from_system().get("bias", 0) * 60))
		var months: Array[String] = [tr("Jan"), tr("Feb"), tr("Mar"), tr("Apr"), tr("May"), tr("Jun"), tr("Jul"), tr("Aug"), tr("Sep"), tr("Oct"), tr("Nov"), tr("Dec")]
		parts.append("%d %s %02d:%02d" % [dt["day"], months[int(dt["month"]) - 1], dt["hour"], dt["minute"]])
	return "  ·  ".join(parts)


# --- Actions --------------------------------------------------------------------------

func _on_continue() -> void:
	_go(true)


func _on_new_game() -> void:
	if _save.is_empty():
		_start_new()
		return
	_main.process_mode = Node.PROCESS_MODE_DISABLED
	_confirm.visible = true
	_confirm.modulate.a = 0.0
	create_tween().tween_property(_confirm, "modulate:a", 1.0, 0.18)
	_confirm_no.call_deferred("grab_focus")


func _start_new() -> void:
	CradleMode.reset_all()  # [late] New Game erases every Cradle Mode world and the Heirlooms too
	SaveManager.delete_save()
	GameState.new_game()
	_go(true)


## Fades out and loads the game. slice.gd loads the save if one exists (and no --fresh).
func _go(fade: bool) -> void:
	if _leaving:
		return
	_leaving = true
	SaveManager.enabled = not (DevHooks.has("fresh") or DevHooks.has("nosave"))
	if fade and _fade:
		_fade.mouse_filter = Control.MOUSE_FILTER_STOP
		var tw: Tween = create_tween().set_trans(Tween.TRANS_SINE)
		tw.tween_property(_fade, "color:a", 1.0, 0.45)
		tw.tween_callback(func() -> void: Loader.goto(GAME_SCENE))  # [intro2] loading screen
	else:
		Loader.goto(GAME_SCENE)


## [worlds2] Save profiles: pick a profile (and then a world), start over in one, rename or delete.
func _open_profiles() -> void:
	_main.process_mode = Node.PROCESS_MODE_DISABLED
	_picker.open_picker()


func _on_profiles_closed(changed: bool) -> void:
	if changed:  # another profile is active now: rebuild the menu (Continue, summaries)
		get_tree().reload_current_scene()
		return
	_on_sub_closed(4)


func _open_settings() -> void:
	_main.process_mode = Node.PROCESS_MODE_DISABLED
	_main.visible = false
	_settings.open_panel()


func _open_credits() -> void:
	_main.process_mode = Node.PROCESS_MODE_DISABLED
	_main.visible = false
	_credits.visible = true
	_credits.modulate.a = 0.0
	create_tween().tween_property(_credits, "modulate:a", 1.0, 0.2)
	(_credits.get_meta("back") as Button).call_deferred("grab_focus")


## Back from a sub-screen (1 = credits, 2 = settings, 3 = confirm): refocus the right button.
func _on_sub_closed(which: int) -> void:
	_credits.visible = false
	_confirm.visible = false
	_main.process_mode = Node.PROCESS_MODE_INHERIT
	_main.visible = true
	var target: Button = _new_game if which != 4 else _profiles_btn  # [worlds2]
	for c: Node in _menu_box.get_children():
		var b: Button = c as Button
		if b and ((which == 1 and b.text == tr("Credits").to_upper()) or (which == 2 and b.text == tr("Settings").to_upper())):
			target = b
	target.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or _ui == null:
		return
	if event.is_action_pressed("ui_cancel"):
		if _credits.visible:
			_on_sub_closed(1)
			get_viewport().set_input_as_handled()
		elif _confirm.visible:
			_on_sub_closed(3)
			get_viewport().set_input_as_handled()


func _build_credits() -> void:
	_credits = CenterContainer.new()
	_credits.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits.visible = false
	_ui.add_child(_credits)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(720, 0)
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.07, 0.88), UITheme.RUST, 1, 6, 22))
	_credits.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	vb.add_child(UITheme.label(tr("CREDITS"), 30, UITheme.GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_font_size_override("bold_font_size", 17)
	rt.add_theme_color_override("default_color", UITheme.CREAM)
	rt.text = _credits_bbcode()
	scroll.add_child(rt)
	var back := Button.new()
	back.text = tr("Back")
	back.custom_minimum_size = Vector2(150, 44)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(_on_sub_closed.bind(1))
	UITheme.juice(back)
	vb.add_child(back)
	_credits.set_meta("back", back)


## docs/CREDITS.md condensed: intro paragraphs, then "Asset - author" per table row, by type.
func _credits_bbcode() -> String:
	var gold: String = UITheme.GOLD.to_html(false)
	var muted: String = UITheme.MUTED.to_html(false)
	var out: String = tr("[b][color=#%s]GREENFALL[/color][/b]\nCode, procedural meshes, synthesized audio and writing are original to Greenfall.\n\n") % gold
	var f := FileAccess.open("res://docs/CREDITS.md", FileAccess.READ)
	if f == null:
		return out + tr("Third-party assets: CC0, Poly Haven (polyhaven.com).")
	var by_type: Dictionary = {}
	var order: Array[String] = []
	var tail: Array[String] = []
	var in_tail: bool = false
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.begins_with("| ") and not line.begins_with("| Asset") and not line.begins_with("|---"):
			var cells: PackedStringArray = line.split("|", false)
			if cells.size() >= 3:
				var asset: String = cells[0].strip_edges()
				var paren: int = asset.find(" (`")
				if paren > 0:
					asset = asset.substr(0, paren)
				var kind: String = cells[1].strip_edges().capitalize()
				if not by_type.has(kind):
					by_type[kind] = []
					order.append(kind)
				(by_type[kind] as Array).append(tr("%s [color=#%s]by %s[/color]") % [asset, muted, cells[2].strip_edges()])
		elif line.begins_with("## "):
			in_tail = true
			tail.append("[b][color=#%s]%s[/color][/b]" % [gold, line.substr(3).to_upper()])
		elif in_tail and line != "":
			tail.append(line)
		elif line.begins_with("All third-party"):
			out += line.replace("(https://polyhaven.com)", "(polyhaven.com)") + "\n\n"
	for kind: String in order:
		out += "[b][color=#%s]%sS[/color][/b]\n" % [gold, kind.to_upper()]
		out += "\n".join(PackedStringArray(by_type[kind])) + "\n\n"
	out += "\n".join(PackedStringArray(tail))
	return out


func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.visible = false
	_ui.add_child(_confirm)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(500, 0)
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.07, 0.94), UITheme.GOLD, 1, 6, 24))
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)
	vb.add_child(UITheme.label(tr("START A NEW GAME?"), 24, UITheme.GOLD))
	var msg := UITheme.label(tr("Your current save will be erased. This can't be undone."), 16)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(msg)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	_confirm_no = Button.new()
	_confirm_no.text = tr("Keep my save")
	_confirm_no.custom_minimum_size = Vector2(170, 46)
	_confirm_no.pressed.connect(_on_sub_closed.bind(3))
	UITheme.juice(_confirm_no)
	hb.add_child(_confirm_no)
	var yes := Button.new()
	yes.text = tr("Erase and start")
	yes.custom_minimum_size = Vector2(190, 46)
	UITheme.orange_button(yes)
	yes.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), Color.WHITE, 2, 5, 8))
	yes.pressed.connect(_start_new)
	UITheme.juice(yes)
	hb.add_child(yes)
	_confirm_no.focus_neighbor_right = _confirm_no.get_path_to(yes)
	yes.focus_neighbor_left = yes.get_path_to(_confirm_no)
	for b: Button in [_confirm_no, yes]:
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)
