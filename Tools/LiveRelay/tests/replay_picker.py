"""Replays a recorded Zikr through the audio picker, as the relay would hear it.

    python tests/replay_picker.py relay tests/recordings/zikr-from-latifa1.wav latifa-1
    python tests/replay_picker.py relay tests/recordings/bayan-1.wav none

Arguments: the relay folder, a 16 kHz mono WAV, and the stage the platform
shows when the recording starts ("none" before any stage). Expect every
stage in order on the Zikr recordings (15 of 15 on zikr-from-latifa1, which
starts after the 1st Latifa) and no stage at all on the bayans."""
import sys, time, wave, numpy as np
sys.path.insert(0, sys.argv[1])
import audio_picker as ap
wf = wave.open(sys.argv[2], "rb")
x = np.frombuffer(wf.readframes(wf.getnframes()), dtype=np.int16)
state = {"stage": (sys.argv[3] if sys.argv[3] != "none" else None) if len(sys.argv) > 3 else "latifa-1"}
def on_stage(stage, why):
    t = picker.clock
    print(f"{int(t//60):02d}:{t%60:04.1f}  -> {stage}   ({why})", flush=True)
    if stage: state["stage"] = stage
picker = ap.Picker(on_stage, lambda: state["stage"], inline=True)
t0 = time.time()
for i in range(0, len(x), 4800):
    picker.feed(x[i:i + 4800])
print("done in", round(time.time() - t0, 1), "s")
