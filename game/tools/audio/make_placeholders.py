"""D392/D393: placeholder SFX for AUDIO-NEEDS.md's "Still missing" list, and
a short cut of the author's pick-reveal sting. Deterministic. Every file is
named ph_* (or sting_pick_short) so the author knows it is ours to replace.

    python game/tools/audio/make_placeholders.py      # then godot --headless --path game --import

Built from the author's recordings where one fits, plus procedural synthesis
in make_sfx.py's style (filtered noise, damped modes, sweeps, saturation):
  author parts    the kick of "no snare beat" (thuds), the first pluck of
                  "shop purchase" (pity), the first two notes of "sting level
                  up" (heal proc), the opening hit of "cursed or bad" (on-kill),
                  the Low fish voice takes (Being hum, granular). All read from
                  design/audio/ or the project folders, never written.
  key (D412)      the parts cut from the stings come from their -3 st retune
                  (retune.py), so the procs sit in A like the stings; the
                  low bell is F#2 / A2. The author's C versions are built too,
                  as <name>_c (manifest "alt_of"; BWSfx.STING_KEY = "C").
  levels          like every SFX: -16 LUFS-ish momentary, peaks <= -1 dBFS,
                  onsets trimmed to 3 ms before the first sound; loops wrap
                  their filters and tails so the seam is clean.

sting_pick_short (D392): "sting pick reveal" trimmed like make_drop2, its
first <= 2.5 s, the last 0.8 s faded (cos^2) so the phrase releases. In A
(D412), and sting_pick_short_c from the original.
"""
from __future__ import annotations

import json
import sys
import zlib
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bwdsp as d  # noqa: E402
import make_drop2 as m2  # noqa: E402
import make_sfx as ms  # noqa: E402
from make_sfx import burst, thump, click, whoosh, sat, bell, jit, hz, noise  # noqa: E402

SR = d.SR
OUT = ms.OUT
TARGET = ms.TARGET
CEIL = ms.CEIL
SHORT_MAX = 2.5
SHORT_FADE = 0.8

_cache: dict = {}
KEY = "A"                       # D412: the key the sting-made parts are cut in ("C" = the author's originals)
FROM_STINGS = ["ph_proc_onkill", "ph_proc_heal", "ph_proc_pity"]   # built twice: A, and <name>_c in C


def mono(x):
    return x.mean(axis=1) if x.ndim > 1 else x


def author_part(name, start, length, fade_out=0.05):
    """A slice of one of the author's drop-2 files (mono), from `start` s."""
    key = (name, start, length, KEY)
    if key not in _cache:
        x = mono(m2.load_keyed(name, KEY))
        a = int(start * SR)
        y = x[a:a + int(length * SR)].copy()
        y = d.fade(y, 0.001, fade_out)
        _cache[key] = y / (np.abs(y).max() + 1e-9)
    return _cache[key].copy()


def kick(pitch=1.0):
    """The author's kick ("no snare beat", the 0.5 s downbeat), resampled by `pitch`."""
    k = author_part("no snare beat", 0.495, 0.45, 0.08)
    if pitch != 1.0:
        k = np.interp(np.arange(0, len(k) - 1, pitch), np.arange(len(k)), k)
    return k


# ------------------------------------------------------------------ weapon swap

def swap_holster(rng, v):
    """Cloth swish, a blade scraping into its sheath (stick-slip at 180 -> 90 Hz
    over 3-8 kHz noise), then the seat: a short leather/wood clack."""
    dur = 0.5
    t = d.t_axis(dur)
    y = 0.5 * whoosh(rng, dur, 700, jit(rng, 2600, 0.15), 1200, 0.12, q=0.6, colour=-1.0)
    sd = 0.2
    st = d.t_axis(sd)
    rate = 180 * (90 / 180) ** (st / sd)
    gate = (np.sin(2 * np.pi * np.cumsum(rate) / SR) > 0.6).astype(float)
    scrape = d.filt(noise(rng, len(st)), "band", [3000, 8000], 2) * (0.35 + 0.65 * gate) * d.env_swell(st, 0.05, 1.0, 1.0)
    d.place(y, 0.55 * scrape, jit(rng, 0.13, 0.1))
    seat = d.modal(d.t_axis(0.12), [jit(rng, 310, 0.08), 760, 1350], [0.03, 0.015, 0.008], [1, 0.5, 0.25], rng)
    seat += 0.8 * thump(0.12, 160, 90, 0.01, 0.025)
    d.place(y, 1.0 * seat, 0.34)
    return y


