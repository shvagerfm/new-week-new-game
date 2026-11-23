"""Synthesizes the game's sound effects into WAV files next to this script.

Run: python3 sfx/make_sfx.py   (needs numpy)
Also writes music.wav, a 15-second loop the game speeds up as the run gets faster.

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




# Jump: a quick upward blip.
d = 0.12
n = int(RATE * d)
save("jump", mix(
    tone(np.geomspace(300, 820, n), d, "square", 0.6) * env(n, 0.002, 0.08),
    highpass(noise(d), 3000) * env(n, 0.001, 0.03) * 0.2,
), peak=0.35)

# Landing on a roof: soft thump with grit.
d = 0.12
n = int(RATE * d)
save("land", mix(
    tone(np.linspace(150, 60, n), d) * env(n, 0.001, 0.05),
    lowpass(noise(d), 1200) * env(n, 0.001, 0.04) * 0.9,
), peak=0.5)

# Edge landing: a bright chime; the game raises its pitch as the combo grows.
d = 0.35
n = int(RATE * d)
save("edge", mix(
    tone(note("E6"), d, "square", 0.5) * env(n, 0.002, 0.18),
    at(tone(note("B6"), 0.28) * env(int(RATE * 0.28), 0.002, 0.2), 0.05),
    highpass(noise(0.06), 4000) * env(int(RATE * 0.06), 0.001, 0.02) * 0.3,
), peak=0.45)

# The combo is lost: short falling two notes.
save("combo_lost", lowpass(mix(
    tone(note("E5"), 0.08, "tri") * env(int(RATE * 0.08), 0.002, 0.06),
    at(tone(note("B4"), 0.14, "tri") * env(int(RATE * 0.14), 0.002, 0.1), 0.07),
), 3000), peak=0.25)

# Parcel picked up: coin-like double ping.
save("parcel", mix(
    tone(note("B5"), 0.07, "square", 0.6) * env(int(RATE * 0.07), 0.002, 0.05),
    at(tone(note("E6"), 0.2, "square", 0.6) * env(int(RATE * 0.2), 0.002, 0.15), 0.06),
), peak=0.38)

# A roof starts to crumble: rattling rumble.
d = 0.45
n = int(RATE * d)
grit = lowpass(noise(d), 600) * env(n, 0.005, 0.4)
grit *= 0.5 + 0.5 * (rng.uniform(0, 1, n) > 0.6)
save("crumble", mix(grit, tone(np.linspace(90, 50, n), d) * env(n, 0.01, 0.3) * 0.6), peak=0.5)

# Hitting an obstacle: crunchy knock and a falling buzz.
d = 0.4
n = int(RATE * d)
save("hit", mix(
    lowpass(noise(0.08), 2500) * env(int(RATE * 0.08), 0.001, 0.04) * 1.2,
    tone(np.linspace(220, 55, n), d, "saw", 0.7) * env(n, 0.002, 0.3),
), peak=0.55)

# Falling between buildings: a long descending whistle.
d = 0.8
n = int(RATE * d)
save("fall", mix(
    tone(np.geomspace(1100, 180, n), d, "tri") * env(n, 0.02, 0.7),
    lowpass(noise(d), 500) * env(n, 0.3, 0.6) * 0.4,
), peak=0.4)

# Passing the record: rising arpeggio.
parts = []
for i, nm in enumerate(["C5", "E5", "G5", "C6", "E6"]):
    dd = 0.4 if i == 4 else 0.14
    parts.append(at(tone(note(nm), dd, "square", 0.6) * env(int(RATE * dd), 0.003, dd * 0.7), i * 0.07))
save("best", lowpass(mix(*parts), 5000), peak=0.5)

# Menu and screen buttons.
d = 0.035
n = int(RATE * d)
save("click", tone(1500, d) * env(n, 0.001, 0.015) + tone(750, d) * env(n, 0.001, 0.02) * 0.5, peak=0.3)


# --- Music: an 8-bar night-drive loop at 128 bpm in A minor. -------------
# Notes that ring past the end wrap around to the start, so the loop is seamless.
BPM = 128
BEAT = 60 / BPM
BARS = 8
LOOP = int(RATE * BEAT * 4 * BARS)
song = np.zeros(LOOP)


def put(x, start):
    i = int(RATE * start) % LOOP
    while len(x):
        k = min(len(x), LOOP - i)
        song[i:i + k] += x[:k]
        x = x[k:]
        i = 0


chords = [("A2", ["A4", "C5", "E5"]), ("F2", ["F4", "A4", "C5"]),
          ("C3", ["C5", "E5", "G5"]), ("G2", ["G4", "B4", "D5"])]
for bar in range(BARS):
    root, triad = chords[bar % 4]
    t0 = bar * 4 * BEAT
    for e in range(8):  # driving eighth-note bass, octave jumps on the off-beats
        f = note(root) * (2 if e % 2 else 1)
        dd = BEAT / 2
        put(lowpass(tone(f, dd, "saw", 0.5), 900) * env(int(RATE * dd), 0.004, dd * 0.8), t0 + e * dd)
    for b in range(4):  # kick on every beat
        dd = 0.18
        k = int(RATE * dd)
        put(tone(np.geomspace(140, 45, k), dd) * env(k, 0.001, 0.12) * 1.2, t0 + b * BEAT)
    for b in range(4):  # closed hat on the off-beats, snare on 2 and 4
        put(highpass(noise(0.04), 6000) * env(int(RATE * 0.04), 0.001, 0.02) * 0.25, t0 + b * BEAT + BEAT / 2)
        if b % 2 == 1:
            put(mix(lowpass(noise(0.14), 3500) * env(int(RATE * 0.14), 0.001, 0.08) * 0.5,
                    tone(190, 0.08) * env(int(RATE * 0.08), 0.001, 0.05) * 0.4), t0 + b * BEAT)
    # Sixteenth-note arpeggio, only in the second half so the loop builds.
    if bar >= 4:
        seq = triad + [triad[1]]
        for s in range(16):
            dd = BEAT / 4
            put(lowpass(tone(note(seq[s % 4]), dd, "square", 0.22), 3500) * env(int(RATE * dd), 0.002, dd * 0.6),
                t0 + s * dd)
    # Pad chord.
    dd = 4 * BEAT
    for nm in triad:
        put(lowpass(tone(note(nm) / 2, dd, "tri", 0.14), 1500) * env(int(RATE * dd), 0.3, dd * 1.2), t0)

song = song / np.max(np.abs(song)) * 0.7
with wave.open(os.path.join(OUT, "music.wav"), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes((song * 32767).astype("<i2").tobytes())

print("wrote", sorted(f for f in os.listdir(OUT) if f.endswith(".wav")))
