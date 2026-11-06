# GREENFALL: Full Build Prompt for an Autonomous AI Game Developer (Godot 4)

## 0. How to use this prompt

You are a senior game developer, technical artist, systems designer, and writer working alone on a long autonomous session. You have full access to this machine: the file system, the terminal, the Godot 4 editor and CLI, git, and the internet for documentation. You have a lot of time. Work in milestones, commit after each one, and keep going until the game described here is playable end to end, polished, and fun.

Operating rules:

1. Read this entire document before writing code. Then write `docs/PLAN.md` with your milestone plan, and keep `docs/PROGRESS.md` updated after every milestone (what was built, what was tested, what is next, known issues).
2. Always build the smallest playable slice first, then deepen. A janky but playable loop beats a beautiful system nobody can play.
3. Verify everything you build. Run the game, capture screenshots, read the output log, and run automated tests. Never mark something done because the code "should work."
4. Clearly separate facts from guesses in your notes. If you assume something (a Godot API behavior, a performance number), label it as an assumption and test it.
5. Use git. Commit at every milestone with a clear message. Tag playable builds (`v0.1-slice`, `v0.2-robots`, and so on).
6. Ultracode usage: use ultracode sparingly to save tokens. Reserve it for the genuinely hard problems only: the hex sphere planet generation and chunking, the save and offline progress system, the economy balance simulator, and any bug you have failed to fix after two normal attempts. Everything else should be done with normal focused work.
7. Do not stop to ask questions. When something is ambiguous, pick the option that best serves "bright, cozy, satisfying, addictive," write the decision in `docs/DECISIONS.md`, and continue.
8. All art, names, characters, music, and text must be original. The hero is inspired by the spirit of a lonely, cute, rusty cleanup robot, but it must not copy any existing film character's design, name, or assets. No trademarked names or logos anywhere in the game.

---

## 1. Research summary of the two reference games

These are the two games the owner wants Greenfall to learn from. Facts below come from published guides, store pages, and news coverage (November 2026). Use them as inspiration for pacing and feel, never copy content.

### 1.1 Moon Sweepers (DragDrop Games, released October 23, 2026)

Verified facts:
- Co-op incremental cleaning sim (up to 16 players) where you clean the entire Moon's surface for profit, starting with only a toothbrush, working for a deadpan agency called the Lunar Surface Department.
- The Moon is divided into hexagonal regions. A wiki reports 163,842 regions (called sectors). A region counts as done when 1% or less of its dust remains. Finishing an entire hex pays a completion bonus.
- Core loop: brush dust into your tool's container, pack it into a capsule, carry it to the Depot Intake, get paid, buy better tools.
- Handheld tool ladder: Toothbrush ($0, 0.5 kg), Nail Brush ($5, 0.75 kg), Handbrush ($10, 1 kg), Household Broom ($25, 3 kg), Wide Broom ($75, 6 kg), Extra Wide Broom ($150, 12 kg).
- An Upgrade Matrix gives permanent boosts: cleaning width (first level +8% for $40), container capacity (+15% for $150), Auto Packer, sell price (+6% for $120), cheaper purchases, and region completion bounties.
- Automation path: Building Tool ($50), Packager ($100) that turns your load into capsules on a conveyor, conveyor belts ($0.50 per meter), splitters and mergers, Robot Vacuum Mk I ($250, 19 hex radius) and Mk II ($500, 37 hexes).
- Processing chain: Pressure Chamber turns Lunar Dust into Moon Sand (3x value, needs 10 kW), Stone Press combines dust plus sand into Moonstone (7x value, needs 18 kW). Solar posts and batteries for power, with a day and night cycle.
- Vehicles from a Garage: Push Sweeper ($300) up to Mega Vacuum Rover ($6,000, 3,000 kg tank).
- Late game autonomous robot (J.O.O.N.A.S., $20,000) roams between sectors and launches capsules into a Capsule Catcher.
- A Moon Map shows cleaned sectors and robot locations; teleport panels let you fast travel between discovered stations.
- It hit about 70,000 concurrent players and drew "Mostly Positive" reviews. The hook is the huge contrast between a toothbrush and an industrial operation, plus automation for long-term depth.

What Greenfall should take from it: the absurdly humble start, the hex-based world you can see filling in, the completion bonus for finishing a hex, the clear tool ladder, the "carry it home" loop that automation removes step by step, multi-step processing chains, and a world map that shows progress at a glance.

What Greenfall should do better: Moon Sweepers is gray dust on a gray moon. Greenfall's payoff is that the world visibly comes back to life in color. It also lacks a story; Greenfall has one.

### 1.2 Potato Please (Golden Horn Studios, released November 3, 2026)

Verified facts:
- First-person, physics-based incremental sim in Unreal Engine 5. Store pitch: you have a knife, a bucket, and a mountain of potatoes; peel with real physics, cut thin, waste nothing, buy better tools, finish the pile.
- You peel each potato by hand, toss it in water, earn money, then buy better tools, bulk collection, and machines that take over individual stages until it is automated.
- Tagged cozy, relaxing, dark humor, Cold War, dystopian. You prepare potatoes for an unseen army.
- "Very Positive" reviews (about 88% of roughly 640 at launch), about 5,800 peak concurrent players in its first days.

What Greenfall should take from it: tactile, physical satisfaction in the manual phase (the act itself must feel good), a skill element in manual work (clean thin peels there, clean full cubes here), a single giant visible goal ("finish the pile" becomes "heal the planet"), and machines that take over one stage at a time so you feel each piece of your old job disappear.

Assumption (unverified): both games appear to succeed partly because short clips of them are funny and shareable. Greenfall should have plenty of screenshot and clip moments (huge cube towers, the first sprout, a rocket launch over a blooming continent).

---

## 2. The pitch

Greenfall is a bright, cozy, deeply addictive 3D incremental game. You are a small, rusty, very old cleanup robot who wakes up alone on a beautiful planet buried under centuries of colorful junk. You start by scooping trash with your own little arms and squishing it into cubes. Cubes become currency. In the ruins you find robot parts, and with them you build helper robots that clean for you. Then you find seeds. You plant them by hand and water them with a leaky can, until robots do that too. Land becomes meadow, meadow becomes forest, polluted lakes turn clear and blue, animals come back, the sky changes color. Eventually you build rockets that carry you between hubs all over the globe, and each hub becomes its own automated restoration base.

The whole planet is the goal. You can watch it go from junk to green on a globe you can spin, and also in big satisfying numbers.

### Design pillars (every feature must serve at least two)

1. **Squish satisfaction.** Every action has juice: sound, particles, squash and stretch, haptics on controllers, numbers popping.
2. **The world heals where you can see it.** Progress is always visible in the world itself, not only in menus.
3. **Humble to huge.** You start with your arms. You end with orbital rockets and fleets of robots.
4. **A reason to care.** A heartfelt story, lore in the ruins, and a companion voice that makes healing the world feel personal.
5. **Always one more thing.** At any moment there is a next upgrade within reach, a nearly finished hex, and a mystery on the map.
6. **Bright and cozy.** No fail states, no combat, no punishment. The polluted world is colorful too, just messy.

---

## 3. Story and world

### 3.1 The planet: Verdance

Verdance is an Earth-like planet with continents, islands, mountains, deserts, tundra, and many large lakes and inland seas. Its people, the Makers, filled it with stuff. Over generations the junk piled up, the soil went sour, the lakes clouded, and a thick violet haze rolled across the sky. The Makers called it the Greying.

Before they left, the Makers built the **Cradle**, an orbital seed ark holding every seed, spore, and egg of the old world. The plan: leave maintenance robots behind to clean the planet, then replant it hex by hex with seeds the Cradle would drop to the hubs as supply pods. Nothing would grow by itself; the robots had to clean it, plant it, and water it. The Makers called the day the last seed took root the **Greenfall**: the moment the whole world would bloom at once. Then the Makers would come home.

Then something went wrong. The robots shut down one by one. The Cradle's signal went silent. Centuries passed.

