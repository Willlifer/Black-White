"""Analyse an in-engine audio capture (godot --path game -- --audio-capture).

    python game/tools/audio/analyse_capture.py [design/audio]

Reads capture.wav (what the Master bus played, after the limiter) and
capture.json (what the game asked for, and when), and checks by analysis:
  - levels per section (title, roster, combat, boss): RMS, K-weighted
    loudness, momentary max, peak, clipped samples
  - beat alignment: when each music change was applied vs the bar/beat grid
    (the engine's own playback clock), and drum onsets in the recording vs
    the 120 / 132.3 BPM grid predicted from the deck start
  - SFX vs animation markers: the frame each marker fired vs the frame its
    sound started, and where the sound actually is in the recording
    (cross-correlation with its source file), against the calibration clicks
Writes capture_report.json, waveform.png, spectrogram.png, sfx_sync.png.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bwdsp as d  # noqa: E402

GAME = Path(__file__).resolve().parents[2]
SFX_DIR = GAME / "audio" / "sfx"
FRAME = 1.0 / 60.0
WHITE, GREY, DARK, INK = (240, 240, 240), (140, 140, 140), (70, 70, 70), (12, 12, 12)
SECTION_COL = {"title": (230, 230, 230), "roster": (120, 170, 255), "combat": (255, 120, 90), "boss": (255, 210, 60), "sync": (150, 150, 150)}


def lufs(x):
    """BS.1770-ish integrated loudness (no gating) of a stereo block."""
    ms = 0.0
    for c in range(x.shape[1]):
        ms += np.mean(d._kweight(x[:, c], SR) ** 2)
    return -0.691 + 10 * np.log10(ms + 1e-15)


def momentary_max(x):
    n = int(0.4 * SR)
    k = sum(d._kweight(x[:, c], SR) ** 2 for c in range(x.shape[1]))
    if len(k) <= n:
        return -0.691 + 10 * np.log10(np.mean(k) + 1e-15)
    cs = np.concatenate([[0.0], np.cumsum(k)])
    return -0.691 + 10 * np.log10(((cs[n:] - cs[:-n]) / n).max() + 1e-15)


def load_sfx(file):
    sr, y = d.load(SFX_DIR / file)
    m = y.mean(axis=1)
    if sr != SR:
        m = signal.resample_poly(m, SR, sr)
    return m


def locate(mono, ref, expect_s, lo=-0.03, hi=0.12, hp=250.0):
    """Lag (s) of `ref` in `mono` around expect_s, by normalised cross-
    correlation of high-passed signals; (lag, score)."""
    a = int(max(0, (expect_s + lo) * SR))
    b = int(min(len(mono), (expect_s + hi) * SR + len(ref)))
    seg = d.filt(mono[a:b], "high", hp, 2)
    r = d.filt(ref[: int(0.25 * SR)], "high", hp, 2)
    if len(seg) <= len(r) + 2:
        return None, 0.0
    c = signal.correlate(seg, r, mode="valid")
    e_seg = np.sqrt(np.convolve(seg ** 2, np.ones(len(r)), mode="valid"))
    nc = c / (e_seg * np.sqrt(np.sum(r ** 2)) + 1e-12)
    i = int(np.argmax(nc))
    return (a + i) / SR - expect_s, float(nc[i])


def main() -> int:
    global SR
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else GAME.parent / "design" / "audio"
    j = json.loads((out / "capture.json").read_text())
    SR, x = d.load(out / "capture.wav")
    mono = x.mean(axis=1)
    stem_path = out / "capture_sfx.wav"
    if stem_path.exists():
        _, st = d.load(stem_path)
        stem = st.mean(axis=1)
        # the stem is part of the master; the Master limiter's look-ahead delays the
        # master by a fixed amount, measured here at full rate around the loudest SFX second
        cs = np.concatenate([[0.0], np.cumsum(stem ** 2)])
        k = int(np.argmax(cs[SR:] - cs[:-SR]))
        a, b = k, min(len(stem), k + SR)
        c = signal.correlate(mono[a:b], stem[a:b], mode="full")
        stem_lag = int(np.argmax(c)) - (b - a - 1)
    else:
        stem, stem_lag = mono, 0
    t0 = j["record_start_usec"]

    def rel(usec):
        return (usec - t0) / 1e6

    report = {"sample_rate": SR, "seconds": round(len(x) / SR, 3), "fps": j.get("fps"),
              "sfx_stem": stem_path.exists(), "stem_vs_master_lag_samples": int(stem_lag)}

    # ---- calibration: the three sync clicks (UI bus, before any music)
    sync = [e for e in j["sfx"] if e.get("tag") == "sync"]
    click = load_sfx(sync[0]["file"]) if sync else None
    lags = []
    for e in sync:
        lag, sc = locate(mono, click, rel(e["usec"]), lo=-0.02, hi=0.2)
        if lag is not None and sc > 0.6:
            lags.append(lag)
    base = float(np.median(lags)) if lags else 0.0
    base_stem = base - stem_lag / SR          # the same path, minus the limiter look-ahead
    report["calibration"] = {"sync_clicks": len(sync), "found": len(lags), "lags_ms": [round(v * 1000, 1) for v in lags],
                             "output_path_latency_ms": round(base * 1000, 1),
                             "master_limiter_lookahead_ms": round(stem_lag / SR * 1000, 2),
                             "note": "time from the frame a sound is started to its first sample in the recording (mix block + latency); every later offset is measured against this. Godot starts a sound at a mix-block boundary, so single sounds scatter by about one block (10.7 ms at 48 kHz)"}

    # ---- sections
    marks = {m["what"]: rel(m["usec"]) for m in j["marks"]}
    names = ["title", "roster", "combat", "boss"]
    bounds = [marks.get(n) for n in names] + [marks.get("record_stop", len(x) / SR)]
    sections = {}
    for i, n in enumerate(names):
        a, b = bounds[i], bounds[i + 1]
        if a is None or b is None:
            continue
        seg = x[int((a + base) * SR): int((b + base) * SR)]
        sections[n] = {
            "from_s": round(a, 2), "to_s": round(b, 2),
            "rms_dbfs": round(d.rms_db(seg), 2), "loudness_lufs": round(lufs(seg), 2),
            "momentary_max_lufs": round(momentary_max(seg), 2), "peak_dbfs": round(d.peak_db(seg), 2),
            "samples_over_-1dBFS": int(np.sum(np.abs(seg) > d.undb(-1.0))),
            "clipped_samples": int(np.sum(np.abs(seg) >= 0.999)),
        }
    report["sections"] = sections
    report["whole"] = {"peak_dbfs": round(d.peak_db(x), 2), "clipped_samples": int(np.sum(np.abs(x) >= 0.999)),
                       "samples_over_-1dBFS": int(np.sum(np.abs(x) > d.undb(-1.0)))}

    # ---- music: changes applied vs the grid (engine clock)
    applied = [e for e in j["music"] if e.get("type") == "applied"]
    starts = [e for e in j["music"] if e.get("type") == "start"]
    report["music_changes"] = [{"what": e["what"], "quant": e["quant"], "cue": e["cue"], "deck": e["deck"],
                                "t_s": round(rel(e["usec"]), 3), "grid_s": round(float(e["grid_s"]), 4),
                                "error_ms": round(float(e["err_ms"]), 2)} for e in applied]
    errs = [abs(float(e["err_ms"])) for e in applied]
    report["music_change_error_ms"] = {"count": len(errs), "max_abs": round(max(errs), 2) if errs else None,
                                       "mean_abs": round(float(np.mean(errs)), 2) if errs else None,
                                       "frame_ms": round(FRAME * 1000, 2)}

    # ---- drum onsets in the recording vs the predicted grid
    grid_checks = []
    for i, s in enumerate(starts):
        deck = s["deck"]
        if deck.split("/")[0] not in ("main", "boss"):
            continue
        bpm = 120.0 if deck.startswith("main") else 120.0 * 705600 / 640000
        sixteenth = 60.0 / bpm / 4
        t_start = rel(s["usec"]) + base
        t_end = (rel(starts[i + 1]["usec"]) + base) if i + 1 < len(starts) else len(x) / SR
        a, b = int(t_start * SR), int(t_end * SR)
        if b - a < SR * 2:
            continue
        seg = d.filt(mono[a:b], "band", [60, 6000], 2)
        tt, fl = d.onset_flux(seg, SR, 512, 128)
        pk, pv = d.peaks(tt, fl, thr_rel=0.35, min_gap=0.08)
        if len(pk) < 4:
            continue
        # where the deck's source position 0 of a 16th falls: from = start position
        phase0 = float(s.get("from", 0.0))
        dev = []
        for t in pk:
            src = phase0 + t                      # source seconds at that onset (rate 1 within the set)
            k = np.round(src / sixteenth)
            dev.append((src - k * sixteenth) * 1000)
        dev = np.asarray(dev)
        grid_checks.append({"deck": deck, "cue": s["cue"], "from_s": round(t_start, 2), "to_s": round(t_end, 2), "onsets": len(pk),
                            "offset_ms_median": round(float(np.median(dev)), 2),
                            "spread_ms_iqr": round(float(np.subtract(*np.percentile(dev, [75, 25]))), 2),
                            "within_15ms_of_grid": round(float(np.mean(np.abs(dev - np.median(dev)) <= 15)), 3)})
    report["onsets_vs_grid"] = grid_checks

    # ---- SFX vs markers
    markers = j["markers"]
    pairs = {"impact": ("impact",), "release": ("release",), "grounded": ("grounded",), "hit2": ("hit2",), "launch": ("launch",)}
    rows = []
    for e in j["sfx"]:
        tag = e.get("tag", "")
        if tag not in pairs or not e.get("unit"):
            continue
        cand = [m for m in markers if m["unit"] == e["unit"] and m["marker"] in pairs[tag] and m["usec"] <= e["usec"] + 1
                and not m.get("report_after_lead", False)]
        if not cand:
            continue
        m = cand[-1]
        delayed = float(e.get("delay", 0.0))
        fgap = e["frame"] - m["frame"]
        # where the sound really is in the recording
        ref = load_sfx(e["file"])
        off = float(e.get("offset", 0.0))
        if off > 0:
            ref = ref[int(off * SR):]
        lag, sc = locate(stem, ref, rel(e["usec"]))
        row = {"sfx": e["file"], "tag": tag, "unit": e["unit"], "marker": m["clip"] + ":" + m["marker"],
               "marker_frame": m["frame"], "sfx_frame": e["frame"], "frame_gap": fgap, "scheduled_delay_s": round(delayed, 3),
               "found_in_capture": lag is not None and sc > 0.45, "score": round(sc, 2),
               "t_s": round(rel(e["usec"]), 3)}
        row["led"] = bool(m.get("led", False))
        if lag is not None and sc > 0.45:
            start = rel(e["usec"]) + lag - base_stem          # when it really began, in game-clock seconds
            if tag == "launch":
                # lined up so its loudest moment lands on the strike's `hit`
                hits = [h for h in markers if h["unit"] == e["unit"] and h["marker"] == "hit" and h["usec"] >= m["usec"]
                        and not h.get("report_after_lead", False)]
                if hits:
                    name, n = e["file"][:-4].rsplit("_", 1)
                    pk = json.loads((SFX_DIR / "sfx.json").read_text())["sounds"][name]["levels"][int(n) - 1]["peak_s"]
                    row["aligned_to"] = hits[0]["clip"] + ":hit"
                    row["sound_vs_marker_ms"] = round((start + float(pk) - off - rel(hits[0].get("true_usec", hits[0]["usec"]))) * 1000, 1)
            else:
                row["sound_vs_marker_ms"] = round((start - rel(m.get("true_usec", m["usec"]))) * 1000, 1)
        rows.append(row)
    report["sfx_vs_markers"] = rows
    imm = [r for r in rows if r["scheduled_delay_s"] == 0.0]
    found = [r for r in rows if "sound_vs_marker_ms" in r]
    report["sfx_sync_summary"] = {
        "marker_linked_sounds": len(rows),
        "same_frame_as_marker": sum(1 for r in imm if r["frame_gap"] == 0),
        "led_by_a_frame": sum(1 for r in rows if r.get("led")),
        "led_max_abs_ms": round(max([abs(r["sound_vs_marker_ms"]) for r in found if r.get("led") and not r.get("aligned_to")] or [0]), 1),
        "aligned_peak_vs_marker_ms": [r["sound_vs_marker_ms"] for r in found if r.get("aligned_to")],
        "frame0_impacts_ms": [r["sound_vs_marker_ms"] for r in found if not r.get("led")],
        "immediate_sounds": len(imm),
        "found_in_capture": len(found),
        "sound_vs_marker_ms_max_abs": round(max(abs(r["sound_vs_marker_ms"]) for r in found), 1) if found else None,
        "within_one_frame": sum(1 for r in found if abs(r["sound_vs_marker_ms"]) <= FRAME * 1000 + 0.5),
    }
    # aligned whooshes: their loudest moment vs the strike's hit marker
    peaks_vs_hit = []
    for e in j["sfx"]:
        if e.get("tag") not in ("launch", "cast_whoom") or not e.get("unit"):
            continue
        want = "hit" if e["tag"] == "launch" else "release"
        hits = [m for m in markers if m["unit"] == e["unit"] and m["marker"] == want and m["usec"] >= e["usec"] - 400000
                and not m.get("report_after_lead", False)]
        if not hits:
            continue
        name, n = e["file"][:-4].rsplit("_", 1)
        info = json.loads((SFX_DIR / "sfx.json").read_text())["sounds"][name]["levels"][int(n) - 1]
        peak_t = rel(e["usec"]) + float(info["peak_s"]) - float(e.get("offset", 0.0))
        peaks_vs_hit.append({"sfx": e["file"], "marker": want, "peak_minus_marker_ms": round((peak_t - rel(hits[0].get("true_usec", hits[0]["usec"]))) * 1000, 1),
                             "note": "from the logged start time; the recording-based check is in sfx_vs_markers"})
    report["whoosh_peak_vs_marker"] = peaks_vs_hit
    (out / "capture_report.json").write_text(json.dumps(report, indent=1))

    # ---- pictures
    draw_waveform(out / "waveform.png", x, base, marks, names, applied, j, rel, sections)
    draw_spectrogram(out / "spectrogram.png", mono, base, marks, names, applied, rel)
    draw_sync(out / "sfx_sync.png", stem, rows, rel, base_stem, j)
    print(json.dumps({k: report[k] for k in ("calibration", "sections", "whole", "music_change_error_ms", "onsets_vs_grid", "sfx_sync_summary", "whoosh_peak_vs_marker")}, indent=1))
    return 0


def _section_bands(img, marks, names, base, W, secs, top, h):
    for i, n in enumerate(names):
        a = marks.get(n)
        b = marks.get(names[i + 1]) if i + 1 < len(names) else marks.get("record_stop", secs)
        if a is None:
            continue
        xa, xb = int((a + base) / secs * W), int((b + base) / secs * W)
        img[top:top + 6, xa:xb] = SECTION_COL[n]
        d.draw_text(img, xa + 6, top + 12, n, SECTION_COL[n], 2)


def draw_waveform(path, x, base, marks, names, applied, j, rel, sections):
    W, H = 2400, 720
    img = np.full((H, W, 3), INK, np.uint8)
    secs = len(x) / SR
    lanes = [(110, 330, 0), (370, 590, 1)]
    for top, bot, ch in lanes:
        mid = (top + bot) // 2
        col = x[:, ch]
        n = len(col) // W
        mx = col[: n * W].reshape(W, n).max(axis=1)
        mn = col[: n * W].reshape(W, n).min(axis=1)
        rms = np.sqrt((col[: n * W].reshape(W, n) ** 2).mean(axis=1))
        half = (bot - top) // 2
        for k in range(W):
            y0, y1 = int(mid - mx[k] * half), int(mid - mn[k] * half)
            img[max(top, y0):min(bot, y1 + 1), k] = GREY
            r = int(rms[k] * half)
            img[mid - r:mid + r + 1, k] = WHITE
        for db_line in (-1.0, -6.0):
            v = int(d.undb(db_line) * half)
            img[mid - v, ::4] = (200, 60, 60) if db_line == -1 else DARK
            img[mid + v, ::4] = (200, 60, 60) if db_line == -1 else DARK
        d.draw_text(img, 8, top + 4, "L" if ch == 0 else "R", WHITE, 2)
    _section_bands(img, marks, names, base, W, secs, 70, 6)
    for e in applied:
        xx = int((rel(e["usec"]) + base) / secs * W)
        img[100:600, xx] = (255, 210, 60) if e["what"] == "cue" else (120, 220, 120)
    for e in j["sfx"]:
        xx = int((rel(e["usec"]) + base) / secs * W)
        c = (255, 120, 90) if e.get("tag") in ("impact", "release", "launch", "grounded") else (DARK if e.get("tag") == "step" else (150, 150, 255))
        img[605:625 if e.get("tag") != "step" else 612, max(0, xx - 1):xx + 1] = c
    for s in range(0, int(secs) + 1, 5):
        xx = int(s / secs * W)
        img[630:640, xx] = WHITE
        d.draw_text(img, xx + 3, 645, f"{s}S", GREY, 2)
    d.draw_text(img, 8, 8, "BLACK | WHITE AUDIO CAPTURE: MASTER BUS AFTER LIMITER. GREY = PEAK, WHITE = RMS, RED DOTS = -1 DBFS", WHITE, 2)
    d.draw_text(img, 8, 32, "YELLOW = CUE CHANGE APPLIED ON THE BAR, GREEN = INTENSITY ON THE BEAT. TICKS BELOW: RED = MARKER SFX, BLUE = UI, GREY = STEPS", GREY, 2)
    yy = 670
    xx = 8
    for n, s in sections.items():
        d.draw_text(img, xx, yy, f"{n}: {s['loudness_lufs']:.1f} LUFS PEAK {s['peak_dbfs']:.1f}", SECTION_COL[n], 2)
        xx += 590
    d.write_png(path, img)


def draw_spectrogram(path, mono, base, marks, names, applied, rel):
    W, H = 2400, 760
    top, bot = 90, 700
    f, t, Z = signal.stft(mono, SR, nperseg=4096, noverlap=4096 - 1024)
    S = 20 * np.log10(np.abs(Z) + 1e-9)
    secs = len(mono) / SR
    fmin, fmax = 30.0, 16000.0
    rows = bot - top
    fy = fmin * (fmax / fmin) ** (1 - np.arange(rows) / (rows - 1))
    fi = np.clip(np.searchsorted(f, fy), 0, len(f) - 1)
    ti = np.clip((np.arange(W) / W * secs / (t[1] - t[0])).astype(int), 0, len(t) - 1)
    M = S[fi][:, ti]
    v = np.clip((M + 100) / 85, 0, 1) ** 0.8
    img = np.full((H, W, 3), INK, np.uint8)
    img[top:bot] = (v[:, :, None] * 255).astype(np.uint8)
    for hz in (50, 100, 200, 500, 1000, 2000, 5000, 10000):
        yy = top + int((1 - np.log(hz / fmin) / np.log(fmax / fmin)) * (rows - 1))
        img[yy, :40] = (255, 120, 90)
        d.draw_text(img, 44, yy - 6, f"{hz}" if hz < 1000 else f"{hz // 1000}K", (255, 120, 90), 2)
    for e in applied:
        xx = int((rel(e["usec"]) + base) / secs * W)
        img[top - 12:top, xx] = (255, 210, 60) if e["what"] == "cue" else (120, 220, 120)
    _section_bands(img, marks, names, base, W, secs, 56, 6)
    for s in range(0, int(secs) + 1, 5):
        xx = int(s / secs * W)
        img[bot:bot + 8, xx] = WHITE
        d.draw_text(img, xx + 3, bot + 14, f"{s}S", GREY, 2)
    d.draw_text(img, 8, 8, "SPECTROGRAM 30 HZ - 16 KHZ (LOG), -100..-15 DBFS. TOP TICKS: YELLOW = CUE CHANGE, GREEN = INTENSITY", WHITE, 2)
    d.write_png(path, img)


def draw_sync(path, mono, rows, rel, base_stem_g, j):
    """Zooms on marker-linked sounds: the marker frame (red) vs the sound in the recording."""
    pick = [r for r in rows if "sound_vs_marker_ms" in r and not r.get("aligned_to")][:8]
    W, Hs = 1200, 150
    H = 60 + Hs * max(1, len(pick))
    img = np.full((H, W, 3), INK, np.uint8)
    d.draw_text(img, 8, 8, "SFX VS MARKER: RED = THE MARKER'S TRUE TIME (+ PATH LATENCY). 250 MS WINDOWS OF THE SFX-BUS STEM", WHITE, 2)
    for i, r in enumerate(pick):
        top = 50 + i * Hs
        mk = [m for m in j["markers"] if m["unit"] == r["unit"] and m["frame"] == r["marker_frame"]]
        if r.get("aligned_to"):
            continue
        tm = rel(mk[0].get("true_usec", mk[0]["usec"])) + base_stem_g if mk else r["t_s"] + base_stem_g
        a = int((tm - 0.05) * SR)
        seg = mono[a:a + int(0.25 * SR)]
        if len(seg) < W:
            continue
        n = len(seg) // W
        mx = np.abs(seg[: n * W]).reshape(W, n).max(axis=1)
        sc = 0.9 / (mx.max() + 1e-9)
        mid = top + Hs // 2
        for k in range(W):
            h = int(mx[k] * sc * (Hs // 2 - 12))
            img[mid - h:mid + h + 1, k] = GREY
        xm = int(0.05 / 0.25 * W)
        img[top + 4:top + Hs - 8, xm] = (255, 80, 60)
        d.draw_text(img, 8, top + 4, f"{r['sfx'][:-4]} ON {r['marker']}: {r['sound_vs_marker_ms']:+.1f} MS", WHITE, 2)
    d.write_png(path, img)


SR = 48000
if __name__ == "__main__":
    sys.exit(main())
