class_name SphereRobotKinds
extends RefCounted
## [orbC] How each robot type moves on a round planet. Every type is a SphereBot (kinematic, on
## SphereSurface.ground, steering through SphereSteer: seek, separation, keep-right avoidance,
## turn, arrive); the profile sets how it carves: speed from the type's stat (data/robots.json,
## research multipliers included, so the flat game's numbers hold), turn rate, footprint, how much
## it leans onto the terrain (wheeled bodies follow the slope, hover bodies stay upright) and how
## far its hover rides.

const PROFILES: Dictionary = {
	# turn rad/s, body radius m, tilt (0 radial .. 1 on the terrain normal), hover m
	"scoopie": {"turn": 3.6, "body": 0.35, "tilt": 0.8, "hover": 0.0},   # little tracked digger
	"haulbug": {"turn": 2.4, "body": 0.45, "tilt": 0.9, "hover": 0.0},   # wheeled carrier: wide turns
	"seedling": {"turn": 4.2, "body": 0.35, "tilt": 0.6, "hover": 0.0},  # nimble walker
	"drip": {"turn": 3.4, "body": 0.35, "tilt": 0.5, "hover": 0.08},     # hover tank
	"skimmer": {"turn": 2.0, "body": 0.45, "tilt": 0.2, "hover": 0.12},  # floats, drifts round corners
	"multibot": {"turn": 3.0, "body": 0.45, "tilt": 0.7, "hover": 0.0},
	"scrounger": {"turn": 3.8, "body": 0.35, "tilt": 0.8, "hover": 0.0},  # low tracked digger: quick on its feet
}


static func profile(type_id: String) -> Dictionary:
	return PROFILES.get(type_id, PROFILES["scoopie"])


static func role_of(type_id: String) -> String:
	var r: String = str(Economy.robots.get(type_id, {}).get("role", "clean"))
	return "clean" if r == "any" else r


## Ground speed in m/s: the flat game's speed stat for the type and tier.
static func speed(type_id: String, tier: int) -> float:
	var v: float = Economy.robot_stat(type_id, "speed", tier)
	return v if v > 0.0 else 1.6


## Sets a SphereBot up to move like `type_id`.
static func apply(bot: SphereBot, type_id: String, tier: int) -> void:
	var p: Dictionary = profile(type_id)
	bot.speed = speed(type_id, tier)
	bot.turn_rate = float(p["turn"])
	bot.body_radius = float(p["body"])
	bot.tilt = float(p["tilt"])
	if bot.visual == null:
		bot.hover = float(p["hover"])
	bot.stop_m = 0.5
