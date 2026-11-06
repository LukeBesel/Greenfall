class_name SteamCloud
extends RefCounted
## Steam Cloud sync for save files through ISteamRemoteStorage (GodotSteam's fileWrite/fileRead).
## Used by SteamService when greenfall/steam/cloud_mode = "remote_storage". With "auto_cloud"
## Steam itself syncs user:// (see docs/steam/README.md) and this class is not used.
##
## Conflict rule: the copy with the newest save time wins. "Save time" is the saved_unix stamp
## inside the save (GameState.to_dict), which survives copies and clock-skewed file systems; the
## Steam file timestamp / local mtime are only used when a save cannot be parsed. Ties keep local.
## A cloud copy that replaces a local save leaves the old local file as <name>.local_bak.

var api: Object


func _init(p_api: Object) -> void:
	api = p_api


## Pure decision: "cloud", "local" or "none" (nothing to do: both missing).
static func pick_newer(local_exists: bool, local_saved: float, cloud_exists: bool, cloud_saved: float) -> String:
	if not local_exists and not cloud_exists:
		return "none"
	if not cloud_exists:
		return "local"
	if not local_exists:
		return "cloud"
	return "cloud" if cloud_saved > local_saved + 0.5 else "local"


## saved_unix inside a compressed save file's bytes (0 when unreadable).
static func saved_unix_of_bytes(bytes: PackedByteArray) -> float:
	if bytes.is_empty():
		return 0.0
	var tmp: String = "user://.steam_cloud_probe.tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return 0.0
	f.store_buffer(bytes)
	f.close()
	var d: Dictionary = SaveManager.read_dict(tmp)
	DirAccess.remove_absolute(tmp)
	return float(d.get("saved_unix", 0.0))


static func saved_unix_of_file(path: String) -> float:
	if not FileAccess.file_exists(path):
		return 0.0
	var t: float = float(SaveManager.read_dict(path).get("saved_unix", 0.0))
	return t if t > 0.0 else float(FileAccess.get_modified_time(path))


func enabled() -> bool:
	if api == null:
		return false
	for m: String in ["isCloudEnabledForAccount", "isCloudEnabledForApp"]:
		if api.has_method(m) and not bool(api.call(m)):
			return false
	return api.has_method("fileWrite") and api.has_method("fileRead")


func cloud_exists(name: String) -> bool:
	return api != null and api.has_method("fileExists") and bool(api.call("fileExists", name))


func read(name: String) -> PackedByteArray:
	if not cloud_exists(name):
		return PackedByteArray()
	var size: int = int(api.call("getFileSize", name)) if api.has_method("getFileSize") else 0
	var r: Variant = api.call("fileRead", name, size)
	if r is Dictionary and bool((r as Dictionary).get("ret", false)):
		return (r as Dictionary).get("buf", PackedByteArray())
	return r if r is PackedByteArray else PackedByteArray()


## Upload a local file. Returns true when Steam accepted it.
func push(local_path: String) -> bool:
	if not enabled() or not FileAccess.file_exists(local_path):
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(local_path)
	if bytes.is_empty():
		return false
	return bool(api.call("fileWrite", local_path.get_file(), bytes, bytes.size()))


func delete(name: String) -> void:
	if cloud_exists(name) and api.has_method("fileDelete"):
		api.call("fileDelete", name)


## File names (no folder) of every cloud file ending with `suffix`.
func list(suffix: String = ".save") -> PackedStringArray:
	var out := PackedStringArray()
	if api == null or not api.has_method("getFileCount"):
		return out
	for i: int in int(api.call("getFileCount")):
		var r: Variant = api.call("getFileNameAndSize", i)
		var nm: String = str((r as Dictionary).get("name", "")) if r is Dictionary else str(r)
		if nm.ends_with(suffix):
			out.append(nm)
	return out


## Bring `dir` and the cloud in step, newest save wins per file. Returns {name: "cloud"|"local"}.
func sync_dir(dir: String) -> Dictionary:
	var result: Dictionary = {}
	if not enabled():
		return result
	DirAccess.make_dir_recursive_absolute(dir)
	var names: Dictionary = {}
	for nm: String in list():
		names[nm] = true
	for nm: String in DirAccess.get_files_at(dir):
		if nm.ends_with(".save"):
			names[nm] = true
	for nm: String in names:
		var path: String = dir.path_join(nm)
		var bytes: PackedByteArray = read(nm)
		var pick: String = pick_newer(FileAccess.file_exists(path), saved_unix_of_file(path), not bytes.is_empty(), saved_unix_of_bytes(bytes))
		if pick == "cloud":
			if FileAccess.file_exists(path):
				DirAccess.copy_absolute(path, path + ".local_bak")
			var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
			if f == null:
				continue
			f.store_buffer(bytes)
			f.close()
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			DirAccess.rename_absolute(path + ".tmp", path)
		elif pick == "local":
			push(path)
		result[nm] = pick
	return result
