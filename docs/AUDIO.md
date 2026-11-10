# Greenfall audio

Everything is synthesized in GDScript at startup or on first use: no audio files ship. API and the
reasons behind it: docs/DECISIONS.md, "Planet audio".

## Files
| File | What |
| --- | --- |
| `autoload/Audio.gd` | SFX synthesis, buses, volumes, ducking, the public music / planet API |
| `audio/music_director.gd` | The sequencer: generative pieces, composed tracks, rotation and gaps |
| `audio/music_tracks.gd` | The composed tracks (data): motifs, progressions, grooves, restored variants |
| `audio/music_synth.gd` | Base instruments (pads, felt piano, kalimba, bell, bass, shaker, kick, air) |
| `audio/planet_synth.gd` | Planet and groove instruments, built lazily per group |
| `audio/planet_themes.gd` | The modes the tracks use. A planet picks its music set (tracks, instruments, ambience bed) with `music_set` in its PlanetDefinition; `MusicTracks.SETS` lists the sets |
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
- Buses: Master (hard limiter -0.5 dB), Music (low-pass by mood, reverb, limiter -1 dB), SFX
  (light reverb), Ambience (-> SFX). Settings sliders set Master / Music / SFX; 0 mutes.
- Music RMS (offline, before the bus): generative explore ~-26 dBFS; tracks -23.5 to -28 dBFS (calm
  Rime the quietest, Anvil's sub-heavy grooves the loudest). Ambience loops are levelled to -20 dBFS
  RMS and sit at -14 dB on the bed, i.e. below the music.
- WREN ducking: music -7 dB, ambience -4.5 dB, 0.25 s attack, 0.9 s release.

## Tools
- `godot --headless --path . -s tools/render_music.gd -- --seconds=45 [--only=anvil] [--reverb] [--out=DIR]`
  renders every mood and track (and restored variants) to WAV with peak / RMS / voice stats.
  `python3 tools/check_music_wav.py DIR/*.wav` reports loudness, high-band energy and clicks.
- `godot --headless --path . -s tools/ambience_levels.gd` builds every ambience loop and one-shot
  and prints build time and levels.
- Dev flags: `--planet-theme=ochre|tidewell|rime|anvil` and `--restoration=0..1` (pins it).
