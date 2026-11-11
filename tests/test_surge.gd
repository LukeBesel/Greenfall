extends GutTest
## The Surge (task M3-09, design spec section 8; systems/surge.gd, core/surge_rules.gd, the
## planet's "balance" table): only Lumi's own work charges the Bloom Core; a full core is released
## as a burst that widens and speeds her sweep, at least three times her output for its duration,
## measured here on a real sweep; it scales by district and pushes a growth wave from the planet's
## wave district on; the charge is saved; the bot lets it go while sweeping. Every number is the
## planet's: the first planet's are the spec's, the dummy planet has its own.

const FIRST: StringName = &"verdance"
const DUMMY: StringName = &"testworld"
const PLANETS: Array[StringName] = [FIRST, DUMMY]
const SPEC_DURATION_S: float = 12.0
const SPEC_OUTPUT: float = 3.0
const SPEC_WAVE_DISTRICT: int = 4
const TICK: float = 1.0 / 60.0
const EPS: float = 0.0005


class HeldInput extends InputSource:
	func scoop_held() -> bool:
		return true


## The junk view's part in a sweep: where a piece is, and a mesh for the pickup effect.
class SweepView extends RefCounted:
	var field: SphereField
	var mesh := BoxMesh.new()

	func move_piece(pid: int, pos: Vector3) -> void:
		field.piece_pos[pid] = pos

	func piece_transform(pid: int) -> Transform3D:
		return Transform3D(Basis(), field.piece_pos[pid])

	func piece_mesh(_pid: int) -> Mesh:
		return mesh


## The members of the world that Lumi's sweep reads.
class SweepWorld extends Node:
	var field: SphereField
	var view: SweepView

	func collect_piece(pid: int) -> void:
		field.remove_piece(pid)

	func salvage_materials(_type_id: String, _vol: float) -> void:
		pass


var _saved: Dictionary = {}
var _nodes: Array[Node] = []
var _fixtures: Array[DistrictFixture] = []
var _charged: int = 0
var _released: Array[Array] = []
var _ended: int = 0


func before_all() -> void:
	Planets.register_dir(DistrictFixture.FIXTURE_PLANETS)


func after_all() -> void:
	Planets.unregister(DUMMY)


func before_each() -> void:
	_saved = GameState.to_dict()
	GameState.new_game()
	GameState.stats["robots_built"] = 1  # [lead Nov 11] the Surge opens with the first robot
	_charged = 0
	_released.clear()
	_ended = 0
	EventBus.surge_charged.connect(_on_charged)
	EventBus.surge_released.connect(_on_released)
	EventBus.surge_ended.connect(_on_ended)


func after_each() -> void:
	EventBus.surge_charged.disconnect(_on_charged)
	EventBus.surge_released.disconnect(_on_released)
	EventBus.surge_ended.disconnect(_on_ended)
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	for fx: DistrictFixture in _fixtures:
		fx.free_systems()
	_fixtures.clear()
	if Input.is_action_pressed(Surge.ACTION):
		Input.action_release(Surge.ACTION)
	GameState.from_dict(_saved)


func _on_charged() -> void:
	_charged += 1


func _on_released(district_id: String, output: float, wave_rings: int) -> void:
	_released.append([district_id, output, wave_rings])


func _on_ended() -> void:
	_ended += 1


func _cfg(planet_id: StringName) -> Dictionary:
	return SurgeRules.config(Planets.by_id(planet_id).table(SurgeRules.TABLE))


## A Surge on a planet's own numbers. With districts, Lumi stands in the planet's district `n`.
func _surge(planet_id: StringName, saved: Dictionary = {}, n: int = 0) -> Surge:
	var districts: Districts = null
	if n > 0:
		var fx := DistrictFixture.new(planet_id)
		_fixtures.append(fx)
		districts = fx.districts
		var id: String = districts.ids()[n - 1]
		districts.set_player_cell(districts.cells_of(id)[0])
	var s := Surge.new()
	_nodes.append(s)
	s.setup(Planets.by_id(planet_id), districts, saved)
	return s


