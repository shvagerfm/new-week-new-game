"""Synthesizes the game's sound effects into WAV files next to this script.

Run: python3 sfx/make_sfx.py   (needs numpy)

Every sound is built from sines, soft square waves and filtered noise, so the
set stays small and consistent. Change a recipe and run again to regenerate.
"""
import os
import wave

import numpy as np

RATE = 22050
OUT = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(7)


def t_axis(dur):
    return np.arange(int(RATE * dur)) / RATE


def env(n, attack=0.004, decay=None, total=None):
    """Fast attack, exponential decay. decay = time to fall to ~5%."""
    t = np.arange(n) / RATE
    a = np.clip(t / attack, 0, 1) if attack > 0 else np.ones(n)
    d = np.exp(-3.0 * t / (decay or (n / RATE)))
    return a * d


def tone(freq, dur, shape="sine", vol=1.0):
    """freq can be a number or an array (sweep)."""
    t = t_axis(dur)
    f = np.broadcast_to(np.asarray(freq, dtype=float), t.shape)
    ph = 2 * np.pi * np.cumsum(f) / RATE
    if shape == "sine":
        w = np.sin(ph)
    elif shape == "square":  # softened square: a few odd harmonics
        w = np.sin(ph) + np.sin(3 * ph) / 3 + np.sin(5 * ph) / 5
        w *= 0.8
    elif shape == "tri":
        w = 2 / np.pi * np.arcsin(np.sin(ph))
    elif shape == "saw":
        w = sum(np.sin(k * ph) / k for k in range(1, 7)) * 0.6
    return w * vol


def noise(dur, vol=1.0):
    return rng.uniform(-1, 1, int(RATE * dur)) * vol


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, delay):
    return np.concatenate([np.zeros(int(RATE * delay)), x])


def note(name):
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semis = names[name[0]] + (1 if "#" in name else 0) + 12 * (int(name[-1]) - 4)
    return 440.0 * 2 ** (semis / 12)


def save(name, x, peak=0.8):
    x = np.asarray(x, dtype=float)
    fade = min(len(x), int(RATE * 0.006))
    x[-fade:] *= np.linspace(1, 0, fade)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)





def ln(a, b, d):
    return np.linspace(a, b, int(RATE * d))


# Throw: a short airy whoosh.
d = 0.16
n = int(RATE * d)
save("throw", mix(lowpass(highpass(noise(d), 900), 4000) * env(n, 0.03, 0.12),
                  tone(ln(500, 900, d), d, "sine", 0.15) * env(n, 0.01, 0.1)), peak=0.35)

# Thunk: the pin goes into the branches.
d = 0.14
n = int(RATE * d)
save("thunk", mix(tone(ln(220, 120, d), d) * env(n, 0.002, 0.08),
                  lowpass(noise(d), 1400) * env(n, 0.001, 0.03) * 0.6), peak=0.55)

# Clash: two glass ornaments hit.
d = 0.45
n = int(RATE * d)
save("clash", mix(*[tone(f, d, "sine", 0.6) * env(n, 0.001, 0.25 + 0.05 * i) for i, f in enumerate([1250, 1870, 2630, 3310])],
                  highpass(noise(0.06), 3000) * env(int(RATE * 0.06), 0.001, 0.03)), peak=0.55)

# Candy: two quick happy notes.
d = 0.09
n = int(RATE * d)
save("candy", mix(tone(note("E6"), d, "tri") * env(n, 0.002, 0.08),
                  at(tone(note("A6"), d * 1.5, "tri") * env(int(n * 1.5), 0.002, 0.12), 0.07)), peak=0.4)

# Star: a sparkly chime.
parts = [at(tone(note(nm), 0.3, "sine") * env(int(RATE * 0.3), 0.002, 0.25), i * 0.05)
         for i, nm in enumerate(["C6", "E6", "G6", "C7"])]
save("star", mix(*parts), peak=0.45)

# Shatter: ice breaks.
d = 0.5
n = int(RATE * d)
save("shatter", mix(highpass(noise(d), 2500) * env(n, 0.001, 0.3),
                    *[at(tone(f, 0.15) * env(int(RATE * 0.15), 0.001, 0.08) * 0.3, dl)
                      for f, dl in [(3100, 0.03), (2500, 0.09), (3700, 0.15), (2900, 0.22)]]), peak=0.5)

# Tier: the finished tier rises onto the tree, an upward arpeggio.
parts = [at(tone(note(nm), 0.22, "tri") * env(int(RATE * 0.22), 0.004, 0.18), i * 0.07)
         for i, nm in enumerate(["G5", "B5", "D6", "G6"])]
save("tier", mix(*parts), peak=0.45)

# Win: a little fanfare with sleigh bells.
seq = [("C5", 0.0), ("E5", 0.12), ("G5", 0.24), ("C6", 0.36), ("G5", 0.56), ("C6", 0.68)]
parts = [at(tone(note(nm), 0.35, "square", 0.5) * env(int(RATE * 0.35), 0.005, 0.3), dl) for nm, dl in seq]
bells = [at(highpass(noise(0.05), 5000) * env(int(RATE * 0.05), 0.001, 0.03) * 0.4, k * 0.09) for k in range(10)]
save("win", lowpass(mix(*parts, *bells), 6000), peak=0.5)

# Fail: a sad downward slide.
d = 0.6
n = int(RATE * d)
save("fail", lowpass(tone(ln(440, 180, d), d, "square") * env(n, 0.01, 0.5), 2500), peak=0.4)

# Phase: the boss gets angry.
d = 0.5
n = int(RATE * d)
save("phase", mix(tone(ln(110, 70, d), d, "saw") * env(n, 0.01, 0.4),
                  lowpass(noise(d), 600) * env(n, 0.01, 0.3) * 0.8), peak=0.55)

# Click: UI.
d = 0.04
n = int(RATE * d)
save("click", tone(1500, d) * env(n, 0.001, 0.015) + tone(750, d) * env(n, 0.001, 0.02) * 0.5, peak=0.3)

# Booster: a magic shimmer.
d = 0.4
n = int(RATE * d)
save("booster", mix(tone(ln(600, 1800, d), d, "sine") * env(n, 0.01, 0.3),
                    tone(ln(900, 2700, d), d, "sine", 0.4) * env(n, 0.01, 0.3)), peak=0.4)

# Shield: a soft bong as the shield takes the hit.
d = 0.35
n = int(RATE * d)
save("shield", mix(tone(520, d) * env(n, 0.002, 0.3), tone(780, d, "sine", 0.5) * env(n, 0.002, 0.2)), peak=0.45)

# Fire: a hot whoosh knocking an ornament off.
d = 0.3
n = int(RATE * d)
save("fire", mix(lowpass(noise(d), 1200) * env(n, 0.005, 0.25), tone(ln(300, 90, d), d) * env(n, 0.002, 0.15) * 0.5), peak=0.5)
