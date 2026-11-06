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

## Update: Front end (title screen + settings)
- Done: `scenes/main_menu.tscn` (`ui/main_menu.gd`) is now `run/main_scene`: Aurora hovering in a sunset junk lot with a slow swinging camera, Continue (with a one-line save summary), New Game (confirms before erasing), Settings, Credits (from `docs/CREDITS.md`), Quit. Any DevHooks flag skips straight to `slice.tscn`, so `tools/shot.sh`, autoplay and tests work as before; `--menu` (or `--menu=settings|credits|confirm`, `--tab=N`) stays on the title for screenshots. The title screen turns `SaveManager.enabled` off so autosave can't overwrite the slot with blank state.
- Done: `ui/settings_panel.gd` (`SettingsPanel`), shared by the title and pause menus: Audio, Graphics (quality preset, render scale, fullscreen, V-Sync), Controls (sensitivity, invert Y, hold/toggle scoop, read-only binding list), Gameplay. New settings in `Settings.gd`: `fullscreen`, `vsync`, `render_scale`, `apply_display()`, `apply_quality_to_tree()`. Pause menu: Resume / Settings / Save / Quit to title / Quit to desktop.

## Update: Command View + Aurora face pass
- Done: Command View (B / D-pad down). A holo map of the district. Pick a crew or a single robot and paint hexes to set its zone. Modes: Priority, Stay, Follow me, Recall. Orders are saved in `GameState.world.orders` and handled in `Fleet` (`order_for`, `zone_hexes`, `mode_of`); robots honour them in `robot.gd`. Tests are in `tests/test_orders.gd`. Dev hook: `--open=command`, `--order=role:mode:hex+hex|far`.
- Done: Aurora face now has big glossy oval eyes with catchlights, cheeks and ^ ^ when happy. The fin antenna is replaced by a bulb antenna.
- Next, in order:
  1. Automation chain: conveyor/hopper feeder that sends bales to the scale; an auto-baler station; drag-to-assign bots on the map.
  2. Bot build loop: build and upgrade robots straight from the Command panel when at the base, with crew size caps raised by hub level.
  3. Skimmer (water) robot and lake cleaning; Grinder/Recycler to remove trash for good.
  4. Tractor-beam pickup visuals for Mk III+ and Patch.
  5. Research tree, cargo rockets, then content (easter eggs, Codex, Ledger) and polish (cinematic intro, music, exports).
