#!/usr/bin/env python3
# Synthesizes Glance's alarm sounds from scratch (original, MIT like the project). Needs ffmpeg with libvorbis.
# Usage: python3 data/sounds/generate.py   (writes data/sounds/*.ogg)
import math, os, struct, subprocess, tempfile, wave

RATE = 48000
HERE = os.path.dirname(os.path.abspath(__file__))


def strike(buf, start, freq, amp, decay, partials, attack=0.004):
    # Adds one struck note: each partial (ratio, gain) decays faster the higher it is.
    n0 = int(start * RATE)
    n = min(int(decay * 7 * RATE), len(buf) - n0)
    for ratio, gain in partials:
        f = freq * ratio
        d = decay / ratio ** 0.6
        w = 2 * math.pi * f / RATE
        for i in range(n):
            t = i / RATE
            buf[n0 + i] += amp * gain * min(1.0, t / attack) * math.exp(-t / d) * math.sin(w * i)


def beep(buf, start, freq, amp, length, partials, edge=0.004):
    # Adds a flat tone with short ramps so it does not click.
    n0 = int(start * RATE)
    n = int(length * RATE)
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / edge, (length - t) / edge)
        buf[n0 + i] += amp * env * sum(g * math.sin(2 * math.pi * freq * r * t) for r, g in partials)


def soft_chime():
    buf = [0.0] * int(2.8 * RATE)
    tones = ((1, 1.0), (2, 0.22), (3, 0.06))
    for k, f in enumerate((1046.5, 1318.5, 1568.0)):
        strike(buf, 0.18 * k, f, 1.0, 0.55, tones, attack=0.012)
    return buf


def bell():
    buf = [0.0] * int(3.4 * RATE)
    partials = ((0.5, 0.45), (1, 1.0), (1.19, 0.55), (1.5, 0.35), (2, 0.45), (2.52, 0.25), (2.66, 0.2), (3.01, 0.12), (4.1, 0.06))
    strike(buf, 0.0, 660.0, 1.0, 0.7, partials)
    strike(buf, 1.3, 660.0, 0.8, 0.7, partials)
    return buf


def digital():
    buf = [0.0] * int(2.5 * RATE)
    square = ((1, 1.0), (3, 0.3), (5, 0.15), (7, 0.08))
    for group in range(3):
        for k in range(4):
            beep(buf, group * 0.8 + k * 0.13, 1760.0, 1.0, 0.07, square)
    return buf


def pulse():
    buf = [0.0] * int(2.6 * RATE)
    warm = ((1, 1.0), (2, 0.35), (0.5, 0.25))
    for k in range(5):
        strike(buf, k * 0.48, 587.3, 1.0, 0.16, warm, attack=0.03)
    return buf


def classic():
    # Mechanical alarm clock: a hammer rattling between two small bells.
    buf = [0.0] * int(3.0 * RATE)
    partials = ((1, 1.0), (2.76, 0.5), (5.4, 0.25))
    for burst in (0.0, 1.5):
        for k in range(int(1.1 * 17)):
            f = 2200.0 if k % 2 == 0 else 2530.0
            strike(buf, burst + k / 17.0, f, 0.8 + 0.2 * ((k * 7) % 5) / 4, 0.05, partials, attack=0.001)
    return buf


def finish(buf):
    # Loudness-match on RMS, cap the peak at -1 dBFS, trim silence, fade the tail.
    rms = math.sqrt(sum(s * s for s in buf) / len(buf))
    gain = 0.12 / rms
    peak = max(abs(s) for s in buf) * gain
    if peak > 0.89:
        gain *= 0.89 / peak
    out = [s * gain for s in buf]
    while out and abs(out[-1]) < 1e-4:
        out.pop()
    fade = int(0.01 * RATE)
    for i in range(min(fade, len(out))):
        out[-1 - i] *= i / fade
    return out


for name, make in (("soft-chime", soft_chime), ("bell", bell), ("digital", digital), ("pulse", pulse), ("classic", classic)):
    samples = finish(make())
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "4",
                        "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
                        os.path.join(HERE, name + ".ogg")], check=True)
    print(name, "%.2fs" % (len(samples) / RATE))
