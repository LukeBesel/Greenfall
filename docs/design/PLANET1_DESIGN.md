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
