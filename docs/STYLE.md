# Greenfall style guide

Rules for code, data, folders, signals, and the game's visual and UI identity. Every agent reads this before touching anything. The code reviewer checks every change against it.

## 1. Originality rules (apply to everything)
- Reference games are for feel only: pacing, feedback timing, polish level. Never copy a HUD layout, menu, icon, art asset, upgrade tree, mechanic, name, term or progression structure from any other game.
- Every design starts from Greenfall's own theme: a rusty robot, salvage, repair, pollution cleanup, ecosystems regrowing, the robot itself changing.
- If something feels close to another game, change it until it is clearly ours and log the call in `docs/DECISIONS.md`.
- Do not name other games in code comments, data or player-facing text. (Existing mentions are removed in task M1-14.)

## 2. GDScript
- Godot 4.7.2, GDScript only. Static typing everywhere: typed variables, parameters, return types and typed arrays. `tools/warnings_audit.sh` must report 0.
- Tabs for indentation. Lines up to about 140 characters.
- One class per file. `class_name` in PascalCase; the file is the same name in snake_case.
- Order inside a file: `class_name`/`extends`, doc comment (`##`), signals, enums, constants, exported vars, public vars, private vars (`_name`), `_ready`/engine callbacks, public methods, private methods.
- Names: `snake_case` functions and variables, `PascalCase` classes, `UPPER_SNAKE` constants, `_leading_underscore` private members, signals in past tense (`hex_cleaned`, `upgrade_bought`).
- Comments say why, not what. No change-history tags in new code (the old `[orbB]`-style tags stay where they are but are not added). No TODO, FIXME or placeholder code in shipped systems.
- No magic numbers for balance or content. A number a designer might tune lives in data. Engine constants (a tween length for one widget, a mesh segment count) may stay in code as named constants.
- Functions stay under about 60 lines. Files stay under about 600 lines; split by job when they grow.
- Player-facing text always goes through `tr()` (see `docs/LOCALIZATION.md`). Text uses plain short words, starts with a verb where it is an instruction, and shows the bound key glyph through `Settings.bind_text`.
- Lifetime rules from `docs/ARCHITECTURE.md` section 5 stay in force: wait on every worker task at quit, no lambda/array reference cycles, never create a node and bail out before `add_child`.

## 3. The no-hardcoding rule (planet-agnostic code)
- Shared code never names a planet. No `"verdance"` string, no `if planet_index == 0`, no planet-specific constant outside `planets/<id>/`.
- Everything unique to a planet comes from its `PlanetDefinition` (section 5) or the data files it points to: terrain, pollution types, resources, upgrade tree, regrowth stages, tutorial steps, balance curves, visuals, music, sites, the restoration rule and the ending.
- Shared systems ask `Planets.current()` for the definition. They never read `data/<file>.json` by a fixed path for planet content.
- A planet may ship its own scripts for art (environment dressing, site props). Those scripts live in its folder and are called only through hooks named in the definition.
- The check: a test-only dummy planet (`tests/fixtures/planets/testworld/`) must load, play 60 seconds under the bot and save/load with no code change.

## 4. Folder layout
```
autoload/        singletons (EventBus, Settings, GameState, Economy, SaveManager, Audio, Planets)
core/            pure helpers with no nodes (BigNum, math, save schema, PlanetDefinition classes)
systems/         shared gameplay systems (cleanup, regrowth, upgrades, research, crew logic, tutorial runner, goals)
world/           assembles a playable world from a PlanetDefinition (the split of scenes/slice.gd)
planet/          shared globe tech: sphere grid, terrain, streaming, sites framework, sky
player/ robots/ automation/ plants/ fauna/ story/   shared actors and their logic
ui/              screens and widgets; ui/theme/ holds the one theme
audio/ art/      shared audio and procedural art helpers, shaders, the art kit
data/            planet-independent data only: currencies, settings defaults, cosmetics, achievements schema
planets/<id>/    one folder per planet: planet.tres (PlanetDefinition), data/*.json, env and site scripts, art
tests/           GUT tests; tests/fixtures/planets/testworld/ is the dummy planet
tools/           bots, simulators, audits, build scripts
docs/            the source of truth
```
Shared systems never import from `planets/<id>/`. A planet folder may import shared code.

## 5. Data
- `PlanetDefinition` is a typed `Resource` (`core/planet_definition.gd`, saved as `planets/<id>/planet.tres`). It holds typed fields for small things (id, display name, globe spec, target playtime, music set, palette) and paths to the planet's JSON tables for big ones (pollution, upgrades, research, regrowth stages, tutorial, goals, sites, balance).
- JSON tables keep a `_doc` key that explains every field. Ids are `snake_case` and never change once shipped (saves refer to them).
- Balance formulas are named and documented in `docs/PLANET_PLAYBOOK.md`. The simulator (`tools/pace_sim`) reads the same data the game reads.
- Global progress (cosmetics, achievements, settings, lifetime stats) is defined outside any planet folder.

