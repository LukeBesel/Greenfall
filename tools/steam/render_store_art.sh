#!/usr/bin/env bash
# Renders all Steam store art in-game, one render at a time, then composites the capsules.
#   tools/steam/render_store_art.sh [OUT_DIR] [all|masters|shots|compose]
# OUT_DIR defaults to screenshots/steam (PNGs there are not committed). Each shot's devhook flags
# are the ones listed in docs/steam/TRAILER.md. Software Vulkan (lavapipe) is slow: a 2560x1440
# High-quality frame takes about a minute, so the masters wait several minutes before the shot.
# Render gating: waits until no other Vulkan Godot runs and >= 6 GB RAM is free (shared machines).
set -u
cd "$(dirname "$0")/../.."
OUT="$(realpath -m "${1:-screenshots/steam}")"
WHAT="${2:-all}"
mkdir -p "$OUT"

gate() {
  while pgrep -f '^godot .*rendering-driver vulkan' >/dev/null || [ "$(free -g | awk '/Mem:/{print $7}')" -lt 6 ]; do
    sleep 2
  done
}

# render NAME RES SCENE DELAY [devhook args...]   (Quality preset 2 = High)
render() {
  local name=$1 res=$2 scene=$3 delay=$4; shift 4
  local n=1 ev=1 want="$OUT/$name.png"
  for a in "$@"; do case $a in --shots=*) n=${a#--shots=};; --shot-every=*) ev=${a#--shot-every=};; esac; done
  [ "$n" -gt 1 ] && want="$OUT/${name}_$((n - 1)).png"
  local qa=$((delay + ev * (n - 1) + 8))
  gate
  rm -f "$want"
  # shellcheck disable=SC2086
  timeout 1500 xvfb-run -a -s "-screen 0 3840x2160x24" stdbuf -oL \
    godot --path . --rendering-driver vulkan --resolution "$res" $scene -- --fresh --quality=2 --perf \
    --shot="$OUT/$name.png" --shot-delay="$delay" --quit-after="$qa" "$@" > "$OUT/$name.log" 2>&1 &
  local pid=$!
  for _ in $(seq 1 400); do [ -f "$want" ] && break; kill -0 $pid 2>/dev/null || break; sleep 5; done
  sleep 3; pkill -f "shot=$OUT/$name.png"; kill $pid 2>/dev/null; sleep 2
  echo "render $name: $([ -f "$want" ] && echo ok || echo MISSING)"
}

if [ "$WHAT" = all ] || [ "$WHAT" = masters ]; then
  render master_wide 2560x1440 res://tools/steam/capsule_stage.tscn 420 --frame=wide
  render master_hero 3840x1240 res://tools/steam/capsule_stage.tscn 480 --frame=hero
fi

if [ "$WHAT" = all ] || [ "$WHAT" = shots ]; then
  render store_01_lasers 1920x1080 "" 150 --no-hud --demo-scoop --demo-yaw=2.0 --demo-dist=2.6 --time-scale=0.4 --time=0.42 --upgrade-levels=multi_lock:3+laser_reach:3 --shots=3 --shot-every=4
  render store_02_baling 1920x1080 "" 150 --no-hud --stations=all --stations-demo --stations-pose=0.6 --cam=wide --time=0.45
  render store_03_crew 1920x1080 "" 150 --no-hud --robots=scoopie:3@3,haulbug:2@2,drip:2@1,seedling:1@1 --unlock-seeds --clean-hexes=3 --stations=all --time=0.45
  render store_04_command 1920x1080 "" 150 --robots=scoopie:3@1,haulbug:2,drip:1 --order=clean:priority:far --open=command --time=0.45
  render store_05_planting 1920x1080 "" 150 --no-hud --future=3 --spawn-pos=16,22 --spawn-yaw=-1.5708 --cam=side --cam-pitch=-0.08 --time=0.45 --robots=seedling:2@2,drip:1@2
  render store_06_future_city 1920x1080 "" 150 --no-hud --future=5 --spawn-pos=16,22 --spawn-yaw=-1.5708 --cam=side --cam-pitch=-0.08 --time=0.45
  render store_07_future_dusk 1920x1080 "" 150 --no-hud --future=5 --spawn-pos=16,22 --spawn-yaw=-1.5708 --cam=side --cam-pitch=-0.08 --time=0.76
  render store_08_hologram_map 1920x1080 "" 150 --open=globe --time=0.4
  render store_09_rocket 1920x1080 "" 120 --no-hud --rocket --auto-launch=1 --time-scale=3 --time=0.42 --shots=4 --shot-every=20
fi

if [ "$WHAT" = all ] || [ "$WHAT" = compose ]; then
  gate
  timeout 900 xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver vulkan \
    res://tools/steam/capsules.tscn -- --in="$OUT" --out="$OUT" --icons > "$OUT/capsules.log" 2>&1
  grep -aE "\[capsules\]|SCRIPT ERROR" "$OUT/capsules.log" | tail -12
fi