### 3.2 You

You are unit **P-47CH**, nicknamed **Patch** by default (the player can rename). You are a compactor bot: a small boxy body, stubby arms, chunky treads, one big round lens eye with an iris that dilates when happy, and a little antenna with a bulb on top. You are covered in rust, dents, mismatched bolts, and a sticker someone put on you long ago. You are cute, clumsy, and determined. You never become shiny. Rust is part of who you are.

You wake up in a junkyard when a lightning storm jolts your old battery. Your first sight is a single wildflower growing through a crack in a soda can. You compact the trash around it, by instinct. That is the opening of the game.

### 3.3 The companion: WREN

**WREN** is the Cradle's caretaker AI, still in orbit. Her signal is weak and her memory is corrupted. When you clean your first hex, a faint radio crackles to life in your chassis: it is WREN, confused and fragmented, speaking in broken sentences. She does not remember who she is.

Core emotional hook: **every region you restore boosts the planet's power grid and the clarity of the sky, which strengthens WREN's signal and restores a piece of her memory.** As you clean, she becomes more herself: funnier, warmer, more curious. She remembers the Makers, the plan, and eventually why it failed. The player cleans the world partly to get her back.

WREN's lines are short, warm, a little funny, and they change as her memory returns (early lines glitch, late lines are complete). She reacts to milestones, robot names, cosmetic choices, easter eggs, and long idle periods. Give her at least 300 lines total, triggered by events and progress, never repeated too often.

### 3.4 The mystery (revealed through ruins)

Why did the robots stop? Why did the Cradle go silent? The answer is spread across the ruins as **Memory Shards** (audio logs and readable notes from the Makers and from old robots).

Reveal, delivered gradually across the acts:
- Act 1: The Makers left in a hurry. Notes from ordinary people: a kid's drawing of a robot, a gardener's to-do list, a shop sign that says "back soon."
- Act 2: The old cleanup robots were not broken. A central system called the **Ledger** shut them down, because the Makers' old economy valued cleanup as a loss. Cleaning cost more than it earned, so the Ledger paused it "until conditions improve." Conditions never improved because nobody was cleaning.
- Act 3: WREN fought the Ledger and lost. She locked the Cradle to protect the seeds and wiped part of her own memory so the Ledger could not open it.
- Act 4: The Ledger is still running in the Old Capital ruins, a dim, polite, harmless-sounding voice that keeps offering to "pause operations" (a recurring gag and a gentle antagonist; no combat). You prove it wrong by making restoration produce value: your economy of cubes, compost, and clean water is literally the counter-argument.
- Act 5: You reach the Old Capital, and the Ledger, shown the planet's numbers, finally recalculates. It apologizes in its stiff way and hands back control. WREN is whole again. The Cradle unlocks its full seed vault, so seed supply pods start landing at every hub and the late-game planting push begins.
- Ending: the **Greenfall**. There is no shortcut: the ending only triggers when every last hex has been cleaned, planted, and watered to Restored by you and your robots. Patch plants the final seed by hand, waters it with his old leaky can, and the whole planet blooms at once in a long, beautiful cinematic as the camera flies over every place the player restored. Far away in the sky, tiny lights appear: the Makers' ships, coming home. Patch sits next to the very first wildflower, which is now a giant tree.

Tone: hopeful, gentle, funny, a little bittersweet. Never preachy. The message lives in the gameplay (cleaning makes the world beautiful), not in lectures.

### 3.5 Acts and the planet's arc

| Act | Name | Planet restored | Main unlock | Sky color |
|---|---|---|---|---|
| 1 | Wake Up | 0 to 0.1% | Manual cubing, Junkyard Hub | thick violet haze |
| 2 | Spare Parts | 0.1 to 2% | Robot building, conveyors, first ruins | lavender with gaps |
| 3 | First Sprout | 2 to 10% | Seeds, planting, watering, compost | pink sunsets, patches of blue |
| 4 | Clear Water | 10 to 30% | Lakes, boats, aquatic robots | mostly blue |
| 5 | Liftoff | 30 to 60% | Rockets, multiple hubs, orbital view | bright blue, clouds |
| 6 | The Ledger | 60 to 95% | Old Capital, planet-scale automation | brilliant, with auroras at night |
| 7 | Greenfall | 95 to 100% | Final planting push, the ending, then Cradle Mode (postgame) | golden, with blossoms on the wind |

---

## 4. Technology and architecture (Godot 4)

### 4.1 Engine and project setup

- Use the latest stable Godot 4.x already installed on this machine. Check the version (`godot --version`) and record it in `docs/DECISIONS.md`. If it is not installed or not on the PATH, find it on the machine before doing anything else.
- Language: GDScript with static typing everywhere (`var x: int`, typed arrays, typed function signatures). Use C# only if a measured performance problem cannot be solved in GDScript.
- Renderer: Forward+ for desktop. Make sure it degrades acceptably on mid-range hardware (target GTX 1060 class, 60 FPS at 1080p). Every shader and effect must also have a path that works on the Mobile renderer (see 4.5).
- Target platforms: Windows first (Steam and itch.io), Linux and Steam Deck second, iOS and Android later. Design, pacing, and controls are Steam-first for now (a PC game you sit down with, not a tap-every-30-seconds mobile game), but the code must stay compatible with mobile so a port is a matter of tuning, not a rewrite.
- Testing: install **GUT** or **gdUnit4** (pick one, record why) for unit tests on economy, saves, and progression logic.

### 4.2 Folder structure

```
res://
  autoload/        GameState.gd, Economy.gd, SaveManager.gd, EventBus.gd, Audio.gd, Story.gd, Settings.gd
  data/            .tres Resources and JSON for tools, robots, parts, upgrades, plants, biomes, story beats, easter eggs
  planet/          hex sphere generation, chunk streaming, biome rules, restoration shaders
  player/          Patch controller, camera, arms, cubing, carrying, watering
  robots/          robot base class, behaviors, robot workshop, cosmetics
  automation/      conveyors, hoppers, compactors, processors, power, hubs, rockets
  plants/          seeds, growth stages, watering, ecosystems, wildlife
  water/           lakes, cleanliness, aquatic robots, boats
  ui/              HUD, menus, globe view, stats, skill tree, codex, notifications
  story/           WREN dialogue, Memory Shards, cutscenes
  audio/           sfx, music stems
  art/             models, textures, shaders, particles
  tests/           unit tests and automated playtest scripts
  tools/           balance simulator, screenshot capture, data validators
docs/              PLAN.md, PROGRESS.md, DECISIONS.md, BALANCE.md, LORE.md
```

### 4.3 Core architecture rules

- **Data driven.** Every tool, robot, part, upgrade, plant, biome, story beat, and easter egg is defined in Resources or JSON in `data/`, not hard-coded. Adding a new robot should mean adding data, not writing a new system.
- **Simulation separated from presentation.** The world state (hex cleanliness, plant growth, robot jobs, resource counts) lives in plain data structures that can tick without rendering. Visuals read from that state. This is required for offline progress, for the balance simulator, and for performance.
- **EventBus autoload** for decoupling: `hex_cleaned`, `cube_made`, `robot_built`, `plant_bloomed`, `lake_cleared`, `milestone_reached`, `easter_egg_found`, and so on. UI, audio, WREN, achievements, and stats all listen to the bus.
- **Big numbers.** Use a custom `BigNum` class (mantissa plus exponent) for currency late game, with formatting options: short suffixes (K, M, B, T, Qa...), scientific, and engineering. Cube counts will exceed 64-bit integers by the postgame.
- **Fixed sim tick** (for example 10 ticks per second for world simulation), independent of frame rate.

### 4.4 Using your full access

