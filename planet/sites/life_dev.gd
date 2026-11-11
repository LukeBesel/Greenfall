class_name LifeDev
extends RefCounted
## [v6life] Dev hooks for the "life returns" layers (renders and tests of cleaned ground):
##   --life-clean=RINGS[,LEVEL[,X,Z]]  cleans every land cell within RINGS cells of Lumi (or of the
##       point X,Z metres from the start cell) the quiet way a robot would, and gives each the hex
##       level LEVEL (1 Clean .. 5 Thriving; default 1). Hub ground stays as it is.
##   --life-clean-at=S                 does it S seconds into play instead of at once (the grow-in).
##   --life-grown                      green jumps to its target instead of growing in.
##   --life-off                        none of the v6life layers (the "before" render).
##   --life-report                     prints a [life] line every few seconds.


static func attach(so: Node) -> void:
	if DevHooks.has("life-clean"):
		var at: float = DevHooks.get_f("life-clean-at", 0.0)
		if at > 0.0:
			so.get_tree().create_timer(at).timeout.connect(func() -> void: apply_clean(so))
		else:
			apply_clean(so)
	if DevHooks.has("life-report"):
		var t := Timer.new()
		t.wait_time = 5.0
		t.autostart = true
		so.add_child(t)
		t.timeout.connect(func() -> void: print("[life] ", report(so)))


static func apply_clean(so: Node) -> int:
	var spec: PackedStringArray = DevHooks.get_s("life-clean", "3").split(",")
	var rings: int = int(spec[0])
	var level: int = clampi(int(spec[1]), 1, 5) if spec.size() > 1 else 1
	var globe: OrbitPlanet = so.get("globe")
	var w: Node = so.get("w")
	var patch: Variant = w.get("patch")
	var centre: int = globe.cell_at((patch as Node3D).global_position) if patch is Node3D else globe.start_cell()
	if spec.size() > 3:
		centre = globe.grid.cell_at(globe.terrain.local_to_dir(globe.start_cell(), float(spec[2]), float(spec[3])))
	var n: int = clean_cells(so, globe.grid.cells_around(centre, rings), level)
	print("[life] cleaned %d cells to level %d" % [n, level])
	return n


## Cleans the given cells (quietly) and sets their hex level. Returns how many it touched.
static func clean_cells(so: Node, list: PackedInt32Array, level: int) -> int:
	var globe: OrbitPlanet = so.get("globe")
	var w: Node = so.get("w")
	var crews: OrbitCrews = so.get("crews")
	var hl: HexLevels = w.get("hex_levels") as HexLevels
	var n: int = 0
	for c: int in list:
		if globe.cells.state[c] == 5 or globe.cells.has_flag(c, SphereCells.F_HUB) or globe.field.hex_hub[c] != 0:
			continue
		if globe.cells.is_dirty(c):
			crews.work_cell(c, 0.0)
			so.call("on_hex_clean", c, true)
		if hl:
			hl.track(c)
			if hl.levels.has(c) and int(hl.levels[c]) < level:
				hl.levels[c] = level
				EventBus.hex_level_changed.emit(c, level)
		n += 1
	if hl:
		hl._recalc_bonus()
	return n


static func report(so: Node) -> String:
	var w: Node = so.get("w")
	var out: Array[String] = []
	var cv: Variant = w.get_node_or_null("CellVerdure")
	if cv is CellVerdure:
		out.append("verdure %s" % str((cv as CellVerdure).stats))
	return "  ".join(out)
