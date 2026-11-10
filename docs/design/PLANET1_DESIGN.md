# Planet 1 design spec

The rules behind `docs/PLAN.md` section 4, written for the agents who build them (task M1-02). Every number here is a starting value that lives in the planet's data and is tuned by the simulator (task M3-01). Shared code implements the rules; the planet's tables supply the content.

Terms: a **hex** is one cell of the globe (about 10 m). A **district** is the ring of hexes round one hub site. **Stage** means a regrowth stage of a hex or a district.

## 1. Districts (table `districts`)

A planet lists its districts in play order. Each one is a chapter.

```json
{"districts": [
  {"id": "old_town", "site": 0, "rings": 6, "pollution": ["litter"], "introduces": "litter",
   "source": "burst_main", "unlock": {"type": "start"}},
  {"id": "scrapyard", "site": 1, "rings": 8, "pollution": ["litter", "wrecks"], "introduces": "wrecks",
   "source": "crusher_stack", "unlock": {"type": "district_stage", "district": "old_town", "stage": 4}}
]}
```

- `rings` sets the size: a district has `1 + 3·r·(r+1)` hexes. Planet 1 starts at 6 rings (127 hexes) and grows to 16 (817) by district 6, about 2,600 hexes in all. Today every hub region is a fixed 18 rings (1,027 hexes), which is why early progress reads as 0%.
- A district's **stage** is the lowest stage reached by at least 80% of its land hexes (`stage_share`, tunable). Stages are the regrowth stages in section 5.
- **Unlock:** the next district opens when the current one reaches stage 4 (sustained), not 5. The player can move on early and finish the last stage with the crew, which keeps momentum.
- **Travel:** the rocket hop to the next hub exists already. The first hop to a district is a short arrival moment; after that it is instant from the map.
- Sites not listed in `districts` are **open ground**: optional, no source, and they count only toward full completion.
- The HUD shows the current district's stage and share (for example "Old Town · Growing 62%"), never a planet figure with decimals.

Events: `district_unlocked(id)`, `district_stage_changed(id, stage)`, `district_entered(id)`.

## 2. Pollution kinds (table `pollution`)

A kind is a family of waste with its own look, handling and payout. Planet 1 has five.

| Kind | District | What it is | Tool gate | Existing system it builds on |
|---|---|---|---|---|
| `litter` | 1 | Loose trash | none | Sweep, bin, baler |
| `wrecks` | 2 | Heavy items: appliances, tyres, car shells | Lift tier, then the cutter | Lift classes, large pieces, landmarks |
| `slick` | 3 | Fouled water: floating waste and scum | Hover drive, skimmer head | Lake hexes, skimming |
| `smog` | 4 | Foul air over a hex: stunts growth until cleared | Scrubber units | The recycler's air effect, sky haze |
| `blight` | 5 | Poisoned soil: nothing grows | Cleansing plants | Planting, hex stages |

```json
{"kinds": {
  "wrecks": {"name": "Wrecks", "tool": "lift", "tool_tier": 2, "yield": {"cubes": 1.8, "parts": 2.5},
             "mastery_per_unit": 1.0, "spawn": {"density": 0.35, "cluster": 0.6}}
}}
```

- A district's hexes roll their waste from the kinds it lists. District 6 lists all five.
- A hex is **clean** when every kind on it is cleared. The 95% rule stays: at 95% cleared by volume the rest is swept away.
- A kind the player cannot handle yet is shown clearly on the piece and in the prompt ("Too heavy: needs Lift II"), never hidden.
- Adding a kind is data plus, at most, one small handler script named in the table.

Events: `pollution_cleared(kind, amount, by_player)`.

## 3. Mastery and apprentice robots (tables `pollution`, `robots`)

- Each kind has a **mastery** level 0-10 for the planet. Only Lumi's own work fills it (`pollution_cleared` with `by_player`).
- Mastery gives Lumi a rate bonus on that kind: `1 + 0.08 · level`.
- A robot type lists the kinds it can work. A robot **cannot work a kind below mastery 1**. Its speed on a kind is `base · (0.4 + 0.12 · level)`, so a crew is weak at mastery 1 and strong at 5 and above.
- **Proximity:** a crew working within 80 m of Lumi gets +25% ("working alongside"). Far crews still work.
- Mastery thresholds follow a gentle curve (first level after about 2 minutes of hand work on that kind; level 5 after about 20).
- Rule the simulator enforces: Lumi's own share of all cleaning output never falls below 30%.

