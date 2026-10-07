"""Procedural SFX for Black | White (Phase 6). Deterministic: the same
script always writes the same files.

    python game/tools/audio/make_sfx.py            # writes game/audio/sfx/*.wav + sfx.json
    python game/tools/audio/make_sfx.py --only hit  # names containing "hit"

Style: clean, punchy, slightly stylised foley-ish synthesis for a
black-and-white stick-figure game. Not chiptune: everything is built from
filtered noise, damped modes (wood, metal, glass, bells), pitched sweeps
and a little saturation, then levelled to a common loudness.

Every sound has 2-6 variations, named <name>_<n>.wav (n from 1). The
manifest sfx.json lists each name, its variation count, its loop flag and
the measured levels; the game reads it (BWSfx) and the tests check it.
A real recording dropped in under the same filename replaces a variation;
see design/audio/AUDIO.md.
"""
from __future__ import annotations

import argparse
import json
import sys
import zlib
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bwdsp as d  # noqa: E402

SR = d.SR
GAME = Path(__file__).resolve().parents[2]
OUT = GAME / "audio" / "sfx"
TARGET = -16.0          # momentary K-weighted RMS, "LUFS-ish"
CEIL = -1.0             # dBFS true-ish peak ceiling

# equal temperament helper (A4 = 440); the score sits in F# minor / A major
NOTE = {n: 440.0 * 2 ** ((i - 9) / 12) for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def hz(name: str, octave: int) -> float:
    return NOTE[name] * 2 ** (octave - 4)


# ------------------------------------------------------------------ building blocks

def noise(rng, n):
    return rng.standard_normal(n)


def burst(rng, dur, lo, hi, decay, attack=0.0005):
    t = d.t_axis(dur)
    x = d.filt(noise(rng, len(t)), "band", [lo, hi], 2)
    return x / (np.std(x) + 1e-9) * d.env_ad(t, attack, decay)


def thump(dur, f0, f1, tau, decay, attack=0.001):
    t = d.t_axis(dur)
    return d.chirp_sine(t, f0, f1, tau) * d.env_ad(t, attack, decay)


def click(rng, dur=0.004, hp=2500.0):
    t = d.t_axis(dur)
    x = d.filt(noise(rng, len(t)), "high", hp, 2)
    return x * np.exp(-t / (dur / 4))


def whoosh(rng, dur, f_lo, f_peak, f_end, peak, q=0.55, colour=-1.0, rise=1.6, fall=2.2):
    t = d.t_axis(dur)
    n = len(t)
    p = peak / dur

    def fc(u):
        if u < p:
            return f_lo * (f_peak / f_lo) ** (u / p)
        return f_peak * (f_end / f_peak) ** ((u - p) / max(1 - p, 1e-6))

    x = d.sweep_noise(n, rng, fc, lambda u: q, colour=colour)
    return x * d.env_swell(t, peak, rise, fall)


def sat(x, drive=1.5):
    return np.tanh(drive * x) / np.tanh(drive)


def pluck(f, dur, bright=1.5, decay=0.25, harmonics=8, rng=None):
    t = d.t_axis(dur)
    y = np.zeros_like(t)
    for k in range(1, harmonics + 1):
        y += (1.0 / k ** bright) * np.sin(2 * np.pi * f * k * t) * np.exp(-t * k ** 0.7 / decay)
    return y * d.env_ad(t, 0.002, 10.0)


def bell(f, dur, decay=1.0, rng=None, bright=1.0):
    t = d.t_axis(dur)
    ratios = [1.0, 2.0, 2.76, 4.07, 5.4]
    amps = [1.0, 0.45 * bright, 0.32 * bright, 0.16 * bright, 0.1 * bright]
    decs = [decay, decay * 0.6, decay * 0.4, decay * 0.25, decay * 0.15]
    y = d.modal(t, [f * r for r in ratios], decs, amps, rng)
    return y * d.env_ad(t, 0.001, 50.0)


def karplus(rng, f, dur, decay=0.996, bright=0.5):
    n = int(dur * SR)
    p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p)
    buf = d.filt(buf, "low", 2000 + 6000 * bright, 1)
    y = np.zeros(n)
    for i in range(n):
        v = buf[i % p]
        y[i] = v
        buf[i % p] = decay * 0.5 * (v + buf[(i + 1) % p])
    return y


def stereo(l, r):
    n = max(len(l), len(r))
    out = np.zeros((n, 2))
    out[: len(l), 0] = l
    out[: len(r), 1] = r
    return out


def jit(rng, v, pct):
    return v * (1.0 + rng.uniform(-pct, pct))


# ------------------------------------------------------------------ weapons

