class_name HexLevels
extends Node
## A level for every non-hub land hex: 0 Junk -> 1 Clean -> 2 Planted -> 3 Growing ->
## 4 Sustained (kept watered while growing) -> 5 Thriving (in bloom, sustained, wildlife).
## Levels never drop. Each level-up pays a reward, adds a small permanent bonus (faster growth,
## more seeds) and gets a little moment. Thresholds and rewards: data/hex_levels.json.
## Sustain is measured from the garden: every sample_s the share of planted slots with water > 0
## goes into a per-hex ring covering sustain_window_s; Sustained needs its mean >= sustain_ratio.

const LEVEL_COLORS: Array[Color] = [Color(0.6, 0.55, 0.5), Color(0.9, 0.9, 0.87), Color(0.78, 0.66, 0.45),
	Color(0.62, 0.86, 0.66), Color(0.45, 0.8, 1.0), Color(1.0, 0.78, 0.3)]
const MAX_LEVEL: int = 5

var world: Node
var cfg: Dictionary
var levels: Dictionary = {}  # hex id -> int level (tracked land hexes only)
var _window: int = 180
var _ring: Dictionary = {}  # hex id -> PackedByteArray of samples (0..100 % watered)
var _ring_i: Dictionary = {}  # hex id -> next write index
var _ring_n: Dictionary = {}  # hex id -> samples filled
var _ring_sum: Dictionary = {}  # hex id -> sum of samples in the ring
var _bonus: Dictionary = {}
var _tick: float = 0.0
var _data_acc: float = 0.0  # [beat]
var _stipend_acc: float = 0.0
## False in unit tests / catch-up: level-ups pay out and count but skip vfx/audio/toasts.
var celebrate: bool = true


## [orbB] Sparse (the globe): only cells that were cleaned are tracked (a 164k-cell globe would
## be sampled every second otherwise); untracked land cells read level 0. Saved in GameState.orbit.
var sparse: bool = false


func setup() -> void:
	cfg = Economy.read_json("res://data/hex_levels.json")
	_window = maxi(1, int(round(float(cfg.get("sustain_window_s", 180)) / float(cfg.get("sample_s", 1.0)))))
	var field: HexField = world.field
	if sparse:  # [orbB]
		EventBus.hex_cleaned.connect(_on_cleaned_sparse)
	else:
		for id: int in field.hex_count():
			if field.hex_hub[id] == 0 and not field.is_water(id):
				levels[id] = 0
	_load()
	_recalc_bonus()
	add_to_group("persist")


func level_of(hid: int) -> int:
	if sparse and not levels.has(hid):  # [orbB]
		var f: HexField = world.field
		return 0 if hid >= 0 and hid < f.hex_count() and f.hex_hub[hid] == 0 and not f.is_water(hid) else -1
	return int(levels.get(hid, -1))


func _on_cleaned_sparse(hid: int, _c: Vector3, _b: BigNum) -> void:
	track(hid)


## [orbB] Sparse mode: start tracking a cell (once it is clean).
func track(hid: int) -> void:
	if is_instance_valid(world) and not levels.has(hid) and world.field.hex_hub[hid] == 0 and not world.field.is_water(hid):
		levels[hid] = 0


func level_def(l: int) -> Dictionary:
	var arr: Array = cfg.get("levels", [])
	return arr[l] if l >= 0 and l < arr.size() else {}


func level_name(l: int) -> String:
	return tr(str(level_def(l).get("name", "Lv %d" % l)))


func count_at_least(l: int) -> int:
	var n: int = 0
	for id: int in levels:
		if int(levels[id]) >= l:
			n += 1
	return n


## Summed permanent bonus over all hexes (e.g. "grow_pct", "seed_pct"), capped by data.
func bonus(key: String) -> float:
	return float(_bonus.get(key, 0.0))


## Share of the sustain window filled with well-watered samples, 0..1 (for HUD hints).
func sustain_progress(hid: int) -> float:
	if not _ring_n.has(hid):
		return 0.0
	return clampf(float(_ring_n[hid]) / _window, 0.0, 1.0)


## Mean watered % over the samples in the ring so far (0..1).
func watered_ratio(hid: int) -> float:
	var n: int = int(_ring_n.get(hid, 0))
	return float(_ring_sum.get(hid, 0)) / (100.0 * n) if n > 0 else 0.0


func sustained_now(hid: int) -> bool:
	return int(_ring_n.get(hid, 0)) >= _window and watered_ratio(hid) >= float(cfg.get("sustain_ratio", 0.9))


## Short HUD readout for the hex Patch is looking at.
func describe(hid: int) -> String:
	var l: int = level_of(hid)
	if l < 0:
		return ""
	var s: String = tr("HEX  LV %d  %s") % [l, level_name(l).to_upper()]
	if l == 3 or (l == 4 and not sustained_now(hid)):
		if _ring_n.has(hid) and watered_ratio(hid) >= float(cfg.get("sustain_ratio", 0.9)):
			s += tr("      SUSTAIN  %d%%") % int(sustain_progress(hid) * 100.0)
		elif _ring_n.has(hid):
			s += tr("      THIRSTY")
	if l < MAX_LEVEL:
		s += tr("      next: %s") % tr(str(level_def(l).get("hint", "")))
	return s


