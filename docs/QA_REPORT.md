# Greenfall QA report: first 45 minutes

- **Build:** `claude/kind-wright-rhxixd` @ 602b7fe (report on `claude/greenfall-qa`)
- **Date:** 2026-11-08
- **Tester:** QA session (Godot 4.7.2, headless plus xvfb/llvmpipe renders)

**Priorities:** **P1** blocks the owner's next playtest, **P2** visible and below the owner's bar, **P3** polish.
All screenshots are in `screenshots/qa/` and each has a `.log` with the same prefix.

## How this was tested
- **Headless autoplay** (`--fresh --autoplay --time-scale=4 --quit-after=700`) covered 45.4 game minutes. Files: `autoplay_700.log` and `autoplay_report.json`.
- **Headless runs with an on-screen text probe** logged every visible Label and RichTextLabel with its rect and alpha:
  - the intro: `headless_intro_watch.log`
  - 28 game minutes of autoplay: `headless_autoplay_watch.log`
- **Rendered checkpoints** used opengl3 at 960x540 on the Low preset: spawn, intro, pause, settings, Codex, workbench (all tabs), bales, night, Glim and its scanner, the CD player and the title.
  - A rendered autoplay at time-scale 6 adds `19_play_*.png`.
  - Software GL runs at about 1 fps, so rendered timing is approximate.
- **Tests:** `tools/run_tests.sh` passed 637/637, and the save round trip passed (`tests.log`).
- **Geometry census:** `scene_stats_low.log`.
- **How the menus were driven:** an untracked autoload probe (`tools/qa_probe.gd`, committed for reuse) loaded through `override.cfg`. It presses actions, clicks buttons by text, takes shots and dumps on-screen text.
  - Usage: `--qa-seq="T:pause;T:click=settings;T:shot=PATH;T:dump" --qa-watch`.
  - To enable it, create `override.cfg` with `[autoload]` and `QAProbe="*res://tools/qa_probe.gd"`. Don't commit that file.

---

## P1: blocks the playtest

### 1. Objective and checklist text fades to 50% and becomes unreadable
- **Steps:** new game, stand still for 6 s.
- **What happens:** the OBJECTIVE and RESTART CHECKLIST cards drop to alpha 0.5 over the bright city backdrop, and the text can't be read.
- **Cause:** `ui/goals_panel.gd:154` dims to `0.5` after `DIM_AFTER_S` (6 s) whenever `hud_mode == MINIMAL`, and MINIMAL is the default (`autoload/Settings.gd:74`).
- **Owner note it fails:** "Goal and task-bar text is easy to read".
- **Shots:** `03_spawn.png`, `08_intro_06.png`, `11b_bale.png`, `19_play_*.png`. The probe logs `a=0.50` on every objective label.
- **Area:** ui / hud.

### 2. Several message lines on screen at once, and too many of them
- **Steps:** new game, play 10–15 minutes (or read `headless_autoplay_watch.log`).
- **What happens:**
  - Out of 481 samples, 20 had 2–3 toasts stacked and 19 had a toast and a WREN subtitle together.
  - There were 73 distinct toasts in 27 game minutes. Nine of them landed between 10.3 and 10.8 min: Baler, first bale, sell, Perfect, achievement, buried part, two "Recovered", "Install 5".
- **Examples:**
  - At 1:16: "Codex entry: Electronics" + "Goal complete · Scoop 15 pieces" + WREN "Lumi, it's WREN…".
  - At 10:37: "BURIED PART: walk toward it…" toast + WREN "Hear that beeping?…", which says the same thing twice (`story/objectives.gd:417-421`).
  - In render: "Relay signal 25%. WREN can reach you." toast + WREN tower line (`19_play_10.png`).
- **Owner note it fails:** "Only ONE message line is on screen at a time … (onboard2)".
- **Area:** toast stack (`EventBus.toast` consumer), `story/subtitles`, `story/objectives.gd`, goal/achievement/codex toasts.
- **Suggestion:** one queue and one line, merge reward lines, and drop codex/achievement toasts while WREN is talking.

### 3. The first objective needs an ability the player doesn't have yet
- **What happens:**
  - From the first second the objective is "Power the base: sell 3 bales" (`data/objectives.json:10`).
  - WREN's crash brief says "Bale junk to power the old base".
  - The pause legend shows "RMB press bale".
  - Baling only unlocks with the Baler upgrade (100 cubes). Autoplay bought it at 12.5 min (10.9 min in the rendered autoplay).
  - A new player is told to do something they can't do for ten minutes.
- **Owner notes it fails:** "Nothing offers an event or goal that needs a locked ability", and "It's clear right away why Lumi cleans".
- **Shots:** `03_spawn.png`, `04_pause.png`, `08_intro_04.png`.
- **Area:** onboard (objectives, WREN brief), pace.

---