def swap_draw(rng, v):
    """A quick scrape out of the sheath and the blade's ring as it clears
    (metal modes, 0.35 s) into a grip thump. Plays when the weapon reaches
    the hand: the ring leads by ~70 ms."""
    dur = 0.6
    st = d.t_axis(0.09)
    rate = 90 * (240 / 90) ** (st / 0.09)
    gate = (np.sin(2 * np.pi * np.cumsum(rate) / SR) > 0.5).astype(float)
    scrape = d.filt(noise(rng, len(st)), "band", [3500, 9000], 2) * (0.3 + 0.7 * gate) * d.env_swell(st, 0.07, 1.5, 0.5)
    y = np.zeros(int(dur * SR))
    d.place(y, 0.6 * scrape, 0.0)
    f0 = jit(rng, 2150, 0.05)
    ring = d.modal(d.t_axis(0.5), [f0, f0 * 1.58, f0 * 2.37, f0 * 3.11], [0.32, 0.18, 0.1, 0.06], [0.5, 0.35, 0.22, 0.12], rng)
    d.place(y, ring, 0.07)
    grip = thump(0.1, 180, 110, 0.01, 0.02) + 0.3 * burst(rng, 0.1, 400, 1800, 0.015)
    d.place(y, 0.9 * grip, 0.075)
    return y


# ------------------------------------------------------------------ procs

def proc_onkill(rng, v):
    """A knell: the opening hit of "cursed or bad" over the author's kick,
    pitched down, with a low bell (F#2 / A2 in A; F#2 / C3 in C) ringing out."""
    dur = 1.6
    y = np.zeros(int(dur * SR))
    hit = author_part("cursed or bad", 0.40, 1.1, 0.4)
    d.place(y, 0.8 * hit, 0.0)
    d.place(y, 0.9 * kick(0.8 if v == 1 else 0.72), 0.0)
    low = hz("F#", 2) if v == 1 else (hz("A", 2) if KEY == "A" else hz("C", 3))
    d.place(y, 0.35 * bell(low, 1.5, 0.9, rng, 0.6), 0.005)
    return sat(y / np.abs(y).max(), 1.3)


def proc_heal(rng, v):
    """The first two notes of "sting level up" (A -> E; C -> G in C), lifted an octave
    (v2: the first note only), with a light sparkle on top."""
    src = author_part("sting level up", 0.16, 0.85, 0.25)
    if v == 2:
        src = author_part("sting level up", 0.16, 0.44, 0.15)
    up = np.interp(np.arange(0, len(src) - 1, 2.0), np.arange(len(src)), src)     # +12 st, half length
    dur = 0.9
    y = np.zeros(int(dur * SR))
    d.place(y, 0.7 * up, 0.0)
    d.place(y, 0.5 * src[:int(0.45 * SR)], 0.0)
    y += 0.08 * burst(rng, dur, 6000, 12000, 0.25, attack=0.08)
    return y


def proc_pity(rng, v):
    """The first pluck of "shop purchase" (a soft A; C in C), short, with a wooden
    tick under it: luck, quietly."""
    p = author_part("shop purchase", 0.865, 0.55, 0.2)
    if v == 2:
        p = np.interp(np.arange(0, len(p) - 1, 1.5), np.arange(len(p)), p)      # up a fifth (G)
    y = np.zeros(int(0.6 * SR))
    d.place(y, p, 0.0)
    tick = d.modal(d.t_axis(0.05), [1800, 2900], [0.01, 0.006], [1, 0.4], rng)
    d.place(y, 0.25 * tick, 0.0)
    return y


