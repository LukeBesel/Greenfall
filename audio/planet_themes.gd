extends RefCounted
## [sound] The modes the composed tracks use. A planet picks its music with
## PlanetDefinition.music_set: the set's rotating track pool lives in audio/music_tracks.gd (key,
## mode, motif, groove, restored variant); its instruments in audio/planet_synth.gd; its ambience
## bed in audio/ambience.gd. See docs/AUDIO.md.

const DORIAN: Array[int] = [0, 2, 3, 5, 7, 9, 10]
const PHRYGIAN: Array[int] = [0, 1, 3, 5, 7, 8, 10]
const PHRYG_DOM: Array[int] = [0, 1, 4, 5, 7, 8, 10]
const MIXOLYDIAN: Array[int] = [0, 2, 4, 5, 7, 9, 10]
const LYDIAN: Array[int] = [0, 2, 4, 6, 7, 9, 11]
const AEOLIAN: Array[int] = [0, 2, 3, 5, 7, 8, 10]
const IONIAN: Array[int] = [0, 2, 4, 5, 7, 9, 11]