## P2: visible to the owner

### Pacing (from `autoplay_report.json`)

4. **Dead early stretch.**
   - No new goal from 1.6 to 12.5 min (`dead_gaps_min [[1.6,12.5,10.9],[16.5,21.3,4.8],[28.7,33.9,5.1]]`).
   - Cubes sat at 37 with a 0/s rate from 2.2 to 5.2 min, and at 32 from 9.2 to 11.2 min.
   - There is also a 9.2-min goal gap from 36.2 to 45.4.
   - The owner wants "something new every 5-20 min, never a long stretch with no goal", and the first 12 minutes is where a new player quits.
   - **Area:** pace.
5. **First seed at 37.1 min.** The owner wants about 20 min (`seed_tin_s` 2226 s). The first robot has not arrived by 45 min (helpers wait for base level 2). **Area:** pace.
6. **Parts pile up with nothing to spend them on.**
   - The player held 1,750 Parts at 45 min with `parts_bought 0`, and research sat idle for 2,519 s (`research_idle_s`).
   - The economy then snowballs: cubes jumped from 401 to 1,096 in one minute at 26 min.
   - **Area:** pace / economy.

### Camera and world

7. **The camera clips into geometry during normal play.**
   - `19_play_02.png`: the screen is almost fully black, with the camera inside a junk heap or canopy.
   - `19_play_03.png`: a black sawtooth band (the underside of an awning) across the top third.
   - `19_play_05-07.png`: next to the broken workbench, the camera sits inside Lumi's head, which fills half the screen.
   - **Area:** player camera collision (`CameraRig`).
8. **Post-intro camera.** When the intro hands over to play, the camera sits right behind Lumi, whose head fills the middle of the screen and covers the "OLD TOWN BASE" label. It stayed there for more than 75 s in render. Compare the no-intro spawn. **Shots:** `08_intro_06.png` to `08_intro_09.png`, and `03_spawn.png`. **Area:** intro hand-off / CameraRig.
9. **Manhole covers render as black voids.** Several large pure-black ellipses in and around the yard look like holes in the ground. They come from `water_manhole_cover` (`planet/city_view.gd:433`). **Shots:** `03_spawn.png`, `11b_bale.png` (big one front left), `19_play_10.png`. **Area:** world / asset material.
10. **Hex outlines are thick dark lines, not lasers.** The yard and street are covered in a dark square-ish grid of lines. The owner asked that all hex outlines look like lasers and that the target hex has a soft glowing outline. **Shots:** `03_spawn.png`, `13_night.png`. **Area:** onboard / world2 (hex outline shader).
11. **The yard has more than pod, bench and bin.**
    - A blue WaterBarrel stands at (2.5, 0, 0.7) from the start.
    - The broken workbench ("Shack", -4.9, 2.2) reads as a bare metal railing, not a workbench.
    - **Owner note it fails:** "The yard holds only the pod, a broken workbench and the trash bin".
    - **Shots:** `03_spawn.png`, `12b_bale_carry.png`. **Area:** camp.
12. **Flat pink and green fan-shaped planes on the ground.**
    - These are unlit, opaque shapes near Lumi and the camera, and look like a placeholder or debug mesh.
    - **Shots:** `14b_glim_scan_b.png`, `20_spawn_far.png`, `19_play_08.png`, `19_play_09.png`.
    - **Area:** unknown. I could not identify the node; look in the player, Glim and garden overlays.
13. **Lumi looks different on the loading screen.** The loading screen shows a red-and-white "Pixel Lumi" (`ui/loading_screen.gd:14`). The title screen, intro and game show the white and teal screen-face Lumi. The owner calls the hero "the red Lumi", so decide which one is canonical. **Shots:** `02_intro_a.png` vs `18_title_b.png` and `19_play_02.png`. **Area:** intro2 / pod2 / hero.

### Text and UI

14. **Glim's discovery toast is cut off.** It reads "Something in the junk blinks back at you: Glim, a little lantern bot! He'll…", so the key instruction is lost. Toasts also have a faint background and are hard to read on pale ground. **Shot:** `19_play_07.png` (bottom left). **Area:** toast width / ellipsis, buddy.
15. **Workbench: a locked card shows a negative "need".**
    - Carry Stack (locked, "Needs Baler Lv 1") shows "need -4.88K · ~-36 s", and "need 0 · ~0 s" with a red price when you have exactly enough.
    - **Cause:** `ui/upgrade_card.gd:217-221` computes the ETA even when `unlocked` is false.
    - **Owner note it fails:** "It's very clear what you can and can't afford".
    - **Shots:** `10_bench_lumi.png`, `09_upgrades.png`. **Area:** ui2.