# ------------------------------------------------------------------ hits, obelisks

def immune(rng, v):
    """A dull clank: low, heavily damped inharmonic modes (no ring), a
    muffled thud, low-passed so it reads as "nothing got through"."""
    dur = 0.4
    f0 = jit(rng, 240, 0.1)
    t = d.t_axis(dur)
    y = d.modal(t, [f0, f0 * 1.58, f0 * 2.37, f0 * 3.11, f0 * 4.2], [0.07, 0.05, 0.035, 0.025, 0.015], [1, 0.7, 0.5, 0.3, 0.2], rng)
    y += 1.0 * thump(dur, 140, 70, 0.01, 0.05)
    y += 0.4 * burst(rng, dur, 300, 1600, 0.02)
    return d.filt(sat(y / np.abs(y).max(), 1.8), "low", 2400, 2)


def obelisk_push(rng, v):
    """Breathing out: the author's kick a fourth down as the stone's thump,
    a 45 Hz sub, and a falling outward rush (1.1k -> 160 Hz)."""
    dur = 1.7
    t = d.t_axis(dur)
    y = np.zeros(len(t))
    d.place(y, 1.0 * kick(0.75), 0.0)
    y += 0.7 * thump(dur, 70, 40, 0.1, 0.5)
    rush = d.sweep_noise(len(t), rng, lambda u: 1100 * (160 / 1100) ** min(u * 1.4, 1), lambda u: 1.0, colour=-1.5)
    y += 0.55 * rush * d.env_ad(t, 0.03, 0.45)
    ir = d.reverb_ir(1.2, rng, 0.4, lp=2000)
    return d.convolve(sat(y / np.abs(y).max(), 1.6), ir, 0.25, keep_len=True)


def obelisk_pull(rng, v):
    """Breathing in: a rising inward rush (150 -> 1.3 kHz) swelling to a
    thump at 0.9 s (the author's kick, a fourth down) that ends it."""
    dur = 1.5
    t = d.t_axis(dur)
    hit = 0.9
    rush = d.sweep_noise(len(t), rng, lambda u: 150 * (1300 / 150) ** min(u / (hit / dur), 1), lambda u: 1.0, colour=-1.5)
    env = np.where(t < hit, (t / hit) ** 2.5, np.exp(-(t - hit) / 0.04))
    y = 0.6 * rush * env
    y += 0.4 * np.sin(2 * np.pi * 46 * t) * np.where(t < hit, (t / hit) ** 2, np.exp(-(t - hit) / 0.2))
    d.place(y, 1.0 * kick(0.75), hit)
    return sat(y / np.abs(y).max(), 1.5)


# ------------------------------------------------------------------ encounters

def colossus_step(rng, v):
    """A giant's footfall: the author's kick down a fifth, a 55 -> 32 Hz
    thump, low gravel grit and a few settling pebbles."""
    dur = 0.8
    t = d.t_axis(dur)
    y = np.zeros(len(t))
    d.place(y, 1.0 * kick(jit(rng, 0.66, 0.05)), 0.0)
    y += 0.9 * thump(dur, 55, 32, 0.05, 0.22)
    y += 0.35 * burst(rng, dur, 250, 1600, 0.06)
    for _ in range(5):
        d.place(y, rng.uniform(0.05, 0.15) * click(rng, 0.004, 2000), rng.uniform(0.05, 0.35))
    return sat(y / np.abs(y).max(), 3.0)


def colossus_thrust(rng, v):
    """The big spear lunge: a heavy, slow whoosh (150 -> 750 -> 220 Hz) that
    peaks at 0.28 s (lined up on the clip's "hit"), an armour rattle on
    the drive and a low push under it."""
    dur = 0.9
    t = d.t_axis(dur)
    pk = 0.28
    y = whoosh(rng, dur, 150, jit(rng, 750, 0.1), 220, pk, q=0.8, colour=-1.5, rise=2.2, fall=1.8)
    y += 0.5 * whoosh(rng, dur, 600, 2400, 900, pk, q=0.3, colour=-0.5, rise=2.5, fall=2.5)
    y += 0.5 * np.sin(2 * np.pi * np.cumsum(60 + 40 * d.env_swell(t, pk)) / SR) * d.env_swell(t, pk, 2.0, 2.0)
    for i in range(6):
        d.place(y, rng.uniform(0.1, 0.25) * d.modal(d.t_axis(0.05), [rng.uniform(1800, 3200)], [0.012], [1], rng), 0.12 + 0.03 * i)
    return y


