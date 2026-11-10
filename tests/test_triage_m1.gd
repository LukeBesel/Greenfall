extends GutTest
## M1-01 bug triage (docs/reviews/TRIAGE_M1.md). B4: the story objectives finish in order whatever
## order the player does them in. The checks that need the whole world are tools, not tests:
## tools/exit_probe.tscn (B2) and tools/hex_stick_probe.tscn (B3).

class StubFleet extends Node:
	var counts: Dictionary = {}

	func robot_total() -> int:
		var n: int = 0
		for k: String in counts:
			n += int(counts[k])
		return n

	func count(type_id: String) -> int:
		return int(counts.get(type_id, 0))


class StubWorld extends Node:
	var fleet: StubFleet
	var goals: Goals
	var hud: Node
	var patch: Patch
	var field: HexField
	var intro: Node
	var wren: Node


class HeldInput extends InputSource:
	func scoop_held() -> bool:
		return true


## The junk view's part in the magnet pull: records which pieces were moved.
class MoveView extends RefCounted:
	var field: SphereField
	var moved: Dictionary = {}

	func move_piece(pid: int, pos: Vector3) -> void:
		moved[pid] = true
		field.piece_pos[pid] = pos


class ScoopWorld extends Node:
	var field: SphereField
	var view: MoveView
	var litter: Node


var _saved: Dictionary


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	GameState.flags["onboard_brief"] = true  # past WREN's brief: the card shows
	GameState.flags["objectives_v2"] = true


func after_each() -> void:
	GameState.from_dict(_saved)


func _chain() -> Array:
	return (JSON.parse_string(FileAccess.get_file_as_string(Objectives.PATH)) as Dictionary)["objectives"]


## The story objectives on a stub world, in the tree (complete() starts a timer), not processing.
func _objectives(w: StubWorld) -> Objectives:
	w.fleet = StubFleet.new()
	w.add_child(w.fleet)
	add_child_autofree(w)
	var o := Objectives.new()
	o.world = w
	w.add_child(o)
	o.set_process(false)
	for c: Node in o.get_children():
		c.set_process(false)
	return o


## Makes one step's condition hold, the way play would (the state its value_of reads).
func _satisfy(def: Dictionary, w: StubWorld) -> void:
	var key: String = str(def.get("key", ""))
	var target: int = int(def.get("target", 1))
	match str(def.get("type", "stat")):
		"stat":
			GameState.stats[key] = maxf(float(GameState.stats.get(key, 0.0)), float(target))
		"upgrade":
			GameState.upgrades[key] = maxi(int(GameState.upgrades.get(key, 0)), target)
		"tower":
			GameState.flags["signal_tower"] = maxi(SignalTower.tier(), target)
		"flag":
			GameState.flags[key] = true
		"bench":
			GameState.flags["bench_tier"] = maxi(BenchTiers.tier(), target)
		"robot":
			var type_id: String = "scoopie" if key == "any" else key
			w.fleet.counts[type_id] = maxi(int(w.fleet.counts.get(type_id, 0)), target)
		"zone":
			GameState.world["orders"] = {"groups": {"scoopie": {"zone": range(target)}}}
		"hub_level":
			GameState.world["hub_level"] = maxi(int(GameState.world.get("hub_level", 1)), target)
		_:
			fail_test("no way to satisfy objective type %s" % def.get("type"))


## What Objectives._process does on its refresh tick for the step on the card.
func _tick(o: Objectives) -> void:
	var def: Dictionary = o.current()
	if not def.is_empty() and o.value_of(def) >= o.target_of(def):
		o.complete()


func test_b4_chain_has_the_21_steps_this_triage_checked() -> void:
	assert_eq(_chain().size(), 21, "a changed chain needs the out-of-order check read again")


func test_b4_objectives_play_through_in_order() -> void:
	var w := StubWorld.new()
	var o := _objectives(w)
	for k: int in o.chain.size():
		assert_eq(o.step, k, "waits on step %s until it is done" % o.chain[k]["id"])
		_satisfy(o.chain[k], w)
		_tick(o)
	assert_eq(o.step, o.chain.size(), "every step finishes")


