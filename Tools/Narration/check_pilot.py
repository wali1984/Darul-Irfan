import json, difflib, re, unicodedata, subprocess, numpy as np
from faster_whisper import WhisperModel
T = json.load(open("/mnt/sata1tb/di-tts/pilot_text.json", encoding="utf-8"))
m = WhisperModel("large-v3", device="cuda", compute_type="int8_float16")
def norm(s):
    s = unicodedata.normalize("NFKC", s); s = re.sub(r"[\u064B-\u0652\u0670]", "", s)
    s = s.replace("ي", "ی").replace("ك", "ک").replace("ہ", "ه").replace("ۃ", "ه")
    return re.sub(r"[^\w]+", " ", s).lower().split()
for lang in ("ur", "en"):
    scores = []
    for a in range(1, 31):
        segs, _ = m.transcribe(np.frombuffer(subprocess.run(["ffmpeg","-loglevel","error","-i",f"/mnt/sata1tb/di-tts/pilot/{lang}_067{a:03d}.wav","-f","f32le","-ac","1","-ar","16000","-"],capture_output=True,check=True).stdout,dtype=np.float32), language=lang, beam_size=5)
        heard = " ".join(s.text for s in segs)
        ref = T[lang][f"67:{a}"]
        r = difflib.SequenceMatcher(None, norm(ref), norm(heard)).ratio(); scores.append(r)
        if a in (1, 2): print(lang, a, "TEXT:", ref[:110], "\n      HEARD:", heard[:110])
    print(lang, "word match vs text: median %.2f, worst %.2f (ayah %d)" % (sorted(scores)[15], min(scores), scores.index(min(scores)) + 1))
