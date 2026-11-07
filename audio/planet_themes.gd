extends RefCounted
## [sound] Music identities for the solar-system planets. Read by audio/music_director.gd's
## resolve(): a theme replaces the key, mode, progression, instruments, tempo and texture of the
## "explore", "base" and "night" moods. "cinematic", "menu" and "homecoming" are shared by every
## planet. Each theme has a "ruined" and a "restored" end; Audio.set_restoration(0..1) lerps the
## numbers and switches mode / progression / voice past the midpoint (with hysteresis), always on
## a chord-cycle boundary. See docs/AUDIO.md for the motifs.
##
## Progressions are [root offset from the key, chord intervals], like MusicDirector.MOODS.

const IDS: Array[String] = ["verdance", "ochre", "tidewell", "rime", "anvil"]

const DORIAN: Array[int] = [0, 2, 3, 5, 7, 9, 10]
const PHRYGIAN: Array[int] = [0, 1, 3, 5, 7, 8, 10]
const PHRYG_DOM: Array[int] = [0, 1, 4, 5, 7, 8, 10]
const MIXOLYDIAN: Array[int] = [0, 2, 4, 5, 7, 9, 10]
const LYDIAN: Array[int] = [0, 2, 4, 6, 7, 9, 11]
const AEOLIAN: Array[int] = [0, 2, 3, 5, 7, 8, 10]
const IONIAN: Array[int] = [0, 2, 4, 5, 7, 9, 11]

