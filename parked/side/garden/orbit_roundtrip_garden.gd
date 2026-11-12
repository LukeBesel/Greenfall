# Snippets cut from tools/orbit_roundtrip.gd in task M3-13 with Garden Mode: the helper
# _free_decor_cell, the Garden Mode checks at the start hub (after the Ledger relay checks), the
# hub-1 decor checks (after the fauna hop) and the decor rebuild check (after the outposts one).

## A free decor cell near Lumi (frame-local), or Vector2i(9999, 9999).
static func _free_decor_cell(dc: Decor, t: String, near: Vector3) -> Vector2i:
	var c0: Vector2i = Decor.cell_at(dc.to_local(near))
	for r: int in range(2, 14):
		for k: int in 16:
			var c: Vector2i = c0 + Vector2i(roundi(cos(TAU * k / 16.0) * r), roundi(sin(TAU * k / 16.0) * r))
			if dc.place_block_reason(t, c, 0) == "":
				return c
	return Vector2i(9999, 9999)


	# Garden Mode: this hub's decor sits in the frame on the ground; the yard's machines and its
	# buildings block a spot; the placer opens on it with the SphereCam following its cursor.
	var dc: Decor = hf.node("Decor") as Decor
	var lt: GardenDirector = GardenDirector.of(s)
	check.call("orbit_decor_at_hub", true, dc != null and lt != null and lt.decor == dc and lt.placer.decor == dc)
	var t0: String = Decor.type_ids()[0]
	var c0: Vector2i = _free_decor_cell(dc, t0, back)
	check.call("orbit_decor_placed", true, c0.x != 9999 and dc.place(t0, c0, 1, false, false))
	if not dc.nodes.is_empty():
		var dn: Node3D = dc.nodes[0]
		var dtilt: float = rad_to_deg(dn.global_basis.y.angle_to(dn.global_position.normalized()))
		check.call("orbit_decor_on_the_ground", true, absf(g.surface.altitude(dn.global_position)) < 0.4 and dtilt < 1.0)
	check.call("orbit_decor_state", 1, ((GameState.world.get("decor", {}) as Dictionary).get("items", []) as Array).size())
	var pod: Node3D = s.get_meta("orbit_pod") as Node3D if s.has_meta("orbit_pod") else null
	check.call("orbit_decor_sees_solid", true, pod != null and dc._solid_at(dc.to_local(pod.global_position)))
	check.call("orbit_decor_blocked_at_bench", true, dc.place_block_reason(t0, Decor.cell_at(dc.to_local(so.yard_point("bench"))), 0) != "")
	var hl0: int = int(GameState.world.get("hub_level", 1))
	GameState.world["hub_level"] = 5
	var sc: SphereCam = so.cam
	check.call("orbit_garden_mode_opens", true, lt.placer.open() and lt.placer.is_open and sc.target != null and sc.target.get_parent() == dc)
	lt.placer.close()
	check.call("orbit_garden_mode_closes", true, not lt.placer.is_open and sc.target == p)
	GameState.world["hub_level"] = hl0
	var dc1: Decor = hf.node("Decor") as Decor
	var t1: String = Decor.type_ids()[0]
	var c1: Vector2i = _free_decor_cell(dc1, t1, h1) if dc1 else Vector2i(9999, 9999)
	check.call("orbit_decor_hub1_own", true, dc1 != null and dc1 != dc and dc1.items.is_empty() and lt.decor == dc1 and dc1.place(t1, c1, 1, false, false))
	check.call("orbit_decor_hub1_state", 1, (((GameState.world.get("orbit_decor", {}) as Dictionary).get("1", {}) as Dictionary).get("items", []) as Array).size())
	check.call("orbit_decor_rebuilt", 1, (hf.node("Decor") as Decor).items.size())
