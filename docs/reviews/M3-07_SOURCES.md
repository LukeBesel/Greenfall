# M3-07: district sources, the Lumi-only capstone jobs

Nov 11 2026, on top of `6b33866`. Rules and state: `systems/sources.gd`. The world's side (spots, markers, prompts, landmark state): `systems/source_sites.gd`. Data: `planets/verdance/data/sources.json` (table `sources`). Formulas: `docs/PLANET_PLAYBOOK.md`, "Source jobs (M3-07)".

## 1. What was built

- **A job per city, as data.** Three step types cover all six jobs, so `planets/verdance/sources/` holds no script: `use` (walk there, use it), `work` (use it, then stay in reach for some seconds; leaving pauses it) and `carry` (pick a part up, pay its price if it has one, carry it to its place, fit it). A `work` step names a pollution kind and runs at Lumi's hand bonus for it, so mastering a city's kind shortens its capstone.
- **The gate.** A city with a running source is held one stage short of the last (`Districts.set_stage_cap`). All its hexes may be thriving; the city reads "Sustained 80%" until the job fills the last fifth of the bar (`hold_share`), and launch progress cannot read 100% while a source runs. The next city still opens at stage 4, so the job never blocks moving on.
- **Only Lumi.** A step moves on only when Lumi uses its spot through the interact key and, for timed work, stays within 2.8 m. Nothing a robot does touches a job.
- **On the card and the beam.** Once the story objectives are done, the job of the city the readouts follow takes the objective card while one of its steps is on offer (title, why line, "2 / 4", a bar that fills with the job). The beam stands on the step's spot; the spot has a marker with Lumi's cyan ring. The goal chain keeps paying behind the card and returns when the job is done or waiting.
- **On completion:** `EventBus.source_shut_down(district)`, the hold lifts (stage 5 and its payout follow at once if the hexes are there), the landmark goes to its shut-down state (`TownSite.set_source_state`), the reward is paid, a notice shows, and the city's source finds are given. `source_shut_at_stage` is gone from the finds table and from `systems/finds.gd`.
- **Saved per planet** (`orbit.sources`): step, carried part, shut. A save from before jobs: a city already at stage 5 counts as shut down (unpaid); every other city gets its job. A save loaded with a shut source whose find was never given gets the find.
- **The bot** does the job of the city it is in as soon as a step is on offer (`AutoplayBot._do_source`), ahead of everything else, and rests a step it cannot reach after 150 s.
- **Dev flags:** `--sources-shut=all|id,id` and `--give-parts=N`; `--launch-ready` shuts every source first. `--district-stage=id:5` now leaves the city at stage 4 with its job on offer, which is the dev start for a job.

## 2. The six jobs

| City | Source | Steps | Reward |
|---|---|---|---|
| Old Town | The burst main | Close the feed valve; dig out the blocked drain (litter, 6 s); fetch the pipe cap and bolt it on (5 s) | 300 cubes, 45 Parts |
| Ironside | The crusher yard | Pull the boiler breaker; cut the wreck out of the press (wrecks, 8 s); fetch the brake shoe and fit it on the scrap crane (5 s); park the gantry | 960 cubes, 90 Parts |
| Kettle Bay | The tanker's leak | Close the transfer valve; fetch the hull plate and weld it over the gash (6 s); skim the slick off the shore (slick, 8 s); winch the boom shut | 1,980 cubes, 80 Parts |
| Highreach | The incinerator | Stop the feed belt; scrub the choked flue (smog, 8 s); fetch a filter cartridge and fit it (5 s); shut the furnace dampers | 2,400 cubes, 150 Parts |
| Lowmeadow | The treatment works | Close the inlet sluice; dig the sludge out of the channel (blight, 8 s); fetch the lime and dose the tank (5 s); fetch the plug and seal the outfall (6 s); start the clean water pumps | 4,260 cubes, 250 Parts |
| Old Capital | The rocket | Six parts, each built at the parts yard on the avenue, carried to the pad and fitted (6 s): launch frame 300, fuel tanks 350, engine cluster 400, guidance core 450, hull plates 500, nose cone 600 Parts (2,600 in all); offered at 35, 45, 55, 65, 75 and 85% of the city clean | 3,060 cubes |

