"""The author's audio drop 2 (design/audio/*.wav, 2026-10-06), measured,
trimmed and levelled into game copies. Deterministic. The originals in
design/audio/ are only read, never written.

    python game/tools/audio/make_drop2.py          # music + stings, then --import

make_music.py and make_sfx.py call music() / sfx() at their end, so a rebuild
of either keeps these in the manifests.

Music (game/audio/music/layers/, levelled like every layer: -20 dB K-RMS,
peak-bound at -1 dBFS, no limiter):
  low_beat   main set (120 BPM, 8 bars, 705 600 samples): "Low Beat" as is,
             its last 8 ms faded to zero (the raw cut jumps 0.041; bar 1
             opens on an attack from silence)
  kick       main set: "no snare beat" (120 BPM, 4 bars) twice; battle (108)
             and boss (132.3): the same, WSOLA anchored on every 16th
             (make_music.stretch_loop "drums")
  drop2/     free-tempo phrase loops, one layer each, their own length:
    arpeggio  "MainTheme Arpeggio": first onset to the onset that repeats it
    chillin   "chillin main theme": three chords at their measured spacing,
              the last one's ring-out wrapped into the head
    moderato  "moderato main loopish": two cycles of its 3.6 s figure
    rooms     "Music Rooms": the phrase and its own decay to -52 dB

Stings and one-shots (game/audio/sfx/<name>_1.wav, UI bus, levelled like
the procedural SFX: -16 LUFS-ish momentary, peaks <= -1 dBFS):
  sting_level_up, sting_pick_reveal, sting_room_hard, sting_good (very good
  event), sting_bad (cursed or bad), shop_purchase. Leading silence trimmed
  to 5 ms before the first onset, the reverb tail cut where it falls 48 dB
  under the loudest 10 ms, then faded.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bwdsp as d  # noqa: E402

SR = d.SR
GAME = Path(__file__).resolve().parents[2]
SRC = GAME.parent / "design" / "audio"
LAYERS = GAME / "audio" / "music" / "layers"
SFX = GAME / "audio" / "sfx"
TARGET_MUSIC = -20.0
TARGET_SFX = -16.0
CEIL = -1.0
N_MAIN = 705600

STINGS = {   # game name: (author's file, what it is for)
    "sting_level_up": ("sting level up", "results: one per screen when the squad levels"),
    "sting_pick_reveal": ("sting pick reveal", "a perk / skill picker opening (stops when it closes)"),
    "sting_room_hard": ("sting room hard", "a Hard room taken"),
    "sting_good": ("very good event", "Wander's jackpot; the victory sting"),
    "sting_bad": ("cursed or bad", "a cursed piece put on; the defeat sting"),
    "shop_purchase": ("shop purchase", "a trade or a scroll used in the shop"),
}
SOLO = ["arpeggio", "chillin", "moderato", "rooms"]


# ------------------------------------------------------------------ helpers

def load(name):
    sr, x = d.load(SRC / f"{name}.wav")
    assert sr == SR, (name, sr)
    return x if x.shape[1] == 2 else np.repeat(x, 2, axis=1)


def frames(x, win=0.01):
    n = int(win * SR)
    m = x.mean(axis=1)
    k = len(m) // n
    return np.array([d.db(np.sqrt(np.mean(m[i * n:(i + 1) * n] ** 2))) for i in range(k)]), n


def first_onset(x):
    """Start of the first 10 ms frame within 30 dB of the loudest one (s)."""
    f, n = frames(x)
    return int(np.where(f > f.max() - 30)[0][0]) * n / SR


def ring_end(x, below=48.0):
    """End of the last 10 ms frame within `below` dB of the loudest one (s):
    48 dB under the peak is inaudible under music at the UI level."""
    f, n = frames(x)
    return (int(np.where(f > f.max() - below)[0][-1]) + 1) * n / SR


def onsets(x, thr=0.15, gap=0.08):
    t, fl = d.onset_flux(x.mean(axis=1), SR, 1024, 128)
    pt, pv = d.peaks(t, fl, thr_rel=thr, min_gap=gap)
    return pt, pv


def fades(y, fin=0.002, fout=0.15):
    y = y.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a:
        y[:a] *= np.linspace(0, 1, a)[:, None]
    if b:
        y[-b:] *= (np.linspace(1, 0, b) ** 2)[:, None]
    return y


def phrase_loop(x, start, length):
    """x from `start`, exactly `length` samples; anything after the loop
    point (ring-out) folds onto the head, as the tail would ring over the
    next pass anyway. A 2 ms fade-in removes the cut's step."""
    seg = x[start:]
    y = np.zeros((length, 2))
    k = min(length, len(seg))
    y[:k] = seg[:k]
    over = seg[length:]
    while len(over):
        m = min(length, len(over))
        y[:m] += over[:m]
        over = over[m:]
    a = int(0.002 * SR)
    y[:a] *= np.linspace(0, 1, a)[:, None]
    return y


