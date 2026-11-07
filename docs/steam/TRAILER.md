# Greenfall trailer and store shots

A 60 to 90 second trailer that tells the whole game in one arc: **junk lot -> clean -> crew -> green -> future
city -> rocket to the next world.** Every shot below can be reproduced with dev hooks; the store screenshots
are the same set at 1920x1080 (`tools/steam/render_store_art.sh` renders them all, one at a time).

How to record: run the command, then capture the window (OBS, 60 fps, 1920x1080) or use `--shots=N
--shot-every=S` for stills. On a real GPU use `--quality=3` (Ultra) and drop `--rendering-driver vulkan`.
The commands below are written for the cloud container (software Vulkan under Xvfb):

```sh
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan --resolution 1920x1080 \
  -- --fresh --quality=2 <FLAGS>
```

`--no-hud` hides the HUD, toasts, subtitles and event banners (Command view and the map keep their UI).
`--time=T` sets the time of day (0.42 morning sun, 0.45 midday, 0.76 dusk, 0.93 night).

## Shot list

| # | Beat (seconds) | What we see | FLAGS | Store still |
|---|---|---|---|---|
| 1 | Cold open (0-6) | Title stage: Lumi hovering over the junk lot at sunset, slow orbit | `--menu` (title screen; crop the menu out, or record before the UI fades in) | |
| 2 | The seam (6-10) | Lumi on the line between junk and meadow, holding still, then looking at camera | scene `res://tools/steam/capsule_stage.tscn`, `--frame=wide` (or `hero` for a 3:1 pan) | key art |
| 3 | Cleaning with lasers (10-18) | Twin claw lasers lock on, junk lifts and glides into the chest hopper | `--no-hud --demo-scoop --demo-yaw=2.0 --demo-dist=2.6 --time-scale=0.4 --time=0.42 --upgrade-levels=multi_lock:3+laser_reach:3` | `store_01_lasers` |
| 4 | Baling (18-24) | The press: belts carry bales into the scale, the auto-baler mid-press | `--no-hud --stations=all --stations-demo --stations-pose=0.6 --spawn-pos=-3.0,0.2 --spawn-yaw=0.96 --cam=close --time=0.45` (drop `--stations-pose` for the full press cycle) | `store_02_baling` |
| 5 | The robots crew (24-32) | Scoopies, Haul Bugs, Drips and a Seedling at work around the base | `--no-hud --robots=scoopie:2@3,haulbug:2@2,drip:1@1,seedling:1@1 --freeze-robots --cam=front --unlock-seeds --stations=all --time=0.45` | `store_03_crew` |
| 6 | Command view (32-38) | Overhead tactical view, zones painted, robots streaming to the far junk | `--robots=scoopie:3@1,haulbug:2,drip:1 --order=clean:priority:far --open=command --time=0.45` | `store_04_command` |
| 7 | Planting and green districts (38-46) | Rows of young plants, watering robots, the ground turning green | `--no-hud --future=3 --spawn-pos=16,22 --spawn-yaw=-1.5708 --cam=side --cam-pitch=-0.08 --time=0.45 --robots=seedling:2@2,drip:1@2` | `store_05_planting` |
| 8 | Future city (46-56) | The restored district grown into a bright, clean city; day, then the same view at dusk with the thin light lines | `--no-hud --future=5 --spawn-pos=16,22 --spawn-yaw=-1.5708 --cam=side --cam-pitch=-0.08 --time=0.45` then `--time=0.76` | `store_06_future_city`, `store_07_future_dusk` |
| 9 | Hologram map (56-62) | Lumi's hand-held planet hologram, one green patch on a grey world | `--open=globe --time=0.4` | `store_08_hologram_map` |
| 10 | Rocket (62-72) | Launch from the pad, climb, arrival at the next base | `--no-hud --rocket --auto-launch=1 --time-scale=3 --time=0.42` (`--shots=4 --shot-every=20` for stills) | `store_09_rocket` |
| 11 | End card (72-80) | Logo over the seam shot, "Wishlist on Steam" | composite: `library_logo_1280x720.png` over `master_wide.png` | |

Extra angles that cut well:

- Dusk and night over the junk lot: `--time=0.755` / `--time=0.93` (the lamps and Lumi's lens light the litter).
- Biomes from other bases: `--hub=25 --time=0.71` (coast), `--hub=28 --time=0.4` (dunes), `--hub=24 --time=0.45` (frost).
- A world event: `--event=salvage_surge --event-at=2 --event-look=1 --streak=95`.
- The demo's end screen: `--demo` then try to build base level 3 (or launch a rocket).

## Music and pacing

Use the in-game score (synthesized at start-up; `tools/render_music.gd` writes it to WAV). Keep cuts on the
beat, slow in shots 1-2, quicker through 3-6, and let 8 breathe. No narration; three short title cards at most:
"One small robot.", "One very big cleanup.", "Wishlist now on Steam".

## Steam's trailer rules (summary)

- Show gameplay in the first seconds; the first frame becomes the thumbnail if none is set.
- 1920x1080, H.264, 5000+ kbps, 30 or 60 fps; up to about 2 minutes.
- No review quotes or prices; avoid "Early Access" wording unless the game is in Early Access.

## Re-rendering the store art

```sh
tools/steam/render_store_art.sh /home/user/Greenfall/screenshots/steam all   # masters + shots + capsules + icons
tools/steam/render_store_art.sh /home/user/Greenfall/screenshots/steam compose  # capsules and icons only
```