Events: `mastery_gained(kind, level)`.

## 4. Sources (table `districts`, scripts in the planet folder)

Each district has one **source**: the thing still polluting it. Until it is shut down, hexes in the district cannot pass stage 3 (growing), and a slow trickle of new waste appears near it.

- A source is a 3-step job only Lumi can do, each step using what the district taught: reach it, clear its surroundings by hand, then a short hands-on action (cut, cap, drain, start, plant).
- Shutting it down is the district's set piece: a large payout, the district's power spike (a rig slot or a tool tier), and a visible change in the district.
- Sources are scripts in `planets/<id>/sources/` behind one interface: `steps()`, `step_done(i)`, `on_complete(world)`.

Events: `source_step_done(district, step)`, `source_shut_down(district)`.

## 5. Regrowth stages and tending (table `regrowth`)

The five existing stages stay: clean, planted, growing, sustained, thriving.

- Growth is pushed by play. Watering a hex gives an immediate growth burst; a watered hex grows at full rate for 3 minutes, an unwatered one at 25%.
- Planting by hand plants a patch (several plants at once) so a hex takes a few actions, not dozens.
- Each stage change pays out and has its own look and sound, larger at higher stages.
- No stage requires waiting with nothing to do: with tending, a hex can go from clean to growing in about 2 minutes.

## 6. Research from field work (table `research`)

- Research nodes cost stock (cubes, parts) and **field data**, not time.
- Field data comes from play: cleaned hexes, mastery levels, stage changes, finds, sources. Each node shows a progress bar that fills as the player works.
- At most one node is active; switching keeps progress.
- Offline time adds no research.

## 7. Upgrades and rigs (tables `upgrades`, `rigs`)

- **Tracks** (existing): linear levels that amplify a stat. Costs grow by a fixed ratio inside a tier; each district opens a new tier.
- **Rigs** (new): three slots on Lumi (arm, chest, drive). One module per slot, swapped at the bench at no cost. Modules are found in the world or built from parts. Each shows on the model.

| Slot | Example modules | Trade-off |
|---|---|---|
| Arm | Wide Sweep / Long Reach / Heavy Claw | area, range or lift |
| Chest | Deep Hold / Press Frame / Sorter | capacity, bale value or parts yield |
| Drive | Sprint Coils / Hover Skirt / Tow Hitch | speed, water crossing or carrying more bales |

```json
{"slots": ["arm", "chest", "drive"],
 "modules": {"wide_sweep": {"slot": "arm", "mods": {"scoop_width": 1.6, "scoop_reach": 0.8}, "source": "find:old_town"}}}
```

No module may be best in every district; the simulator checks this.

## 8. Surge (table `balance`)

- Sweeping, pressing and tending by hand charge the Bloom Core. Robots do not.
- At full charge the player releases a **Surge**: for 12 seconds Lumi's sweep widens and speeds up sharply (at least 3x output). From district 4 it also pushes a wave of growth across nearby hexes.
- Charge time is about 4 minutes of steady play; upgrades shorten it.
- The existing Bloom Core meter is its gauge.

## 9. Restoration and the ending (table `restoration`)

```json
{"weights": {"per_district": "equal"}, "stage_values": [0, 0.25, 0.45, 0.65, 0.85, 1.0],
 "ending": {"when": "all_districts_stage", "stage": 5, "sequence": "bloom"}}
```

- Planet restoration is the mean of its districts' values, where a district's value comes from its stage and share. Nothing outside the planet affects it.
- When the last district reaches stage 5 (thriving), `planet_restored` fires once. The planet's ending sequence plays (Planet 1: the Bloom, where green spreads from every district over the whole globe), then the end screen with session stats and the hook.
- After the ending the player keeps playing: open ground, finds and full completion.

Events: `planet_restoration_changed(value)`, `planet_restored(id)`.

## 10. Goals (table `goals`)

Three tiers are always active, each generated from state, not from a fixed chain:
- **Now** (under 3 min): finish this hex, fill this bale, afford the next fit.
- **District** (10-20 min): the district's next stage, its source step, the next mastery level.
- **Planet** (hours): districts restored out of six.