16. **Workbench tabs open scrolled partway down.** The Lumi and Bots tabs open with the first row of cards cut off: no names, only Buy/Max buttons visible. **Shots:** `09_upgrades.png`, `10_bench_bots.png`. **Area:** ui2 (focus grab scrolls the ScrollContainer).
17. **Research cards cut off their time.** Labels read "600 cubes · 1:" and "3K cubes · 3:0". **Shot:** `10_bench_research.png`. **Area:** ui2 research card.
18. **Settings: the last row is clipped by the footer.** "Everything else" and the "More settings: …" button are half hidden at the default size. **Shot:** `05_settings.png`. **Area:** settings.
19. **Pause menu: the key legend overlaps the HUD hint bar.** "G goals" appears twice at the bottom right, and the legend advertises "RMB press bale" while baling is locked. **Shot:** `04_pause.png`. **Area:** `ui/pause_menu.gd`.
20. **"Recovered: Worn Sensor Module" toasts don't say what you got.**
    - Robot parts are now worth Parts (ui2), but "Recovered: …" toasts at 10–18 min show no amount.
    - Later "Salvaged: … +25 parts" toasts do show it.
    - "Lumi reached level 5 · +89 cubes +10 parts +5 parts" lists parts twice.
    - **Owner note it fails:** "Every reward toast names exactly what you got".
    - **Log:** `headless_autoplay_watch.log`. **Area:** pace / robot_parts toasts.
21. **The title screen's now-playing tag is invisible.**
    - The label is laid out at (-37,-62) with a width of 1 px.
    - **Cause:** `ui/title_song_tag.gd`. The `clip_text` Label in the HBox has no `size_flags_horizontal = EXPAND_FILL`, so its width collapses to 0. The parent's full-rect anchor may also be zero-size.
    - **Log:** `18_title.log` (probe dump). **Area:** tunes.
22. **The CD player is in Keepsakes before the radio is built.**
    - Keepsakes offers CD Player, Album, Nursery and Seed of the Week from the first minute.
    - The roadmap lists this as still open.
    - **Owner notes it fails:** "The radio is built later at the hub" and "There is no nursery at the start".
    - **Shot:** `16_cd_player_b.png`. **Area:** camp / extras.
23. **Loading stalls.** The bar sits at 57% "Setting the scene" for 15 s or more while the district builds, which is the known intro2 follow-up. `slice built in 14–16 s` even headless. **Shots:** `01_spawn.png`, `02_intro_a.png`, `02_intro_b.png`. **Area:** intro2 / loader.
24. **Performance risk on the Low preset.**
    - At spawn the frame is about 1,660 draw calls and 6.0M primitives, against about 190k in the intro.
    - Census (`scene_stats_low.log`):
      - Litter MultiMesh: 239k instances, 6.8M triangles
      - Garden: 888k triangles at minute 0, with nothing grown
      - FirstFlower: one hidden mesh of 105k triangles
    - The loader's warm-up frame peaks at 17M primitives.
    - On the owner's Mac or a Steam Deck this is the likely source of hitches.
    - **Logs:** `03_spawn_menus.log` (`[perf]`), `scene_stats_low.log`. **Area:** vqa2 / world (litter density and LOD).

---

## P3: polish
25. The settings header says "Q E switch tabs" but Basics has only one tab (`05_settings.png`).
26. The Codex header counters wrap, leaving "achievements" alone on a line (`06_codex.png`).
27. The intro's "BLOOM CORE / GREEN LIGHT · NONE DETECTED" readout is 12 px and 60% alpha, and is never explained (`08_intro_02.png`). It also shows over the cinematic next to the subtitle.
28. Daylight scenes are overexposed and washed out: the white sky, paper litter blown out, and the aerial intro shot nearly white (`08_intro_00.png`, `19_play_*`). The bottom of the frame often has a hard sawtooth shadow edge (`03_spawn_b.png`, `16_cd_player.png`).
29. The pod's door ramp is a flat white slab with no shading (`08_intro_01.png`), and the pod stands upright with no lean or smoke. The owner checklist leaves these open (pod2, crash site).
30. A maxed upgrade card still has a highlighted "Buy" button (Baler, `09_upgrades_bought.png`). Locked Carry Stack shows "Max (5)". "Where it comes from: Base 0" is jargon.
31. The Hub tab's machine column has empty narrow boxes (missing images?) under each machine (`10_bench_hub.png`).
32. The Glim scan marks pieces with big flat white triangles that clutter the hex (`14b_glim_scan_b.png`). It works: 276 pieces marked. Glim's blob shadow is a hard black disc far below him (`14_glim_scan.png`).
33. Title screen: a new player's first, focused button is "PROFILES (Profile 1 · 1 planet)" rather than New game or Continue (`18_title_b.png`). Lumi hovers with no support. The camera move is still static (pod2 is open).
34. No CD was found in 45 minutes of autoplay, so the "New song" toast never showed. Check the CD drop rate early on.
35. The log is noisy on Compatibility: SSR, SSIL, SDFGI, volumetric fog and screen-space AA are set on every run, giving 6 warnings per start. There are 18–31 ObjectDB leaks at exit.
36. The objective trail from Lumi is a thin white line rather than the purple trail (`19_play_01.png`).

