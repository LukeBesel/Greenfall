# Greenfall Roadmap

Start here in a new session: `docs/PROGRESS.md` (what exists, known issues, next steps), `docs/PLAN.md` (milestones + owner feature requests), `docs/DECISIONS.md` (choices and assumptions), `docs/BUILD_PROMPT.md` (the owner's full brief).

## Status
- [x] M0 Setup
- [x] M1 The Slice (city district, Patch, baling, tutorial, lens view)
- [~] M2 Planet: sphere data + globe done; walking on the sphere (M2b) next
- [~] M3 Robots: 5 robot types, workshop, fleet upgrades, Mk tiers, Haggle trade; visual redesign in progress
- [~] M4 Story: WREN, shards, first-seed cinematic; ruins/acts 2+ pending
- [~] M5 Growing: planting, watering, growth, allocation board, wildlife; ecosystems/compost pending
- [ ] M6 Water, M7 Hubs+Rockets (hub levels done), M8-M11

## Update: Command View + Aurora face pass
- Done: Command View (B / D-pad down). A holo map of the district. Pick a crew or a single robot and paint hexes to set its zone. Modes: Priority, Stay, Follow me, Recall. Orders are saved in `GameState.world.orders` and handled in `Fleet` (`order_for`, `zone_hexes`, `mode_of`); robots honour them in `robot.gd`. Tests are in `tests/test_orders.gd`. Dev hook: `--open=command`, `--order=role:mode:hex+hex|far`.
- Done: Aurora face now has big glossy oval eyes with catchlights, cheeks and ^ ^ when happy. The fin antenna is replaced by a bulb antenna.
- Next, in order:
  1. Automation chain: conveyor/hopper feeder that sends bales to the scale; an auto-baler station; drag-to-assign bots on the map.
  2. Bot build loop: build and upgrade robots straight from the Command panel when at the base, with crew size caps raised by hub level.
  3. Skimmer (water) robot and lake cleaning; Grinder/Recycler to remove trash for good.
  4. Tractor-beam pickup visuals for Mk III+ and Patch.
  5. Research tree, cargo rockets, then content (easter eggs, Codex, Ledger) and polish (cinematic intro, music, exports).

## Update: bale automation + Recycler (wt/stations)
- Done: `automation/stations.gd` (manager, group "stations", state in `GameState.world.stations`, data in `data/stations.json`) with three machines bought in the Hub tab (`ui/stations_panel.gd`, added to `HubPanel`):
  - Conveyor Feeder (`automation/conveyor.gd`): hopper pad with a roller turntable at (7, -0.8), scrolling cleated belt (`art/shaders/belt.gdshader`) into the scale. Haulers drop there when it is closer (`Stations.haul_drop`); Patch drives on to unload.
  - Auto-baler (`automation/auto_baler.gd`, group "baler_station"): air-dropped at the cleaning frontier; cleaners tip full hoppers into it (`Stations.claim_dump`/`dump_step`, marked `[stations]` in robot.gd) and it presses denser bales with a hydraulic platen, then rolls them out for haulers. "Move to frontier" button.
  - Recycler (`automation/recycler.gd`, hub level 2): shredder drums + smelter; bales are destroyed for bolts, building stock and a few cubes; stats `bales_recycled`, `junk_destroyed_kg`; adds to `air_filtered` (sky haze). Fed by an incline belt (auto-route every Nth bale) or the hand-feed plate.
  - Upgrades (tab hub): Belt Drive, Baler Hydraulics, Recycler Yield (bases in patch.json).
- Dev hooks: `--stations=all --stations-demo --route=N --stations-pose=K`. Tests: `tests/test_stations.gd`.
- Next: robot status text for "dumping at baler", Command View marker for the baler, offline progress for stations.
