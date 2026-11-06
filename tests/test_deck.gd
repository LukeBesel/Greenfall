extends GutTest
## [deck] Steam Deck / controller and performance pass: hardware preset detection, the
## frame-rate probe rule, pad glyph names, prompt templates, the font floor and MeshBatch.

const TEST_PATH: String = "user://test_deck_settings.cfg"

var _saved_path: String
var _saved: Dictionary = {}


func before_each() -> void:
	_saved_path = Settings.settings_path
	Settings.settings_path = TEST_PATH
	for k: String in ["quality", "quality_auto", "quality_note", "quality_probe_done", "glyph_style", "last_input_pad", "render_scale", "ui_scale", "stick_sensitivity"]:
		_saved[k] = Settings.get(k)


func after_each() -> void:
	for k: String in _saved:
		Settings.set(k, _saved[k])
	Settings.settings_path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _info(adapter: String, type: int, os_name: String = "Windows", screen := Vector2i(1920, 1080), extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"adapter": adapter, "vendor": "", "type": type, "os": os_name, "arch": "x86_64",
		"screen": screen, "dpi": 96, "steam_deck_env": false, "method": "forward_plus", "ram_gb": 16.0}
	d.merge(extra, true)
	return d


# --- Quality detection ---------------------------------------------------------------------

func test_steam_deck_gets_low_and_bigger_ui() -> void:
	var by_name: Dictionary = QualityDetect.pick(_info("AMD Custom GPU 0405 (RADV VANGOGH)", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, "Linux", Vector2i(1280, 800)))
	assert_eq(int(by_name["quality"]), QualityDetect.LOW)
	assert_true(by_name["deck"])
	assert_almost_eq(float(by_name["ui_scale"]), 1.1, 0.001)
	assert_almost_eq(float(by_name["render_scale"]), 1.0, 0.001)
	var by_env: Dictionary = QualityDetect.pick(_info("AMD Radeon Graphics", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, "Linux", Vector2i(1280, 800), {"steam_deck_env": true}))
	assert_true(by_env["deck"])
	assert_string_contains(str(by_env["note"]), "Steam Deck")


func test_integrated_and_discrete_pc() -> void:
	assert_eq(int(QualityDetect.pick(_info("Intel(R) UHD Graphics 620", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU))["quality"]), QualityDetect.LOW)
	assert_eq(int(QualityDetect.pick(_info("NVIDIA GeForce RTX 3060", RenderingDevice.DEVICE_TYPE_DISCRETE_GPU))["quality"]), QualityDetect.HIGH)
	assert_eq(int(QualityDetect.pick(_info("NVIDIA GeForce GTX 1050 Ti", RenderingDevice.DEVICE_TYPE_DISCRETE_GPU))["quality"]), QualityDetect.MEDIUM)
	# Integrated GPU on a 1440p screen: Low with a smaller 3D render (FSR upscaled).
	var big: Dictionary = QualityDetect.pick(_info("AMD Radeon(TM) Graphics", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, "Windows", Vector2i(2560, 1440)))
	assert_eq(int(big["quality"]), QualityDetect.LOW)
	assert_lt(float(big["render_scale"]), 1.0)
	assert_eq(float(big["ui_scale"]), 0.0, "a desktop screen keeps its interface scale")


func test_macs() -> void:
	var m1: Dictionary = QualityDetect.pick(_info("Apple M1", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, "macOS", Vector2i(1440, 900), {"arch": "arm64"}))
	assert_eq(int(m1["quality"]), QualityDetect.MEDIUM)
	assert_string_contains(str(m1["note"]), "Apple Silicon")
	var max_chip: Dictionary = QualityDetect.pick(_info("Apple M2 Max", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, "macOS", Vector2i(1728, 1117), {"arch": "arm64"}))
	assert_eq(int(max_chip["quality"]), QualityDetect.HIGH)
	var intel_mac: Dictionary = QualityDetect.pick(_info("Intel(R) Iris(TM) Plus Graphics", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, "macOS"))
	assert_eq(int(intel_mac["quality"]), QualityDetect.LOW)
	assert_string_contains(str(intel_mac["note"]), "Intel Mac")


func test_software_and_other_renderers_are_low() -> void:
	assert_eq(int(QualityDetect.pick(_info("llvmpipe (LLVM 15.0.7, 256 bits)", RenderingDevice.DEVICE_TYPE_CPU, "Linux"))["quality"]), QualityDetect.LOW)
	assert_eq(int(QualityDetect.pick(_info("NVIDIA GeForce RTX 4090", RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, "Windows", Vector2i(1920, 1080), {"method": "mobile"}))["quality"]), QualityDetect.LOW)