def _loop_noise(rng, n, band, xf=0.25):
    bed = d.filt(noise(rng, n + int(xf * SR)), "band", band, 2)
    bed /= np.std(bed)
    k = int(xf * SR)
    w = np.linspace(0, 1, k)
    out = bed[:n].copy()
    out[:k] = bed[:k] * w + bed[n:n + k] * (1 - w)
    return out


def horde_shuffle(rng, v):
    """A crowd of feet, 3.0 s seamless: ~16 scuffs and heel taps a second
    (make_sfx's stone step, smaller and shuffled), random levels, over a
    low grit bed. Everything wraps the seam."""
    dur = 3.0
    n = int(dur * SR)
    y = np.zeros(n)
    tpos = 0.0
    while tpos < dur:
        fp = 0.25 * thump(0.12, jit(rng, 160, 0.2), 80, 0.01, 0.015)
        fp += 0.5 * burst(rng, 0.12, jit(rng, 1200, 0.3), 4500, jit(rng, 0.03, 0.3), attack=jit(rng, 0.01, 0.5))
        g = rng.uniform(0.2, 0.9)
        idx = (int(tpos * SR) + np.arange(len(fp))) % n
        y[idx] += g * fp
        tpos += rng.exponential(1 / 16.0)
    y += 0.12 * _loop_noise(rng, n, [300, 2500])
    return d.filt_circular(y, "high", 60.0, 2)


def being_hum(rng, v):
    """An Elemental Being's idle hum, 4.0 s seamless: a granular drone from
    the Low fish voice takes (as the music's voice_pad), on A2 and E3, with a
    slow 0.5 Hz swell and a 0.25 Hz-multiple sine core so the loop closes."""
    import make_music as mm
    dur = 4.0
    n = int(dur * SR)
    srcs, pool = mm.voice_pool()
    y = np.zeros(n)
    t = d.t_axis(dur)
    for target, gain in ((hz("A", 2), 1.0), (hz("E", 3), 0.5)):
        pos = 0.0
        while pos < dur and pool:
            L = int(rng.uniform(0.08, 0.14) * SR)
            si, s0, f0 = pool[rng.integers(len(pool))]
            ratio = target * 2 ** (rng.normal(0, 6) / 1200) / f0
            need = int(L * ratio) + 2
            src = srcs[si]
            if s0 + need < len(src):
                seg = src[s0:s0 + need]
                g = np.interp(np.arange(L) * ratio, np.arange(len(seg)), seg) * np.hanning(L)
                idx = (int(pos * SR) + np.arange(L)) % n
                y[idx] += gain * g
            pos += rng.uniform(0.6, 1.4) / 40.0
    y = d.filt_circular(y, "band", [90, 1800], 2)
    y = y / (np.abs(y).max() + 1e-9)
    core = 0.35 * np.sin(2 * np.pi * 110.0 * t) + 0.15 * np.sin(2 * np.pi * 165.0 * t) + 0.1 * np.sin(2 * np.pi * 55.0 * t)
    swell = 0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * t)
    return (0.7 * y + core) * swell