## B4: each step in turn is done first, before anything else; the chain must still pass it when
## its turn comes, with no second action from the player.
func test_b4_a_step_done_before_its_turn_completes_when_it_comes_up() -> void:
	var n: int = _chain().size()
	for early: int in n:
		GameState.new_game()
		GameState.flags["onboard_brief"] = true
		GameState.flags["objectives_v2"] = true
		var w := StubWorld.new()
		var o := _objectives(w)
		_satisfy(o.chain[early], w)
		var stalled: String = ""
		for k: int in n:
			if k != early:
				_satisfy(o.chain[k], w)
			_tick(o)
			if o.step != k + 1 and stalled == "":
				stalled = str(o.chain[k]["id"])
		assert_eq(stalled, "", "step %s done early: the chain stalls at %s" % [o.chain[early]["id"], stalled])
		w.queue_free()


## B4: everything done before the first step is even on the card (a player who ignores the card).
func test_b4_all_steps_done_up_front_drain_one_per_tick() -> void:
	var w := StubWorld.new()
	var o := _objectives(w)
	for def: Dictionary in o.chain:
		_satisfy(def, w)
	for k: int in o.chain.size():
		_tick(o)
	assert_eq(o.step, o.chain.size(), "one step per tick, none left behind")


## B4: a save made out of order catches up silently on load (Objectives._catch_up).
func test_b4_load_catches_up_past_steps_done_out_of_order() -> void:
	var chain: Array = _chain()
	var holder := StubWorld.new()
	holder.fleet = StubFleet.new()
	holder.add_child(holder.fleet)
	add_child_autofree(holder)
	for def: Dictionary in chain:
		if str(def.get("type", "")) != "robot":  # no robots in the loading stub
			_satisfy(def, holder)
	var o := Objectives.new()
	o.world = holder
	holder.add_child(o)
	o.set_process(false)
	var robot_step: int = chain.map(func(d: Dictionary) -> String: return str(d["type"])).find("robot")
	assert_eq(o.step, robot_step, "the load stops at the first step that does not hold (%s)" % chain[robot_step]["id"])


## B4: the values the chain reads only ever grow in play, except the zone, which the player can
## erase. An erased zone must put the step back to "not done", not strand it.
func test_b4_zone_step_reads_the_current_zone() -> void:
	var w := StubWorld.new()
	var o := _objectives(w)
	var zone_def: Dictionary = o.chain.filter(func(d: Dictionary) -> bool: return str(d["type"]) == "zone")[0]
	_satisfy(zone_def, w)
	assert_eq(o.value_of(zone_def), 1.0)
	GameState.world["orders"] = {}
	assert_eq(o.value_of(zone_def), 0.0, "erased before its turn: the step asks again, and painting one hex finishes it")
	_satisfy(zone_def, w)
	assert_gte(o.value_of(zone_def), o.target_of(zone_def))


## B4 (prerequisites): nothing a step needs is locked behind a later step. Bench tiers and story
## unlocks name their conditions in data; each must be something an earlier step already asks for
## or something outside the chain.
func test_b4_bench_tiers_wait_only_on_earlier_steps() -> void:
	var chain: Array = _chain()
	var ids: Array = chain.map(func(d: Dictionary) -> String: return str(d["id"]))
	var bench2: int = ids.find("bench2")
	for c: Variant in BenchTiers.def(2).get("requires", []):
		match str(c[0]):
			"tower":
				assert_lt(ids.find("tower"), bench2, "the Bot Bay waits for the tower, an earlier step")
			"stat":
				assert_eq(str(c[1]), "hexes_cleaned")
				assert_lte(int(c[2]), 3, "the Bot Bay waits for 3 clean hexes, the step before it")
				assert_lt(ids.find("hex3"), bench2)
			_:
				fail_test("unchecked Bot Bay condition %s" % str(c))
	assert_lt(bench2, ids.find("robot"), "the Bots tab opens before the first robot is asked for")
	assert_true("salvage_logic" in BenchTiers.def(2).get("grants_research", []), "the Bot Bay brings the Scoopie's research")
	for c: Variant in BenchTiers.def(3).get("requires", []):
		assert_eq(str(c[0]), "hub_level", "the Research Desk waits on the base level only")
		assert_lte(int(c[1]), 2)
	assert_lt(ids.find("base2"), ids.find("research1"), "base level 2 (the Research Desk's gate) is asked before research")


