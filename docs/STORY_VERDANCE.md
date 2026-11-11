# The story of Verdance (first planet)

Owner items 58, 60, 61, 63 and 64: the player leaves Verdance after 4–5 hours, with about 20% of it
clean and about six of its bases seen, and every single thing they are asked to do has a plain
reason that the game itself says. This page is the reference for that. Text lives in
`data/objectives.json`, `data/goals.json` + `data/goal_reasons.json`, `data/wren_lines.json`,
`data/homeward.json` and the story scripts; the test `tests/test_story_reasons.gd` fails when a step
has no reason.

Status key in the tables: **ok** (the game says it), **fixed** (v6story changed the text),
**in game** (the step exists and says it; who built it is named).

## The story in one page

**Verdance** was the Settlers' home: towns, gardens, a blue sky. A machine company called **the
Ledger** dug up every world around the two suns and left its trash behind. When the air went bad,
the Settlers packed the last seeds into a big ship, the ark **Cradle**, and went to sleep on board.
They left their cleanup robots running, in little **cleanup stations** in every town: a workbench,
a trash bin with a recycler, a scale and a landing pad. The plan was to come back and plant when the
world was clean. They called that day the **Greenfall**.

Name: the ark's people are **the Settlers** (one Settler; "Settler tech"). The owner turned down "the
Makers" and "the Gardeners" (2026-11-11). Ids, flags and save keys still say `maker` (`maker_shell`,
`builder_maker`, `maker_fragments`, `maker_badge`) so old saves load; only the shown text changed.

It never came. The Ledger did its sums, decided that cleaning "costs more than it earns", and paused
every robot. Three hundred years went by. The stations fell silent and the trash stayed.

**Lumi** (LM-1) is the Cradle's small seed-keeper robot. He sings to the seedlings. **WREN** is the
Cradle's mind: she flies the ship and has looked after Lumi all that time. One night a meteor storm
tears the seed vault open. Lumi climbs into a pod to save a tray of seedlings, and the pod falls all
the way down to Verdance. **Glim**, a little lantern bot, holds on to the outside the whole way.

Lumi wakes next to one of the old cleanup stations, with his battery at 4%. His **Bloom Core** runs
on green light, the light living plants give off, and nothing green is left.

So the plan, in the order the game teaches it:

1. **Trash becomes cubes.** The station's bin still works: its recycler turns trash into **cubes**,
   small clean building blocks. The workbench builds everything out of cubes. A small thing takes a
   few; a big machine takes a great many, and a rocket takes a mountain. That is why prices climb.
   Trash pressed into a tight **bale** recycles with nothing wasted, so a bale gives far more cubes.
2. **A tower, so WREN can talk.** Her signal can't reach a dead station. The first thing built from
   cubes is the signal tower.
3. **Clean ground, then plants.** Plants only grow on clean ground. Plants give green light. Green
   light fills Lumi's Bloom Core (so he keeps going), and it is the sign the Cradle looks for from
   space: the ark will not come down to a dead world.
4. **Robots, because a planet is big.** One small robot can't clean a world. The station can build
   helpers again once it has power, and a bigger station powers more of them. Robots also keep
   working when Lumi is somewhere else.
5. **Six stations.** Lumi's little rocket can hop from town to town, but it can't leave the planet.
   When the Settlers left they used every big rocket they had. What is left of the last launch kit sits
   in the landmarks of six old stations: seeds at **Garden Row**, hull plates at **Gantry Works**,
   the star chart at **Signal Heights**, a power cell at the **Fairground**, fuel at **Stack
   Works**. At each station Lumi cleans a little, wakes the landmark, takes its piece for the rocket,
   and leaves a crew of robots there to carry on.
6. **Why fly on with Verdance only one fifth clean.** The star chart at Signal Heights shows the
   truth: the Ledger buried **five** worlds, not one. The Cradle's rule (the Settlers' charter) is
   "wake us when the worlds can feed us", and one green town is not enough. Two more things make
   leaving the right call. First, some of Verdance can't be cleaned with what is here: the tools for
   its buried, flooded and frozen parts were left on the other worlds (the Deep Drill is on Ochre).
   Second, Verdance is no longer alone: six stations are awake, and their robots keep cleaning and
   planting while Lumi is away. Lumi goes on to wake the next world and comes back with better
   tools. When every world is green, the Cradle comes home.

