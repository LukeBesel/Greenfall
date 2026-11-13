class_name HexAudit
extends Node
## [v8hex] Dev QA: `--orbit --hex-audit[=FRAMES] [--hex-audit-r=M] [--hex-audit-hubs] [--hex-audit-all] [--hex-audit-quit]`.
## Owner item (Nov 13): "This starter hex i cleared but it says 94% and i dont get anything".
## For every junk hex whose centre lies within R m of the start pad (default: the start area,
## data/start_area.json "radius_m"), and with --hex-audit-hubs every other hub pad's too, it
## lays the hex's pieces, then pretends Lumi takes every piece the starter tools can take
## (HexLeftovers.why: Lift Strength 0, reachable dry ground, not under or inside a collider).
## A land hex is STUCK when what is left then is over the clear threshold's 5% (it would lean on
## the leftover rule, SphereField.leftover_from, or never clear). Lake hexes are listed (they wait
## for Hover Jets) but don't fail. It also lists big things in the start area
## (StartArea.big_things: pieces over Lift 0, wreck landmarks, junk-looking props).
## Lines:
##   [hexaudit] hubH hex C at (x, z) d=Dm: pieces N, takeable T, now P%, left after X% (needs <= 5%) [STUCK|LAKE] <why %>
##   [hexaudit] big <what> at (x, z) d=Dm
##   [hexaudit] RESULT hexes=H stuck=S big=B lakes=L
## Exit 1 (with --hex-audit-quit) when S or B is above 0. Positions are hub-site local metres.
## --hex-audit-raw: without the start area's collider tidy (StartJunkTidy), the root cause alone.
## Colliders are loaded round Lumi only, so the under/inside tests run on hub 0 (where he starts).

var so: Node  # SliceOrbit


static func attach(p_so: Node) -> HexAudit:
	var a := HexAudit.new()
	a.name = "HexAudit"
	a.so = p_so
	p_so.add_child(a)
	return a


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for i: int in int(DevHooks.get_f("hex-audit", 240.0)):
		await get_tree().process_frame
	for i: int in 1500:  # the start area's tidy and the one-time heal (StartJunkTidy) first
		var t: StartJunkTidy = so.get_node_or_null("StartJunkTidy") as StartJunkTidy
		if t and t.done():
			break
		await get_tree().process_frame
	await get_tree().physics_frame
	if DevHooks.has("hex-audit-stick"):
		_stick()
		return
	var res: Array = report()
	for l: String in res[0]:
		print(l)
	if DevHooks.has("hex-audit-quit"):
		get_tree().quit(1 if int(res[1]) > 0 else 0)


## [lines, failures]
func report() -> Array:
	var g: OrbitPlanet = so.get("globe")
	var w: Node = so.get("w")
	var f: SphereField = g.field
	var lines: PackedStringArray = []
	var hl: HexLeftovers = HexLeftovers.for_world(w)
	hl.lumi = null  # judge every start-area piece, wherever Lumi stands
	var r_m: float = DevHooks.get_f("hex-audit-r", StartArea.radius_m())
	var hubs: Array[int] = [0]
	if DevHooks.has("hex-audit-hubs"):
		for i: int in range(1, g.sites.size()):
			hubs.append(i)
	var n_hex: int = 0
	var stuck: int = 0
	var lakes: int = 0
	for hi: int in hubs:
		var site: Dictionary = g.sites[hi]
		var inv: Transform3D = (site["transform"] as Transform3D).affine_inverse()
		var c0: int = int(site["cell"])
		for c: int in g.grid.cells_within(g.grid.centers[c0], r_m, c0):
			if f.hex_hub[c] == 1 or f.hex_clean[c] == 1:
				continue
			f.materialize(c)
			var mv: Array = f.relocate_blocked(c)  # as the late keep-out sweep would
			if g.junk_view:
				for pid: int in mv[1]:
					g.junk_view.hide_piece(pid)
			var tidy: StartJunkTidy = so.get_node_or_null("StartJunkTidy") as StartJunkTidy
			if tidy and hi == 0 and not DevHooks.has("hex-audit-raw"):  # as the start area's tidy does once a cell is laid
				tidy.tidy_cell(c)
			var lake: bool = f.hex_water[c] == 1
			n_hex += 1
			var r: Dictionary = audit_hex(hl, c, hi == 0, inv)
			var lp: Vector3 = inv * g.terrain.ground(g.grid.centers[c])
			var ok: bool = float(r["after"]) <= 1.0 - f.clean_threshold + 0.0005
			if lake:
				lakes += 1
			elif not ok:
				stuck += 1
			if (not ok and not lake) or DevHooks.has("hex-audit-all"):
				var why: PackedStringArray = []
				for k: String in r["why"]:
					why.append("%s %.1f%%" % [k, 100.0 * float(r["why"][k]) / maxf(f.hex_total[c], 0.001)])
				var tag: String = " LAKE" if lake else ("" if ok else " STUCK")
				if not ok and not lake and 1.0 - float(r["after"]) >= f.leftover_from:
					tag += " (the leftover rule would sweep it)"
				lines.append("[hexaudit] hub%d hex %d at (%.0f, %.0f) d=%.0fm: pieces %d, takeable %d, now %.1f%%, left after %.1f%% (needs <= %.0f%%)%s %s" % [
					hi, c, lp.x, lp.z, Vector2(lp.x, lp.z).length(), r["pieces"], r["take"], 100.0 * f.removed_fraction(c), 100.0 * float(r["after"]),
					100.0 * (1.0 - f.clean_threshold), tag, " ".join(why)])
				for s: String in r["samples"]:
					lines.append("[hexaudit]     " + s)
	var big: PackedStringArray = StartArea.big_things(g, w)
	for s: String in big:
		lines.append("[hexaudit] big " + s)
	lines.append("[hexaudit] RESULT hexes=%d stuck=%d big=%d lakes=%d (r=%.0fm, hubs=%d)" % [n_hex, stuck, big.size(), lakes, r_m, hubs.size()])
	return [lines, stuck + big.size()]


