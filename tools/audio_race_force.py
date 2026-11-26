# [v10quit] gdb script: forces the audio mixer race (see audio/mix_barrier.gd). It holds the mixer
# thread right after it has loaded a playback's bus-details pointer, before it copies the details,
# while the rest of the game runs on (non-stop mode); MALLOC_PERTURB_ poisons freed memory, so a
# read of freed details always crashes instead of only sometimes. The address is for the official
# Godot 4.7.2-stable linux x86_64 binary.
#   gdb -q -batch -x tools/audio_race_force.py --args /opt/godot/Godot_v4.7.2-stable_linux.x86_64 \
#       --headless --path . res://tools/audio_race_stress.tscn -- --seconds=12 [--no-mix-barrier]
#   (or the game: ... --path . -- --fresh --orbit --no-intro --quit-after=20 [--no-mix-barrier])
# With --no-mix-barrier: SIGSEGV at 0x48f7c18 on the first hold (the field crash). Without it: no crash.
# FORCE_EVERY (hold every Nth bus-details read, 50), FORCE_MAX (holds, 40), FORCE_HOLD (s, 0.2).
import gdb, time, os
EVERY = int(os.environ.get("FORCE_EVERY", "50"))
MAXH = int(os.environ.get("FORCE_MAX", "40"))
HOLD = float(os.environ.get("FORCE_HOLD", "0.2"))
class Hold(gdb.Breakpoint):
    hits = 0
    holds = 0
    def stop(self):
        Hold.hits += 1
        if Hold.hits % EVERY == 1 and Hold.holds < MAXH:
            Hold.holds += 1
            print("[force] mixer held %.0f ms at the bus-details copy (hold %d)" % (HOLD * 1000, Hold.holds), flush=True)
            time.sleep(HOLD)
        return False
gdb.execute("set pagination off")
gdb.execute("set non-stop on")
gdb.execute("set confirm off")
gdb.execute("handle SIGUSR1 SIGUSR2 SIGPIPE SIG32 SIG33 SIG34 SIG35 nostop noprint pass")
gdb.execute("set environment MALLOC_PERTURB_=85")
Hold("*0x3b19859")  # Godot 4.7.2-stable linux x86_64: AudioServer::_mix_step, bus_details pointer loaded, before `bus_details = *ptr`
gdb.execute("run")
