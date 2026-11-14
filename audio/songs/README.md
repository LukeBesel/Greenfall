# Songs (owner-made with Suno)

Made by the owner on Suno's free plan, Nov 2026. Free-plan songs are licensed for personal, non-commercial use only. Before a commercial (Steam) release, regenerate them on a paid plan, or replace them.

| File | Song | Prompt (docs/music/suno_prompts.json) |
|---|---|---|
| greenfall_main.mp3 | Greenfall (Main Theme) | Story themes |
| fall_of_lm1.mp3 | The Fall of LM-1 | Story themes |
| clean_sweep.mp3 | Clean Sweep | Verdance |
| morning_shift.mp3 | Morning Shift | Verdance |
| sunbaked.mp3 | Sunbaked | Ochre |
| dune_caravan.mp3 | Dune Caravan | Ochre |
| strip_mine_shuffle.mp3 | Strip Mine Shuffle | Ochre |

## Adding songs

No code needed. Put the file (mp3, ogg or wav) in this folder, or in a folder inside it named after a planet (`ochre/`, `rime/`). That alone is enough: a file with no entry in `data/songs.json` plays with the defaults (title from the file name, owned from the start, on its folder's planet, or everywhere from this folder). Add an entry to `data/songs.json` to set the title, artist, planets, moments, weight, volume trim and whether it is a CD to find. Then run `python3 tools/check_songs.py` to see what the game will do with it. Full notes: `docs/ADJUSTING.md`, "Music and sound".

The planned songs below already have entries; drop the MP3 in under the file name shown. Songs whose file is missing are skipped automatically: no CD drops for them and they are not on the CD player. Each intact CD is found on its artist's home planet.

| File | Song | In-game artist (home) | Group | Unlock |
|---|---|---|---|---|
| greenfall_main.mp3 | Greenfall (Main Theme) | The Cradle Farewell Orchestra (Verdance) | story (title) | start |
| fall_of_lm1.mp3 | The Fall of LM-1 | The Cradle Farewell Orchestra (Verdance) | story (cinematic) | CD on Verdance |
| the_ledger.mp3 | The Ledger | Ledger Brand Audio (Anvil) | story (villain) | CD on Anvil |
| sprout_step.mp3 | Sprout Step | The Compactors (Verdance) | verdance (playlist) | CD on Verdance |
| clean_sweep.mp3 | Clean Sweep | The Compactors (Verdance) | verdance (playlist) | start |
| little_helpers.mp3 | Little Helpers | Lil' Rustbucket (Verdance) | verdance (playlist) | CD on Verdance |
| neon_gutters.mp3 | Neon Gutters | DJ Recycle Bin (Verdance) | verdance (playlist) | CD on Verdance |
| morning_shift.mp3 | Morning Shift | The Compactors (Verdance) | verdance (playlist) | start |
| bale_by_bale.mp3 | Bale by Bale | DJ Recycle Bin (Verdance) | verdance (playlist) | CD on Verdance |
| rust_and_ribbons.mp3 | Rust and Ribbons | Professor Pianissimo (Verdance) | verdance (playlist) | CD on Verdance |
| old_town_at_rest.mp3 | Old Town at Rest | Professor Pianissimo (Verdance) | verdance (playlist) | CD on Verdance |
| verdance_night.mp3 | Verdance Night | Professor Pianissimo (Verdance) | verdance (night) | CD on Verdance |
| verdance_in_bloom.mp3 | Verdance in Bloom | The Cradle Farewell Orchestra (Verdance) | verdance (restored) | CD on Verdance |
| sunbaked.mp3 | Sunbaked | Two Suns Tango Orchestra (Ochre) | ochre (playlist) | CD on Ochre |
| strip_mine_shuffle.mp3 | Strip Mine Shuffle | Two Suns Tango Orchestra (Ochre) | ochre (playlist) | CD on Ochre |
| dune_caravan.mp3 | Dune Caravan | Two Suns Tango Orchestra (Ochre) | ochre (playlist) | CD on Ochre |
| glass_dunes.mp3 | Glass Dunes | The Mirage Brothers (Ochre) | ochre (playlist) | CD on Ochre |
| sandglass.mp3 | Sandglass | The Mirage Brothers (Ochre) | ochre (playlist) | CD on Ochre |
| twin_noon.mp3 | Twin Noon | The Mirage Brothers (Ochre) | ochre (playlist) | CD on Ochre |
| mirage_night.mp3 | Mirage Night | The Mirage Brothers (Ochre) | ochre (night) | CD on Ochre |
| oasis_terraces.mp3 | Oasis Terraces | Two Suns Tango Orchestra (Ochre) | ochre (restored) | CD on Ochre |
| tradewinds.mp3 | Tradewinds | The Salty Buoys (Tidewell) | tidewell (playlist) | CD on Tidewell |
| hover_hop.mp3 | Hover Hop | The Salty Buoys (Tidewell) | tidewell (playlist) | CD on Tidewell |
| skipping_stones.mp3 | Skipping Stones | The Salty Buoys (Tidewell) | tidewell (playlist) | CD on Tidewell |
| salt_and_sails.mp3 | Salt and Sails | The Salty Buoys (Tidewell) | tidewell (playlist) | CD on Tidewell |
| low_tide_lofi.mp3 | Low Tide Lofi | Barnacle Bossa Trio (Tidewell) | tidewell (playlist) | CD on Tidewell |
| glass_lagoon.mp3 | Glass Lagoon | Barnacle Bossa Trio (Tidewell) | tidewell (playlist) | CD on Tidewell |
| tidepools.mp3 | Tidepools | Barnacle Bossa Trio (Tidewell) | tidewell (night) | CD on Tidewell |
| kelp_garden.mp3 | Kelp Garden | Barnacle Bossa Trio (Tidewell) | tidewell (restored) | CD on Tidewell |
| snowplow.mp3 | Snowplow | Static & the Streetlights (Rime) | rime (playlist) | CD on Rime |
| hoarfrost.mp3 | Hoarfrost | Static & the Streetlights (Rime) | rime (playlist) | CD on Rime |
| crunch_ice.mp3 | Crunch Ice | Static & the Streetlights (Rime) | rime (playlist) | CD on Rime |
| aurora_drift.mp3 | Aurora Drift | Static & the Streetlights (Rime) | rime (playlist) | CD on Rime |
| ringlight.mp3 | Ringlight | Static & the Streetlights (Rime) | rime (playlist) | CD on Rime |
| frozen_harbor.mp3 | Frozen Harbor | Mittens McKenzie (Rime) | rime (playlist) | CD on Rime |
| long_night.mp3 | Long Night | Mittens McKenzie (Rime) | rime (night) | CD on Rime |
| thaw.mp3 | Thaw | Mittens McKenzie (Rime) | rime (restored) | CD on Rime |
| red_engine.mp3 | Red Engine | Smelter Skelter (Anvil) | anvil (playlist) | CD on Anvil |
| slag_run.mp3 | Slag Run | Smelter Skelter (Anvil) | anvil (playlist) | CD on Anvil |
| foundry_heart.mp3 | Foundry Heart | Smelter Skelter (Anvil) | anvil (playlist) | CD on Anvil |
| ember_market.mp3 | Ember Market | Smelter Skelter (Anvil) | anvil (playlist) | CD on Anvil |
| red_dust_waltz.mp3 | Red Dust Waltz | Smelter Skelter (Anvil) | anvil (playlist) | CD on Anvil |
| magma_crawl.mp3 | Magma Crawl | Smelter Skelter (Anvil) | anvil (playlist) | CD on Anvil |
| ash_choir.mp3 | Ash Choir | Smelter Skelter (Anvil) | anvil (night) | CD on Anvil |
| iron_bloom.mp3 | Iron Bloom | Smelter Skelter (Anvil) | anvil (restored) | CD on Anvil |