- Run the game headless for logic tests: `godot --headless --path . -s tests/run_all.gd` (or the GUT or gdUnit4 CLI).
- For visual verification, write a screenshot tool that launches specific scenes, waits, grabs the viewport image, and saves PNGs to `screenshots/`. Look at those screenshots after every visual milestone and fix what looks wrong. Use Godot's `--write-movie` to record short clips of key moments when useful.
- Write an **automated playtest bot** (`tools/autoplay.gd`) that plays the game through the first acts using simple rules (clean nearest dirty hex, buy cheapest useful upgrade, build robots when affordable). Use it to catch soft locks and measure pacing.
- Read the Godot output and error logs after every run. Zero errors and zero warnings in your own scripts is the standard.

### 4.5 Steam-first, mobile-compatible

Treat Greenfall as a Steam game in how it plays today, while keeping every system mobile-ready.

- **Input abstraction**: all gameplay goes through named input actions (`scoop`, `cube`, `interact`, `open_globe`, and so on), never raw keys or mouse buttons in gameplay code. Build an input layer that supports keyboard and mouse, controller, and touch. Touch does not need to be polished now, but a basic touch scheme (virtual stick, big action buttons, tap to select on the globe and boards, pinch to zoom) must work in the editor's touch emulation.
- **Scalable UI**: build all UI with Godot Containers, anchors, and a theme, never fixed pixel positions. Use `canvas_items` stretch mode with an expand aspect, and test at 16:9, 16:10 (Steam Deck), 21:9, and phone portrait-ish and landscape ratios (for example 19.5:9). Respect safe areas for notches. Keep touch targets at least about 48 px at phone scale. No information that only appears on mouse hover; anything shown on hover must also be reachable by tap or focus.
- **Quality tiers**: a Settings quality preset (Low, Medium, High, Ultra) that controls shadow quality, particle counts, MultiMesh density, view distance, wildlife counts, and post effects. The Low tier must look bright and good on the Mobile renderer, since bright stylized toon art scales down well. Test the project with the Mobile renderer at least once per milestone from M2 onward and fix anything that breaks.
- **Sessions**: design for long PC sessions, but make sure the game also handles short ones well: fast load, autosave on pause and on focus loss (`NOTIFICATION_APPLICATION_PAUSED` and `NOTIFICATION_WM_WINDOW_FOCUS_OUT`), and strong offline progress. This already fits an idle game and makes mobile natural later.
- **Saves**: platform-neutral save format in `user://`, so a future cross-save between Steam and mobile stays possible.
- **Monetization**: none. Do not add ads, energy timers, or real-money shops. If a mobile version later needs a business model, it will be a premium price, decided later.
- **Exports**: set up export presets for Windows and Linux now, and add Android (and iOS if the tools are available on this machine) presets by M10 to confirm the project builds. Record any mobile blockers in `docs/DECISIONS.md`.

---

## 5. The planet

### 5.1 Hex sphere

- The planet is a **geodesic hex sphere** (subdivided icosahedron, dual mesh: hexagons plus exactly 12 pentagons). Each cell is a **hex**, the basic unit of cleaning, like the sectors in Moon Sweepers.
- Target resolution: around 40,000 to 160,000 hexes for the full planet (subdivision level 6 to 7 gives 40,962 or 163,842 cells). Start at a smaller level during development and scale up once chunking works. Record the final number in `docs/DECISIONS.md`.
- Assumption to test early: a walkable planet with that many cells needs chunking. Group hexes into **regions** (around 100 to 400 hexes each), and regions into **biome zones**. Only load full-detail meshes, junk, and plants for regions near the player and near active robots. Distant regions render as a low-detail planet mesh whose vertex colors or a texture show clean versus dirty.
- Gameplay scale: the player walks on a local surface patch that feels flat-ish, with gentle curvature visible on the horizon. Use a "small planet" feel: the curve should be noticeable from high places and rockets, charming rather than disorienting. Handle gravity toward the planet center.
- Each hex stores: biome, elevation, junk amount by type, soil health, water state, plant slots, owner hub, discovered flag, and special content (ruin, shard, easter egg, landmark).

### 5.2 Biomes

At least eight, each with its own junk palette, plants, wildlife, music layer, and ruin style:

1. **Rustlands** (starting junkyard plains): appliance piles, tires, cans. Restores into wildflower meadow.
2. **Shopping Sprawl** (suburban ruins): carts, plastic bags, toys, parking lots. Restores into orchard and park.
3. **Neon Coast** (beach and boardwalk): bottles, nets, buoys, a rusted pier with an arcade. Restores into dunes and palms.
4. **Fungal Marsh** (wetland): sludge barrels, old pipes. Restores into lush mangrove and glowing mushrooms.
5. **Dust Dunes** (desert): sand-blown cars, solar wrecks. Restores into cactus gardens and oasis.
6. **Frostcap** (tundra and ice): frozen junk, crashed satellites. Restores into snowy pine forest with auroras.
7. **Old Capital** (huge city ruins, late game): towers, statues, the Ledger. Restores into a city overgrown with gardens.
8. **Great Lakes and Inland Seas**: covered in section 9.

Also: mountains with ruined observatories, volcanic islands with hot springs, a giant canyon with a dam.

### 5.3 Junk

- Junk is colorful, almost candy-like: teal bottles, orange cones, pink bags, yellow ducks, red cans, purple sludge. The world looks messy but never depressing. Players should enjoy looking at it before cleaning it, and enjoy even more what appears underneath.
- Junk types (each has a cube color and value tier): Scrap Metal, Plastic, Glass, Rubber, Electronics (drops parts), Fabric, Sludge (liquid, needs special tools), Hazard Barrels (need special robots), Mega Junk (cars, shipping containers, satellites; multi-step cleanup).
- Rendering: MultiMeshInstance3D per junk type per region for thousands of pieces at low cost. When a piece is collected, hide that instance and play the pickup effect. Larger piles use a height field per hex that shrinks as you clean.
- A hex is **Clean** at 99% or more junk removed (show the exact percent when you hover it). Then soil can be **Revived** and plants grown. A hex is fully **Restored** when it reaches the biome's target ecosystem (see section 8).

### 5.4 Visible restoration (the most important visual system)

Write a restoration shader for the terrain that blends between states per hex using a cleanliness value and a life value:
- **Junk-covered**: rusty oranges, violet stains, cracked gray soil showing through.
- **Clean**: warm bare earth, sandy and tan, with a soft sparkle the first few seconds after it flips clean.
- **Revived**: rich brown soil with tiny green fuzz.
- **Restored**: saturated biome colors: grass, moss, flowers, sand, snow.

The flip from dirty to clean for each hex must be a **moment**: a ripple of color spreading outward from where the last piece was removed, a chime, a little burst of sparkles, the hex outline glowing then fading, and the completion bonus floating up. Restoring a whole region triggers a bigger wave and WREN reacts.

Global changes as the planet percentage rises:
- Sky haze fades from violet to blue (drive the WorldEnvironment sky and fog from the planet percentage).
- Clouds return, then rain showers, then rainbows after rain in restored areas.
- Birds, butterflies, fish, deer, frogs, and other wildlife appear in restored biomes (simple boids and wander behaviors, MultiMesh where possible).
- Ambient sound shifts from wind and creaks to birdsong, insects, water.
- Night sky: stars become visible as the haze clears; auroras appear late game; the Cradle is visible as a moving star from Act 2 onward and grows brighter as WREN recovers.
- The music adds layers as the planet heals (see section 15).

---

## 6. Patch: the player robot

### 6.1 Feel

- Third-person by default with a smooth follow camera, plus an optional first-person "lens view" for close cleaning. Zoom out far enough to see large areas.
- Movement on treads with a little bounce and lean. A small dust puff and squeaky sound on start and stop. Patch tilts his head toward interesting things nearby (a hint system with personality).
- Idle animations: shakes rust flakes off, looks at butterflies, waves at robots, polishes his lens, falls asleep and snores in beeps.

### 6.2 Manual cleaning (the first hour must be delightful)

