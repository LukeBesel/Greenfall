class_name Designs
extends RefCounted
## Lumi's unlockable designs (data/designs.json): Aurora (default), Bolt, Sprout, Pixel, Nova,
## Patch. The looks live in PatchModel.VARIANTS; this owns the gameplay side: unlock conditions
## (checked about once a second by the Achievements node), the small themed buff of the worn
## design, the "looks only" switch and the worn/unlocked state.
## State: flags.patch_skin (worn id), flags.skins_unlocked (Array of ids, "aurora" always),
## flags.designs_looks_only (bool: no bonuses). All in the save via GameState.flags.

const PATH: String = "res://data/designs.json"
const DEFAULT: String = "aurora"

static var _defs: Array = []
static var _by_id: Dictionary = {}
## Unlocks waiting for their card toast (ui/design_toast.gd shows one at a time).
static var pending_toasts: Array[String] = []


static func defs() -> Array:
	if _defs.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_defs = (d as Dictionary).get("designs", [])
		for e: Dictionary in _defs:
			_by_id[str(e["id"])] = e
	return _defs


static func def(id: String) -> Dictionary:
	defs()
	return _by_id.get(id, {})


static func ids() -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in defs():
		out.append(str(e["id"]))
	return out


# --- State ------------------------------------------------------------------------------------

## The worn design (falls back to Aurora for unknown ids).
static func current() -> String:
	var id: String = str(GameState.flags.get("patch_skin", DEFAULT))
	return id if not def(id).is_empty() else DEFAULT


static func unlocked() -> Array:
	var have: Variant = GameState.flags.get("skins_unlocked", [])
	var arr: Array = have if have is Array else []
	if not (DEFAULT in arr):
		arr.push_front(DEFAULT)
	GameState.flags["skins_unlocked"] = arr
	return arr


static func is_unlocked(id: String) -> bool:
	return id == DEFAULT or id in unlocked()


## Wear a design. Returns false for a locked or unknown one.
static func select(id: String) -> bool:
	if def(id).is_empty() or not is_unlocked(id):
		return false
	GameState.flags["patch_skin"] = id
	return true


static func looks_only() -> bool:
	return bool(GameState.flags.get("designs_looks_only", false))


static func set_looks_only(on: bool) -> void:
	GameState.flags["designs_looks_only"] = on


# --- Unlocks ----------------------------------------------------------------------------------

## Current value of one unlock condition (achievement condition types + fleet_tier).
static func cond_value(c: Dictionary) -> float:
	if str(c.get("type", "")) == "fleet_tier":
		var best: int = 0
		for rid: String in Economy.robot_order:
			best = maxi(best, int(GameState.flags.get("tier_" + rid, 0)))
		return float(best)
	return Achievements.value_of(c)


static func conds(id: String) -> Array:
	return (def(id).get("unlock", {}) as Dictionary).get("any", [])


static func met(id: String) -> bool:
	if id == DEFAULT:
		return true
	for c: Dictionary in conds(id):
		if cond_value(c) >= float(c.get("target", 1.0)) - 0.000001:
			return true
	return false


## 0..1: the condition closest to done.
static func progress(id: String) -> float:
	if is_unlocked(id):
		return 1.0
	var best: float = 0.0
	for c: Dictionary in conds(id):
		best = maxf(best, clampf(cond_value(c) / maxf(float(c.get("target", 1.0)), 0.0001), 0.0, 1.0))
	return best


## "How to unlock" line, translated.
static func unlock_text(id: String) -> String:
	if id == DEFAULT:
		return TranslationServer.translate("Default")
	return TranslationServer.translate(str((def(id).get("unlock", {}) as Dictionary).get("text", "")))


