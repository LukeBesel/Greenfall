class_name ProfileSlots
extends RefCounted
## [worlds2] The three save profiles (SaveManager.profile_dir: user://saves/p1..p3). Each holds its
## own Cradle Mode profile (profile.save: worlds, Starseeds, Heirlooms, the profile's name) and its
## worlds' save slots; settings are shared. This reads summaries for the title screen
## (ui/profile_picker.gd) and renames profiles. Pure helpers take dictionaries so tests need no files.

const NAME_MAX: int = 24

## Dev (title shots): summaries shown in place of slots' files, {n: summary}.
static var dev_summaries: Dictionary = {}


## A title-screen summary from a profile dict and its current world's save dict (pure):
## {empty, name, time_s, worlds, world, district, bloom_pct, saved_unix}.
static func summary_from(prof: Dictionary, save: Dictionary, n: int) -> Dictionary:
	var empty: bool = save.is_empty() and prof.is_empty()
	var out: Dictionary = {"empty": empty, "name": display_name(prof, n), "time_s": 0.0, "worlds": 0, "world": "",
		"district": "", "bloom_pct": 0, "saved_unix": 0.0}
	if empty:
		return out
	var ws: Array = prof.get("worlds", [])
	var cur: int = clampi(int(prof.get("current", 0)), 0, maxi(ws.size() - 1, 0))
	var t: float = 0.0
	for i: int in ws.size():
		if i != cur and ws[i] is Dictionary:
			t += float(((ws[i] as Dictionary).get("stats", {}) as Dictionary).get("time_played", 0.0))
	t += float((save.get("stats", {}) as Dictionary).get("time_played", 0.0))
	out["time_s"] = t
	out["worlds"] = maxi(ws.size(), 1)
	out["world"] = str((ws[cur] as Dictionary).get("name", "Verdance")) if not ws.is_empty() and ws[cur] is Dictionary else "Verdance"
	var flags: Dictionary = save.get("flags", {})
	out["district"] = str(flags.get("last_district", "")) if flags.get("last_district", "") != "<null>" else ""
	var total: int = maxi(Bloom.milestones().size(), 1)
	out["bloom_pct"] = int(round(100.0 * float((flags.get("bloom_done", []) as Array).size()) / float(total)))
	# The three currencies only (Cubes, Parts, Seeds), as numbers for the card.
	var money: Dictionary = save.get("currencies", {})
	for k: String in ["cubes", "seeds"]:
		out[k] = BigNum.from_serialized(money[k]).to_float() if money.has(k) else 0.0
	out["parts"] = BigNum.from_serialized(money["parts"]).to_float() if money.has("parts") else float((save.get("parts", []) as Array).size())
	out["saved_unix"] = maxf(float(save.get("saved_unix", 0.0)), float(prof.get("saved_unix", 0.0)))
	return out


## The profile's own name, or "Profile N".
static func display_name(prof: Dictionary, n: int) -> String:
	var nm: String = str(prof.get("name", "")).strip_edges()
	return nm if nm != "" else TranslationServer.translate("Profile %d") % n


## A typed name made safe: trimmed, one line, at most NAME_MAX characters (pure).
static func clean_name(s: String) -> String:
	var t: String = s.replace("\n", " ").replace("\t", " ").strip_edges()
	return t.substr(0, NAME_MAX).strip_edges()


static func profile_file(n: int) -> String:
	return SaveManager.profile_dir(n).path_join(CradleMode.PROFILE_FILE)


## Reads profile n from disk (the live profile for the current one).
static func read_profile(n: int) -> Dictionary:
	if n == SaveManager.profile_slot and not CradleMode.profile.is_empty() and (FileAccess.file_exists(profile_file(n)) or not CradleMode.persist):
		return CradleMode.profile
	return SaveManager.read_dict(profile_file(n)) if FileAccess.file_exists(profile_file(n)) else {}


static func summary(n: int) -> Dictionary:
	if dev_summaries.has(n):
		return dev_summaries[n]
	var prof: Dictionary = read_profile(n)
	var slot: int = 0
	var ws: Array = prof.get("worlds", [])
	if not ws.is_empty():
		var cur: int = clampi(int(prof.get("current", 0)), 0, ws.size() - 1)
		slot = int((ws[cur] as Dictionary).get("slot", 0))
	var sp: String = SaveManager.profile_dir(n).path_join("slot_%d.save" % slot)
	var save: Dictionary = SaveManager.read_dict(sp) if FileAccess.file_exists(sp) else {}
	return summary_from(prof, save, n)


## Renames profile n (written to its profile.save; it syncs to the cloud like any save).
static func rename(n: int, new_name: String) -> bool:
	var nm: String = clean_name(new_name)
	if nm == "":
		return false
	if n == SaveManager.profile_slot:
		CradleMode.profile["name"] = nm
		if CradleMode.persist:
			return CradleMode.save_profile()
		return true
	var d: Dictionary = SaveManager.read_dict(profile_file(n)) if FileAccess.file_exists(profile_file(n)) else CradleMode.default_profile()
	d["name"] = nm
	d["saved_unix"] = Time.get_unix_time_from_system()
	DirAccess.make_dir_recursive_absolute(SaveManager.profile_dir(n))
	var ok: bool = SaveManager.write_dict(profile_file(n), d)
	if ok:
		SteamService.on_saved(profile_file(n))
	return ok


## "2:05 h" style play time (pure).
static func hours(s: float) -> String:
	var m: int = int(s / 60.0)
	@warning_ignore("integer_division")
	return TranslationServer.translate("%d:%02d h") % [m / 60, m % 60]