# --- B3: junk laid inside buildings ------------------------------------------------------------

## Points (0.25 m apart) inside a building footprint that the junk keep-out does not block. The
## footprint stands in its own ground frame at `at`, as the town outskirts add theirs.
func _keep_out_holes(at: Vector3, half_m: float) -> int:
	var radius: float = 1840.0
	var k := YardKeepOut.new()
	k.radius = radius
	k.xf_inv = Transform3D(SphereGrid.frame(Vector3.UP), Vector3.UP * radius).affine_inverse()  # a start site far away
	var fr := Transform3D(SphereGrid.frame(at), at.normalized() * radius)
	var rect := Rect2(-half_m, -half_m, half_m * 2.0, half_m * 2.0)
	k.add_world("test", [[fr, rect]])
	var holes: int = 0
	var x: float = -half_m + 0.125
	while x < half_m:
		var z: float = -half_m + 0.125
		while z < half_m:
			if not k.blocks((fr * Vector3(x, 0.0, z)).normalized()):
				holes += 1
			z += 0.25
		x += 0.25
	return holes


## B3: every spot inside a building's footprint keeps junk out. Where it does not, pieces are laid
## inside the building's collider, out of Lumi's reach, and the hex cannot reach the clean rule
## (tools/hex_stick_probe.tscn: cell 153095, 5.04% of its junk inside Outskirts/Tile_1_2).
func test_b3_keep_out_covers_a_whole_building_footprint() -> void:
	pending("B3 junk keep-out has holes inside building footprints (planet/sites/yard_keep_out.gd add_world / _blocks_world)")
	return
	# The outskirts building of the stuck cell, and three more spots round the sphere.
	for at: Vector3 in [Vector3(1299.2, 155.0, -1299.3), Vector3(1203.4, 310.4, -1362.9), Vector3(700.0, 900.0, 1400.0), Vector3(-1000.0, 20.0, 1500.0)]:
		assert_eq(_keep_out_holes(at, 12.0), 0, "unblocked spots inside a 24 m footprint at %s" % str(at))


# --- B4: a later step's purchase closes an earlier step ------------------------------------------

## B4: the Baler (step 4) has no prerequisite, and once it is fitted the bin takes no loose loads
## (Pace.dump_allowed, data/patch.json dump.after_baler = false). junk_dumps then never grows, so a
## player who buys the Baler before the third bin trip can never finish step 1, "Fill the trash bin
## 3 times": the whole chain stops on its first card.
func test_b4_baler_bought_before_the_third_bin_trip_does_not_strand_the_bin_step() -> void:
	pending("B4 the Baler bought before the third bin trip strands step 1 (core/pace.gd dump_allowed, data/objectives.json dump3)")
	return
	var w := StubWorld.new()
	var o := _objectives(w)
	var dump3: Dictionary = o.chain[0]
	assert_eq(str(dump3["key"]), "junk_dumps", "step 1 counts bin trips")
	GameState.stats["junk_dumps"] = int(dump3["target"]) - 1
	GameState.add_currency("cubes", Economy.upgrade_cost(Pace.UP_BALER))
	assert_eq(Economy.buy_upgrade(Pace.UP_BALER), 1, "the Baler can be bought while step 1 is on the card")
	_tick(o)
	var can_still_finish: bool = Pace.dump_allowed() or o.step > 0
	assert_true(can_still_finish, "with the Baler fitted the bin refuses loose loads and step 1 stays at %d / %d for good" % [
		int(o.value_of(dump3)), int(o.target_of(dump3))])


