#!/usr/bin/env bash
# [art1] The art overhaul's fixed views, for before/after frames. Usage: tools/art_shots.sh OUTDIR [set...]
# Sets: yard (noon, dusk, night and a morning wide from the start pad, one load), lake_night, lake_day.
# Low preset, 960x540, opengl3, no HUD; each run takes the render lock (tools/shot.sh).
set -e
cd "$(dirname "$0")/.."
OUT="${1:?outdir}"; shift || true
SETS="${*:-yard lake_night lake_day}"
mkdir -p "$OUT"
for s in $SETS; do
  case "$s" in
    yard)
      DELAY=${YARD_DELAY:-150} tools/shot.sh art_tmp --orbit --no-intro --no-hud --life-tour="$OUT/yard" --life-tour-start=${YARD_START:-105} \
        --life-tour-stops="0,0,0,0.5,8;0,0,0,0.735,8;0,0,0,0.0,8;0,0,0,0.33,8,9,-0.25" > /dev/null
      for p in 0:yard_noon 1:yard_dusk 2:yard_night 3:yard_morning; do mv "$OUT/yard_${p%%:*}.png" "$OUT/${p##*:}.png"; done ;;
    lake_night) DELAY=110 tools/shot.sh art_tmp --orbit --no-intro --no-hud --lake-view --orbit-time=0.0 > /dev/null; mv screenshots/art_tmp.png "$OUT/lake_night.png" ;;
    lake_day) DELAY=110 tools/shot.sh art_tmp --orbit --no-intro --no-hud --lake-view --orbit-time=0.45 > /dev/null; mv screenshots/art_tmp.png "$OUT/lake_day.png" ;;
    *) echo "unknown set $s"; exit 1 ;;
  esac
  grep -aE "SCRIPT ERROR|SHADER ERROR|ERROR: .*shader" screenshots/art_tmp.log | head -5 || true
done
python3 tools/frame_stats.py "$OUT"/*.png