Authored one-off goals (story beats, firsts) slot into the "now" tier when their trigger fires. The existing goal list is cut down to those.

## 11. What is cut or parked for Planet 1

Decided in task M3-13 after the loop is rebuilt; current leaning:
- **Parked:** the requests board, world events that hand out rewards from nowhere, the weekly seed, the museum, the antagonist arc beyond a light story thread, real-time research.
- **Kept and trimmed:** WREN's story lines, buried finds, song finds, wildlife, photo mode, the character builder.

## 12. Pacing targets by district (starting values for the simulator)

| District | Hexes | Player time in district | Crew at the end | Hand share |
|---|---|---|---|---|
| 1 | 127 | 50 min | 3 | 70% |
| 2 | 217 | 30 min | 6 | 50% |
| 3 | 331 | 30 min | 10 | 45% |
| 4 | 469 | 35 min | 14 | 40% |
| 5 | 631 | 35 min | 18 | 35% |
| 6 | 817 | 45 min | 24 | 30% |

Lumi's hand rate grows from about 1 hex per 2.5 minutes at the start to about 4 hexes a minute by district 6 (tracks, rigs, mastery, Surge).

## 13. Looks: found pieces and the Locker (owner, Nov 9)

Owner's rules: all six designs look exactly like the concept sheet, whole robot, not only the eyes. New designs and cosmetics are **rare and hard to get**. You **find items in the world** to unlock what you can wear. A **Locker** is a place you build, where you design your bot from what you have found.

### The fiction
The six designs are six old robot models that once worked on this planet. Their wrecks and spare parts are still out there under the trash. Lumi salvages pieces and can wear them.

### Pieces
- Every look is made of **pieces**, one per slot: paint set, wear pattern, eye shape, glow colour, head piece, ear lenses, shoulders, chest plate, held item, hip item, companion. A design (Bolt, Sprout, Pixel, Nova, Patch) is a **set** of 6 to 8 pieces.
- A piece can be worn only after it is found. Nothing cosmetic is bought, and nothing unlocks from a counter (the old "press 50 bales" style rules are removed).
- Unfound pieces show in the Locker as a dark silhouette with "???" and one hint line about where that kind of thing turns up ("Old machines rust in the scrapyard").
- Wearing a complete set shows the set's name and gives its small bonus. Mixed looks give no bonus, so looks are a free choice.
- Pieces are **global progress**: they stay with the player across planets. Where they are hidden is planet data.

### Where pieces are found (table `finds` in the planet folder; piece list in `data/cosmetics.json`)
| Source | What it gives | Rarity |
|---|---|---|
| Paint tins and lens chips buried in ordinary hexes (the detector helps) | single colours, glow colours | uncommon: about one per 40 hexes |
| A robot wreck, hidden off the main path in some districts | 1-2 pieces of the planet's design | rare: needs exploring and hand-clearing |
| Shutting down a district's source | 1 piece of the planet's design, in some districts | once per district at most |
| Secrets and open ground | extra colours, a companion | very rare |

```json
{"finds": [
  {"piece": "head_cat_ears", "where": "wreck", "district": "smogworks"},
  {"piece": "paint_bolt", "where": "source", "district": "scrapyard"},
  {"piece": "swatch_teal", "where": "buried", "chance_per_hex": 0.025}
]}
```

### Pace (the simulator and the bot check these)
The first planet is only the beginning (owner, Nov 10). It must not hand out the collection.
- The player starts as Aurora. **Exactly one new design can be completed on Planet 1: Sprout**, the restoration-themed set. Its pieces are spread across the districts, and the last one comes from the final district, so the set completes near the ending.
- **Bolt, Pixel, Nova and Patch belong to later planets, one per planet.** Their pieces are not placed on Planet 1. At most, one wreck of a later design can be seen as a tease that cannot be salvaged yet ("Too far gone. Maybe somewhere else.").
- Loose finds on Planet 1: about 8 colours and glow tints in total.
- First piece (a colour): about minute 25. It triggers the "Build a Locker" step.
- A found piece is a moment: a short reveal on Lumi, the piece named, and a pointer to the Locker.
- Which designs a planet offers is that planet's data (`finds` table), so later planets add theirs without code.

