#!/usr/bin/env python3
"""Generate the game's synthwave / outrun music loop.

Original work, synthesised from scratch. No sample material, no third-party
track, nothing to licence — we own it outright.

This is a real subtractive synth, not a beep generator. What makes it read as
synthwave rather than chiptune, in rough order of importance:

  1. PolyBLEP band-limited oscillators. A naive saw at 44.1 kHz aliases hard,
     and that aliasing is *exactly* the harsh 8-bit character we are avoiding.
  2. Supersaw lead — 7 detuned voices, spread across the stereo field.
  3. Resonant low-pass filters with per-note cutoff envelopes (block-processed
     biquads), so notes open and close instead of sitting static.
  4. Convolution reverb with a synthesised impulse response.
  5. Sidechain ducking keyed off the kick, so everything pumps under the beat.
  6. Tape-style saturation for warmth and glue.

Requires the project venv:  .venv/bin/python tools/gen_music.py
Encodes to OGG Vorbis via ffmpeg (Godot loops OGG gaplessly; MP3 cannot,
because its encoder delay/padding inserts silence at the seam).
"""

import math
import os
import subprocess
import sys

import numpy as np
from scipy import signal

# --- Format ------------------------------------------------------------------
SR = 44100
BPM = 112.0
BEAT = 60.0 / BPM
BAR = BEAT * 4.0
BARS = 40                       # 40 bars @ 112 BPM = 85.7 s
LOOP_N = int(round(BARS * BAR * SR))
TOTAL = LOOP_N * 2              # two loops; we keep the second (see below)

# Intermediate audition file. Deliberately OUTSIDE assets/ so Godot does not
# import it as a second copy of the track; only the .ogg ships.
WAV_PATH = os.path.join("build", "synthwave_loop.wav")
OGG_PATH = os.path.join("assets", "music", "synthwave_loop.ogg")

rng = np.random.default_rng(20260718)

# --- Musical material --------------------------------------------------------
# A natural minor, i - VI - III - VII. Two bars per chord, 8-bar cycle.
PROGRESSION = ["Am", "F", "C", "G"]

BASS_CHORDS = {
    "Am": [45, 48, 52], "F": [41, 45, 48],
    "C":  [48, 52, 55], "G": [43, 47, 50],
}
PAD_CHORDS = {
    "Am": [57, 60, 64, 69], "F": [53, 57, 60, 65],
    "C":  [55, 60, 64, 67], "G": [55, 59, 62, 67],
}
ARP_FIGURE = [0, 2, 1, 2, 0, 2, 1, 2, 0, 2, 1, 2, 1, 2, 1, 2]

# 808 figure: (beat, length_in_beats, semitones_from_root, glide_from_semitones).
# Syncopated rather than on-grid, and the last note glides up a fifth — the
# pitch slide is what makes an 808 read as trap rather than as a plain sub.
TRAP_808_PATTERN = [
    (0.00, 1.75, 0, None),
    (1.75, 0.75, 0, -5),
    (2.75, 1.25, 7, 0),
]

LEAD_PHRASE = [
    (0, 0.0, 1.5, 69), (0, 1.5, 0.5, 72), (0, 2.0, 1.0, 76), (0, 3.0, 1.0, 74),
    (1, 0.0, 2.0, 71), (1, 2.0, 2.0, 69),
    (2, 0.0, 1.5, 65), (2, 1.5, 0.5, 69), (2, 2.0, 1.0, 72), (2, 3.0, 1.0, 69),
    (3, 0.0, 2.0, 67), (3, 2.0, 2.0, 65),
    (4, 0.0, 1.5, 76), (4, 1.5, 0.5, 79), (4, 2.0, 1.0, 76), (4, 3.0, 1.0, 72),
    (5, 0.0, 2.0, 74), (5, 2.0, 2.0, 72),
    (6, 0.0, 1.5, 74), (6, 1.5, 0.5, 71), (6, 2.0, 1.0, 67), (6, 3.0, 1.0, 71),
    (7, 0.0, 2.0, 74), (7, 2.0, 2.0, 76),
]
COUNTER_PHRASE = [
    (0, 2.5, 1.0, 84), (1, 1.0, 1.0, 81), (1, 3.0, 1.0, 84),
    (2, 2.5, 1.0, 81), (3, 1.0, 1.0, 77), (3, 3.0, 1.0, 81),
    (4, 2.5, 1.0, 88), (5, 1.0, 1.0, 84), (5, 3.0, 1.0, 88),
    (6, 2.5, 1.0, 86), (7, 1.0, 1.0, 83), (7, 3.0, 1.0, 79),
]


