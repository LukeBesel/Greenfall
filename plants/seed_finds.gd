class_name SeedFinds
extends Node
## [first] The early seed trickle: once the Settler seed tin is found, Lumi now and then turns up a
## dry old seed in the junk he scoops (organic junk likelier). Rare and rate-limited, so planting
## stays a slow side track for the first hour while cleaning drives progress.
## Data: data/plants.json "seed_finds" {chance, organic_mult, cooldown_s}.

var world: Node
var _cooldown: float = 0.0
var _cfg: Dictionary = {}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/plants.json"))
	_cfg = (d as Dictionary).get("seed_finds", {}) if d is Dictionary else {}
	EventBus.junk_scooped.connect(_on_scooped)


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


## Chance for one scooped piece of this type (0 while locked or cooling down).
func chance_for(type_id: String) -> float:
	if not GameState.flags.get("seeds_unlocked", false) or _cooldown > 0.0:
		return 0.0
	var c: float = float(_cfg.get("chance", 0.006))
	if type_id == "paper":
		c *= float(_cfg.get("organic_mult", 2.5))
	return c


func _on_scooped(type_id: String, pos: Vector3) -> void:
	if rng.randf() >= chance_for(type_id):
		return
	_cooldown = float(_cfg.get("cooldown_s", 60.0))
	GameState.add_currency("seeds", BigNum.from_float(1.0))
	GameState.inc_stat("seeds_found_rubble")
	Vfx.burst("sparkle", pos + OrbitUp.up(pos) * 1.0, Color(0.7, 1.0, 0.55), 0.5)  # [orbB] local up (Vector3.UP flat)
	Vfx.float_text(pos + OrbitUp.up(pos) * 1.7, tr("+1 SEED"), Color(0.7, 1.0, 0.6), 0.5, 0.7)
	Audio.play("chime", 1.6, -12.0)
	if not GameState.flags.get("seed_find_hint", false):
		GameState.flags["seed_find_hint"] = true
		EventBus.toast.emit(tr("A dry old seed, still sealed in its husk. Junk hides a few of these."), "hint")
