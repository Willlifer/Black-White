"""D411: analyse the sting-duck capture (godot --path game -- --duck --audio-capture <dir>).

    python game/tools/audio/analyse_duck.py <dir>

Reads capture_duck.wav (Master), capture_duck_music_pre.wav / _post.wav (the
Music bus before its duck and after it) and capture_duck.json. The applied
gain is post / pre in 20 ms windows (only where the music itself is above
-60 dBFS, so the chords' decays don't read as a duck). For each sting:
  - the gain before it, how long it took to fall 20 dB, the lowest gain
  - when it started back (the gain rising 3 dB over the floor) and when it
    was within 1 dB of 0 again, against the expected hold + DUCK_IN
  - for the overlap (cursed 1 s after the Hard room): no rise in between
  - for the screen change: the new track is playing, under the duck, and
    then at full gain
and the Master's clipped samples and peak. Writes capture_duck_report.json
into <dir> and prints the summary.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bwdsp as d  # noqa: E402

WIN = 0.02


def env(x, sr):
    m = x.mean(axis=1) if x.ndim > 1 else x
    n = int(WIN * sr)
    k = len(m) // n
    return np.sqrt(np.mean(m[:k * n].reshape(k, n) ** 2, axis=1))


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    j = json.loads((out / "capture_duck.json").read_text())
    sr, mx = d.load(out / "capture_duck.wav")
    _, pre = d.load(out / "capture_duck_music_pre.wav")
    _, post = d.load(out / "capture_duck_music_post.wav")
    t0 = j["record_start_usec"]
    n = min(len(pre), len(post))
    ep, eq = env(pre[:n], sr), env(post[:n], sr)
    live = ep > 10 ** (-60 / 20)
    gain = np.full(len(ep), np.nan)
    gain[live] = 20 * np.log10(np.maximum(eq[live], 1e-9) / ep[live])
    tt = np.arange(len(ep)) * WIN + WIN / 2

    def g_at(a, b):
        s = gain[(tt >= a) & (tt < b)]
        s = s[~np.isnan(s)]
        return s

    marks = {m["what"]: (m["usec"] - t0) / 1e6 for m in j["marks"]}
    holds = {e["kind"]: float(e.get("hold_s", 0.0)) for e in j["music"] if e.get("type") == "sting"}
    d_in = float(j["duck_in"])
    rep = {"sample_rate": sr, "seconds": round(len(mx) / sr, 2), "master_peak_dbfs": round(d.peak_db(mx), 2),
           "master_clipped": int((np.abs(mx) >= 0.999).sum()), "duck_out_s": j["duck_out"], "duck_in_s": d_in, "stings": []}
    plan = [("sting_level_up", "level_up", None), ("sting_room_hard", "room_hard", "sting_cursed_overlap"),
            ("sting_cursed_overlap", "cursed", None), ("sting_shop", "shop", "rooms"),
            ("picker_open", "pick", "picker_close"), ("sting_victory", "victory", None)]
    for mark, kind, nxt in plan:
        if mark not in marks:
            continue
        t = marks[mark]
        before = g_at(t - 1.0, t)
        row = {"sting": kind, "at_s": round(t, 2), "hold_s": holds.get(kind),
               "gain_before_db": round(float(np.median(before)), 2) if len(before) else None}
        # fall: first window 20 dB down after t
        after = (tt >= t) & ~np.isnan(gain)
        idx = np.where(after & (gain <= -20.0))[0]
        row["fell_20db_after_s"] = round(float(tt[idx[0]] - t), 3) if len(idx) else None
        nexts = [marks[m] for m, _, _ in plan if m in marks and marks[m] > t + 0.01]
        win_end = min([t + (holds.get(kind) or 3.0) + d_in + 3.0] + nexts)
        seg = (tt >= t) & (tt < win_end) & ~np.isnan(gain)
        row["min_gain_db"] = round(float(np.nanmin(gain[seg])), 1) if seg.any() else None
        if nxt is None or kind == "pick":
            # recovery: the gain starting back up (over -50 dB) and within 1 dB of 0 again
            ok = ~np.isnan(gain)
            rs = np.where(ok & (tt > t + j["duck_out"] + 0.1) & (gain > -50.0))[0]
            if len(rs):
                row["rise_start_after_s"] = round(float(tt[rs[0]] - t), 2)
                up = np.where(ok & (tt > tt[rs[0]]) & (gain > -1.0))[0]
                row["back_within_1db_after_s"] = round(float(tt[up[0]] - t), 2) if len(up) else None
            if kind == "pick":
                row["released_at_s"] = round(marks["picker_close"] - t, 2)
                row["expected_back_s"] = round(marks["picker_close"] - t + 0.4 + d_in, 2)   # stop_sting(0.8): release after 0.4 s
            else:
                row["expected_back_s"] = round((holds.get(kind) or 0.0) + d_in, 2)
        rep["stings"].append(row)
    # overlap: between the Hard room sting and the end of the cursed hold, the gain never climbs back
    if "sting_room_hard" in marks and "sting_cursed_overlap" in marks:
        a, b = marks["sting_room_hard"] + j["duck_out"] + 0.05, marks["sting_cursed_overlap"] + holds.get("cursed", 2.0) - 0.05
        s = g_at(a, b)
        rep["overlap"] = {"from_s": round(a, 2), "to_s": round(b, 2), "max_gain_db": round(float(s.max()), 1) if len(s) else None,
                          "note": "the second sting extends the duck: the music stays out between them"}
    # screen change mid-duck: the rooms track plays, ducked, then comes back to full gain
    if "rooms" in marks:
        t = marks["rooms"]
        hold_end = marks["sting_shop"] + holds.get("shop", 3.0)
        s_in = g_at(t + 0.2, hold_end - 0.05)
        live_after = ep[(tt > t + 0.5) & (tt < t + 6.0)]
        s_back = g_at(hold_end + d_in + 0.1, marks.get("picker_open", hold_end + 5.0) - 0.1)
        rep["screen_change"] = {"at_s": round(t, 2), "new_track_level_dbfs": round(d.db(float(np.sqrt(np.mean(live_after ** 2)))), 1),
                                "gain_while_sting_held_max_db": round(float(s_in.max()), 1) if len(s_in) else None,
                                "gain_after_median_db": round(float(np.median(s_back)), 2) if len(s_back) else None}
    # the frame log of BWMusic.duck_db(): its lowest and its last
    dl = j.get("duck_log", [])
    if dl:
        rep["duck_log"] = {"frames": len(dl), "min_db": round(min(v for _, v in dl), 1), "last_db": dl[-1][1]}
    (out / "capture_duck_report.json").write_text(json.dumps(rep, indent=1))
    print(json.dumps(rep, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
