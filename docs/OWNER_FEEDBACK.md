# Owner feedback checklist

This is every note from the owner's playtests and requests, and who is working on each. A box is checked only after the change has been seen working in a merged build: a render, a headless check, or a test. Merging the helper's branch is not enough. Update it at every merge.

Helper branches: intro2, onboard, world2, ui2, style, fauna2, ship, pace, camp, buddy, eggs2, orbit, hero, sysmap, p_ochre, p_tidewell, p_anvil.

## Start, loading and intro (intro2)
- [x] (intro2 merged; follow-up on claude/greenfall-leftovers: the district now builds across frames, the bar shows real progress and Lumi keeps moving; one ~0.5-0.8 s step remains at the end of the build) There is no purple "paused" screen at launch. A real loading screen shows a loading bar with the red Lumi picking up garbage in a line. No music plays during loading. (Reported in playtests #1 and #2.)
- [x] Only one text line shows at a time.
- [x] The text stays long enough to read, and the animation is slower and longer.
- [x] Subtitles sit at the bottom and are readable against the background.
- [x] Readable text has no heavy glitch effect. Heavy glitching is used only on redacted story text.
- [x] SPACEBAR pauses the story.
- [x] There is a way to rewatch the story ("Watch the story").
- [ ] The loading screen is a tiny 3D scene of the real world, with the real red Lumi model scooping junk along the bar. (pod2)
- [ ] Title screen: the camera starts high over the junk, drifts past the smoking pod at the crash site, and glides down to Lumi cleaning piece by piece. (pod2)
- [ ] The ark is redesigned in our Seedglider style. (ship)
- [ ] Lumi's eyes have no glitches, no double eyes, and don't close slowly.
- [ ] The escape pod door looks good and doesn't glitch.
- [ ] The pod matches the ship design, and its animations match the pod.
- [ ] Crash site: the pod leans, smokes, and glitches with sparks until it's repaired. It looks great after each repair stage.

## Story and WREN (onboard)
- [ ] It's clear right away why Lumi cleans: picking up trash powers things and lets you build bots.
- [ ] The SIGNAL % is explained. It is now the signal-tower strength.
- [ ] WREN is introduced as the ark's caretaker AI. It leaves one last message as the pod crashes, then goes silent.
- [ ] Signal towers bring WREN back: better towers unlock more messages, and they get clearer at higher signal.
- [ ] Bird and WREN chatter is rare, never constant.
- [ ] Only ONE message line is on screen at a time, anywhere in the game (subtitles, toasts, rewards, hints). Every message stays up long enough for an average reader. (onboard2)
- [ ] Goal text after leaving the pod stays long enough to read.
- [ ] Goal and task-bar text is easy to read.
- [ ] Goals say "Clean a hex", never "this hex".
- [ ] The target hex has a glowing laser outline on the floor that pulses softly. All hex outlines look like lasers.
- [ ] The hex % (or the hub/base name) is always shown.
- [ ] Every objective has a purple trail or waypoint (e.g. "Read a memory shard"), so the player always knows where to go.
- [ ] Requests (the old contracts and events) unlock later in the game.
- [ ] Nothing offers an event or goal that needs a locked ability (dig, bale, lift and so on).

## World (world2)
- [ ] The starting fences are gone.
- [ ] Hitboxes work on every prop: you can't walk through fences, props or junk heaps.
- [ ] You can't stand inside junk piles, so you can't vacuum a whole pile from inside it.
- [ ] Bales sit on the ground and never clip into it.
- [ ] Bales are solid (not transparent or blue) and look good.
- [ ] A carried bale sits clearly outside Lumi.
- [ ] The entire world is trashed. No cleared spots are visible from spawn, and there are no empty streets.
- [ ] Starting hexes have no large items (fridges and the like).
- [ ] When you land nothing works: no lit streetlamps, neon signs or string lights, and nothing powered. Everything is broken and comes back on only when you fix or build it (parts and cubes) or restore the area. (world3)
- [ ] Walking off the edge never drops Lumi out of the world. (orbit)

## Walk around the planet (orbit)
- [ ] Each planet is a real, small, round planet you can walk all the way around, like moon sweeper games. The curve is subtle: planets are big, so the ground looks nearly flat nearby and only gently curves at the horizon. No exaggerated tiny-planet bending.
- [ ] It is big enough that you never set foot on most hexes, because the bots clean those.
- [ ] The whole planet is covered in hexes. Bases are sites on the globe, so far apart that you need the rocket to travel between hubs on the same planet.
- [ ] Only the area near Lumi is loaded. Bots working far away are simulated cheaply.
- [x] Order: a prototype and plan first, then the owner reviews, then a rollout split across helpers. (prototype done, lap test passes)
- Owner decisions (Nov 8): BIG planets (164k hexes, R 1.84 km, 11.6 km around). Planet % counts the hub regions; the rest greens on its own. Travel is the x4 boost plus a buyable vehicle later, with the rocket between hubs. REAL day and night sides of the planet.
- [ ] Rollout phase A: Lumi in the real game on the sphere. (orbit)
- [ ] Rollout phases B-F: hex field and saves, robots and Command view, hub sites, future/system map/Homeward, Mac performance. (3-4 helpers)

## Pacing and economy (pace)
- [x] There are only 3 currencies: cubes, parts and seeds.
- [x] You can pick up only a few pieces at a time at first. Upgrades grow this to today's speed.
- [x] Picking up large items needs a lift-strength upgrade.
- [x] Baling is an unlock upgrade.
- [x] After two bales you can afford about 1 upgrade.
- [x] Auto-cubing and automation come much later.
- [x] Overpowered upgrades are slowed down.
- [ ] The full game takes about 20 h: grindy, but upgrades speed it up and something new arrives every 5-20 min, never a long stretch with no goal. Planting ramps up around 1-2 h, and the first planet takes 3-4 h, with plenty going on throughout. (pace2)
- [x] The magnet comes late, is capped, isn't glitchy, and never pulls pieces Lumi can't lift.
- [ ] The first seed comes at about 20 min (or with super luck). Planting ramps up at about 1 h.
- [x] Planting can come at 1-2 h: the garden takes off (Pollinator Survey) at about 75-110 min bot time (pace2: 106, was 163).
- [ ] The whole game takes about 20 h, grindy but never boring: something new every 5-20 min, no goal-less stretch over 10-15 min. (pace2: targets and bot measurements in docs/BALANCE.md "Whole-game curve"; Verdance measured to 3.7 h bot, later planets still to measure.)
- [ ] The first planet (Verdance, up to the launch to another planet) takes 3-4 h. (pace2: the Mk V opens at Verdance 50% or a level 3 base, 60k cubes.)
- [x] You can unlock the next planet without 100% on the first one: drives open from partial progress (Mk V: Verdance 50% or a level 3 base; Mk VI: another planet at 50%); only the Homeward rocket needs the whole system.
- [x] You can't 100% a planet until you bring tools from later planets (Deep Drill from Ochre, Tide Pump from Tidewell, Cryo Beacon from Rime, Heat Core from Anvil); the gated Verdance areas say "Needs Deep Drill: found on Ochre".
- [x] The rare-part beam indicator is an upgrade, and dig events appear only once digging is unlocked.
- [x] Supply crates never appear out of nowhere: supplies are only found in the world. Every reward toast names exactly what you got, in readable text.

## Landing site and yard (camp)
- [x] The yard holds only the pod, a broken workbench and the trash bin. Everything else appears when it is unlocked. (camp, camp2)
- [x] Lumi plays a short repair animation on the workbench before it can be used. (camp)
- [x] Nothing appears on its own (not even the composter): everything besides the bench and bin is a Hub build. One-time builds drop off the Hub build list once built. (camp2: data/builds.json + HubBuilds; Build/Upgrades tabs by ui3)
- [x] The trash bin is upgradeable (bin → shredder): Dented Bin, Scrap Skip, Weigh Skip, Compactor, Shredder. (camp)
- [x] There is no nursery at the start. It needs the first seed plus cubes. (camp)
- [x] The radio is built later at the hub. It sits away from the workbench, and its prompt names it. (camp: CD player by the right fence)
- [x] Yard interactables are at least about 3 m apart. (camp: test + --camp-report)
- [~] The radio and jukebox stop the background music and play only their own song. (camp: radio + Audio.mute_score for tunes' songs; the jukebox egg is eggs2's)
- [x] The observatory telescope sits away from spawn and its view doesn't glitch. (camp: back edge, zoom fixes)
- [x] Buying a machine upgrade (belt drive, baler and so on) makes it visibly appear, with a build effect and a pointer to it. (Bug: they bought both and nothing appeared.) (camp: upgrades need their machine; every build gets a reveal)

## Workbench and menus (ui2)
- [ ] The workbench is simple, small and futuristic.
- [ ] The Bots page is simple and uses parts only.
- [ ] Trade is gone.
- [ ] The hub page is simple and costs parts and cubes.
- [ ] Currency icons look cool.
- [ ] Locked tabs and options show a lock and can't be opened.
- [ ] It's very clear what you can and can't afford.
- [ ] Upgrade screens as simple as the owner's reference: a plain one-line list (icon, name, level pips, price tag, "?" locked rows) plus one detail panel with a big Install button. 3-4 tabs at most. (ui5)
- [x] Photo mode comes with a camera-bot Hub build: unlocked early-ish, but it needs a good amount of parts. Before that, no photo mode. (camp3: Blink, hub level 2 or ~25 min, 400 cubes + 80 parts)
- [ ] The Locker is a physical yard build bought with parts; open it with E for cosmetics. It is not a workbench tab. (ui5)
- [ ] Workbench tabs: Upgrades holds everything with tiers; Build holds one-time buildings, which drop off once built. As few tabs as possible. (ui3 + camp2)
- [ ] The upgrades page isn't glitchy or bulky.
- [ ] Settings are simplified.
- [ ] The pause menu has no Save button: saving is automatic. "Quit" saves and returns to the title screen. Fewer buttons, but Photo mode, Codex and Keepsakes stay.
- [ ] The Requests page is simple.

## Cosmetics and Locker (style, hero)
- [ ] The Locker unlocks with the hub and combines cosmetics and the builder, with a selector for which bot you're editing.
- [ ] Cosmetic parts unlock throughout the game.
- [ ] Locked bot designs are hidden (silhouette or "???").
- [ ] Character builder: colours, eyes, head piece, held item, companion, glow and laser colours.
- [ ] The red antenna beacon stays on Lumi's head and never drifts off. (hero)
- [ ] Aurora's model matches the concept art exactly: a round pill head, the stalk-and-paddle fin, the cyan chest band, arms up and out, and a chunky torso. It needs much more detail, with colours sampled from the reference down to the scuffs, speckles and glint colours. The owner reviews it again before the other 5 designs. The owner reviews it, then the other 5 designs follow.

## Light buddy and night (buddy)
- [ ] Nights are bright enough, or day lasts longer early on.
- [ ] A light-bot companion follows Lumi.
- [ ] Its hex scanner highlights the pieces left in your hex.
- [ ] The buddy has upgrades and cosmetics.

## Wildlife (fauna2)
- [ ] Bird flapping and calls are rare, not constant, and don't glitch.
- [ ] You can feed the birds.
- [ ] Animals (cats, deer, fish) look real and cute.

## Easter eggs (eggs2)
- [ ] Gnomes and other collectibles are picked up into a Codex Collection page. No display at the base.
- [ ] One Museum is built near the end (the Verdance launch phase), left behind for whoever comes after. It shows every collectible, with empty plinths for missing ones. Filling it is the 100% goal.
- [ ] The jukebox stops the music and plays its own tune.
- [ ] The brass telescope sits away from spawn and its view doesn't glitch.
- [ ] The TV shows images that tell what happened to the world.

## Ship, planets and system (ship, sysmap, p_*)
- [ ] The spaceship has an original design and gets cooler with each tier, not just bigger.
- [x] The solar-system map uses the detailed planet globes and zooms into the chosen planet. (sysmap, renders)
- [ ] Planets unlock in order. Undiscovered planets are hidden or shown as a silhouette, and there is no "unvisited" label. (sysmap2)
- [ ] Clean map view: no names, "you are here" or text over the planets, one small info panel, and no overlapping text anywhere. (sysmap2)
- [x] Every planet has the same two suns, sized by distance.
- [x] Planet globes are detailed from afar, with the ice-spike, sand and fire rings.
- [x] Rime is merged.
- [x] Rime at night is bright enough to read, and the gas giant is smaller. (rime2, render v2)
- [ ] Ochre, Tidewell (ocean, hover over water) and Anvil (red, Nether vibe) are merged.
- [ ] The next planet unlocks without 100% on the current one (about 50% plus the drive). Today the Mk V and Mk VI drives require a 100% planet; fixing that. Only the final launch home needs everything. (pace2)
- [ ] You can't 100% a planet until you bring tools, bots and upgrades from later planets (e.g. a deep drill from Ochre, a water bot from Tidewell). Gated hexes say what they need, so you return later with new toys. (pace2)

## Music and docs
- [x] The Suno prompts doc has a grinding playlist per planet, with context in each prompt, as plain copyable text plus a .txt file.
- [x] The owner's first 5 songs are in audio/songs/.
- [ ] The main theme plays on the title screen and The Fall of LM-1 plays in the intro. (tunes)
- [ ] You start with the main theme plus 1-2 songs. The rest unlock from CDs found in the rubble, with a readable "New song" toast. (tunes)
- [ ] Unlocked songs shuffle at random with quiet gaps between them. The radio is a CD player with a Random mode, and it also lets you pick a song. (tunes)
- [ ] Each song's intact CD is found on its home planet and unlocks it for good; the artist is shown as from that planet. (tunes)
- [ ] 5-10 rare scratched CDs per planet hold songs from other planets. Each plays once (Play now / Keep), then breaks, and is clearly labelled as one listen. (tunes)
- [ ] Later, a light-buddy "Music" upgrade downloads your CDs so you can play any found song anywhere. (tunes + buddy)
- [ ] New MP3s can be dropped in by song name. (tunes)
- [ ] Every song has a funny in-world artist with a short bio, drawn from a recurring cast of about 6-8 artists. Artists appear on the DVD toast, in the radio and on a Codex Artists page. The game never mentions Suno; the credits just say "Music by Lucas". (tunes)
- [x] Music is frozen. Sound effects stay satisfying.

## Download
- [x] The Mac updater script works with no "Open Anyway" prompt (rolling `latest` release).

## Nov 8 (art bar + helpers)
- [ ] Every build and building on every planet must look as good as Moon Sweepers hubs (kit, yard, p_anvil, p_ochre, p_seas, orbD). The rejected example is the Anvil restored yard: white CG turbines, a flat slab, a flat green carpet.
- [ ] Use as many helpers as needed, all aligned and not overwriting each other (file ownership in owners.md; main merges).
- [ ] Fully build the walkable round planets (orbB to orbE).
- [ ] Planets come in different sizes: Ochre (2nd) a bit smaller, later ones larger, Anvil (last) the largest. Later planets unlock more and speed things up so the game keeps moving (orbB grid sizes, orbD hub counts, pacing).
- [ ] Planets grow much larger as you go; the last (Anvil) is about 4x the starter (radius 2x). Data has been set to 0.85 / 1.3 / 1.6 / 2.0x.
- [ ] The 3rd planet (Tidewell) unlocks a bot-building bot (Bot Fabricator) so fleets reach "tons of bots"; bots go out and work on their own.
- [ ] Finish the game to Moon Sweepers quality, with no glitches. Simple to understand, guide the player, keep it interesting and super visually appealing. All buildings look good and make sense. Run quality and visual tests.
- [ ] Stay within the usage limit (owner: keep under about 10%): helpers resume after the weekly limit resets on Nov 10, 19:00 UTC.
- [ ] All cosmetics live at the Locker: Lumi, Glim, bots and rockets. Nowhere else edits looks (ui).
- [ ] Send a picture of the workbench view (main: render queued until memory frees).
- [ ] Bots are BUILT at the workbench (Bots tab, Fabricator queue). Their LOOKS are designed at the Locker, per robot type or job, and every bot of that type wears the design (e.g. all planting bots green, including newly built ones) (ui, orbC).
- [ ] Owner (Nov 8, later): no need to send pictures for now. Focus on finishing everything already agreed. Renders only where a helper needs one to check its own work.
- [ ] Workbench (and Locker): simple is good, but restyle it futuristic and robot-like. Not full screen (like Moon Sweepers): floating modules with gaps that show the environment, slightly see-through glass, chamfered corners, thin glowing lines, a hologram open (ui).

## 2026-11-08 playtest (round Verdance, from the start)
Direction: the flat world's vibe is better, so build it into the round world: buildings, signs, colours, purple indicators. Make the round world close to flat, then remove the flat world. Focus only on the first planet (Verdance) for now.

**Menus, audio and intro**
1. The loading screen Lumi still has two sets of eyes overlapping. Make the loading screen simple and clean: Lumi (or the round guy) flying around, or just a loading circle, on a good background, animated continuously.
2. Remove the Credits button.
3. Changing the quality preset is very slow. Default it to Medium.
4. If the settings only have basic options, drop the "Basic" header.
5. Music:
   - The main theme played twice in a row.
   - Rules: main theme first when the game opens; it is the most common song; other songs mixed in; never the main theme back to back.
   - Longer gaps between songs.
   - Music started far too early after the pod landed: wait a few minutes.
6. A voice-over for the intro text.
7. The intro fall: the whole planet should look covered in trash. Parts not yet loaded looked clean.

**Start area**
8. Define the trash bin area clearly.
9. The trash bin and workbench should be closer together.
10. No vehicle at the start.
11. The floating buddy is a build: you don't get him right away.
12. The pod's hitbox is terrible.
13. The pad should be cleaner and flatter. It looks like I'm standing on trash.
14. Trash right outside the pad: there's a clean ring around it, so it's a long walk to reach trash.
15. Way more trash, like the flat world, with more of it close to the pod. Bring back the city buildings.
16. The water-to-land edge is glitchy and looks bad.

**Guidance and progression**
17. The objective markers are barely noticeable. Use a beam up to the sky with a ring around the target.
18. The story doesn't say why we're picking up trash. WREN should say something like "pick up pieces and look for parts to build the receiver."
19. Throwing trash in the bin needs a visual, glint or sound: it just disappears.
20. It says to save up for the Baler, but the Baler isn't unlocked to save up for.
21. No instructions on how to make a bale after the upgrade.
22. A carried bale still clips into the body.
23. "Build the signal tower" isn't an option in the workbench.
24. The workbench shows Bots and Research early, before finding anything. Those come ~30 min in.
25. Clicking an upgrade should show its details; only the price square buys.
26. The start is too slow ("I already want to quit"): too much walking between trash and the bin. Speed it up.
27. Upgrade types stay in a fixed row/order in the workbench, not moving around by price or affordability.
28. Workbench tabs (Bots, Research, etc.) unlock by upgrading the workbench itself (workbench tiers), not on their own.

## 2026-11-08 playtest 2
29. Lumi's eyes still looked like two sets: fixed on main (one solid glowing eye per side) and needs checking. In the intro, when the pod lands, his eyes are almost closed and look weird.
30. No human voice-over. Use robot beeps under the lines: done on main.
31. No "New sighting" popups during the intro animation: done on main.
32. Birds chirp far too much again.
33. The purple indicator points at nothing. In the screenshot, the ring was on a road cell while the step was "Empty your chest into the trash bin". Also, two cards showed at once ("OBJECTIVE: Save up for the Baler" plus "NEXT STEP: Empty your chest..."): there must be only one.
34. After the signal tower restores the connection, WREN only says hello. WREN should narrate the goals and what we're trying to do to get back home.
35. The starting hexes can't hold large items, because then you can't fully clear a hex.
36. When a hex reaches 95% clear, the rest of it clears automatically: the hex counts as clean and its leftover pieces are swept away.
37. The purple beam/ring and the yellow pointer should NOT point at parts or leftover pieces. Use them only to lead to PLACES a goal needs (bench, bin, tower spot, greenhouse...), and only when necessary.
38. After walking away I couldn't tell which way home was. The pod's smoke should be a super tall plume, a landmark for home visible from far away.
39. A hex stuck at 96% with no findable leftovers: this is the 95% rule (item 36). It's the top priority.
40. Map view (M) looks great but is a little glitched, and it's too close to Moon Sweepers (legal risk). Make it our own style. The launch/travel UI must NOT be in the map; it appears only when you press E at the rocket.

## 2026-11-08 direction: Verdance must feel finished
41. The first planet must be completely free of glitches, easy to make progress on, and simple enough that a young kid could understand and play it. Make it feel real and professional.
42. The city feels empty: about 3 buildings and that's it. It doesn't feel whole or working. Verdance needs a full, lived-in city (streets, blocks, districts, signs, lights, parked junk), like the flat world's districts or better.

## 2026-11-09 playtest 3
43. The little floating bot (Glim) should be a build and a much bigger deal: a helper who followed you and clung to the pod to be with you.
44. The water bot unlocks way too fast.
45. Every time the water bot cleans a hex, WREN's "I can see the bottom…" line plays again. It should play once.
46. Unlock the Scoopie first, and have just him for a while before the Hauler.
47. After building bots the first time, the "I hear another voice" line must not repeat every time.
48. The first seed is hard to find: after a bit, show an indicator to where it is.
49. Far too many messages at once; it's hard to know what's happening. Cut them way down.
50. The beeping is still super annoying: way less, or none.
51. Planted plants can't be seen, so I don't know where to water or whether it's working.
52. Haulers should also pick up the bales I make.
53. The water still doesn't look like water.
54. Lumi should need an upgrade to hover over water.
55. The objective led me under a building I can't get to. Every target must be reachable.
56. Overall: it still needs more polish.
57. Balance the timing (base 3 and the rest) so the first planet takes 4–5 hours in total.
58. Focus on making the first world fully playable, fun, well paced and good-looking; what works here feeds into the other worlds. Moving on to the next planet comes at 4–5 hours, NOT at 100% cleaned. The planet might be only about 20% cleaned at that point. Cleaning the rest is optional, for later.
59. For cleanup work that doesn't much affect the game (removing the flat world and the like), use Opus helpers.
60. The storyline must make sense: there must be real in-world reasons for what the player does, not "because it's a game".
61. Before flying off Verdance (at 4–5 hours), the player should have seen about 6 of its bases (hubs).
62. More songs are coming later. Set music up so songs are easy to add, swap and adjust (which planet, when, how often, volume) without code changes. The same goes for everything as the game grows to the other planets: keep it easy to change and adjustable per planet.
63. Cubes should grow semi-exponentially, like an incremental game: income and prices multiply as you go (bigger numbers each base), not a flat or linear price ladder. Time per step stays roughly steady because income grows with the prices.
64. Numbers should be big: a few thousand cubes is far too small for major steps. Upgrading the rocket enough to leave the planet should cost tens or hundreds of thousands of cubes.
65. Only three songs on Verdance gets boring. Until more songs arrive, play more of the songs we have there (done: Ochre's three songs also play on Verdance, owned from the start, and the main theme comes up less often; see `data/songs.json` `planets.verdance`).
66. The base names are up to us (kept: Landing Yard, Garden Row, Gantry Works, Signal Heights, Fairground, Stack Works).
67. The people asleep on the ark are not "the Makers" (and not "the Gardeners"). The owner picked **the Settlers**.
68. Songs and breaks like Minecraft: a song, then a long quiet stretch with only the world's own sounds (done: 6–15 min between songs, 1–2 min after loading; `data/songs.json` `gap_s`, `first_gap_s`).
69. After the crash landing it should be a good while (about 10 min) before the first song, and a song must never start over WREN or a story line (done: `landing_gap_s` 9–12 min; a song waits while a line is spoken).
70. Verdance must be fully ready to release and play: simple enough for a child, addictive, with a real story. The pace keeps you moving, but you still have to grind a bit to get there.
71. Set the foundation for more planets made the way Verdance was: different themes, planet sizes and landmarks. Do not build the other planets yet.
72. The story must leave room for the other planets and spill into them: across the planets we gather enough fuel and power to make it back home.
73. Renders of the yard machines and landmarks look great, except the inside of the pod (through the open hatch it shows flat brown/orange streaks). Give the pod a proper interior.
74. Standing rule: everything built from now on (machines, landmarks, props, other planets) keeps the same style and quality as the v6 yard machines and landmarks: chunky, friendly kit shapes, the same paint palette, hazard stripes, picture signs, soft glow. Reference shots: `screenshots/yard/v6_*.png`; models in `systems/camp/machine_art.gd` and `planet/sites/hub_landmarks.gd`.
75. "45 mins for first bot seems too long tbh. should be like 25 mins." (person time; about 12-13 bot minutes, it was 22.6). Done: the Bot Bay costs 450 cubes (was 900) and opens after the first clean hex (was 3), the first Scoopie costs 250 (was 600), and "Clean 2 hexes" and "Clean 3 hexes" now come after the robot (with it helping) instead of before the Bot Bay (`data/workbench.json` `tiers[1]`, `data/robots.json` scoopie `cost`, `data/objectives.json`). Measured (short runs, three seeds): first robot at 15.3, 8.7 and 15.4 bot min (was 22.6). See docs/BALANCE.md.