## Progress of the closest condition, e.g. "12 / 50 bales" ("" when unlocked).
static func progress_text(id: String) -> String:
	if is_unlocked(id):
		return ""
	var best_c: Dictionary = {}
	var best: float = -1.0
	for c: Dictionary in conds(id):
		var p: float = cond_value(c) / maxf(float(c.get("target", 1.0)), 0.0001)
		if p > best:
			best = p
			best_c = c
	if best_c.is_empty():
		return ""
	var unit: String = str(best_c.get("unit", ""))
	if unit == "Mk":
		return TranslationServer.translate("Best fleet: %s") % Economy.tier_name(int(cond_value(best_c)))
	return "%d / %d %s" % [int(cond_value(best_c)), int(best_c.get("target", 1)), TranslationServer.translate(unit)]


## Unlock every design whose condition is met. Returns the new ids; each gets a toast unless
## `quiet` (first check after loading an old save).
static func check_unlocks(quiet: bool = false) -> Array[String]:
	var out: Array[String] = []
	_dev_tick()
	var have: Array = unlocked()
	for id: String in ids():
		if id in have or not met(id):
			continue
		have.append(id)
		out.append(id)
		if not quiet:
			pending_toasts.append(id)
			EventBus.toast.emit(TranslationServer.translate("New look unlocked: %s. Try it on at the Locker.") % TranslationServer.translate(str(def(id).get("name", id))), "reward")  # [v4calm] cut
	if not out.is_empty() and not quiet:
		DesignToast.show_next()
	return out


# --- Buffs ------------------------------------------------------------------------------------

static func buff(id: String) -> Dictionary:
	return def(id).get("buff", {})


static func buff_text(id: String) -> String:
	return TranslationServer.translate(str(buff(id).get("text", "")))


## Multiplier the worn design adds to a stat (1.0 when it doesn't touch it or looks only is on).
static func mult(stat_id: String) -> float:
	if looks_only():
		return 1.0
	var b: Dictionary = buff(current())
	var s: String = str(b.get("stat", ""))
	if s == "":
		return 1.0
	if s == stat_id or (s.begins_with("*.") and stat_id.ends_with(s.substr(1))):
		return 1.0 + float(b.get("amount", 0.0))
	return 1.0


static func apply(stat_id: String, value: float) -> float:
	var m: float = mult(stat_id)
	return value * m if m != 1.0 else value


## Breakdown row for the stat tooltip ([] when the worn design doesn't touch the stat).
static func breakdown(stat_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m: float = mult(stat_id)
	if m != 1.0:
		out.append({"source": TranslationServer.translate("Design: %s") % TranslationServer.translate(str(def(current()).get("name", ""))), "text": "x%.2f" % m})
	return out


# --- Dev hooks (screenshots) --------------------------------------------------------------------
##   --design=ID          unlock and wear a design at start
##   --designs-all        unlock every design
##   --design-unlock=ID   play the unlock (toast card) for ID after --design-unlock-at=S seconds (default 4)
static func dev_hooks(world: Node) -> void:
	if DevHooks.has("designs-all"):
		for id: String in ids():
			if not (id in unlocked()):
				unlocked().append(id)
	var want: String = DevHooks.get_s("design", "")
	if want != "" and not def(want).is_empty():
		if not (want in unlocked()):
			unlocked().append(want)
		select(want)
		if world and world.get("patch") and world.patch.get("model"):
			(world.patch.model as PatchModel).set_variant(want)
	var show: String = DevHooks.get_s("design-unlock", "")
	if show != "" and not def(show).is_empty():
		unlocked().erase(show)
		_dev_show = show
		_dev_at_ms = Time.get_ticks_msec() + int(DevHooks.get_f("design-unlock-at", 4.0) * 1000.0)
		if DevHooks.get_f("design-unlock-at", 4.0) <= 0.0:
			_dev_tick()


static var _dev_show: String = ""
static var _dev_at_ms: int = 0


## --design-unlock: play the unlock once its (wall-clock) time has come. Called by check_unlocks.
static func _dev_tick() -> void:
	if _dev_show == "" or Time.get_ticks_msec() < _dev_at_ms:
		return
	if not (_dev_show in unlocked()):
		unlocked().append(_dev_show)
	pending_toasts.append(_dev_show)
	_dev_show = ""
	DesignToast.show_next()
