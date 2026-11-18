class_name CosmeticTargets
extends RefCounted
## [style] Registry of things the Locker can dress up ("cosmetic targets"): Lumi (built in), and
## whatever else registers itself (the buddy light-bot, robots). The Locker's bot selector lists
## `all()` and hosts `make_editor(id, world)` in its body.
##
##   CosmeticTargets.register("buddy", {
##       "name": "Buddy",                       # English; tr() at display
##       "order": 20,                           # selector order (Lumi is 0)
##       "editor": func(world: Node) -> Control: return BuddyBuilder.new(),   # required
##       "unlocked": func() -> bool: return GameState.flags.get("buddy_met", false),  # optional
##       "hint": "Meet the light-bot in the Old Town",   # optional, shown while locked
##   })
##
## Unlock rules for parts can reuse LumiStyle's helpers with your own data:
## LumiStyle.unlock_met(u, key), unlock_progress(u, key), unlock_text(u), buy(...) work on the same
## unlock dicts as data/style_parts.json ({design}, {lumi_level}, {achievement}, {cond}, {cost}).
## Locked things are shown as "???" with only the hint (LumiStyle.LOCKED_NAME), never their look.

static var _targets: Dictionary = {}


static func _ensure_builtin() -> void:
	if _targets.has("lumi"):
		return
	_targets["lumi"] = {
		"id": "lumi",
		"name": "Lumi",
		"order": 0,
		"editor": func(world: Node) -> Control:
			var b := LumiBuilder.new()
			b.world = world
			return b,
		"unlocked": func() -> bool: return true,
		"hint": "",
	}


## Add or replace a target. Returns false when the definition has no editor.
static func register(id: String, def: Dictionary) -> bool:
	_ensure_builtin()
	if not (def.get("editor") is Callable):
		push_warning("CosmeticTargets.register(%s): needs an 'editor' Callable" % id)
		return false
	var d: Dictionary = def.duplicate()
	d["id"] = id
	_targets[id] = d
	return true


static func unregister(id: String) -> void:
	if id != "lumi":
		_targets.erase(id)


static func has(id: String) -> bool:
	_ensure_builtin()
	return _targets.has(id)


## All targets, in selector order.
static func all() -> Array[Dictionary]:
	_ensure_builtin()
	var out: Array[Dictionary] = []
	for k: String in _targets:
		out.append(_targets[k])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 50)) < int(b.get("order", 50)))
	return out


static func is_unlocked(id: String) -> bool:
	_ensure_builtin()
	var u: Variant = (_targets.get(id, {}) as Dictionary).get("unlocked")
	return bool((u as Callable).call()) if u is Callable else _targets.has(id)


## Display name, translated ("???" while locked).
static func display_name(id: String) -> String:
	_ensure_builtin()
	if not is_unlocked(id):
		return TranslationServer.translate(LumiStyle.LOCKED_NAME)
	return TranslationServer.translate(str((_targets.get(id, {}) as Dictionary).get("name", id)))


static func hint(id: String) -> String:
	_ensure_builtin()
	return TranslationServer.translate(str((_targets.get(id, {}) as Dictionary).get("hint", "")))


## A fresh editor Control for the target (null when unknown or locked).
static func make_editor(id: String, world: Node) -> Control:
	_ensure_builtin()
	if not _targets.has(id) or not is_unlocked(id):
		return null
	return ((_targets[id] as Dictionary)["editor"] as Callable).call(world)
