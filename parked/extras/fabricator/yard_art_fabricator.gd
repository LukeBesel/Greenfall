# Parked with the Bot Fabricator (M1-08). These were static functions of YardArt (systems/camp/yard_art.gd):
# paste them back into that class to restore the Fabricator's model (fabricator_model.gd).

# --- Bot Fabricator (systems/camp/fabricator_model.gd) -------------------------------------------------

static func fabricator_shell() -> Kit:
	var k := Kit.new()
	k.box(Vector3(4.6, 0.22, 3.4), Vector3(0, 0.11, -0.3), Color.WHITE, Vector3.ZERO, 0.05, "concrete")
	k.hazard(Vector3(4.62, 0.06, 3.42), Vector3(0, 0.2, -0.3))
	k.box(Vector3(2.4, 0.04, 2.2), Vector3(0, 0.24, -0.4), GUNMETAL, Vector3.ZERO, 0.015)  # bay floor
	for s: float in [-1.0, 1.0]:  # bay walls
		k.box(Vector3(0.3, 2.5, 2.4), Vector3(s * 1.45, 1.47, -0.4), CREAM, Vector3.ZERO, 0.06)
		k.panel(1.9, 1.9, Vector3(s * 1.61, 1.45, -0.4), CREAM.darkened(0.05), Vector3(0, s * 90.0, 0), Color(-1, 0, 0), 0.04)
		k.hazard(Vector3(0.32, 0.3, 0.06), Vector3(s * 1.45, 0.4, 0.82))
		k.box(Vector3(0.36, 0.1, 2.5), Vector3(s * 1.45, 2.75, -0.4), TEAL, Vector3.ZERO, 0.03)
	k.box(Vector3(3.2, 2.5, 0.2), Vector3(0, 1.47, -1.6), TEAL_D, Vector3.ZERO, 0.05)  # back wall
	for x: float in [-0.8, 0.0, 0.8]:
		k.box(Vector3(0.08, 2.3, 0.06), Vector3(x, 1.45, -1.48), TEAL, Vector3.ZERO, 0.02)
	k.decal("logo", Vector2(0.7, 0.7), Vector3(-0.4, 1.9, -1.45))
	k.vent(0.6, 0.4, Vector3(0.45, 0.9, -1.48), TEAL, Vector3.ZERO, 4)
	# Gantry over the bay: two rails and a trolley with a hoist.
	for z: float in [-1.3, 0.6]:
		k.box(Vector3(3.2, 0.16, 0.16), Vector3(0, 2.86, z), YELLOW, Vector3.ZERO, 0.03)
	k.box(Vector3(0.5, 0.18, 2.1), Vector3(-0.3, 2.86, -0.35), GUNMETAL, Vector3.ZERO, 0.03)
	k.box(Vector3(0.3, 0.2, 0.3), Vector3(-0.3, 2.7, -0.4), ORANGE, Vector3.ZERO, 0.04)
	k.pipe(Vector3(-0.3, 2.6, -0.4), Vector3(-0.3, 2.0, -0.4), 0.015, STEEL, false)
	k.box(Vector3(0.24, 0.06, 0.24), Vector3(-0.3, 1.97, -0.4), GUNMETAL, Vector3.ZERO, 0.015)
	# Status beacon on top.
	k.cyl(0.12, 0.1, Vector3(1.45, 2.85, 0.7), DARK, Vector3.ZERO, 0.02, 12)
	k.glow_cyl(0.09, 0.12, Vector3(1.45, 2.95, 0.7), MINT, Vector3.ZERO, 12)
	# Out-conveyor from the bay mouth to the front.
	k.push(Transform3D(Basis(), Vector3(0, 0, 0.9)))
	for x: float in [-0.5, 0.5]:
		k.box(Vector3(0.1, 0.18, 2.2), Vector3(x, 0.42, 1.0), YELLOW, Vector3.ZERO, 0.03)
		for z: float in [0.2, 1.8]:
			k.box(Vector3(0.08, 0.34, 0.08), Vector3(x, 0.17, z), GUNMETAL)
	k.box(Vector3(0.9, 0.04, 2.2), Vector3(0, 0.48, 1.0), RUBBER, Vector3.ZERO, 0.01)
	for i: int in 8:
		k.cyl(0.05, 0.92, Vector3(0, 0.44, 0.05 + i * 0.27), STEEL, Vector3(0, 0, 90), 0.01, 10)
	k.decal("chevrons", Vector2(0.7, 0.24), Vector3(0, 0.505, 1.6), Vector3(-90, 0, 0))
	k.pop()
	# Console on the right, parts bins on the left, pipes on the back.
	k.box(Vector3(0.6, 1.0, 0.5), Vector3(1.95, 0.72, 0.5), CREAM, Vector3.ZERO, 0.04)
	k.box(Vector3(0.62, 0.3, 0.52), Vector3(1.95, 1.3, 0.42), TEAL, Vector3(-25, 0, 0), 0.03)
	k.glow_box(Vector3(0.44, 0.2, 0.02), Vector3(1.95, 1.33, 0.67), CYAN, Vector3(-25, 0, 0))
	for i: int in 3:
		k.glow_box(Vector3(0.04, 0.04, 0.02), Vector3(1.8 + i * 0.12, 0.95, 0.755), [MINT, AMBER, MINT][i])
	for i: int in 3:
		for j: int in 2:
			k.box(Vector3(0.36, 0.22, 0.4), Vector3(-1.95, 0.36 + j * 0.24, 0.6 - i * 0.42), [YELLOW, BLUE, RED][(i + j) % 3], Vector3.ZERO, 0.03)
	k.pipe(Vector3(-1.3, 0.25, -1.75), Vector3(-1.3, 2.4, -1.75), 0.07, GUNMETAL, true)
	k.pipe(Vector3(-1.3, 2.4, -1.75), Vector3(1.3, 2.4, -1.75), 0.07, GUNMETAL, true)
	k.cable([Vector3(1.95, 0.3, 0.25), Vector3(1.7, 0.25, -0.2), Vector3(1.3, 0.26, -0.6)], 0.025)
	return k


