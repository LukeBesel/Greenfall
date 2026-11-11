extends Node
## [v6sound] Dev: --sound-log[=file] logs every sound that starts, with its bus, level and time,
## and prints a summary table when the run ends (and into screenshots/sound_log_summary.json).
## Used with a long autoplay to find sounds that repeat too often or stack:
##   godot --headless --path . -- --fresh --orbit --no-intro --autoplay --time-scale=4 --sound-log --quit-after=1200
## Times are game seconds (they follow the time scale), so the numbers read as the player would
## hear them at normal speed. Sources:
## - Audio.play() and the planet ambience call played() themselves (exact, with the sound's name);
## - every other AudioStreamPlayer / 2D / 3D in the tree is watched for the moment it starts.
## The score's note voices (Audio/MusicVoices) are only counted, per minute.
## A "repeat" is the same sound starting again within REPEAT_S; "stack" is how many of the same
## sound were sounding at once.

const REPEAT_S: float = 5.0
const DEFAULT_OUT: String = "res://screenshots/sound_log.txt"
const SUMMARY: String = "res://screenshots/sound_log_summary.json"

var out_path: String = ""
var _file: FileAccess
var _watch: Array = []  # [player, was_playing, last_pos, name]
var _stats: Dictionary = {}  # name -> {n, bus, db_sum, db_max, last, min_gap, repeats, stack, ends:[], drops}
var _notes: int = 0
var _real0: int = 0
var _done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_real0 = Time.get_ticks_msec()
	var path: String = out_path if out_path != "" else DEFAULT_OUT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file:
		_file.store_line("game_s\treal_s\tbus\tdb\tsound\tfrom")
	get_tree().node_added.connect(_on_node)
	_scan(get_tree().root)
	print("[snd] sound log on (%s)" % path)


func _scan(n: Node) -> void:
	_on_node(n)
	for c: Node in n.get_children():
		_scan(c)


func _on_node(n: Node) -> void:
	if not (n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D):
		return
	# Audio's one-shot pool and the ambience one-shots report through played(); they are created
	# with no stream, unlike the loop players, which are watched like any other player.
	var par: Node = n.get_parent()
	var pooled: bool = par == Audio or (par != null and par.name == "Ambience" and par.get_parent() == Audio)
	if pooled and n.get("stream") == null:
		return
	_watch.append([n, false, 0.0])


