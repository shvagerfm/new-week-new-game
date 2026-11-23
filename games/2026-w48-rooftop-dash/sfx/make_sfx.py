"""Synthesizes the game's sound effects into WAV files next to this script.

Run: python3 sfx/make_sfx.py   (needs numpy)
Also writes the music: an 8-bar loop split into three stems (music_base.wav,
music_drums.wav, music_lead.wav) that the game fades in one by one as the run
gets faster.

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

# Parcel picked up: a soft round "bloop" into a small bell. Pure sines, no
# buzz; the game raises the pitch along a scale for parcels in a row.
d = 0.09
n = int(RATE * d)
bloop = tone(np.geomspace(420, 880, n), d) * env(n, 0.003, 0.07)
d2 = 0.32
n2 = int(RATE * d2)
bell = (tone(note("E6"), d2) + tone(note("E6") * 2, d2) * 0.25 + tone(note("B6"), d2) * 0.15) * env(n2, 0.002, 0.22)
save("parcel", mix(bloop * 0.9, at(bell * 0.6, 0.045)), peak=0.34)

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

# Caught in a wire: an electric zap, buzzing and crackling.
d = 0.45
n = int(RATE * d)
buzz = tone(np.linspace(120, 90, n), d, "saw", 0.7) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 31 * t_axis(d))))
crackle = highpass(noise(d), 2500) * (rng.uniform(0, 1, n) > 0.85) * 0.8
save("zap", mix(buzz * env(n, 0.001, 0.35), crackle * env(n, 0.001, 0.25)), peak=0.6)

# Running into an antenna: a metal clang with a ringing tail.
d = 0.6
n = int(RATE * d)
ring = sum(tone(f, d) * env(n, 0.001, dec) * v
           for f, dec, v in [(523, 0.5, 0.6), (1187, 0.35, 0.4), (1873, 0.2, 0.3), (2719, 0.12, 0.2)])
save("clang", mix(ring, lowpass(noise(0.05), 3000) * env(int(RATE * 0.05), 0.001, 0.02) * 0.8), peak=0.6)

# A crumbling roof gives way: a deeper crash of falling rubble.
d = 0.7
n = int(RATE * d)
rubble = lowpass(noise(d), 900) * env(n, 0.003, 0.6)
rubble *= 0.4 + 0.6 * (rng.uniform(0, 1, n) > 0.7)
save("collapse", mix(rubble, tone(np.linspace(70, 35, n), d) * env(n, 0.005, 0.5) * 0.8,
                     at(lowpass(noise(0.15), 1500) * env(int(RATE * 0.15), 0.001, 0.08) * 0.7, 0.12)), peak=0.5)

# A footstep on the roof: a tiny soft tap, played quietly on every stride.
d = 0.05
n = int(RATE * d)
save("step", mix(lowpass(noise(d), 1800) * env(n, 0.001, 0.025),
                 tone(np.linspace(130, 80, n), d) * env(n, 0.001, 0.03) * 0.5), peak=0.3)

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
# It is written as three stems of the same length that the game plays
# together: base (bass, kick, pad) from the start, then drums (hats and
# snare), then lead (arpeggio and a hook) as the run speeds up.
# Notes that ring past the end wrap around to the start, so each loop is seamless.
BPM = 128
BEAT = 60 / BPM
BARS = 8
LOOP = int(RATE * BEAT * 4 * BARS)
stems = {"base": np.zeros(LOOP), "drums": np.zeros(LOOP), "lead": np.zeros(LOOP)}


def put(stem, x, start):
    song = stems[stem]
    i = int(RATE * start) % LOOP
    while len(x):
        k = min(len(x), LOOP - i)
        song[i:i + k] += x[:k]
        x = x[k:]
        i = 0


chords = [("A2", ["A4", "C5", "E5"]), ("F2", ["F4", "A4", "C5"]),
          ("C3", ["C5", "E5", "G5"]), ("G2", ["G4", "B4", "D5"])]
# A short hook over bars 5-8: (beat in the 4-bar phrase, note, length in beats).
hook = [(0, "E5", 1.5), (1.5, "D5", 0.5), (2, "C5", 1), (3, "E5", 1),
        (4, "F5", 1.5), (5.5, "E5", 0.5), (6, "C5", 2),
        (8, "G5", 1.5), (9.5, "E5", 0.5), (10, "D5", 1), (11, "C5", 1),
        (12, "B4", 1.5), (13.5, "C5", 0.5), (14, "D5", 2)]
for bar in range(BARS):
    root, triad = chords[bar % 4]
    t0 = bar * 4 * BEAT
    for e in range(8):  # driving eighth-note bass, octave jumps on the off-beats
        f = note(root) * (2 if e % 2 else 1)
        dd = BEAT / 2
        put("base", lowpass(tone(f, dd, "saw", 0.5), 900) * env(int(RATE * dd), 0.004, dd * 0.8), t0 + e * dd)
    for b in range(4):  # kick on every beat
        dd = 0.18
        k = int(RATE * dd)
        put("base", tone(np.geomspace(140, 45, k), dd) * env(k, 0.001, 0.12) * 1.2, t0 + b * BEAT)
    for s16 in range(16):  # hats: open on the off-beats, quiet ticks between
        dd = 0.04
        v = 0.25 if s16 % 4 == 2 else 0.08
        put("drums", highpass(noise(dd), 6000) * env(int(RATE * dd), 0.001, 0.02) * v, t0 + s16 * BEAT / 4)
    for b in (1, 3):  # snare on 2 and 4
        put("drums", mix(lowpass(noise(0.14), 3500) * env(int(RATE * 0.14), 0.001, 0.08) * 0.5,
                         tone(190, 0.08) * env(int(RATE * 0.08), 0.001, 0.05) * 0.4), t0 + b * BEAT)
    seq = triad + [triad[1]]
    for s16 in range(16):  # sixteenth-note arpeggio
        dd = BEAT / 4
        put("lead", lowpass(tone(note(seq[s16 % 4]), dd, "square", 0.2), 3500) * env(int(RATE * dd), 0.002, dd * 0.6),
            t0 + s16 * dd)
    dd = 4 * BEAT  # pad chord
    for nm in triad:
        put("base", lowpass(tone(note(nm) / 2, dd, "tri", 0.14), 1500) * env(int(RATE * dd), 0.3, dd * 1.2), t0)
for half in (16,):
    for beat, nm, length in hook:
        dd = length * BEAT
        put("lead", lowpass(tone(note(nm), dd, "tri", 0.35), 2500) * env(int(RATE * dd), 0.01, dd * 0.9),
            (half + beat) * BEAT)

# One gain for all stems, so they keep their balance when mixed.
gain = 0.75 / np.max(np.abs(sum(stems.values())))
for name, song in stems.items():
    with wave.open(os.path.join(OUT, "music_%s.wav" % name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((song * gain * 32767).astype("<i2").tobytes())


# --- Newer obstacles (kept after the music so the older sounds don't change) --

# Through a skylight: a bright glass smash with tinkling shards.
d = 0.7
n = int(RATE * d)
smash = highpass(noise(0.12), 3000) * env(int(RATE * 0.12), 0.001, 0.08)
bits = []
for k in range(9):
    dd = 0.12
    bits.append(at(tone(rng.uniform(2500, 5200), dd) * env(int(RATE * dd), 0.001, 0.06) * rng.uniform(0.3, 0.6),
                   0.05 + k * 0.06))
tinkle = mix(*bits)
save("glass", mix(smash, tinkle, tone(np.linspace(160, 70, n), d) * env(n, 0.002, 0.2) * 0.4), peak=0.5)

# Into a bat: two quick high squeaks.
parts = []
for i, f0 in enumerate([2600, 3100]):
    dd = 0.07
    k = int(RATE * dd)
    parts.append(at(tone(np.linspace(f0, f0 * 1.3, k), dd, "tri") * env(k, 0.002, 0.05), i * 0.09))
save("squeak", mix(*parts, lowpass(noise(0.1), 1500) * env(int(RATE * 0.1), 0.001, 0.05) * 0.5), peak=0.42)

# Into the laundry: a soft cloth flap and a thump.
d = 0.35
n = int(RATE * d)
flap = lowpass(noise(d), 1200) * env(n, 0.01, 0.25) * (0.6 + 0.4 * np.sin(2 * np.pi * 18 * t_axis(d)))
save("cloth", mix(flap, tone(np.linspace(120, 60, n), d) * env(n, 0.002, 0.12) * 0.6), peak=0.45)

print("wrote", sorted(f for f in os.listdir(OUT) if f.endswith(".wav")))
