# Adjusting the game

Where to change things without reading the code. One section per area.

## Hubs: what each town is for (v6hubs)

Everything about a planet's hubs is in `data/planets.json`, under the planet's id.

| To change | Edit |
|---|---|
| How many hubs are the main path (the rest are extras) | `hub_defaults.main_path` |
| Hexes to clean at a far hub before its landmark can be woken | `hub_defaults.clean_hexes`, or that hub's own `chain` |
| Outposts to repair first | `hub_defaults.outposts`, or `{"do": "outposts", "count": N}` in a hub's `chain` |
| When a woken hub rises to level 3, 4, 5 (share of its region clean) | `hub_defaults.level_at` |
| A hub's name, the picker's "why go" line, its arrival line | `hubs[].name`, `desc`, `hint` |
| The order of the hubs | `hubs[].order` (1 = the start hub) |
| Which landmark stands there and what it is called | `hubs[].landmark.kind` and `.name` |
| The rocket piece a hub gives | `hubs[].piece` (sets flags `rocket_piece_<id>` and the count `rocket_pieces`) |
| The gift at the wake | `hubs[].gift`: `cubes`, `parts`, `seeds`, `research` (a node, free), `design` (a Lumi look), `flag` |
| A stat boost while a hub is woken (not used on Verdance) | `hubs[].boosts`: `[{stat, mult, text}]` |
| The price of a wake and the sell multiplier per hub | `data/hub.json` `far_hub` (v6pace) |
| How many hubs a rocket tier can keep | `data/rockets.json` tiers' `hubs` (v6pace) |

Landmark kinds: `water_tower`, `crane`, `ferris_wheel`, `radio_mast`, `smokestack`, `old_bus`,
`windpump`, `lighthouse`. The town's look (suburb, downtown...) is `VerdanceSite.KIND_BY_HUB`; the
`town` field is what the picker and the arrival title say, so keep the two in step.

Code: `planet/sites/hub_plan.gd` (data and saved state), `planet/sites/hub_purpose.gd` (arrival,
steps, the wake, the field bench, HUD lines). Check with
`godot --headless --path . -- --fresh --orbit --no-intro --rocket --orbit-hop=9 --hub-dev-chain=3 --hub-report=20 --quit-after=50`
(`--hub-wake=9,7` wakes hubs for free at start; `--hop-skip` skips the flight; `--hop-shots=PREFIX` saves pictures in a rendered run).
A new planet gets the same by adding `hub_defaults` and `hubs` to its entry.