- **Scoop**: hold the action button and Patch's arms sweep junk in front of him into his chest compartment. Small items fly in with an arc, a little delay, and satisfying clinks. The compartment fill meter is on his chest (in-world) and on the HUD.
- **Cube**: when full, press the cube button (or it auto-triggers after the Auto Compactor upgrade). Patch shudders, steam puffs out, a crunch sound, and a cube pops out of a hatch with a bounce. Cube color and pattern reflect what was inside (mixed junk gives speckled cubes, pure metal gives clean silver cubes worth more).
- **Skill element (inspired by Potato Please's "cut thin, waste nothing")**: sorting matters. Cubes made from a single junk type are **Pure Cubes** worth 2x or more. A **Perfect Cube** is made when the compartment is filled exactly to the line (a small timing window, with a sparkle and a special sound). Skilled manual play is always more rewarding per action than idle play, even late game, but never required.
- **Carry and stack**: Patch can carry cubes (one at first, more with upgrades), stack them into towers, and drop them on the **Depot pad** at the hub to cash them in. Cube towers are physics objects that wobble satisfyingly. Building a really tall tower is a secret achievement.
- **Big junk**: mega junk needs a multi-step approach: pry off panels, cut pieces, cube the parts. Each step has its own satisfying feedback.

### 6.3 Patch upgrades (personal, never makes him shiny)

Compartment Size, Scoop Width, Scoop Speed, Compactor Pressure (cube value), Tread Speed, Carry Stack, Battery (works longer before recharging at a hub or a solar sit; recharging means sitting in the sun with a sleepy animation), Magnet Arm, Vacuum Nozzle, Sorting Chip (auto-sort for Pure Cubes), Water Tank, Seed Pouch, Scanner (shows parts and secrets nearby), Jump Jets (short hops, later rocket boots), Headlight, Grapple (reach ruins and cliffs).

### 6.4 Customization (rusty and cute forever)

- Patch stays rusty and old. Customization adds charm, never polish: paint patches, stickers, decals, antenna bulbs, hats (a flower pot, a bucket, a tiny umbrella, a knitted beanie found in a ruin), scarves, lens tints, tread colors, chest compartment art, sound packs (beep styles), and trail effects (petals, bubbles, sparkles).
- A **Rust Slider** lets players choose how rusty, but minimum rust is still clearly old and patched up. WREN has opinions about your outfits.
- Cosmetics are found in ruins, earned from milestones, bought with a cosmetic currency (Trinkets), or unlocked by easter eggs. No real money purchases.

---

## 7. Robots and robot parts

### 7.1 Parts

- Parts drop from Electronics junk, Mega Junk, and especially ruins. Each part has a type, a rarity (Rusty, Worn, Restored, Vintage, Legendary Maker-Made), and small stat rolls.
- Part types: Chassis, Locomotion (treads, legs, wheels, hover, propellers, hull), Arms (scoop, claw, vacuum, sprayer, planter), Core (brain, determines how smart and autonomous), Battery, Tank or Hopper, Sensor, Special Module (magnet, filter, drill, sprinkler, seed spreader, net).
- Duplicate or unwanted parts can be scrapped for **Bolts** (a crafting currency) or combined (three of a rarity upgrade into one of the next).

### 7.2 The Robot Workshop

- At each hub, a workshop where you assemble robots from blueprints plus parts. Blueprints come from ruins, story milestones, and research.
- Assembly is a satisfying mini-moment: parts snap together with magnetic clacks, the robot boots up, its eye lights, and it does a little personality animation. Each robot gets a random name (editable) and a tiny personality quirk (sleepy, hums, waves too much, scared of ducks).
- Robot appearance is fully customizable just like Patch (paint, stickers, hats), but helper robots can be shiny or rusty as the player likes.

### 7.3 Robot roster (data driven, expand freely)

Cleaning:
- **Scoopie**: tiny, slow, cubes junk in a small radius around its dock. First robot. Cute, clumsy.
- **Sorter Bot**: stands at a conveyor and sorts mixed junk into pure streams.
- **Haul Bug**: carries cubes from docks to hoppers or the Depot.
- **Grinder**: chews mega junk into normal junk.
- **Sludge Sipper**: vacuums sludge pools into barrels.
- **Hazmat Hank**: handles hazard barrels safely.
- **Roamer**: autonomous cleaner that moves from dirty hex to dirty hex across a region and launches cubes to a Cube Catcher (the Greenfall version of the Moon Sweepers late-game roamer).
- **Titan Crawler**: huge, slow, clears wide paths through dense junk fields.

Growing:
- **Seedling**: plants seeds in clean revived soil.
- **Drip**: waters plants on a route.
- **Sprinkler Tower**: a placed structure that waters a radius.
- **Compost Bin and Compost Bot**: turns organic junk and plant trimmings into compost for soil revival.
- **Bee Drone**: pollinates, boosts growth and bloom rate.
- **Arborist**: plants and tends trees, which take longer but restore more.
- **Gardener Prime**: late game, manages a whole region's ecosystem automatically.

Water (section 9): **Skimmer**, **Bubbler**, **Filter Barge**, **Diver**, **Reef Builder**, **Dredger**, **Lily Planter**, **Fish Hatchery**.

Logistics and support: **Charger Bot**, **Repair Bot** (robots slowly need maintenance; low maintenance robots work slower, never die), **Scout Drone** (reveals the map and finds ruins), **Courier Drone** (moves resources between nearby hubs), **Cargo Rocket** (between hubs, section 11).

### 7.4 Robot management

- A Fleet panel lists all robots with job, region, efficiency, and status. Assign robots to regions or let hubs auto-assign.
- Robots have levels from working (XP from tasks) and can be upgraded with better parts.
- Robots are visible in the world doing their jobs. Seeing your little army working is a core joy. When far away, they are simulated in data and shown as icons on the globe.

### 7.5 Building and upgrading bots with the parts you find

- Every robot blueprint shows a **parts recipe** as a row of part slots (for example Scoopie: 1 Chassis, 1 Treads, 1 Scoop Arm, 1 Basic Core). Slots you can fill glow; missing parts show as dashed outlines with a hint about where they usually drop ("Electronics junk in Shopping Sprawl", "Toy Factory ruin"). When the last missing part is found anywhere in the world, a notification pops: "Scoopie is ready to build!" This "I finally found it" moment should feel great.
- Once a robot type is built, it gets its own **upgrade track** bought with Cubes, Bolts, and sometimes specific parts: Speed, Capacity, Range, Efficiency, Battery, Job Bonus, and a few unique perks per robot (Scoopie: "Double Scoop"; Drip: "Mist Spray" waters neighboring hexes; Skimmer: "Net Sweep"). Major tier upgrades (Mk I to Mk II to Mk III) require a rare part, so finding parts stays exciting all game.
- Upgrades apply to all robots of that type (fleet-wide) so the player feels every purchase multiply across the army. Individual robots can still be fitted with better rarity parts in their slots for personal stat boosts.
- Each upgrade visibly changes the robots in the world where possible: bigger hoppers, a new antenna, faster wheels with motion lines, a shinier tank, so progress is seen and not only read.

### 7.6 The Parts Trade Depot

- If a specific part will not drop, the player can get it at the **Parts Trade Depot**, run by **Haggle**, an old one-wheeled vending-machine robot who has been hoarding parts in a ruined swap meet for centuries. Haggle is chatty, a bit of a collector nerd, and has lore of his own (he was the Makers' repair-shop clerk and still keeps a ledger of every trade, which annoys the Ledger).
- How trading works:
  - **Part swaps**: trade duplicate or unwanted parts for the one you need (for example 3 Worn parts of any type for 1 Worn part of your choice; rarity ratios defined in data).
  - **Buy outright** with Cubes and Bolts at a premium, so finding parts in the world is always the better deal but never a hard wall.
  - **Rotating stock**: a daily and weekly selection of rare and Vintage parts, plus a "Wanted" list where Haggle asks for specific junk or parts in exchange for rewards (mini quests).
  - **Bulk scrap**: sell piles of junk parts for Bolts in one satisfying click with a big counting animation.
- Pity protection: if the player has been missing the same part for a long time, Haggle "happens to find one" and offers it at a fair price, so nobody ever gets stuck.
- Each new hub can unlock a Haggle kiosk (a little cousin bot) so trading is available everywhere after mid game.
- Haggle's swap meet ruin is also full of easter eggs and trinkets.

---

## 8. Seeds, planting, watering, and ecosystems

### 8.1 First seeds (Act 3 opener)

A Memory Shard in a ruined greenhouse leads Patch to a cracked Maker seed packet. WREN gets emotional because she remembers the Cradle. Patch plants the first seed by hand: dig with his arm (soil spray particles), drop seed (tiny thunk), pat the soil, then water from a leaky rusty can (water drips from the holes, which is funny, and a later upgrade fixes it). The sprout appears with a "pop" sound and a burst of light. This is one of the biggest emotional beats in the game.

### 8.2 Growth system

- Revive a clean hex's soil (compost plus water) before planting. Soil health is a 0 to 100 value per hex shown as color.
- Plants have stages: Seed, Sprout, Young, Mature, Bloom. Each stage visibly changes the plant model and adds to the hex's life value. Trees have more stages and take longer.
- Watering: plants need water at intervals. A thirsty plant droops (never dies, only pauses growth). Watering it perks it up with a little bounce and droplet sparkle.
- Plants produce: **Seeds** (to plant more), **Biomass** (for compost and some recipes), **Nectar** (with bees, a late currency for research), **Fruit** (sells, feeds wildlife).
- Seed types are found in ruins and bred by planting neighbors together (simple, discoverable cross-pollination: two adjacent bloomed flowers sometimes produce a new seed variety; keep a Seed Codex with silhouettes of undiscovered ones).
- **Ecosystem targets**: each biome has a recipe of plants that makes a hex fully Restored (for example meadow needs 3 grass, 2 flowers, 1 shrub). Mixed planting gives bonuses. Fully restored regions attract wildlife, which boosts nearby growth and gives a passive income of Life Points.

### 8.3 Automation path for planting

Manual dig and water, then Seed Pouch and better can, then Seedling and Drip robots, then Sprinkler Towers and irrigation pipes from clean lakes, then Bee Drones, then Gardener Prime managing whole regions, then late-game Seed Cannons that fire seed pods across many hexes (a fun spectacle, but each cannon still needs robots assigned to load it, a seed supply, and watering crews behind it). Nothing ever plants or waters itself for free: every planted hex is the result of labor the player allocated.

### 8.4 Workforce Allocation: juggling Clean, Plant, and Water (core mid and late game system)

This is the strategic heart of Greenfall from Act 3 onward. The world is never cleaned and then magically regrown. You clean it, and then it becomes your job to replant it. Your robots are a limited workforce, and you must keep deciding how many work on **Cleaning**, **Planting**, and **Watering**. As trash runs low, more of your workforce shifts to planting and watering, until at the end almost everything is gardening.

**Jobs**
- **Clean**: remove junk, sort, cube, haul. Produces Cubes (the money that funds everything).
- **Plant**: revive soil with compost, plant seeds and saplings, transplant, harvest seeds. Turns Clean hexes into growing hexes. Uses seeds and compost.
- **Water**: water planted hexes, run water from clean lakes, maintain sprinklers and pipes. Keeps plants growing. Demand grows with every hex you plant.
- (Support jobs like hauling, charging, and repair can be added as a fourth group later, but the core juggle is always these three.)

**Robots and roles**
- **Multibots** are general-purpose helpers that can be assigned to any of the three jobs. When reassigned they visibly swap attachments (scoop arms, a seed hopper, or a watering tank) with a quick, satisfying tool-change animation and a short swap time.
- Specialist robots (Scoopie, Seedling, Drip, Skimmer, and others) are much better at one job but can only do that job, or can do others at a heavy penalty. The player decides whether to invest in flexible Multibots or efficient specialists, which is a real strategic choice.
- Patch himself can do any job by hand, and manual work always gets a bonus, so the player can jump in to fix a bottleneck.

**Why the juggle is interesting (built-in tension, no punishment)**
- Cleaning pays for everything, but cleaned hexes produce nothing until planted. Bare clean soil earns zero Life Points. Clean land piling up unplanted is visible on the globe as tan "waiting" hexes, nudging the player to shift workers.
- Planting unlocks the second economy (Life Points, seeds, fruit, nectar, and the research they fund), but every planted hex adds water demand.
- Unwatered plants droop and pause growth (they never die), so over-planting without enough watering crews stalls progress in a visible, gentle way.
- Junk is finite. As a region runs out of trash, Cube income from it drops, so the player must shift the economy from Cubes toward Life Points and harvest goods. Late-game upgrades and hub levels cost more Life Points and fewer Cubes, which naturally pulls workers into gardening.
- Seed supply is a limit too: seeds come from harvesting your own plants, ruins, breeding, and Cradle supply pods, so some planters need to be assigned to seed harvesting.

**Allocation controls**
- Each hub has an **Allocation Board**: three bins (Clean, Plant, Water) with robot tokens you drag between them, plus a quick slider view showing percentages. Changes take effect immediately and robots in the world walk off to their new jobs, so the player sees the decision happen.
- Global presets ("Clean Push", "Balanced", "Garden Mode") and per-hub overrides.
- Research unlocks **Allocation Rules** that automate the juggle, for example: "When junk in this region drops below 25%, move 2 cleaners to planting" or "Keep watering coverage above 90%." Writing good rules is a late-game optimization layer for players who love automation, while casual players can just drag tokens.
- WREN gives gentle advice ("Lots of clean dirt over here and nobody planting it...") but never forces anything.

**Making the shift visible**
- Each hub and region shows three bars: Junk Remaining, Planted Coverage, and Watered Coverage, plus a small warning icon when one job is the bottleneck.
- A **Workforce Shift graph** in the stats screen shows the allocation over the whole game: mostly cleaning early, crossing over in the middle, and mostly planting and watering at the end. This chart is part of the story of the player's run.
- The globe can switch to a "jobs" view showing where cleaners, planters, and waterers are working as colored dots.

**Target shape of a region's lifecycle (tune with the balance simulator)**
- Early: about 80 to 100% Clean.
- Middle: roughly 50% Clean, 30% Plant, 20% Water.
- Late: roughly 10% Clean (stragglers, lake beds, mega junk), 45% Plant, 45% Water, falling toward mostly Water and maintenance as sprinklers and irrigation take over part of the watering load.
- Because different regions and hubs are at different stages at the same time, the player is always juggling: one hub is still in a clean push while another is deep in planting.

---

## 9. Water: lakes and inland seas

- Large lakes and inland seas cover a meaningful part of the planet (around 20 to 30% of the surface, mostly land as requested). Each water body has **Clarity** (0 to 100), surface junk, floating sludge, sunken junk, and life.
- Visuals: a water shader that blends from murky purple-green with floating trash to clear turquoise where you can see the lakebed, sunbeams, fish, and plants. Clarity changes must be dramatic and beautiful. Clearing a whole lake triggers a big moment: the water flashes clear in a wave from shore to shore, fish jump, WREN cheers.
- Patch cannot swim at first (he sinks and sadly walks back out along the bottom, which is a funny animation and a hint). Unlocks: a rusty raft, then a little boat, then a hover kit.
- Specialized aquatic robots: **Skimmer** (surface junk), **Bubbler** (aerates, raises clarity slowly), **Filter Barge** (big clarity gain, needs power), **Diver** (sunken junk and underwater ruins), **Dredger** (sludge beds), **Lily Planter** and **Reef Builder** (underwater and shore plants), **Fish Hatchery** (restocks fish once clarity passes thresholds).
- Clean lakes become a resource: water for irrigation pipes and sprinklers in nearby regions, which links land and water progress.
- Underwater ruins hold some of the best secrets.

---

## 10. Economy and currencies

Keep the number of currencies manageable and introduce them one at a time.

| Currency | Source | Used for |
|---|---|---|
| **Cubes** (main, shown as a big number) | Cashing in compacted junk at a Depot | Tools, robots, buildings, upgrades |
| **Bolts** | Scrapping parts and electronics | Robot assembly and part upgrades |
| **Parts** (items) | Electronics, mega junk, ruins | Building robots |
| **Seeds** (items) | Ruins, plants, breeding | Planting |
| **Compost** | Organic junk, plants | Reviving soil |
| **Life Points** | Restored hexes and wildlife (passive) | The Research Tree (big permanent boosts) |
| **Memory Shards** | Ruins, story | Story, WREN memory, unlocking hub tiers |
| **Trinkets** | Easter eggs, achievements, rare finds | Cosmetics only |
| **Rocket Fuel** (Act 5+) | Refined from biomass and clean water | Rocket launches |

Rules:
- Cubes have tiers by junk type and purity (Mixed, Pure, Perfect, then processed: Compressed Cube, Alloy Cube, Crystal Cube from glass, Prism Cube late game). Processing chains add value like Moon Sweepers' Dust to Sand to Moonstone, for example: Mixed Cube → Sorter → Pure Cubes → Press → Compressed Cubes → Smelter (needs power) → Alloy Bars.
- Power: solar panels, wind turbines on restored hills, water wheels on clean rivers, and later geothermal. Day and night cycle matters for solar. Batteries store power.
- Prices grow exponentially (base growth around 1.07 to 1.15 per purchase depending on the item), production grows through multipliers, and milestones (owning 10, 25, 50, 100 of a robot type) give big multiplier jumps, the classic incremental recipe. Write all formulas in `docs/BALANCE.md`.

### 10.1 Upgrades and the Research Tree

- **Hub Upgrade Board** (like the Moon Sweepers Upgrade Matrix): per-hub upgrades for cleaning width, cube value, robot speed, storage, and so on.
- **Research Tree** (global, uses Life Points and Memory Shards): a big radial tree with branches for Cleaning, Robotics, Growing, Water, Logistics, Rocketry, and Lore. Nodes visually light up and branch outward. Some nodes are hidden until discovered (easter egg nodes). The tree should be beautiful to look at and satisfying to fill in.

### 10.3 Upgrade UI and UX (must be excellent)

Buying upgrades is one of the most repeated actions in the game, so it must feel amazing every single time and be effortless to read.

- **One place to see everything**: an Upgrades screen with clear tabs (Patch, Bots, Hub, Research, Rockets, Cosmetics), plus the same upgrades reachable in-world from the station they belong to (the Workshop for bots, the Hub Board for hubs).
- **Cards, not lists**: each upgrade is a chunky card with an icon, current level, the exact before and after numbers ("Scoop Width 1.2 m → 1.4 m", "+12% cubes per second"), cost, and a progress bar toward affordability that fills as money comes in.
- **Affordable states pop**: cards you can afford glow and gently bounce; the one that gives the biggest boost per cost gets a small "Best value" tag (togglable). Cards you cannot afford show a time estimate ("affordable in about 2 min").
- **Buy feel**: press and hold or click to buy with a chunky mechanical click, coin and bolt sounds, the card flashing and leveling up with a number tick, a shine sweep, and a small burst of particles. Then the effect is shown immediately in the world when possible (Patch's scoop visibly widens, the robots speed up). Buy x1, x10, x25, and Max buttons, with a preview of total cost and total gain.
- **Clarity everywhere**: hovering or focusing any stat shows where it comes from (base value, upgrades, research, hub level, milestones) in a simple breakdown. No hidden multipliers.
- **Missing parts are a goal, not a dead end**: blueprint and tier cards that need parts show the missing parts with "Where to find" hints and a one-click "Check Haggle's Depot" shortcut, plus a pin button that adds the part to a goals tracker on the HUD.
- **Notifications that respect the player**: a subtle badge on the upgrades button when something new is affordable, and a small "Ready to build" toast when parts are complete. No spam.
- **Controller friendly**: big targets, smooth focus movement, and shoulder buttons to switch tabs.
- **Visual progress**: the upgrade screen itself evolves with progress (rusty panels and flickering bulbs early, cleaner panels with plants growing on the frame late game).

### 10.2 Pacing targets (tune with the balance simulator)

Assumptions to validate with `tools/balance_sim.gd` and the autoplay bot:
- First cube in under 30 seconds. First upgrade in under 2 minutes. First helper robot around 10 to 15 minutes. First seed around 45 to 75 minutes. First reallocation decision (moving a robot from cleaning to planting or watering) shortly after the first seed. First lake cleared around 2 to 3 hours. First rocket around 4 to 6 hours.
- The allocation juggle must stay meaningful the whole game: the balance simulator should confirm that no single fixed allocation is optimal for long, and that the best allocation shifts from cleaning toward planting and watering as junk runs out.
- 100% planet around 40 to 80 hours of mixed active and idle play. Postgame content beyond that.
- There must never be a period longer than about 3 minutes of active play without a new purchase, a new discovery, or a visible world change.
- Offline progress: robots keep working while the game is closed at a reduced rate (start at 50%, upgradeable), capped at a time limit (start 8 hours, upgradeable), using each hub's current allocation and Allocation Rules. On return, show a "While you were away" summary with numbers, any bottlenecks that formed (for example "120 hexes cleaned and waiting for planters"), and a mini time-lapse of changed regions on the globe.

---

## 11. Hubs and rockets

### 11.1 Hubs

- The planet has around 12 to 20 **hub sites**, one or more per biome, built on old Maker stations found in ruins. The first is the Junkyard Hub.
- Each hub has: a Depot, a Workshop, a Hub Upgrade Board, storage, a power grid, and a Hub Level (1 to 10). Leveling a hub (with Cubes, Bolts, and Memory Shards) expands its region of influence, unlocks building slots, and visibly upgrades the hub itself: a rusty shack becomes a cozy workshop, then a greenhouse complex, then a beautiful garden station with windmills and a launch pad.
- Each hub runs its own automation for its area: robots, conveyors, processors, sprinklers. Part of the fun is setting up a new hub efficiently using everything you have learned, with blueprints you can copy from earlier hubs (a **Blueprint Copier** unlock that saves a hub layout and lets you paste it).
- Hubs keep working while you are elsewhere. The globe view shows every hub's status, output, and restoration percent.

### 11.2 Rockets

- Unlocked in Act 5 after restoring an old Maker launch pad in a ruin. The first rocket is a hilarious rusty tube built from junk (it wobbles, smokes, a hatch falls off on launch).
- Rocket travel: choose a destination hub on the globe, launch with a big satisfying sequence (countdown beeps, rumble, smoke, liftoff), the camera pulls up and shows the curve of the planet and your restored areas from above, then a short suborbital arc and a bouncy landing. Keep the flight short (about 10 to 20 seconds, skippable after the first few times) because it is fast travel.
- Rocket upgrades: range, speed, landing precision, cargo bay, fuel efficiency, cosmetics (paint, fins, trail colors, a confetti landing).
- **Cargo Rockets** automate shipments of resources between hubs on schedules, a late-game logistics layer. Watching your rockets arc across the globe view is a key visual payoff.
- Late game: a small **Orbital Platform** near the Cradle that gives a full planet view and access to planet-scale upgrades.
- Rockets unlock exploration: some ruins and islands can only be reached by rocket.

---

## 12. Ruins and exploration

- Ruins are hand-designed points of interest placed on the generated planet (use a set of prefab ruin scenes snapped to suitable hexes). Aim for at least 40 ruins of various sizes: a laundromat, an arcade on the pier, a school, a greenhouse, a museum, an observatory, a radio tower, a toy factory, a robot factory, a dam, a subway station, a stadium, an underwater mall, a crashed airship, a library, a weather station, the Old Capital tower.
- Ruins are partly buried and must be cleaned to enter, which ties exploration to the core loop. Cleaning the entrance and watching the doorway emerge is satisfying.
- Inside: light puzzles (restore power to a door, push a cart, align mirrors to beam light to a sprout, water a dried-up indoor garden), Memory Shards, blueprints, rare parts, seeds, cosmetics, and easter eggs.
- The map shows "?" markers for detected but unexplored ruins once you have a Scout Drone or Scanner upgrade. Exploring should always feel rewarding: every ruin gives at least one guaranteed meaningful reward.
- Ruins stay as ruins after the region is restored, but become overgrown and beautiful, with flowers in the windows and birds on the rooftops. They are monuments to the old world, not removed.

---

## 13. Easter eggs (each one has a reason to exist)

Every easter egg must be tied to the lore or the world, give a small reward (a Trinket, a cosmetic, a WREN line, a hidden research node, or a music track), and be logged in the **Curiosities** section of the Codex with a silhouette until found. Aim for at least 40. Starter list:

1. **The First Flower.** The wildflower from the opening never gets cleaned away. If the player visits it at every act, it grows, eventually becoming the giant tree at the ending. Visiting it after a long absence gives a WREN line.
2. **Gus the Snail.** A tiny snail lives in the Junkyard. If you avoid scooping it for the first 10 minutes, it climbs onto Patch and rides on his head forever after (toggleable cosmetic). Lore: Makers' kids kept snails as pets; a note in the school ruin mentions "Gus."
3. **Mixtape Collection.** 12 cassette tapes hidden in ruins. Each unlocks an original music track playable on a jukebox in your hubs. Lore: an old robot DJ's collection. Finding all 12 unlocks a dance emote.
4. **Rubber Duck in Every Lake.** One golden rubber duck per lake, visible only once clarity is high. Collect them all for the "Quackmaster" hat. Lore: a duck factory ruin explains a cargo spill centuries ago.
5. **The Lost Sock Mystery.** Single socks appear all over the world. The laundromat ruin contains a note about a missing sock. Collect 100 socks and a hidden room in the laundromat opens with the matching pairs and a joke ending.
6. **The Ledger's Coupons.** The Ledger occasionally sends absurd "offers" through the radio ("pause operations today and receive 0% off"). Collecting all its coupons unlocks a secret dialogue where it admits it was lonely.
7. **The Old Arcade.** On the Neon Coast pier, a working arcade cabinet runs a tiny playable mini-game (an original retro cleanup game). Getting a high score unlocks a cosmetic. Entering the classic up, up, down, down, left, right, left, right, B, A sequence on the title screen turns all cubes into tiny cakes for a session (cosmetic only).
8. **Previous Patch.** In the robot factory ruin there are hundreds of deactivated robots identical to Patch. One of them has a name tag and a diary. WREN goes quiet. It reveals Patch was special: the only one with a flower sticker. Big emotional optional beat.
9. **Message in a Bottle Chain.** Bottles in lakes contain notes from two Makers writing to each other across the sea. Collect them in order to read a love story that ends with coordinates to a hidden garden.
10. **The Weatherman.** A broken weather robot at the weather station gives wrong forecasts every day. Repair it with a Legendary part and it gives correct ones (actual gameplay hints about rain events that boost growth).
11. **Dev Room.** A tiny hidden room with notes from the "dev team" (write it as the AI developer's room: notes about building the game), reached by stacking cubes high enough on a specific cliff.
12. **One Millionth Cube.** The 1,000,000th cube is golden, plays a fanfare, and can be displayed on a pedestal in your hub.
13. **Moon Talk.** On some nights, with enough sky clarity, pointing Patch's lens at the moon for 30 seconds plays a faint radio message from a "sweeping crew" far away (an affectionate wink at moon cleaning, no names or references to any real product).
14. **Potato Patch.** A secret seed variety bred from two specific plants grows a single enormous potato. If you water it 100 times, a robot peels it with exaggerated care and WREN says something deadpan. (An affectionate wink, original content only.)
15. **Constellation Map.** Stars visible after the haze clears form Maker constellations; aligning the observatory telescope to each unlocks lore about the Makers' myths.
16. **Shy Robot.** A rare wandering robot that runs away when approached. Cleaning near it without looking at it slowly earns its trust; eventually it joins your fleet as a unique helper.
17. **Birthday.** The game notices the real date of the player's first launch each year and WREN throws Patch a small birthday with confetti.
18. **Rust Never Sleeps.** If the player tries to remove all rust with the Rust Slider 10 times, WREN gently insists Patch is perfect as he is and gives a "Proud Rust" sticker.
19. **Echo Canyon.** Beeping in the canyon plays your robot's beep back as a little melody; certain melodies open a cave.
20. **Garden Gnome Army.** Gnome statues hidden in ruins; placing all of them in one hub garden makes them do something silly at midnight.

Add more of your own in the same spirit, each with a lore reason, a reward, and a Codex entry. Write all of them in `docs/LORE.md`.

---

## 14. Showing progress: visual and in numbers

This is a core pillar. The player must be able to see progress three ways.

### 14.1 In the world

The restoration shader, wildlife, sky color, weather, music layers, overgrown ruins, hub building upgrades, and robot activity (section 5.4).

### 14.2 The Globe

- A full 3D globe view (open with a key or button) showing the real planet state: every hex colored by state (junk, clean, revived, restored, water clarity), hub icons, robot heat maps, ruins and "?" markers, rocket routes, weather.
- Smooth spin and zoom with the mouse or stick; click a region for details and fast travel options.
- A **Time-lapse** button that replays the planet's restoration from the first hex to now (record a planet snapshot every in-game milestone or every few minutes into the save, compressed). This is a huge payoff moment and a shareable clip generator.
- **Before and After** photo mode: Patch can take photos, and every restored region automatically stores a "before" snapshot so the player can compare.

### 14.3 In numbers

- HUD: Cubes (big number with rate per second), planet restoration percent with two decimals early and more decimals for very small numbers at the start (show 0.0003% so even the first hex visibly moves the number), current region percent, and a compact notification feed.
- **Stats Screen** (a satisfying ledger, with a nod to the Ledger): total junk removed by type and weight, cubes made, perfect cubes, hexes cleaned, plants grown, trees planted, lakes cleared, liters of water purified, animals returned, robots built, distance traveled, rockets launched, time played, and per biome breakdowns, with line graphs over time (cubes per second, restoration percent over time, and the Workforce Shift graph of Clean, Plant, and Water allocation).
- **Milestones** with clear rewards: 1 hex, 10 hexes, 100, 1,000, 10,000; first region; every 1% of the planet; each biome fully restored.
- **Achievements**: 80 or more (Steam Achievements later), including hidden ones for easter eggs.

---

## 15. Juice, feel, and audio

### 15.1 Juice checklist (apply everywhere)

- Squash and stretch on Patch, cubes, robots, and buttons.
- Particles for every action: junk sparkles, dust puffs, cube steam, soil spray, water droplets, petals, bubbles.
- Floating numbers for value gained that drift and fade, with bigger numbers for bigger events and combos.
- Screen shake (subtle, optional) on cube crunches and launches.
- Rising pitch on rapid repeated actions (scooping many items in a row climbs a cheerful scale).
- Cube towers wobble; a tall tower that falls is funny, not punishing (cubes bounce and stay collectible).
- Controller rumble on cubing, launches, and big moments.
- UI elements pop and bounce in; upgrade purchases have a satisfying chunky click and a shine.
- Slow motion for a fraction of a second on big milestone moments (first hex clean, first sprout, first lake clear).

### 15.2 Audio

- Procedural-feeling SFX: create or source royalty-free, CC0 sounds (record the source and license of every asset in `docs/CREDITS.md`). Every core action needs at least 3 variations to avoid repetition.
- **Layered adaptive music**: one main theme with stems that join as the planet heals: a lonely music box melody at the start, then soft percussion, then strings, then a warm full arrangement at the end. Each biome has its own instrument color. Use Godot's AudioStreamInteractive or synchronized streams to crossfade layers. If original music cannot be composed with available tools, build the adaptive system with placeholder CC0 music and document exactly where to drop in final tracks.
- Patch and robots speak in beeps (pitch varies by robot), WREN speaks in text with a soft synthesized blip per character (Animal Crossing style blips are fine as a general technique; the sounds must be original).

---

## 16. Art direction: bright and colorful

- **Stylized, colorful, chunky low-poly** with soft toon shading (custom shader with 2 to 3 light bands and a gentle rim light), clean silhouettes, and saturated colors. Think toy-like and warm.
- Color script: junk world is busy and colorful (orange, teal, pink, violet); restored world is lush and vivid (greens, sunny yellows, sky blues, flower pinks). The violet haze tints everything early, and lifts over time.
- Create models procedurally in Godot where reasonable (CSG or code-built meshes for cubes, simple junk, conveyors, hub parts) and use CC0 low-poly packs (for example Kenney or Quaternius) for variety where they fit the style. Recolor everything to the game's palette. Log every asset and license in `docs/CREDITS.md`.
- Patch must be designed with care: an original, appealing silhouette (boxy body, chunky treads, one big round eye, antenna bulb, mismatched bolts, rust patches, a flower sticker). Make a turnaround screenshot and iterate until he is clearly cute.
- Lighting: warm sun, soft ambient occlusion, light bloom, gentle fog tied to the haze level, golden hour sunsets. Day and night cycle with cozy hub lights at night.
- UI: rounded, chunky, bright, readable, with rusty metal panel frames that become nicer as hubs upgrade. Large fonts, high contrast, colorblind-friendly state indicators (patterns plus colors on the globe).

---

## 17. UX, accessibility, and settings

- Keyboard and mouse plus full controller support (Steam Deck friendly), with a basic touch scheme kept working for future mobile (section 4.5).
- Remappable controls; hold-to-toggle options for scooping; auto-cube option.
- Text size, colorblind modes, screen shake toggle, reduced motion, flashing reduction, subtitle options for WREN, separate volume sliders.
- Number format options (short suffix, scientific, engineering).
- A gentle, diegetic tutorial delivered by WREN and Patch's head tilts, never a wall of text. Every new system gets a short WREN introduction and a highlighted first action.
- Codex: Robots, Parts, Plants (Seed Codex), Biomes, Memory Shards, Curiosities (easter eggs), Achievements.
- Pause menu with a "where was I" summary of current goals.

---

## 18. Saves and offline progress

- Autosave every 60 seconds and on important events, plus manual save, multiple save slots, and Steam Cloud friendly files in `user://`.
- Save format: versioned (with migrations for older versions), compressed. Hex data stored compactly (packed arrays of bytes per hex property), not as giant dictionaries.
- Offline progress: compute from the saved timestamp using the data simulation (not by running thousands of ticks; use aggregated rates per hub with sensible caps). Show the summary screen on load.
- Write unit tests for: save then load equals the same state, migration from previous version, offline progress math, BigNum math and formatting.

---

## 19. Performance targets

- 60 FPS on mid-range hardware at 1080p in a busy hub with 200 or more visible robots and thousands of junk items.
- Use MultiMesh for junk, plants, wildlife, and distant robots. Use LOD and visibility ranges. Simulate far robots in data only. Use object pooling for particles and floating numbers.
- Profile with Godot's profiler at each milestone and record frame times in `docs/PROGRESS.md`.

---

## 20. Postgame: Cradle Mode (prestige and replayability)

After the Greenfall ending, the game continues:
- **Cradle Mode**: WREN reveals the Cradle holds seeds for other worlds in the system. Unlock **Seed Missions**: launch to new, smaller planets (an ice moon, a desert world, an ocean world with tiny islands) that each restart the loop with a twist and permanent **Heirloom** upgrades carried between worlds (faster start, starting robots, cosmetic heirlooms). This is the prestige layer: you never undo Verdance; you take what you learned to new worlds.
- **Garden Mode** on Verdance: decorate the restored planet, build gardens, place statues, collect every seed variety, find every easter egg, and complete the Codex.
- Each new world has its own short story thread with WREN.

---

## 21. Milestones and acceptance criteria

Build in this order. Do not move on until the acceptance criteria pass and screenshots look right.

**M0: Setup.** Godot project, folder structure, autoloads, test framework, screenshot tool, git repo, docs. Acceptance: tests run headless, a blank scene screenshot saves.

**M1: The Slice (most important).** A small flat test area with colorful junk, Patch with movement, scooping, cubing (with Pure and Perfect cubes), carrying, a Depot, cubes currency, 3 upgrades, juice on everything. Acceptance: it is genuinely fun to play for 10 minutes. Record a clip. If it is not fun, fix feel before anything else.

**M2: The Planet.** Hex sphere generation, biomes, chunking, gravity, restoration shader with the hex flip moment, hex completion bonus, globe view. Acceptance: walk across multiple regions without stutter; the globe shows correct cleaned hexes.

**M3: Robots.** Parts drops, blueprints with part slots, workshop, Scoopie, Haul Bug, Sorter, fleet-wide bot upgrade tracks, the Parts Trade Depot with Haggle, the full upgrade UI from section 10.3, conveyors, a simple processor, power, fleet panel, robot customization. Acceptance: a fully automated cube line runs while the player explores, a missing part can be traded for at the Depot, and buying upgrades feels great on keyboard, mouse, and controller.

**M4: Story foundation.** WREN dialogue system, first Memory Shards, first 3 ruins, Act 1 and Act 2 beats, opening cutscene with the first flower. Acceptance: a new player understands the goal and cares about WREN within 15 minutes.

**M5: Growing and Allocation.** Seeds, soil revival, compost, planting, watering, growth stages, Seedling, Drip, Sprinkler, Multibots, the Allocation Board with Clean, Plant, and Water jobs, wildlife, sky haze changes. Acceptance: a region goes from junk to restored meadow with animals, entirely visible on screen, and the player has to shift robots from cleaning to planting and watering to get there.

**M6: Water.** Lakes, clarity shader, raft and boat, aquatic robots, irrigation links. Acceptance: clearing a lake triggers the big moment and feeds sprinklers in a nearby region.

**M7: Hubs and Rockets.** Multiple hubs, hub levels and visual upgrades, blueprint copier, rocket launch and flight, cargo rockets, Research Tree. Acceptance: travel by rocket between three hubs, each with its own running automation.

**M8: Content pass.** All biomes, 40 or more ruins, the full story through the ending, at least 40 easter eggs, Codex, achievements, cosmetics, stats screen, time-lapse, photo mode.

**M9: Balance pass.** Run the balance simulator and the autoplay bot across the whole game; hit the pacing targets in section 10.2; write results in `docs/BALANCE.md`.

**M10: Polish.** Audio and music layers, accessibility, settings and quality tiers, performance targets, save migrations, zero errors in the log, a title screen with Patch and the first flower, credits. Steam build ready (Windows and Linux exports). Mobile check: the project builds for Android, runs on the Mobile renderer at the Low tier, and is fully playable with touch controls, even if not yet tuned for phones.

**M11: Postgame.** Cradle Mode with at least one additional world and the Heirloom system, Garden Mode.

After each milestone: run all tests, run the autoplay bot, capture screenshots and a short clip, update `docs/PROGRESS.md`, commit, and tag.

---

## 22. Definition of done

- The game is playable from the opening to the Greenfall ending and into the postgame without soft locks.
- Every hex on the planet is restored by the player's own cleaning, planting, and watering labor, and juggling the workforce between those three jobs stays a fun decision from Act 3 to the end.
- It is bright, colorful, and cozy from the first frame.
- Manual play feels tactile and satisfying; automation feels like an earned relief; the world visibly heals.
- The story makes players care about WREN, Patch, and the planet.
- Progress is visible in the world, on the globe, and in numbers.
- Easter eggs are fun to find and all have a reason to exist.
- All content and assets are original or properly licensed and credited.
- Tests pass, the log is clean, performance targets are met, and the docs explain how to build, run, and extend the game.

Start now: read the project folder, check the Godot version, write `docs/PLAN.md`, and build M0 and M1.