func _is_loop(p: Node) -> bool:
	var st: Variant = p.get("stream")
	if st == null:
		return true  # set later: Audio.loop() players and the ambience beds
	if st is AudioStreamWAV:
		return (st as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	return bool((st as Object).get("loop")) if (st as Object).get("loop") != null else false


func _name_of(p: Node) -> String:
	var st: AudioStream = p.get("stream")
	var par: Node = p.get_parent()
	if par != null and par.name == "TunesDirector":
		return "song:" + st.resource_path.get_file().get_basename() if st != null and st.resource_path != "" else "song"
	if st != null and st.resource_path != "" and not st.resource_path.contains("::"):
		return st.resource_path.get_file().get_basename()
	var owner_name: String = str(par.name) if par else "?"
	owner_name = owner_name.rstrip("0123456789@")
	var own: String = str(p.name).rstrip("0123456789@")
	if own == "" or own.begins_with("AudioStreamPlayer") or own.begins_with("_"):
		own = "player"
	return "%s/%s" % [owner_name, own]


func _process(_delta: float) -> void:
	var i: int = 0
	while i < _watch.size():
		var w: Array = _watch[i]
		var p: Variant = w[0]
		if not is_instance_valid(p):
			_watch.remove_at(i)
			continue
		var node: Node = p
		var playing: bool = bool(node.get("playing"))
		var pos: float = float(node.call("get_playback_position")) if playing else 0.0
		var restarted: bool = playing and bool(w[1]) and pos < float(w[2]) - 0.05 and not _is_loop(node)
		if (playing and not bool(w[1])) or restarted:
			var par: Node = node.get_parent()
			if par != null and par.name == "MusicVoices":
				_notes += 1
			else:
				var st: AudioStream = node.get("stream")
				var length: float = st.get_length() if st else 0.0
				played(_name_of(node), str(node.get("bus")), float(node.get("volume_db")), 0.0 if _is_loop(node) else length)
		w[1] = playing
		w[2] = pos
		i += 1


## A sound started. `length` (seconds) is used for the stack count; 0 for a loop.
func played(sound: String, bus: String, db: float, length: float) -> void:
	var t: float = Audio.game_t
	var who: String = _caller()
	if _file:
		_file.store_line("%.2f\t%.2f\t%s\t%.1f\t%s\t%s" % [t, (Time.get_ticks_msec() - _real0) / 1000.0, bus, db, sound, who])
	var s: Dictionary = _stat(sound)
	var by: Dictionary = s["by"]
	by[who] = int(by.get(who, 0)) + 1
	s["bus"] = bus
	s["n"] = int(s["n"]) + 1
	s["db_sum"] = float(s["db_sum"]) + db
	s["db_max"] = maxf(float(s["db_max"]), db)
	if float(s["last"]) >= 0.0:
		var gap: float = t - float(s["last"])
		s["min_gap"] = minf(float(s["min_gap"]), gap)
		if gap < REPEAT_S:
			s["repeats"] = int(s["repeats"]) + 1
	s["last"] = t
	var ends: Array = s["ends"]
	for k: int in range(ends.size() - 1, -1, -1):
		if float(ends[k]) <= t:
			ends.remove_at(k)
	ends.append(t + length)
	s["stack"] = maxi(int(s["stack"]), ends.size())


## Who asked for the sound: the first script line outside the audio code (debug builds only).
func _caller() -> String:
	for f: Dictionary in get_stack():
		var src: String = str(f.get("source", ""))
		if src.ends_with("sound_log.gd") or src.ends_with("Audio.gd") or src.ends_with("ambience.gd"):
			continue
		return "%s:%d" % [src.get_file(), int(f.get("line", 0))]
	return "player node"


## A play that the min_gap_s gate dropped (data/sound.json).
func dropped(sound: String) -> void:
	var s: Dictionary = _stat(sound)
	s["drops"] = int(s["drops"]) + 1


func _stat(sound: String) -> Dictionary:
	if not _stats.has(sound):
		_stats[sound] = {"n": 0, "bus": "", "db_sum": 0.0, "db_max": -99.0, "last": -1.0, "min_gap": 1.0e9,
			"repeats": 0, "stack": 0, "ends": [], "drops": 0, "by": {}}
	return _stats[sound]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		report()


func report() -> void:
	if _done:
		return
	_done = true
	var minutes: float = maxf(Audio.game_t / 60.0, 0.01)
	var names: Array = _stats.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return int(_stats[a]["n"]) > int(_stats[b]["n"]))
	print("[snd] %.1f game minutes (%.0f s real). Score notes: %d (%.0f a minute)." % [minutes,
		(Time.get_ticks_msec() - _real0) / 1000.0, _notes, _notes / minutes])
	print("[snd] %-30s %-9s %6s %7s %7s %7s %8s %6s %6s" % ["sound", "bus", "plays", "per min", "avg dB", "max dB", "min gap", "<%ds" % int(REPEAT_S), "stack"])
	var out: Dictionary = {"minutes": minutes, "notes": _notes, "sounds": {}}
	var by_bus: Dictionary = {}
	for nm: String in names:
		var s: Dictionary = _stats[nm]
		var n: int = int(s["n"])
		by_bus[s["bus"]] = int(by_bus.get(s["bus"], 0)) + n
		var row: Dictionary = {"bus": s["bus"], "plays": n, "per_min": n / minutes, "avg_db": float(s["db_sum"]) / maxi(n, 1),
			"max_db": s["db_max"], "min_gap": s["min_gap"] if n > 1 else -1.0, "repeats": s["repeats"], "stack": s["stack"], "drops": s["drops"],
			"by": s["by"]}
		(out["sounds"] as Dictionary)[nm] = row
		if n == 0:
			print("[snd] %-30s %-9s %6d   (all %d plays dropped by min_gap_s)" % [nm.left(30), "-", 0, int(s["drops"])])
			continue
		print("[snd] %-30s %-9s %6d %7.2f %7.1f %7.1f %8s %6d %6d%s" % [nm.left(30), str(s["bus"]), n, n / minutes,
			float(row["avg_db"]), float(s["db_max"]), ("%.2f" % float(s["min_gap"])) if n > 1 else "-", int(s["repeats"]), int(s["stack"]),
			("  (%d dropped)" % int(s["drops"])) if int(s["drops"]) > 0 else ""])
		var by: Dictionary = s["by"]
		var who: Array = by.keys()
		who.sort_custom(func(a: String, b: String) -> bool: return int(by[a]) > int(by[b]))
		var parts: PackedStringArray = []
		for w: String in who.slice(0, 3):
			parts.append("%s x%d" % [w, int(by[w])])
		print("[snd]     from %s" % ", ".join(parts))
	print("[snd] plays per bus: %s" % str(by_bus))
	out["by_bus"] = by_bus
	var f := FileAccess.open(SUMMARY, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, " "))
		f.close()
	if _file:
		_file.close()
		_file = null