**The Ledger** is not a villain to fight. It is a lonely adding machine that still sends coupons
asking Lumi to stop, and drones that put a little trash back on clean ground (never on planted
ground). Later Lumi and WREN find its relay and show it the sums: clean ground and living plants go
in the "asset" column. It changes sides and its drones deliver seeds.

**Memory shards** are things the Settlers left behind (a shop sign, a child's drawing, a voicemail).
They are how the player learns what happened: found when the hex that holds them is cleaned.

## Every step, in order

"Card" = the objective card's title and its reason line. "WREN" = her one line as the step starts
(only after the first signal tower). Minutes are from a bot run (`--autoplay --clarity-log`).

### A. The crash and the first minutes (WREN silent after her crash message)

| # | What the player does | In-world reason | Where the game says it | Problem / status |
|---|---|---|---|---|
| 0 | Watches the intro | The Settlers left on the Cradle; Lumi fell | story/intro.gd captions | ok |
| 1 | Hears WREN's crash message | The pod fell by an old cleanup station; its bin makes cubes; a tower lets her talk | objectives.json `brief` | **fixed**: it said "pick up trash, find parts" with no word on what the place is or what cubes are |
| 2 | Fixes the workbench | It is the Settlers' bench, dead for 300 years; everything is built on it | checklist (story/tutorial.gd) | **fixed**: the step now says whose bench it is |
| 3 | Picks up trash, empties the chest in the bin | The bin's recycler turns trash into cubes | checklist + card `dump3` | **fixed**: nobody said why a bin pays cubes |
| 4 | Buys a bigger chest, a wider scoop | Carry more, grab more: fewer walks to the bin | cards `compartment`, `scoop_size` | ok. **fixed**: the reason was hidden while saving up (the card showed only "Need N more cubes") |
| 5 | Saves up for the Baler | A tight bale recycles with nothing wasted: more cubes | card `baler` | **fixed**: "bales sell for more" had no why |
| 6 | Recycles 3 bales | Enough cubes to build the tower | card `power` | **fixed**: WREN said "three of them and the base wakes up", then nothing woke up |
| 7 | Builds the signal tower | WREN's signal can't reach a dead station | card `tower` | ok |

### B. WREN is back: the plan

| # | What the player does | In-world reason | Where the game says it | Problem / status |
|---|---|---|---|---|
| 8 | Hears WREN's briefing | Who she is; plants make green light; green light fills the Bloom Core and is the sign the Cradle looks for | objectives.json `wren_brief` | **fixed**: it promised "when it's full, the Cradle comes down and we go home", which is not what happens on Verdance |
| 9 | Repairs Glim | He held on to the pod; he lights the night and spots missed trash | card `glim` + WREN | **fixed** (card gave only where to click) |
| 10 | Cleans the glowing hex, then 2, then 3 | Plants only grow on clean ground; three clean hexes round the station give robots room to start | cards `hex`, `hex2`, `hex3` | **fixed**: "3 clean hexes unlock the Bot Bay" was a game rule, not a reason |
| 11 | Adds a Bot Bay to the bench | A planet is too big for one small robot | card `bench2` + WREN | **fixed** (card gave only where to click) |
| 12 | Builds the first robot, shows it where to clean first | The robot already cleans by itself; painting hexes only tells it where to start. Robots keep going when Lumi is busy | cards `robot`, `zone` + WREN | **fixed**: WREN said "the base has power!" with no cause; the step read as if the robot did nothing until told |
| 13 | Finds the Settler seed tin, plants and waters the first seed | Nothing grows by itself any more; every bloom gives green light and a seed back | story/first_seed.gd (WREN's long scene), card `seed` | ok. The best-told beat in the game |
| 14 | Meets the Ledger's drones | The Ledger thinks cleaning costs too much; drones can't touch planted ground, so planting protects clean ground | story/ledger.gd toasts | ok |
| 15 | Cleans 10 hexes with the robots | More clean ground, more room to plant | card `hex10` | **fixed** (card gave only the key to press) |
| 16 | Rebuilds the base to level 2 | A bigger station makes more power: more robots can run | card `base2` | **fixed** ("the base can grow now" said nothing about why) |
| 17 | Builds a Haul Bug | Robot bales pile up in the streets; a Haul Bug carries them to the scale | research.json `haul_rig` + card `haul` | ok |
| 18 | Boosts the signal tower | A stronger tower lets WREN see further: she can find plans and the next station | card `tower2` | **fixed** ("WREN will sound clearer" is nice but not a reason) |
| 19 | Finishes a research project | The bench studies what Lumi digs up and learns to build it | card `research1` | ok |
| 20 | Cleans 20 hexes | Green light for the core | card `hex20` | **fixed** |
| 21 | Rebuilds the base to level 3 | A stronger base runs bigger machines | card `base3` | **fixed**: "the Cradle is watching" and "opens the Request Board" were not reasons |

### C. Six stations (v6hubs builds the steps, v6pace times them)

One reason carries the whole chain: **the rocket can hop, but it can't leave the planet; each
station kept one piece of the last launch kit, and each one woken keeps cleaning without Lumi.**

| # | Station (landmark) | What the player does | In-world reason for going | What it gives | Status |
|---|---|---|---|---|---|
| 1 | Landing Yard (water tower) | everything in A and B | Lumi fell here | a home, the first crew, the hop rocket | ok |
| 2 | Garden Row (windpump) | cleans a few hexes, wakes the windpump | The seed tin is nearly empty; the Settlers' seed store was at Garden Row | seed stock, so planting never stops | in game (v6hubs; picker line, arrival line and wake toast; card reason `hub_fly_N` in story_reasons.json) |
| 3 | Gantry Works (crane) | cleans, wakes the crane | The hop rocket's skin would burn up in space; the works made hull plates | hull plates (rocket tier) | in game (v6hubs; picker line, arrival line and wake toast; card reason `hub_fly_N` in story_reasons.json) |
| 4 | Signal Heights (radio mast) | cleans, wakes the mast | Nobody knows where to fly; the tall mast kept the Settlers' star chart | the star chart: five buried worlds, and Ochre first | in game (v6hubs; picker line, arrival line and wake toast; card reason `hub_fly_N` in story_reasons.json) |
| 5 | Fairground (ferris wheel) | cleans, wakes the wheel | A long flight needs power that lasts; the wheel ran on a big power cell | a power cell (rocket tier) | in game (v6hubs; picker line, arrival line and wake toast; card reason `hub_fly_N` in story_reasons.json) |
| 6 | Stack Works (smokestack) | cleans, wakes the stack | The tanks are empty; the stack works made fuel | fuel (rocket tier): the rocket can leave | in game (v6hubs; picker line, arrival line and wake toast; card reason `hub_fly_N` in story_reasons.json) |

Two rules of the economy get a reason here too (v6pace's numbers):

- **Each woken station multiplies what trash is worth (x2.5).** The stations were built as one
  recycling network. One recycler alone can only make plain cubes; every station that joins shares
  its sorting machines with the others, so the same trash gives more cubes everywhere.
- **The rocket is upgraded in tiers (Mk II, Mk III) before it can leave.** Every station Lumi wakes
  needs supplies and news carried to it. A small rocket can keep two stations going; a bigger one
  keeps more. The pieces from the stations (hull plates, power cell, fuel) are what each tier is made
  of, plus a great many cubes.

What the game says at each station (v6hubs' steps, v6story's wording):

- *Before the rocket exists* (rocket panel): "The launch pad is still buried. Put your first robot to
  work to clear it."
- *Why go* (rocket picker and the card's reason): one line per station, e.g. "Nobody knows where to
  fly. Signal Heights kept the star chart."
- *On arrival*: the station's own line, e.g. "The fuel works. The tanks under the Tall Stack are
  still full."
- *Clean first*: "Dig the landmark out. Clean hexes here: 3 / 8".
- *Wake it* (costs cubes): "Gantry Crane is awake. Gantry Works keeps cleaning when you fly on.", then
  "Rocket piece: Hull Plates" and "The recycling network grew: everything sells for x2.5 now."
- *Too many stations for the rocket*: "The rocket can carry supplies to 2 bases. Upgrade it at the
  workbench."
- *Coming back*: "Garden Row: 31% clean, up 6% while you were away." (the robots really do carry on).

### D. The exit

| # | What the player does | In-world reason | Where the game says it | Status |
|---|---|---|---|---|
| E0 | Has six stations restored to level 2 | Six crews are enough to keep Verdance going without Lumi; the launch kit is complete | WREN, first line of the exit beat: "Six stations awake, Lumi. Their robots can look after Verdance now." (homeward.json `leave.toast`); before that the map says "Wake 6 old stations on Verdance to level 2 (N so far)" | in game (v6pace gate, v6story text) |
| E1 | Sees the solar map open | The star chart shows five worlds the Ledger buried; the Cradle waits for all of them | WREN, same beat, spoken once: story_reasons.json `exit.system_open` (two lines) | **fixed** (there was no line at all: the map button just appeared) |
| E2 | Builds the Mk V Orbital drive (500K cubes, the biggest price on Verdance) | It is the hop rocket rebuilt for space out of a mountain of cubes | homeward.json drive desc; goal reason "The hop rocket can't leave the planet. A drive can." | **fixed** (the desc was a spec sheet) |
| E3 | Launches to Ochre | Verdance isn't finished and that is all right; some of its trash needs tools left on other worlds; Lumi will be back | WREN `exit.drive_built` (two lines, once) + the Verdance line on the map ("Your robots keep cleaning it while you are away") | **fixed** |

### E. The goal chain after the story steps

Goals come one at a time on the same card. Each used to show only "Reward: N cubes". Now each shows
a reason first, from `data/goal_reasons.json` (by goal id, else by what the goal counts), then the
reward. Examples: clean N hexes ("Plants only grow on clean ground"), buy N upgrades ("Better tools:
more trash per trip"), earn N cubes ("Big machines are built from many cubes"), plant / bloom
("Every bloom gives green light for your core"), Drip robots ("Thirsty plants stop growing"), pet a
cat ("The animals are coming back. Say hello"), memory shards ("The Settlers left these. They tell what
happened here").

## Holes found, and what was done

| Hole | Fix |
|---|---|
| What cubes are, why a bin pays them | Said in WREN's crash message, on the first card and in the Cubes description: the recycler turns trash into cubes; the bench builds with cubes |
| Why bale | Card + Baler description: a tight bale recycles with nothing wasted |
| Why prices climb (owner 63–64) | Cubes description and the drive text: bigger machines are built from more cubes; a rocket takes a mountain |
| Who built the bench, bin, scale, pad | "An old cleanup station" of the Settlers: crash message, checklist, base level 1 text |
| Why "base levels" | Each rebuild gives the station more power: more robots, a better scale, the rocket pad |
| Why cleaning matters to getting home | Briefing: clean ground → plants → green light → Lumi's core, and the sign the Cradle looks for |
| Why robots | Bot Bay card and WREN: a planet is too big for one robot; crews carry on when Lumi leaves |
| Why plant, if we leave | Green light for the core; planted ground is safe from the Ledger's drones; the Cradle counts green |
| Why leave a dirty planet | The exit beat (E0–E3) |
| WREN's step line could come a step late | A step line is dropped unsaid if its step is already done when her turn comes |
| Steps with only a "where to click" line | Each has a reason now; where to click moved behind the reason |
| The reason vanished while saving up | The card keeps the reason and shows the "need N more cubes" hint under it |
| Goals had no reason | `data/goal_reasons.json` + the card |
| Old words | Three upgrade descriptions still called bales "cubes" (an older mechanic); the briefing promised the Cradle lands when the core is full |

## Not changed (and why)

- The first-seed scene, the Ledger arc, the shards and the eggs: already coherent and well liked.
- "Sell" stays as the everyday word for putting a bale on the scale (dozens of strings); the story
  says what really happens there (it is recycled into cubes).
- The Cradle Returns frontier and the late-game goals: off Verdance's first visit. They keep the
  Homeward canon in docs/DECISIONS.md.
