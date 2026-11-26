# Art overhaul brief (owner, 26 Nov)

Target: Greenfall on round Verdance looks and feels good: more realistic, still super futuristic.
Real far-future hardware and places in real light. Cast stays robots in a ruined city that turns green.

Order: 1 light/tone/atmosphere (day, dusk, night; the night lake is nearly black) · 2 Lumi (look and
animation; keep visor face, concept-sheet proportions, Locker colours/eyes/head pieces; check the
opening film) · 3 buildings and start town from the play camera · 4 bases · 5 shuttle and its
launch/landing · 6 Scoopie and Haul Bug · 7 regrowth on cleaned land (no greenhouse/seed/water props).

Rules: every change rendered from the play camera and looked at, before/after of the same view
(screenshots/art/before, /after; boards in docs/art/). Mac build must not get slower (--load-report,
--hitch before and after). No change to colliders, walk areas, saves or gameplay; --city-walk and
--target-reach after geometry changes. No test skipped. Unit tests + affected walks before each
hand-off. Push only to claude/practical-meitner-eipd0h. Gameplay files: small edits only (another
session edits jump, title, map, far bases, planting).

Method: ToggleOps toggle-studio (04 materials/light, 08 atmosphere, 02 Blender in code) and
creature-mocap for rigs. Film methods for form, material and light; result brought into Godot at a
game budget. Blender headless -> .glb in art/models.

Budget: render here is software GL (opengl3, 960x540, Low, one at a time). Sub-agents: at most 2-3.
Cannot check here: real Mac, Metal/Forward+, 60 fps, High preset effects (SSAO, shadows splits).
Hand-off in stages; stage 1 = light and atmosphere.