def seam(y):
    jump = float(np.abs(y[0] - y[-1]).max())
    typ = float(np.percentile(np.abs(np.diff(y, axis=0)), 99))
    return jump, typ


# ------------------------------------------------------------------ music

def low_beat():
    """8 bars at 120 already (705 600 samples, no lead, no tail). Bar 1
    opens on an attack from digital silence (sample 69), but the file ends
    mid-note at 0.04, so the raw loop clicks (jump 0.041, 4x the 99th-pct
    step). The last 8 ms fade to zero: the held note is cut the way the
    file's own start implies, and bar 1's attack is left untouched."""
    x = load("Low Beat")
    assert len(x) == N_MAIN, len(x)
    w = int(0.008 * SR)
    y = x.copy()
    y[-w:] *= (np.cos(np.linspace(0, np.pi / 2, w)) ** 2)[:, None]
    return y, {"end_fade_ms": 8, "raw_seam_jump": round(seam(x)[0], 4)}


def kick():
    x = load("no snare beat")
    assert len(x) * 2 == N_MAIN, len(x)
    return np.concatenate([x, x], axis=0)


def arpeggio():
    x = load("MainTheme Arpeggio")
    pt, _ = onsets(x)
    s = int((pt[0] - 0.005) * SR)
    e = int((pt[-1] - 0.005) * SR)          # the last onset (13.99 s) starts the figure again
    return phrase_loop(x, s, e - s), {"from_s": round(pt[0], 3), "to_s": round(pt[-1], 3)}


def chillin():
    x = load("chillin main theme")
    pt, pv = onsets(x)
    big = np.sort(pt[np.argsort(pv)[::-1][:3]])           # the three chords
    period = float(np.mean(np.diff(big)))
    s = int((big[0] - 0.005) * SR)
    return phrase_loop(x, s, int(round(3 * period * SR))), {"chords_s": [round(v, 3) for v in big], "period_s": round(period, 4)}


def moderato():
    """Two cycles of its figure. The period is where the onset envelope
    best repeats itself (3.3-3.9 s)."""
    x = load("moderato main loopish")
    t, fl = d.onset_flux(x.mean(axis=1), SR, 1024, 128)
    fl = fl - fl.mean()
    hop = 128 / SR
    lags = np.arange(int(3.3 / hop), int(3.9 / hop))
    ac = [float(np.dot(fl[:-L], fl[L:])) for L in lags]
    period = lags[int(np.argmax(ac))] * hop
    s = int((first_onset(x) - 0.005) * SR)
    return phrase_loop(x, s, int(round(2 * period * SR))), {"period_s": round(period, 4)}


def rooms():
    x = load("Music Rooms")
    s = int((first_onset(x) - 0.005) * SR)
    y = fades(x[s:], 0.002, 0.02)
    return y, {"from_s": round(s / SR, 3), "end_db": round(frames(x)[0][-1], 1)}