func test_low_memory_steps_down() -> void:
	var d: Dictionary = QualityDetect.pick(_info("NVIDIA GeForce RTX 2060", RenderingDevice.DEVICE_TYPE_DISCRETE_GPU, "Windows", Vector2i(1920, 1080), {"ram_gb": 4.0}))
	assert_eq(int(d["quality"]), QualityDetect.MEDIUM)


func test_probe_rule() -> void:
	assert_eq(QualityProbe.next_quality(2, 38.0), 1)
	assert_eq(QualityProbe.next_quality(2, 58.0), 2)
	assert_eq(QualityProbe.next_quality(0, 20.0), 0, "never below Low")
	assert_true(QualityProbe.wanted(true, false, 2, false, false))
	assert_false(QualityProbe.wanted(false, false, 2, false, false), "a manual preset is never probed")
	assert_false(QualityProbe.wanted(true, true, 2, false, false), "runs once")
	assert_false(QualityProbe.wanted(true, false, 2, true, false), "not headless")
	assert_false(QualityProbe.wanted(true, false, 2, false, true), "not in tool runs")


func test_manual_choice_turns_auto_off_and_persists() -> void:
	Settings.quality_auto = true
	Settings.quality_note = "Steam Deck"
	Settings.set_quality_manual(1)
	assert_false(Settings.quality_auto)
	assert_true(Settings.quality_probe_done)
	Settings.glyph_style = PadGlyphs.Style.PLAYSTATION
	Settings.stick_sensitivity = 1.4
	Settings.save_settings()
	Settings.stick_sensitivity = 1.0
	Settings.quality = 3
	Settings.quality_auto = true
	Settings.glyph_style = 0
	Settings.load_settings()
	assert_eq(Settings.quality, 1)
	assert_false(Settings.quality_auto)
	assert_eq(Settings.quality_note, "Steam Deck")
	assert_eq(Settings.glyph_style, PadGlyphs.Style.PLAYSTATION)
	assert_almost_eq(Settings.stick_sensitivity, 1.4, 0.001)


func test_particles_scale_with_preset() -> void:
	Settings.quality = 0
	assert_almost_eq(Settings.particle_scale(), 0.5, 0.001)
	Settings.quality = 2
	assert_almost_eq(Settings.particle_scale(), 1.0, 0.001)


# --- Controller --------------------------------------------------------------------------

func test_pad_can_confirm_and_back() -> void:
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	assert_true(a.is_action("ui_accept"), "A presses the focused button")
	assert_true(b.is_action("ui_cancel"), "B backs out of menus")


func test_glyph_names_per_family() -> void:
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	var lb := InputEventJoypadButton.new()
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	assert_eq(PadGlyphs.event_name(a, PadGlyphs.Style.XBOX), "A")
	assert_eq(PadGlyphs.event_name(a, PadGlyphs.Style.PLAYSTATION), "Cross")
	assert_eq(PadGlyphs.event_name(lb, PadGlyphs.Style.PLAYSTATION), "L1")
	assert_eq(PadGlyphs.event_name(lb, PadGlyphs.Style.DECK), "L1")
	assert_eq(PadGlyphs.event_name(rt, PadGlyphs.Style.XBOX), "RT")
	assert_eq(PadGlyphs.event_name(rt, PadGlyphs.Style.DECK), "R2")
	assert_eq(str(PadGlyphs.badge(a, PadGlyphs.Style.PLAYSTATION)["shape"]), "ps_cross")
	assert_eq(str(PadGlyphs.badge(a, PadGlyphs.Style.XBOX)["shape"]), "face")
	assert_eq(str(PadGlyphs.badge(rt, PadGlyphs.Style.XBOX)["shape"]), "trigger")


func test_style_from_controller_name() -> void:
	assert_eq(PadGlyphs.style_for_name("PS5 Controller"), PadGlyphs.Style.PLAYSTATION)
	assert_eq(PadGlyphs.style_for_name("Sony DualSense Wireless Controller"), PadGlyphs.Style.PLAYSTATION)
	assert_eq(PadGlyphs.style_for_name("Steam Deck"), PadGlyphs.Style.DECK)
	assert_eq(PadGlyphs.style_for_name("Steam Virtual Gamepad", true), PadGlyphs.Style.DECK)
	assert_eq(PadGlyphs.style_for_name("Xbox Series X Controller"), PadGlyphs.Style.XBOX)
	assert_eq(PadGlyphs.style_for_name(""), PadGlyphs.Style.XBOX)


func test_settings_glyph_follows_family() -> void:
	Settings.last_input_pad = true
	Settings.glyph_style = PadGlyphs.Style.PLAYSTATION
	assert_eq(Settings.glyph("interact"), "Cross")
	Settings.glyph_style = PadGlyphs.Style.XBOX
	assert_eq(Settings.glyph("interact"), "A")
	Settings.last_input_pad = false
	assert_eq(Settings.glyph("interact"), "E")


