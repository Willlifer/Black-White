"""D394: analyse the placeholder capture (godot --path game -- --placeholders --audio-capture <dir>).

    python game/tools/audio/analyse_placeholders.py <dir>

For the short pick reveal and every ph_* sound: where it really starts in
the recording (cross-correlation with its file, against the sync clicks),
the match score, its momentary max (400 ms) against the music just before
it, and the peak. Writes capture_ph_report.json next to the capture.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bwdsp as d  # noqa: E402
import analyse_capture as ac  # noqa: E402


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ac.GAME.parent / "design" / "audio"
    j = json.loads((out / "capture_ph.json").read_text())
    sr, x = d.load(out / "capture_ph.wav")
    ac.SR = sr
    mono = x.mean(axis=1)
    t0 = j["record_start_usec"]

    def rel(usec):
        return (usec - t0) / 1e6

    sync = [e for e in j["sfx"] if e.get("tag") == "sync"]
    click = ac.load_sfx(sync[0]["file"]) if sync else None
    lags = [lag for e in sync for lag, sc in [ac.locate(mono, click, rel(e["usec"]), lo=-0.02, hi=0.2)] if lag is not None and sc > 0.6]
    base = float(np.median(lags)) if lags else 0.0
    rows = []
    for e in j["sfx"]:
        if not (e["name"].startswith("ph_") or e["name"] == "sting_pick_short"):
            continue
        t_req = rel(e["usec"])
        ref = ac.load_sfx(e["file"])
        w = int(0.25 * sr)
        cs = np.concatenate([[0.0], np.cumsum(ref ** 2)])
        o = int(np.argmax(cs[w:] - cs[:-w])) if len(ref) > w else 0
        lag, score = ac.locate(mono, ref[o:], t_req + base + o / sr, lo=-0.03, hi=0.15, hp=150.0)
        start = t_req + base + (lag or 0.0)
        dur = min(len(ref) / sr, 3.0)
        pre = x[int(max(0, start - 1.2) * sr): int(max(0, start - 0.05) * sr)]
        on = x[int(start * sr): int((start + dur) * sr)]
        rows.append({"name": e["name"], "asked_s": round(t_req, 3), "found": bool(score > 0.3), "match": round(score, 2),
                     "start_vs_asked_ms": round((lag or 0.0) * 1000, 1),
                     "music_before_momentary": round(ac.momentary_max(pre), 1) if len(pre) > sr // 2 else None,
                     "with_sound_momentary": round(ac.momentary_max(on), 1), "peak_dbfs": round(d.peak_db(on), 1)})
    rep = {"sample_rate": sr, "seconds": round(len(x) / sr, 2), "output_path_latency_ms": round(base * 1000, 1),
           "clipped": int((np.abs(x) >= 0.999).sum()), "peak_dbfs": round(d.peak_db(x), 1), "sounds": rows}
    (out / "capture_ph_report.json").write_text(json.dumps(rep, indent=1))
    print(json.dumps(rep, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
