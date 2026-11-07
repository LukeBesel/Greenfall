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
| UI fits the screen, text overflow, D-pad reach (all workbench tabs, Command view, globe, codex tabs, pause, every Settings tab) | `godot --headless --path . -- --fresh --pad-audit --audit-size=1280x720 --ui-scale=1.0 --locale=de` (also `1280x800 --ui-scale=1.1`, `--locale=pseudo`; add `--audit-why` to print the widest min-size chain) | fixed: pass at 1280x720 / 1280x800 @110% / 1920x1080 in en, de, pseudo; [vqa2] workbench tabs share the row by name length, so pseudo no longer truncates Research / Cosmetics / Contracts (de @110% still ellipsizes one contract "Annehmen (15:00)" button) |
| Title menu UI | `godot --headless --path . -- --menu --pad-audit --audit-size=1280x800 --ui-scale=1.1` | owned by "first" |
| Unit tests | `tools/run_tests.sh` | ok |

Note: headless runs have no window, so without `--audit-size` the audit measured a bogus
1164x1164 screen and its clipping results were meaningless.

## Frontiers

| View | Command (flags after `tools/shot.sh NAME`) | Look for | Status |
|---|---|---|---|
| Cradle Returns overview | `--frontier=cradle_returns --frontier-cam=110,-0.3,0,50 --frontier-nohud` (QUALITY=2, DELAY=170) | apron shading, lawn colour, tower glass, perspective lean | fixed |
| Sunken City overview | `--frontier=sunken_city --frontier-cam=95,-0.42,0,55 --frontier-nohud` (QUALITY=1; High runs out of memory here) | dark shadow slabs on the near water | fixed (left slab); open: dark patches below the rim buildings (right edge, and under the tall block top right). [vqa2] diagnosed: not sun shadow (the point sees open sky, and it shows at Low where shadows end at 35 m), not wet silt (the warped hex there is a water hex, Water draws), junk inside it is unshaded; it is building-shaped and sits *below* each rim building on screen, so it is either the building's sunk 7.5 m reading through the water or a water reflection term. See the diag note below |
| Frozen Port overview | `--frontier=frozen_port --frontier-cam=80,-0.28,0,55 --frontier-nohud` | faceted far mountains, streaks on steep faces, polygon crack grid on the ice, grey sky | fixed |
| Dust Flats overview | `--frontier=dust_flats --frontier-cam=95,-0.3,0,55 --frontier-nohud` | dune seams, wrecks sunk/floating | ok: no seams, wrecks seated. [vqa2] the debris mounds under junk read as dark rubble crescents at 100 m; they now take the frontier coat (sand on top), lighter but still visible as small crescents (minor) |
| Restored states | `--future=5` (every hex Thriving; `--hub-level` alone does not restore a frontier) plus `--drain=6` for the Sunken City, `--thaw-all` for the port | white/futuristic landmarks, glow thinness | fixed: holo boards read mirrored from behind (now a back-face label). Sunken City drained and green: ok. open (minor): Frozen Port restored shows FutureLayer's far glass spires as flat translucent blue columns over the snow mountains, and a soft white haze band across the lawn near the rim; Dust Flats / Cradle restored not rendered |

## Lumi and HUD

| View | Command | Look for | Status |
|---|---|---|---|
| Lumi's designs, side / 3/4 / back | `godot --path . res://scenes/design_lineup.tscn -- --fresh --out=NAME` (xvfb, vulkan, 1600x640) | ears reading as eyes from the side | fixed: vented side-pods, thin glow stripe, antenna stub |
| HUD bottom at the hex-clean moment | `--first-demo=reveal --time-scale=0.05 --spawn-hex=30` at 1280x720 and 1280x800 | notification stack, context line, level bar and floating text crowding | fixed |

## Starter district and future layer

| View | Command | Look for | Status |
|---|---|---|---|
| Start view, hub levels 1-5 | `DELAY=60 tools/shot.sh NAME --hub-level=N` | junk inside the shack, floating props, yard seams | ok: levels 1 (default start), 3 and 5 rendered: no junk in the shack, no floating props, no seams |
| Future layer 1-5 | `--future=N --hub-level=5 --time=0.8` | thick glow lines, straight hex borders | fixed: yard lines thin at dusk (future=5); [vqa2] fixed: the dark slab under the spawn camera was the level-4 solar row (dark glass panels at the yard's front edge, z 7, right under the camera). It now stands in the yard's front-right, in front of the level-3 office, with a collider |
| Night | `--time=0.0` (0.25 dawn, 0.75 dusk) | fog banding, lamp glow | ok: moonlit, festoons and lamps glow, no fog banding |
| Robots against walls | `--robots=scoopie:4,haulbug:2 --time-scale=2 --spawn-pos=8,-3 --spawn-yaw=-1.2` (plus `--trace-bot=NAME` headless) | robots grinding into walls, camera in clutter | ok: robots slide along the fence and curbs and unstick (stall watch); [vqa2] fixed: the camera arm ended inside the hub street lamp (no collider), now a pole collider |
| Lake district shoreline | a district with water hexes (`--hub=N`) | hex-straight shoreline | fixed (code): warped shoreline |

## Views and screens

| View | Command | Look for | Status |
|---|---|---|---|
| Command view zoomed out | `--open=command` | junk / gardens popping out past 110-160 m | fixed (code): ranges lifted while open |
| Hologram map (M) | `--open=globe` | clipping, overlap | todo |
| Lens view (V) | `--lens` | near-plane clipping | ok |
| Workbench tabs, codex, builder | `--open=upgrades --tab=ID`, `--open=codex` | layout at 1280x720 | fixed (audit) |
| Photo mode | `--photo=3` | panel layout | ok (960x540 Low: panel fits, no overlap) |
| Pause + Settings | pad audit | layout | ok (audit) |

## Sky

| View | Command | Look for | Status |
|---|---|---|---|
| Faint orange / tan dots in the day sky | any daytime shot | dust motes, particles, sky noise | fixed (code): PhysicalSkyMaterial adds `night_sky` under the sun too (times the reddish extinction), so the 2600 stars showed as faint warm dots by day. `SkyDirector` fades the star texture with the sun (6 steps, only the star pixels are rewritten) |

## Cinematics

| View | Command | Look for | Status |
|---|---|---|---|
| Rocket launch (boarding, countdown, ignition, lift-off) | `--hub-level=5 --auto-launch=1 --rocket-shots=3.0,6.0,9.6,12.0 --rocket-shot-wait=25 --rocket-shot-name=NAME` (DELAY=1000) | yard sign, fence, wires, lamp heads, holo boards between lens and rocket; camera inside the vapour | fixed; [vqa2] fixed (code): the mid-ground lamp in the ignition shot was the hub's own street lamp (slice.gd ruin bits), now hidden with the yard dressing in the close shots |
| Rocket arrival | `--hub-level=5 --rocket-arrive --rocket-shots=3.0,6.5,9.0 --rocket-shot-wait=25 --rocket-shot-name=NAME` (DELAY=900) | camera inside the yard clutter | fixed: the touchdown camera stood inside the yard next to the recycler looking across the back fence; it is in the open lot east of the pad now and the yard dressing hides for the close shots, as in the launch |