def swing_light(rng, v):
    dur = jit(rng, 0.30, 0.12)
    peak = jit(rng, 0.10, 0.15)
    y = whoosh(rng, dur, jit(rng, 650, 0.2), jit(rng, 2600, 0.2), jit(rng, 1100, 0.2), peak, q=0.45, colour=-0.5)
    y += 0.35 * whoosh(rng, dur, 1500, jit(rng, 3800, 0.15), 2000, peak, q=0.08, colour=0.0)   # blade edge whistle
    return y


def swing_heavy(rng, v):
    dur = jit(rng, 0.46, 0.1)
    peak = jit(rng, 0.17, 0.12)
    y = whoosh(rng, dur, jit(rng, 220, 0.2), jit(rng, 900, 0.2), jit(rng, 380, 0.2), peak, q=0.7, colour=-2.0)
    y += 0.6 * whoosh(rng, dur, 90, 190, 110, peak, q=0.6, colour=-3.0)                        # body of the weight
    return y


def swing_axe(rng, v):
    dur = jit(rng, 0.40, 0.1)
    peak = jit(rng, 0.15, 0.12)
    t = d.t_axis(dur)
    y = whoosh(rng, dur, jit(rng, 320, 0.2), jit(rng, 1300, 0.2), 520, peak, q=0.6, colour=-1.5)
    tumble = 0.55 + 0.45 * np.sin(2 * np.pi * jit(rng, 24, 0.2) * t + rng.uniform(0, 6)) ** 2   # the head chopping air
    return y * tumble


def hit_flesh(rng, v):
    dur = 0.35
    y = 1.0 * thump(dur, jit(rng, 170, 0.15), jit(rng, 55, 0.1), 0.03, jit(rng, 0.09, 0.2))
    y += 0.55 * burst(rng, dur, 120, jit(rng, 1300, 0.2), 0.03)
    y += 0.35 * burst(rng, dur, 500, 1400, 0.018)                         # the slap
    d.place(y, 0.3 * click(rng, 0.004, 3000), 0.0)
    return sat(y / np.abs(y).max(), 1.8)


def hit_crit(rng, v):
    dur = 1.1
    t = d.t_axis(dur)
    y = 1.0 * thump(dur, jit(rng, 140, 0.1), 38, 0.04, 0.2)
    y += 0.7 * burst(rng, dur, 100, 2400, 0.07)
    y += 0.4 * burst(rng, dur, 2500, 9000, 0.02)                           # crack
    f0 = jit(rng, 600, 0.12)
    ring = d.modal(t, [f0, f0 * 2.76, f0 * 5.4, f0 * 8.93], [0.55, 0.3, 0.14, 0.07], [0.5, 0.3, 0.18, 0.08], rng)
    y += 0.55 * ring * d.env_ad(t, 0.004, 20)
    return sat(y / np.abs(y).max(), 2.0)


def hit_glance(rng, v):
    dur = 0.38
    t = d.t_axis(dur)
    rate = jit(rng, 150, 0.25)
    ph = np.cumsum(rate * (1 + 0.3 * rng.standard_normal(len(t)) * 0.1)) / SR
    am = 0.4 + 0.6 * (np.sin(2 * np.pi * ph) > 0.2)                      # stick-slip
    y = burst(rng, dur, jit(rng, 1800, 0.15), jit(rng, 5200, 0.1), 0.12, attack=0.01) * am
    y += 0.25 * d.modal(t, [jit(rng, 2100, 0.1), 3400], [0.06, 0.04], [1, 0.6], rng)
    y += 0.3 * thump(dur, 200, 90, 0.02, 0.03)
    return y


def hit_block(rng, v):
    dur = 0.85
    t = d.t_axis(dur)
    f0 = jit(rng, 470, 0.15)
    ratios = [1.0, 1.58, 2.37, 3.11, 4.2, 5.73]
    y = d.modal(t, [f0 * r for r in ratios], [0.32, 0.22, 0.16, 0.1, 0.07, 0.05], [1, 0.7, 0.55, 0.4, 0.3, 0.2], rng)
    y += 1.4 * burst(rng, dur, 1500, 8000, 0.008)
    y += 0.8 * thump(dur, 160, 80, 0.02, 0.05)
    return sat(y / np.abs(y).max(), 1.6)


def hit_miss(rng, v):
    dur = jit(rng, 0.2, 0.15)
    return whoosh(rng, dur, 1400, jit(rng, 4200, 0.15), 2600, dur * 0.35, q=0.35, colour=0.5, rise=1.2, fall=3.0)


