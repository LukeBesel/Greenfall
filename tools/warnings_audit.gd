extends SceneTree
## [health] GDScript warnings audit. Godot only shows warnings in the editor (or to an attached
## debugger), so tools/warnings_audit.sh turns every "warn" level warning into an error through a
## temporary override.cfg and this script compiles every project script once (on the first frame); each warning is then
## printed as "SCRIPT ERROR: Parse Error: ... (Warning treated as error.)" with its file and line.
## Run through tools/warnings_audit.sh, not directly. Skips addons/ (GUT).
##   --list-levels   print the warn-level settings as override.cfg lines (used by the shell script)

const SKIP: Array[String] = ["res://addons/", "res://.godot/"]


func _init() -> void:
	if "--list-levels" in OS.get_cmdline_user_args():
		var out: PackedStringArray = ["[debug]"]
		var extra: String = ""
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--extra="):
				extra = a.trim_prefix("--extra=")
		for p: Dictionary in ProjectSettings.get_property_list():
			var n: String = p["name"]
			if not n.begins_with("debug/gdscript/warnings/") or not (ProjectSettings.get_setting(n) is int):
				continue
			var lvl: int = int(ProjectSettings.get_setting(n))
			var short: String = n.get_file()
			if lvl == 1 or (extra != "" and short in extra.split(",")):
				out.append(n.trim_prefix("debug/") + "=2")
		print("\n".join(out))
		quit()
		return
	# Compile on the first frame: autoload names (Settings, Economy...) only resolve once they exist.
	process_frame.connect(_audit, CONNECT_ONE_SHOT)


func _audit() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	for f: String in files:
		if OS.get_environment("WA_VERBOSE") != "":
			print("[wa] ", f)
		# Each script compiles (and reports) once; already-loaded ones (autoloads, their deps)
		# reported when they first compiled at startup. Reloading those in place crashes.
		if not ResourceLoader.has_cached(f):
			ResourceLoader.load(f)
	print("[warnings_audit] compiled %d scripts" % files.size())
	quit()


func _collect(dir: String, out: Array[String]) -> void:
	for s: String in SKIP:
		if dir.begins_with(s):
			return
	for f: String in DirAccess.get_files_at(dir):
		if f.get_extension() == "gd":
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_collect(dir.path_join(d) + "/", out)