### The Locker
- A build in the yard (a tall salvaged steel locker with a small turntable), offered after the first piece is found.
- Using it puts Lumi on the turntable with the camera orbiting; the panel lists the slots, found pieces first.
- It is the only place looks are edited: Lumi, the lantern companion and the crew's robots (one look per robot type).
- Saved looks: three presets.

Events: `piece_found(piece_id, source)`, `set_completed(design_id)`, `look_changed()`.

## 14. Economy scale, parts and the crew (owner, Nov 10)

Owner's rules: pacing is the most important thing. Currency numbers must not get high quickly. Currency must make sense. Parts are hard to get at the start. Robot building and upgrading must be paced. Long term, a robot type that finds parts.

### Scale: small numbers that mean something
- Planet 1 is the beginning, so it stays in small numbers. Later planets go higher.
- A plain bale sells for **tens of cubes**. First upgrades cost tens; district 1 tops out in the low thousands; the most expensive single purchase on Planet 1 is **under 50,000 cubes**.
- Income never jumps by more than about 3x from one purchase or unlock, and goal rewards never arrive in bursts: a goal pays when it completes, and a reward is never worth more than about 3 minutes of current income.
- Prices rise because the player moved to a harder district with richer waste, not because of compounding multipliers. Multipliers are few and additive where possible.
- All numbers shown to the player are whole and under 6 digits on Planet 1. No "k/M" abbreviations should be needed before the last district.
- Tipping loose trash in the bin never out-earns pressing a bale.

### One job per currency
| Currency | Comes from | Pays for |
|---|---|---|
| Cubes | selling bales at the scale; stage payouts | Lumi's upgrade tracks, base levels, builds |
| Parts | salvage: buried parts, stripped wrecks, sources | robots, robot upgrades, machines, rig modules |
| Seeds | plants that bloom | planting |
Nothing converts one currency into another at the bench. No reward hands out a currency that did not come from a matching action.

### Parts are scarce at the start
- In district 1 parts come only from Lumi's own hands: buried parts found with the detector (about one per 3 hexes) and the occasional piece worth stripping. A hex yields **0 to 3 parts**.
- The first robot costs parts the player has gathered over about 20 minutes: it is a real achievement, not a purchase.
- District 2 (wrecks) is where parts open up: stripping a wreck by hand yields parts, and wreck mastery lets a robot do it slowly.
- Parts are never the reason nothing can be bought for more than 4 minutes: the simulator checks parts waits as well as cube waits.

### The crew: few robots, each one a decision
- Planet 1 ends with a crew of **about 10 to 12 robots**, not dozens. The crew cap rises with base level.
- Robot tiers on Planet 1: **rusty** (as salvaged) and **repaired**. Higher tiers are for later planets.
- Building and upgrading both cost parts, so the player chooses: one better robot or one more robot. Upgrades show on the robot.
- Unlock order on Planet 1: cleaner (about minute 20), hauler (district 2), skimmer (district 3), planter and waterer (districts 3-4), and late in district 5 the **Scrounger**.
- **Scrounger (parts-finding robot).** One unit on Planet 1. It roams cleaned ground near Lumi, sniffs out buried parts and plants a marker; Lumi digs them up. It finds, the player collects, so hands stay the engine. A later-planet version that digs and carries is noted in `docs/FUTURE.md`.

## 15. The world: cities under junk (owner, Nov 10)

Owner's rule: full cities around the planet, full of junk, with clear world goals.

- Each of the six districts is a **full city of its own character** (the existing kinds: old town, downtown, industrial, harbour, suburb, plus one more), not a few buildings: streets, blocks, signs, landmarks and a skyline, all buried in junk at the start.
- Each city has a **landmark tied to its source** (for example a leaking treatment works, a smoking stack, a crusher yard) that is visible from across the district and changes when the source is shut down.
- The land between cities is junk fields, outskirts and industrial edges, never empty ground. From the map the whole globe reads as covered.
- A district's regrowth stage changes the city itself, not only the ground: lights come back, signs are readable, water runs clear, trees line the streets, animals move in.
- **World goals** are stated in the world's terms and shown on the map: "Old Town: Growing 62%", "Shut down the burst main", "4 of 6 cities restored". The map shows each city's state at a glance.
- Budget: every city must hold the performance budgets on the Low preset; buildings and furniture are batched as today.
