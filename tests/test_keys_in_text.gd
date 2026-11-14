extends GutTest
## [v9d] Player text never names a key: "press E", "(H)", "LMB" read wrong after a rebind and on a
## pad. Key names go through the binding glyphs ({interact}, {garden_mode}, ... filled in by
## Objectives.glyphs / Tutorial.glyphs). Interact prompts that start with "E   " are fine: the HUD
## swaps that E for the binding (ui/hud.gd _prompt_text).

const DIRS: Array[String] = ["res://story", "res://ui", "res://systems", "res://scenes", "res://automation", "res://plants",
	"res://fauna", "res://player", "res://planet", "res://robots", "res://core"]
## Device-specific help that names the device's own fixed controls (photo mode's free camera, the
## Command view's paint buttons): not rebindable actions.
const ALLOW_FILES: Array[String] = ["res://ui/photo_panel.gd", "res://robots/sphere/command_overlay.gd"]
const DATA_KEYS: Array[String] = ["text", "short", "desc", "hint", "toast", "hud", "lines", "prompt", "body", "title", "name"]

var _key_re := RegEx.new()


func before_all() -> void:
	_key_re.compile("(\\b(?:[Pp]ress|[Hh]old|[Tt]ap)\\s+(?:[A-Z](?![a-z])|[0-9](?![0-9,.])|Tab|Space|Shift|Esc|LMB|RMB)\\b)|(\\([A-Z]\\))|(\\bLMB\\b)|(\\bRMB\\b)")


func bad(t: String) -> bool:
	if t.begins_with("E   ") or t.begins_with("_"):
		return false
	return _key_re.search(t) != null


func test_the_check_catches_key_names() -> void:
	assert_true(bad("Walk up and press E to open it"))
	assert_true(bad("Place a decoration (H)"))
	assert_true(bad("then hold LMB on a bed"))
	assert_false(bad("Press {interact} to open it"))
	assert_false(bad("Press 1,000 bales."))
	assert_false(bad("E   Open the workbench"))


func test_no_key_names_in_code_strings() -> void:
	var str_re := RegEx.new()
	str_re.compile("(?:\\btr|translate|tr_n)\\(\"((?:[^\"\\\\]|\\\\.)*)\"")
	var hits: Array[String] = []
	for d: String in DIRS:
		for f: String in _files(d, "gd"):
			if f in ALLOW_FILES:
				continue
			var lines: PackedStringArray = FileAccess.get_file_as_string(f).split("\n")
			for i: int in lines.size():
				for m: RegExMatch in str_re.search_all(lines[i]):
					if bad(m.get_string(1)):
						hits.append("%s:%d  %s" % [f, i + 1, m.get_string(1).left(90)])
	assert_eq(hits.size(), 0, "\n".join(hits))


func test_no_key_names_in_data_text() -> void:
	var hits: Array[String] = []
	for f: String in _files("res://data", "json"):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		_walk(d, "", f, hits)
	assert_eq(hits.size(), 0, "\n".join(hits))


func _walk(v: Variant, key: String, f: String, hits: Array[String]) -> void:
	if v is Dictionary:
		for k: Variant in v:
			_walk((v as Dictionary)[k], str(k), f, hits)
	elif v is Array:
		for e: Variant in v:
			_walk(e, key, f, hits)
	elif v is String and key in DATA_KEYS and bad(str(v)):
		hits.append("%s [%s]  %s" % [f, key, str(v).left(90)])


func _files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f: String in da.get_files():
		if f.get_extension() == ext:
			out.append(dir.path_join(f))
	for sub: String in da.get_directories():
		out.append_array(_files(dir.path_join(sub), ext))
	return out
