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

Landmark kinds: `water_tower`, `crane`, `tower_crane`, `ferris_wheel`, `radio_mast`, `smokestack`, `old_bus`,
`windpump`, `lighthouse`. The `town` field picks the town's look
(`oldtown`, `downtown`, `suburb`, `industrial`) and is what the picker and the arrival title say; a
hub where the lake reaches into the town is always built (and named) as a harbour.

Code: `planet/sites/hub_plan.gd` (data and saved state), `planet/sites/hub_purpose.gd` (arrival,
steps, the wake, the field bench, HUD lines). Check with
`godot --headless --path . -- --fresh --orbit --no-intro --rocket --orbit-hop=9 --hub-dev-chain=3 --hub-report=20 --quit-after=50`
(`--hub-wake=9,7` wakes hubs for free at start; `--hop-skip` skips the flight; `--hop-shots=PREFIX` saves pictures in a rendered run).
The rocket hop between hubs and the arrival are `hub_defaults.hop` in the same entry: `leg_s`, `leg_m`,
`cruise_alt_m`, `fade_s`, `skip_after_s`, the approach camera, the arrival title's `title_in_s` /
`title_hold_s` / `title_out_s` and `arrive_sting` (the music sting on a first arrival, "" for none).
The title's "why we came" line is the hub's `reason`, else `hub_fly_<order>` in
data/story_reasons.json (the same line as the goal card), else its `desc`.
After changing hubs, run the six-base walkthrough:
`godot --headless --path . -- --fresh --orbit --no-intro --hop-skip --hub-walkthrough` (PASS/FAIL, docs/QA_VERDANCE.md).
A new planet gets the same by adding `hub_defaults` and `hubs` to its entry.

## Music and sound (v6sound)

**Add a song (no code).** Put the file (mp3, ogg or wav) in `audio/songs/`. That is all: the game
picks it up, names it after the file (`My New Song.mp3` shows as "My New Song"), owns it from the
start and plays it everywhere. To make it a song of one planet, put it in a folder named after
the planet instead: `audio/songs/ochre/My New Song.mp3`. Then run `python3 tools/check_songs.py`:
it lists every song, whether its file is there, the files that have no entry, and each planet's
playlist. A missing or damaged file never breaks anything; the song is skipped.

**Say more about a song.** Add an entry to `"songs"` in `data/songs.json`. The `id` is the file
name in lower case with `_` for spaces (`my_new_song`). Everything else is optional:

| To change | Write in the entry |
|---|---|
| The title, the in-game artist, the CD note | `"title"`, `"artist"` (an id from `"artists"`), `"desc"` |
| Which planets it plays on | `"planets": ["verdance", "rime"]` or `["all"]` |
| When it plays | `"moments"`: any of `title` (title screen), `intro`, `explore` (day), `night`, `restored` (the planet is mostly green), `base_restored`, `launch`, `ending` |
| How often | `"weight"`: 1 is normal, 2 twice as often, 0 never in the shuffle |
| Louder or quieter | `"volume_db"`: `-3` a bit quieter, `2` a bit louder |
| Owned at once, or a CD to find | `"unlock": "start"`, or `"unlock": "cd"` with `"found_on": "verdance"` |
| A file name that does not match the id | `"file": "Some Other Name.mp3"` |

A song with `launch`, `ending`, `base_restored` or `intro` plays at that moment whether or not
its CD was found. While no song is marked for a moment, the built-in score plays it as before.
What a file with no entry gets is `"defaults"` in the same file.

**The rules** are at the top of `data/songs.json`:

| To change | Edit |
|---|---|
| Quiet between songs (seconds, shortest and longest) | `gap_s` |
| Quiet after loading a save | `first_gap_s` |
| Quiet minutes after the pod lands | `landing_gap_s` |
| How often the main theme is picked (0 to 1). It still never plays twice in a row | `main_share` |
| Which song is the main theme (first on the title screen) | `main_theme` |
| Level of all songs against the rest of the game | `song_db` |
| How green a planet must be for `restored` songs (0 to 1) | `restored_at` |
| How often story songs and other planets' songs turn up | `story_weight`, `other_planet_weight` |

**A planet's playlist.** A planet plays the songs of its group (`"group": "ochre"`), the songs
whose `"planets"` name it, the files in its folder, and any ids listed in
`"planets"."ochre"."songs"` in `data/songs.json`. That block can also repeat any rule from the
table above to change it on that planet only, e.g. `"rime": {"songs": [], "gap_s": [120, 240]}`.
A new planet: add a block with its id there (and a folder if you like).