const THEMES: Dictionary = {
	# Ochre: warm, plucky, desert modal. E Phrygian dominant (the raised 3rd gives the desert
	# colour) over a lute ostinato and a frame drum; restored opens into a sunny E Mixolydian.
	"ochre": {
		"key": 52, "pad": ["pad_reed", "pad_warm"], "bass": "bass", "bell": "bell", "kick": "frame",
		"texture": "pluck", "tex_sample": "pluck", "pad_attack": 2.0,
		"ruined": {
			"mode": PHRYG_DOM, "voice": "pluck",
			"prog": [[0, [0, 4, 7]], [1, [0, 4, 7, 11]], [0, [0, 4, 7, 10]], [5, [0, 3, 7]]],
			"bpm": 84.0, "density": 0.5, "bright": 0.35, "lpf": 4200.0, "tex": 0.9, "bloom": 0.0, "tacet": 0.25,
			"mel_lo": 62, "mel_hi": 76,
			"mix": {"pad": 0.75, "air": 1.1, "bass": 0.9, "melody": 1.0, "bell": 0.3, "shaker": 0.6, "kick": 0.7},
		},
		"restored": {
			"mode": MIXOLYDIAN, "voice": "pluck",
			"prog": [[0, [0, 4, 7, 10]], [10, [0, 4, 7, 14]], [5, [0, 4, 7, 11]], [0, [0, 5, 7, 10]]],
			"bpm": 88.0, "density": 0.7, "bright": 0.6, "lpf": 6500.0, "tex": 1.0, "bloom": 1.0, "tacet": 0.12,
			"mel_lo": 64, "mel_hi": 81,
			"mix": {"pad": 1.0, "air": 0.5, "bass": 1.0, "melody": 1.1, "bell": 0.8, "shaker": 1.0, "kick": 1.0},
		},
	},
	# Tidewell: flowing, arpeggiated, oceanic. F Dorian swells under a rolling harp arpeggio;
	# restored drifts into F Lydian with a piano melody and a fuller pad.
	"tidewell": {
		"key": 53, "pad": ["pad_ocean", "pad_bright"], "bass": "bass", "bell": "bell", "kick": "kick",
		"texture": "arp", "tex_sample": "harp", "pad_attack": 3.5,
		"ruined": {
			"mode": DORIAN, "voice": "harp",
			"prog": [[0, [0, 3, 7, 10, 14]], [5, [0, 4, 7, 9]], [0, [0, 3, 7, 10]], [10, [0, 4, 7, 11]]],
			"bpm": 66.0, "density": 0.45, "bright": 0.4, "lpf": 4200.0, "tex": 0.75, "bloom": 0.0, "tacet": 0.3,
			"mel_lo": 64, "mel_hi": 79,
			"mix": {"pad": 1.0, "air": 1.2, "bass": 0.7, "melody": 0.8, "bell": 0.5, "shaker": 0.0, "kick": 0.0},
		},
		"restored": {
			"mode": LYDIAN, "voice": "piano",
			"prog": [[0, [0, 4, 7, 11, 14]], [2, [0, 4, 7, 14]], [9, [0, 3, 7, 10]], [4, [0, 3, 7, 10]]],
			"bpm": 70.0, "density": 0.6, "bright": 0.7, "lpf": 7000.0, "tex": 1.0, "bloom": 0.9, "tacet": 0.15,
			"mel_lo": 65, "mel_hi": 81,
			"mix": {"pad": 1.15, "air": 0.6, "bass": 1.0, "melody": 1.0, "bell": 0.9, "shaker": 0.5, "kick": 0.3},
		},
	},
	# Rime: crystalline bells, sparse, airy. Open fifths in B Aeolian, glass bells and a thin ice
	# pad with long silences; restored warms into B Lydian.
	"rime": {
		"key": 47, "pad": ["pad_ice", "pad_bright"], "bass": "bass", "bell": "glass", "kick": "kick",
		"texture": "twinkle", "tex_sample": "glass", "pad_attack": 4.0,
		"ruined": {
			"mode": AEOLIAN, "voice": "glass",
			"prog": [[0, [0, 7, 14]], [8, [0, 4, 7, 11]], [3, [0, 7, 14]], [10, [0, 5, 7]]],
			"bpm": 54.0, "density": 0.25, "bright": 0.7, "lpf": 7000.0, "tex": 0.8, "bloom": 0.0, "tacet": 0.45,
			"mel_lo": 66, "mel_hi": 84,
			"mix": {"pad": 1.05, "air": 1.5, "bass": 0.5, "melody": 0.85, "bell": 1.0, "shaker": 0.0, "kick": 0.0},
		},
		"restored": {
			"mode": LYDIAN, "voice": "glass",
			"prog": [[0, [0, 4, 7, 11, 14]], [2, [0, 4, 7, 14]], [7, [0, 4, 7, 11]], [4, [0, 3, 7, 10]]],
			"bpm": 58.0, "density": 0.4, "bright": 0.9, "lpf": 9000.0, "tex": 1.0, "bloom": 0.7, "tacet": 0.25,
			"mel_lo": 66, "mel_hi": 86,
			"mix": {"pad": 1.1, "air": 0.8, "bass": 0.7, "melody": 0.9, "bell": 1.2, "shaker": 0.3, "kick": 0.0},
		},
	},
	# Anvil: a low industrial pulse in C Phrygian with distant anvil clanks; restored turns hopeful:
	# C major, the pulse softens, bells replace the clanks and a warm bloom fills in.
	"anvil": {
		"key": 48, "pad": ["pad_brass", "pad_warm"], "bass": "bass", "bell": "bell", "kick": "kick",
		"texture": "pulse", "tex_sample": "pulse", "pad_attack": 2.5,
		"ruined": {
			"mode": PHRYGIAN, "voice": "piano",
			"prog": [[0, [0, 3, 7]], [1, [0, 4, 7]], [0, [0, 3, 7, 10]], [10, [0, 4, 7]]],
			"bpm": 80.0, "density": 0.35, "bright": 0.2, "lpf": 2600.0, "tex": 1.0, "bloom": 0.0, "tacet": 0.35,
			"mel_lo": 55, "mel_hi": 70,
			"mix": {"pad": 0.75, "air": 0.6, "bass": 1.1, "melody": 0.75, "bell": 0.2, "shaker": 0.0, "kick": 0.8},
		},
		"restored": {
			"mode": IONIAN, "voice": "piano",
			"prog": [[0, [0, 4, 7, 14]], [7, [0, 4, 7]], [9, [0, 3, 7, 10]], [5, [0, 4, 7, 11]]],
			"bpm": 84.0, "density": 0.65, "bright": 0.65, "lpf": 6500.0, "tex": 0.55, "bloom": 1.0, "tacet": 0.12,
			"mel_lo": 64, "mel_hi": 79,
			"mix": {"pad": 1.1, "air": 0.4, "bass": 1.0, "melody": 1.1, "bell": 0.9, "shaker": 0.7, "kick": 0.8},
		},
	},
}


static func has(id: String) -> bool:
	return id == "verdance" or THEMES.has(id)