def bow_draw(rng, v):
    dur = 0.62
    t = d.t_axis(dur)
    y = np.zeros(len(t))
    pos = 0.02
    while pos < dur - 0.03:
        u = pos / dur
        rate = 30 + 70 * u ** 1.5
        amp = 0.4 + 0.6 * np.sin(np.pi * min(u * 1.2, 1.0))
        imp = d.modal(d.t_axis(0.03), [jit(rng, 310, 0.05), jit(rng, 730, 0.05), jit(rng, 1180, 0.05), 1950],
                      [0.012, 0.009, 0.006, 0.004], [1, 0.8, 0.5, 0.3], rng)
        d.place(y, amp * rng.uniform(0.6, 1.0) * imp, pos)
        pos += (1.0 / rate) * rng.uniform(0.7, 1.3)
    squeak = whoosh(rng, dur, 1900, 2600, 2900, dur * 0.8, q=0.06, colour=0.0)
    return y + 0.25 * squeak


def bow_release(rng, v):
    dur = 0.55
    t = d.t_axis(dur)
    f = jit(rng, 118, 0.12)
    s = karplus(rng, f, dur, 0.992, 0.4)
    s *= d.env_ad(t, 0.0005, 0.12)
    y = 0.9 * s / (np.abs(s).max() + 1e-9)
    y += 0.7 * burst(rng, dur, 900, 4500, 0.025)                          # thwip
    y += 0.5 * thump(dur, 260, 140, 0.01, 0.03)                            # limb slap
    return y


def arrow_thunk(rng, v):
    dur = 0.5
    t = d.t_axis(dur)
    y = thump(dur, jit(rng, 320, 0.1), 120, 0.012, 0.035)
    y += 0.5 * d.modal(t, [jit(rng, 430, 0.1), 990, 1650], [0.04, 0.03, 0.02], [1, 0.6, 0.4], rng)
    y += 0.4 * burst(rng, dur, 1500, 5000, 0.006)                           # the tip bites
    wob = 0.5 + 0.5 * np.sin(2 * np.pi * jit(rng, 42, 0.15) * t)               # the shaft quivers
    y += 0.35 * burst(rng, dur, 250, 900, 0.16, attack=0.01) * wob
    return y


def pistol_shot(rng, v):
    dur = 1.3
    t = d.t_axis(dur)
    y = np.zeros(len(t))
    nw = np.concatenate([np.linspace(0, 1, 8), np.linspace(1, -0.8, 30), np.linspace(-0.8, 0, 40)])  # N-wave crack
    d.place(y, 1.0 * nw, 0.0)
    y += 1.0 * burst(rng, dur, 300, 9000, 0.012)
    y += 0.8 * burst(rng, dur, 100, 2500, 0.045)
    y += 0.9 * thump(dur, jit(rng, 130, 0.1), 48, 0.02, 0.12)
    tail = burst(rng, dur, 200, 3000, 0.35, attack=0.02) * 0.18
    y = sat(y / np.abs(y).max(), 2.2) + tail
    ir = d.reverb_ir(0.8, rng, 0.22, lp=4000)
    return d.convolve(y, ir, 0.12, keep_len=True)


def flintlock_shot(rng, v):
    dur = 1.8
    t = d.t_axis(dur)
    y = np.zeros(len(t))
    d.place(y, 0.6 * click(rng, 0.004, 2500), 0.0)                         # flint strikes
    d.place(y, 0.35 * burst(rng, 0.09, 2500, 7000, 0.05, attack=0.01), 0.004)   # the pan flashes
    main = np.zeros(int(1.6 * SR))
    main += 1.0 * burst(rng, 1.6, 200, 7000, 0.016)
    main += 0.9 * burst(rng, 1.6, 80, 1800, 0.07)
    main += 1.0 * thump(1.6, jit(rng, 105, 0.1), 36, 0.03, 0.2)
    main = sat(main / np.abs(main).max(), 2.0)
    main += 0.22 * burst(rng, 1.6, 1200, 6000, 0.4, attack=0.03)           # smoke hiss
    d.place(y, main, jit(rng, 0.085, 0.15))
    ir = d.reverb_ir(1.0, rng, 0.3, lp=3500)
    return d.convolve(y, ir, 0.14, keep_len=True)


def cast_whoom(rng, v):
    dur = 0.75
    t = d.t_axis(dur)
    peak = 0.13
    y = whoosh(rng, dur, 140, jit(rng, 900, 0.2), 260, peak, q=0.5, colour=-1.5, rise=1.3, fall=1.4)
    sub = d.chirp_sine(t, 50, jit(rng, 85, 0.1), 0.08) * d.env_swell(t, peak, 1.5, 1.5)
    tone = sum(np.sin(2 * np.pi * jit(rng, 220, 0.004) * k * t + rng.uniform(0, 6)) / k for k in (1, 2, 3))
    y += 0.8 * sub + 0.18 * tone * d.env_swell(t, peak * 1.2, 1.5, 1.2)
    return y


