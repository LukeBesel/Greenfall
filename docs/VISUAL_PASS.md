# Visual pass: round Verdance (v7look, 2026-11-11)

The first real-renderer look at recent work (renders were blocked by a stale lock for a long time).
Shots are 960x540, Low quality, opengl3 (scratchpad `render.sh`), in `screenshots/v7/`.
Each line: what it shows, file, and OK / fixed (what) / open (why).

## Shots

### HUD and arrival
- Gantry Works arrival title, 1.6 s in (sky veil still lifting): `v7/hub_7_land_1.png`. OK (the title fades in as the veil lifts).
- Gantry Works arrival title: `v7/hub_7_land_9.png`. **fixed**: the title ran under the goal card and was crowded by the HUD lines. It now sits top centre in a column at most 62% of the screen wide (lines wrap), and the top-right cards fade out while it is up and come back after (`HUD.hold_corner`). `--ui-audit` has an `arrival` pass (title vs. the top-right cards, the cube counter, the subtitle bar, off-screen, clipped), every size, scale and language.
- Top-right corner (base % and bases n/6): `v7/pips_0.png`, `v7/cmd.png`. **fixed**: the two faint floating lines are now one glass card in the goal cards' style (base name and %, a 6 px green bar, "VERDANCE BASES 1/6"), placed *under* the goal stack, 10 px apart. In the default Minimal HUD it fades after 6 s idle as before, and since it is at the bottom it leaves no hole above the goal card. The subtitle bar keeps clear of both cards (`Subtitles._goal_rect` reads `HUD.corner_rect`).

### Command view
- Command view (card with OTHER BASES, painted hexes, hints): `v7/cmd.png`. **fixed**: the `--crew-command` hook used a game-time timer that never fired before the wall-clock shot (now `DevHooks.wait_wall`). In the view: the objective beam lay flat as a long white streak across the map (hidden in the Command view now); a light shade dims the world under the overlay so painted hexes and robot marks stand out on the pale ground; robot marks 8 px (were 6); the goal stack steps aside while the view is open (it collided with the hints at UI 1.25 and 1.5). The card reads at a glance.

### Robots
- Mk rank pips, Scoopie Mk III close-up (subtitles off, new `--no-subs` dev flag): `v7/pips_0.png`. **fixed**: the pips were 4 cm diamonds spinning round the lamp and could not be seen at all; bigger ones smeared into the orange lamp. Now a row of crisp gold diamonds with a dark rim (picture texture, `BotBadge._diamond_image`) between the head and the lamp, turned to face the camera; lamp 11 cm (was 8.5).
- Mk pips, Haul Bug Mk II close-up: `v7/pips_1.png`. OK after the fix (two diamonds, grey idle lamp, "z").
- Key-hint pill vs. the hotbar on a 960-wide screen (seen in v6feel's tour shots: it covered STREAK and the hex count): **fixed**: on narrow screens it lifts just over the level bar and the slots, and the subtitle bar keeps above it (`HUD.hints_top`).