## What Lumi with the starter tools can take of hex c, and what would be left (a fraction of its total).
func audit_hex(hl: HexLeftovers, c: int, phys: bool, inv: Transform3D) -> Dictionary:
	var f: SphereField = hl.field
	var why: Dictionary = {}
	var take: int = 0
	var n: int = 0
	var alive_vol: float = 0.0
	var left_vol: float = 0.0
	var samples: PackedStringArray = []
	var seen: Dictionary = {}
	for pid: int in f.pieces_in(c):
		if f.piece_alive[pid] == 0:
			continue
		n += 1
		alive_vol += f.piece_vol[pid]
		hl.last_hit = ""
		var k: String = hl.why(pid, true, phys)
		if k == "":
			take += 1
			continue
		why[k] = float(why.get(k, 0.0)) + f.piece_vol[pid]
		left_vol += f.piece_vol[pid]
		if samples.size() < 4 or (hl.last_hit != "" and not seen.has(hl.last_hit) and samples.size() < 10):
			seen[hl.last_hit] = true
			var lp: Vector3 = inv * f.piece_pos[pid]
			samples.append("%s: %s (vol %.2f) at (%.1f, %.1f) %s" % [k, f.piece_model[pid], f.piece_vol[pid], lp.x, lp.z, hl.last_hit])
	var ghost: float = f.hex_left[c] - alive_vol
	if ghost > 0.01:  # ledger volume with no piece behind it
		why["ghost"] = ghost
		left_vol += ghost
	return {"pieces": n, "take": take, "why": why, "samples": samples, "after": left_vol / maxf(f.hex_total[c], 0.001)}


## Dev (--hex-audit-stick, with --save-dir=NAME): makes a save like the owner's (Nov 13): a start-area
## land hex scooped to 94% and left there, saved without the one-time heal flag, then quits. Load it
## (same --save-dir, no --fresh): StartJunkTidy.heal prints "[hexheal] 1 ..." and the hex is clean.
func _stick() -> void:
	var g: OrbitPlanet = so.get("globe")
	var f: SphereField = g.field
	var c0: int = g.start_cell()
	for c: int in g.grid.cells_within(g.grid.centers[c0], StartArea.radius_m(), c0):
		if f.hex_hub[c] == 1 or f.hex_clean[c] == 1 or f.hex_water[c] == 1:
			continue
		f.materialize(c)
		for pid: int in f.pieces_in(c):
			if f.piece_alive[pid] == 1 and f.removed_fraction(c) + f.piece_vol[pid] / f.hex_total[c] < 0.945:
				so.call("collect_piece", pid)
		print("[hexaudit] stick: hex %d left at %.1f%% clear (clean=%d)" % [c, 100.0 * f.removed_fraction(c), f.hex_clean[c]])
		GameState.flags.erase("v8hex_heal")
		print("[hexaudit] stick: saved=%s" % str(SaveManager.save_game()))
		get_tree().quit(0)
		return
