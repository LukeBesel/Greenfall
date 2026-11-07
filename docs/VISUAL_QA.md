# Visual QA render checklist

One line per view: the dev-hook command that frames it, what to look for, and its status.
Renders are slow in the container (Forward+ on lavapipe), so triage at Low/Medium and keep High
for before/after pairs. Wrapper: `tools/shot.sh NAME <flags>` (env `QUALITY=0..3`, `RES=WxH`,
`DELAY=s`); before every render wait until no other `godot ... --rendering-driver vulkan` runs
and `free -g` shows >= 6 GB available. Frontier overviews need `DELAY>=140` (the first frames
compile shaders for over a minute).

Status: **ok** (rendered, clean) · **fixed** (glitch found and fixed, re-rendered) ·
**fixed (code)** (root cause fixed, not re-rendered) · **open** (known issue) · **todo** (not rendered
this pass).

## Automated checks (no render)

| Check | Command | Status |
|---|---|---|
| UI fits the screen, text overflow, D-pad reach (all workbench tabs, Command view, globe, codex tabs, pause, every Settings tab) | `godot --headless --path . -- --fresh --pad-audit --audit-size=1280x720 --ui-scale=1.0 --locale=de` (also `1280x800 --ui-scale=1.1`, `--locale=pseudo`; add `--audit-why` to print the widest min-size chain) | fixed: pass at 1280x720 / 1280x800 @110% / 1920x1080 in en, de, pseudo (pseudo only truncates three workbench tab names with an ellipsis) |
| Title menu UI | `godot --headless --path . -- --menu --pad-audit --audit-size=1280x800 --ui-scale=1.1` | owned by "first" |
| Unit tests | `tools/run_tests.sh` | ok |

Note: headless runs have no window, so without `--audit-size` the audit measured a bogus
1164x1164 screen and its clipping results were meaningless.

## Frontiers

| View | Command (flags after `tools/shot.sh NAME`) | Look for | Status |
|---|---|---|---|
| Cradle Returns overview | `--frontier=cradle_returns --frontier-cam=110,-0.3,0,50 --frontier-nohud` (QUALITY=2, DELAY=170) | apron shading, lawn colour, tower glass, perspective lean | fixed |
| Sunken City overview | `--frontier=sunken_city --frontier-cam=95,-0.42,0,55 --frontier-nohud` | dark shadow slabs on the near water | fixed |
| Frozen Port overview | `--frontier=frozen_port --frontier-cam=95,-0.3,0,55 --frontier-nohud` | faceted far mountains, grey sky | fixed |
| Dust Flats overview | `--frontier=dust_flats --frontier-cam=95,-0.3,0,55 --frontier-nohud` | dune seams, wrecks sunk/floating | todo |
| Restored states | add `--hub-level=5` (and `--drain=6` for the Sunken City, `--thaw-all` for the port) | white/futuristic landmarks, glow thinness | todo |

## Starter district and future layer

| View | Command | Look for | Status |
|---|---|---|---|
| Start view, hub levels 1-5 | `DELAY=60 tools/shot.sh NAME --hub-level=N` | junk inside the shack, floating props, yard seams | todo |
| Future layer 1-5 | `--future=N --hub-level=5` | thick glow lines, straight hex borders | fixed (code): glow thinned globally |
| Night | `--time=0.0` (0.25 dawn, 0.75 dusk) | fog banding, lamp glow | todo |
| Lake district shoreline | a district with water hexes (`--hub=N`) | hex-straight shoreline | fixed (code): warped shoreline |

## Views and screens

| View | Command | Look for | Status |
|---|---|---|---|
| Command view zoomed out | `--open=command` | junk / gardens popping out past 110-160 m | fixed (code): ranges lifted while open |
| Hologram map (M) | `--open=globe` | clipping, overlap | todo |
| Lens view (V) | `--lens` | near-plane clipping | todo |
| Workbench tabs, codex, builder | `--open=upgrades --tab=ID`, `--open=codex` | layout at 1280x720 | fixed (audit) |
| Photo mode | `--photo=3` | panel layout | todo |
| Pause + Settings | pad audit | layout | ok (audit) |

## Cinematics

| View | Command | Look for | Status |
|---|---|---|---|
| Rocket launch (boarding, countdown, ignition, lift-off) | `--hub-level=5 --auto-launch=1 --rocket-shots=3.0,6.0,9.6,12.0 --rocket-shot-wait=25 --rocket-shot-name=NAME` | yard sign, fence, wires, lamp heads between lens and rocket | fixed |
| Rocket arrival | `--rocket-arrive --rocket-shots=...` | camera inside the yard clutter | todo |
