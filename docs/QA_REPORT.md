# Greenfall QA report (in progress)

Build: `claude/kind-wright-rhxixd` @ 602b7fe (QA branch `claude/greenfall-qa`). Date: 2026-11-08.
Status: PARTIAL, more checkpoints rendering. Final version replaces this file.

Priorities: **P1** blocks a playtest, **P2** visible to the owner, **P3** polish.

## P1
- **Objective / checklist text is unreadable at 50% opacity.** Spawn, stand still 6 s: the OBJECTIVE and RESTART CHECKLIST cards fade to half alpha over a bright sky/building backdrop. Cause: `ui/goals_panel.gd` dims to `0.5` after `DIM_AFTER_S` in the default `HudMode.MINIMAL` (`autoload/Settings.gd:74`). Owner note "Goal and task-bar text is easy to read" fails. Shot: `screenshots/qa/03_spawn.png`.
- **Several message lines on screen at once.** Headless autoplay with a text probe (`screenshots/qa/headless_autoplay_watch.log`): in the first 28 game minutes, 20 samples had 2+ toasts stacked and 19 had a toast and a WREN subtitle together, e.g. "Codex entry: Electronics" + "Goal complete · Scoop 15 pieces" + WREN "Lumi, it's WREN..." at 1:16. Owner note "Only ONE message line at a time" (onboard2) fails. Area: toast stack (bottom-left), `story/subtitles`, events banner.

## P2
- **First objective needs a locked ability.** The first objective is "Power the base: sell 3 bales" (`data/objectives.json`) and WREN's crash brief says "Bale junk to power the old base", but baling needs the Baler upgrade (bought at 12.5 min in autoplay). The pause legend also shows "RMB press bale". Owner note "Nothing offers a goal that needs a locked ability". Shots: `03_spawn.png`, `04_pause.png`.
- **Dead early stretch.** Autoplay (`screenshots/qa/autoplay_700.log`, report `autoplay_report.json`): no new goal from 1.6 to 12.5 min, cubes stuck at 37 from 2.2 to 5.2 min and 32 from 9.2 to 11.2 min. First seed at 37 min (owner: ~20 min).
- **Post-intro camera.** After the intro the game camera sits right behind Lumi, whose head fills the middle of the screen; the "OLD TOWN BASE" label sits on top of it. Shot: `08_intro_06.png` (compare the no-intro spawn `03_spawn.png`).
- **Pause menu: key legend overlaps the HUD hint bar** ("G goals" twice, bottom right). Shot: `04_pause.png`. Area: `ui/pause_menu.gd`.
- **Settings: the last row is clipped by the footer** ("Everything else" / "More settings..." half hidden). Shot: `05_settings.png`.

## P3
- Settings header says "Q E switch tabs" with only one tab. `05_settings.png`.
- Codex header counters wrap ("achievements" alone on a line). `06_codex.png`.
- Intro "BLOOM CORE / GREEN LIGHT · NONE DETECTED" readout is tiny, faint and unexplained. `08_intro_02.png`.