# --- Evaluation ------------------------------------------------------------------------

func _process(delta: float) -> void:
	step(delta)


## Advance the sampler by dt seconds; evaluates levels once per sample.
func step(dt: float) -> void:
	_tick += dt
	var ss: float = float(cfg.get("sample_s", 1.0))
	while _tick >= ss:
		_tick -= ss
		_sample_all()


func _sample_all() -> void:
	_pay_stipend(float(cfg.get("sample_s", 1.0)))
	for id: int in levels:
		var m: Vector3i = _measure(id)
		if m.x > 0:
			_push(id, int(round(100.0 * float(m.y) / float(m.x))))
		elif _ring_n.has(id):
			_clear_ring(id)
		var target: int = _target_level(id, m)
		if target > int(levels[id]):
			_level_up(id, int(levels[id]), target)


## Garden stipend: Sustained and Thriving hexes pay a small steady trickle of cubes (bonus key
## "cubes_per_min", summed over hexes and capped like the other bonuses). It keeps a district whose
## junk is all gone moving toward the next base level instead of stalling.
func _pay_stipend(dt: float) -> void:
	# [beat] Thriving hexes also log wildlife notes, so research never stalls for good in a district
	# whose junk is gone. [money] They pay a small cube trickle (research costs cubes now).
	var data_min: float = bonus("wildlife_cubes_per_min")
	if data_min > 0.0:
		_data_acc += data_min * dt / 60.0
		if _data_acc >= 1.0:
			var wd: float = floorf(_data_acc)
			_data_acc -= wd
			GameState.add_currency("cubes", BigNum.from_float(wd))
			GameState.inc_stat("wildlife_cubes", wd)
	var per_min: float = bonus("cubes_per_min")
	if per_min <= 0.0:
		return
	_stipend_acc += per_min * dt / 60.0
	if _stipend_acc >= 1.0:
		var whole: float = floorf(_stipend_acc)
		_stipend_acc -= whole
		GameState.add_currency("cubes", BigNum.from_float(whole))
		GameState.inc_stat("garden_stipend", whole)


## (planted, watered, bloomed) slot counts of a hex.
func _measure(hid: int) -> Vector3i:
	var g: Garden = world.get("garden") as Garden
	if g == null or not g.hex_slots.has(hid):
		return Vector3i.ZERO
	var planted: int = 0
	var watered: int = 0
	var bloomed: int = 0
	for s: int in g.hex_slots[hid]:
		if g.slot_species[s] < 0:
			continue
		planted += 1
		if g.slot_water[s] > 0.0:
			watered += 1
		if g.slot_stage[s] >= 4:
			bloomed += 1
	return Vector3i(planted, watered, bloomed)


## The level a hex qualifies for right now (ignores the never-drop rule).
func _target_level(hid: int, m: Vector3i) -> int:
	if not world.field.is_clean(hid):
		return 0
	var g: Garden = world.get("garden") as Garden
	if g == null or not g.hex_slots.has(hid):
		return 1
	var total: int = (g.hex_slots[hid] as PackedInt32Array).size()
	if total == 0 or m.x < maxi(1, ceili(float(cfg.get("planted_min_frac", 0.25)) * total)):
		return 1
	var life: float = float(g.hex_life.get(hid, 0.0))
	if life < float(cfg.get("growing_life", 0.35)):
		return 2
	if not sustained_now(hid):
		return 3
	if m.z < m.x or life < float(cfg.get("thriving_life", 0.8)):
		return 4
	return 5


func _push(hid: int, v: int) -> void:
	if not _ring.has(hid):
		var b := PackedByteArray()
		b.resize(_window)
		b.fill(0)
		_ring[hid] = b
		_ring_i[hid] = 0
		_ring_n[hid] = 0
		_ring_sum[hid] = 0
	var ring: PackedByteArray = _ring[hid]
	var i: int = _ring_i[hid]
	if int(_ring_n[hid]) >= _window:
		_ring_sum[hid] = int(_ring_sum[hid]) - ring[i]
	else:
		_ring_n[hid] = int(_ring_n[hid]) + 1
	ring[i] = v
	_ring[hid] = ring
	_ring_sum[hid] = int(_ring_sum[hid]) + v
	_ring_i[hid] = (i + 1) % _window


func _clear_ring(hid: int) -> void:
	_ring.erase(hid)
	_ring_i.erase(hid)
	_ring_n.erase(hid)
	_ring_sum.erase(hid)