def bolt_fizz(rng, v):
    dur = 0.55
    t = d.t_axis(dur)
    hiss = d.filt(noise(rng, len(t)), "band", [2800, 7500], 2)
    grains = (rng.uniform(0, 1, len(t)) < 0.004).astype(float)
    grains = d.filt(grains, "low", 200, 1)                                  # crackle density envelope
    am = 0.35 + np.clip(grains * 60, 0, 1.2)
    y = hiss / np.std(hiss) * am * d.env_swell(t, 0.04, 1.0, 1.4)
    f = 600 * (1 + 1.3 * t / dur) * (1 + 0.04 * np.sin(2 * np.pi * 18 * t))
    y += 0.4 * np.sin(2 * np.pi * np.cumsum(f) / SR) * d.env_swell(t, 0.05, 1.0, 1.8)
    return y


def channel_loop(rng, v):
    """2.0 s seamless loop: every partial is a multiple of 0.5 Hz, the noise
    bed is wrapped tail-into-head."""
    dur = 2.0
    t = d.t_axis(dur)
    base = [110.0, 110.5, 165.0, 220.5] if v == 1 else [98.0, 98.5, 147.0, 196.5]
    y = sum(a * np.sin(2 * np.pi * f * t) for f, a in zip(base, [1.0, 0.8, 0.45, 0.3]))
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 4.0 * t)
    n = len(t)
    xf = int(0.25 * SR)
    bed = d.filt(noise(rng, n + xf), "band", [500, 1400], 2)
    bed = bed / np.std(bed)
    w = np.linspace(0, 1, xf)
    looped = bed[:n].copy()
    looped[:xf] = bed[:xf] * w + bed[n:n + xf] * (1 - w)
    return (0.6 * y * trem + 0.25 * looped) * 0.5


# ------------------------------------------------------------------ elements

def elem_fire(rng, v):
    dur = 0.75
    t = d.t_axis(dur)
    y = whoosh(rng, dur, 250, jit(rng, 1400, 0.2), 500, 0.07, q=0.9, colour=-2.0, rise=1.0, fall=1.8)   # whoomph
    for _ in range(int(jit(rng, 34, 0.2))):
        at = rng.exponential(0.16)
        if at < dur - 0.01:
            d.place(y, rng.exponential(0.6) * click(rng, rng.uniform(0.001, 0.004), rng.uniform(1500, 4000)), at)
    y += 0.4 * burst(rng, dur, 300, 900, 0.25, attack=0.02)
    return y


def elem_water(rng, v):
    dur = 0.65
    t = d.t_axis(dur)
    y = 1.0 * burst(rng, dur, 700, 3500, 0.06, attack=0.002)
    y += 0.6 * thump(dur, 200, 360, 0.04, 0.05) * 0.6                       # the bloop
    for _ in range(int(jit(rng, 24, 0.25))):
        at = 0.02 + rng.exponential(0.12)
        if at < dur - 0.03:
            f0 = rng.uniform(700, 1900)
            dt = d.t_axis(0.03)
            drop = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.8 * dt / 0.03)) / SR) * np.exp(-dt / 0.008)
            d.place(y, rng.uniform(0.15, 0.5) * drop, at)
    return y


def elem_ice(rng, v):
    dur = 0.85
    t = d.t_axis(dur)
    y = 1.2 * burst(rng, dur, 3000, 11000, 0.008)
    y += 0.4 * burst(rng, dur, 2500, 6000, 0.08)
    for _ in range(int(jit(rng, 32, 0.2))):
        at = rng.exponential(0.12)
        if at < dur - 0.13:
            f = rng.uniform(2500, 7000)
            dt = d.t_axis(0.13)
            ping = d.modal(dt, [f, f * 1.53], [rng.uniform(0.03, 0.11), 0.03], [1, 0.4], rng)
            d.place(y, rng.exponential(0.25) * ping, at)
    y += 0.5 * thump(dur, 260, 120, 0.01, 0.03)
    return y


def elem_thunder(rng, v):
    dur = 0.6
    t = d.t_axis(dur)
    f = jit(rng, 95, 0.2) * (1 + 0.08 * d.filt(noise(rng, len(t)), "low", 30, 1) * 20)
    saw = 2 * ((np.cumsum(f) / SR) % 1.0) - 1
    gate = d.filt((rng.uniform(0, 1, len(t)) < 0.01).astype(float), "low", 60, 1)
    gate = np.clip(gate / (gate.max() + 1e-9) * 1.6, 0.15, 1.0)
    y = d.filt(saw, "band", [250, 5000], 2) * gate * d.env_ad(t, 0.002, 0.22)
    y += 0.8 * burst(rng, dur, 2000, 10000, 0.01)                            # the snap
    for _ in range(12):
        at = rng.uniform(0, dur * 0.7)
        d.place(y, rng.uniform(0.2, 0.7) * click(rng, 0.003, 3000), at)
    return sat(y / np.abs(y).max(), 2.5)


