# Greenfall: Milestone Plan

Source of truth for the design: `docs/BUILD_PROMPT.md` (the owner's brief). This file is the working plan.
Status of each milestone lives in `docs/PROGRESS.md`; choices and assumptions in `docs/DECISIONS.md`.

## Principles
- Smallest playable slice first, then deepen. Verify with tests, screenshots, and the autoplay bot.
- Simulation (plain data, fixed 10 Hz tick) is separated from presentation (nodes that read state).
- Everything content-like lives in `data/` (JSON), loaded by autoloads.
- All gameplay input goes through named actions and an `InputSource` abstraction, so the autoplay bot and touch can drive Patch.

## Milestones

| # | Name | Core deliverables | Acceptance | Tag |
|---|---|---|---|---|
| M0 | Setup | Project, folders, autoloads, GUT, screenshot hook, docs | Tests run headless; a screenshot saves | `v0.0-setup` |
| M1 | The Slice | Flat hex test field with colorful junk, Patch (move, scoop, cube incl. Pure/Perfect, carry, stack), Depot, Cubes currency, 4 upgrades with card UI, hex flip moment, juice, procedural SFX, save/load | Fun for 10 minutes; autoplay reaches first cube <30 s and first upgrade <2 min | `v0.1-slice` |
| M2 | The Planet | Geodesic hex sphere (dual of subdivided icosahedron), regions/chunks, biomes, gravity to center, restoration shader, globe view | Walk across regions without stutter; globe matches sim | `v0.2-planet` |
| M3 | Robots | Parts, blueprints, Workshop, Scoopie/Haul Bug/Sorter, fleet upgrades, Haggle's depot, full upgrade UI, conveyors, processor, power, fleet panel | Automated cube line runs while exploring | `v0.3-robots` |
| M4 | Story foundation | WREN dialogue system, Memory Shards, 3 ruins, Acts 1-2, opening with the first flower | New player cares about WREN within 15 min | `v0.4-story` |
| M5 | Growing + Allocation | Soil, compost, seeds, growth, watering, Seedling/Drip/Sprinkler, Multibots, Allocation Board, wildlife, sky haze | Region goes junk → meadow with animals, requiring reallocation | `v0.5-grow` |
| M6 | Water | Lakes, clarity shader, raft/boat, aquatic robots, irrigation | Lake clear moment feeds sprinklers | `v0.6-water` |
| M7 | Hubs + Rockets | Multiple hubs, hub levels, blueprint copier, rockets, cargo rockets, Research Tree | Rocket between 3 automated hubs | `v0.7-rockets` |
| M8 | Content pass | All biomes, 40 ruins, full story, 40 easter eggs, Codex, achievements, cosmetics, stats, time-lapse, photo mode | Content complete | `v0.8-content` |
| M9 | Balance | Balance simulator + autoplay across the game, BALANCE.md | Pacing targets met | `v0.9-balance` |
| M10 | Polish | Music layers, accessibility, settings, quality tiers, perf, migrations, title, exports (Win/Linux/Android) | Zero log errors; builds export | `v1.0-rc` |
| M11 | Postgame | Cradle Mode world + Heirlooms, Garden Mode | Prestige loop works | `v1.1-postgame` |

## M1 breakdown (current)
1. Core: `BigNum`, `EventBus`, `GameState`, `Economy` (data-driven upgrades), `SaveManager`, `Settings`, `Audio` (procedural SFX), `Story` (stub).
2. World: flat hex grid test field (axial coords, ~250 hexes), per-hex junk ledger, MultiMesh junk per type, ground shader driven by a per-hex state texture.
3. Patch: procedural toon model, tread movement with lean/bounce, follow camera, scoop cone, chest compartment, cube press with Pure/Perfect/Lumpy, physics cubes, carry stack, drop/stack towers.
4. Depot pad: cash-in with suction + floating numbers; Upgrade Board UI (cards, before→after, progress bars, buy juice, x1/x10/Max).
5. Juice: squash/stretch, particles (dust, sparkles, steam), floating numbers, screen shake, rising pitch, hitstop/slow-mo on first hex.
6. HUD: Cubes + rate, compartment meter with perfect band, field restored %, toast feed, control hints.
7. Verification: GUT tests (BigNum, Economy, Save round trip, cube values), screenshot hook, autoplay bot measuring time-to-first-cube / first-upgrade.

## Ultracode / multi-agent use
Only for: the hex-sphere planet + chunking design (M2), save/offline progress (M5-M7), the economy balance simulator (M9), milestone bug bashes, and bugs that survive two normal fix attempts. Max 6 agents per workflow.

## Owner feature requests (added during M1)
- **Part detector** (M1 basic, deepened in M3): parts are buried in hexes. Patch's detector beeps faster and his antenna lamp blinks red as he closes in; within range the lens readout shows the part's rarity tier (Rusty → Legendary Maker-Made) by color. Dig to recover it into the Parts inventory.
- **Survey Drone + hologram map** (M2, with the globe view): an unlockable aerial survey drone (original design, a weathered municipal survey unit). It flies up from Patch and produces a **holographic survey map** of the area/planet showing hex states (junk / clean / planted / growing) with percentages and where robots are working. The hologram is a *snapshot*: it can be pulled up anytime but goes stale as the world changes (shown with a "surveyed N min ago" stamp and faded/estimated regions). Paying for a re-survey refreshes it. Upgrades add periodic automatic updates, then a live layer. Launch/landing and scan animations are a payoff moment.
- **Hub starts humble** (M1 visuals, M3/M7 systems): the first hub is not a building. It's an open lean-to shack with a salvaged workbench (the upgrade station) and a scrap drop bin on a weigh scale. Hub levels are built from **salvaged building materials** found in the world (planks, sheet metal, beams, pipes, concrete blocks) plus Cubes, upgrading shack → workshop → depot station → garden station.
