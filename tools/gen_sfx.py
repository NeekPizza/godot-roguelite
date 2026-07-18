#!/usr/bin/env python3
"""Generate the game's retro SFX as 16-bit mono WAVs.

sfxr-style synthesis using only the Python standard library. We generate rather
than download so every sound is our own work — no attribution obligation, no
licence to verify, nothing that can block a commercial release.

Deterministic: the RNG is fixed-seeded, so re-running reproduces the same files
byte for byte. Run from the repo root:

    python3 tools/gen_sfx.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT_DIR = os.path.join("assets", "sfx")


def square(phase):
    return 1.0 if (phase % 1.0) < 0.5 else -1.0


def saw(phase):
    return 2.0 * (phase % 1.0) - 1.0


def render(duration, fn, volume=0.5):
    """fn(t, progress) -> sample in [-1, 1]."""
    total = int(RATE * duration)
    out = []
    for i in range(total):
        t = i / RATE
        progress = i / total
        out.append(fn(t, progress) * volume)
    return out


def envelope(progress, attack=0.01, release=0.6):
    if progress < attack:
        return progress / attack
    tail = (progress - attack) / max(1e-6, 1.0 - attack)
    return math.pow(max(0.0, 1.0 - tail), release * 6.0)


def noise(rng):
    return rng.uniform(-1.0, 1.0)


def write_wav(name, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    frames = bytearray()
    for sample in samples:
        clipped = max(-1.0, min(1.0, sample))
        frames += struct.pack("<h", int(clipped * 32767))
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(bytes(frames))
    print("wrote %s (%d frames)" % (path, len(samples)))


def main():
    rng = random.Random(20260718)

    # shoot: short descending square blip
    def shoot(t, p):
        freq = 880.0 * (1.0 - 0.55 * p)
        return square(t * freq) * envelope(p, 0.005, 0.9)

    write_wav("shoot", render(0.08, shoot, 0.22))

    # hit: tight noise tick
    def hit(t, p):
        return noise(rng) * envelope(p, 0.002, 1.4)

    write_wav("hit", render(0.05, hit, 0.30))

    # enemy_death: noise burst plus a falling tone
    def enemy_death(t, p):
        tone = saw(t * 420.0 * (1.0 - 0.6 * p))
        return (noise(rng) * 0.6 + tone * 0.4) * envelope(p, 0.005, 0.8)

    write_wav("enemy_death", render(0.18, enemy_death, 0.32))

    # xp_pickup: quick rising sine blip
    def xp_pickup(t, p):
        freq = 620.0 + 480.0 * p
        return math.sin(TAU * t * freq) * envelope(p, 0.01, 1.1)

    write_wav("xp_pickup", render(0.07, xp_pickup, 0.20))

    # level_up: three-note rising arpeggio
    def level_up(t, p):
        notes = [523.25, 659.25, 783.99]
        index = min(len(notes) - 1, int(p * len(notes)))
        local = (p * len(notes)) % 1.0
        return square(t * notes[index]) * envelope(local, 0.02, 1.0)

    write_wav("level_up", render(0.42, level_up, 0.24))

    # player_hurt: low descending square with noise grit
    def player_hurt(t, p):
        freq = 320.0 * (1.0 - 0.5 * p)
        return (square(t * freq) * 0.7 + noise(rng) * 0.3) * envelope(p, 0.005, 0.7)

    write_wav("player_hurt", render(0.25, player_hurt, 0.34))

    # run_over: long descending tone
    def run_over(t, p):
        freq = 440.0 * (1.0 - 0.62 * p)
        return (saw(t * freq) * 0.5 + math.sin(TAU * t * freq) * 0.5) * envelope(p, 0.02, 0.5)

    write_wav("run_over", render(0.9, run_over, 0.30))


TAU = math.pi * 2.0

if __name__ == "__main__":
    main()