## Lumi clears `share` of a full charge of waste by hand, a little at a time, as play does.
func _work(s: Surge, share: float) -> void:
	var slice: float = 0.02
	var done: float = 0.0
	while done < share - 0.000001:
		var part: float = minf(slice, share - done)
		EventBus.pollution_cleared.emit("any_kind", s.units_needed() * part, true)
		s.step(float(s.config()["min_fill_s"]) * slice * 1.5)
		done += part


func _fill(s: Surge) -> void:
	_work(s, 1.0 - s.charge() + 0.01)


# --- Data -------------------------------------------------------------------------------------

func test_the_table_documents_every_field(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var table: Dictionary = Planets.by_id(planet_id).table(SurgeRules.TABLE)
	assert_true(table.has(SurgeRules.BLOCK), "%s has a surge block in its balance table" % planet_id)
	var doc: String = str(table.get("_doc", ""))
	assert_ne(doc, "", "the table has a _doc")
	if planet_id == DUMMY:
		return  # the dummy planet's _doc points at the real table's
	var block: Dictionary = table[SurgeRules.BLOCK]
	for key: String in block:
		assert_true(doc.contains(key), "_doc explains surge.%s" % key)
		if block[key] is Dictionary and key != "stats":
			for sub: String in (block[key] as Dictionary):
				assert_true(doc.contains(sub), "_doc explains surge.%s.%s" % [key, sub])


func test_the_first_planet_follows_the_spec() -> void:
	var cfg: Dictionary = _cfg(FIRST)
	assert_almost_eq(float(cfg["duration_s"]), SPEC_DURATION_S, 0.001, "a Surge lasts 12 seconds")
	assert_eq(int(cfg["wave_from"]), SPEC_WAVE_DISTRICT, "the growth wave comes with city 4")
	for n: int in range(1, 7):
		assert_gte(SurgeRules.output_mult(cfg, n), SPEC_OUTPUT, "at least 3x output in district %d" % n)
		assert_gt(SurgeRules.stat_mult(cfg, "scoop_width", n), 1.0, "the sweep widens in district %d" % n)
		assert_gt(SurgeRules.stat_mult(cfg, "scoop_rate", n), 1.0, "the sweep speeds up in district %d" % n)


func test_a_planet_with_no_surge_block_has_no_surge() -> void:
	var s := Surge.new()
	_nodes.append(s)
	s.setup(PlanetDefinition.new(), null, {"charge": 0.8})
	assert_false(s.enabled())
	assert_eq(s.charge(), 0.0, "a saved charge means nothing without the rules")
	EventBus.pollution_cleared.emit("any_kind", 100000.0, true)
	assert_eq(s.charge(), 0.0)
	assert_false(s.release())
	assert_eq(s.gauge(), 0.0)


# --- Charging: only from active play ----------------------------------------------------------

func test_lumis_own_work_charges_the_core(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var s: Surge = _surge(planet_id)
	_work(s, 0.5)
	assert_almost_eq(s.charge(), 0.5, 0.001, "half the units, half the charge")
	assert_false(s.can_release())
	assert_eq(_charged, 0)
	_work(s, 0.5)
	assert_almost_eq(s.charge(), 1.0, 0.001)
	assert_true(s.can_release(), "a full core can be released")
	assert_eq(_charged, 1, "the core announces that it filled, once")
	_work(s, 0.5)
	assert_eq(s.charge(), 1.0, "a full core takes no more")
	assert_eq(_charged, 1)


func test_work_on_every_pollution_kind_counts() -> void:
	var s: Surge = _surge(FIRST)
	var kinds: Dictionary = Planets.by_id(FIRST).table(Pollution.TABLE)["kinds"]
	assert_gt(kinds.size(), 1)
	var before: float = 0.0
	for id: String in kinds:
		EventBus.pollution_cleared.emit(id, s.units_needed() * 0.01, true)
		s.step(60.0)
		assert_gt(s.charge(), before, "hand work on %s charges the core" % id)
		before = s.charge()


func test_robots_never_charge_the_core(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var s: Surge = _surge(planet_id)
	for _i: int in 50:
		EventBus.pollution_cleared.emit("any_kind", s.units_needed(), false)
		s.step(60.0)
	assert_eq(s.charge(), 0.0, "robot work is not Lumi's")
	assert_eq(_charged, 0)


func test_pressing_and_tending_by_hand_charge_the_core(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var s: Surge = _surge(planet_id)
	var cfg: Dictionary = s.config()
	EventBus.cube_made.emit({})
	assert_almost_eq(s.charge(), float(cfg["per_bale"]), EPS, "a pressed bale")
	s.step(600.0)
	EventBus.hand_tended.emit(Surge.TEND_PLANT)
	assert_almost_eq(s.charge(), float(cfg["per_bale"]) + float(cfg["per_plant"]), EPS, "a seed planted")
	s.step(600.0)
	EventBus.hand_tended.emit(Surge.TEND_WATER)
	assert_almost_eq(s.charge(), float(cfg["per_bale"]) + float(cfg["per_plant"]) + float(cfg["per_water"]), EPS, "a pour on a plant")
	assert_gt(float(cfg["per_bale"]), 0.0)
	assert_gt(float(cfg["per_plant"]), 0.0)
	assert_gt(float(cfg["per_water"]), 0.0)


func test_no_idle_charge_and_no_charge_while_away(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var s: Surge = _surge(planet_id)
	_work(s, 0.3)
	var before: float = s.charge()
	for _i: int in 600:
		s.step(60.0)  # ten hours of standing still
	assert_eq(s.charge(), before, "time alone charges nothing")
	var saved: Dictionary = s.save_state()
	var later: Surge = _surge(planet_id, saved)  # the save loaded any time later
	later.step(86400.0)
	assert_almost_eq(later.charge(), before, 0.0002, "the core comes back as it was left")
	assert_eq(saved.keys(), ["charge"], "the save holds no clock to credit time away from")


func test_the_core_fills_no_faster_than_the_planet_allows(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var s: Surge = _surge(planet_id)
	var fastest: float = float(s.config()["min_fill_s"])
	assert_gt(fastest, 0.0)
	var bank: float = Surge.BANK_S / fastest
	var steps: int = int(fastest * 0.5 / 0.1)
	for _i: int in steps:  # half the fastest fill time of impossibly fast work
		EventBus.pollution_cleared.emit("any_kind", s.units_needed() * 10.0, true)
		s.step(0.1)
	assert_lte(s.charge(), minf(1.0, 0.5 + bank + 0.01), "work faster than the cap does not fill it sooner")
	assert_gte(s.charge(), minf(1.0, 0.5 - 0.01), "the cap itself is reached")


# --- Release ----------------------------------------------------------------------------------

func test_release_needs_a_full_core_and_runs_for_its_duration(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var s: Surge = _surge(planet_id)
	_work(s, 0.9)
	assert_false(s.release(), "not full: nothing happens")
	assert_eq(_released.size(), 0)
	_fill(s)
	assert_true(s.release())
	assert_eq(_released.size(), 1)
	assert_almost_eq(float(_released[0][1]), SurgeRules.output_mult(s.config(), 1), EPS, "the event carries the output it gives")
	assert_true(s.active())
	assert_eq(s.charge(), 0.0, "the charge is spent")
	assert_almost_eq(s.time_left(), float(s.config()["duration_s"]), EPS)
	assert_almost_eq(s.gauge(), 1.0, EPS, "the gauge starts full and drains")
	assert_false(s.release(), "one Surge at a time")
	EventBus.pollution_cleared.emit("any_kind", s.units_needed() * 0.05, true)
	assert_eq(s.charge(), 0.0, "work during a Surge does not charge the next")
	s.step(s.duration() * 0.5)
	assert_almost_eq(s.gauge(), 0.5, 0.001, "half way through, the gauge is half drained")
	assert_true(s.active())
	assert_eq(_ended, 0)
	s.step(s.duration() * 0.5 + TICK)
	assert_false(s.active(), "it ends after its duration")
	assert_eq(_ended, 1)
	assert_eq(int(GameState.stats.get(Surge.STAT_COUNT, 0)), 1)
	EventBus.pollution_cleared.emit("any_kind", s.units_needed() * 0.05, true)
	assert_gt(s.charge(), 0.0, "and the core charges again")


func test_a_running_surge_multiplies_lumis_sweep_stats(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var s: Surge = _surge(planet_id)
	var cfg: Dictionary = s.config()
	var stats: Dictionary = cfg["stats"]
	assert_true(stats.has(SurgeRules.STAT_RATE) and stats.has(SurgeRules.STAT_BITE))
	for id: String in stats:
		assert_eq(Surge.stat_mod(id, 2.0), 2.0, "%s is untouched before the release" % id)
	assert_eq(Surge.chest_pack(), 1.0)
	_fill(s)
	s.release()
	for id: String in stats:
		assert_almost_eq(Surge.stat_mod(id, 2.0), 2.0 * float(stats[id]), EPS, "%s during the Surge" % id)
	assert_eq(Surge.stat_mod("move_speed_of_nothing", 2.0), 2.0, "other stats are left alone")
	assert_almost_eq(Surge.chest_pack(), SurgeRules.chest_pack(cfg, 1), EPS)
	assert_lt(Surge.chest_pack(), 1.0, "a Surge's load packs tighter than a plain one")
	assert_eq(Surge.breakdown(SurgeRules.STAT_RATE).size(), 1, "the stat tooltip names the Surge")
	s.step(s.duration() + TICK)
	for id: String in stats:
		assert_eq(Surge.stat_mod(id, 2.0), 2.0, "%s is back to normal after it" % id)
	assert_eq(Surge.chest_pack(), 1.0)
	assert_eq(Surge.breakdown(SurgeRules.STAT_RATE).size(), 0)


func test_a_surge_freed_mid_burst_takes_its_effect_with_it() -> void:
	var s: Surge = _surge(FIRST)
	_fill(s)
	s.release()
	assert_gt(Surge.stat_mod(SurgeRules.STAT_RATE, 1.0), 1.0)
	s.free()
	assert_eq(Surge.stat_mod(SurgeRules.STAT_RATE, 1.0), 1.0, "leaving the planet ends the burst")


# --- The measured sweep -------------------------------------------------------------------------

## Lumi on a small globe of junk with the scoop held, not processing: the test steps her sweep.
func _sweeper() -> Array:
	var fx := GlobeFixture.new()
	var def: PlanetDefinition = Planets.by_id(FIRST)
	fx.field.worth = HexWorth.for_planet(def, fx.grid, DistrictFixture.face_centre_cells(fx.grid, def.hub_count))
	var w := SweepWorld.new()
	w.field = fx.field
	w.view = SweepView.new()
	w.view.field = fx.field
	add_child_autofree(w)
	var p := Patch.new()
	p.input = HeldInput.new()
	p.world = w
	p.process_mode = Node.PROCESS_MODE_DISABLED
	w.add_child(p)
	return [fx, p]


## Lets the pieces still flying into the chest land before the test's Lumi is freed.
func _settle() -> void:
	await wait_seconds(0.7)


## Stands Lumi on a junk cell with every piece of it loose and light just in front of the scoop.
func _stand_on(fx: GlobeFixture, p: Patch, cell: int) -> void:
	fx.field.materialize(cell)
	var centre: Vector3 = fx.field.hex_center(cell)
	p.global_transform = Transform3D(SphereGrid.frame(centre.normalized()), centre)
	for pid: int in fx.field.pieces_in(cell):
		fx.field.piece_pos[pid] = p.scoop_origin() + p.forward() * 0.6
		fx.field.piece_embed[pid] = 0.0
		fx.field.piece_size[pid] = Pace.SIZE_SMALL


## Units of waste Lumi's sweep lifts in `seconds` of sweeping with waste always in reach and the
## chest emptied as it fills (so only the sweep is measured). A given Surge runs alongside.
func _swept(fx: GlobeFixture, p: Patch, seconds: float, s: Surge = null) -> float:
	var cells: PackedInt32Array = fx.region()
	var next: int = 8
	var cell: int = cells[next]
	_stand_on(fx, p, cell)
	var swept: float = 0.0
	var left: float = fx.field.hex_left[cell]
	for _i: int in int(round(seconds / TICK)):
		p._handle_scoop(TICK)
		if s != null:
			s.step(TICK)
		p.compartment.take_all()
		p.compartment.pending = 0.0
		swept += left - fx.field.hex_left[cell]
		left = fx.field.hex_left[cell]
		if left <= Pace.pulse_volume() * 4.0:  # nearly bare: on to the next cell
			next += 1
			cell = cells[next]
			_stand_on(fx, p, cell)
			left = fx.field.hex_left[cell]
	return swept


func test_measured_sweep_output_is_at_least_three_times_for_the_whole_surge() -> void:
	var made: Array = _sweeper()
	var fx: GlobeFixture = made[0]
	var p: Patch = made[1]
	var s: Surge = _surge(FIRST)
	var seconds: float = s.duration()
	var plain: float = _swept(fx, p, seconds)
	var stated: float = Pace.pulse_volume() * Economy.stat("scoop_rate")
	assert_between(plain / seconds, stated * 0.9, stated * 1.01, "the plain sweep lifts about its stat's worth (whole frames round it down a little)")
	_fill(s)
	assert_true(s.release())
	p._scoop_timer = 0.0
	var surged: float = _swept(fx, p, seconds, s)
	var measured: float = surged / plain
	gut.p("measured Surge output: %.1f units in %.0f s against %.1f plain = %.2fx" % [surged, seconds, plain, measured])
	assert_gte(measured, SPEC_OUTPUT, "a Surge at least triples what Lumi's sweep lifts, over its whole duration")
	assert_gte(measured, SurgeRules.output_mult(s.config(), 1) - 0.05, "and no less than the output the rules state")
	assert_almost_eq(surged / seconds, stated * SurgeRules.output_mult(s.config(), 1), stated * 0.05, "its pulses are not rounded to whole frames")
	assert_false(s.active(), "the Surge has run out")
	p._scoop_timer = 0.0
	var after: float = _swept(fx, p, seconds)
	assert_almost_eq(after, plain, plain * 0.03, "afterwards the sweep is the plain one again")
	await _settle()


func test_measured_sweep_follows_any_planets_numbers() -> void:
	var made: Array = _sweeper()
	var fx: GlobeFixture = made[0]
	var p: Patch = made[1]
	var s: Surge = _surge(DUMMY)
	var seconds: float = s.duration()
	var plain: float = _swept(fx, p, seconds)
	_fill(s)
	s.release()
	p._scoop_timer = 0.0
	var surged: float = _swept(fx, p, seconds, s)
	var stated: float = SurgeRules.output_mult(s.config(), 1)
	assert_between(surged / plain, stated - 0.1, stated * 1.12, "the dummy planet's own multiplier, with no code change")
	assert_ne(SurgeRules.output_mult(s.config(), 1), SurgeRules.output_mult(_cfg(FIRST), 1))
	await _settle()


func test_the_surge_sweep_is_wider() -> void:
	var made: Array = _sweeper()
	var fx: GlobeFixture = made[0]
	var p: Patch = made[1]
	var s: Surge = _surge(FIRST)
	var cell: int = fx.region()[8]
	_stand_on(fx, p, cell)
	var side: float = Economy.stat("scoop_width") * 0.5 + 0.35  # just past the plain sweep's edge
	for pid: int in fx.field.pieces_in(cell):
		fx.field.piece_pos[pid] = p.scoop_origin() + p.forward() * 0.1 + p.global_transform.basis.x * side
	var full: float = fx.field.hex_left[cell]
	p._handle_scoop(TICK)
	assert_eq(fx.field.hex_left[cell], full, "the plain sweep does not reach it")
	_fill(s)
	s.release()
	p._handle_scoop(TICK)
	assert_lt(fx.field.hex_left[cell], full, "the Surge's wider sweep does")
	await _settle()


func test_a_surges_load_packs_tight_in_the_chest() -> void:
	var made: Array = _sweeper()
	var fx: GlobeFixture = made[0]
	var p: Patch = made[1]
	var s: Surge = _surge(FIRST)
	var cell: int = fx.region()[8]
	_stand_on(fx, p, cell)
	var full: float = fx.field.hex_left[cell]
	p._handle_scoop(TICK)
	var plain_vol: float = full - fx.field.hex_left[cell]
	assert_almost_eq(p.compartment.pending, plain_vol, 0.001, "a plain sweep takes its own volume of chest")
	p.compartment.pending = 0.0
	_fill(s)
	s.release()
	p._scoop_timer = 0.0
	full = fx.field.hex_left[cell]
	p._handle_scoop(TICK)
	var surge_vol: float = full - fx.field.hex_left[cell]
	assert_gt(surge_vol, plain_vol, "a Surge pulse lifts more")
	assert_almost_eq(p.compartment.pending, surge_vol * SurgeRules.chest_pack(s.config(), 1), 0.001, "and takes less chest for it")
	assert_lte(p.compartment.pending, plain_vol, "so the chest fills no faster than in plain sweeping")
	await _settle()


# --- Scaling by district ----------------------------------------------------------------------

func test_the_charge_and_the_burst_scale_by_district() -> void:
	var cfg: Dictionary = _cfg(FIRST)
	var count: int = Districts.specs_for(Planets.by_id(FIRST)).size()
	assert_gt(count, SPEC_WAVE_DISTRICT)
	for n: int in range(2, count + 1):
		assert_gte(SurgeRules.units_needed(cfg, n), SurgeRules.units_needed(cfg, n - 1), "district %d needs no less work for a charge" % n)
		assert_gt(SurgeRules.output_mult(cfg, n), SurgeRules.output_mult(cfg, n - 1), "district %d's Surge is stronger" % n)
		assert_gte(SurgeRules.wave_rings(cfg, n), SurgeRules.wave_rings(cfg, n - 1))
	assert_gt(SurgeRules.units_needed(cfg, count), SurgeRules.units_needed(cfg, 1))
	assert_gt(SurgeRules.wave_rings(cfg, count), SurgeRules.wave_rings(cfg, SPEC_WAVE_DISTRICT), "the wave reaches further by the last city")
	assert_eq(SurgeRules.units_needed(cfg, count + 5), SurgeRules.units_needed(cfg, count), "a district past the list uses the last entry")


func test_the_surge_reads_the_district_lumi_stands_in() -> void:
	var first: Surge = _surge(FIRST, {}, 1)
	var late: Surge = _surge(FIRST, {}, 5)
	assert_eq(first.district_n(), 1)
	assert_eq(late.district_n(), 5)
	assert_gt(late.units_needed(), first.units_needed())
	assert_gt(late.output_mult(), first.output_mult())
	_fill(late)
	late.release()
	assert_almost_eq(Surge.stat_mod(SurgeRules.STAT_RATE, 1.0), SurgeRules.stat_mult(late.config(), SurgeRules.STAT_RATE, 5), EPS)
	assert_gt(Surge.stat_mod(SurgeRules.STAT_RATE, 1.0), SurgeRules.stat_mult(late.config(), SurgeRules.STAT_RATE, 1))
	assert_eq(str(_released[0][0]), late.district_id())


func test_the_wave_starts_at_the_planets_wave_district() -> void:
	var cfg: Dictionary = _cfg(FIRST)
	for n: int in range(1, SPEC_WAVE_DISTRICT):
		assert_false(SurgeRules.has_wave(cfg, n), "no wave in district %d" % n)
		assert_eq(SurgeRules.wave_rings(cfg, n), 0)
	for n: int in range(SPEC_WAVE_DISTRICT, 7):
		assert_true(SurgeRules.has_wave(cfg, n), "a wave in district %d" % n)
		assert_gt(SurgeRules.wave_rings(cfg, n), 0)
	assert_true(SurgeRules.has_wave(_cfg(DUMMY), 1), "the dummy planet's wave district is its own")


# --- The growth wave --------------------------------------------------------------------------

## A garden on a small globe with one seed planted on each of three clean cells: the cell Lumi
## stands on, a neighbour, and one far away. Returns [world, garden, [slots], Lumi's cell].
func _planted_world() -> Array:
	var w := GlobeWorld.new(5)
	add_child_autofree(w)
	var g: Garden = w.add_garden()
	g.set_process(false)
	var home: int = w.land_cell(4)
	var near: int = -1
	for c: int in w.fixture.grid.cells_around(home, 1):
		if c != home and w.field.hex_hub[c] == 0 and not w.field.is_water(c):
			near = c
			break
	var far: int = -1
	var ring: PackedInt32Array = w.fixture.grid.cells_around(home, 5)
	for i: int in range(ring.size() - 1, -1, -1):
		if w.field.hex_hub[ring[i]] == 0 and not w.field.is_water(ring[i]):
			far = ring[i]
			break
	GameState.currencies["seeds"] = BigNum.from_float(10.0)
	var slots: Array[int] = []
	for c: int in [home, near, far]:
		w.clean(c)
		var slot: int = (g.hex_slots[c] as PackedInt32Array)[0]
		assert_true(g.plant(slot), "a seed goes in on cell %d" % c)
		slots.append(slot)
	return [w, g, slots, home]


func test_the_wave_waters_and_pushes_growth_on_nearby_hexes() -> void:
	var made: Array = _planted_world()
	var w: GlobeWorld = made[0]
	var g: Garden = made[1]
	var slots: Array[int] = made[2]
	var home: int = made[3]
	var s: Surge = _surge(DUMMY)  # its Surges push a wave from the first district
	s.bind_wave(w.fixture.grid, g, func() -> int: return home)
	_fill(s)
	assert_true(s.release())
	assert_eq(int(_released[0][2]), SurgeRules.wave_rings(s.config(), 1), "the event says how far the wave reached")
	var cfg: Dictionary = s.config()
	for i: int in 2:
		assert_almost_eq(g.slot_water[slots[i]], float(cfg["wave_water_s"]), 0.01, "a plant in reach is watered")
		assert_almost_eq(g.slot_progress[slots[i]], float(cfg["wave_stages"]), 0.01, "and its growth is pushed on")
	assert_eq(g.slot_water[slots[2]], 0.0, "a plant out of reach is not touched")
	assert_eq(g.slot_progress[slots[2]], 0.0)


func test_a_full_stage_push_shows_on_the_next_growth_tick() -> void:
	var made: Array = _planted_world()
	var g: Garden = made[1]
	var slots: Array[int] = made[2]
	g.water(slots[0], 30.0)
	g.push_growth(slots[0], 1.0)
	g.push_growth(slots[2], 1.0)  # dry: it waits for water
	g._tick = 0.5
	g._process(0.0)
	assert_eq(g.slot_stage[slots[0]], 1, "a watered plant steps up a stage")
	assert_eq(g.slot_stage[slots[2]], 0, "a dry one does not")


func test_no_wave_before_the_wave_district() -> void:
	var made: Array = _planted_world()
	var w: GlobeWorld = made[0]
	var g: Garden = made[1]
	var slots: Array[int] = made[2]
	var home: int = made[3]
	var s: Surge = _surge(FIRST, {}, 1)
	s.bind_wave(w.fixture.grid, g, func() -> int: return home)
	_fill(s)
	assert_true(s.release())
	assert_eq(int(_released[0][2]), 0)
	assert_eq(g.slot_water[slots[0]], 0.0, "city 1's Surge leaves the plants alone")
	assert_eq(g.slot_progress[slots[0]], 0.0)


# --- Saving -----------------------------------------------------------------------------------

func test_the_charge_is_saved(planet_id: StringName = use_parameters(PLANETS)) -> void:
	var s: Surge = _surge(planet_id)
	_work(s, 0.64)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.save_state()))
	var again: Surge = _surge(planet_id, saved)
	assert_almost_eq(again.charge(), s.charge(), 0.0002)
	assert_false(again.active())
	_fill(again)
	var full: Surge = _surge(planet_id, JSON.parse_string(JSON.stringify(again.save_state())))
	assert_true(full.can_release(), "a full core is still full after a load")
	assert_eq(_surge(planet_id, {"charge": 7.0}).charge(), 1.0, "a bad save is clamped")
	assert_eq(_surge(planet_id, {}).charge(), 0.0, "a save from before the Surge starts empty")


func test_a_surge_cut_short_by_a_save_is_over_on_load() -> void:
	var s: Surge = _surge(FIRST)
	_fill(s)
	s.release()
	var again: Surge = _surge(FIRST, s.save_state())
	assert_eq(again.charge(), 0.0)
	assert_false(again.active())


# --- Input ------------------------------------------------------------------------------------

func test_the_release_has_a_key_and_a_pad_way() -> void:
	assert_true(InputMap.has_action(Surge.ACTION))
	var keys: int = 0
	for ev: InputEvent in InputMap.action_get_events(Surge.ACTION):
		keys += 1 if ev is InputEventKey else 0
	assert_gt(keys, 0, "the keyboard has a release key")
	assert_true(Settings.REBINDABLE.any(func(e: Array) -> bool: return e[0] == Surge.ACTION), "it can be rebound")
	for action: String in Surge.PAD_CHORD:
		var pad: int = 0
		for ev: InputEvent in InputMap.action_get_events(action):
			pad += 1 if ev is InputEventJoypadButton else 0
		assert_gt(pad, 0, "%s is a controller button: both together release the Surge" % action)
	var was_pad: bool = Settings.last_input_pad
	Settings.last_input_pad = false
	assert_ne(SurgeFx.release_glyph(), "")
	Settings.last_input_pad = true
	assert_true(SurgeFx.release_glyph().contains("+"), "the pad prompt names both buttons")
	Settings.last_input_pad = was_pad


func test_the_players_key_releases_a_full_core_when_input_is_live() -> void:
	var s: Surge = _surge(FIRST)
	var live: Array[bool] = [false]
	s.input_gate = func() -> bool: return live[0]
	_fill(s)
	Input.action_press(Surge.ACTION)
	s._physics_process(TICK)
	assert_false(s.active(), "a screen is open: the key does nothing")
	live[0] = true
	s._physics_process(TICK)
	assert_true(s.active(), "the key releases the Surge")
	Input.action_release(Surge.ACTION)


# --- The bot ----------------------------------------------------------------------------------

func test_the_bot_releases_when_full_and_sweeping_with_room() -> void:
	var s: Surge = _surge(FIRST)
	var bot := AutoplaySurge.new()
	assert_false(bot.tick(null, true, 0.0, 1.0), "a planet with no Surge")
	assert_false(bot.tick(s, true, 0.0, 1.0), "not charged yet")
	_fill(s)
	assert_false(bot.tick(s, false, 0.0, 2.0), "not sweeping: it keeps the charge")
	assert_false(bot.tick(s, true, AutoplaySurge.CHEST_ROOM + 0.1, 3.0), "the chest is nearly full: it empties it first")
	assert_true(s.can_release())
	assert_true(bot.tick(s, true, 0.2, 4.0), "sweeping dirty ground with room in the chest: release")
	assert_true(s.active())
	assert_false(bot.tick(s, true, 0.2, 5.0))
	var report: Dictionary = {}
	bot.write(report)
	assert_eq(report["surges"], 1)
	assert_eq(report["surge_times_s"], [4.0])


## [lead Nov 11] The Surge opens with the first robot, so the opening keeps its fitted pace:
## before it no hand work charges the core and nothing can be released; after it, it charges.
func test_the_surge_opens_with_the_first_robot() -> void:
	var cfg: Dictionary = _cfg(FIRST)
	assert_eq(int((cfg.get("unlock", {}) as Dictionary).get("robots_built", 0)), 1, "the table opens it with the first robot")
	assert_false(SurgeRules.unlocked(cfg, {"robots_built": 0}), "shut before the first robot")
	assert_true(SurgeRules.unlocked(cfg, {"robots_built": 1}), "open once one is built")
	assert_true(SurgeRules.unlocked({"enabled": true}, {}), "a planet with no unlock rule has it from the start")


## Regression (lead Nov 11): a game started before the first robot must start charging once the
## robot is built, without a reload (setup listened only if the Surge was already open).
func test_a_surge_set_up_before_the_first_robot_charges_after_it() -> void:
	GameState.stats["robots_built"] = 0
	var s := Surge.new()
	_nodes.append(s)
	add_child(s)
	s.setup(Planets.by_id(FIRST), null)
	assert_false(s.enabled(), "shut before the first robot")
	EventBus.pollution_cleared.emit("litter", 50.0, true)
	assert_eq(s.charge(), 0.0, "no charge while shut")
	GameState.stats["robots_built"] = 1
	assert_true(s.enabled(), "open after the first robot")
	EventBus.pollution_cleared.emit("litter", 50.0, true)
	assert_gt(s.charge(), 0.0, "Lumi's work charges it now")
