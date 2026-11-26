# Art overhaul check: High quality and motion (NOT the Mac)

**Read this first.** This was meant to be run on the owner's Mac (Metal, Forward+). The cloud
session that got the job could not attach the Mac's Greenfall folder, and the owner asked for it
to be done in the cloud anyway. So nothing here was seen on Metal or on a real GPU.

What this run adds over the art session's own renders:

- **High preset (`--quality=2`)** instead of Low, at 1280x720 instead of 960x540: four shadow
  splits, SSAO and glow switched on. Still the **Compatibility renderer** on Mesa llvmpipe
  (software GL), so glow, SSAO and tone mapping are the Compatibility versions, not Forward+.
- **Motion**: Godot's movie writer at a fixed 30 fps gives exact game time however slow the
  renderer is, so there are three real clips, plus a per-frame log of Lumi's spring values
  (60 fps, headless), which is better evidence than the clips for overshoot and jitter.

## Commits and hardware

| | |
|---|---|
| After | `claude/practical-meitner-eipd0h` at `249b9e9f` |
| Before | `claude/kind-wright-rhxixd` at `72648c60` |
| Machine | Linux cloud container, 4 vCPU Intel Xeon 2.1 GHz, 15 GB RAM, no GPU |
| Renderer | OpenGL 4.5 Compatibility, Mesa 25.2.8 llvmpipe, under Xvfb |
| Engine | Godot 4.7.2.stable.official |
| Rendered speed | about 0.6 fps at High 1280x720 (so no frame-rate numbers are reported) |

## Numbers (headless, High preset, median of three runs)

These are CPU-side numbers from a 4-core cloud box. They compare before and after fairly, but
they are not the Mac's numbers.

| Measure | Before | After | Runs before | Runs after |
|---|---|---|---|---|
| Load: ready in | 16 874 ms | 15 847 ms | 15 105 / 17 952 / 16 874 | 14 762 / 15 847 / 16 748 |
| Load: longest frame | 160 ms | 133 ms | 160 / 197 / 159 | 133 / 128 / 169 |
| Boost walk: frames over 30 ms | 28 | 30 | 32 / 28 / 21 | 18 / 30 / 32 |
| Boost walk: worst frame | 51 ms | 52 ms | 51 / 52 / 44 | 48 / 56 / 52 |
| Frame rate, draw calls on Metal | not measured | not measured | | |

The differences are inside the run-to-run spread: the art branch does not change load time or
hitches. The third "before" hitch run overlapped the start of a render and may be slightly off.
One rendered data point, for what it is worth: 1111 draw calls, 1158 objects, 11.0 M primitives
standing on the start pad at 0.42 (after, High).

## Findings, worst first

Screen positions are for the 1280x720 frames. `board.jpg` shows before and after side by side.

1. **The guide chevron nearly disappears on the pad by day and at dusk.**
   `after/yard_noon.jpg`, `after/yard_dusk.jpg`, `after/yard_morning.jpg`: the chevron on the
   pad left of Lumi (around x 420-480, y 500-530) is a faint pale mauve mark, about the
   brightness of the pad. In `before/` the same chevron is a large, clearly purple arrow. At
   night (`after/yard_night.jpg`) it reads well as pink. The small purple triangle at the left
   screen edge (x 12, y 555) is readable in all four. Calmer is achieved; readable on pale
   ground by day is not.

2. **Lumi's paint chips read as black pixel noise from the play camera.**
   `after/lumi_close.jpg`, `clips/idle_frames.jpg`, `clips/lumi_idle.mp4`: on the back of the
   head the chips are hard black dashes and blotches with a jagged dark outline round the
   head, not worn paint. Close up on the turnaround (`after/lumi_turn_sheet.jpg`) the same
   chips look right. Part of this may be the Compatibility renderer without the Forward+
   anti-aliasing, so check it on the Mac before changing the texture; if it holds there, the
   chips need softer edges or a lighter colour at distance (mip bias or a browner chip tone).

3. **Dusk shadows are strongly blue and the junk field goes almost black.**
   `after/yard_dusk.jpg`: the building shadows across the pad (right half, y 380-560) are
   slate blue against a warm brown pad, more saturated and darker than in
   `before/yard_dusk.jpg`. Behind the Old Town sign the whole junk field (y 195-270) drops to
   near black and loses its colour, where at noon it is the busiest part of the frame. The lit
   pad itself looks good.

4. **Night is bright: closer to a blue day than to night.**
   `after/yard_night.jpg`, `after/lake_night.jpg`: buildings, murals and the litter on the
   ground keep full colour and contrast; the pad is light blue. Nothing is hard to see, which
   may be the intent, but no window or lamp is lit and nothing glows except Lumi, so the scene
   has no night mood of its own. Stars are small clean points, a little square at this
   resolution.

5. **The night lake now works, but there is no moon path.**
   `board.jpg` row "Lake shore, night": before, the water is black; after, it shows waves and
   a deep blue that matches the sky. No moon or moon reflection is in this view, so the moon
   path could not be confirmed. By day (`after/lake_day.jpg`) the water is olive green under a
   blue sky; the horizon buildings sit in the dust band and look right.

6. **Opening film: whites clip in the close shots, and the pad has a white glare streak.**
   `after/film/f_008800.jpg`: the top of Lumi's head and the pod's hull are flat white with no
   paint detail. `after/film/f_011300.jpg`: a broad white specular streak on the pad at centre
   right (x 600-700, y 330-480 of 960x540). Both are also in `before/film/`, slightly
   stronger, so this is old, not caused by the art branch. Lumi's new C-ring eyes read very
   well in the film.

