# Progress

## Current state (Nov 2026)
The game is playable end to end: title screen → intro cinematic → clean → bale → upgrade → robots → command zones → plant → water robots → sustain → base levels → research → rockets. See `docs/PLAYTEST.md` for how to run it and the controls.

### Systems in the game now
- **Front end**: title screen over a junk-covered ruined city (Continue with save summary, New Game with confirm, Settings, Credits, Quit). Settings: audio (master/music/SFX), graphics (quality preset, render scale, fullscreen, V-Sync), controls (sensitivity, invert Y, hold/toggle scoop, bindings list), gameplay (shake, reduced motion, number format). Pause: Resume, Settings, Codex, Save, Quit to title, Quit.
- **Intro**: landing-pod cinematic (skippable); the pod stays as a landmark.
- **Aurora (P-47CH)**: rebuilt to the owner's concept sheet (thick glowing C eyes, orange accents, ear lenses, hooked fin, claw arms, hover bowl). Tractor-beam pickups. Six unlockable colourways. Scoop → hopper → hydraulic bale → carry → scale. Tools: Scoop, Plant, Water. Part detector. Lens view (V).
- **Survey hologram (M)**: Aurora projects the planet from its raised claw; holo glass panes with % reclaimed, state counts, re-survey, rocket destinations.
- **Command (B)**: overhead view of the real district; pick a crew or one robot; mark hexes; modes Priority / Stay / Follow me / Recall; build and upgrade crews from here at the base; place water refill tanks.
- **Robots**: Scoopie (clean), Haul Bug (haul), Seedling (plant), Drip (water/sustain), Skimmer (lakes), Multibot. Mk I-IV with visual upgrades. Crew caps rise with base level. Idle robots park and show why.
- **Currencies** ([money], Nov 7): exactly three, from `data/currencies.json` / `core/currencies.gd`: Cubes (main money), Parts (robot parts and building stock) and Seeds (planting). Old ids (bolts, sheet metal, plastic, glass, Data, compost, tokens, trinkets, Settler Fragments) are a legacy alias layer; saves migrate at v2.
- **Automation**: conveyor feeder into the scale, auto-baler station that robots dump into, recycler that destroys bales for Parts (and clears the air), compost press turning paper and blooms into seeds.
- **Progression**: hex levels (Clean, Planted, Growing, Sustained, Thriving) with rewards; 50-goal chain in the HUD; base levels 1-5; research tree (30 nodes, costs cubes plus real time, offline); Haggle's parts trade (scrap spares for Parts); rockets between bases.
- **Story**: WREN companion (171 lines, memory stages), memory shards, first-seed cinematic, Ledger antagonist arc (intercepted messages, dump drones, signal jammers, relay rewrite cinematic, seed deliveries), 17 easter eggs.
- **Variety** (wt/events): world events every 4-8 min (Supply Drop, Salvage Surge, Rain Shower, Robot Hiccup, Wildlife Visit, Rare Part Signal, Ledger Audit), cleaning streak with a small bale bonus, Requests board (contracts and world events on one board, paying cubes or parts; its reward track unlocks liveries, Builder parts and capsules), Collection of 28 trinkets/photos in the Codex.
- **Wildlife** (wt/wild): stray cats you can pet (and adopt), pigeons, sparrows and rats in the city; rabbits, deer, foxes, bees, robins and fireflies as hexes turn green; fish, ducks and frogs at clean lakes; frontier animals (lizards, fennecs, seals, gulls, arctic foxes, herons, turtles, Cradle cranes). Codex Animals, animal photos in the Collection.
- **Meta**: Codex (40 entries), 54 achievements, lifetime stats, saves (versioned, compressed, autosave), offline progress, save/load round-trip tool.
- **Audio**: synthesized SFX; layered procedural score (explore, base, night, cinematic, menu moods; intensity follows restoration; stingers).
- **Builds**: export presets; GitHub Actions builds Windows and Linux on every push (macOS needs the ETC2/ASTC import setting).
- **Late game**: four frontier districts (Dust Flats sandstorms, Frozen Port thawing + greenhouses, Sunken City pumps, Cradle Returns landing pad -> ark finale).
- **New in Nov 7 pass**: minimal HUD (hotbar, Lumi Level bar, Bloom Core ring), robot builder (parts, traits), photo mode, futuristic rocket Mk I-IV with cinematics, Lumi story cinematics, world events/streak/contracts/Collection, natural organic hex borders.
- **Platforms**: Steam service (achievements, cloud saves, demo build), Steam Deck/controller pass, auto quality, localization (POT + pseudo/de/es samples), website (website/).
- **Tests**: 283 GUT tests.

### Measured
- Autoplay: first bale ~7 s, first sale ~11 s, first upgrade ~8 s; 2 hexes in ~7 game-min (the bot spreads across hexes; a focused player is faster).
- Robot run (3 Scoopie, 2 Haul Bug): 24 bales made, 24 hauled in 80 s at 4x.

### Known issues / next steps
See `docs/ROADMAP.md` "Next steps".