func test_prompt_template_parse() -> void:
	var t: String = "{ui_tab_prev}{ui_tab_next}  switch   [k]Wheel  zoom[/k][p]{zoom_in}  zoom[/p]  {kbd:open_command}{pad:ui_cancel}  back"
	var kb: Array = PromptLabel.parse(t, false)
	var pad: Array = PromptLabel.parse(t, true)
	assert_eq(kb, [["glyph", "ui_tab_prev"], ["glyph", "ui_tab_next"], ["text", "  switch   Wheel  zoom  "], ["glyph", "open_command"], ["text", "  back"]])
	assert_eq(pad, [["glyph", "ui_tab_prev"], ["glyph", "ui_tab_next"], ["text", "  switch   "], ["glyph", "zoom_in"], ["text", "  zoom  "], ["glyph", "ui_cancel"], ["text", "  back"]])


func test_tutorial_text_uses_glyphs() -> void:
	Settings.last_input_pad = true
	Settings.glyph_style = PadGlyphs.Style.XBOX
	assert_eq(Tutorial.glyphs("Hold  {scoop}  to scoop"), "Hold  RT  to scoop")
	Settings.last_input_pad = false
	assert_eq(Tutorial.glyphs("Hold  {scoop}  to scoop"), "Hold  LMB  to scoop")


func test_prompt_glyph_specs() -> void:
	assert_eq(str(PromptGlyph.spec_for("@move", true)["shape"]), "stick")
	assert_eq(str(PromptGlyph.spec_for("@move", false)["text"]), "WASD")
	assert_eq(str(PromptGlyph.spec_for("#0", true)["shape"]), "face")
	assert_eq(str(PromptGlyph.spec_for("interact", false)["text"]), "E")


# --- Readability -------------------------------------------------------------------------

func test_font_floor() -> void:
	var l := UITheme.label("tiny", 10)
	add_child_autofree(l)
	await get_tree().process_frame
	assert_gte(l.get_theme_font_size("font_size"), Settings.MIN_FONT_PX)
	var hidden := UITheme.label("", 1)
	add_child_autofree(hidden)
	await get_tree().process_frame
	assert_eq(hidden.get_theme_font_size("font_size"), 1, "deliberately tiny helper labels are left alone")
	var big := UITheme.label("big", 20)
	assert_false(ReadableUI.enforce(big))
	big.free()


# --- Batching ----------------------------------------------------------------------------

func test_mesh_batch_instances_and_merges() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var mat := StandardMaterial3D.new()
	var box: Mesh = BoxMesh.new()
	var b := MeshBatch.new()
	for i: int in 5:
		b.instance(box, Transform3D(Basis.IDENTITY, Vector3(i * 2.0, 0, 0)), mat)
	var p1 := PlaneMesh.new()
	var p2 := PlaneMesh.new()
	b.merge(p1, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), mat, false)
	b.merge(p2, Transform3D(Basis.from_scale(Vector3(-1, 1, 1)), Vector3(5, 1, 0)), mat, false)
	var nodes: Array = b.flush(root)
	assert_eq(nodes.size(), 2, "5 boxes -> one MultiMesh, 2 planes -> one merged mesh")
	var mmi: MultiMeshInstance3D = null
	var mi: MeshInstance3D = null
	for n: Node in nodes:
		if n is MultiMeshInstance3D:
			mmi = n
		elif n is MeshInstance3D:
			mi = n
	assert_not_null(mmi)
	assert_eq(mmi.multimesh.instance_count, 5)
	assert_eq(mmi.material_override, mat)
	assert_not_null(mi)
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var src: Array = p1.surface_get_arrays(0)
	assert_eq((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 2)
	assert_not_null(arr[Mesh.ARRAY_TANGENT], "tangents kept (normal maps)")
	assert_not_null(arr[Mesh.ARRAY_TEX_UV], "UVs kept")
	# Mirrored part: normals still point up and faces keep their winding (up-facing).
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	assert_almost_eq(nrm[nrm.size() - 1].y, 1.0, 0.001)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var last: int = idx.size() - 3
	var face_n: Vector3 = (v[idx[last + 2]] - v[idx[last]]).cross(v[idx[last + 1]] - v[idx[last]])
	var first_n: Vector3 = (v[idx[2]] - v[idx[0]]).cross(v[idx[1]] - v[idx[0]])
	assert_gt(face_n.y * first_n.y, 0.0, "mirrored copy has the same facing as the original")


func test_mesh_batch_cells_split() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var box: Mesh = BoxMesh.new()
	var b := MeshBatch.new()
	b.cell = 10.0
	b.instance(box, Transform3D(Basis.IDENTITY, Vector3(1, 0, 1)))
	b.instance(box, Transform3D(Basis.IDENTITY, Vector3(2, 0, 2)))
	b.instance(box, Transform3D(Basis.IDENTITY, Vector3(25, 0, 1)))
	assert_eq(b.flush(root).size(), 2)
