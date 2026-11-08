# Owner feedback checklist

This is every note from the owner's playtests and requests, and who is working on each. A box is checked only after the change has been seen working in a merged build: a render, a headless check, or a test. Merging the helper's branch is not enough. Update it at every merge.

Helper branches: intro2, onboard, world2, ui2, style, fauna2, ship, pace, camp, buddy, eggs2, orbit, hero, sysmap, p_ochre, p_tidewell, p_anvil.

## Start, loading and intro (intro2)
- [x] (intro2 merged; the bar still pauses while the district builds, about 10 s on a dark screen, follow-up) There is no purple "paused" screen at launch. A real loading screen shows a loading bar with the red Lumi picking up garbage in a line. No music plays during loading. (Reported in playtests #1 and #2.)
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
