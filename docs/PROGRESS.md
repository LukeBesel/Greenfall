# Progress

## Current state (session 1, continued)
M0 done. M1 slice playable. Large parts of M2-M5 are in, built on the Old Town district slice.

### Systems in the game now
- **World**: Old Town city district (roads, sidewalks, kit buildings, props, skyline), 10 m hexes covered in real-model junk on a dense litter carpet that the scoop sweeps through. PBR ground that cleans to asphalt/concrete/dirt and greens with plant life.
- **Patch**: "Beetle" design (v2): small, cute, light-blue worn paint over rust. Scoop → hopper with Perfect band → hydraulic baling → carry → scale + skip. Tools 1/2/3: Scoop, Plant, Water (leaky can, refills at the hub). Part detector (beeps, red blink, rarity readout, dig). Lens view (V).
- **Hub**: lean-to shack with workbench (upgrades only there), scrap skip on a weigh scale. Hub levels 2-5 from salvaged materials (sheet metal, plastic stock, glass) with fast-build sequences; air scrubbers.
- **Robots**: Scoopie (clean), Haul Bug (deliver bales), Seedling (plant), Drip (water), Multibot (assignable). Built from part recipes at the workbench; fleet upgrades; Mk I-IV tiers (salvage → restored → modern → hover with tractor beams; Mk tiers cost cubes + bolts + a rarer Control Core). Allocation Board with presets and bottleneck hints.
- **Parts**: buried (detector), salvaged from electronics; Haggle's Parts Trade (buy, swap 3-for-1, scrap for bolts, pity offer).
- **Planet**: 40,962-hex geodesic sphere, lakes/inland seas (~25%), biomes, 24 cities incl. Old Capital. Holographic survey globe (M): snapshot with age, paid re-survey. The slice is mapped onto planet cells; restoration % is planet-wide.
- **Growing**: first-seed greenhouse event with cinematic + WREN story; planting slots per clean hex, growth stages with watering/droop, blooms drop seeds; Planted → Growing → Restored per cell; wildlife (butterflies, birds, birdsong) in restored hexes.
- **Story**: restart-checklist tutorial; WREN dialogue (memory stages, glitched early lines, no-repeat pools, voice blips); 8 Memory Shards (documents) revealed by cleaning.
- **Sky**: day/night cycle with bright moonlight and stars; haze lifts with restoration and air scrubbers.
- **Meta**: saves (versioned, compressed), offline progress (50%, 8 h cap, needs a hauler), autosave.
- **Tests**: 48 GUT tests (BigNum, economy, saves, field, geosphere, planet, WREN, hub, offline, garden).

### Measured
- Autoplay: first bale ~7 s, first cash-in ~10 s, first upgrade ~23 s, first hex ~4 min; 4 hexes in ~9.5 min.
- Robot-only run (2 Scoopie, 1 Haul Bug, 1 Seedling, 1 Drip, ~8 game-min): 2 hexes cleaned, 34 planted, 20 bloomed.

### Next steps
1. Integrate the robot-line visual redesign (design workflow running: sleek Mk III/IV, floating rings, tractor beams).
2. M2b: walk on the actual sphere (region streaming, gravity to center, cities in local frames, rocket travel between hubs).
3. M6 water (lakes, clarity, aquatic robots), M7 rockets + research tree, M8 content, M9 balance, M10 polish/exports (Windows, Linux, macOS, Android).
4. Real-GPU performance pass.