def blank_step(rng, v):
    """Eerie and exact: a dry heel tick, a muted knock, and a faint glassy
    ping (A6 / E6 / F#6) that hangs a moment. Variations differ only in the
    ping, so the steps read as identical, precise."""
    dur = 0.45
    y = np.zeros(int(dur * SR))
    d.place(y, 0.6 * click(rng, 0.003, 4000), 0.0)
    knock = d.modal(d.t_axis(0.06), [185, 420], [0.012, 0.006], [1, 0.4], rng) + 0.5 * thump(0.06, 140, 90, 0.005, 0.012)
    d.place(y, knock, 0.0)
    f = [hz("A", 6), hz("E", 6), hz("F#", 6)][(v - 1) % 3]
    ping = d.modal(d.t_axis(0.4), [f, f * 2.76], [0.18, 0.05], [1, 0.2], None)
    d.place(y, 0.08 * ping, 0.012)
    return y


# ------------------------------------------------------------------ big casts

def cast_fire(rng, v):
    """Fire roar: a deep whoomph, a 1.2 s roaring band and dense crackle."""
    dur = 1.5
    t = d.t_axis(dur)
    y = whoosh(rng, dur, 120, jit(rng, 900, 0.1), 300, 0.12, q=1.1, colour=-2.0, rise=1.0, fall=1.4)
    y += 0.6 * d.filt(noise(rng, len(t)), "band", [200, 1500], 2) / 3 * d.env_ad(t, 0.08, 0.5) * (0.7 + 0.3 * np.sin(2 * np.pi * 11 * t))
    y += 0.6 * thump(dur, 80, 40, 0.05, 0.25)
    for _ in range(70):
        at = rng.exponential(0.3)
        if at < dur - 0.01:
            d.place(y, rng.exponential(0.5) * click(rng, rng.uniform(0.001, 0.004), rng.uniform(1500, 5000)), at)
    return sat(y / np.abs(y).max(), 1.8)


def cast_water(rng, v):
    """Water surge: a rushing band rising 200 Hz -> 1.6 kHz with bubbling AM,
    cresting into a splash at 0.14 s, then droplets."""
    dur = 1.4
    t = d.t_axis(dur)
    rush = d.sweep_noise(len(t), rng, lambda u: 200 * (1600 / 200) ** min(u * 7, 1) * (1 - 0.5 * max(u - 0.15, 0)), lambda u: 1.2, colour=-1.0)
    y = rush * d.env_swell(t, 0.14, 1.2, 1.6) * (0.75 + 0.25 * np.sin(2 * np.pi * 17 * t))
    d.place(y, 0.9 * burst(rng, 0.6, 700, 4000, 0.12, attack=0.01), 0.12)
    d.place(y, 0.6 * thump(0.3, 180, 90, 0.04, 0.08), 0.12)
    for _ in range(30):
        at = 0.15 + rng.exponential(0.25)
        if at < dur - 0.03:
            dt = d.t_axis(0.03)
            f0 = rng.uniform(600, 1800)
            d.place(y, rng.uniform(0.1, 0.35) * np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.8 * dt / 0.03)) / SR) * np.exp(-dt / 0.008), at)
    return y


def cast_ice(rng, v):
    """Ice crack: a hard split at 0.1 s, a low groan as it spreads, and a
    shower of glassy shards."""
    dur = 1.4
    t = d.t_axis(dur)
    y = np.zeros(len(t))
    crack = 1.4 * burst(rng, 0.4, 2500, 11000, 0.012) + 0.8 * thump(0.4, 320, 110, 0.01, 0.04)
    d.place(y, crack, 0.1)
    d.place(y, 0.6 * burst(rng, 0.3, 3000, 9000, 0.008), 0.16)
    groan = np.sin(2 * np.pi * np.cumsum(95 * (1 + 0.06 * np.sin(2 * np.pi * 4 * t))) / SR)
    y += 0.3 * d.filt(sat(groan, 3.0), "band", [150, 1200], 2) * d.env_swell(t, 0.35, 1.5, 2.0)
    for _ in range(45):
        at = 0.1 + rng.exponential(0.2)
        if at < dur - 0.15:
            f = rng.uniform(2500, 7500)
            d.place(y, rng.exponential(0.2) * d.modal(d.t_axis(0.15), [f, f * 1.53], [rng.uniform(0.03, 0.12), 0.03], [1, 0.4], rng), at)
    return y