**Volumes and the mix** are in `data/sound.json`:

| To change | Edit |
|---|---|
| Where the five sliders in Settings start for a new player (Master, Music, Ambience, Sound effects, Interface) | `volumes` (0 to 1) |
| A fixed trim under a slider (Music, Songs, Ambience, SFX, UI) | `bus_trim_db` |
| Which slider a sound follows (menu clicks: Interface; animal calls: Ambience; the rest: Sound effects) | `bus_of` |
| One sound louder or quieter everywhere | `sound_db`: `"chime": -3` |
| A sound that repeats too fast: the shortest time between two plays, in seconds | `min_gap_s`: `"clink": 0.2` |
| The same, only where one thing plays it: `tag:sound`. Tags: `scoop` (pieces flying into Lumi), `lumi` (start/stop squeak), `sweep` (litter), `lights` (street lights coming on), `robot` (robots at work) | `min_gap_s`: `"robot:servo": 2.0`, `sound_db`: `"scoop:pop": -3` |
| Mute a sound in one place (e.g. the beep on every scooped piece) | `sound_db`: `"scoop:blip": -80` (delete the line to bring it back) |
| How far music and ambience dip while WREN speaks | `duck` |
| A planet's ambience (wind, water, animal calls) and how it changes from ruined to restored | `planets`.`<id>`.`ambience` |
| Which built-in score a planet uses when no song plays (a new planet can borrow one) | `planets`.`<id>`.`theme` |

**Check what plays.** Add `--sound-log` to any run, for example
`godot --headless --path . -- --fresh --orbit --no-intro --autoplay --time-scale=4 --sound-log --quit-after=1200`.
At the end it prints a `[snd]` table: every sound, its slider group, how often it played, its
level, the shortest time between two plays, how many came within 5 seconds of the last, and how
many sounded at once, and under each sound the script lines that played it most (`from patch.gd:519 x712`).
The full list is in `screenshots/sound_log.txt`, one line per play with its source.

**The 2026-11-11 pass** (22 game minutes of autoplay from a fresh start, sound plays per minute,
before -> after): the four layers on each scooped piece plus its beep 161 -> 56 (the beep 34 -> 0), the scoop clink
ladder 61 -> 33 (same-frame duplicates dropped), Lumi's start/stop squeak 19 -> 7, the litter-sweep
whoosh 17 -> 5, all sounds together 333 -> 152. Birds stayed under one call a minute, no WREN line
repeated, and the main theme played first with quiet gaps between songs. Robots (`robot:`) and
street lights (`lights:`) got gaps too; they only show up later in a run.

## The world coming back to life (v6life)

What reacts where Lumi cleans: grass on clean ground, town blocks that wake up, butterflies, and
the sound bed. All of it is in `data/life.json` (look, rules) and `data/sound.json` (sound). In
`data/life.json`, `_default` has every value; a planet's block (`"verdance": {...}`) repeats only
what it changes, e.g. `"ochre": {"ground": {"grow_s": 600}}`. Nothing is saved, so a change shows
on the next start.

| To change | Edit |
|---|---|
| How green a clean cell grows, per hex level 0..5 (6 numbers, 0 to 1) | `ground.green_per_level` |
| How long a freshly cleaned cell takes to green over (seconds) | `ground.grow_s` |
| Grass tufts per cell and how far round Lumi they stand, per quality preset Low..Ultra | `ground.tufts_per_cell`, `ground.tuft_rings` |
| How many tufts are flowers, and their colours | `ground.flower_share`, `ground.petals` (`"#rrggbb"`) |
| How clean a city block must be for its first windows (stage 1) and its street lamps (stage 2) | `town.swept_at`, `town.awake_at` (share of its cells, 0 to 1) |
| Planted cells that make a clean block "alive" (stage 3: neon, string lights, shop windows) | `town.planted_cells` |
| Share of windows lit at dusk per stage 0..3 | `town.lit_windows` |
| Which stage turns street lamps and signs on | `town.lamps_at_stage`, `town.signs_at_stage` |
| How fast a block's colour and windows follow a change (seconds) | `town.ease_s` |
| Butterflies and fireflies per cell by hex level, the most at once, their colours | `flutter.per_level`, `flutter.max`, `flutter.colors` |
| The sound that follows the ground round Lumi (wind over junk, leaves over grass, rare creaks and bird phrases) | `data/sound.json` `planets.<id>.ambience.life`: `loops` (`id: [dB, dirty/green/always]`) and `events` (`[sound, min s, max s, dB, pitch lo, pitch hi, dirty/green/green_day/always, min s between]`). A loop or sound can be a `res://` file, so a recorded sound can replace a built-in one. A planet without a `life` block has none |
| When those beds come in and how the one-shots' conditions read the ground | same block: `mix` (`dirty_from`/`dirty_full`, `green_from`/`green_full`: share of junk / mean green, 0 to 1, where a bed starts / is full; `dirty_hushes_green`) and `when` (`dirty`, `green`, `night` thresholds) |
| The least time between two plays of any one life sound (birds, creaks), whatever the event says | same block: `min_gap_floor_s` (60: about once a minute at most; the beds are loops and do not count) |
| How far round Lumi the bed listens, how fast it crossfades | same block: `rings` (3 is about 30 m), `fade_s` |