## B4 (new, B26): step 19 "Finish a research project" teaches the Research tab. The Bot Bay (step
## 11) comes with Salvage Logic through Research.grant, which counts as a finished project
## (research_done), so step 19 always holds before its turn and completes by itself: the player is
## told they finished a research project without having opened the Research tab.
func test_b4_research_step_is_not_finished_by_the_bot_bay_gift() -> void:
	pending("B26 the Bot Bay's Salvage Logic gift finishes the research step (ui/bench_tiers.gd buy -> Research.grant counts research_done)")
	return
	var w := StubWorld.new()
	var o := _objectives(w)
	GameState.flags["signal_tower"] = 1
	GameState.stats["hexes_cleaned"] = 3
	GameState.add_currency("cubes", BigNum.from_float(100000.0))
	GameState.add_currency("parts", BigNum.from_float(100000.0))
	assert_true(BenchTiers.buy(w), "the Bot Bay can be bought")
	assert_true(Research.has("salvage_logic"), "the Bot Bay brings Salvage Logic")
	var research1: Dictionary = o.chain.filter(func(d: Dictionary) -> bool: return str(d["id"]) == "research1")[0]
	assert_lt(o.value_of(research1), o.target_of(research1), "no project was run, yet the research step already counts %d / %d" % [
		int(o.value_of(research1)), int(o.target_of(research1))])


# --- B23: the magnet on the globe ----------------------------------------------------------------

## Lumi holding the scoop on one junk cell of a small globe with Magnet Arm at `level`; `pieces`
## loose pieces are laid 1.5 m round the scoop, inside the magnet's radius. One scoop frame runs
## (no pickup: the scoop's own timer is held back). The first piece laid gets `first_size` and
## `first_embed`. Returns [field, view, the pieces laid].
func _magnet_frame(level: int, pieces: int, first_size: int = Pace.SIZE_SMALL, first_embed: float = 0.0) -> Array:
	GameState.upgrades["magnet_arm"] = level
	var fx := GlobeFixture.new()
	var cell: int = fx.region()[8]
	fx.field.materialize(cell)
	var ids: PackedInt32Array = fx.field.pieces_in(cell)
	assert_gte(ids.size(), pieces, "the cell holds enough pieces for the test")
	var w := ScoopWorld.new()
	w.field = fx.field
	w.view = MoveView.new()
	w.view.field = fx.field
	add_child_autofree(w)
	var p := Patch.new()
	p.input = HeldInput.new()
	p.world = w
	p.process_mode = Node.PROCESS_MODE_DISABLED
	w.add_child(p)
	var centre: Vector3 = fx.field.hex_center(cell)
	p.global_transform = Transform3D(SphereGrid.frame(centre.normalized()), centre)
	var origin: Vector3 = p.scoop_origin()
	var laid: Array[int] = []
	for k: int in ids.size():
		var pid: int = ids[k]
		if k >= pieces:
			fx.field.piece_pos[pid] = centre + p.global_transform.basis.x * 40.0  # out of the magnet's way
			continue
		var a: float = TAU * float(k) / float(pieces)
		fx.field.piece_pos[pid] = origin + (p.global_transform.basis.x * cos(a) + p.global_transform.basis.z * sin(a)) * 1.5
		fx.field.piece_embed[pid] = 0.0
		fx.field.piece_size[pid] = Pace.SIZE_SMALL
		laid.append(pid)
	fx.field.piece_size[laid[0]] = first_size
	fx.field.piece_embed[laid[0]] = first_embed
	assert_gt(p.stat("scoop_reach") + p.stat("magnet_radius"), 1.5, "the laid pieces are inside the magnet's radius")
	p._scoop_timer = 5.0
	p._handle_scoop(0.1)
	return [fx.field, w.view, laid]


