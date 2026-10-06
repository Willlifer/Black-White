"""Shared DSP helpers for the Black | White audio tools (numpy + scipy only).

WAV I/O, filters (static and circular, for seamless loops), loudness
measurement, normalisation, WSOLA time-stretching and a tiny PNG writer
(no matplotlib in this environment).
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

import numpy as np
from scipy import signal
import scipy.io.wavfile as wavfile

SR = 44100
PEAK_CEIL_DB = -1.0


# ------------------------------------------------------------------ I/O

def load(path) -> tuple[int, np.ndarray]:
    """Float64 samples in -1..1, shape (n, ch)."""
    sr, x = wavfile.read(str(path))
    dt = x.dtype
    x = x.astype(np.float64)
    if dt == np.int16:
        x /= 32768.0
    elif dt == np.int32:
        x /= 2.0 ** 31
    elif dt == np.uint8:
        x = (x - 128.0) / 128.0
    if x.ndim == 1:
        x = x[:, None]
    return sr, x


def save(path, x: np.ndarray, sr: int = SR) -> None:
    """16-bit PCM. Refuses to write anything that would clip."""
    x = np.asarray(x, dtype=np.float64)
    pk = np.max(np.abs(x)) if x.size else 0.0
    if pk > 1.0:
        raise ValueError(f"{path}: peak {pk:.3f} would clip")
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    y = np.round(x * 32767.0).astype(np.int16)
    wavfile.write(str(path), sr, y)


# ------------------------------------------------------------------ levels

def db(v: float) -> float:
    return 20.0 * np.log10(max(float(v), 1e-12))


def undb(d: float) -> float:
    return 10.0 ** (d / 20.0)


def _kweight(m: np.ndarray, sr: int) -> np.ndarray:
    """Rough K-weighting (BS.1770): a +4 dB shelf above ~1.7 kHz and a
    60 Hz high-pass. Good enough for 'LUFS-ish' levelling of short SFX."""
    b, a = signal.butter(2, 60.0 / (sr / 2), "high")
    y = signal.lfilter(b, a, m)
    hb, ha = signal.butter(1, 1700.0 / (sr / 2), "high")
    return y + (undb(4.0) - 1.0) * signal.lfilter(hb, ha, y)


def loudness(x: np.ndarray, sr: int = SR, window: float = 0.4) -> float:
    """Max momentary K-weighted RMS (dBFS) over `window` s windows.
    For one-shots this is the loud part, not diluted by silence."""
    m = x.mean(axis=1) if x.ndim > 1 else x
    k = _kweight(m, sr)
    n = max(1, int(window * sr))
    if len(k) <= n:
        return db(np.sqrt(np.mean(k ** 2)))
    c = np.cumsum(np.concatenate([[0.0], k ** 2]))
    ms = (c[n:] - c[:-n]) / n
    return db(np.sqrt(ms.max()))


def rms_db(x: np.ndarray) -> float:
    return db(np.sqrt(np.mean(np.asarray(x) ** 2)))


def peak_db(x: np.ndarray) -> float:
    return db(np.max(np.abs(x)))


def normalise(x: np.ndarray, target: float, sr: int = SR, ceil_db: float = PEAK_CEIL_DB,
              measure=None) -> tuple[np.ndarray, float]:
    """Gain to `target` loudness (default measure: momentary K-RMS), then a
    gentle peak limiter so nothing passes `ceil_db`. Returns (y, gain_db)."""
    meas = measure or (lambda v: loudness(v, sr))
    y = x
    g = 0.0
    for _ in range(4):                 # transients lose level to the limiter: top up, re-limit
        step = target - meas(y)
        if abs(step) < 0.3:
            break
        step = min(step, 6.0) if g > 0 else step
        y = limit(y * undb(step), ceil_db, sr)
        g += step
    return limit(y, ceil_db, sr), g


def limit(x: np.ndarray, ceil_db: float = PEAK_CEIL_DB, sr: int = SR, release: float = 0.06) -> np.ndarray:
    """Look-ahead peak limiter (gain computer on the |x| envelope, 1.5 ms
    look-ahead, exponential release). Leaves material under the ceiling alone."""
    ceil = undb(ceil_db) * 0.995
    a = np.abs(x).max(axis=1) if x.ndim > 1 else np.abs(x)
    if a.max() <= ceil:
        return x
    need = np.minimum(1.0, ceil / np.maximum(a, 1e-12))
    la = int(0.0015 * sr)
    # look-ahead: the gain reaches its target before the peak
    need = _min_filter(need, la)
    g = np.empty_like(need)
    rel = np.exp(-1.0 / (release * sr))
    cur = 1.0
    for i in range(len(need)):         # attack instant (already looked ahead), release smooth
        t = need[i]
        cur = t if t < cur else t + (cur - t) * rel
        g[i] = cur
    y = x * (g[:, None] if x.ndim > 1 else g)
    # belt and braces: scale any sub-sample residue under the ceiling
    pk = np.abs(y).max()
    if pk > ceil:
        y *= ceil / pk
    return y


def _min_filter(v: np.ndarray, n: int) -> np.ndarray:
    from scipy.ndimage import minimum_filter1d
    # a window of +-n around each sample: the gain is down n samples before a peak
    return minimum_filter1d(v, size=2 * n + 1, mode="nearest")


# ------------------------------------------------------------------ filters

def sos(kind: str, f, order: int = 2, sr: int = SR):
    f = np.atleast_1d(np.asarray(f, dtype=float)) / (sr / 2)
    f = np.clip(f, 1e-5, 0.9999)
    return signal.butter(order, f if f.size > 1 else f[0], kind, output="sos")


def filt(x: np.ndarray, kind: str, f, order: int = 2, sr: int = SR) -> np.ndarray:
    return signal.sosfilt(sos(kind, f, order, sr), x, axis=0)


def filt_circular(x: np.ndarray, kind: str, f, order: int = 2, sr: int = SR, zero_phase: bool = True) -> np.ndarray:
    """Filter a loop as if it repeated forever: run it over three copies and
    keep the middle, so the seam stays seamless."""
    n = len(x)
    xx = np.concatenate([x, x, x], axis=0)
    s = sos(kind, f, order, sr)
    y = signal.sosfiltfilt(s, xx, axis=0) if zero_phase else signal.sosfilt(s, xx, axis=0)
    return y[n:2 * n]


def sweep_noise(n: int, rng, f_of_t, q_of_t=None, sr: int = SR, nfft: int = 1024, colour: float = 0.0) -> np.ndarray:
    """Noise shaped by a time-varying band (centre f(t) Hz, relative width
    q(t)) in the STFT domain: whooshes, gusts, fizzes. `colour` tilts the
    spectrum (dB/octave, negative = darker)."""
    hop = nfft // 4
    noise = rng.standard_normal(n + nfft)
    f, t, Z = signal.stft(noise, sr, nperseg=nfft, noverlap=nfft - hop)
    tt = np.clip(t / max(n / sr, 1e-9), 0, 1)
    fc = np.array([f_of_t(u) for u in tt])
    q = np.array([q_of_t(u) if q_of_t else 0.6 for u in tt])
    lf = np.log2(np.maximum(f, 1.0))[:, None]
    lc = np.log2(np.maximum(fc, 1.0))[None, :]
    mask = np.exp(-0.5 * ((lf - lc) / np.maximum(q, 0.05)[None, :]) ** 2)
    if colour:
        mask *= undb(colour * (lf - np.log2(1000.0)))
    _, y = signal.istft(Z * mask, sr, nperseg=nfft, noverlap=nfft - hop)
    y = np.concatenate([y, np.zeros(max(0, n - len(y)))])[:n]
    return y / (np.std(y) + 1e-12)


# ------------------------------------------------------------------ envelopes / helpers

def t_axis(dur: float, sr: int = SR) -> np.ndarray:
    return np.arange(int(dur * sr)) / sr


def env_ad(t: np.ndarray, attack: float, decay: float, curve: float = 1.0) -> np.ndarray:
    """Attack (linear) then exponential decay with time constant `decay`."""
    a = np.clip(t / max(attack, 1e-5), 0, 1) ** curve
    d = np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-5))
    return a * d


def env_swell(t: np.ndarray, peak: float, rise: float = 2.0, fall: float = 2.0) -> np.ndarray:
    """0 → 1 at `peak` → 0 at the end; power-curve sides."""
    T = t[-1] if len(t) else 1.0
    up = np.clip(t / max(peak, 1e-5), 0, 1) ** rise
    dn = np.clip((T - t) / max(T - peak, 1e-5), 0, 1) ** fall
    return np.where(t < peak, up, dn)


def fade(x: np.ndarray, fin: float = 0.002, fout: float = 0.01, sr: int = SR) -> np.ndarray:
    y = x.copy()
    a = int(fin * sr)
    b = int(fout * sr)
    if a > 0:
        y[:a] *= np.linspace(0, 1, a)[:, None] if y.ndim > 1 else np.linspace(0, 1, a)
    if b > 0:
        y[-b:] *= np.linspace(1, 0, b)[:, None] if y.ndim > 1 else np.linspace(1, 0, b)
    return y


def modal(t: np.ndarray, freqs, decays, amps, phase_rng=None) -> np.ndarray:
    """Sum of exponentially damped sines (bells, metal, wood)."""
    y = np.zeros_like(t)
    for i, (f, d, a) in enumerate(zip(freqs, decays, amps)):
        ph = phase_rng.uniform(0, 2 * np.pi) if phase_rng is not None else 0.0
        y += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / d)
    return y


def chirp_sine(t: np.ndarray, f0: float, f1: float, tau: float) -> np.ndarray:
    """Sine whose frequency glides exponentially from f0 to f1 (time const tau)."""
    f = f1 + (f0 - f1) * np.exp(-t / max(tau, 1e-5))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def place(dst: np.ndarray, src: np.ndarray, at: float, gain: float = 1.0, sr: int = SR) -> None:
    i = int(round(at * sr))
    if i >= len(dst):
        return
    n = min(len(src), len(dst) - i)
    dst[i:i + n] += gain * src[:n]


def reverb_ir(dur: float, rng, decay: float, sr: int = SR, lp: float = 6000.0, stereo: bool = False) -> np.ndarray:
    """Synthetic room: exponentially decaying filtered noise."""
    t = t_axis(dur, sr)
    ch = 2 if stereo else 1
    ir = rng.standard_normal((len(t), ch)) * np.exp(-t / decay)[:, None]
    ir = filt(ir, "low", lp, 2, sr)
    ir[: int(0.004 * sr)] *= np.linspace(0, 1, int(0.004 * sr))[:, None]
    return ir / np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True))


def convolve(x: np.ndarray, ir: np.ndarray, wet: float, keep_len: bool = False) -> np.ndarray:
    """Mono or stereo dry/wet convolution; output grows by the IR length."""
    x2 = x if x.ndim > 1 else x[:, None]
    ch = max(x2.shape[1], ir.shape[1])
    out = np.zeros((len(x2) + len(ir) - 1, ch))
    for c in range(ch):
        out[:, c] = signal.fftconvolve(x2[:, c % x2.shape[1]], ir[:, c % ir.shape[1]])
    out *= wet
    dry = np.zeros_like(out)
    dry[: len(x2)] = x2 if x2.shape[1] == ch else np.repeat(x2, ch, axis=1)
    y = dry + out
    if keep_len:
        y = y[: len(x2)]
    return y if (x.ndim > 1 or ch > 1) else y[:, 0]


# ------------------------------------------------------------------ time stretch

def wsola(x: np.ndarray, ratio: float, frame: int = 1024, tol: int = 256) -> np.ndarray:
    """Waveform-similarity overlap-add. `ratio` = output length / input
    length (0.75 = 25% faster). Pitch is unchanged. Works on (n, ch)."""
    x2 = x if x.ndim > 1 else x[:, None]
    hs = frame // 2
    ha = hs / ratio
    win = np.hanning(frame)[:, None]
    n_out = int(round(len(x2) * ratio))
    pad = np.concatenate([np.zeros((frame + tol, x2.shape[1])), x2, np.zeros((frame * 2 + tol * 2, x2.shape[1]))])
    off = frame + tol
    y = np.zeros((n_out + frame * 2, x2.shape[1]))
    wsum = np.zeros((n_out + frame * 2, 1))
    mono = pad.mean(axis=1)
    delta = 0
    k = 0
    while k * hs < n_out + hs:
        a = int(round(k * ha)) + off
        pos = a + delta
        y[k * hs: k * hs + frame] += pad[pos: pos + frame] * win
        wsum[k * hs: k * hs + frame] += win
        # natural continuation of what we just placed, one synthesis hop on
        nat = mono[pos + hs: pos + hs + frame]
        a_next = int(round((k + 1) * ha)) + off
        lo = a_next - tol
        seg = mono[lo: lo + frame + 2 * tol]
        if len(seg) < frame + 2 * tol or len(nat) < frame:
            delta = 0
        else:
            c = signal.correlate(seg, nat, mode="valid")
            delta = int(np.argmax(c)) - tol
        k += 1
    y = y[:n_out] / np.maximum(wsum[:n_out], 1e-3)
    return y if x.ndim > 1 else y[:, 0]


def wsola_anchored(x: np.ndarray, anchors_in, anchors_out, frame: int = 1024, tol: int = 192, xfade: int = 64) -> np.ndarray:
    """WSOLA between anchor points: each segment [anchors_in[i],
    anchors_in[i+1]) is stretched on its own to land exactly on
    [anchors_out[i], anchors_out[i+1]). With anchors on the 16th-note grid,
    every drum transient stays sharp and exactly on the new grid."""
    x2 = x if x.ndim > 1 else x[:, None]
    n_out = int(anchors_out[-1])
    y = np.zeros((n_out + xfade, x2.shape[1]))
    for i in range(len(anchors_in) - 1):
        a0, a1 = int(anchors_in[i]), int(anchors_in[i + 1])
        b0, b1 = int(anchors_out[i]), int(anchors_out[i + 1])
        seg = x2[a0: min(len(x2), a1 + xfade * 2)]
        want = b1 - b0
        r = want / max(a1 - a0, 1)
        s = wsola(seg, r, frame, tol)[: want + xfade]
        if len(s) < want + xfade:
            s = np.concatenate([s, np.zeros((want + xfade - len(s), x2.shape[1]))])
        # the head of the segment is the transient: keep it whole; fade the
        # overhang out under the next segment's head
        s[want:] *= np.linspace(1, 0, xfade)[:, None]
        y[b0: b0 + want + xfade] += s
    y = y[:n_out]
    return y if x.ndim > 1 else y[:, 0]


# ------------------------------------------------------------------ analysis

def onset_flux(m: np.ndarray, sr: int = SR, n: int = 1024, hop: int = 256):
    f, t, Z = signal.stft(m, sr, nperseg=n, noverlap=n - hop)
    M = np.log1p(100 * np.abs(Z))
    flux = np.maximum(np.diff(M, axis=1), 0).sum(axis=0)
    return t[1:], flux


def peaks(t, v, k: int = 0, thr_rel: float = 0.3, min_gap: float = 0.06):
    """Local maxima above thr_rel*max, at least min_gap apart (strongest win)."""
    idx = [i for i in range(1, len(v) - 1) if v[i] >= v[i - 1] and v[i] >= v[i + 1] and v[i] > thr_rel * v.max()]
    idx.sort(key=lambda i: -v[i])
    keep = []
    for i in idx:
        if all(abs(t[i] - t[j]) >= min_gap for j in keep):
            keep.append(i)
        if k and len(keep) >= k:
            break
    keep.sort()
    return np.asarray([t[i] for i in keep]), np.asarray([v[i] for i in keep])


# ------------------------------------------------------------------ PNG

def write_png(path, rgb: np.ndarray) -> None:
    """rgb: (h, w, 3) uint8."""
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].astype(np.uint8).tobytes() for y in range(h))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(png)


# 5x7 bitmap font for PNG labels (digits, upper case, a few marks)
_FONT = {
    "0": "01110100011001110101110011000101110", "1": "00100011000010000100001000010001110",
    "2": "01110100010000100010001000100011111", "3": "11111000100010000010000011000101110",
    "4": "00010001100101010010111110001000010", "5": "11111100001111000001000011000101110",
    "6": "00110010001000011110100011000101110", "7": "11111000010001000100010000100001000",
    "8": "01110100011000101110100011000101110", "9": "01110100011000101111000010001001100",
    "A": "01110100011000111111100011000110001", "B": "11110100011000111110100011000111110",
    "C": "01110100011000010000100001000101110", "D": "11100100101000110001100011001011100",
    "E": "11111100001000011110100001000011111", "F": "11111100001000011110100001000010000",
    "G": "01110100011000010111100011000101111", "H": "10001100011000111111100011000110001",
    "I": "01110001000010000100001000010001110", "J": "00111000100001000010000101001001100",
    "K": "10001100101010011000101001001010001", "L": "10000100001000010000100001000011111",
    "M": "10001110111010110101100011000110001", "N": "10001100011100110101100111000110001",
    "O": "01110100011000110001100011000101110", "P": "11110100011000111110100001000010000",
    "Q": "01110100011000110001101011001001101", "R": "11110100011000111110101001001010001",
    "S": "01111100001000001110000010000111110", "T": "11111001000010000100001000010000100",
    "U": "10001100011000110001100011000101110", "V": "10001100011000110001100010101000100",
    "W": "10001100011000110101101011010101010", "X": "10001100010101000100010101000110001",
    "Y": "10001100010101000100001000010000100", "Z": "11111000010001000100010001000011111",
    " ": "0" * 35, "-": "00000000000000011111000000000000000", ".": "00000000000000000000000000110001100",
    ":": "00000011000110000000011000110000000", "/": "00001000010001000100010001000010000",
    "%": "11001110010001000100010001001110011", "(": "00010001000100001000010000010000010",
    ")": "01000001000001000010000100010001000", "+": "00000001000010011111001000010000000",
    "=": "00000000001111100000111110000000000", "_": "00000000000000000000000000000011111",
}


def draw_text(img: np.ndarray, x: int, y: int, text: str, col=(255, 255, 255), scale: int = 2) -> None:
    for ch in text.upper():
        g = _FONT.get(ch, _FONT[" "])
        for r in range(7):
            for c in range(5):
                if g[r * 5 + c] == "1":
                    y0, x0 = y + r * scale, x + c * scale
                    if 0 <= y0 < img.shape[0] - scale and 0 <= x0 < img.shape[1] - scale:
                        img[y0:y0 + scale, x0:x0 + scale] = col
        x += 6 * scale
