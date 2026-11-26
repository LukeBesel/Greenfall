# Greenfall audio

Greenfall synthesizes its effects, ambience and procedural score in GDScript. The seven recorded
songs under [audio/songs](../audio/songs/README.md) run through the title, opening film and CD
player. See [DECISIONS.md](DECISIONS.md) for how the planet audio was designed.

## Where sounds play

| Moment | What plays | Source |
| --- | --- | --- |
| Scoop | A short intake sweep when a piece lifts, a soft beam hum while the beam is busy, and a material or combo clink as junk reaches the chest. Heavy pieces get a hydraulic accent. | [PickupFx](../player/pickup_fx.gd), [Patch](../player/patch.gd) |
| Loose bin dump | Scrap spills against a hollow bin wall. A separate payout tone plays when cubes are credited. | [Pace](../core/pace.gd) |
| Baler | Hydraulics and a motor groan begin the chest press. A short bite and chassis knock mark compression. The hatch clunks on ejection. The Auto Baler has its own intake, press, vent and output timing and uses the same synthesized press bite. | [Patch](../player/patch.gd), [FeelFx](../art/feel_fx.gd), [Auto Baler](../automation/auto_baler.gd) |
| Bale scale | A suction sweep at intake, a clunk at the chute and a rising readout when the bale pays. Consecutive sales raise the pitch. | [Depot](../automation/depot.gd) |
| Robot built | A mechanical latch and two short startup notes play once on the build event, including while a song is on. Normal purchases and upgrades still use their own feedback. | [MusicHooks](../audio/music_hooks.gd), [BenchBots](../ui/bench_bots.gd) |
| Launch and landing | The globe's intra- and interplanetary flights use a takeoff whoosh and a touchdown thud. The separate Rocket sequence has countdown beeps, a siren, charge, repeated engine roars, and landing gear, impact and steam cues. The opening film uses some of those sources for pod and ark effects. | [HubHop](../planet/sites/hub_hop.gd), [Rocket](../automation/rocket.gd), [film shot table](../data/intro_shots.json) |
| Interface | Button clicks on the Interface bus, focus blips on title/profile/world navigation, and short confirm, refusal and purchase cues. | [Main menu](../ui/main_menu.gd), [Pause menu](../ui/pause_menu.gd), [Settings](../ui/settings_panel.gd), [ListDetail](../ui/list_detail.gd) |
| Other effects | Lumi's treads and gestures, animal calls, robot work, detector and dig cues, puzzle and Easter egg sounds, discoveries, restoration and upgrade rewards. | [Audio](../autoload/Audio.gd), [Fauna](../fauna/fauna_sounds.gd), [StorySfx](../story/story_sfx.gd), [MusicHooks](../audio/music_hooks.gd) |
| Planet ambience | Verdance tracks dirt and greenery around Lumi. Ochre has warm wind and grit, Tidewell has waves and buoy bells, Rime has wind and ice, and Anvil has dust and foundry sounds. Restoration changes the mix. Birds in the planet beds share the wildlife clock. | [Life ambience](../audio/life_ambience.gd), [planet beds](../audio/ambience.gd), [sound data](../data/sound.json) |

## Recorded music and direction

- **Title and opening film.** Greenfall (Main Theme) opens the title playlist with warm piano and a
  slow string swell. The Fall of LM-1 scores the opening and rewatch, moving from storm percussion
  to sparse piano and fading at the landing. The title may shuffle the other recordings too.
- **World and radio.** Clean Sweep and Morning Shift are Verdance tracks. Sunbaked, Dune Caravan
  and Strip Mine Shuffle are Ochre tracks available in the current shuffle. Finding the first
  Sunbaked CD starts the world playlist. The background leaves space between songs. The radio can
  shuffle, repeat one song or stop. Selecting the song already playing preserves its position.
  A repeat fades at the seam without playing two copies together.
- **Music direction.** The [existing Suno prompts](music/suno_prompts.json) specify plucky, bright
  rhythms for Verdance, warm hand percussion and winding melodies for Ochre, breezy flow for
  Tidewell, glassy space for Rime, and dark grooves that grow warmer for Anvil. The procedural
  themes below cover those worlds while most recordings are still pending. Small Robot, Big Sky
  is the direction for a future launch recording with driving rhythm, rising strings and a
  bright lead. The launch currently has no recorded moment track.

## Handoff

- For dedicated ship sounds on the globe, replace the existing cues in the travel owner's
  [HubHop](../planet/sites/hub_hop.gd). Use the same short thrust rise for `hop_with` and
  `depart_with`, then one gear impact for `hop_with` and `_step_off`. Check a complete
  approach and one skipped with E so each arrival has one impact.
