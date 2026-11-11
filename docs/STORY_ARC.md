# The story of the whole game (the arc)

Owner items 70–72: a real story, simple enough for a child, that starts on Verdance and spills into
the other planets, "where ultimately we get enough fuel and power to make it back home".
Verdance's own steps are in docs/STORY_VERDANCE.md. The text and numbers below live in
`data/story_arc.json` (how to change them: docs/ADJUSTING.md, "Story arc"). The test
`tests/test_story_arc.gd` checks that the numbers add up.

## Why Lumi can't go home yet

Lumi lives on the **Cradle**, the big ship where **the Settlers** are asleep. A meteor storm broke
the Cradle open. Lumi fell to Verdance in a little pod. The same storm cracked the Cradle's fuel
tanks, and three hundred years in the dark used up most of its power.

So the Cradle can't come home, and Lumi can't fly back up to it. Home needs two things:

- **FUEL**, so the Cradle can fly home.
- **POWER**, so it can wake the Settlers.

Home needs **10 fuel and 10 power**. Each planet Lumi wakes gives some. The game shows it the same
way everywhere: **Home: fuel 2/10, power 2/10**.

## The five planets, then home

A planet gives its fuel and power when its way onward opens (on Verdance: six stations awake). That
moment is the planet's **exit beat**: WREN says how far home is, the question the planet leaves
open, and why the next planet is the one to go to. She says it once.

| # | Planet | Fuel | Power | Why that planet | Where it comes from |
|---|---|---|---|---|---|
| 1 | **Verdance**, the Settlers' home, a world of towns and gardens | 2 | 2 | Lumi's pod fell here | the fuel tanks at Stack Works, the big power cell at the Fairground |
| 2 | **Ochre**, desert and open pits | 1 | 3 | Two suns and steady wind: the best place for **power** | old sun mirrors and wind pumps; one haul truck's tank |
| 3 | **Tidewell**, islands and sea | 3 | 1 | Sea water can be made into **fuel** | the harbour's fuel works; the tide pumps |
| 4 | **Rime**, a frozen moon | 3 | 1 | Ice is frozen **fuel**, and there is lots of it | the ice; the warm springs under the lakes |
| 5 | **Anvil**, rust and foundries, the Ledger's head office | 1 | 3 | The Ledger's big reactor: the last **power** | the foundry reactor, once the Ledger lets us; its last tank |
| | **All five** | **10** | **10** | exactly what home needs | |

The numbers take turns (power world, fuel world, fuel world, power world) so every planet matters,
and no four planets are ever enough.

## One question per planet

Each planet leaves one question open. The next planet answers it.

| Planet | The question it leaves | Answered on | The answer |
|---|---|---|---|
| Verdance | The star chart shows four more buried worlds. Why did the Ledger bury them all? | Ochre | The Ledger dug Ochre first. When digging stopped paying, it left everything where it fell. |
| Ochre | A radio on Tidewell is still calling for help. Is anyone there? | Tidewell | The people left long ago, but they planted mangroves and asked someone to look after them. They are still alive. |
| Tidewell | The dredger logs say the Ledger sold the heat of Rime. How do you sell heat? | Rime | It drilled out the moon's warm heart and sold it. So the lakes froze. |
| Rime | Every Ledger memo is signed by a head office. Where is it? | Anvil | On Anvil. Nobody works there now: only one old audit robot, still counting. |
| Anvil | Will the Settlers wake up, and will they like their green home? | the Cradle | Yes. They wake up, look out of the windows, and see green. |

## The Ledger, planet by planet

The Ledger is the company that buried the worlds. It is never a monster to fight. It is a machine
that only counts what it takes.

1. **Verdance**: a voice on coupons and a few drones. It thinks cleaning "costs more than it earns".
2. **Ochre**: its closure notices. It leaves a world the day digging stops paying.
3. **Tidewell**: its dredgers still run on a timer. Nobody ever told them to stop.
4. **Rime**: its own sums: "the moon was not ours to keep warm".
5. **Anvil**: its heart, a lonely adding machine at the head office. Lumi shows it the sums: clean
   ground is worth more than trash. It changes sides and switches its reactor on for us. That is
   Anvil's 3 power.
6. **The Cradle**: the Ledger sends one last coupon: "Account balanced. Paid in full."

## How it ends

Fuel 10/10 and power 10/10 is all home needs. WREN says so at the last planet: "Fuel and power are
full. Back to Verdance: build the Homeward rocket and fly home." Lumi builds the big **Mk VII
Homeward** rocket on Verdance (`data/homeward.json` drive tier 7, `requires_home`), plants the last
seed and flies up to the Cradle with the fuel and power on board. The Cradle fills its tanks and
comes down to Verdance. The Settlers wake up (story/homecoming.gd, story/bloom_finale.gd).

**Every world at 100% is an extra, never a must** (owner item 58). Cleaning a planet all the way
still gives what it always gave: the planet's relic and an Heirloom pick, its "restored" note, and,
with all five, WREN's "every world alive" line. It also gives the better ending: in the Homecoming,
the five worlds glow fully green and the Cradle reads "FIVE WORLDS. FIVE ALIVE." Without it, the
worlds are only partly green and WREN says "Five worlds awake. Not all green yet, but robots are
planting on every one."

## Verdance's ending, in the game

When the sixth station wakes, WREN says, once:

1. "Six stations awake, Lumi. Their robots can look after Verdance now."
2. "To go home we need 10 fuel and 10 power. We have 2 fuel and 2 power."
3. "The star map shows four more worlds. The Ledger buried every one. Why?"
4. "Ochre is next. Its sun and wind can fill up our power."

The screen shows **Home: fuel 2/10, power 2/10**. The system map shows the same meters, two bars,
and for each planet what it gives ("Gives fuel 1 and power 3") and why to go there. When the
Orbital drive is built, WREN adds that the rocket can leave now and Verdance's robots carry on
without Lumi (docs/STORY_VERDANCE.md, D).

## What is built and what is only planned

- **Built**: the two meters, Verdance's exit beat, the map's meters and planet lines, WREN's
  arrival lines on the first rocket landing on each planet (on Verdance: the first return), and the
  Mk VII gate (full fuel and power; older saves with every planet at 100% count as full).
- **Planned** (the text is in the data, read the same way): Ochre, Tidewell, Rime and Anvil. A
  planet builder only has to build the planet. Until a planet names its own way onward in
  `data/homeward.json` (`planets[k].leave`), its exit beat comes when it is half restored
  (`chart_at`).
- Dev planets (`"dev": true` in data/planets.json, such as `testworld`) need no story block.
- The story notes `from`, `answers` and `ledger` are for the people who build each planet. They are
  not shown in the game yet.
