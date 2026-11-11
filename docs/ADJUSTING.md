# Adjusting Greenfall

Where to change a number. Every line names the file, the key and what it does. Data files are
JSON; restart the game after an edit. Each helper adds its own section.

## Pacing, prices and gates (v6pace)

Measure after a change: `flock /tmp/gf-autoplay.lock godot --headless --path . -- --fresh --orbit --autoplay --time-scale=8 --quit-after=2700`
prints a `[card]` line per objective step and an `[arc]` line per hub, rocket tier and the exit
(bot minutes; a person takes about twice as long). Tests that pin these numbers: `tests/test_v6pace.gd`.

| What | File and key | Now | Effect |
|---|---|---|---|
| When the rocket appears | `data/hub.json` `rocket.level`, `rocket.after_objective` | level 1, after the step `zone` | The rocket stands on the start pad once that story step is done and the base has that level. |
| Price of the first far hub | `data/hub.json` `far_hub.cost_override."0"` | 600 cubes, 30 Parts | The on-ramp. Remove the entry to use the curve's base. |
| Far hub price curve | `data/hub.json` `far_hub.cost_base`, `far_hub.cost_growth` | 1,500 cubes x 4.0 per hub (Parts 40 x 1.4) | Price of hub n = base x growth^n, rounded to two digits: 6K, 24K, 96K, 380K. One number moves the whole ladder. |
| Income per restored hub | `data/hub.json` `far_hub.sell_growth` | 2.5 | Every sale (scale, robot bales, trash bin) is multiplied by this for each far hub restored. Raise it and hubs come faster; lower it and each hub takes longer. |
| Level of a restored far hub | `data/hub.json` `far_hub.level` | 2 | What a woken hub counts as. |
| Per-planet overrides | `data/homeward.json` `planets[k].far_hub` | none | Any `far_hub` key, for that planet only. |
| How many hubs a rocket tier reaches | `data/rockets.json` `tiers[].hubs` | Mk I 3, Mk II 5, Mk III all | Hubs kept restored, the start hub included. |
| Rocket tier prices | `data/rockets.json` `tiers[].cost` | Mk II 20K, Mk III 150K, Mk IV 2.5M | Mk IV (warp) is not needed to leave. |
| When Lumi may leave a planet | `data/homeward.json` `planets[k].leave.hubs`, `.hub_level` | Verdance: 6 hubs at level 2 | Opens the system map and the drive. Not tied to the planet's clean %. |
| What WREN says then | `data/homeward.json` `planets[k].leave.toast` | "You can fly on now, Lumi. The rest of Verdance can wait." | Said once. |
| The drive that leaves Verdance | `data/homeward.json` `drive[0].cost` | 500K cubes, 300 Parts | The biggest price of the planet. |
| Base level prices (start hub) | `data/hub.json` `levels[].cost` | 1,500 / 9,000 / 28,000 / 30,000 | Level 2 and 3 are story steps. 4 and 5 are optional on Verdance's way out. |
| Order of the card's steps | `data/objectives.json` (story), then `data/goals.json` `goals` in file order | | The card shows the first unfinished one. Move a line to move the step. |
| A goal's own "why" line | `data/goals.json` goal `desc` | only on "Fly to another planet" | Shown instead of "Reward: ...". |
| Goal rewards | `data/goals.json` goal `reward` | | Paid when the step completes. |
