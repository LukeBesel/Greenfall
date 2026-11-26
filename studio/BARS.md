# Bars (what counts as real)

- Light: one warm hero (the primary sun), shadows filled by coloured bounce and sky, never a flat
  grey ambient. Dusk is low, orange and long-shadowed. Night is moonlit blue with readable ground.
- Air: far layers get lighter, lower in contrast and take the horizon colour; the horizon is the
  brightest band of the sky at every hour, night included. Mist glows, it does not darken.
- Tone: clipped highlights and crushed blacks each under 0.5% of a frame (measured, tools/frame_stats.py),
  unless a light source.
- Water at night: the lake shows the sky and a moon path; the shore line reads.
- Hardware: thickness, seams, joints that could move; painted metal vs glass vs rubber read apart;
  wear at edges, dirt from the ground up.
- Motion: weight (anticipation, settle), no sliding, no popping.

## World target (owner, 26 Nov): art/concept/world_target.jpg
The owner's picture of how the game should look. What makes it work, in order of effect:
1. Light: a low sun behind the scene, warm key against cool shade, long shadows, lit cloud edges, shafts of light in hazy air.
2. Wet dark ground: asphalt and stone with puddles that mirror the sky, cracks, painted marks, weeds and leaves. Not pale dry dirt.
3. Junk you can recognise: monitors, computer cases, boxes, crates, bottles, cans, cables, in clusters with gaps between them. Not a confetti of small coloured squares.
4. Places with history: brick and stone with depth, ivy, awnings, bunting, trees, pilings and railings in the water, a hazy far shore.
5. Lumi small and clean-reading in the middle, with his glow on the wet ground.
6. Grade: rich contrast, warm highlights, cool shadows, a soft glow on lights, nothing clipped.
Measured (tools/frame_stats.py): mean 89, p5 29, p95 170, saturation 0.31, ground band 70.