- Cubes are one minute of each city's `income_ref` (the limit is three). Parts are the accepted proposal's source payouts; the rocket pays none back.
- Cities 1 to 5 are offered from stage 3 (Growing). The rocket is offered from the start of the city, part by part as it is cleaned.
- The rocket is the last source: when it is done and Old Capital's hexes are thriving, the city reaches stage 5, the launch rule (every city at stage 5) is met and `story/planet_ending.gd` plays as before. The ending needs the six cities and nothing of the rest of the planet.

## 3. Checks

RESULTS_PLACEHOLDER

## 4. Design calls for the lead

1. **The gate is on stage 5, as the task says.** Design spec section 4 says a running source holds hexes at stage 3 and trickles new waste round it. Neither is built: hexes grow freely and no waste comes back. If the trickle is wanted it is a rule in `systems/pollution.gd` keyed on `Sources.is_shut`.
2. **Old Capital has six steps, one per part** (the task's "3 to 5" and "six parts" cannot both hold).
3. **Rocket parts are bought on the spot, not made on the Assembler's line.** The proposal has each part take the line for 45 s. Here Lumi pays the Parts at the parts yard and has the part at once, so the launch crew is not slowed by the rocket (M3-20 counted on about nine player minutes of line time). Fitting takes 6 s, not 20: twenty seconds standing still six times read as sluggish.
4. **No power spike on shutdown.** The spec gives each source a rig slot or tool tier. Rigs are another task; a job has no `grants` field yet.
5. **No step needs robots.** "Hold a lever while robots clear around" is not built: a step that waits on a crew can strand a player who has none there.
6. **The job takes the card ahead of the goal chain** from the moment it is on offer. In cities 1 to 5 that is stage 3, when planting is still the main work; if that is too early, raise `open_stage` to 4.
7. **Spots stand on the street in front of each landmark and on the open lot**, not on the landmark, because only that ground is sure to be free of buildings. A valve "of the tanker" therefore stands a few metres from the hull.
8. **An old save whose city was at stage 5 keeps it and is never paid for the job**; one at stage 4 or below must do the job even if every hex is thriving.

## 5. Honest state: what is below the bar

- **Markers are plain props** (a post with a wheel, a box with a lever, a striped trestle, a crate, a plate with a peg) in flat paint with a cyan ground ring. They work and they are far from commercial quality: no models, no animation, no sound of their own beyond a chime. None was rendered.
- **The rocket does not grow.** The landmark has two states (running, shut down); fitting a part changes nothing on the pad until the last one. A per-part hook on the landmark is needed for the launch site to read as a build.
- **Lumi carries a small crate over her head** for every carried part, whatever the part is. No carry animation.
- **Timed work has no effect or animation**: Lumi stands in the ring while the card's bar fills.
- **Nothing was seen on screen.** The card, the beam, the ring and the notice are covered by tests and headless bot runs only.
- **No WREN line, no sound design, no camera moment** for a shutdown: the "set piece" is the landmark's state change and a notice.
- `story/objectives.gd` grew by about 60 lines and is 903 lines (it was 845, already over the style guide's 600).

## 6. Things to know

- Files outside `systems/` and the planet folder, and why: `planet/sites/town_site.gd` and `planets/verdance/sites/verdance_site.gd` (`source_frame()`, the landmark's frame), `core/planet_definition.gd` and `planets/verdance/planet.tres` (the `sources` table), `autoload/EventBus.gd` (`source_job_opened`, `source_step_done`), `story/objectives.gd` (the card and the beam), `scenes/slice_orbit.gd` (wiring, save section, `--give-parts`), `systems/districts.gd` (the hold), `systems/districts_dev.gd` and `autoload/DevHooks.gd` (dev flags), `systems/finds.gd` and `finds.json` (finds on the real shutdown; Old Capital's hint now names the rocket), `tools/autoplay.gd`, `tools/orbit_roundtrip.gd`, `tests/test_looks.gd`.
- `planet.tres` and `core/planet_definition.gd` each gain one line; the rigs task may touch the same lines.
- New strings are in `sources.json` (`name`, `text`, `text_1`, `desc`, `prompt`, `final_prompt`, `toast`: all keys the extractor reads) and three `tr()` calls in code. `tools/extract_strings.py` was not run.
- The simulators (`tools/pace_sim`, `tools/crew_sim`) were not changed: the pace simulator's proposal tables already model a source job and the rocket their own way.
- Originality: nothing here was modelled on another game. A multi-step repair job with a carried part is common across games; the steps are ordinary plant work on each city's own landmark.
- `docs/ROADMAP.md`, `docs/DECISIONS.md` and `docs/TASKS.md` were not updated (lead's files).
