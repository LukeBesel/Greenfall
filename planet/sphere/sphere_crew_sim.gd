class_name SphereCrewSim
extends RefCounted
## [smove] Abstract simulation for bots far from Lumi: no nodes, no physics, no avoidance. A bot
## is its SphereBot.to_record() dictionary; advance() moves it along its waypoints at its speed
## with exact great-circle steps (any dt, so a whole crew can be stepped once a second or caught
## up after a rocket flight) and returns the metres travelled. Work on cells is the caller's
## (orbit_world's crews already tick junk per hub); this only keeps positions plausible so a bot
## streams back in where it should be.


static func advance(rec: Dictionary, dt: float, radius: float) -> float:
	var travelled: float = 0.0
	var budget: float = float(rec.get("speed", 3.2)) * dt
	var d: Vector3 = rec["dir"]
	var goal: Vector3 = rec.get("goal", Vector3.ZERO)
	var path: Array = rec.get("path", [])
	while budget > 1e-4 and goal != Vector3.ZERO:
		var left: float = d.angle_to(goal) * radius
		if left <= budget:
			rec["heading"] = SphereMath.heading_to(d, goal, rec.get("heading", Vector3.FORWARD)) if left > 1e-4 else rec.get("heading", Vector3.FORWARD)
			d = goal
			budget -= left
			travelled += left
			goal = path.pop_front() if not path.is_empty() else Vector3.ZERO
		else:
			var h: Vector3 = SphereMath.heading_to(d, goal, rec.get("heading", Vector3.FORWARD))
			var adv: Array = SphereMath.advance(d, h, budget / radius)
			d = adv[0]
			rec["heading"] = adv[1]
			travelled += budget
			budget = 0.0
	rec["dir"] = d
	rec["goal"] = goal
	rec["path"] = path
	if goal == Vector3.ZERO and rec.has("target") and int(rec["target"]) >= 0:
		rec["working"] = true
	return travelled


## Swap a live bot out (returns its record and frees the node) / back in (new node).
static func demote(bot: SphereBot) -> Dictionary:
	var r: Dictionary = bot.to_record()
	if bot.swarm:
		bot.swarm.remove(bot)
	bot.queue_free()
	return r


static func promote(rec: Dictionary, surface: SphereSurface, parent: Node, type_id: String = "") -> SphereBot:
	var b := SphereBot.new()
	parent.add_child(b)
	b.setup(surface, rec["dir"], rec.get("heading", Vector3.ZERO))
	b.from_record(rec)
	if type_id != "":
		b.add_visual(type_id)
	return b