def music() -> dict:
    import make_music as mm
    info = json.loads((LAYERS / "layers.json").read_text())
    out = {}

    def put(set_name, layer, y, what, extra=None):
        folder = info["sets"][set_name]["folder"] if set_name in info["sets"] else "drop2"
        y = mm.level(y, f"{set_name}/{layer}")
        path = (LAYERS / folder / f"{layer}.wav") if folder else (LAYERS / f"{layer}.wav")
        d.save(path, y)
        jmp, typ = seam(y)
        row = {"file": (folder + "/" if folder else "") + f"{layer}.wav", "what": what, "k_rms_db": round(mm.k_rms(y), 2),
               "peak_db": round(d.peak_db(y), 2), "seam_jump": round(jmp, 5), "step_p99": round(typ, 5), "drop": 2}
        row.update(extra or {})
        out[f"{set_name}/{layer}"] = row
        return row

    y, ex = low_beat()
    info["sets"]["main"]["layers"]["low_beat"] = put("main", "low_beat", y, "author drop 2: Low Beat (120 BPM, 8 bars) as is, last 8 ms faded", ex)
    k = kick()
    info["sets"]["main"]["layers"]["kick"] = put("main", "kick", k, "author drop 2: no snare beat (120 BPM, 4 bars) twice")
    for set_name in ("battle", "boss"):
        n = int(info["sets"][set_name]["samples"])
        ks = mm.stretch_loop(k, n, "drums")
        assert len(ks) == n
        info["sets"][set_name]["layers"]["kick"] = put(set_name, "kick", ks,
                                                      f"kick re-timed to {info['sets'][set_name]['bpm']} BPM (WSOLA anchored on the 16th)")
    for name, (fn, src, what) in {
        "arpeggio": (arpeggio, "MainTheme Arpeggio", "free-tempo phrase loop (4 phrases, D-A-C-D), first onset to its repeat"),
        "chillin": (chillin, "chillin main theme", "three sustained chords at their measured spacing, ring-out wrapped"),
        "moderato": (moderato, "moderato main loopish", "two cycles of its arpeggiated figure"),
        "rooms": (rooms, "Music Rooms", "the phrase and its own decay, lead trimmed"),
    }.items():
        y, ex = fn()
        info["sets"][name] = {"samples": len(y), "seconds": round(len(y) / SR, 6), "free": True, "folder": "drop2",
                              "source": f"design/audio/{src}.wav", "layers": {}}
        info["sets"][name]["layers"][name] = put(name, name, y, what, ex)
    (LAYERS / "layers.json").write_text(json.dumps(info, indent=1))
    print("drop 2 music:")
    for k2, r in out.items():
        print(f"  {k2:18s} {r['k_rms_db']:6.2f} dB K-RMS  peak {r['peak_db']:6.2f}  seam {r['seam_jump']:.4f} (p99 step {r['step_p99']:.4f})")
    return out


# ------------------------------------------------------------------ stings

def sfx() -> dict:
    path = SFX / "sfx.json"
    manifest = json.loads(path.read_text())
    out = {}
    for name, (src, what) in STINGS.items():
        x = load(src)
        on = first_onset(x)
        end = min(len(x) / SR, ring_end(x) + 0.05)
        truncated = end >= len(x) / SR - 0.01           # still ringing when the file ends
        y = x[int(max(0.0, on - 0.005) * SR): int(end * SR)]
        y = fades(y, 0.002, 0.35 if truncated else 0.15)
        y, gain = d.normalise(y, TARGET_SFX, ceil_db=CEIL)
        d.save(SFX / f"{name}_1.wav", y)
        f, n = frames(y)
        lv = {"peak_db": round(d.peak_db(y), 2), "loudness": round(d.loudness(y), 2), "rms_db": round(d.rms_db(y), 2),
              "seconds": round(len(y) / SR, 3), "peak_s": round(int(np.argmax(f)) * n / SR, 3),
              "body_s": round((int(np.where(f > f.max() - 20)[0][-1]) + 1) * n / SR, 3)}   # BWMusic ducks for this long
        manifest["sounds"][name] = {"variants": 1, "bus": "UI", "loop": False, "levels": [lv], "drop": 2,
                                    "source": f"design/audio/{src}.wav", "for": what,
                                    "trim": {"lead_cut_s": round(max(0.0, on - 0.005), 3), "end_s": round(end, 3),
                                             "fade_out_s": 0.35 if truncated else 0.15, "gain_db": round(gain, 2)}}
        out[name] = manifest["sounds"][name]
        print(f"  {name:18s} {lv['seconds']:5.2f}s  loud {lv['loudness']:6.2f}  peak {lv['peak_db']:6.2f}  "
              f"(cut {on - 0.005:.3f}s lead, end {end:.2f}s{' truncated' if truncated else ''}, gain {gain:+.1f} dB)")
    path.write_text(json.dumps(manifest, indent=1))
    return out


def main() -> int:
    print("drop 2 stings:")
    sfx()
    import make_placeholders              # D393: keeps sting_pick_short + ph_* in sfx.json
    make_placeholders.build()
    music()
    return 0


if __name__ == "__main__":
    sys.exit(main())