def midi_hz(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


# --- Oscillators -------------------------------------------------------------

def _poly_blep(t, dt):
    """Polynomial band-limited step: rounds the discontinuity that aliases."""
    out = np.zeros_like(t)
    dt = np.broadcast_to(dt, t.shape)   # dt is per-sample (phase increment)
    rising = t < dt
    x = t[rising] / dt[rising]
    out[rising] = x + x - x * x - 1.0
    falling = t > (1.0 - dt)
    x = (t[falling] - 1.0) / dt[falling]
    out[falling] = x * x + x + x + 1.0
    return out


def saw(phase, dt):
    return (2.0 * phase - 1.0) - _poly_blep(phase, dt)


def pulse(phase, dt, width):
    square = np.where(phase < width, 1.0, -1.0)
    shifted = (phase - width) % 1.0
    return square + _poly_blep(phase, dt) - _poly_blep(shifted, dt)


def phase_ramp(freq_hz, n, drift=0.0):
    """Running phase with a touch of slow drift, so voices never lock rigidly."""
    inc = np.full(n, freq_hz / SR)
    if drift > 0.0:
        t = np.arange(n) / SR
        inc *= 1.0 + drift * np.sin(2.0 * np.pi * (0.7 + rng.random()) * t)
    return np.cumsum(inc) % 1.0, inc


# --- Filter ------------------------------------------------------------------

def resonant_lowpass(x, cutoff_start, cutoff_end, q, block=256):
    """Time-varying resonant low-pass, RBJ biquad re-tuned every block.

    Block processing rather than per-sample: it keeps the sweep smooth to the
    ear while staying vectorised, and carries filter state across boundaries so
    there are no discontinuities.
    """
    n = len(x)
    out = np.empty_like(x)
    zi = np.zeros(2)
    positions = range(0, n, block)
    for start in positions:
        end = min(start + block, n)
        progress = start / max(1, n)
        fc = cutoff_start + (cutoff_end - cutoff_start) * progress
        fc = float(np.clip(fc, 30.0, SR * 0.45))

        w0 = 2.0 * math.pi * fc / SR
        alpha = math.sin(w0) / (2.0 * max(0.5, q))
        cos_w0 = math.cos(w0)
        b = np.array([(1.0 - cos_w0) / 2.0, 1.0 - cos_w0, (1.0 - cos_w0) / 2.0])
        a = np.array([1.0 + alpha, -2.0 * cos_w0, 1.0 - alpha])
        b /= a[0]
        a = a / a[0]
        out[start:end], zi = signal.lfilter(b, a, x[start:end], zi=zi)
    return out


def resonant_lowpass_mod(x, cutoff_curve, q, block=128):
    """Low-pass whose cutoff follows an arbitrary curve, re-tuned every block.

    The wobble bass needs cutoff modulated by an LFO rather than a straight
    line, so this takes a full-length curve instead of start/end values. Smaller
    block than the static version: a fast wobble needs finer time resolution or
    it turns into audible steps.
    """
    n = len(x)
    out = np.empty_like(x)
    zi = np.zeros(2)
    for start in range(0, n, block):
        end = min(start + block, n)
        fc = float(np.clip(cutoff_curve[start], 30.0, SR * 0.45))
        w0 = 2.0 * math.pi * fc / SR
        alpha = math.sin(w0) / (2.0 * max(0.5, q))
        cos_w0 = math.cos(w0)
        b = np.array([(1.0 - cos_w0) / 2.0, 1.0 - cos_w0, (1.0 - cos_w0) / 2.0])
        a = np.array([1.0 + alpha, -2.0 * cos_w0, 1.0 - alpha])
        b /= a[0]
        a = a / a[0]
        out[start:end], zi = signal.lfilter(b, a, x[start:end], zi=zi)
    return out


# --- Buses -------------------------------------------------------------------
mix = np.zeros((2, TOTAL), dtype=np.float64)
send = np.zeros(TOTAL, dtype=np.float64)     # reverb send
kick_positions = []


def add(buffer_index, start, data, gain=1.0):
    end = start + len(data)
    if start >= TOTAL:
        return
    if end > TOTAL:
        data = data[:TOTAL - start]
        end = TOTAL
    mix[buffer_index, start:end] += data * gain


def add_send(start, data, gain):
    end = min(start + len(data), TOTAL)
    if start < TOTAL:
        send[start:end] += data[:end - start] * gain


def env_ad(n, attack, release, curve=0.35):
    """Attack / sustain / release with a gentle overall decay."""
    e = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    if a < n:
        e[:a] = np.linspace(0.0, 1.0, a)
    if r < n:
        e[-r:] *= np.linspace(1.0, 0.0, r)
    e *= (1.0 - np.linspace(0.0, 1.0, n)) ** curve
    return e


# --- Voices ------------------------------------------------------------------

def supersaw(start, length, freq, amp, voices, detune_cents, cutoff, q,
             pan, send_amount, attack, release, spread=0.0, curve=0.35):
    n = int(length * SR)
    if n <= 0:
        return
    left = np.zeros(n)
    right = np.zeros(n)
    for v in range(voices):
        offset = (v - (voices - 1) / 2.0) / max(1, (voices - 1) / 2.0)
        ratio = 2.0 ** (offset * detune_cents / 1200.0)
        phase, inc = phase_ramp(freq * ratio, n, drift=0.0006)
        # Random start phase per voice: aligned phases sum into a click.
        phase = (phase + rng.random()) % 1.0
        wave = saw(phase, inc)
        # Spread voices across the field; the outer ones sit widest.
        position = np.clip(pan + offset * spread, -1.0, 1.0)
        gl = math.cos((position + 1.0) * math.pi / 4.0)
        gr = math.sin((position + 1.0) * math.pi / 4.0)
        left += wave * gl
        right += wave * gr
    left /= voices
    right /= voices

    e = env_ad(n, attack, release, curve)
    left = resonant_lowpass(left, cutoff[0], cutoff[1], q) * e * amp
    right = resonant_lowpass(right, cutoff[0], cutoff[1], q) * e * amp

    add(0, start, left)
    add(1, start, right)
    if send_amount > 0.0:
        add_send(start, (left + right) * 0.5, send_amount)


def pulse_voice(start, length, freq, amp, width, cutoff, q, pan,
                send_amount, attack, release):
    n = int(length * SR)
    if n <= 0:
        return
    phase, inc = phase_ramp(freq, n, drift=0.0004)
    wave = pulse(phase, inc, width)
    e = env_ad(n, attack, release)
    body = resonant_lowpass(wave, cutoff[0], cutoff[1], q) * e * amp
    gl = math.cos((pan + 1.0) * math.pi / 4.0)
    gr = math.sin((pan + 1.0) * math.pi / 4.0)
    add(0, start, body, gl)
    add(1, start, body, gr)
    if send_amount > 0.0:
        add_send(start, body, send_amount)


def sub_bass(start, length, freq, amp=0.30):
    """Pure sine an octave under the arp. Carries the weight the saw bass
    cannot: a filtered saw has little energy below ~60 Hz once the resonant
    low-pass has done its work."""
    n = int(length * SR)
    if n <= 0:
        return
    t = np.arange(n) / SR
    wave = np.sin(2.0 * np.pi * freq * t)
    e = env_ad(n, 0.012, 0.05, curve=0.10)
    body = wave * e * amp
    add(0, start, body)
    add(1, start, body)


def bass_808(start, length, freq, amp=0.55, glide_from=None,
             glide_time=0.085, drive=1.7):
    """808-style sub: a sine with a pitch glide, a long exponential tail, and
    just enough saturation to be audible on speakers with no low end.

    This replaces the earlier Reese wobble. A wobble's character comes from
    fast filter movement, which reads as aggressive by design; an 808 carries
    the same low-end weight through sustain and glide instead, which sits far
    better under gameplay audio.
    """
    n = int(length * SR)
    if n <= 0:
        return
    t = np.arange(n) / SR

    if glide_from is not None and glide_from > 0.0:
        # Glide in pitch (log) space, not linear Hz, so it sounds even.
        progress = np.minimum(t / glide_time, 1.0)
        freq_curve = glide_from * (freq / glide_from) ** progress
    else:
        freq_curve = np.full(n, freq)

    wave = np.sin(2.0 * np.pi * np.cumsum(freq_curve) / SR)

    env = np.exp(-t * (2.4 / max(0.15, length)))
    attack = max(1, int(0.006 * SR))
    env[:attack] *= np.linspace(0.0, 1.0, attack)
    tail = max(1, int(0.025 * SR))
    env[-tail:] *= np.linspace(1.0, 0.0, tail)   # no click at note end

    body = np.tanh(wave * drive) / math.tanh(drive)
    # Keep it round: the saturation's upper harmonics would otherwise clutter
    # the same midrange the shoot/hit SFX live in.
    b, a = signal.butter(2, 320 / (SR / 2), btype="low")
    body = signal.lfilter(b, a, body) * env * amp

    add(0, start, body)
    add(1, start, body)


def kick(start):
    n = int(0.30 * SR)
    t = np.arange(n) / SR
    freq = 48.0 + 82.0 * np.exp(-t * 42.0)      # sweep 130 Hz -> 48 Hz
    body = np.sin(2.0 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 14.0)
    click = rng.uniform(-1.0, 1.0, n) * np.exp(-t * 500.0) * 0.30
    out = np.tanh((body + click) * 1.4) * 0.92  # saturate for punch
    add(0, start, out)
    add(1, start, out)
    kick_positions.append(start)


def snare(start):
    n = int(0.26 * SR)
    t = np.arange(n) / SR
    noise = rng.uniform(-1.0, 1.0, n)
    b, a = signal.butter(2, [220 / (SR / 2), 7200 / (SR / 2)], btype="band")
    noise = signal.lfilter(b, a, noise)
    tone = np.sin(2.0 * np.pi * 190.0 * t) * 0.45
    out = (noise * 0.9 + tone) * np.exp(-t * 19.0) * 0.44
    add(0, start, out, 0.97)
    add(1, start, out, 1.0)
    add_send(start, out, 0.42)


def hat(start, open_hat=False, velocity=1.0):
    n = int((0.16 if open_hat else 0.040) * SR)
    t = np.arange(n) / SR
    noise = rng.uniform(-1.0, 1.0, n)
    b, a = signal.butter(2, 7000 / (SR / 2), btype="high")
    noise = signal.lfilter(b, a, noise)
    out = noise * np.exp(-t * (22.0 if open_hat else 85.0))
    out *= (0.13 if open_hat else 0.10) * velocity
    add(0, start, out, 0.82)
    add(1, start, out, 1.0)
    if open_hat:
        add_send(start, out, 0.25)


def trap_hats(base, roll=False):
    """16th-note hats with accented 8ths, and an optional 32nd-note roll on the
    last beat. The roll is the clearest trap signifier and costs nothing."""
    for step in range(16):
        at = base + int(step * (BEAT / 4.0) * SR)
        if roll and step >= 12:
            continue                      # the roll takes over the last beat
        velocity = 1.0 if step % 4 == 0 else (0.62 if step % 2 == 0 else 0.42)
        hat(at, open_hat=False, velocity=velocity)
    if roll:
        # 8 x 32nd notes swelling into the downbeat.
        for i in range(8):
            at = base + int((3.0 + i * 0.125) * BEAT * SR)
            hat(at, open_hat=False, velocity=0.35 + 0.075 * i)


# --- Arrangement -------------------------------------------------------------

def arrange():
    for bar in range(BARS * 2):
        cycle_bar = bar % 8
        loop_bar = bar % BARS
        chord = PROGRESSION[(bar // 2) % len(PROGRESSION)]
        base = int(round(bar * BAR * SR))

        breakdown = 24 <= loop_bar < 28
        # Trap-flavoured sections: 808 glide bass and 16th hats replace the
        # sustained sub. The intro stays clean synthwave so the low end
        # arriving at bar 12 still lands as a shift rather than the default.
        trap_in = (12 <= loop_bar < 24) or (32 <= loop_bar < 40)
        drums_in = loop_bar >= 4 and not breakdown
        kick_in = loop_bar >= 2 and not breakdown
        lead_in = (8 <= loop_bar < 24) or (28 <= loop_bar < 40)
        counter_in = (16 <= loop_bar < 24) or (32 <= loop_bar < 40)

        # Pads: wide, dark, slow-moving. Opened up during the breakdown.
        if bar % 2 == 0:
            top = 1500.0 if breakdown else 900.0
            for index, note in enumerate(PAD_CHORDS[chord]):
                supersaw(
                    base, BAR * 2.0, midi_hz(note),
                    amp=0.075, voices=5, detune_cents=22.0,
                    cutoff=(480.0, top), q=1.0,
                    pan=-0.6 + 0.4 * index, send_amount=0.34,
                    attack=0.45, release=0.6, spread=0.35, curve=0.12,
                )

        root = BASS_CHORDS[chord][0] - 12
        if trap_in:
            # 808 pattern: syncopated, with glides into the offbeat notes.
            for beat, length, semitones, glide in TRAP_808_PATTERN:
                target = midi_hz(root + semitones)
                supply = midi_hz(root + glide) if glide is not None else None
                bass_808(
                    base + int(beat * BEAT * SR), length * BEAT,
                    target, amp=0.52, glide_from=supply,
                )
        elif loop_bar >= 2:
            # Sustained sub elsewhere, so the low end never fully disappears.
            sub_bass(base, BAR * 0.98, midi_hz(root),
                     amp=0.20 if breakdown else 0.32)

        # Bass arp: the engine. Short, resonant, filter closing on each note.
        voicing = BASS_CHORDS[chord]
        for step in range(16):
            note = voicing[ARP_FIGURE[step] % len(voicing)]
            if step % 4 == 0:
                note -= 12
            start = base + int(step * (BEAT / 4.0) * SR)
            supersaw(
                start, BEAT / 4.0 * 0.95, midi_hz(note),
                amp=0.19, voices=3, detune_cents=9.0,
                cutoff=(2400.0, 620.0), q=3.2,
                pan=0.0, send_amount=0.04,
                attack=0.003, release=0.02, spread=0.10, curve=0.5,
            )

        # Lead: 7-voice supersaw, wide, opening filter, heavy delay send.
        if lead_in:
            for phrase_bar, beat, length, note in LEAD_PHRASE:
                if phrase_bar != cycle_bar:
                    continue
                supersaw(
                    base + int(beat * BEAT * SR), length * BEAT * 0.96,
                    midi_hz(note),
                    amp=0.17, voices=7, detune_cents=26.0,
                    cutoff=(1400.0, 3800.0), q=1.8,
                    pan=-0.12, send_amount=0.38,
                    attack=0.025, release=0.16, spread=0.55, curve=0.18,
                )

        # Counter-melody: narrow pulse above the lead.
        if counter_in:
            for phrase_bar, beat, length, note in COUNTER_PHRASE:
                if phrase_bar != cycle_bar:
                    continue
                pulse_voice(
                    base + int(beat * BEAT * SR), length * BEAT * 0.9,
                    midi_hz(note),
                    amp=0.075, width=0.28,
                    cutoff=(2800.0, 1600.0), q=1.4,
                    pan=0.45, send_amount=0.42,
                    attack=0.012, release=0.12,
                )

        if drums_in and trap_in:
            trap_hats(base, roll=(loop_bar % 4 == 3))

        for beat_index in range(4):
            at = base + int(beat_index * BEAT * SR)
            if kick_in:
                kick(at)
            if drums_in and beat_index in (1, 3):
                snare(at)
            if drums_in:
                hat(at + int(BEAT * 0.5 * SR), open_hat=(beat_index == 3))


# --- Processing --------------------------------------------------------------

def feedback_delay(buf, delay_seconds, feedback):
    """Chunk-wise feedback delay. Each chunk reads the previous one, which has
    already accumulated its own feedback — so one pass gives the full tail."""
    d = int(delay_seconds * SR)
    if d <= 0:
        return buf
    for start in range(d, len(buf), d):
        end = min(start + d, len(buf))
        buf[start:end] += buf[start - d:start - d + (end - start)] * feedback
    return buf


def make_impulse_response(seconds=2.0, decay=5.5):
    """Synthetic IR: exponentially decaying filtered noise plus early
    reflections. Cheaper to author than a real space and it keeps the file
    entirely our own work."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.zeros((2, n))
    for channel in range(2):
        noise = rng.uniform(-1.0, 1.0, n)
        b, a = signal.butter(2, [180 / (SR / 2), 8000 / (SR / 2)], btype="band")
        noise = signal.lfilter(b, a, noise)
        ir[channel] = noise * np.exp(-t * decay)
    for offset_ms, gain in ((11.0, 0.5), (19.0, 0.38), (27.0, 0.3), (41.0, 0.22)):
        i = int(offset_ms * 0.001 * SR)
        ir[0, i] += gain
        ir[1, i + 40] += gain * 0.9
    ir /= np.max(np.abs(ir))
    return ir


def build_duck():
    """Sidechain envelope keyed off every kick — the genre's signature pump."""
    duck = np.ones(TOTAL)
    span = int(0.26 * SR)
    t = np.arange(span) / SR
    shape = 1.0 - 0.60 * np.exp(-t / 0.09)
    for at in kick_positions:
        end = min(at + span, TOTAL)
        if at >= TOTAL:
            continue
        duck[at:end] = np.minimum(duck[at:end], shape[:end - at])
    return duck


def saturate(x, drive=1.3):
    """Tape-ish soft clip: rounds transients and adds low-order harmonics."""
    return np.tanh(x * drive) / math.tanh(drive)


def main():
    print("arranging %d bars @ %.0f BPM (x2 for tail wrap)..." % (BARS, BPM))
    arrange()

    print("sidechain ducking (%d kicks)..." % len(kick_positions))
    duck = build_duck()
    mix[0] *= duck
    mix[1] *= duck
    np.multiply(send, duck, out=send)   # in-place: plain *= would rebind the global

    print("delay...")
    feedback_delay(mix[0], BEAT * 0.75, 0.33)
    feedback_delay(mix[1], BEAT * 0.75 * 1.5, 0.30)

    print("convolution reverb...")
    ir = make_impulse_response()
    wet_l = signal.fftconvolve(send, ir[0])[:TOTAL]
    wet_r = signal.fftconvolve(send, ir[1])[:TOTAL]
    peak_wet = max(np.max(np.abs(wet_l)), np.max(np.abs(wet_r)), 1e-9)
    mix[0] += wet_l / peak_wet * 0.26
    mix[1] += wet_r / peak_wet * 0.24

    print("bus shaping...")
    # Gentle high shelf: the open hats and supersaws otherwise pile up as hiss.
    b, a = signal.butter(2, 11000 / (SR / 2), btype="low")
    mix[0] = 0.82 * signal.lfilter(b, a, mix[0]) + 0.18 * mix[0]
    mix[1] = 0.82 * signal.lfilter(b, a, mix[1]) + 0.18 * mix[1]
    # High-pass out subsonic energy that only eats headroom.
    b, a = signal.butter(2, 22 / (SR / 2), btype="high")
    mix[0] = signal.lfilter(b, a, mix[0])
    mix[1] = signal.lfilter(b, a, mix[1])

    mix[0] = saturate(mix[0], 1.10)
    mix[1] = saturate(mix[1], 1.10)

    # Keep the SECOND loop: it already contains the first loop's delay and
    # reverb tails, so its head sounds like a continuation, not a cold start.
    out = mix[:, LOOP_N:LOOP_N * 2].copy()

    peak = np.max(np.abs(out))
    out *= 0.92 / peak
    print("peak %.3f -> normalised" % peak)

    os.makedirs(os.path.dirname(WAV_PATH), exist_ok=True)
    stereo = np.stack([out[0], out[1]], axis=1)
    pcm = (np.clip(stereo, -1.0, 1.0) * 32767).astype("<i2")
    import wave
    with wave.open(WAV_PATH, "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())
    print("wrote %s (%.1f s)" % (WAV_PATH, LOOP_N / SR))

    print("encoding OGG Vorbis...")
    result = subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", WAV_PATH,
         "-c:a", "vorbis", "-strict", "-2", "-q:a", "7", OGG_PATH],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print("ffmpeg failed:\n" + result.stderr, file=sys.stderr)
        sys.exit(1)
    print("wrote %s (%.2f MB)" % (OGG_PATH, os.path.getsize(OGG_PATH) / 1048576.0))


if __name__ == "__main__":
    main()
