class_name FieldBenches
extends RefCounted
## The field benches' rules and state, plain data (decision after the full-planet bot: away from the
## start yard nothing could be bought or researched). Every city Lumi has reached, other than the
## one on the start site, offers a field bench at its base: a packed kit on the site's bench anchor
## that Lumi sets up (for the data's cost, free when it is empty). A bench that is set up gives the
## whole workbench there: upgrades, rigs, research, robot building and the Assembler's mix. The
## start yard keeps the Locker, the yard builds and the Assembler building itself.
## The node that shows the benches and takes the E press is FieldBenchSites (field_bench_sites.gd).
##
## Data: the planet's "yard" table (planets/<id>/data/camp.json), key "field_bench": cost, reach_m,
## looks (per district id) and default. A planet without it offers free benches with the default look.
## Save: save_state() / load_state() (the planet's save section, key SAVE_KEY). A save from before
## field benches (no key) gets a bench set up in every city it had already reached.
## Events: EventBus.field_bench_set_up(district_id).

const SAVE_KEY: String = "field_benches"
const CFG_KEY: String = "field_bench"
## The start site: its own workbench stands there (scenes/slice_orbit.gd), never a field bench.
const START_SITE: int = 0
## How close Lumi stands to use a field bench when the data does not say (the start bench's reach).
const REACH_FALLBACK_M: float = 3.2

var districts: Districts
var _set_up: Dictionary[String, bool] = {}


static func cfg() -> Dictionary:
	return YardBuilds.cfg().get(CFG_KEY, {})


## What setting up a bench costs ({} = free).
static func cost() -> Dictionary:
	return cfg().get("cost", {})


static func reach_m() -> float:
	return float(cfg().get("reach_m", REACH_FALLBACK_M))


## The bench's colours in city `id`: {frame, panel, canopy, trim} as Colors.
static func look_of(id: String) -> Dictionary[String, Color]:
	var all: Dictionary = cfg().get("looks", {})
	var src: Dictionary = all.get(id, cfg().get("default", {}))
	var out: Dictionary[String, Color] = {}
	for k: String in ["frame", "panel", "canopy", "trim"]:
		var a: Array = src.get(k, [0.8, 0.8, 0.8])
		out[k] = Color(float(a[0]), float(a[1]), float(a[2]))
	return out


func setup(p_districts: Districts) -> void:
	districts = p_districts


## Whether city `id` can have a field bench at all: a city of this planet off the start site.
func has_site(id: String) -> bool:
	return districts != null and districts.has(id) and districts.site_of(id) >= 0 and districts.site_of(id) != START_SITE


## Whether a kit waits in city `id`: Lumi has reached it and its bench is not set up yet.
func offered(id: String) -> bool:
	return has_site(id) and districts.is_visited(id) and not is_set_up(id)


func is_set_up(id: String) -> bool:
	return _set_up.get(id, false)


## "" when Lumi can set up the bench in `id` now, else why not.
func block_reason(id: String) -> String:
	if is_set_up(id):
		return TranslationServer.translate("The field bench is set up.")
	if not offered(id):
		return TranslationServer.translate("Reach this city first.")
	if not GameState.can_afford_all(cost()):
		return TranslationServer.translate("Not enough materials.")
	return ""


## Pays and sets up the bench in `id`. False (nothing paid) when block_reason says no.
func set_up(id: String) -> bool:
	if block_reason(id) != "":
		return false
	if not cost().is_empty() and not GameState.spend_all(cost()):
		return false
	_set_up[id] = true
	GameState.inc_stat("field_benches_set_up")
	EventBus.field_bench_set_up.emit(id)
	return true


## The cities whose bench is set up, in play order.
func set_up_ids() -> Array[String]:
	var out: Array[String] = []
	if districts == null:
		return out
	for id: String in districts.ids():
		if is_set_up(id):
			out.append(id)
	return out


## Site indices that show a bench or a kit now: [{site, id, ready}] (ready = set up).
func shown() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if districts == null:
		return out
	for id: String in districts.ids():
		if is_set_up(id) or offered(id):
			out.append({"site": districts.site_of(id), "id": id, "ready": is_set_up(id)})
	return out


func save_state() -> Dictionary:
	return {"set_up": set_up_ids()}


## Restores from the planet's save section. `has_key` false: a save from before field benches, where
## every city already reached gets its bench (the player never saw a kit there to set up).
## Call after the districts have loaded (visited cities come from them).
func load_state(d: Dictionary, has_key: bool) -> void:
	_set_up.clear()
	if not has_key:
		if districts != null:
			for id: String in districts.ids():
				if has_site(id) and districts.is_visited(id):
					_set_up[id] = true
		return
	for v: Variant in d.get("set_up", []):
		if has_site(str(v)):
			_set_up[str(v)] = true