- Title, profile and world navigation play the shared `blip` on focus. Set Interface to zero,
  leave Sound effects up and move controller focus to hear it. The UI owner can switch those
  call sites to a dedicated Interface-bus focus cue. The existing click already follows that
  slider. [Title](../ui/main_menu.gd), [profiles](../ui/profile_picker.gd), [worlds](../ui/world_picker.gd)

## Files
| File | What |
| --- | --- |
| `autoload/Audio.gd` | SFX synthesis, buses, volumes, ducking, the public music / planet API |
| `audio/music_director.gd` | The sequencer: generative pieces, composed tracks, rotation and gaps |
| `audio/music_tracks.gd` | The composed tracks (data): motifs, progressions, grooves, restored variants |
| `audio/music_synth.gd` | Base instruments (pads, felt piano, kalimba, bell, bass, shaker, kick, air) |
| `audio/planet_synth.gd` | Planet and groove instruments, built lazily per group |
| `audio/planet_themes.gd` | Planet ids and the modes the tracks use |
| `audio/ambience.gd`, `audio/ambience_synth.gd` | Planet ambience beds (loops + random events) |
| `audio/music_hooks.gd` | Drives mood, intensity, restoration and activity from the game |

## How the score plays
- **Pieces rotate.** In explore / base / night the director plays one piece, then a silence gap
  (8-45 s while exploring, shorter when busy; 25-55 s at night), then the next piece from the
  planet's pool (never the same twice in a row). Story moods (cinematic, menu, homecoming) and the
  radio never gap.
- **Energy follows play.** Cleaning hexes, building robots and buying upgrades raise `activity`;
  while it is up the director picks the planet's active tracks and their drums play fuller. Night and
  the base pick calm tracks (Verdance: its generative night / base pieces), with drums cut back.
- **A track** is 8 chords of 2 bars (16 eighth notes each), played 2-4 times. Its form gives one
  letter per 2-chord phrase: A (the motif), H (the motif a third higher), C (a second motif),
  B (a generative answer), E (half the motif and a cadence). The motif is written in scale degrees
  and re-fitted to each chord (strong beats snap to chord tones), so the hook survives a new chord or
  a new mode. From the second pass the hook is doubled by a second instrument. The first two chords
  of a piece have no drums (an intro); busy moments get a hand-drum fill every 4 chords.
- **Restored variants.** Past 0.55 restoration a track switches to its restored mode, progression and
  instruments (with hysteresis), on a chord-cycle boundary; brightness and the warm low "bloom" pad
  glide with restoration. The motif stays the same, so on Anvil the same tunes turn from Phrygian to
  major.
- **Build tracks** (Rime, the ending) add layers every 4 chords: bells, bass, bloom, then soft drums.

## Planet themes and motifs
Motifs below are scale degrees (1 = tonic) in eighth notes; "-" is a rest of one eighth.

### Verdance (start): the existing score, plus two cleaning tracks
- Generative explore / night / base / cinematic / menu pieces in D major (unchanged).
- **Sprout Step** (active, D major, 104 bpm, light swing): kalimba hook doubled by bells, rim
  backbeat, eighth hats, congas, bouncing bass. Hook: `5 - 5 6 5 - 3 - - - 1 - 2 - 3 -` over I - vi.
- **Clean Sweep** (active, G major, 112 bpm): marimba hook answered by felt piano, harp arpeggio,
  four-on-the-floor with syncopated congas. Hook: `1 3 5 - 5 4 3 - 2 - 3 - 1` then a leap up the
  octave `4 6 8 - 8 7 6 - 5`.

### Ochre (desert strip mine): warm, plucky, sunny
Reed pad, lute pluck, marimba, frame drum, clap, shaker, congas. Ambience: warm wind with sand grit,
a faint heat buzz; sand gusts. Restored: cicadas, songbirds and chirps.
- **Sunbaked** (active, E Mixolydian, 100 bpm, swing): marimba hook over a lute ostinato and
  hand-drum groove; I - bVII - IV - I. Hook: `8 7 8 5 - 3 5 1 - - 3 5 - 6` (a sunny fall and climb).
- **Dune Caravan** (active, E Phrygian dominant -> E Mixolydian restored, 92 bpm): a winding pluck
  line over a loping frame drum; I - bII - I - iv. Hook: `1 2 3 - 2 1 7, 1` (a turn around the tonic).
- **Mirage** (calm, E Mixolydian, 76 bpm): kalimba and bells over the reed pad, a lone hand drum.
  Hook: `5 - - 6 5 - 3 - 5 - - - 1`.

### Tidewell (ocean world): bouncy, flowing, breezy
Ocean pad, steel pan, harp, marimba, rim, shaker, a light shuffle. Ambience: waves, sea wind, gulls,
buoy bells; `hover_spray` loop for Lumi over water. Restored: songbirds, frogs, crickets, a brook.
- **Tradewinds** (active, F major, 108 bpm, shuffle): steel-pan hook and steel-pan arpeggios;
  I - V - vi - IV. Hook: `3 5 8 - 7 5 6 - 5 - 3 - 5` (a leap to the octave and a skipping descent).