def cast_thunder(rng, v):
    """Thunder snap: an N-wave crack at 0.06 s, a crackling saw burst, then a
    rolling 1.2 s rumble."""
    dur = 1.6
    t = d.t_axis(dur)
    y = np.zeros(len(t))
    snap = ms.elem_thunder(rng, v)
    d.place(y, 1.0 * snap, 0.04)
    nw = d.t_axis(0.004)
    d.place(y, 1.5 * np.concatenate([1 - 2 * nw / 0.004, np.zeros(10)]), 0.06)
    rumble = d.filt(noise(rng, len(t)), "low", 180, 2)
    rumble = rumble / np.std(rumble) * d.env_ad(t, 0.12, 0.45) * (0.6 + 0.4 * np.abs(d.filt(noise(rng, len(t)), "low", 6, 1)) * 40)
    y += 0.25 * np.clip(rumble, -4, 4)
    return sat(y / np.abs(y).max(), 1.8)


def cast_wind(rng, v):
    """Wind whoosh: a wide gust (300 -> 2 kHz -> 500 Hz) peaking at 0.2 s with
    a 6 Hz flutter and a high whistle, in stereo."""
    dur = 1.3
    t = d.t_axis(dur)
    L = whoosh(rng, dur, 300, jit(rng, 2000, 0.1), 500, 0.2, q=1.1, colour=-1.5, rise=1.2, fall=1.4)
    R = whoosh(rng, dur, 300, jit(rng, 1900, 0.1), 520, 0.21, q=1.1, colour=-1.5, rise=1.2, fall=1.4)
    fl = 0.75 + 0.25 * np.sin(2 * np.pi * 6 * t)
    wh = 0.3 * whoosh(rng, dur, 1200, 2100, 1400, 0.22, q=0.05, colour=0.0)
    return ms.stereo((L + wh) * fl, (R + wh) * fl)


def cast_light(rng, v):
    """Light shimmer: an A-major bell cluster (A5 C#6 E6 A6, rolled), a
    bright noise sparkle and a soft swell under it."""
    dur = 1.8
    t = d.t_axis(dur)
    y = np.zeros(len(t))
    for i, f in enumerate([hz("A", 5), hz("C#", 6), hz("E", 6), hz("A", 6)]):
        d.place(y, (0.8 - 0.1 * i) * bell(f, dur - 0.2, 1.0, rng, 0.9), 0.06 + i * 0.035)
    y += 0.18 * burst(rng, dur, 5000, 12000, 0.5, attack=0.08)
    y += 0.25 * sum(np.sin(2 * np.pi * f * t) for f in (hz("A", 4), hz("E", 5))) * d.env_swell(t, 0.25, 1.2, 1.6)
    return y


def cast_dark(rng, v):
    """Dark collapse: an inward swell (a reversed low rush) drawn tight, then
    the implosion at 0.68 s (the release's dark impact time): a 40 Hz sub
    drop and a 31 Hz ring-mod shiver as it settles."""
    dur = 1.6
    t = d.t_axis(dur)
    hit = 0.68
    rush = d.sweep_noise(len(t), rng, lambda u: 90 * (700 / 90) ** min(u / (hit / dur), 1), lambda u: 0.9, colour=-2.5)
    y = 0.7 * rush * np.where(t < hit, (t / hit) ** 3, np.exp(-(t - hit) / 0.03))
    tail = d.t_axis(dur - hit)
    imp = 1.0 * d.chirp_sine(tail, 120, 38, 0.06) * d.env_ad(tail, 0.002, 0.35)
    imp += 0.5 * burst(rng, dur - hit, 80, 600, 0.12)
    imp *= 0.8 + 0.2 * np.sin(2 * np.pi * 31 * tail)
    d.place(y, imp, hit)
    return sat(y / np.abs(y).max(), 1.6)