Check with `godot --headless --path . -- --fresh --orbit --no-intro --life-clean=6,2 --life-report --quit-after=60`
(`[life]` lines: grass tufts, butterflies, sound weights and plays, each town's blocks per stage
and its lit lights). More dev hooks are listed at the top of `planet/sites/life_dev.gd`. Tests:
`tests/test_town_life.gd`, `tests/test_cell_verdure.gd`.

## Pacing, prices and gates (v6pace)

Measure after a change: `flock /tmp/gf-autoplay.lock godot --headless --path . -- --fresh --orbit --autoplay --time-scale=8 --quit-after=2700`
prints a `[card]` line per objective step and an `[arc]` line per hub, rocket tier and the exit
(bot minutes; a person takes about twice as long). Tests that pin these numbers: `tests/test_v6pace.gd`.
Then `python3 tools/cadence.py screenshots/autoplay_report.json run.log` for the arc, cubes per minute,
reward gaps and card waits; targets and the last measured run are in `docs/BALANCE.md`.

| What | File and key | Now | Effect |
|---|---|---|---|
| When the rocket appears | `data/hub.json` `rocket.level`, `rocket.after_objective` | level 1, after the step `seed` | The rocket stands on the start pad once that story step is done and the base has that level. |
| Single far-hub prices | `data/hub.json` `far_hub.cost_override` (step number as the key, e.g. `"2": {"cubes": 8000}`) | hub 6 (`"4"`): 300K cubes, 120 Parts | Replaces one step of the curve without moving the others. |
| The whole planet's speed | `data/hub.json` `far_hub.pace` | 1.3 | Every sale pays 1/pace: 1.25 makes each cube step about 25% longer, 0.8 about 20% shorter. The first knob to turn after a playtest. |
| Woken bases clean while Lumi is away | `data/hub.json` `far_hub.keep` | 4 cells/min + 1 per base level above 1 + 0.5 per robot there | The main lever on the planet % at the leave point. `home: true` lets the start hub do it too. |
| What the planet % counts | `data/hub.json` `far_hub.pct_over` | `all_regions` | `all_regions`: every hub region's land (only goes up). `built_regions`: only the woken hubs' regions (drops at each wake). |
| Far hub price curve | `data/hub.json` `far_hub.cost_base`, `far_hub.cost_growth` | 600 cubes x 4.0 per hub (Parts 30 x 1.4) | Price of hub n = base x growth^n, rounded to two digits: 600, 2.4K, 9.6K, 38K (then hub 6 by override). One number moves the whole ladder. |
| Income per restored hub | `data/hub.json` `far_hub.sell_growth` | 3.5 | Every sale (scale, robot bales, trash bin) is multiplied by this for each far hub restored. Raise it and hubs come faster; lower it and each hub takes longer. |
| Level of a restored far hub | `data/hub.json` `far_hub.level` | 2 | What a woken hub counts as. |
| Per-planet overrides | `data/homeward.json` `planets[k].far_hub` | none | Any `far_hub` key, for that planet only. |
| How many hubs a rocket tier reaches | `data/rockets.json` `tiers[].hubs` | Mk I 3, Mk II 5, Mk III all | Hubs kept restored, the start hub included. |
| Rocket tier prices | `data/rockets.json` `tiers[].cost` | Mk II 8K, Mk III 100K, Mk IV 2.5M | Mk IV (warp) is not needed to leave. |
| When Lumi may leave a planet | `data/homeward.json` `planets[k].leave.hubs`, `.hub_level` | Verdance: 6 hubs at level 2 | Opens the system map and the drive. Not tied to the planet's clean %. |
| What WREN says then | `data/homeward.json` `planets[k].leave.toast` | "Six stations awake, Lumi. Their robots can look after Verdance now." | Said once, before the exit lines in `data/story_reasons.json` `exit.system_open`. |
| The drive that leaves Verdance | `data/homeward.json` `drive[0].cost` | 500K cubes, 300 Parts | The biggest price of the planet. |
| Base level prices (start hub) | `data/hub.json` `levels[].cost` | 1,500 / 9,000 / 60,000 / 250,000 | Level 2 and 3 are story steps. 4 and 5 are optional, but they lift income a lot: cheap ones made the last hub and the drive come within minutes. |
| Order of the card's steps | `data/objectives.json` (story), then `data/goals.json` `goals` in file order | | The card shows the first unfinished one. Move a line to move the step. |
| A goal's own "why" line | `data/goals.json` goal `desc` | only on "Fly to another planet" | Shown instead of "Reward: ...". The hub, wake and rocket steps carry none: their why is in `data/story_reasons.json` (card and WREN). |
| The first robot's price | `data/robots.json` `scoopie.cost`, `.parts` | 800 cubes, 40 Parts | Parts come from scooping metal, plastic and glass; the card says how many are missing. |
| Goal rewards | `data/goals.json` goal `reward` | | Paid when the step completes. |