def elem_wind(rng, v):
    dur = jit(rng, 0.85, 0.1)
    t = d.t_axis(dur)
    y = whoosh(rng, dur, 300, jit(rng, 1200, 0.2), 450, 0.1, q=1.0, colour=-1.5, rise=1.0, fall=1.5)
    y *= 0.75 + 0.25 * np.sin(2 * np.pi * jit(rng, 7, 0.2) * t)
    y += 0.3 * whoosh(rng, dur, 1100, jit(rng, 1700, 0.1), 1300, 0.14, q=0.05, colour=0.0)   # whistle
    return y


def elem_dark(rng, v):
    dur = 0.95
    t = d.t_axis(dur)
    y = whoosh(rng, dur, 80, jit(rng, 320, 0.15), 65, 0.07, q=0.7, colour=-3.0, rise=1.2, fall=1.4)
    y += 0.8 * np.sin(2 * np.pi * 46 * t) * d.env_swell(t, 0.09, 1.2, 1.3)
    y *= 0.8 + 0.2 * np.sin(2 * np.pi * 31 * t)                              # a ring-mod shiver
    return y


def elem_light(rng, v):
    dur = 1.4
    notes = [hz("A", 5), hz("C#", 6), hz("E", 6)]
    if v % 2 == 0:
        notes = notes[::-1]
    y = np.zeros(int(dur * SR))
    for i, f in enumerate(notes):
        d.place(y, (0.9 - 0.15 * i) * bell(f, dur - 0.1, 0.8, rng, 0.8), i * jit(rng, 0.045, 0.2))
    y += 0.12 * burst(rng, dur, 6000, 12000, 0.4, attack=0.03)
    return y


def heal(rng, v):
    dur = 1.3
    t = d.t_axis(dur)
    f = hz("A", 4) * (1 + 0.5 * np.clip(t / 0.5, 0, 1) ** 0.6)            # glides up a fifth
    y = np.zeros(len(t))
    for det in (0.997, 1.0, 1.004):
        y += np.sin(2 * np.pi * np.cumsum(f * det) / SR)
        y += 0.3 * np.sin(2 * np.pi * np.cumsum(2 * f * det) / SR)
    y *= d.env_swell(t, 0.45, 1.2, 1.6) * 0.4
    d.place(y, 0.6 * bell(hz("E", 6 if v == 1 else 5), 0.8, 0.5, rng), 0.42)
    y += 0.12 * burst(rng, dur, 6000, 12000, 0.3, attack=0.2)
    return y


# ------------------------------------------------------------------ tiles

def tile_detonate(rng, v):
    dur = 2.0
    t = d.t_axis(dur)
    n = len(t)
    body = d.sweep_noise(n, rng, lambda u: 3500 * (180 / 3500) ** min(u * 4, 1), lambda u: 1.2, colour=-2.0)
    y = body * d.env_ad(t, 0.002, 0.28)
    y += 1.2 * thump(dur, jit(rng, 90, 0.1), 30, 0.06, 0.4)
    for _ in range(10):
        at = rng.uniform(0.0, 0.25)
        d.place(y, rng.uniform(0.3, 0.8) * elem_thunder(rng, v)[: int(0.08 * SR)], at)
    y = sat(y / np.abs(y).max(), 2.2)
    ir = d.reverb_ir(1.4, rng, 0.45, lp=2500)
    return d.convolve(y, ir, 0.2, keep_len=True)


def tile_glaze(rng, v):
    dur = 1.0
    t = d.t_axis(dur)
    y = np.zeros(len(t))
    pos = 0.0
    while pos < 0.6:
        rate = 30 + 400 * (pos / 0.6) ** 2                                   # crystals forming faster
        d.place(y, rng.uniform(0.2, 0.6) * click(rng, 0.002, rng.uniform(3000, 7000)), pos)
        pos += rng.exponential(1.0 / rate)
    groan = np.sin(2 * np.pi * np.cumsum(120 * (1 + 0.05 * np.sin(2 * np.pi * 5 * t))) / SR)
    y += 0.25 * d.filt(sat(groan, 3.0), "band", [200, 1500], 2) * d.env_swell(t, 0.4, 1.5, 2.0)
    pings = np.zeros(len(t))
    d.place(pings, bell(jit(rng, 2800, 0.1), 0.4, 0.15, rng), 0.6)
    return y + 0.6 * pings


def tile_gale(rng, v):
    dur = 1.5
    t = d.t_axis(dur)
    y = whoosh(rng, dur, 220, jit(rng, 1000, 0.15), 380, 0.45, q=1.1, colour=-1.5, rise=1.4, fall=1.4)
    y += 0.7 * whoosh(rng, dur, 300, jit(rng, 1500, 0.15), 500, 0.95, q=0.9, colour=-1.0, rise=2.0, fall=1.2)
    y *= 0.7 + 0.3 * np.sin(2 * np.pi * jit(rng, 5, 0.2) * t)
    return y


