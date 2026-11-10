# Parked with the prestige mode (M1-08): the endless Seed Ark loop of Bloom (systems/bloom.gd).
# These were static functions of that class, plus two fragments: the Seed Ark half of globe_line()
# and the wave check at the end of Bloom._process(). Its numbers are the "seed_ark" block of the
# planet's postgame table; waves count in stats.ark_waves and the state lives in flags.seed_ark.

# --- Seed Ark (endless, cozy) ---------------------------------------------------------

static func ark_unlocked() -> bool:
	return is_done(str(cfg().get("seed_ark", {}).get("unlock", "verdance_bloom")))


static func ark_state() -> Dictionary:
	var v: Variant = GameState.flags.get("seed_ark")
	if not (v is Dictionary):
		v = {"wave": 0, "start": float(GameState.stats.get("plants_bloomed", 0.0))}
		GameState.flags["seed_ark"] = v
	(v as Dictionary)["wave"] = int((v as Dictionary).get("wave", 0))  # [beat] JSON brings it back as a float
	return v


static func ark_target(wave: int) -> int:
	var a: Dictionary = cfg().get("seed_ark", {})
	return int(round(float(a.get("base", 120)) * pow(float(a.get("growth", 1.5)), wave)))


static func ark_progress() -> int:
	return maxi(0, int(float(GameState.stats.get("plants_bloomed", 0.0)) - float(ark_state().get("start", 0.0))))


## Completes as many waves as the blooms cover. Returns how many finished (rewards paid).
static func ark_step() -> int:
	if not ark_unlocked():
		return 0
	var st: Dictionary = ark_state()
	var n: int = 0
	while ark_progress() >= ark_target(int(st["wave"])) and n < 20:
		var w: int = int(st["wave"])
		st["start"] = float(st["start"]) + ark_target(w)
		st["wave"] = w + 1
		var a: Dictionary = cfg().get("seed_ark", {})
		_pay(a.get("reward", {}), pow(float(a.get("reward_growth", 1.35)), w))
		GameState.inc_stat("ark_waves")
		n += 1
	return n

# --- globe_line(): shown instead of the milestone line once ark_unlocked() ---
#	var w: int = int(ark_state()["wave"])
#	return TranslationServer.translate("Seed Ark wave %d  ·  %d / %d blooms planet-wide") % [w + 1, mini(ark_progress(), ark_target(w)), ark_target(w)]

# --- Bloom._process(), after the milestone check ---
#	var waves: int = ark_step()
#	if waves > 0:
#		var w: int = int(ark_state()["wave"])
#		EventBus.toast.emit(tr("Seed Ark wave %d planted across Verdance. The Cradle drops a gift. Next wave: %d blooms.") % [w, ark_target(w)], "story")
#		Audio.play("fanfare", 1.1, -8.0)
#		if world and world.get("wren") != null:
#			world.wren.say("ark_wave", 1.0, true)