## B23: the test's own ground. A loose piece Lumi can lift is pulled (so the two tests below fail
## for the right reason).
func test_b23_magnet_pulls_a_loose_piece_lumi_can_lift() -> void:
	var r: Array = _magnet_frame(1, 3)
	var view: MoveView = r[1]
	assert_true(view.moved.has((r[2] as Array[int])[0]), "a loose light piece drifts toward the scoop")


## B23: owner rule "never pulls pieces Lumi can't lift" (data/upgrades.json magnet_arm desc: "Never
## heavy ones").
func test_b23_magnet_leaves_pieces_too_heavy_for_the_lift_tier() -> void:
	pending("B23 the globe magnet pulls pieces Lumi cannot lift (player/patch.gd _handle_scoop: no Pace.can_lift check)")
	return
	var r: Array = _magnet_frame(1, 3, Pace.SIZE_LARGE)
	var field: SphereField = r[0]
	var view: MoveView = r[1]
	var heavy: int = (r[2] as Array[int])[0]
	assert_false(Pace.can_lift(field, heavy), "the piece is over Lumi's starting lift tier")
	assert_false(view.moved.has(heavy), "a piece Lumi cannot lift stays where it is")


## B23: "never from inside a heap": a piece seated in a heap (piece_embed > 0) is dug out by the
## scoop, not dragged out by the magnet.
func test_b23_magnet_leaves_pieces_embedded_in_a_heap() -> void:
	pending("B23 the globe magnet pulls pieces embedded in a heap (player/patch.gd _handle_scoop: no piece_embed check)")
	return
	var r: Array = _magnet_frame(1, 3, Pace.SIZE_SMALL, 0.5)
	var view: MoveView = r[1]
	assert_false(view.moved.has((r[2] as Array[int])[0]), "an embedded piece stays in its heap")


## B23: "capped": the description says "a few loose pieces". The flat rule this replaced pulled at
## most 2 + one per level at a time; with 12 loose pieces in range the globe pulls all 12.
func test_b23_magnet_pulls_only_a_few_pieces_at_a_time() -> void:
	pending("B23 the globe magnet has no cap on pieces pulled at once (player/patch.gd _handle_scoop)")
	return
	var r: Array = _magnet_frame(1, 12)
	var view: MoveView = r[1]
	assert_lte(view.moved.size(), 6, "Magnet Arm level 1 pulls a few pieces, not everything in range (12 laid)")


# --- B8: the carried bale and Lumi's body --------------------------------------------------------

## Lumi wearing `design` with one full bale picked up and its pick-up tween finished. Returns the
## probe's measure (tools/exit_probe.gd carry_gap): the bale's bottom against the top of the model.
func _carry_gap(design: String) -> Dictionary:
	GameState.flags["patch_skin"] = design
	var p := Patch.new()
	add_child_autofree(p)
	p.set_process(false)
	p.set_physics_process(false)
	for c: Node in p.get_children():
		if c.name != "Stack" and c.name != "Model":
			c.process_mode = Node.PROCESS_MODE_DISABLED
	var bale := JunkCube.create(BigNum.from_float(10.0), {"fill": 1.0, "colors": [Color(0.5, 0.45, 0.4)]})
	add_child(bale)
	bale.global_position = Vector3(0.0, 0.3, -0.8)
	p.pick_up(bale)
	await wait_seconds(0.5)
	p._update_stack(0.016)
	var gap: Dictionary = (load("res://tools/exit_probe.gd") as GDScript).call("carry_gap", p)
	gap["design"] = design
	return gap


## B8: a carried bale rests clear of the body on every design (thin antennae may reach it; anything
## 12 cm wide or more may not).
func test_b8_carried_bale_rests_above_the_body_on_every_design() -> void:
	for id: String in Designs.ids():
		var gap: Dictionary = await _carry_gap(id)
		gut.p("[b8] %s" % JSON.stringify(gap))
		assert_gte(float(gap["gap_solid"]), 0.1, "%s: the bale's bottom is %.2f m from the top of the body" % [id, float(gap["gap_solid"])])
