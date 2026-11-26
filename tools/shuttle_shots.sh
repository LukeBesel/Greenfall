#!/usr/bin/env bash
# [art5] Frames of the shuttle on its pad and across its hops, from the play camera (tools/shuttle_shots.gd).
# Usage: tools/shuttle_shots.sh OUTDIR [extra devhook args...]   (takes the shared render lock)
set -e
cd "$(dirname "$0")/.."
OUT="${1:?outdir}"; shift || true
mkdir -p "$OUT"
stdbuf -oL flock -o /tmp/gf-render.lock timeout "${TIMEOUT:-1500}" xvfb-run -a -s "-screen 0 1280x720x24" stdbuf -oL \
  godot --path . --rendering-driver opengl3 --resolution 960x540 --fixed-fps 10 -- --fresh --orbit --no-intro --no-hud --quality="${QUALITY:-0}" --perf \
  --rocket --shuttle-shots="$OUT/s" --hop-marks="${MARKS:-0.02,0.08,0.16,0.3,0.5,0.8}" --quit-after=99999 "$@" > "$OUT/run.log" 2>&1 || true
grep -aE "shuttle-shots|perf\]|SCRIPT ERROR|hop\]" "$OUT/run.log" | tail -12 || true