def fan_knives(rng, v):
    """Fan of Knives: three thin blade whooshes 70 ms apart, rising, and a
    small knife-release tick on each; the last (loudest) one peaks at 0.22 s
    (lined up on the spin's "hit")."""
    dur = 0.6
    y = np.zeros(int(dur * SR))
    for i in range(3):
        w = whoosh(rng, 0.3, 900 + 300 * i, jit(rng, 3600 + 500 * i, 0.1), 1800, 0.08, q=0.35, colour=-0.3)
        d.place(y, (0.55 + 0.2 * i) * w, 0.06 + 0.07 * i)
        tick = d.modal(d.t_axis(0.04), [rng.uniform(3500, 5200)], [0.01], [1], rng)
        d.place(y, 0.25 * tick, 0.14 + 0.07 * i)
    return y


# ------------------------------------------------------------------ registry
# name: (generator, variations, bus, loop, what it replaces / where it plays)
PH = {
    "ph_swap_holster": (swap_holster, 2, "SFX", False, "weapon swap: the hand weapon goes to its carry spot"),
    "ph_swap_draw": (swap_draw, 2, "SFX", False, "weapon swap: the other weapon reaches the hand"),
    "ph_proc_onkill": (proc_onkill, 2, "SFX", False, "on-kill enchantments (Death Knell, Relentless, Wake of Ash)"),
    "ph_proc_heal": (proc_heal, 2, "SFX", False, "lifesteal / recovery procs (an enchantment's heal, Mend-Link)"),
    "ph_proc_pity": (proc_pity, 2, "SFX", False, "RNG forgiveness (Second Chance, Graze, Follow-Through, Steady Hand)"),
    "ph_immune": (immune, 3, "SFX", False, "a blow on an immune Blank / Elemental Being"),
    "ph_obelisk_push": (obelisk_push, 2, "SFX", False, "the Lantern's pulse (push)"),
    "ph_obelisk_pull": (obelisk_pull, 2, "SFX", False, "the Well's pulse (pull)"),
    "ph_colossus_step": (colossus_step, 3, "SFX", False, "the Colossus's footfalls and arrival stomp"),
    "ph_colossus_thrust": (colossus_thrust, 2, "SFX", False, "the Colossus's line thrust"),
    "ph_horde_shuffle": (horde_shuffle, 1, "SFX", True, "loop while any Horde grunt walks"),
    "ph_being_hum": (being_hum, 1, "SFX", True, "loop on each living Elemental Being"),
    "ph_blank_step": (blank_step, 3, "SFX", False, "a Blank's footsteps"),
    "ph_cast_fire": (cast_fire, 2, "SFX", False, "big fire cast release"),
    "ph_cast_water": (cast_water, 2, "SFX", False, "big water cast release"),
    "ph_cast_ice": (cast_ice, 2, "SFX", False, "big ice cast release"),
    "ph_cast_thunder": (cast_thunder, 2, "SFX", False, "big thunder cast release"),
    "ph_cast_wind": (cast_wind, 2, "SFX", False, "big wind cast release"),
    "ph_cast_light": (cast_light, 2, "SFX", False, "big light cast release"),
    "ph_cast_dark": (cast_dark, 2, "SFX", False, "big dark cast release"),
    "ph_fan_knives": (fan_knives, 2, "SFX", False, "Fan of Knives' spin"),
}


def trim_onset(y):
    """Cut to 3 ms before the first sample within 40 dB of the peak."""
    m = np.abs(mono(y))
    i = int(np.argmax(m > m.max() * 10 ** (-40 / 20)))
    return y[max(0, i - int(0.003 * SR)):]


def render(name, v):
    fn, _, _, loop, _ = PH[name]
    rng = np.random.default_rng(zlib.crc32(f"{name}#{v}".encode()))
    y = np.asarray(fn(rng, v), dtype=np.float64)
    if y.ndim == 1:
        y = y[:, None]
    if loop:
        y = d.filt_circular(y, "high", 25.0, 2)
    else:
        y = d.filt(y, "high", 25.0, 2)
        y = trim_onset(y)
        y = d.fade(y, 0.0005, 0.03)
    y, _ = d.normalise(y, TARGET, ceil_db=CEIL)
    return y


