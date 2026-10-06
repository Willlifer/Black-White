"""Music layers for Black | White (Phase 6). Deterministic.

    python game/tools/audio/make_music.py

Reads the author's loops and writes sample-aligned 16.0 s loops (8 bars at
120 BPM, 705 600 samples, 44.1 kHz 16-bit stereo) into
game/audio/music/layers/, plus layers.json (what each layer is, its levels,
its seam check). BWMusic plays them all at once in an AudioStreamSynchronized
and mixes them per cue.

Inputs (never modified):
  game/audio/music/blackwhite_loop.wav   120 BPM, 8 bars + a 0.32 s reverb tail
  game/audio/music/drum_beat.wav         90 BPM, 8 bars = 21.333 s (the Low fish beat)
  ../Low fish Beat Project/Samples/Recorded/*.wav   two raw voice takes (male, ~120-200 Hz)

Layers:
  full        the BlackWhite loop, its tail wrapped into its head
  calm        full, low-passed (800 Hz)
  air         full, high-passed (2.5 kHz) plus a gentle exciter on the harmonic part
  perc        the percussive part of full (HPSS: median filtering on the STFT)
  drums       drum_beat, 90 -> 120 BPM without changing pitch (WSOLA anchored on the 16th grid)
  drums_half  the first 4 bars of drum_beat at half-time against 120 (same method, x1.5)
  voice_pad   a granular pad from the Low fish voice takes, tuned to the loop's bass roots
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.ndimage import median_filter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bwdsp as d  # noqa: E402

SR = d.SR
BPM = 120.0
BARS = 8
N = int(round(BARS * 4 * 60.0 / BPM * SR))      # 705600
GAME = Path(__file__).resolve().parents[2]
MUSIC = GAME / "audio" / "music"
OUT = MUSIC / "layers"
LOWFISH = GAME.parent / "Low fish Beat Project" / "Samples" / "Recorded"
TARGET = -20.0          # K-weighted RMS over the whole loop, every layer
CEIL = -1.0
# The loop's bass, per bar (measured: chroma + bass peak per bar, see AUDIO.md)
BAR_ROOTS = ["F#", "F#", "E", "E", "E", "E", "F#", "F#"]
ROOT_HZ = {"F#": 184.997, "E": 164.814}
FIFTH_HZ = {"F#": 277.183, "E": 246.942}


def stereo(x):
    return x if x.ndim > 1 and x.shape[1] == 2 else np.repeat(x.reshape(len(x), -1)[:, :1], 2, axis=1)


def k_rms(x):
    m = x.mean(axis=1)
    return d.rms_db(d._kweight(np.concatenate([m, m]), SR)[len(m):])     # circular-ish: warm the filter on a copy


def level(x, name):
    """Gain to TARGET, but never past the peak ceiling (no limiter on loops:
    its gain state would not match across the seam)."""
    lv = k_rms(x)
    pk = d.peak_db(x)
    g = min(TARGET - lv, CEIL - 0.05 - pk)
    y = x * d.undb(g)
    print(f"  {name:11s} level {lv:6.2f} -> {k_rms(y):6.2f} dB K-RMS, peak {d.peak_db(y):6.2f} dBFS (gain {g:+.2f})"
          + ("  [peak-limited: quieter than target]" if g < TARGET - lv - 0.05 else ""))
    return y


def seam(x):
    """Discontinuity at the loop point relative to typical sample steps."""
    jump = np.abs(x[0] - x[-1]).max()
    typ = np.percentile(np.abs(np.diff(x, axis=0)), 99)
    return float(jump), float(typ)


# ------------------------------------------------------------------ the BlackWhite loop

def clean_loop(x):
    """Cut on the 8-bar line and wrap the reverb tail into the head: when the
    loop repeats, the tail would have rung over the next bar 1 anyway."""
    y = x[:N].copy()
    tail = x[N:]
    y[: len(tail)] += tail
    return y


def hpss(x, n=2048, hop=512, kh=17, kp=17, power=2.0):
    """Harmonic/percussive split (Fitzgerald 2010) on a loop, circularly."""
    pad = n * 4
    xx = np.concatenate([x[-pad:], x, x[:pad]], axis=0)
    harm = np.zeros_like(xx)
    perc = np.zeros_like(xx)
    for c in range(x.shape[1]):
        f, t, Z = signal.stft(xx[:, c], SR, nperseg=n, noverlap=n - hop)
        S = np.abs(Z)
        H = median_filter(S, size=(1, kh), mode="wrap")
        P = median_filter(S, size=(kp, 1), mode="nearest")
        Mh = H ** power / (H ** power + P ** power + 1e-12)
        Mp = 1.0 - Mh
        _, h = signal.istft(Z * Mh, SR, nperseg=n, noverlap=n - hop)
        _, p = signal.istft(Z * Mp, SR, nperseg=n, noverlap=n - hop)
        harm[:, c] = h[: len(xx)]
        perc[:, c] = p[: len(xx)]
    return harm[pad: pad + N], perc[pad: pad + N]


# ------------------------------------------------------------------ drums

def grid_onsets(x, bpm, bars):
    """Onset times and their deviation from the 16th grid (ms)."""
    t, fl = d.onset_flux(x.mean(axis=1))
    pk, _ = d.peaks(t, fl, thr_rel=0.25, min_gap=0.05)
    s = 60.0 / bpm / 4
    dev = (pk / s - np.round(pk / s)) * s * 1000
    return pk, dev


def stretch_drums(x, bpm_in, bpm_out, slices, method="anchored"):
    s_in = 60.0 / bpm_in / 4 * SR
    s_out = 60.0 / bpm_out / 4 * SR
    if method == "anchored":
        a_in = np.round(np.arange(slices + 1) * s_in).astype(int)
        a_out = np.round(np.arange(slices + 1) * s_out).astype(int)
        # loop-safe: let the last segment read into a copy of the head
        xx = np.concatenate([x, x[: 4096]], axis=0)
        return d.wsola_anchored(xx, a_in, a_out)
    y = d.wsola(x[: int(round(slices * s_in))], s_out / s_in)
    return y[: int(round(slices * s_out))]


def end_fade(x, ms=2.0):
    k = int(ms / 1000 * SR)
    y = x.copy()
    y[-k:] *= np.linspace(1, 0, k)[:, None] ** 2
    return y


def wrap_overhang(y, n):
    """Anything past n (the last slice's ring-out) folds onto the head."""
    out = y[:n].copy()
    if len(y) > n:
        out[: len(y) - n] += y[n:]
    return out


# ------------------------------------------------------------------ voice pad

def yin(fr, fmin=70.0, fmax=400.0):
    W = len(fr) // 2
    lo, hi = int(SR / fmax), int(SR / fmin)
    taus = np.arange(lo, hi)
    dd = np.array([np.sum((fr[:W] - fr[t:t + W]) ** 2) for t in taus])
    cm = dd / (np.cumsum(dd) / np.arange(1, len(dd) + 1) + 1e-12)
    i = int(np.argmin(cm))
    # parabolic refinement
    if 0 < i < len(cm) - 1:
        a, b, c = cm[i - 1], cm[i], cm[i + 1]
        off = 0.5 * (a - c) / (a - 2 * b + c + 1e-12)
    else:
        off = 0.0
    return SR / (taus[i] + off), float(cm[i])


def voice_pool():
    """Voiced, steady 20 ms frames from the Low fish takes: (signal, start, f0)."""
    pool = []
    srcs = []
    for f in sorted(LOWFISH.glob("*.wav")):
        sr, x = d.load(f)
        m = x.mean(axis=1)
        if sr != SR:
            m = signal.resample_poly(m, SR, sr)
        m = d.filt(m, "high", 80, 2)
        srcs.append(m)
        hop = int(0.02 * SR)
        frames = []
        for s in range(0, len(m) - 2048, hop):
            fr = m[s:s + 2048]
            r = np.sqrt(np.mean(fr ** 2))
            if r < 0.006:
                frames.append(None)
                continue
            p, c = yin(fr)
            frames.append((s, p) if c < 0.15 else None)
        for i in range(2, len(frames) - 2):
            win = frames[i - 2:i + 3]
            if any(w is None for w in win):
                continue
            ps = np.array([w[1] for w in win])
            if ps.max() / ps.min() < 1.04:          # steady within ~0.7 semitone over 100 ms
                pool.append((len(srcs) - 1, frames[i][0], float(np.median(ps))))
    return srcs, pool


def voice_pad(rng):
    srcs, pool = voice_pool()
    if len(pool) < 20:
        print("  voice_pad: not enough steady voiced material; layer skipped")
        return None, {"grains_pool": len(pool)}
    out = np.zeros((N, 2))
    bar = N // BARS
    for voice, (table, gain) in enumerate([(ROOT_HZ, 1.0), (FIFTH_HZ, 0.55)]):
        t = 0.0
        while t < N / SR:
            L = int(rng.uniform(0.07, 0.12) * SR)
            centre = int(t * SR + L / 2) % N
            root = BAR_ROOTS[min(centre // bar, BARS - 1)]
            target = table[root] * 2 ** (rng.normal(0, 8) / 1200)        # a few cents of chorus
            si, s0, f0 = pool[rng.integers(len(pool))]
            ratio = target / f0
            src = srcs[si]
            need = int(L * ratio) + 2
            if s0 + need >= len(src):
                t += 0.5 / 60
                continue
            seg = src[s0:s0 + need]
            g = np.interp(np.arange(L) * ratio, np.arange(len(seg)), seg) * np.hanning(L)
            pan = rng.uniform(0.2, 0.8)
            idx = (int(t * SR) + np.arange(L)) % N                         # circular: grains wrap the seam
            out[idx, 0] += gain * g * np.sqrt(1 - pan)
            out[idx, 1] += gain * g * np.sqrt(pan)
            t += rng.uniform(0.6, 1.4) / 55.0                              # ~55 grains/s per voice
    out = d.filt_circular(out, "band", [110, 3200], 2)
    # a long, dark, circular room so the pad breathes across the seam
    ir = d.reverb_ir(3.0, rng, 1.1, lp=3000, stereo=True)
    wet = np.zeros_like(out)
    for c in range(2):
        wet[:, c] = np.fft.irfft(np.fft.rfft(out[:, c]) * np.fft.rfft(ir[:, c], n=N), n=N)   # circular
    y = 0.45 * out + 0.9 * wet / (np.abs(wet).max() + 1e-9) * np.abs(out).max()
    return y, {"grains_pool": len(pool), "pool_seconds": round(len(pool) * 0.02, 2)}


# ------------------------------------------------------------------ tempo sets

def stretch_loop(x, n_out, kind="tonal"):
    """Pitch-preserving stretch of a loop to exactly n_out samples, done on
    three copies so the seam is stretched like any other point."""
    n = len(x)
    xx = np.concatenate([x, x, x], axis=0)
    if kind == "drums":
        k = np.arange(3 * 128 + 1)
        a_in = np.round(k * n / 128).astype(int)
        a_out = np.round(k * n_out / 128).astype(int)
        y = d.wsola_anchored(np.concatenate([xx, x[:4096]], axis=0), a_in, a_out)
    else:
        y = d.wsola(xx, n_out / n, frame=2048, tol=512)
    y = np.concatenate([y, np.zeros((max(0, 3 * n_out - len(y)), x.shape[1]))])
    return seam_join(y, n_out, 2048 if kind != "drums" else 64)


def seam_join(y, n, xf):
    """Middle copy of a 3-copy render, with its head crossfaded into what
    actually followed its end (the third copy). WSOLA drifts by up to its
    tolerance, so the plain middle would not meet itself at the seam."""
    out = y[n:2 * n].copy()
    w = np.sin(np.linspace(0, np.pi / 2, xf)) ** 2
    out[:xf] = y[n:n + xf] * w[:, None] + y[2 * n:2 * n + xf] * (1 - w[:, None])
    return out


def octave_up(x):
    """+12 semitones, same length: stretch x2 (WSOLA) then decimate by 2."""
    n = len(x)
    xx = np.concatenate([x, x, x], axis=0)
    y = d.wsola(xx, 2.0, frame=2048, tol=512)
    y = signal.resample_poly(y, 1, 2, axis=0)
    y = np.concatenate([y, np.zeros((max(0, 3 * n - len(y)), x.shape[1]))])
    return seam_join(y, n, 2048)


def chroma_peak(x):
    Sx = np.abs(np.fft.rfft(x.mean(axis=1))) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    ch = np.zeros(12)
    sel = (f > 50) & (f < 2000)
    np.add.at(ch, (np.round(12 * np.log2(f[sel] / 261.63)) % 12).astype(int), Sx[sel])
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return names[int(np.argmax(ch))], round(float(np.sum(f * Sx) / np.sum(Sx)), 0)


# ------------------------------------------------------------------ main

SETS = {
    # set: (samples for 8 bars, layers in the set)
    "main": (N, ["full", "bright", "calm", "air", "drums", "drums_top", "drums_half", "voice_pad"]),  # 120 BPM
    "slow": (830000, ["full", "bright", "calm", "voice_pad"]),                                # 102.0 BPM: roster, rest
    # author 10/4: "when battle starts it's a little too fast. Drop the BPM a bit" -> 108 BPM
    "battle": (784000, ["full", "bright", "air", "drums", "drums_top", "voice_pad"]),         # 108.0 BPM: combat
    "boss": (640000, ["full", "bright", "calm", "air", "drums", "drums_top", "voice_pad"]),   # 132.3 BPM
}


def main() -> int:
    rng = np.random.default_rng(1206)
    OUT.mkdir(parents=True, exist_ok=True)
    info = {"bars": BARS, "sample_rate": SR, "sets": {}, "analysis": {}}

    sr, bw = d.load(MUSIC / "blackwhite_loop.wav")
    assert sr == SR
    bw = stereo(bw)
    print(f"blackwhite_loop: {len(bw)} samples ({len(bw) / SR:.3f} s); bar line at {N}; tail {len(bw) - N} samples")
    full = clean_loop(bw)
    j_raw = np.abs(bw[N - 1] - bw[0]).max()
    j, typ = seam(full)
    print(f"  seam: hard cut would jump {j_raw:.4f}; wrapped jump {j:.4f} (99th pct sample step {typ:.4f})")
    S = np.abs(np.fft.rfft(full.mean(axis=1))) ** 2
    fr = np.fft.rfftfreq(N, 1 / SR)
    bands = {f"{a}-{b}": round(10 * np.log10(S[(fr >= a) & (fr < b)].sum() / S.sum() + 1e-15), 1)
             for a, b in [(20, 150), (150, 300), (300, 600), (600, 1200), (1200, 2400), (2400, 22050)]}
    print("  energy by band (dB of total):", bands)
    info["analysis"]["blackwhite_seam"] = {"hard_cut_jump": round(float(j_raw), 4), "wrapped_jump": round(j, 5)}

    harm, perc = hpss(full)
    e_h, e_p = d.rms_db(harm), d.rms_db(perc)
    t, fl = d.onset_flux(perc.mean(axis=1))
    pk, _ = d.peaks(t, fl, thr_rel=0.3, min_gap=0.08)
    dev = np.abs((pk / 0.125 - np.round(pk / 0.125)) * 125.0)
    print(f"  HPSS: percussive part is {e_p - e_h:+.1f} dB under the harmonic part; its {len(pk)} onsets sit "
          f"{dev.mean():.0f} ms (mean) off the 16th grid (uniformly random would be ~31): not a beat, no perc layer ships")
    info["analysis"]["blackwhite_bands_db"] = bands
    info["analysis"]["hpss"] = {"perc_vs_harm_db": round(e_p - e_h, 1), "perc_onsets": len(pk),
                                "perc_grid_dev_ms_mean": round(float(dev.mean()), 1), "shipped": False}

    calm = d.filt_circular(harm, "low", 420, 2)
    # author 10/4: "the music is a little depressing, we may be able to up it an
    # octave". The whole loop +12 semitones (tempo kept), with a gentle low cut
    # so the doubled bass doesn't mud the original underneath it.
    bright = d.filt_circular(octave_up(full), "high", 160, 2)
    shimmer = octave_up(harm)
    air = d.filt_circular(shimmer, "high", 500, 2)
    hp_plain = d.rms_db(d.filt_circular(full, "high", 2500, 2))
    print(f"  air: a plain 2.5 kHz high-pass would be {hp_plain:.1f} dB RMS (nothing there), so air = the harmonic "
          f"part an octave up, high-passed at 500 Hz ({d.rms_db(air):.1f} dB RMS before levelling)")
    info["analysis"]["air_plain_highpass_rms_db"] = round(hp_plain, 1)

    sr, drum = d.load(MUSIC / "drum_beat.wav")
    drum = stereo(drum)
    print(f"drum_beat: {len(drum)} samples ({len(drum) / SR:.3f} s) at 90 BPM")
    d_anch = wrap_overhang(stretch_drums(drum, 90, 120, 128, "anchored"), N)
    d_glob = stretch_drums(drum, 90, 120, 128, "global")
    d_glob = np.concatenate([d_glob, np.zeros((max(0, N - len(d_glob)), 2))])[:N]
    o_src, dev_src = grid_onsets(drum, 90, 8)
    o_a, dev_a = grid_onsets(d_anch, 120, 8)
    o_g, dev_g = grid_onsets(d_glob, 120, 8)
    cmp = {
        "source_90": {"onsets": len(o_src), "grid_dev_ms_mean_abs": round(float(np.mean(np.abs(dev_src))), 2), "chroma_centroid": chroma_peak(drum)},
        "wsola_anchored": {"onsets": len(o_a), "grid_dev_ms_mean_abs": round(float(np.mean(np.abs(dev_a))), 2), "chroma_centroid": chroma_peak(d_anch)},
        "wsola_global": {"onsets": len(o_g), "grid_dev_ms_mean_abs": round(float(np.mean(np.abs(dev_g))), 2), "chroma_centroid": chroma_peak(d_glob)},
    }
    print("  stretch comparison:", json.dumps(cmp))
    info["analysis"]["drum_stretch"] = cmp
    # The Low fish render starts from silence but ends mid-ring (the source file's
    # own loop point jumps 0.075): a 2 ms fade into the downbeat hides that step.
    drums = end_fade(d_anch)
    drums_top = d.filt_circular(drums, "high", 5000, 2)

    half_src = drum[: int(round(4 * 4 * 60 / 90 * SR))]
    halfx = np.concatenate([half_src, half_src[:4096]], axis=0)
    a_in = np.round(np.arange(65) * (60 / 90 / 4 * SR)).astype(int)
    a_out = np.round(np.arange(65) * (60 / 120 / 2 * SR)).astype(int)     # a 16th lasts an 8th: half-time
    drums_half = end_fade(wrap_overhang(d.wsola_anchored(halfx, a_in, a_out), N))

    pad, pad_info = voice_pad(rng)
    info["analysis"]["voice_pad"] = pad_info

    main_layers = {
        "full": (full, "BlackWhite loop, cut on the 8-bar line, reverb tail wrapped into the head"),
        "bright": (bright, "the whole loop an octave up (WSOLA x2 + decimate), low-cut at 160 Hz: the lighter voicing"),
        "calm": (calm, "harmonic part of full (HPSS), low-passed at 420 Hz: no attacks, softer"),
        "air": (air, "harmonic part an octave up (WSOLA x2 + decimate), high-passed at 500 Hz: a shimmer"),
        "drums": (drums, "drum_beat 90->120 BPM, pitch kept: WSOLA anchored on every 16th"),
        "drums_top": (drums_top, "drums high-passed at 5 kHz: hats and shakers only"),
        "drums_half": (drums_half, "drum_beat bars 1-4 at half-time (each 16th stretched to an 8th, WSOLA anchored)"),
        "voice_pad": (pad, "granular pad from the Low fish voice takes, root + fifth on the loop's bass"),
    }
    print("levels:")
    for set_name, (n_set, names) in SETS.items():
        folder = OUT if set_name == "main" else OUT / set_name
        bpm = 120.0 * N / n_set
        entry = {"samples": n_set, "seconds": round(n_set / SR, 6), "bpm": round(bpm, 3),
                 "folder": "" if set_name == "main" else set_name, "layers": {}}
        for name in names:
            src, what = main_layers[name]
            if src is None:
                continue
            x = src if set_name == "main" else stretch_loop(src, n_set, "drums" if name.startswith("drums") else "tonal")
            assert len(x) == n_set, (set_name, name, len(x))
            y = level(x, f"{set_name}/{name}")
            jmp, typ = seam(y)
            d.save(folder / f"{name}.wav", y)
            entry["layers"][name] = {"file": (entry["folder"] + "/" if entry["folder"] else "") + f"{name}.wav",
                                     "what": what if set_name == "main" else f"{name} re-timed to {bpm:.1f} BPM (WSOLA)",
                                     "k_rms_db": round(k_rms(y), 2), "peak_db": round(d.peak_db(y), 2),
                                     "seam_jump": round(jmp, 5), "step_p99": round(typ, 5)}
            if set_name != "main":
                entry["layers"][name]["chroma_centroid"] = chroma_peak(y)
        info["sets"][set_name] = entry
    info["bar_roots"] = BAR_ROOTS
    info["main_chroma_centroid"] = {k: chroma_peak(v[0]) for k, v in main_layers.items() if v[0] is not None}
    (OUT / "layers.json").write_text(json.dumps(info, indent=1))
    print(f"wrote {sum(len(s['layers']) for s in info['sets'].values())} layers to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