# ------------------------------------------------------------------ bodies

def step_stone(rng, v):
    dur = 0.2
    y = 1.0 * thump(dur, jit(rng, 150, 0.15), 75, 0.012, jit(rng, 0.02, 0.2))
    y += 0.6 * burst(rng, dur, jit(rng, 1500, 0.2), 5000, 0.012)
    scuff = burst(rng, 0.06, 2000, 4500, 0.02, attack=0.012)
    d.place(y, rng.uniform(0.2, 0.45) * scuff, jit(rng, 0.035, 0.3))
    return y


def ko_thud(rng, v):
    dur = 1.0
    y = np.zeros(int(dur * SR))
    seat = thump(0.6, jit(rng, 115, 0.1), 42, 0.03, 0.13) + 0.5 * burst(rng, 0.6, 80, 1800, 0.07)
    back = thump(0.6, jit(rng, 100, 0.1), 40, 0.03, 0.1) + 0.6 * burst(rng, 0.6, 100, 2200, 0.08)
    d.place(y, sat(seat, 1.6), 0.0)
    d.place(y, 0.75 * sat(back, 1.6), jit(rng, 0.22, 0.15))
    d.place(y, 0.18 * hit_block(rng, v)[: int(0.4 * SR)], jit(rng, 0.25, 0.1))   # gear rattles
    return y


# ------------------------------------------------------------------ UI

def ui_hover(rng, v):
    t = d.t_axis(0.045)
    f = [2400, 2700, 3000][(v - 1) % 3]
    return np.sin(2 * np.pi * f * t) * np.exp(-t / 0.006) + 0.15 * d.filt(noise(rng, len(t)), "high", 4000, 2) * np.exp(-t / 0.002)


def ui_click(rng, v):
    dur = 0.09
    t = d.t_axis(dur)
    y = np.sin(2 * np.pi * (1800 if v == 1 else 2000) * t) * np.exp(-t / 0.006)
    y += 0.8 * np.sin(2 * np.pi * 420 * t) * np.exp(-t / 0.024)
    return y


def ui_confirm(rng, v):
    a, b = (hz("E", 5), hz("A", 5)) if v == 1 else (hz("A", 5), hz("E", 6))
    y = np.zeros(int(0.42 * SR))
    d.place(y, pluck(a, 0.3, 1.6, 0.12), 0.0)
    d.place(y, pluck(b, 0.34, 1.6, 0.16), 0.07)
    return y


def ui_cancel(rng, v):
    a, b = (hz("E", 5), hz("B", 4)) if v == 1 else (hz("C#", 5), hz("F#", 4))
    y = np.zeros(int(0.38 * SR))
    d.place(y, pluck(a, 0.25, 2.0, 0.08), 0.0)
    d.place(y, pluck(b, 0.3, 2.0, 0.1), 0.075)
    return d.filt(y, "low", 3000, 2)


def ui_pick(rng, v):
    y = np.zeros(int(0.35 * SR))
    d.place(y, 0.7 * thump(0.15, 180, 90, 0.01, 0.03), 0.0)
    d.place(y, pluck(hz("A", 5) if v == 1 else hz("C#", 6), 0.3, 1.4, 0.12), 0.005)
    return y


def ui_turn(rng, v):
    y = np.zeros(int(0.8 * SR))
    first, second = (hz("A", 5), hz("E", 6)) if v == 1 else (hz("E", 5), hz("A", 5))
    d.place(y, bell(first, 0.7, 0.35, rng, 0.7), 0.0)
    d.place(y, 0.8 * bell(second, 0.6, 0.3, rng, 0.7), 0.09)
    return y


def ui_levelup(rng, v):
    notes = [hz("E", 5), hz("G#", 5), hz("B", 5), hz("E", 6)]
    if v == 2:
        notes = [hz("A", 4), hz("C#", 5), hz("E", 5), hz("A", 5)]
    dur = 1.4
    y = np.zeros(int(dur * SR))
    for i, f in enumerate(notes):
        d.place(y, (0.7 + 0.1 * i) * pluck(f, 0.9, 1.3, 0.3), i * 0.065)
    d.place(y, 0.5 * bell(notes[-1] * 2, 1.0, 0.6, rng, 0.6), 0.26)
    y += 0.1 * burst(rng, dur, 6000, 12000, 0.35, attack=0.25)
    return y


def _pad_chord(rng, freqs, dur, cutoff=1800.0, detune=0.004):
    t = d.t_axis(dur)
    out = []
    for ch in range(2):
        y = np.zeros(len(t))
        for f in freqs:
            for det in (1 - detune, 1 + detune * (1.3 if ch else 0.7)):
                ph = rng.uniform(0, 1)
                y += 2 * (((f * det) * t + ph) % 1.0) - 1
        out.append(d.filt(y, "low", cutoff, 2) / len(freqs))
    return np.stack(out, axis=1)


