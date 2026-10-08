"""D412: retune the author's drop-2 stings by -3 semitones (C -> A), duration
and transients kept. The author, 2026-10-08: "I did notice some clashes
between A and C. If you can adjust that, it may clash less."

    python game/tools/audio/retune.py          # compare the methods, measure keys -> design/audio/retune_report.json

make_drop2.py and make_placeholders.py call `shifted(name)` for every source
they cut a sting from, so the A files and their C alternates come out of the
same trim / level pipeline. The originals in design/audio/ are only read.

Pitch shift = a time-scale change by 37/44 (2^(-3/12) to 0.03 cents) and a
polyphase resample by 44/37 back to the original length. Methods compared
on all six sources (measure(), the report's "methods"):
  pv_basic   phase vocoder, 2048 / hop 256, per channel, no phase locking
  pv_locked  phase vocoder, 2048 / hop 256: phase increments measured over
             exactly one synthesis hop (no unwrapping), identity phase
             locking around spectral peaks, a phase reset on transient
             frames, and one set of phase corrections for both channels
             (taken from the mid), so the stereo image keeps its phases
  wsola      bwdsp.wsola (1024 / tol 256), then the same resample
  pv_transient  pv_locked, then transient handling: around each clear
             onset (flux peak >= 25% of the max, 150 ms apart) the plain
             resample is spliced in from 20 ms before to 30 ms after, so the
             attack keeps its shape (no vocoder window smear); dense runs
             are left to the vocoder. PICKED: transients as sharp as WSOLA,
             tones as clean as the vocoder (design/audio/retune_report.json)
Measures (compare()): onset flux, pre-echo, envelope warble, stereo image,
chroma, plus tonal contrast against the plain resample (the ideal spectrum)
and onset timing on a synthetic pluck train.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from scipy import signal

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bwdsp as d  # noqa: E402

SR = d.SR
SEMITONES = -3
UP, DOWN = 44, 37                      # resample ratio; DOWN/UP = 0.840909 vs 2^(-3/12) = 0.840896
ALPHA = DOWN / UP                      # time-scale factor before the resample
METHOD = "pv_transient"                # picked by measure() (see the report)
# the author's sting files (design/audio names); everything the stings and
# the sting-made placeholders are cut from
SOURCES = ["sting level up", "sting pick reveal", "sting room hard", "very good event", "cursed or bad", "shop purchase"]
PC = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
MAJOR = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])   # Krumhansl-Kessler
MINOR = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])
A_MAJOR = [9, 11, 1, 2, 4, 6, 8]       # A B C# D E F# G# (= F# natural minor)
C_MAJOR = [0, 2, 4, 5, 7, 9, 11]


# ------------------------------------------------------------------ methods

def _stft_frame(x, pos, win, n):
    seg = np.zeros(n)
    a, b = max(pos, 0), min(pos + n, len(x))
    if b > a:
        seg[a - pos: b - pos] = x[a:b]
    return np.fft.rfft(seg * win)


def pv_stretch(x, alpha, n=2048, hs=256, lock=True, reset=True):
    """Phase-vocoder time-scale: output length = alpha * input. x: (n, ch).
    Each synthesis frame k reads the input at a_k = k*hs/alpha and at
    a_k - hs, so its phase advance is measured over exactly one synthesis
    hop. lock: identity phase locking (Laroche-Dolson); reset: analysis
    phases on transient frames; the corrections come from the mid and are
    applied to every channel."""
    x = x if x.ndim > 1 else x[:, None]
    ch = x.shape[1]
    win = np.hanning(n)
    n_out = int(round(len(x) * alpha))
    k_max = n_out // hs + 2
    y = np.zeros((n_out + 2 * n, ch))
    wsum = np.zeros(n_out + 2 * n)
    mid = x.mean(axis=1)
    phs = None
    prev_mag = None
    flux_hist: list[float] = []
    for k in range(k_max):
        a = int(round(k * hs / alpha)) - n // 2
        Xm = _stft_frame(mid, a, win, n)
        Xp = _stft_frame(mid, a - hs, win, n)
        mag = np.abs(Xm)
        ph_now = np.angle(Xm)
        # transient: positive log-spectral flux far over its running median
        transient = False
        if prev_mag is not None:
            fl = float(np.maximum(np.log1p(100 * mag) - np.log1p(100 * prev_mag), 0).sum())
            med = float(np.median(flux_hist[-24:])) if flux_hist else fl
            transient = reset and len(flux_hist) > 3 and fl > 3.0 * med + 1e-9 and fl > 1.0
            flux_hist.append(fl)
        prev_mag = mag
        if phs is None or transient:
            phs = ph_now.copy()
        else:
            adv = ph_now - np.angle(Xp)                       # advance over exactly hs (mod 2 pi is all we need)
            new = phs + adv
            if lock:
                # identity phase locking: bins follow their region's peak
                pk = signal.argrelmax(mag, order=1)[0]
                pk = pk[mag[pk] > mag.max() * 1e-4] if len(pk) else pk
                if len(pk):
                    edges = np.concatenate([[0], (pk[:-1] + pk[1:]) // 2 + 1, [len(mag)]])
                    owner = np.repeat(pk, np.diff(edges))
                    new = new[owner] + (ph_now - ph_now[owner])
            phs = new
        corr = phs - ph_now                                   # one correction per bin, all channels
        o = k * hs
        for c in range(ch):
            Xc = _stft_frame(x[:, c], a, win, n)
            frame = np.fft.irfft(Xc * np.exp(1j * corr), n) * win
            y[o: o + n, c] += frame
        wsum[o: o + n] += win ** 2
    # the output frame k is centred at k*hs + n/2 for input centre k*hs/alpha
    y = y[n // 2: n // 2 + n_out] / np.maximum(wsum[n // 2: n // 2 + n_out], 1e-3)[:, None]
    return y


def pv_basic_stretch(x, alpha, n=2048, hs=256):
    """The textbook vocoder: each channel on its own, no locking, no reset."""
    x = x if x.ndim > 1 else x[:, None]
    return np.concatenate([pv_stretch(x[:, c:c + 1], alpha, n, hs, lock=False, reset=False) for c in range(x.shape[1])], axis=1)


def resample_back(y, n_len):
    z = signal.resample_poly(y, UP, DOWN, axis=0)
    if len(z) >= n_len:
        return z[:n_len]
    return np.concatenate([z, np.zeros((n_len - len(z), z.shape[1]))])


def onset_times(x, thr=0.12, gap=0.08):
    """Onsets (s) of the source: spectral-flux peaks (frame centres)."""
    t, fl = d.onset_flux(x.mean(axis=1), SR, 1024, 128)
    pt, _ = d.peaks(t, fl, thr_rel=thr, min_gap=gap)
    return pt


def _best_cut(a, b, lo, hi, w):
    """The sample in [lo, hi) where a and b agree best over w samples (mid)."""
    best, at = -2.0, (lo + hi) // 2
    ma, mb = a.mean(axis=1), b.mean(axis=1)
    for i in range(lo, hi, 16):
        p, q = ma[i - w // 2: i + w // 2], mb[i - w // 2: i + w // 2]
        if len(p) < w or len(q) < w:
            continue
        den = np.sqrt((p @ p) * (q @ q))
        r = (p @ q) / den if den > 1e-12 else 0.0
        if r > best:
            best, at = r, i
    return at


def splice_transients(y, x, pre=0.02, post=0.03, xf=0.008, spacing=0.15):
    """Transient handling for the vocoder: around each source onset, the
    vocoder's window smears the attack (~14 ms rise, some pre-echo). The
    plain resample (pitch right, 19% slower, no smear) is spliced in from
    `pre` before the onset to `post` after it, its onset placed on the
    source's onset time; both splice points sit where the two signals agree
    best (+-6 ms) and crossfade over `xf` (equal-gain on correlated signals)."""
    z = signal.resample_poly(x, UP, DOWN, axis=0)     # pitch -3 st, 1.189x long
    out = y.copy()
    k = UP / DOWN
    n_xf = int(xf * SR)
    w = int(0.006 * SR)
    last = -1.0
    for t in onset_times(x, thr=0.25):
        if t - last < spacing:                        # a dense run: the vocoder keeps it (splices would roughen it)
            continue
        last = t
        o = int(t * SR)                               # the flux peak leads a clean attack by ~7 ms
        s_out, e_out = o - int(pre * SR), o + int(post * SR)
        if s_out - w - n_xf < 0 or e_out + w + n_xf >= len(y):
            continue
        off = int(round(o * k)) - o                   # z index = out index + off (onset on onset)
        if s_out + off - w < 0 or e_out + off + w + n_xf >= len(z):
            continue
        zz = z[off:off + len(y)] if off + len(y) <= len(z) else np.concatenate([z[off:], np.zeros((off + len(y) - len(z), z.shape[1]))])
        s = _best_cut(y, zz, s_out - w, s_out + w, n_xf)
        e = _best_cut(y, zz, e_out - w, e_out + w, n_xf)
        ramp = np.sin(np.linspace(0, np.pi / 2, n_xf))[:, None] ** 2
        out[s: s + n_xf] = y[s: s + n_xf] * (1 - ramp) + zz[s: s + n_xf] * ramp
        out[s + n_xf: e] = zz[s + n_xf: e]
        out[e: e + n_xf] = zz[e: e + n_xf] * (1 - ramp) + y[e: e + n_xf] * ramp
    return out


def shift(x, method=METHOD):
    """-3 semitones, same length. x: (n, ch)."""
    if method == "pv_transient":
        return splice_transients(resample_back(pv_stretch(x, ALPHA), len(x)), x)
    if method == "pv_locked":
        y = pv_stretch(x, ALPHA)
    elif method == "pv_basic":
        y = pv_basic_stretch(x, ALPHA)
    elif method == "wsola":
        y = d.wsola(x, ALPHA)
    else:
        raise ValueError(method)
    return resample_back(y, len(x))


_cache: dict = {}


def load_src(name):
    sr, x = d.load(Path(__file__).resolve().parents[3] / "design" / "audio" / f"{name}.wav")
    assert sr == SR, (name, sr)
    return x if x.shape[1] == 2 else np.repeat(x, 2, axis=1)


def shifted(name, method=METHOD):
    """The author's file `name`, retuned -3 st (cached; the original is only read).
    Peak-guarded: a shift can raise a peak a little; the trims re-level anyway."""
    key = (name, method)
    if key not in _cache:
        y = shift(load_src(name), method)
        pk = np.abs(y).max()
        if pk > 0.99:
            y *= 0.99 / pk
        _cache[key] = y
    return _cache[key].copy()


# ------------------------------------------------------------------ measures

def chroma(x, fmin=55.0, fmax=2000.0):
    """Energy per pitch class (C = 0), from a 8192-point STFT."""
    m = x.mean(axis=1) if x.ndim > 1 else x
    f, _, Z = signal.stft(m, SR, nperseg=8192, noverlap=8192 - 2048)
    P = (np.abs(Z) ** 2).sum(axis=1)
    sel = (f >= fmin) & (f <= fmax)
    pc = (np.round(12 * np.log2(f[sel] / 440.0)).astype(int) + 9) % 12
    c = np.bincount(pc, weights=P[sel], minlength=12)
    return c / (c.sum() + 1e-12)


def key_of(c):
    """Best Krumhansl key and the next two, with correlations."""
    rows = []
    for i in range(12):
        rows.append((float(np.corrcoef(c, np.roll(MAJOR, i))[0, 1]), f"{PC[i]} major"))
        rows.append((float(np.corrcoef(c, np.roll(MINOR, i))[0, 1]), f"{PC[i]} minor"))
    rows.sort(reverse=True)
    return rows[:3]


def describe_key(x):
    c = chroma(x)
    top = [PC[i] for i in np.argsort(c)[::-1][:4]]
    k = key_of(c)
    return {"centre": PC[int(np.argmax(c))], "top_pcs": top, "key": k[0][1], "key_r": round(k[0][0], 3),
            "next": [f"{n} ({r:.2f})" for r, n in k[1:]],
            "in_A_major_pct": round(100 * float(c[A_MAJOR].sum()), 1), "in_C_major_pct": round(100 * float(c[C_MAJOR].sum()), 1),
            "chroma": [round(float(v), 4) for v in c]}


def _env_db(m, a, b):
    seg = m[max(0, a): max(0, b)]
    return d.db(np.sqrt(np.mean(seg ** 2))) if len(seg) else -120.0


def compare(orig, proc):
    """Ear-proxy measures of one shift against its source (same length).
    flux_ratio_db   onset sharpness: the spectral-flux peak at each source
                    onset, processed vs source (0 = as sharp; negative = smeared)
    pre_echo_db     energy 40-5 ms before each onset over the 30 ms after,
                    processed minus source (positive = attacks smeared early)
    warble_db       10-60 Hz modulation of the 5 ms RMS envelope away from
                    onsets, processed minus source (WSOLA's splice flutter)
    stereo_r_diff   mean |L/R correlation change| over 50 ms frames (phasiness
                    shows as a wandering stereo image)
    chroma_r        processed chroma vs the source's rolled -3 (1 = exact shift)"""
    mo, mp = orig.mean(axis=1), proc.mean(axis=1)
    t, flo = d.onset_flux(mo, SR, 1024, 128)
    _, flp = d.onset_flux(mp, SR, 1024, 128)
    pt, _ = d.peaks(t, flo, thr_rel=0.2, min_gap=0.1)
    ratios, pre = [], []
    for tt in pt:
        i = int(np.argmin(np.abs(t - tt)))
        w = max(1, int(0.02 * SR / 128))
        po = flo[max(0, i - w): i + w + 1].max()
        pp = flp[max(0, i - w): i + w + 1].max()
        ratios.append(d.db(pp / max(po, 1e-9)))
        s = int(tt * SR)
        def pe(m):
            return _env_db(m, s - int(0.04 * SR), s - int(0.005 * SR)) - _env_db(m, s, s + int(0.03 * SR))
        pre.append(pe(mp) - pe(mo))
    # envelope warble away from onsets
    h = int(0.005 * SR)
    def env(m):
        k = len(m) // h
        return np.sqrt(np.mean(m[:k * h].reshape(k, h) ** 2, axis=1)) + 1e-6
    eo, ep = env(mo), env(mp)
    keep = np.ones(len(eo), bool)
    for tt in pt:
        a = int(tt / 0.005)
        keep[max(0, a - 4): a + 30] = False
    keep &= eo > eo.max() * 10 ** (-40 / 20)
    sos = signal.butter(2, [10, 60], "band", fs=200, output="sos")
    def warble(e):
        le = 20 * np.log10(e)
        mod = signal.sosfiltfilt(sos, le)
        return float(np.sqrt(np.mean(mod[keep] ** 2))) if keep.any() else 0.0
    # stereo image
    f = int(0.05 * SR)
    def lr(x):
        out = []
        for i in range(0, len(x) - f, f):
            L, R = x[i:i + f, 0], x[i:i + f, 1]
            if np.sqrt(np.mean(L ** 2)) > 1e-3:
                out.append(float(np.corrcoef(L, R)[0, 1]))
            else:
                out.append(np.nan)
        return np.array(out)
    ro, rp = lr(orig), lr(proc)
    ok = ~np.isnan(ro) & ~np.isnan(rp)
    co, cp = chroma(orig), chroma(proc)
    return {"onsets": len(pt), "flux_ratio_db": round(float(np.mean(ratios)), 2), "flux_ratio_worst_db": round(float(np.min(ratios)), 2),
            "pre_echo_db": round(float(np.mean(pre)), 2), "warble_db": round(warble(ep) - warble(eo), 3),
            "stereo_r_diff": round(float(np.mean(np.abs(ro[ok] - rp[ok]))), 4) if ok.any() else 0.0,
            "chroma_r": round(float(np.corrcoef(np.roll(co, SEMITONES), cp)[0, 1]), 4),
            "length_same": len(orig) == len(proc)}


def contrast_db(x):
    """Tonal contrast: per frame, the 95th over the 30th percentile of the
    100 Hz-2 kHz power spectrum (dB), averaged. Smeared or combed partials
    (WSOLA doubling, vocoder phasiness) lower it."""
    m = x.mean(axis=1)
    f, _, Z = signal.stft(m, SR, nperseg=4096, noverlap=3072)
    P = np.abs(Z[(f > 100) & (f < 2000)]) ** 2
    e = P.sum(axis=0)
    keep = e > e.max() * 1e-3
    return float(np.mean(10 * np.log10(np.percentile(P[:, keep], 95, axis=0) / (np.percentile(P[:, keep], 30, axis=0) + 1e-20))))


def pluck_timing(method):
    """Three synthetic 440 Hz plucks at 0.5 / 1.3 / 2.1 s: where each attack
    lands after the shift (ms vs true) and its 10-90% rise (ms)."""
    t = np.arange(int(3 * SR)) / SR
    x = np.zeros_like(t)
    for on in (0.5, 1.3, 2.1):
        m = t >= on
        x[m] += np.sin(2 * np.pi * 440 * (t[m] - on)) * np.exp(-(t[m] - on) * 4)
    y = shift(np.stack([x, x], 1) * 0.5, method)
    errs, rises = [], []
    for on in (0.5, 1.3, 2.1):
        a = int((on - 0.05) * SR)
        seg = np.abs(y[a:a + int(0.1 * SR), 0])
        errs.append(np.argmax(seg > 0.5 * seg.max()) / SR * 1000 - 50.0)
        rises.append((np.argmax(seg > 0.9 * seg.max()) - np.argmax(seg > 0.1 * seg.max())) / SR * 1000)
    return {"onset_err_ms": [round(float(v), 1) for v in errs], "rise_ms": [round(float(v), 1) for v in rises]}


METHODS = ("pv_basic", "pv_locked", "wsola", "pv_transient")


def measure() -> dict:
    rep = {"semitones": SEMITONES, "ratio": f"{DOWN}/{UP} = {ALPHA:.6f} (2^(-3/12) = {2 ** (-3 / 12):.6f})",
           "methods": {}, "keys": {}, "picked": METHOD, "plucks": {}}
    for name in SOURCES:
        x = load_src(name)
        ref = contrast_db(signal.resample_poly(x, UP, DOWN, axis=0))
        rep["keys"][name] = {"before": describe_key(x)}
        for m in METHODS:
            y = shifted(name, m)
            row = compare(x, y)
            row["contrast_vs_resample_db"] = round(contrast_db(y) - ref, 2)
            rep["methods"].setdefault(m, {})[name] = row
            if m == METHOD:
                rep["keys"][name]["after"] = describe_key(y)
    for m in METHODS:
        rep["plucks"][m] = pluck_timing(m)
    summary = {}
    for m, rows in rep["methods"].items():
        vals = list(rows.values())
        summary[m] = {k: round(float(np.mean([v[k] for v in vals])), 3) for k in
                      ("flux_ratio_db", "flux_ratio_worst_db", "pre_echo_db", "warble_db", "stereo_r_diff", "chroma_r", "contrast_vs_resample_db")}
        summary[m].update(rep["plucks"][m])
    rep["summary"] = summary
    return rep


def game_keys() -> dict:
    """The shipped copies, A vs their C alternates (sfx.json "key"/"alt_of"):
    the pitch centre and how much chroma energy sits in A major / F# minor."""
    sfx = Path(__file__).resolve().parents[2] / "audio" / "sfx"
    man = json.loads((sfx / "sfx.json").read_text())["sounds"]
    out = {}
    for name, row in man.items():
        if row.get("key") != "A":
            continue
        alt = name + "_c"
        r = {}
        for tag, n in (("C", alt), ("A", name)):
            if n not in man:
                continue
            xs = [d.load(sfx / f"{n}_{v}.wav")[1] for v in range(1, int(man[n]["variants"]) + 1)]
            x = np.concatenate([v if v.shape[1] == 2 else np.repeat(v, 2, axis=1) for v in xs])
            k = describe_key(x)
            r[tag] = {kk: k[kk] for kk in ("centre", "top_pcs", "key", "key_r", "in_A_major_pct", "in_C_major_pct")}
        out[name] = r
    return out


def main() -> int:
    if "--game" in sys.argv:              # only the shipped copies (after make_drop2 --stings)
        out = Path(__file__).resolve().parents[3] / "design" / "audio" / "retune_report.json"
        rep = json.loads(out.read_text())
        rep["game_files"] = game_keys()
        out.write_text(json.dumps(rep, indent=1))
        for n, r in rep["game_files"].items():
            c, a = r.get("C", {}), r.get("A", {})
            print(f"  {n:18s} C: {c.get('key', ''):9s} top {'/'.join(c.get('top_pcs', [])[:3]):9s} A-maj {c.get('in_A_major_pct')}%  ->  "
                  f"A: {a.get('key', ''):9s} top {'/'.join(a.get('top_pcs', [])[:3]):9s} A-maj {a.get('in_A_major_pct')}%")
        return 0
    rep = measure()
    rep["game_files"] = game_keys()
    out = Path(__file__).resolve().parents[3] / "design" / "audio" / "retune_report.json"
    out.write_text(json.dumps(rep, indent=1))
    print(json.dumps(rep["summary"], indent=1))
    for n, k in rep["keys"].items():
        b, a = k["before"], k.get("after", {})
        print(f"  {n:18s} {b['key']:9s} ({b['centre']}, A-maj {b['in_A_major_pct']}%)  ->  {a.get('key', '?'):9s} "
              f"({a.get('centre', '?')}, A-maj {a.get('in_A_major_pct', '?')}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
