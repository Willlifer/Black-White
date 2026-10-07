"""Analyse the drop-2 capture (godot --path game -- --drop2 --audio-capture).

    python game/tools/audio/analyse_drop2.py [design/audio]

Reads capture_drop2.wav / .json and reports, by measurement:
  - each cue section: integrated loudness (BS.1770-ish, no gate), momentary
    max, peak, clipped samples; next to the Phase 6 cue sections it replaces
  - each music change: request -> applied (free-tempo sets leave at once)
  - each drop-2 sting / one-shot: the frame it was asked for vs the frame it
    started, where it really starts in the recording (cross-correlation with
    its file, against the sync clicks), how far it rises over the music, and
    whether the music ducked under it
Writes capture_drop2_report.json.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bwdsp as d  # noqa: E402
import analyse_capture as ac  # noqa: E402

DROP2 = {"sting_good", "sting_bad", "sting_level_up", "sting_pick_reveal", "sting_room_hard", "shop_purchase"}


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ac.GAME.parent / "design" / "audio"
    j = json.loads((out / "capture_drop2.json").read_text())
    sr, x = d.load(out / "capture_drop2.wav")
    ac.SR = sr
    mono = x.mean(axis=1)
    t0 = j["record_start_usec"]

    def rel(usec):
        return (usec - t0) / 1e6

    rep = {"sample_rate": sr, "seconds": round(len(x) / sr, 2), "fps": j.get("fps")}
    sync = [e for e in j["sfx"] if e.get("tag") == "sync"]
    click = ac.load_sfx(sync[0]["file"]) if sync else None
    lags = [lag for e in sync for lag, sc in [ac.locate(mono, click, rel(e["usec"]), lo=-0.02, hi=0.2)] if lag is not None and sc > 0.6]
    base = float(np.median(lags)) if lags else 0.0
    rep["output_path_latency_ms"] = round(base * 1000, 1)

    marks = {m["what"]: rel(m["usec"]) for m in j["marks"]}
    secs = j["sections"]
    rows = []
    for (name, t), (_, t_next) in zip(secs[:-1], secs[1:]):
        if name == "sync":
            continue
        a = int((marks.get(name, t) + 2.0) * sr)          # skip the 2 s crossfade in
        b = int(min(t_next, rep["seconds"]) * sr)
        seg = x[a:b]
        rows.append({"section": name, "lufs": round(ac.lufs(seg), 1), "momentary_max": round(ac.momentary_max(seg), 1),
                     "peak_dbfs": round(d.peak_db(seg), 1), "clipped": int((np.abs(seg) >= 0.999).sum())})
    rep["sections"] = rows
    rep["phase6_reference"] = {"title": -20.3, "roster": -20.3, "combat": -19.5, "boss": -17.9}

    applied = [e for e in j["music"] if (e.get("type") == "applied" and e.get("what") == "cue") or e.get("type") == "start"]
    asked = [e for e in j["music"] if e.get("type") == "cue"]
    changes = []
    for q in asked:
        nxt = next((e for e in applied if int(e["usec"]) >= int(q["usec"])), None)
        if nxt:
            changes.append({"cue": q["cue"], "wait_s": round((int(nxt["usec"]) - int(q["usec"])) / 1e6, 3), "deck": nxt.get("deck")})
    rep["cue_changes"] = changes

    manifest = json.loads((ac.SFX_DIR / "sfx.json").read_text())["sounds"]
    stings = []
    for e in j["sfx"]:
        if e["name"] not in DROP2:
            continue
        t_req = rel(e["usec"])
        ref = ac.load_sfx(e["file"])
        # locate by the file's loudest 250 ms (a crescendo's quiet head matches poorly)
        w = int(0.25 * sr)
        cs = np.concatenate([[0.0], np.cumsum(ref ** 2)])
        o = int(np.argmax(cs[w:] - cs[:-w])) if len(ref) > w else 0
        lag, score = ac.locate(mono, ref[o:], t_req + base + o / sr, lo=-0.03, hi=0.15, hp=150.0)
        start = t_req + base + (lag or 0.0)
        body = float(manifest[e["name"]]["levels"][0].get("body_s", 1.5))
        pre = x[int(max(0, start - 1.5) * sr): int(max(0, start - 0.1) * sr)]
        on = x[int(start * sr): int((start + body) * sr)]
        stings.append({"name": e["name"], "tag": e.get("tag"), "asked_s": round(t_req, 3),
                       "found": bool(score > 0.3), "match": round(score, 2),
                       "start_vs_expected_ms": round((lag or 0.0) * 1000, 1),
                       "music_before_lufs": round(ac.momentary_max(pre), 1) if len(pre) > sr // 2 else None,
                       "body_s": body, "with_sting_momentary_max": round(ac.momentary_max(on), 1), "peak_dbfs": round(d.peak_db(on), 1)})
    rep["stings"] = stings
    rep["sting_log"] = [e for e in j["music"] if e.get("type") == "sting"]
    (out / "capture_drop2_report.json").write_text(json.dumps(rep, indent=1))
    print(json.dumps({k: rep[k] for k in ("output_path_latency_ms", "sections", "cue_changes", "stings")}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