def sting_victory(rng, v):
    dur = 3.2
    n = int(dur * SR)
    y = np.zeros((n, 2))
    arp = [hz("A", 4), hz("C#", 5), hz("E", 5), hz("A", 5)] if v == 1 else [hz("E", 4), hz("A", 4), hz("C#", 5), hz("E", 5)]
    for i, f in enumerate(arp):
        p = pluck(f, 1.6, 1.3, 0.35)
        pan = 0.35 + 0.1 * i
        d.place(y[:, 0], (1 - pan) * p * 1.6, i * 0.11)
        d.place(y[:, 1], pan * p * 1.6, i * 0.11)
    chord = _pad_chord(rng, [hz("A", 3), hz("E", 4), hz("A", 4), hz("C#", 5)], dur - 0.4, 2200)
    t = d.t_axis(dur - 0.4)
    chord *= d.env_swell(t, 0.5, 1.2, 1.4)[:, None] * 0.5
    y[int(0.4 * SR): int(0.4 * SR) + len(chord)] += chord
    b = bell(hz("A", 5), 2.4, 1.0, rng, 0.8)
    d.place(y[:, 0], 0.5 * b, 0.42)
    d.place(y[:, 1], 0.5 * b, 0.43)
    return y


def sting_defeat(rng, v):
    dur = 3.4
    n = int(dur * SR)
    y = np.zeros((n, 2))
    line = [hz("F#", 4), hz("E", 4), hz("D", 4), hz("C#", 4)] if v == 1 else [hz("A", 4), hz("F#", 4), hz("E", 4), hz("C#", 4)]
    for i, f in enumerate(line):
        p = d.filt(pluck(f, 1.2, 2.2, 0.4), "low", 2500, 2)
        d.place(y[:, 0], p, i * 0.24)
        d.place(y[:, 1], p, i * 0.24 + 0.006)
    drone = _pad_chord(rng, [hz("F#", 2), hz("C#", 3), hz("A", 3)], dur - 0.7, 700, 0.006)
    t = d.t_axis(dur - 0.7)
    drone *= d.env_swell(t, 0.9, 1.5, 1.2)[:, None] * 0.9
    y[int(0.7 * SR): int(0.7 * SR) + len(drone)] += drone
    return y


def progress_day(rng, v):
    dur = 5.0
    n = int(dur * SR)
    t = d.t_axis(dur)
    swell = np.stack([d.filt(noise(rng, n), "high", 3500, 2) for _ in range(2)], axis=1)
    swell *= (np.clip(t / 4.2, 0, 1) ** 3 * (t < 4.25) + (t >= 4.25) * np.exp(-(t - 4.25) / 0.05))[:, None] * 0.25
    chord = [hz("A", 3), hz("E", 4), hz("B", 4), hz("C#", 5)] if v == 1 else [hz("F#", 3), hz("C#", 4), hz("E", 4), hz("A", 4)]
    pad = _pad_chord(rng, chord, dur, 900 + 0 * 1, 0.005)
    lp_env = np.clip(t / 4.2, 0, 1)
    bright = _pad_chord(rng, chord, dur, 3200, 0.005)
    pad = pad * (1 - lp_env)[:, None] + bright * lp_env[:, None]
    pad *= (np.clip(t / 4.2, 0, 1) ** 1.6 * (t < 4.25) + (t >= 4.25) * np.exp(-(t - 4.25) / 0.35))[:, None] * 0.6
    y = swell + pad
    b = bell(hz("A", 5) if v == 1 else hz("C#", 6), 0.75, 0.6, rng, 0.8)
    d.place(y[:, 0], 0.6 * b, 4.25)
    d.place(y[:, 1], 0.6 * b, 4.255)
    return y


