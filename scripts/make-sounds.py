#!/usr/bin/env python3
"""Renders the chime sounds in Resources/Sounds. Run after changing anything here:

    pip install numpy scipy && scripts/make-sounds.py

Everything is synthesised, so there is nothing to license, and the output is the same on
every run (fixed random seed). Needs ffmpeg for the AAC encoding.

Singing bowl: a Himalayan bowl is a handful of inharmonic modes (about 1 : 2.76 : 5.15 : 8.15 :
11.7 times the fundamental). Each mode is really a pair a hair apart in pitch, which is
where the slow "wah-wah" beating comes from; higher modes beat faster and die sooner. A
felt mallet adds a short soft knock. The left and right channels weight each pair the
other way round, so the beating drifts across the stereo field the way it does in a room.

Marimba: tuned bars have overtones near 4x and 10x the note, gone within a fraction of a
second, over a warm fundamental.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt
from scipy.io import wavfile

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Sounds")
rng = np.random.default_rng(20261006)


def seconds(n):
    return np.arange(int(n * RATE)) / RATE


def room(stereo, wet=0.16, length=1.6):
    """A soft room: convolution with decaying noise, a little longer on the right."""
    out = np.empty_like(stereo)
    for ch in range(2):
        t = seconds(length + 0.07 * ch)
        ir = rng.standard_normal(t.size) * np.exp(-t / (length / 6.9))
        ir = sosfilt(butter(2, 5000, "low", fs=RATE, output="sos"), ir)
        ir /= np.sqrt(np.sum(ir ** 2))
        out[:, ch] = stereo[:, ch] + wet * fftconvolve(stereo[:, ch], ir)[: stereo.shape[0]]
    return out


# MARK: Singing bowl

# (frequency ratio, level, decay time constant in seconds, beat rate in Hz)
BOWL_MODES = [
    (1.000, 1.00, 1.00, 0.70),
    (2.760, 0.48, 0.62, 1.85),
    (5.150, 0.20, 0.36, 2.90),
    (8.150, 0.09, 0.22, 3.70),
    (11.70, 0.04, 0.14, 4.60),
]


def bowl_strike(fundamental, ring, total, strength=1.0):
    """One mallet strike. `ring` scales every mode's decay (seconds of the fundamental)."""
    t = seconds(total)
    out = np.zeros((t.size, 2))
    attack = np.minimum(1, t / 0.006)
    for ratio, level, decay, beat in BOWL_MODES:
        f = fundamental * ratio
        if f > RATE * 0.45:
            continue
        # Each strike lands a little differently on the rim.
        level *= rng.uniform(0.85, 1.15) * strength ** (1 + 0.6 * (ratio > 2))
        env = attack * np.exp(-t / (ring * decay))
        phase_a, phase_b = rng.uniform(0, 2 * np.pi, 2)
        a = np.sin(2 * np.pi * (f - beat / 2) * t + phase_a)
        b = np.sin(2 * np.pi * (f + beat / 2) * t + phase_b)
        out[:, 0] += level * env * (0.6 * a + 0.4 * b)
        out[:, 1] += level * env * (0.4 * a + 0.6 * b)
    # The felt mallet's knock: 20 ms of soft, band-limited noise.
    knock_t = seconds(0.02)
    knock = rng.standard_normal(knock_t.size) * np.exp(-knock_t / 0.004)
    knock = sosfilt(butter(2, [300, 2500], "bandpass", fs=RATE, output="sos"), knock)
    knock *= 0.05 * strength / np.max(np.abs(knock))
    out[: knock.size, 0] += knock
    out[: knock.size, 1] += knock
    return out


def singing_bowl_zero():
    """Three strikes, about ten seconds apart but not on a grid, each a touch different."""
    strikes = [(0.0, 1.0), (9.4, 0.84), (19.7, 0.92)]
    total = 36.0
    mix = np.zeros((int(total * RATE), 2))
    for start, strength in strikes:
        strike = bowl_strike(196.0, ring=4.2, total=total - start, strength=strength)
        i = int(start * RATE)
        mix[i : i + strike.shape[0]] += strike
    return fade_out(room(mix), 4.0)


def singing_bowl_warning():
    """A small, higher bowl, struck lightly once."""
    return fade_out(room(bowl_strike(523.0, ring=1.7, total=9.0, strength=0.75)), 2.0)


# MARK: Marimba

def marimba_note(freq, total, level=1.0):
    t = seconds(total)
    attack = np.minimum(1, t / 0.0015)
    body = 0.55 * (440 / freq) ** 0.5
    partials = [(1.0, 1.0, body), (3.93, 0.32, body * 0.22), (9.86, 0.09, body * 0.06)]
    mono = np.zeros(t.size)
    for ratio, amp, decay in partials:
        if freq * ratio < RATE * 0.45:
            mono += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / decay)
    mono *= attack * level
    return np.column_stack([mono, mono])


def sequence(notes, total):
    """notes: (start seconds, frequency, level, pan -1...1)"""
    mix = np.zeros((int(total * RATE), 2))
    for start, freq, level, pan in notes:
        note = marimba_note(freq, total - start, level)
        note[:, 0] *= np.sqrt((1 - pan) / 2) * np.sqrt(2)
        note[:, 1] *= np.sqrt((1 + pan) / 2) * np.sqrt(2)
        i = int(start * RATE)
        mix[i : i + note.shape[0]] += note
    return mix


C5, E5, G5, C6 = 523.25, 659.26, 783.99, 1046.50


def marimba_zero():
    """C–E–G–C up, twice, the top note held a little stronger."""
    run = [(0.00, C5, 0.8, -0.3), (0.15, E5, 0.8, -0.1), (0.30, G5, 0.85, 0.1), (0.45, C6, 1.0, 0.3)]
    notes = run + [(start + 1.6, f, level * 0.9, pan) for start, f, level, pan in run]
    return fade_out(room(sequence(notes, 4.5), wet=0.12, length=1.0), 0.8)


def marimba_warning():
    """A soft two-note "ding-dong"."""
    return fade_out(room(sequence([(0.0, E5, 0.8, -0.15), (0.22, C5, 0.75, 0.15)], 2.6), wet=0.12, length=1.0), 0.6)


# MARK: Output

def fade_out(stereo, length):
    n = int(length * RATE)
    stereo[-n:] *= np.linspace(1, 0, n)[:, None] ** 2
    return stereo


def write(name, stereo, peak_db):
    stereo = stereo * (10 ** (peak_db / 20) / np.max(np.abs(stereo)))
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        wavfile.write(wav, RATE, (stereo * 32767).astype(np.int16))
        target = os.path.join(OUT, name + ".m4a")
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "aac", "-b:a", "160k", target],
            check=True,
        )
    print(f"{name}.m4a  {stereo.shape[0] / RATE:.1f}s")


if __name__ == "__main__":
    write("singing-bowl-zero", singing_bowl_zero(), -1.5)
    write("singing-bowl-warning", singing_bowl_warning(), -7)
    write("marimba-zero", marimba_zero(), -1.5)
    write("marimba-warning", marimba_warning(), -6)
    sys.exit(0)
