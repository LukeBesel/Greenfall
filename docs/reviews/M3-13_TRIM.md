# M3-13: side systems trimmed to what Planet 1 uses (Nov 12)

Follows `docs/DECISIONS.md` "Side systems trimmed to what Planet 1 uses (M3-13)" and the to-do in
"Crew and Glim looks found-only (M3-14b)". Base commit `e8c19d9`. Everything parked is in
`parked/` (not loaded); `parked/README.md` lists each system's files, snippets and dependencies.

## What was parked

| System | Parked | What the player loses | What stays |
|---|---|---|---|
| Requests board | `systems/contracts.gd`, `ui/contracts_panel.gd`, the workbench Requests tab, the Mk IV bench tier (1,200 cubes) that opened it, the "request ready" HUD nudge, the planet's `contracts` table | Timed jobs and their reward track | The three goal tiers give directed tasks |
| Trinkets | `systems/collection.gd`, the planet's `trinkets` table, the trinket list on the Codex Collection tab, the `trinkets` exhibit | 55 trinkets and photos, the max-streak medal, the bird-feeding crumb bag | The Collection tab lists Lumi's collection (gnomes, Biscuit, shards, curiosities); photo-mode animal photos still count (`fauna_photos`, achievement `wild_photos`) |
| Garden Mode | `systems/decor.gd`, `systems/garden_director.gd`, `ui/garden_placer.gd`, the pause menu's Garden Mode entry (`ui/late_menu.gd`), the H key, `data/decor.json`, WREN's `garden_place` | Post-finale decorations and their small growth bonus | `DecorProps` (shared art helpers) |
| Robot nursery | `systems/extras/nursery.gd`, the Keepsakes Nursery tab with Retire, the 1,500-cube yard build | Retiring robots, caretakers and their growth bonus | Tier steps cover old robots |
| Lumi Level | `systems/lumi_level.gd`, the planet's `robot_level` table, the XP bar and level-up banner over the hotbar | A second experience bar | **Its rewards, on mastery levels** (below); the Bloom Core ring and Surge gauge stay over the hotbar |
| Ship look purchases | `systems/ship_style.gd`, `data/ship_style.json`, the Locker's Rocket section | Rocket paint, trim and glow choices (free, Mk-unlocked or 120 to 200 Parts) | The rocket's own colours (identical to the old free defaults) |

Achievements hidden (moved to `parked/achievements_parked.json`, unlocks kept in saves, not
counted): `late_decor_1`, `late_decor_25`, `late_decor_all`, `late_charm_25` (Garden Mode),
`extras_retire_1`, `extras_visits_5` (nursery), `builder_mix`, `builder_maker`, `builder_hats`
(robot parts: Planet 1 places none, M3-14b) and `home_answered` (nothing on Planet 1 sets
`cradle_answered`). Goals and Codex entries: none pointed at these systems (M3-10 had removed them).

## Lumi Level: its rewards moved to mastery levels

Lumi Level paid cubes and seeds every level, and the city 1 fit (M3-21) was measured with them:
in the fresh 25-minute bot run before this task it paid **412 cubes and 2 seeds** (levels 2 to 7
at minutes 1.0, 3.0, 6.1, 10.1, 16.4 and 22.3), 8% of the 5,072 cubes earned, 129 of them before
the first robot. So the rewards moved instead of going.

`systems/mastery_rewards.gd` pays each mastery level Lumi gains (any kind, her own hands only, so
robots still earn nothing) what the same-numbered Lumi level paid: step = all mastery levels + 1,
the same formula and the same numbers (`mastery.level_reward` in the pollution table: about 30 s
of income, floor 5 x step, cap max(8 x step^1.5, 0.4% of lifetime cubes), 2 seeds every third
step once the garden is open). The count of steps matches well early: the same run gained litter
mastery 1 to 5 at minutes 3.0, 4.8, 8.0, 11.9 and 19.9 against six Lumi levels; by the launch
point mastery reaches about 25 to 30 levels against an estimated Lumi Level 20 to 25.
The reward shows as a floating line over Lumi with a coin sound; the mastery toast is unchanged.

Fresh bot runs, 25 game minutes, time-scale 4, no dev flags (before: base commit; after: this
task):

| | Before (Lumi Level) | After (mastery rewards) |
|---|---|---|
| Rewards paid | 412 cubes, 2 seeds (6 levels) | 318 cubes, 2 seeds (5 mastery levels: 23, 42, 64, 89, 100 + 2 seeds) |
| First hex / first robot | 87 s / 9.5 min | 93 s / 10.6 min |
| Purchases / longest wait in the first 20 min | 38 / 151 s | 35 / 140 s |
| Cubes earned | 5,072 | 4,609 |
| Script errors | 0 | 0 |