func _level_up(hid: int, from: int, to: int) -> void:
	levels[hid] = to
	var reward: Dictionary = {}
	for l: int in range(from + 1, to + 1):
		var r: Dictionary = level_def(l).get("reward", {})
		for k: String in r:
			reward[k] = float(reward.get(k, 0.0)) + float(r[k])
		GameState.inc_stat("hex_lvl_%d" % l)
	for k: String in reward:
		if float(reward[k]) > 0.0:
			GameState.add_currency(k, BigNum.from_float(float(reward[k])))
	GameState.inc_stat("hex_level_ups", to - from)
	_recalc_bonus()
	if celebrate:
		_celebrate(hid, to, reward)
	EventBus.hex_level_changed.emit(hid, to)


static func reward_text(reward: Dictionary) -> String:
	var parts: Array[String] = []
	for k: String in Currencies.IDS:  # [money]
		if float(reward.get(k, 0.0)) > 0.0:
			parts.append(L10nFmt.amount(k, float(reward[k]), true))  # [i18n2]
	return "  ".join(parts)


func _celebrate(hid: int, to: int, reward: Dictionary) -> void:
	var c: Vector3 = world.field.hex_center(hid)
	var col: Color = LEVEL_COLORS[clampi(to, 0, MAX_LEVEL)]
	var nm: String = level_name(to)
	var up: Vector3 = world.field.call("up_at", c) if world.field.has_method("up_at") else Vector3.UP  # [orbB] radial on the globe
	Vfx.burst("big_sparkle" if to >= 4 else "sparkle", c + up * 0.5, col, 1.0 if to >= 4 else 2.0)
	Vfx.ring(c, world.field.hex_size * 1.05, Color(col.r, col.g, col.b, 0.85), 0.9)
	Vfx.float_text(c + up * 2.0, tr("HEX LV %d  %s") % [to, nm.to_upper()], col, 1.3 if to < 4 else 1.7, 2.2)
	Audio.play("sparkle" if to < 4 else "chime", 0.9 + 0.08 * to, -6.0 if to < 4 else -3.0)
	if to == MAX_LEVEL:
		Audio.play("bird", 1.1, -10.0, 0.0)
		var wl: Node = world.get("wildlife")
		if wl and wl.has_method("_on_restored"):
			wl.call("_on_restored", hid)  # extra butterflies and a bird for a thriving hex
	EventBus.toast.emit(tr("Hex Lv %d  %s.   %s") % [to, nm, reward_text(reward)], "reward")  # [v4calm] item 49: hex level-ups are reward chatter (the hex's own FX shows it)


func _recalc_bonus() -> void:
	_bonus = {}
	for id: int in levels:
		for l: int in range(1, int(levels[id]) + 1):
			var b: Dictionary = level_def(l).get("bonus", {})
			for k: String in b:
				_bonus[k] = float(_bonus.get(k, 0.0)) + float(b[k])
	var caps: Dictionary = cfg.get("bonus_caps", {})
	for k: String in _bonus:
		if caps.has(k):
			_bonus[k] = minf(float(_bonus[k]), float(caps[k]))


# --- Persistence -----------------------------------------------------------------------

func persist_save() -> void:
	if sparse:  # [orbB] the globe saves it in GameState.orbit (scenes/slice_orbit.gd)
		return
	GameState.world["hex_levels"] = persist()


func persist() -> Dictionary:
	var raw := PackedByteArray()
	raw.resize(world.field.hex_count())
	raw.fill(0)
	for id: int in levels:
		raw[id] = int(levels[id])
	var rings: Dictionary = {}
	for id: int in _ring:
		rings[str(id)] = [Marshalls.raw_to_base64(_ring[id]), int(_ring_i[id]), int(_ring_n[id])]
	return {"levels": Marshalls.raw_to_base64(raw), "rings": rings, "window": _window}


func _load() -> void:
	var d: Dictionary = GameState.world.get("hex_levels", {}) if not sparse else GameState.orbit.get("hex_levels", {})  # [orbB]
	var raw: PackedByteArray = Marshalls.base64_to_raw(str(d.get("levels", ""))) if d.has("levels") else PackedByteArray()
	if sparse and raw.size() == world.field.hex_count():  # [orbB] cleaned cells come back tracked
		for id: int in raw.size():
			if raw[id] > 0:
				track(id)
	if raw.size() != world.field.hex_count():
		# Old save (or fresh field): catch up silently to what each hex already shows, no rewards.
		for id: int in levels:
			levels[id] = mini(_target_level(id, _measure(id)), 3)
		return
	for id: int in levels:
		levels[id] = clampi(int(raw[id]), 0, MAX_LEVEL)
	if int(d.get("window", 0)) != _window:
		return
	var rings: Dictionary = d.get("rings", {})
	for k: Variant in rings:
		var id: int = int(str(k))
		var e: Array = rings[k]
		var b: PackedByteArray = Marshalls.base64_to_raw(str(e[0]))
		if b.size() != _window or not levels.has(id):
			continue
		_ring[id] = b
		_ring_i[id] = int(e[1]) % _window
		_ring_n[id] = clampi(int(e[2]), 0, _window)
		var sum: int = 0
		for v: int in b:
			sum += v
		_ring_sum[id] = sum