## 6. Signals and dependencies
- Gameplay emits on `EventBus`; UI, audio, tutorial, goals and stats listen. Gameplay never calls UI directly.
- A system gets what it needs in `setup(world)` or through its constructor. No reaching through `get_node("/root/...")` and no duck-typed `world.get("x")` in new code.
- Signal names are past tense and carry ids, not nodes (`hex_cleaned(cell_id: int)`).
- Connections made to autoloads are disconnected in `_exit_tree`, or made with a method `Callable` on a node that the engine cleans up. No lambdas that capture `self` on long-lived signals.
- The tutorial and goals react to events and conditions only. They never poll private state of other systems.

## 7. Saves
- One versioned document: `{version, global, planets: {<id>: {...}}, current_planet}`. Planet state never leaks into `global`, and the reverse.
- Any change to the format adds a migration step and a fixture save in `tests/fixtures/saves/` with a test that loads it.
- Writes are atomic (write a temp file, then rename) with one rolling backup. A save that fails to parse falls back to the backup and tells the player.

## 8. Tests
- GUT, headless: `tools/run_tests.sh`. Test files are `tests/test_<area>.gd`; test names say the behaviour (`test_bale_pays_more_than_loose_trash`).
- Every bug fix adds a regression test that fails before the fix.
- Tests that can run on any planet take the planet id as a parameter and run against both the first planet and the dummy planet.
- Nothing is done until the full suite, the save round trip and the bot playthrough pass.

## 9. Visual style (art direction: realistic in detail, bright in mood)
The owner's rule (Nov 10): "fun to look at still and bright and colorful even with junk. I do not want a gloomy dark brown game all the time." Realism comes from believable shapes, materials and wear. It never comes from draining the colour.
- **Bright by default.** Sunny daylight, blue sky, clear shadows. Nights are readable and short. Haze and smog belong to specific polluted places and lift as they are cleaned; there is never a brown or grey grade over the whole game.
- **Junk is colourful.** Real litter is: drink cans, crates, plastic, painted metal, packaging, signs. Keep saturated colours in the junk; make it believable with real shapes, labels, dents and dirt on top of the colour, not instead of it.
- **Cities have colour of their own.** Painted buildings, murals, shop signs, awnings, street furniture, each city with its own palette and character. Worn, not dead.
- **Lumi's base keeps strong colours** (teal, orange, safety yellow, cream). Improve materials and detail; do not repaint things grey or brown to look "serious".
- **Restoration adds more colour:** green, flowers, clear water, wildlife, lights. The world goes from colourful and messy to colourful and alive, never from brown to green.
- **What "not cartoonish" means:** real-world scale, PBR materials, natural light, no flat toon shading, no outline shaders, no rubbery squash-and-stretch. It does not mean muted.
- **Readable states:** polluted and restored ground must be told apart from 30 metres by what is on it (litter and bare dry earth against soil, moss, grass, flowers, shrubs, trees), not by a dull colour cast.
- Machines are salvaged equipment with honest wear: chipped paint, bare metal edges, stencilled markings. Lumi's cyan marks things Lumi powers.
- Effects are physical: dust, sparks, steam, falling leaves, pollen, water spray. Glows and beams are for Lumi's tools and restoration moments, and they scale with the size of the win.
- Check every render for mood as well as detail: if a frame reads as gloomy, brown or grey overall, it fails.

## 10. UI style (identity: a field instrument)
The interface reads as Lumi's own instrument panel: a rugged, weathered survey tool, not a floating game menu.
- **Shapes:** rectangular plates with one clipped corner, thin engraved rules, riveted or stencilled section labels. No pill buttons, no glossy gradients, no card-fan layouts.
- **Type:** one condensed industrial sans for labels and numbers (tabular figures), one readable humanist sans for sentences. Minimum 16 px at 720p; sentences never below 18 px.
- **Colour:** warm off-white text on dark slate plates at 85-92% opacity. Accents: Lumi cyan (interactive and "yours"), hazard amber (needs attention), growth green (restored). Red only for real failure. Colour is never the only signal (shape or icon too).
- **Numbers:** big wins count up; small gains tick in place. Numbers never bounce. Formatting is short-scale with at most 4 significant digits (`12.4k`).
- **Motion:** 120-180 ms mechanical eases (slide, stamp, needle swing). No elastic or bouncy easing. Reduced-motion setting cuts all non-essential motion.
- **Diegetic first:** where the world can show it, the world shows it (chest fill on Lumi's gauge, a hex's progress as a ground ring). The HUD repeats only what must be read at a glance.
- **One next thing:** at most one objective card and one message line at a time.
- **Layout:** anchors and containers only, safe margins of 4% of the short side, tested at 16:9, 16:10, 21:9, 4:3 and Steam Deck (1280x800). Every screen works with mouse, keyboard, controller and touch-sized targets (minimum 44 px at 720p). Focus is always visible.
- **Scale:** the whole UI respects the interface-scale setting (0.8-1.5).