def pick_short():
    """D392: the author's pick reveal, trimmed as make_drop2 trims it, then
    its first <= 2.5 s: cut 20 ms before a strong onset in 1.9-2.5 s if one
    opens a phrase there, else at 2.5 s; the last 0.8 s fade (cos^2)."""
    x = m2.load_keyed("sting pick reveal", KEY)
    on = m2.first_onset(x)
    y = x[int(max(0.0, on - 0.005) * SR):]
    pt, pv = m2.onsets(y, thr=0.3, gap=0.12)
    cands = [t for t in pt if 1.9 <= t <= SHORT_MAX + 0.02]
    end = min(SHORT_MAX, (max(cands) - 0.02) if cands else SHORT_MAX)
    z = y[:int(end * SR)].copy()
    z = m2.fades(z, 0.002, 0.0)
    b = int(SHORT_FADE * SR)
    z[-b:] *= (np.cos(np.linspace(0, np.pi / 2, b)) ** 2)[:, None]
    z, gain = d.normalise(z, m2.TARGET_SFX, ceil_db=CEIL)
    return z, {"lead_cut_s": round(max(0.0, on - 0.005), 3), "cut_s": round(end, 3), "fade_out_s": SHORT_FADE, "gain_db": round(gain, 2)}


def build() -> dict:
    global KEY
    path = OUT / "sfx.json"
    manifest = json.loads(path.read_text())
    rows = []
    jobs = [(n, "A") for n in PH] + [(n, "C") for n in FROM_STINGS]
    for name, key in jobs:
        fn, count, bus, loop, what = PH[name]
        KEY = key
        out = name if key == "A" else name + "_c"
        levels = []
        for v in range(1, count + 1):
            y = render(name, v)
            d.save(OUT / f"{out}_{v}.wav", y)
            pk, lu = d.peak_db(y), d.loudness(y)
            levels.append({"peak_db": round(pk, 2), "loudness": round(lu, 2), "rms_db": round(d.rms_db(y), 2),
                           "seconds": round(len(y) / SR, 3), "peak_s": round(ms.envelope_peak(y), 3)})
            rows.append(f"  {out}_{v:<2} {len(y) / SR:5.2f}s  loud {lu:6.2f}  peak {pk:6.2f}  peak@ {levels[-1]['peak_s']:.3f}s")
        row = {"variants": count, "bus": bus, "loop": loop, "levels": levels, "placeholder": True, "for": what}
        if name in FROM_STINGS:
            row["key"] = key
            if key == "C":
                row["alt_of"] = name
        manifest["sounds"][out] = row
    for key in ("A", "C"):
        KEY = key
        out = "sting_pick_short" if key == "A" else "sting_pick_short_c"
        z, trim = pick_short()
        d.save(OUT / f"{out}_1.wav", z)
        f, n = m2.frames(z)
        lv = {"peak_db": round(d.peak_db(z), 2), "loudness": round(d.loudness(z), 2), "rms_db": round(d.rms_db(z), 2),
              "seconds": round(len(z) / SR, 3), "peak_s": round(int(np.argmax(f)) * n / SR, 3),
              "body_s": round((int(np.where(f > f.max() - 20)[0][-1]) + 1) * n / SR, 3), "tail_s": m2.tail_s(f, n)}
        row = {"variants": 1, "bus": "UI", "loop": False, "levels": [lv], "drop": 2, "cut_of": "sting_pick_reveal" + ("" if key == "A" else "_c"),
               "source": "design/audio/sting pick reveal.wav", "for": "the pick cards (D392)", "trim": trim, "key": key}
        if key == "C":
            row["alt_of"] = "sting_pick_short"
        manifest["sounds"][out] = row
        rows.append(f"  {out} {lv['seconds']:.2f}s  loud {lv['loudness']:.2f}  peak {lv['peak_db']:.2f}  (cut {trim['cut_s']} s)")
    KEY = "A"
    path.write_text(json.dumps(manifest, indent=1))
    print("\n".join(rows))
    return manifest


def main() -> int:
    print("placeholders (D392/D393):")
    build()
    return 0


if __name__ == "__main__":
    sys.exit(main())
