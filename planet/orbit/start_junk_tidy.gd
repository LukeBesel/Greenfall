class_name StartJunkTidy
extends Node
## [v8hex] Owner item (Nov 13): "This starter hex i cleared but it says 94% and i dont get
## anything... fix the ones partially in the starting zone". Measured with --hex-audit: the start
## area's hexes held pieces nobody could see or take: under the First Seed greenhouse's planting
## beds and walled in by its posts (5-9% of the hex it stands on, on every seed tried), and a
## few inside or under street furniture (benches, bins, parked wrecks: up to 3.5%). So:
##   - the greenhouse's ground is kept clear of junk (YardKeepOut.add_clear_box) once it stands,
##   - every start-area cell (SphereField.small_only) moves its pieces off any collider they lie
##     under or inside (SphereField.relocate_blocked with HexLeftovers.covered), when its pieces
##     are laid and again once the yard has stood up, one cell a frame,
##   - the leftover rule (SphereField.leftover_check = HexLeftovers.findable) clears a hex 80%
##     cleaned whose live pieces are all hidden or out of reach, anywhere near Lumi,
##   - a save that already has a start-area hex stuck like this heals once on load
##     (data/start_area.json "heal_from"): it counts as clean and pays its bonus.

var so: SliceOrbit
var hl: HexLeftovers
var _q: Array[int] = []
var _queued: Dictionary = {}
var _ready_to_run: bool = false
var tidied: int = 0  # pieces moved off colliders (for checks)
var worst_ms: float = 0.0  # the longest tidy_cell (one cell's collider tests)


static func attach(p_so: SliceOrbit) -> StartJunkTidy:
	var t := StartJunkTidy.new()
	t.name = "StartJunkTidy"
	t.so = p_so
	p_so.add_child(t)
	return t


## Call once the yard (and the greenhouse) stand in the physics space.
func start(fs: FirstSeed) -> void:
	var g: OrbitPlanet = so.globe
	var f: SphereField = g.field
	hl = HexLeftovers.for_world(so.w)
	if hl == null:
		return
	f.leftover_from = StartArea.leftover_from()
	f.leftover_check = hl.findable
	var ko: YardKeepOut = g.yard_keep_out()
	if ko and fs and is_instance_valid(fs):
		var gx: Transform3D = fs.global_transform * Transform3D(Basis.IDENTITY, FirstSeed.GREENHOUSE_POS)
		var half: Vector2 = StartArea.greenhouse_half()
		ko.add_clear_box(Transform3D(gx.basis.orthonormalized(), gx.origin), half)
	f.after_lay = func(c: int) -> void:
		if f.small_only.has(c):
			_queue(c)
	for c: int in f.small_only:
		if f.materialized[c] == 1:
			_queue(c)
	_ready_to_run = true
	if DevHooks.has("hex-audit"):
		print("[hexheal] tidy started: %d cells queued" % _q.size())


func _queue(c: int) -> void:
	if not _queued.has(c):
		_queued[c] = true
		_q.append(c)


func _process(_dt: float) -> void:
	if not _ready_to_run:
		return
	var t0: int = Time.get_ticks_usec()
	var did: bool = not _q.is_empty()
	while not _q.is_empty() and Time.get_ticks_usec() - t0 < 2000:
		var c: int = _q.pop_front()
		_queued.erase(c)
		var t1: int = Time.get_ticks_usec()
		tidy_cell(c)
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - t1) / 1000.0)
	if did:
		Hitch.mark("start junk tidy", t0 if Hitch.on else 0)
	if _q.is_empty() and not _healed:
		_healed = true
		heal()
		if DevHooks.has("hex-audit"):
			print("[hexaudit] tidy: %d pieces moved off colliders, longest cell %.1f ms" % [tidied, worst_ms])


## Moves a start-area cell's pieces off the colliders and the keep-out. Returns pieces touched.
func tidy_cell(c: int) -> int:
	var g: OrbitPlanet = so.globe
	var f: SphereField = g.field
	if f.materialized[c] == 0 or f.hex_clean[c] == 1:
		return 0
	var r: Array = f.relocate_blocked(c, hl.covered)
	var n: int = (r[0] as PackedInt32Array).size() + (r[1] as PackedInt32Array).size()
	if n == 0:
		return 0
	for pid: int in r[0]:
		g.junk_view.move_piece(pid, f.piece_pos[pid])
	for pid: int in r[1]:
		g.junk_view.hide_piece(pid)
	tidied += n
	if f.check_clean(c):  # dropping the last hidden pieces can finish a hex
		g.write_cell(c)
		g.junk_view.refresh_hex(c, true)
		so.on_hex_clean(c, true)
	else:
		g.write_cell(c)
		g.junk_view.refresh_hex(c)
	return n


var _healed: bool = false


## Whether the first tidy pass and the heal are done (the hex audit waits for it).
func done() -> bool:
	return _ready_to_run and _healed


## A loaded save's start-area hexes the old rules left stuck (cleared to heal_from or more, but not
## clean): clean now, bonus paid. Once per save (flag "v8hex_heal").
func heal() -> int:
	if GameState.flags.get("v8hex_heal", false):
		return 0
	GameState.flags["v8hex_heal"] = true
	var g: OrbitPlanet = so.globe
	var f: SphereField = g.field
	var n: int = 0
	var bar: float = StartArea.heal_from()
	for c: int in f.small_only:
		if f.hex_hub[c] == 1 or f.hex_water[c] == 1 or f.hex_clean[c] == 1 or not g.cells.is_dirty(c):
			continue
		if 1.0 - g.cells.junk[c] < bar:
			continue
		if f.force_clean(c):
			g.write_cell(c)
			g.junk_view.refresh_hex(c, true)
			so.on_hex_clean(c, true)
			n += 1
	if n > 0:
		print("[hexheal] %d start-area hex(es) that were stuck short of clean now count as clean" % n)
	return n