Per step the pay is the same; in 25 minutes mastery reaches one step fewer than Lumi Level did
(the sixth Lumi level, 140 cubes at minute 22, has no counterpart yet). The first-robot difference
is inside the run-to-run spread M3-09 measured (7.6 to 13.8 minutes on one build), so one pair of
runs cannot show a pacing change; the balance pass (M3-12) should look at it with its own runs.

## World events: what was cut

Rule from the lead: every event points at cleaning, pressing or tending; events that pay outside
the hex-value rules (robots earn no cubes; no reward above 3 minutes of income) are cut.

| Event | Verdict | Why |
|---|---|---|
| Supply Drop | **Cut** | Already off since the owner's playtest (no reward crates from the sky); paid 80 s of cubes, Parts, seeds, a robot part and a trinket for nothing Lumi cleaned |
| Robot Hiccup | **Cut** | Points at robots, not at cleaning, pressing or tending; paid 50 s of cubes and Parts for robot upkeep |
| Wildlife Visit | **Cut** | Its reward was a photo for the parked Collection, plus 60 s of cubes and seeds for a photo |
| Salvage Glint | Kept | Pressing: Lumi's own takes from one hex count 3x in her bale; its only extra pay was a trinket roll (removed) |
| Rain Shower | Kept | Tending: waters every plant; 30 s of cubes and 1 to 3 seeds |
| Rare Part Signal | Kept | Digging, Lumi's hand work: 40 s of cubes, 2 to 4 Parts and one rare robot part |
| Ledger Audit | Kept | Cleaning race: 70 s of cubes and 2 to 3 Parts; 20 s of cubes on a loss |

**Rule fix:** an event's cubes were max(min, income x income_s, lifetime x fraction). The lifetime
floor could lift a reward far above 3 minutes of current income when the income rate was low
(Lumi tending, or idle). Event cubes are now capped at `reward.max_income_s` (180 s) of current
income, never below the 20-cube floor (`WorldEvents.capped_cubes`, tested). The cut events' code,
props, checks and data are snippets in `parked/side/events/`.

Not changed, for the lead: the kept events still pay flat cubes that come from no hex. They are
within 3 minutes of income; if the hex-value rule should mean "only hexes pay cubes", Rain
Shower, Rare Part Signal and Ledger Audit would lose their cubes and keep seeds and Parts.

## Saves

Old saves load and keep every parked key untouched: `tests/test_side_systems_saves.gd` loads a
real version 4 globe save (`tests/fixtures/saves/side_systems_v4`, written by
`tools/side_save_fixture.gd`) that used every parked system (a Requests board mid-run on the Mk IV
bench, trinkets, Lumi Level 14, a caretaker, decorations and their charm, bought ship looks, the
cut events in the director's memory, the hidden achievements), checks the data is carried as it
was and ignored (no growth bonus, achievements not counted, the bench reads as tier 3 while its
flag stays 4, the director never picks a cut event), then saves and loads it again. The only
migration step that touched parked data (the v1 to v2 Requests rewrite) moved to a parked snippet.

## Code removed from the build

GDScript outside `parked/` and `tests/` (`git diff --numstat e8c19d9`): **3,373 lines removed,
354 added (net -3,019)**; of the added, 95 are the new fixture writer and 87 `mastery_rewards.gd`.
Game code alone (no `tools/`): 3,306 removed, 259 added. Tests: 552 removed (moved to
`parked/tests/`), 266 added. Planet and global data tables: 321 JSON lines removed.

## Tests and checks

TEST_RESULTS

## Notes and open questions

- New player-facing line without a translation yet: "Snap! A first photo of a %s." (photo mode;
  the old one promised the Collection). The Rebuild-the-base-to-3 card now reuses "Workbench,
  Upgrades tab. More robots can work." `tools/extract_strings.py` was not run (task rule).
- Not verified and not changed: whether the wilderness achievements (`biome_1`, `biome_3`,
  `wild_curio`, `wild_curio_all`) and `curio_all` (29 curiosities; the eggs table has 28 district
  ones, 7 wild, 4 frontier and 2 `new_world`) can be earned on the globe; they may need the same
  hiding.
- Originality: paying a reward on a skill level is a common genre pattern; here it is Lumi's own
  learning of each pollution kind, and nothing new was modelled on another game.