---

## Owner checklist: lines that are checked or claimed done

| Owner line | Result | Evidence |
|---|---|---|
| No purple paused screen; loading bar with red Lumi; no music while loading | **Pass**, but the bar stalls (#23) | `02_intro_*.png`; tunes start after `[loader] ready` |
| Intro: one text line at a time | **Pass** | `headless_intro_watch.log`: one subtitle per sample |
| Intro text stays long enough; slower animation | **Pass** | 4.5–5.5 s per line |
| Subtitles at the bottom and readable | **Pass** | `08_intro_03.png`, `08_intro_04.png` |
| No heavy glitch on readable text | **Pass** | Only "I'll be …" and the end of "hold on—" are garbled, and those are the deliberate last words |
| SPACEBAR pauses the story | **Not exercised** | The prompt "Space pause · Esc skip" is shown |
| "Watch the story" | **Pass** | Codex button (`06_codex.png`) |
| Solar map, suns, globes, Rime | **Not re-verified** | Beyond the first 45 min |
| Suno prompts doc; owner songs in audio/songs | **Pass** | `docs/music/`, 7 mp3s |
| Music frozen | **Pass** | Sound effects can't be heard in the container |
| Mac updater | **Not testable here** | |

Unchecked lines whose features the roadmap reports as built:

| Owner line | Result | Evidence |
|---|---|---|
| Pause menu: no Save; fewer buttons; Photo, Codex and Keepsakes stay | **Pass** | 6 buttons (`04_pause.png`); legend overlap is #19 |
| Trade gone; Requests simple; Hub costs parts and cubes | **Pass** | `10_bench_*.png` |
| Workbench tabs: Upgrades vs Build, as few tabs as possible | **Fail** | Still 7 tabs (`10_bench_lumi.png`) |
| Locked tabs show a lock | **Partial** | Tabs are hidden until they open (`data/workbench.json`), not shown locked |
| Settings simplified | **Pass** | Basics plus "Everything else"; clipping is #18 |
| Only 3 currencies | **Pass** | Cubes, Parts and Seeds in the bench header |
| Baling is an unlock; lift upgrades; magnet late; no supply crates | **Pass** | Autoplay: baler at 12.5 min, lift 1 and 2, no magnet, no supply_drop |
| After two bales, about one upgrade | **Pass** | `pace_affordable_at_2nd_bale: 1` |
| First seed at about 20 min | **Fail** | 37 min (#5) |
| Reward toasts name what you got | **Fail** | #20 |
| One message line at a time | **Fail** | #2 |
| Goal text readable | **Fail** | #1 |
| Goals say "Clean a hex" | **Pass** | No "this hex" in data or locale |
| Hex % or base name always shown | **Pass** | "HEX 14% CLEAR" and "OLD TOWN BASE" |
| WREN: one last message at the crash, then silent; towers bring it back | **Pass** | The brief, then nothing until "Relay signal 25%" at 7.3 min |
| Bird and WREN chatter is rare | **Pass** | 0 bird calls/min over 4 min (`--fauna-callcount`); 16 WREN lines in 26 min |
| Starting fences gone | **Pass** | No yard fence. The broken bench looks like a rail (#11) |
| Bales solid, on the ground, look good | **Pass** | `11b_bale.png` |
| A carried bale sits clearly outside Lumi | **Unclear** | In `12b_bale_carry.png` ("CARRYING 1/1") no bale is on Lumi. A tall bale stands about 5 m behind. Needs a closer look |
| Walking off the edge never drops Lumi out | **Pass** | `fell_through 0` in 45 min |
| Yard holds only pod, broken bench and bin | **Fail** | #11 |
| Lumi repairs the bench before use | **Pass** | "E Workbench (broken): repair it" (`19_play_05.png`); the camera clips there (#7) |
| Radio built later; nursery not at start | **Fail** | Keepsakes gives both early (#22) |
| Nights bright enough | **Pass** | `13_night.png` |
| Light buddy follows; scanner highlights pieces; has upgrades and cosmetics | **Pass** | `14b_glim_scan_b.png`, `15_glim_panel_b.png`; toast truncation is #14 |
| Main theme on title; Fall of LM-1 in the intro | **Pass** | `[tunes] now playing greenfall_main (menu)`, `fall_of_lm1 (intro)` |
| Start with the theme plus 1–2 songs; CD player with Random and picking; artists | **Pass** | CDs 3/7, Shuffle, bios (`16_cd_player_b.png`) |
| Title now-playing tag | **Fail** | #21 |

## Typos fixed
None found in the strings I saw.
