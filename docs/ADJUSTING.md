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

Landmark kinds: `water_tower`, `crane`, `ferris_wheel`, `radio_mast`, `smokestack`, `old_bus`,
`windpump`, `lighthouse`. The town's look (suburb, downtown...) is `VerdanceSite.KIND_BY_HUB`; the
`town` field is what the picker and the arrival title say, so keep the two in step.

Code: `planet/sites/hub_plan.gd` (data and saved state), `planet/sites/hub_purpose.gd` (arrival,
steps, the wake, the field bench, HUD lines). Check with
`godot --headless --path . -- --fresh --orbit --no-intro --rocket --orbit-hop=9 --hub-dev-chain=3 --hub-report=20 --quit-after=50`
(`--hub-wake=9,7` wakes hubs for free at start; `--hop-skip` skips the flight; `--hop-shots=PREFIX` saves pictures in a rendered run).
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
| How far music and ambience dip while WREN speaks | `duck` |
| A planet's ambience (wind, water, animal calls) and how it changes from ruined to restored | `planets`.`<id>`.`ambience` |
| Which built-in score a planet uses when no song plays (a new planet can borrow one) | `planets`.`<id>`.`theme` |

**Check what plays.** Add `--sound-log` to any run, for example
`godot --headless --path . -- --fresh --orbit --no-intro --autoplay --time-scale=4 --sound-log --quit-after=1200`.
At the end it prints a `[snd]` table: every sound, its slider group, how often it played, its
level, the shortest time between two plays, how many came within 5 seconds of the last, and how
many sounded at once. The full list is in `screenshots/sound_log.txt`.

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

Check with `godot --headless --path . -- --fresh --orbit --no-intro --life-clean=6,2 --life-report --quit-after=60`
(`[life]` lines: grass tufts, butterflies, sound weights and plays, each town's blocks per stage
and its lit lights). More dev hooks are listed at the top of `planet/sites/life_dev.gd`. Tests:
`tests/test_town_life.gd`, `tests/test_cell_verdure.gd`.

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
| What WREN says then | `data/homeward.json` `planets[k].leave.toast` | "Six stations awake, Lumi. Their robots can look after Verdance now." | Said once, before the exit lines in `data/story_reasons.json` `exit.system_open`. |
| The drive that leaves Verdance | `data/homeward.json` `drive[0].cost` | 500K cubes, 300 Parts | The biggest price of the planet. |
| Base level prices (start hub) | `data/hub.json` `levels[].cost` | 1,500 / 9,000 / 28,000 / 30,000 | Level 2 and 3 are story steps. 4 and 5 are optional on Verdance's way out. |
| Order of the card's steps | `data/objectives.json` (story), then `data/goals.json` `goals` in file order | | The card shows the first unfinished one. Move a line to move the step. |
| A goal's own "why" line | `data/goals.json` goal `desc` | only on "Fly to another planet" | Shown instead of "Reward: ...". |
| Goal rewards | `data/goals.json` goal `reward` | | Paid when the step completes. |