- **Tidepools** (calm, F Lydian, 80 bpm): harp melody over rolling harp arpeggios, brushed shaker.
  Hook: `5 - 4 - 5 - 8 - 7 - - - 5` (the Lydian #4 shimmering under the fifth).
- **Skipping Stones** (active, F Mixolydian, 116 bpm, shuffle): marimba hook, steel-pan off-beat
  arpeggio, four-on-the-floor; the second phrase repeats the hook a third higher.
  Hook: `1 - 3 5 5 - 3 5 6 - 5 - 3`.

### Rime (ice moon): crystalline, sparse, airy, slow warm builds
Ice pad, glass bells and twinkles, piano. Ambience: eerie whistling wind, creaking ice, geyser hiss.
Restored: meltwater, songbirds and chirps.
- **Hoarfrost** (calm build, B Aeolian -> B Lydian restored, 64 bpm): a glass-bell melody that gains
  bass, a bloom pad and a heartbeat kick over three passes. Hook: `1 - 3 - 5 - - - 4 - 3 - 5` and an
  answer from the octave `8 - - - 7 - 5 - 4 - - - 3`.
- **Aurora** (active build, B Aeolian -> B major restored, 76 bpm): piano melody doubled by glass,
  soft rim backbeat arriving on the second pass. Hook: `5 4 3 1 - 3 - 5 - - - 8`.

### Anvil (red foundry world): Nether-like, dark and groovy, turning hopeful
Brass pad with an eerie "ah" choir, detuned synth lead, deep sub bass, reverb-drenched metal hits
pitched to the chord root, heartbeat kick. Ambience: dust wind, distant metal groans and clunks, dust
devils. Restored: a brook, crickets, songbirds. Restored tracks keep their motifs but move to C major,
trade the synth for piano / marimba, the sub for a round bass, the metal hits for bells, and bloom.
- **Foundry Heart** (active, C Phrygian, 90 bpm): lub-dub heartbeat kick, pulsing sub, metal hits on
  the off-beats. Hook: `1 - - b2 1 - b6, - 1 - - - 4 - b3` (a slow menacing turn around the tonic).
- **Ash Choir** (calm, C Phrygian, 70 bpm): choir pad, a sparse synth line, a single distant hit.
  Hook: `5 - - - 4 - b2 - 1`, falling to `b6,` then climbing back.
- **Red Engine** (active, C Phrygian, 104 bpm): driving eighth-note pulse bass, clap backbeat, metal
  hits. Hook: `1 - 1 4 b3 - b2 - 1 - b7, 1 b2` (a stamping riff).

### Homecoming (the ending)
The **Greenfall motif**, D major: `5 - 8 - - - 7 - 6 - 5 - - - 3`, answered by `3 - 5 - 6 - - - 8 - - - 7`,
then the same shape an octave up. It is first heard as the sting that opens the intro
(`music_sting("motif")`). The ending (`set_music_mood("homecoming")`) plays the whole tune over
I add9 - vi7 - IVmaj7 - V7 and builds every 4 chords: piano and pads; then bass, bloom and bell
doubling; then a choir pad, a soft heartbeat kick and shaker; finally the melody an octave up.

## Mix
- Settings offers Master, Music, Sound effects, Wind and animals, Interface and Reward sounds.
  Zero mutes the matching bus. Music controls both the procedural Music bus and recorded Songs
  bus. The jukebox fades both music buses. Master has a small-speaker high-pass and a -0.5 dB
  limiter. Music has a mood-driven low-pass, reverb and a -1 dB limiter. SFX uses light reverb.
- Music RMS (offline, before the bus): generative explore ~-26 dBFS; tracks -23.5 to -28 dBFS (calm
  Rime the quietest, Anvil's sub-heavy grooves the loudest). Ambience loops are levelled to -20 dBFS
  RMS. Each bed applies its own level and restoration weights before the Wind and animals slider.
- WREN ducking: music -7 dB, ambience -4.5 dB, 0.25 s attack, 0.9 s release.

## Tools
- `godot --headless --path . -s tools/render_music.gd -- --seconds=45 [--only=anvil] [--reverb] [--out=DIR]`
  renders every mood and track (and restored variants) to WAV with peak / RMS / voice stats.
  `python3 tools/check_music_wav.py DIR/*.wav` reports loudness, high-band energy and clicks.
- `godot --headless --path . -s tools/ambience_levels.gd` builds every ambience loop and one-shot
  and prints build time and levels.
- Dev flags: `--planet-theme=ochre|tidewell|rime|anvil` and `--restoration=0..1` (pins it).
