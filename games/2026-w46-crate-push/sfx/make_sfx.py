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


# Kip's wheels: a soft, short tick.
d = 0.06
n = int(RATE * d)
save("step", mix(
    tone(np.linspace(260, 170, n), d) * env(n, 0.002, 0.03),
    lowpass(noise(d), 2500) * env(n, 0.001, 0.015) * 0.5,
), peak=0.35)

# A crate scraping one cell: low thud plus gritty scrape.
d = 0.16
n = int(RATE * d)
save("push", mix(
    tone(np.linspace(110, 60, n), d) * env(n, 0.003, 0.08),
    lowpass(noise(d), 900) * env(n, 0.01, 0.12) * 1.6,
), peak=0.6)

# Walking into a wall: dull knock.
d = 0.09
n = int(RATE * d)
save("bump", mix(
    tone(np.linspace(140, 70, n), d) * env(n, 0.001, 0.04),
    lowpass(noise(d), 600) * env(n, 0.001, 0.02) * 0.8,
), peak=0.45)

# A crate lands on its charger: bright two-note chime with a little buzz.
d = 0.5
n = int(RATE * d)
save("charge", mix(
    tone(note("E6"), 0.4) * env(int(RATE * 0.4), 0.003, 0.25),
    at(tone(note("B6"), 0.42) * env(int(RATE * 0.42), 0.003, 0.3), 0.08),
    tone(note("E4"), 0.25, "square", 0.25) * env(int(RATE * 0.25), 0.002, 0.08),
), peak=0.55)

# Room solved: rising arpeggio and a held chord.
parts = []
for i, nm in enumerate(["C5", "E5", "G5", "C6"]):
    dd = 0.5 if i == 3 else 0.22
    parts.append(at(tone(note(nm), dd, "square", 0.6) * env(int(RATE * dd), 0.004, dd * 0.7), i * 0.09))
parts.append(at(tone(note("E6"), 0.5) * env(int(RATE * 0.5), 0.01, 0.4) * 0.5, 0.27))
parts.append(at(tone(note("G6"), 0.5) * env(int(RATE * 0.5), 0.01, 0.4) * 0.4, 0.29))
save("win", lowpass(mix(*parts), 5000), peak=0.6)

# Failed (fire, black hole, out of moves): sad falling wobble.
d = 0.6
n = int(RATE * d)
t = t_axis(d)
f = np.linspace(420, 110, n) * (1 + 0.04 * np.sin(2 * np.pi * 9 * t))
save("fail", lowpass(tone(f, d, "saw") * env(n, 0.01, 0.5), 1800), peak=0.5)

# Undo / restart: quick reverse swish.
d = 0.11
n = int(RATE * d)
save("undo", mix(
    tone(np.linspace(700, 300, n), d, "tri") * env(n, 0.002, 0.07),
    highpass(noise(d), 2000) * env(n, 0.002, 0.05) * 0.25,
), peak=0.35)

# Menu and popup buttons.
d = 0.035
n = int(RATE * d)
save("click", tone(1500, d) * env(n, 0.001, 0.015) + tone(750, d) * env(n, 0.001, 0.02) * 0.5, peak=0.3)

# Teleporter: rising warble.
d = 0.3
n = int(RATE * d)
t = t_axis(d)
f = np.geomspace(250, 1400, n) * (1 + 0.15 * np.sin(2 * np.pi * 30 * t))
save("teleport", tone(f, d, "tri") * env(n, 0.01, 0.25), peak=0.4)

# Key or clock picked up: two quick high notes.
save("pickup", mix(
    tone(note("A5"), 0.08, "square", 0.6) * env(int(RATE * 0.08), 0.002, 0.06),
    at(tone(note("E6"), 0.16, "square", 0.6) * env(int(RATE * 0.16), 0.002, 0.12), 0.07),
), peak=0.4)

# Door unlocks: metal clunk.
d = 0.22
n = int(RATE * d)
save("door", mix(
    tone(np.linspace(180, 120, n), d, "square", 0.5) * env(n, 0.002, 0.1),
    at(tone(1800, 0.03) * env(int(RATE * 0.03), 0.001, 0.01) * 0.6, 0.0),
    at(lowpass(noise(0.08), 1500) * env(int(RATE * 0.08), 0.001, 0.04), 0.06),
), peak=0.5)

# Cracked floor gives way: crumbly rumble.
d = 0.35
n = int(RATE * d)
grit = lowpass(noise(d), 700) * env(n, 0.005, 0.3)
grit *= 0.6 + 0.4 * (rng.uniform(0, 1, n) > 0.7)
save("crumble", grit, peak=0.45)

# A tool is used or armed: sparkly upward sweep.
d = 0.22
n = int(RATE * d)
save("tool", mix(
    tone(np.geomspace(500, 1600, n), d, "sine") * env(n, 0.005, 0.18),
    tone(np.geomspace(1000, 3200, n), d, "sine") * env(n, 0.005, 0.12) * 0.3,
), peak=0.4)

print("wrote", sorted(f for f in os.listdir(OUT) if f.endswith(".wav")))
