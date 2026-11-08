class_name OrbitMigrate
extends RefCounted
## [orbB] Old (flat) saves onto the walkable globe. A flat save keeps its whole-planet survey in
## GameState.planet_state: PlanetData at level 6 (40,962 cells), where every district hex wrote
## its junk left to its planet cell (slice.gd slice_cells / collect_piece). The globe is level 7
## (Verdance, f = 128) and the grid is hierarchical: a level-6 id is the same level-7 id, and
## every other level-7 cell is the midpoint of a level-6 edge, so its parent is the nearer of its
## two level-6 neighbours. Each changed level-6 cell's junk fraction is spread over the level-7
## cells it covers; base levels move to the nearest globe hub; Lumi starts on the start site with
## the cargo he had.
## Only planets whose globe is level 7 can take a level-6 survey (the other sizes start fresh).

const FROM_LEVEL: int = 6
const HUB_MATCH_M: float = 450.0  # an old base this close to a globe hub keeps its level there


## True when GameState holds a flat game this globe can take (and no globe save yet).
static func can_migrate(globe_freq: int) -> bool:
	var ps: Dictionary = GameState.planet_state
	return GameState.orbit.is_empty() and not ps.is_empty() and int(ps.get("level", -1)) == FROM_LEVEL \
		and globe_freq == (1 << (FROM_LEVEL + 1))


## Level-6 parent of every level-7 cell (exact, from the hierarchy).
static func parents(grid: SphereGrid) -> PackedInt32Array:
	var n6: int = SphereGrid.cells_at_level(FROM_LEVEL)
	var n: int = grid.cell_count()
	var out := PackedInt32Array()
	out.resize(n)
	for i: int in n:
		if i < n6:
			out[i] = i
			continue
		var best: int = -1
		var best_d: float = -2.0
		for k: int in grid.nbr_count[i]:
			var j: int = grid.nbr[i * SphereGrid.MAX_N + k]
			if j < n6:
				var d: float = grid.centers[i].dot(grid.centers[j])
				if d > best_d:
					best_d = d
					best = j
		out[i] = best if best >= 0 else grid.walk(grid.centers[i], 0)
	return out


## Applies the flat survey to the globe's cells (call after the sites are reserved, before the
## field is made). Returns a report {cells, changed6, hubs, ...} for the log and tests.
static func apply(globe: OrbitPlanet) -> Dictionary:
	var ps: Dictionary = GameState.planet_state
	var seed6: int = int(ps.get("seed", globe.seed_value))
	var base := PlanetData.new(seed6, FROM_LEVEL, 10.0)  # what the flat survey started from
	base.mix = CradleMode.planet_mix()
	base.generate()
	var was := PlanetData.new(seed6, FROM_LEVEL, 10.0)
	was.mix = base.mix
	was.generate()
	var ok: bool = was.apply_dict(ps)
	var report: Dictionary = {"ok": ok, "changed6": 0, "cells": 0, "cleaned": 0, "hubs": {}}
	if not ok:
		return report
	# Fraction of junk left per level-6 cell (1 = untouched), and what it became.
	var left6 := PackedFloat32Array()
	left6.resize(was.cell_count())
	left6.fill(1.0)
	var clean6 := PackedByteArray()
	clean6.resize(was.cell_count())
	for c: int in was.cell_count():
		if was.state[c] == PlanetData.State.WATER:
			continue
		var b: float = base.junk[c]
		if was.state[c] != base.state[c] and was.state[c] != PlanetData.State.JUNK:
			clean6[c] = was.state[c]
			left6[c] = 0.0
			report["changed6"] = int(report["changed6"]) + 1
		elif was.junk[c] < b - 0.001:
			left6[c] = clampf(was.junk[c] / maxf(b, 0.001), 0.0, 1.0)
			report["changed6"] = int(report["changed6"]) + 1
	var cells: SphereCells = globe.cells
	var par: PackedInt32Array = parents(globe.grid)
	for i: int in cells.n:
		var p: int = par[i]
		if left6[p] >= 1.0 or cells.state[i] == PlanetData.State.WATER:
			continue
		report["cells"] = int(report["cells"]) + 1
		if clean6[p] != 0:
			cells.junk[i] = 0.0
			cells.state[i] = clean6[p]
			report["cleaned"] = int(report["cleaned"]) + 1
		else:
			cells.junk[i] = cells.junk[i] * left6[p]
			if cells.junk[i] <= 0.02 and cells.state[i] == 0:
				cells.state[i] = 1
				report["cleaned"] = int(report["cleaned"]) + 1
	cells.refresh_all()
	report["hubs"] = hub_levels(globe, base)
	return report


## Old bases (GameState.districts by hub index) -> {globe site index: {level}} for the bases that
## sit near a globe hub (the start district always maps to the start site).
static func hub_levels(globe: OrbitPlanet, base: PlanetData) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in GameState.districts:
		var hi: int = int(str(k))
		var d: Dictionary = GameState.districts[k]
		var lvl: int = int(d.get("hub_level", 1))
		if hi < 0 or hi >= base.hubs.size():
			continue
		var dir: Vector3 = base.grid.centers[base.hubs[hi]]
		var best: int = 0 if hi == 0 else -1
		var best_m: float = HUB_MATCH_M
		if hi != 0:
			for s: Dictionary in globe.sites:
				var m: float = globe.grid.great_circle_m(dir, globe.grid.centers[int(s["cell"])])
				if m < best_m:
					best_m = m
					best = int(s["index"])
		if best < 0:
			continue
		var key: String = str(best)
		var cur: int = int((out.get(key, {"level": 1}) as Dictionary)["level"])
		out[key] = {"level": maxi(cur, lvl)}
	return out


## Lumi's cargo from the flat district he was in ({compartment, carried}); his position is not
## kept (he starts on the start site).
static func lumi_cargo() -> Dictionary:
	var pd: Dictionary = GameState.world.get("patch", {})
	return {"compartment": pd.get("compartment", {}), "carried": pd.get("carried", [])}