# ------------------------------------------------------------------ registry
# name: (generator, variations, bus, loop)
SOUNDS = {
    "swing_light": (swing_light, 4, "SFX", False),
    "swing_heavy": (swing_heavy, 3, "SFX", False),
    "swing_axe": (swing_axe, 3, "SFX", False),
    "hit_flesh": (hit_flesh, 4, "SFX", False),
    "hit_crit": (hit_crit, 3, "SFX", False),
    "hit_glance": (hit_glance, 3, "SFX", False),
    "hit_block": (hit_block, 3, "SFX", False),
    "hit_miss": (hit_miss, 3, "SFX", False),
    "bow_draw": (bow_draw, 2, "SFX", False),
    "bow_release": (bow_release, 3, "SFX", False),
    "arrow_thunk": (arrow_thunk, 3, "SFX", False),
    "pistol_shot": (pistol_shot, 3, "SFX", False),
    "flintlock_shot": (flintlock_shot, 2, "SFX", False),
    "cast_whoom": (cast_whoom, 3, "SFX", False),
    "bolt_fizz": (bolt_fizz, 3, "SFX", False),
    "channel_loop": (channel_loop, 2, "SFX", True),
    "elem_fire": (elem_fire, 3, "SFX", False),
    "elem_water": (elem_water, 3, "SFX", False),
    "elem_ice": (elem_ice, 3, "SFX", False),
    "elem_thunder": (elem_thunder, 3, "SFX", False),
    "elem_wind": (elem_wind, 3, "SFX", False),
    "elem_dark": (elem_dark, 3, "SFX", False),
    "elem_light": (elem_light, 3, "SFX", False),
    "heal": (heal, 2, "SFX", False),
    "tile_detonate": (tile_detonate, 3, "SFX", False),
    "tile_glaze": (tile_glaze, 2, "SFX", False),
    "tile_gale": (tile_gale, 2, "SFX", False),
    "step_stone": (step_stone, 6, "SFX", False),
    "ko_thud": (ko_thud, 2, "SFX", False),
    "ui_hover": (ui_hover, 3, "UI", False),
    "ui_click": (ui_click, 2, "UI", False),
    "ui_confirm": (ui_confirm, 2, "UI", False),
    "ui_cancel": (ui_cancel, 2, "UI", False),
    "ui_pick": (ui_pick, 2, "UI", False),
    "ui_turn": (ui_turn, 2, "UI", False),
    "ui_levelup": (ui_levelup, 2, "UI", False),
    "sting_victory": (sting_victory, 2, "UI", False),
    "sting_defeat": (sting_defeat, 2, "UI", False),
    "progress_day": (progress_day, 2, "UI", False),
}


def envelope_peak(y: np.ndarray) -> float:
    """Seconds to the loudest 10 ms: where a whoosh 'is', so the game can
    line it up with the hit frame."""
    m = (y.mean(axis=1) if y.ndim > 1 else y) ** 2
    n = int(0.01 * SR)
    e = np.convolve(m, np.ones(n) / n, mode="same")
    return float(np.argmax(e)) / SR


def render(name: str, v: int) -> np.ndarray:
    fn = SOUNDS[name][0]
    rng = np.random.default_rng(zlib.crc32(f"{name}#{v}".encode()))
    y = np.asarray(fn(rng, v), dtype=np.float64)
    if y.ndim == 1:
        y = y[:, None]
    loop = SOUNDS[name][3]
    if loop:
        y = d.filt_circular(y, "high", 25.0, 2)       # a loop is filtered as if it repeated: no seam
    else:
        y = d.filt(y, "high", 25.0, 2)                # no DC, no sub rumble below hearing
        y = d.fade(y, 0.0005, 0.012)
    y, _ = d.normalise(y, TARGET, ceil_db=CEIL)
    return y


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "sfx.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() and args.only else {"sounds": {}}
    rows = []
    bad = 0
    for name, (fn, count, bus, loop) in SOUNDS.items():
        if args.only and args.only not in name:
            continue
        levels = []
        for v in range(1, count + 1):
            y = render(name, v)
            path = OUT / f"{name}_{v}.wav"
            d.save(path, y)
            pk, lu, rm, dur = d.peak_db(y), d.loudness(y), d.rms_db(y), len(y) / SR
            levels.append({"peak_db": round(pk, 2), "loudness": round(lu, 2), "rms_db": round(rm, 2), "seconds": round(dur, 3),
                           "peak_s": round(envelope_peak(y), 3)})
            ok = pk <= CEIL + 0.01 and abs(lu - TARGET) <= 1.5
            if not ok:
                bad += 1
            rows.append(f"{name}_{v:<3} {dur:6.3f}s  peak {pk:6.2f}  loud {lu:6.2f}  rms {rm:6.2f}  {'ok' if ok else 'CHECK'}")
        manifest["sounds"][name] = {"variants": count, "bus": bus, "loop": loop, "levels": levels}
    manifest["format"] = "44.1 kHz 16-bit PCM; <name>_<n>.wav, n from 1"
    manifest["target_loudness"] = TARGET
    manifest["peak_ceiling_db"] = CEIL
    manifest_path.write_text(json.dumps(manifest, indent=1))
    print("\n".join(rows))
    print(f"{len(rows)} files, {bad} outside target (peak > {CEIL} dBFS or loudness off {TARGET} by > 1.5)")
    import make_drop2                     # D240: the author's drop-2 stings, merged back into sfx.json
    make_drop2.sfx()
    import make_placeholders              # D393: ph_* placeholders + the short pick reveal, merged back too
    make_placeholders.build()
    return 0


if __name__ == "__main__":
    sys.exit(main())