7. **Noon is good.** `after/yard_noon.jpg`: the pad is a readable pale grey, not blown out;
   shade under Lumi and the sign is not too dark. The sky is a clean blue dome with a dust band
   on the horizon and no visible banding (JPEG, 8-bit, software GL: recheck banding on the
   Mac's display). At the play camera's low pitch (`after/lumi_close.jpg`) the top of the sky
   is a very saturated blue, noticeably stronger than in the wide shots.

8. **Lumi matches the brief on the turnaround.** `after/lumi_turn_sheet.jpg` against
   `before/lumi_turn_sheet.jpg`: eyes are a thick glowing C ring with one dot; ear ring modules
   are there; paint is chipped; no pink, white or untextured surface; nothing detached and no
   z-fighting in six views. In the extreme close-up (bottom right) the eye glow smears a
   little past the ring. `art/concept/` is not on the branch, so this is judged against the
   written brief only.

9. **The `--lake-view` shot is spoiled by a scrap pile** (both branches): a corrugated sheet
   and rusty panels fill the middle of the frame and hide Lumi. It is the dev flag's placement,
   not the art, but it makes the lake frames poor evidence. A different back distance or
   `--lake-view-high` would give a cleaner view.

## Motion

Clips: `clips/lumi_walk.mp4`, `clips/lumi_boost.mp4`, `clips/lumi_idle.mp4` (960x540, 30 fps,
camera behind Lumi as in play). Frame sheets: `clips/walk_start_frames.jpg`,
`walk_stop_frames.jpg`, `walk_turn_frames.jpg`, `idle_frames.jpg` (frame number and time on
each tile).

`--orbit-walk` never stops or turns, so the walk and boost clips were driven by a temporary,
uncommitted helper node that switched the dev auto-input on a timeline: rest 0-1 s, walk 1-4,
stop 4-6.5, walk 6.5-8, curve right 8-9.5, curve left 9.5-11, straight 11-12, stop 12-15. No
game file was changed. The spring values below come from the same timeline run headless at
60 fps, reading `_lean`, `_sq`, `_nod`, `_arm_lag`, `_turn` from `player/patch_model.gd`.

| Question | Verdict | Evidence |
|---|---|---|
| Body dips and settles on stopping | **Too small to see** | `_sq` reaches only -0.012 m (1.2 cm) and is gone in 0.3 s. The idle hover bob is ±2.2 cm, so the dip is hidden inside it. Walk clip frames 120-135. |
| Lean with a small overshoot | **Start is a big pitch, not a small overshoot; stop is good** | Setting off: lean goes to -0.243 rad (14°) at 0.28 s, then back to the steady -0.08 (4.6°) by 0.9 s: three times the steady lean. Stopping: rocks back to +0.133 (7.6°), one small undershoot of -0.013, settled in 0.6 s. Walk clip frames 30-56 and 120-145. |
| Banks into turns | **Yes, and reads well** | Roll reaches 0.15-0.16 rad (about 9°), which is the clamp, on both curves. Walk clip frames 244-256 and 290-304. |
| Head leads a turn | **Yes, but mixed with look-at** | The turn term adds up to 0.2-0.33 rad. The head's own look-at yaw moves ±0.45 rad in straight walking and changed direction 4 times in 1.5 s, stepping up to 0.05 rad per frame, so the lead is hard to tell apart from Lumi looking at junk. Worth watching on a real screen for twitchiness. |
| Jitter, popping, vibration | **None found** | In steady walking lean, nod and arm change by under 0.001 rad per frame with no direction flips. No pops in any clip. |
| Arms swing too much | **No** | Arm lag 0.32 rad walking, peak 0.39 on setting off; on stopping it swings back past rest to -0.08 (4.5°) once and settles in about 1.3 s. |
| Boost | **Hits its limits** | Lean sits on the -0.32 rad clamp (18°) for about 0.4 s from 1.8 s, with the head nod at 0.26-0.29 against its 0.3 clamp on top: about 33° nose-down, held flat rather than easing. Arm lag 0.51-0.56. Boost clip frames 54-70. |
| Idle | **Calm** | Hover bob and a head glance to one side every few seconds; nothing else moves. `clips/idle_frames.jpg`. |

Suggested direction, for the art session to decide: the stop dip needs roughly three to four
times the push in `squash()` to show over the bob; the start lean would be closer to "a small
overshoot" with a smaller acceleration gain in `set_motion()` (the `-local_accel.y * 0.015`
term) or more damping; at boost the clamp at 0.32 is what flattens the motion.

One thing in the code, not verified as a visible fault: `squash()` uses `absf(amount)`, so
`squash(-0.3)` on stopping and `squash(0.25)` on starting both push the body down. If stopping
was meant to lift, it does not.

## Not checked

- Anything on Metal, Forward+ or a real GPU: real glow, SSAO and shadow quality at High.
- Frame rate, V-Sync, draw-call cost on the Mac.
- Whether glow blows out Lumi's eyes, ear rings or hover ring in play: the play camera sits
  behind Lumi, so the eyes are only seen in the film and turnaround, where they are fine.
- The guide beam and the four trail chevrons drifting: only one or two chevrons are in these
  views, in stills; their pulse was not watched.
- Building shimmer or flicker from the lake shore: needs a real-time view; not attempted.
- The moon path on the lake (no moon in the lake view).
- Concept art comparison (`art/concept/` is not on the branch).
- Sky banding on a real display.
