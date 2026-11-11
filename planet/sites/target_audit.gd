class_name TargetAudit
extends RefCounted
## [v4world] Dev: --target-reach. Owner playtest 3 #55: every collectible and objective target on
## the globe must be reachable. Builds each hub site in turn (as --site-reach does), stands the hub
## frame there so its outposts, eggs and Ledger relay are placed as in play, lets the hub's cells
## materialize round its pad (parts, wrecks), then tests every target with TargetReach (with the
## colliders loaded): memory shards (where each surfaces), CDs (where each would turn up, every
## 3rd hex), outposts, eggs and gnomes, the Ledger relay, the First Seed greenhouse, buried parts,
## the hub's build anchors (SiteReach.audit), and the purple beacon's point for raw hex centres
## (TargetReach.beacon_point, every 3rd hex). Prints a [targets] line per hub and kind, the
## failures, and "[targets] N unreachable" with PASS/FAIL; exits 1 on any failure.
## Run: godot --headless --path . -- --fresh --orbit --target-reach

const CD_EVERY: int = 3


static func run_dev(so: SliceOrbit) -> void:
	var tree: SceneTree = so.w.get_tree()
	await tree.create_timer(DevHooks.get_f("target-reach", 3.0)).timeout
	while so.hub_frame == null or bool(so.w.get("building")):  # [v6qa] a slow load (busy box) outlasted the 3 s timer: hub_frame was still null
		await tree.process_frame
	var sm: SiteManager = so.globe.site_manager
	var hf: HubFrame = so.hub_frame
	var patch: Node3D = so.w.get("patch")
	var t_all: int = Time.get_ticks_msec()
	var bad: Array[String] = []
	var total: int = 0
	var hubs: int = sm.sites.size() if not DevHooks.has("target-reach-hubs") else mini(sm.sites.size(), int(DevHooks.get_f("target-reach-hubs", 1.0)))
	for i: int in hubs:
		var p: SitePrefab = sm.build_hub(i, true)
		if not p.is_built:
			await p.rebuilt
		# Lumi on the hub's pad: the cells round it materialize (parts, wrecks), colliders load.
		var pad: Transform3D = sm.pad_xf(i)
		patch.global_position = so.globe.terrain.ground(pad.origin.normalized()) + pad.origin.normalized() * 0.3
		for k: int in 20:
			await tree.process_frame
		for k: int in 3:
			await tree.physics_frame
		if hf.hub != i:
			hf._set_hub(i)
			for k: int in 4:
				await tree.process_frame
		var counts: Dictionary = {}
		var fails: Array[String] = []
		var check := func(kind: String, at: Vector3, own: Node) -> void:
			var t: TargetReach = TargetReach.for_world(so.w, true, own)
			var r: String = t.reach(at)
			counts[kind] = int(counts.get(kind, 0)) + 1
			if r != "":
				fails.append("%s@%s(%s)" % [kind, _where(so, i, at), r])
		var outs: Node = hf.node("Outposts")
		if outs is Outposts:
			for o: Outpost in (outs as Outposts).items:
				check.call("outpost", o.anchor.global_position if o.get("anchor") is Node3D else o.global_position, o)
		var eggs: Node = hf.node("EasterEggs")
		if eggs is EasterEggs:
			for e: Dictionary in (eggs as EasterEggs).placed:
				var en: Node3D = e["node"]
				check.call("gnome" if str(e.get("kind", "")).contains("gnome") else "egg", en.global_position, en)
		var lg: Node = hf.node("Ledger")
		if lg is LedgerArc:
			var rs: Dictionary = LedgerArc.relay_spot_cells(hf, so.globe.field, hf.region(), i)
			check.call("relay", hf.to_global(rs["pos"]), (lg as LedgerArc).relay)
		var cells: PackedInt32Array = hf.region()
		var cdf: Node = so.w.get_node_or_null("CdFinds")
		if cdf == null:
			cdf = so.w.find_child("CdFinds", true, false)
		var f: SphereField = so.globe.field
		var n_cd: int = 0
		for c: int in cells:
			if f.hex_hub[c] != 0 or f.is_water(c):
				continue
			n_cd += 1
			if n_cd % CD_EVERY == 0 and cdf != null and cdf.has_method("spot"):
				check.call("cd", cdf.call("spot", c, false), null)
			if n_cd % CD_EVERY == 1:  # the beam on a raw hex centre (inside a building or not) stands on open ground
				check.call("beacon", TargetReach.beacon_point(so.w, f.hex_center(c)), null)
			if f.materialized[c] != 0:
				for pi: int in f.parts_in(c) if f.has_method("parts_in") else []:
					if f.part_found[pi] == 0:
						check.call("part", f.part_pos[pi], null)
		if i == 0:
			var sh: Variant = so.w.get("shards")
			if sh is ShardSystem:
				for hid: int in (sh as ShardSystem)._placed:
					check.call("shard", (sh as ShardSystem).spot(hid), null)
			var fs: Variant = so.w.get("first_seed")
			if fs is FirstSeed:
				check.call("first_seed", (fs as FirstSeed).greenhouse_point(), fs as Node)
		await SiteReach.fix_anchors(p, so.globe.terrain)
		var ra: Dictionary = await SiteReach.audit(p, so.globe.terrain)
		if not ra.is_empty():
			counts["anchor"] = (ra["anchors"] as Dictionary).size()
			for nm: String in ra["cut"]:
				fails.append("anchor %s" % nm)
		var n: int = 0
		var parts: PackedStringArray = []
		for k2: String in counts:
			n += int(counts[k2])
			parts.append("%s %d" % [k2, int(counts[k2])])
		total += n
		print("[targets] hub %d (%s): %d targets (%s), %d unreachable%s" % [i, p.site_id, n, ", ".join(parts), fails.size(),
			"" if fails.is_empty() else ": " + ", ".join(fails.slice(0, 14))])
		bad.append_array(fails)
		if i > 0:
			sm.free_hub(i)
			await tree.process_frame
	print("[targets] %d targets on %d hubs, %d unreachable (%d ms)" % [total, hubs, bad.size(), Time.get_ticks_msec() - t_all])
	print("[targets] %s" % ("PASS" if bad.is_empty() else "FAIL"))
	tree.quit(0 if bad.is_empty() else 1)


static func _where(so: SliceOrbit, i: int, at: Vector3) -> String:
	var lp: Vector3 = (so.globe.sites[i]["transform"] as Transform3D).affine_inverse() * at
	return "(%.0f,%.0f)" % [lp.x, lp.z]