## How Lumi moves (v6feel)
`data/patch.json` `move` controls how Lumi meets things on a round planet: `max_step` (0.45 m) is the tallest kerb, step or low planter he hovers over instead of stopping, and `round_keep` (0.6) is how much of his speed he keeps while rounding a post, bin or heap he clipped nearly head-on (0 = a plain slide, which nearly stops him). Check a change with `--feel=walk` (tools/feel_probe.gd).

## Seed of the Week on or off (v6screens)

`data/weekly.json` `"enabled"` is the one switch. It is `false`: the mode does not work on the round world yet (the week's seed is ignored and a resumed run has no robots), so its Keepsakes tab, its two Garden Mode decorations and its two achievements in the Codex are hidden, and Pause shows no Keepsakes button until a radio, an album or a nursery exists.
Set it to `true` to bring all of it back. To look at it while it is off, run with `--extras=weekly` or `--weekly`. Test: `tests/test_extras.gd` (`test_weekly_off_hides_every_way_in`).

## Yard machines and landmarks (v6yard)

**Picture signs and machine paint: `data/machine_art.json`.** Every yard machine carries a round
sign with one pictogram and no words, so a small child can tell what it does.

| To change | Edit |
|---|---|
| Size, face and ink colour of every sign | `signs.defaults` (`size` in metres, colours `#rrggbb`) |
| One machine's picture, rim colour, accent colour, size | `signs.<machine>`: `icon` (`wrench`, `bin`, `bale`, `belt`, `leaf`, `signal`, `bot`, `parts`), `rim`, `accent`, `size` |
| Remove a machine's sign | `signs.<machine>.show: false` |
| Height of the bin's and the composter's sign | `signs.trash_bin.post_height`, `signs.composter.post_height` |
| The baler's paint (body, press head and hopper, crosshead) | `baler.body`, `baler.press`, `baler.trim` |
| The belt drive's paint (frame, motor) | `belt.frame`, `belt.motor` |
| The recycler's paint (housing, hopper, smelter) | `recycler.body`, `recycler.hopper`, `recycler.kiln` |
| The repair cart by the crashed pod (shown from the first upgrade until the planter stage) | `pod.service: false` removes it; `pod.cart`, `pod.cart_trim`, `pod.cone` colour it |

Machines: `workbench`, `trash_bin`, `baler`, `belt`, `composter`, `signal_tower`, `fabricator`, `recycler`.
Code: `systems/camp/machine_art.gd` (signs, baler, belt drive, pod cart), `systems/camp/yard_art.gd`
(the other machines). A new pictogram is a new case in `MachineArt._icon`.

**Hub landmarks: `data/landmarks.json`.** Which hub has which landmark stays in
`data/planets.json` (`hubs[].landmark.kind`, see "Hubs" above). This file is how each kind looks.

| To change | Edit |
|---|---|
| A landmark's two colours | `kinds.<kind>.main`, `.accent`: a kit colour name (cream, white, teal, mint, sky, navy, orange, yellow, red, olive, slate, plum) or `#rrggbb` |
| Its size | `height`, `radius`, `tank_height` (water tower); `height`, `wheel_radius`, `blades` (windpump); `span`, `height`, `run` (crane); `height` (mast, stack, lighthouse); `radius`, `gondolas` (wheel); `height`, `jib` (tower crane); `length` (bus) |
| How fast the fan, the wheel or the radar turns once the hub is awake | `kinds.<kind>.spin` (radians a second, 0 = still) |
| The wheel's gondola colours | `kinds.ferris_wheel.gondola_a`, `.gondola_b` |
| The room a landmark keeps clear of junk and buildings | `kinds.<kind>.foot` (metres) |
| Go back to the old thin model for one kind | `kinds.<kind>.kit: false` |
| A different look on another planet | `planets.<planet>.<kind>`: any of the keys above; what is left out comes from `kinds` |
| Which look a hub level gives | `states`: the look from that level upward (`broken` is dark and still, `repaired` and `restored` are lit and turning) |

Kinds with a kit model: `water_tower`, `windpump`, `crane` (a gantry crane), `radio_mast`,
`ferris_wheel`, `smokestack`, `tower_crane` (its jib turns), `old_bus`, `lighthouse`. On planets other
than Verdance's city biome the old thin models still stand.
Code: `planet/sites/hub_landmarks.gd` (models), `planet/sites/hub_landmark_node.gd` (state, lights,
turning). Check the numbers with `godot --headless --path . res://tools/machine_stats.tscn`
(triangles, draw calls and build time per model), and look at them with
`res://tools/yard_lineup.tscn -- --shots=v6 --lm-state=broken|repaired|restored --out=screenshots/yard/v6`
(rendered; one picture per machine and landmark).

## A new planet (v7planet)

`data/planets.json` `_default` is what every planet gets; a planet block (`"<id>": {...}`) repeats only what it changes: `name`, `globe` (`frequency`, `hub_count`, optional `seed`: the size), `site_kit` (`towns` or `prefab`), `look.ground` (ground textures and colour multipliers), `hub_defaults`, `hubs`, `hub_steps` (`generated`: the card's fly/wake/rocket steps come from the planet's `hubs[]`; Verdance keeps `shared`). `"dev": true` makes a test planet that only `--orbit-planet=<id>` reaches.
The step-by-step recipe, the per-planet blocks in the other files (`landmarks.json`, `life.json`, `sound.json` with `"like"`, `songs.json`, `homeward.json`) and the checks (`tools/planet_smoke.sh <id>`, `tests/test_planet_data.gd`) are in docs/NEW_PLANET.md; its worked example is the dev planet `testworld`.

## Story arc: fuel, power and each planet's story (v7arc)

`data/story_arc.json` holds the story spine across the planets (docs/STORY_ARC.md). Home needs
`home.fuel` and `home.power`; each planet's `planets.<id>` block says what it gives (`gives`), its
one-line reason to go (`reason`), the question it leaves open (`question`), and WREN's lines on the
first rocket landing (`arrive`) and at its exit beat (`leave`). A planet gives its fuel and power
once, when its way onward opens (`data/homeward.json` `planets[k].leave`, else restoration at
`chart_at`).

| To change | Edit |
|---|---|
| How much fuel and power home needs | `home.fuel`, `home.power` (must equal the sum of all `gives`) |
| What a planet adds to the meters | `planets.<id>.gives` `{fuel, power}` |
| The "why go" line on the map and in WREN's "next" line | `planets.<id>.reason` |
| WREN on the first rocket landing / at the exit beat | `planets.<id>.arrive` / `planets.<id>.leave` (1–2 short lines) |
| The meter and line formats | `home.meter`, `home.home_line`, `home.next`, `home.gives_text`, `home.gave_text`, `home.full` |
| The line after the last planet | `cradle.reason` |
| What the final Homeward rocket needs | `data/homeward.json` `drive` tier 7: `requires_home: true` (the meters full). `requires_relics` / `requires_system` still work as gates if you want 100% back as a must |

`from`, `answers` and `ledger` are notes for whoever builds the planet; they are not shown yet. A
new planet needs only its block (keyed by its id in `data/homeward.json`). After changing text, run
`python3 tools/extract_strings.py` and fill the six languages (docs/LOCALIZATION.md). Check with
`godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_story_arc.gd -gexit`.
