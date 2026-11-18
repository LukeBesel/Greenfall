class_name BaseKeepers
extends Node
## [v6pace] A woken base keeps cleaning its own region while Lumi is somewhere else (owner: "a woken
## station keeps cleaning"; story_reasons hub_wake_). Each woken far hub clears whole cells of its
## region, nearest its centre first, at
##     cells/min = keep.cells_per_min + keep.per_level x (level - 1) + keep.per_robot x robots there
## (data/hub.json far_hub.keep; a planet overrides it in data/homeward.json planets[k].far_hub).
## Only while Lumi's nearest hub is another one, so nothing pops away in front of her; on the next
## visit HubPurpose says "N% clean, up M% while you were away". A cell cleared here counts and pays
## like any other (SliceOrbit.on_hex_clean, quiet). keep.home: the start hub too (off on Verdance:
## its crews are the player's). Nothing is saved: the cells' own state is.
## Dev: --keep-report prints a [keep] line a game minute (cells cleared, planet %, each built hub's region %).

const TICK_S: float = 2.0

var sites: OrbitSites
var _acc: Dictionary = {}     # hub -> cells owed (fraction carried over)
var _cursor: Dictionary = {}  # hub -> index into its region where the last cleared cell was
var _t: float = 0.0
## Cells cleared by the keepers this session (dev reports).
var cleared: int = 0
var _rep_t: float = 0.0


static func attach(p_sites: OrbitSites) -> BaseKeepers:
	var k := BaseKeepers.new()
	k.name = "BaseKeepers"
	k.sites = p_sites
	p_sites.add_child(k)
	return k


static func cfg() -> Dictionary:
	var v: Variant = Hub.far_cfg().get("keep", {})
	return v as Dictionary if v is Dictionary else {}


## Cells a minute hub i's keepers clear (0 while it isn't woken).
static func rate(level: int, robots: int, c: Dictionary = {}) -> float:
	if c.is_empty():
		c = cfg()
	return maxf(0.0, float(c.get("cells_per_min", 0.0)) + float(c.get("per_level", 0.0)) * float(maxi(level - 1, 0))
		+ float(c.get("per_robot", 0.0)) * float(robots))


func _process(delta: float) -> void:
	_t += delta
	if _t < TICK_S:
		return
	var dt: float = _t
	_t = 0.0
	var sm: SiteManager = sites.sm if sites else null
	if sm == null or sm.cells == null or sites.so == null:
		return
	var c: Dictionary = cfg()
	if c.is_empty():
		return
	var home_too: bool = bool(c.get("home", false))
	for i: int in sm.sites.size():
		if sm.built[i] == 0 or i == sm.nearest or (i == 0 and not home_too) or i >= sm.regions.size():
			continue
		var robots: int = int(sites.purpose.crew_summary(i).get("robots", 0)) if sites.purpose else 0
		var owed: float = float(_acc.get(i, 0.0)) + rate(sm.levels[i] if i < sm.levels.size() else 1, robots, c) * dt / 60.0
		var n: int = int(owed)
		_acc[i] = owed - float(n)
		if n > 0:
			_clear(i, n)
	if DevHooks.has("keep-report"):  # dev: a [keep] line a game minute
		_rep_t += dt
		if _rep_t >= 60.0:
			_rep_t = 0.0
			var parts: Array[String] = []
			for j: int in sm.sites.size():
				if sm.built[j] != 0:
					parts.append("hub %d %.1f%%" % [j, sm.region_clean(j) * 100.0])
			print("[keep] %.1f min  cleared %d  planet %.2f%%  %s" % [float(GameState.stats.get("time_played", 0.0)) / 60.0, cleared, sm.planet_fraction() * 100.0, "  ".join(parts)])


## Clears up to n dirty cells of hub i's region, centre first. Returns how many.
func _clear(i: int, n: int) -> int:
	var sm: SiteManager = sites.sm
	var so: SliceOrbit = sites.so
	var crews: Variant = so.get("crews")
	var field: Variant = so.globe.field if so.globe else null
	if crews == null or field == null:
		return 0
	var reg: PackedInt32Array = sm.regions[i]
	var k: int = int(_cursor.get(i, 0))
	var done: int = 0
	var looked: int = 0
	while done < n and looked < reg.size():
		if k >= reg.size():
			k = 0
		var cell: int = reg[k]
		looked += 1
		k += 1
		if sm.cells.state[cell] == 5 or sm.cells.has_flag(cell, SphereCells.F_HUB) or (field as SphereField).hex_hub[cell] != 0:
			continue
		if not sm.cells.is_dirty(cell):
			continue
		(crews as Object).call("work_cell", cell, 0.0)
		so.on_hex_clean(cell, true)
		done += 1
	_cursor[i] = k
	cleared += done
	return done