## The bay pad, its ring and light: lit only while a bot is being built.
static func fabricator_bay() -> Kit:
	var k := Kit.new()
	k.cyl(0.7, 0.06, Vector3(-0.3, 0.29, -0.4), GUNMETAL, Vector3.ZERO, 0.02, 24)
	for i: int in 20:  # a thin ring of lights round the pad (not a lit disc)
		var a: float = TAU * i / 20.0
		k.glow_box(Vector3(0.12, 0.02, 0.035), Vector3(-0.3 + cos(a) * 0.62, 0.325, -0.4 + sin(a) * 0.62), CYAN, Vector3(0, -rad_to_deg(a) + 90.0, 0))
	for s: float in [-1.0, 1.0]:
		k.glow_box(Vector3(0.03, 1.8, 0.03), Vector3(s * 1.28, 1.4, 0.75), CYAN)
	k.light(Vector3(-0.3, 1.6, -0.2), CYAN, 0.9, 3.5)
	return k


## The fabricator arm's parts (each sits on its own node): "base" turret, "upper" arm, "fore" arm.
static func arm_part(part: String) -> Kit:
	var k := Kit.new()
	match part:
		"base":
			k.cyl(0.28, 0.12, Vector3(0, 0.06, 0), GUNMETAL, Vector3.ZERO, 0.03, 16)
			k.cyl(0.2, 0.3, Vector3(0, 0.27, 0), ORANGE, Vector3.ZERO, 0.04, 16)
			k.cyl(0.13, 0.26, Vector3(0, 0.42, 0), DARK, Vector3(90, 0, 0), 0.03, 14)
		"upper":
			k.box(Vector3(0.16, 0.9, 0.16), Vector3(0, 0.45, 0), ORANGE, Vector3.ZERO, 0.04)
			k.pipe(Vector3(0.1, 0.1, 0.06), Vector3(0.1, 0.8, 0.06), 0.02, RUBBER, false)
			k.cyl(0.11, 0.22, Vector3(0, 0.9, 0), DARK, Vector3(90, 0, 0), 0.03, 14)
		_:
			k.box(Vector3(0.13, 0.7, 0.13), Vector3(0, 0.35, 0), ORANGE, Vector3.ZERO, 0.035)
			k.cyl(0.08, 0.1, Vector3(0, 0.74, 0), GUNMETAL, Vector3.ZERO, 0.02, 12)
			for s: float in [-1.0, 1.0]:
				k.box(Vector3(0.03, 0.16, 0.06), Vector3(s * 0.06, 0.86, 0), STEEL, Vector3(0, 0, s * -12.0), 0.01)
			k.glow_box(Vector3(0.03, 0.03, 0.02), Vector3(0, 0.6, 0.07), WARM)
	return k

