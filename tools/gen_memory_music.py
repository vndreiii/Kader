#!/usr/bin/env python3
"""Synthesises the bundled Memories soundtrack (assets/music/*.ogg).

Every note is generated here from scratch (sine/saw oscillators, noise
percussion, a little delay) -- no samples, no third-party recordings -- so the
output is original work, dedicated to the public domain under CC0 1.0.
Needs numpy and ffmpeg (libvorbis). Usage: tools/gen_memory_music.py [outdir]
"""
import subprocess, sys, os
import numpy as np

SR = 44100
rng = np.random.default_rng(7)

def midi(n): return 440.0 * 2 ** ((n - 69) / 12)

def env(n, a=0.005, d=0.2, s=0.0, r=0.05):
    t = np.arange(n) / SR
    e = np.where(t < a, t / a, np.exp(-(t - a) / d) * (1 - s) + s)
    rel = int(r * SR)
    if rel and n > rel:
        e[-rel:] *= np.linspace(1, 0, rel)
    return e

def tone(freq, dur, kind="pluck", amp=0.3):
    n = int(dur * SR); t = np.arange(n) / SR
    if kind == "pluck":
        w = sum(np.sin(2 * np.pi * freq * k * t) / k ** 1.6 for k in (1, 2, 3, 4))
        return amp * w * env(n, 0.004, 0.35, 0.0, 0.04)
    if kind == "bell":
        w = np.sin(2*np.pi*freq*t) + 0.4*np.sin(2*np.pi*freq*2.76*t) + 0.2*np.sin(2*np.pi*freq*5.4*t)
        return amp * w * env(n, 0.002, 0.9, 0.0, 0.1)
    if kind == "pad":
        w = sum(np.sin(2*np.pi*freq*(1+d)*t) for d in (-0.003, 0, 0.004)) / 3
        w += 0.3 * np.sin(2*np.pi*freq*2*t)
        a = min(1.2, dur / 3)
        return amp * w * env(n, a, 1e9, 1.0, min(1.5, dur / 3)) * np.clip(t / a, 0, 1)
    if kind == "bass":
        w = np.sign(np.sin(2*np.pi*freq*t)) * 0.25 + np.sin(2*np.pi*freq*t)
        return amp * w * env(n, 0.005, 0.25, 0.25, 0.03)
    if kind == "saw":
        w = 2 * ((freq * t) % 1) - 1
        return amp * w * env(n, 0.005, 0.15, 0.3, 0.03)

def kick(amp=0.55):
    n = int(0.25 * SR); t = np.arange(n) / SR
    f = 50 + 110 * np.exp(-t * 28)
    return amp * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 14)

def hat(amp=0.12, dur=0.05):
    n = int(dur * SR)
    return amp * rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 90)

def snare(amp=0.25):
    n = int(0.18 * SR); t = np.arange(n) / SR
    return amp * (rng.standard_normal(n) * 0.8 + np.sin(2*np.pi*190*t)) * np.exp(-t * 22)

def put(buf, start, snd):
    i = int(start * SR)
    if i >= len(buf): return
    j = min(len(buf), i + len(snd))
    buf[i:j] += snd[:j - i]

def delay(x, sec, fb, mix):
    d = int(sec * SR); out = x.copy()
    for k in range(1, 5):
        if k * d >= len(x): break
        out[k * d:] += x[:-k * d] * (mix * fb ** (k - 1))
    return out

def render(bpm, prog, bars, style, scale_root=60):
    """prog: list of (root_midi_offset, chord intervals), one per bar, looped."""
    beat = 60 / bpm; total = bars * 4 * beat
    buf = np.zeros(int((total + 3) * SR))
    for bar in range(bars):
        off, chord = prog[bar % len(prog)]
        root = scale_root + off
        t0 = bar * 4 * beat
        notes = [root + c for c in chord]
        if style == "upbeat":
            for s in range(16):  # 16th arpeggio, accent on 8ths
                put(buf, t0 + s * beat / 4, tone(midi(notes[s % len(notes)] + 12), beat * 0.6, "pluck", 0.16 if s % 2 == 0 else 0.1))
            for b in range(4):
                put(buf, t0 + b * beat, kick())
                put(buf, t0 + (b + .5) * beat, hat()); put(buf, t0 + b * beat, hat(0.06))
            put(buf, t0 + beat, snare()); put(buf, t0 + 3 * beat, snare())
            for b in range(8):
                put(buf, t0 + b * beat / 2, tone(midi(root - 24), beat * 0.45, "bass", 0.3))
        elif style == "energetic":
            for s in range(8):
                put(buf, t0 + s * beat / 2, tone(midi(notes[(s * 2) % len(notes)] + 12), beat * 0.4, "saw", 0.07))
                put(buf, t0 + s * beat / 2, tone(midi(root - 24), beat * 0.42, "bass", 0.32))
            for s in range(16):
                put(buf, t0 + s * beat / 4, tone(midi(notes[s % len(notes)] + 24), beat * 0.3, "pluck", 0.08))
                put(buf, t0 + s * beat / 4 + beat / 8, hat(0.1))
            for b in range(4):
                put(buf, t0 + b * beat, kick(0.65))
            put(buf, t0 + beat, snare(0.3)); put(buf, t0 + 3 * beat, snare(0.3))
        elif style == "calm":
            for n_ in notes:
                put(buf, t0, tone(midi(n_), 4 * beat + 0.5, "pad", 0.1))
            for s, k in enumerate((0, 2, 1, 2, 0, 1, 2, 1)):
                put(buf, t0 + s * beat / 2, tone(midi(notes[k] + 12), beat * 1.6, "bell", 0.06))
            put(buf, t0, tone(midi(root - 12), 4 * beat, "pad", 0.12))
        elif style == "nostalgic":
            for s, k in enumerate((0, 1, 2, 1, 0, 1, 2, 3)):
                put(buf, t0 + s * beat / 2, tone(midi(notes[k % len(notes)]), beat * 0.9, "pluck", 0.17))
            put(buf, t0, tone(midi(root - 12), beat * 2, "pluck", 0.2))
            put(buf, t0 + 2 * beat, tone(midi(notes[2] - 12), beat * 2, "pluck", 0.14))
            for n_ in notes:
                put(buf, t0, tone(midi(n_ + 12), 4 * beat, "pad", 0.04))
            put(buf, t0, hat(0.05)); put(buf, t0 + 2 * beat, hat(0.05))
        elif style == "dreamy":
            for n_ in notes:
                put(buf, t0, tone(midi(n_), 4 * beat + 1, "pad", 0.11))
            put(buf, t0, tone(midi(root - 12), 4 * beat + 1, "pad", 0.13))
            for s, k in enumerate((2, 3, 1, 3)):
                put(buf, t0 + (s * 1.0 + .5) * beat, tone(midi(notes[k % len(notes)] + 24), beat * 2, "bell", 0.05))
    if style in ("calm", "dreamy", "nostalgic"):
        buf = delay(buf, beat * 0.75, 0.55, 0.45)
    body = buf[:int(total * SR)]
    tail = buf[int(total * SR):][:len(body)]
    body[:len(tail)] += tail  # wrap the tail for a clean loop
    body /= max(1e-6, np.abs(body).max()) / 0.85
    return body

# chord = intervals above root
MAJ, MIN, MAJ7, MIN7, ADD9, LYD = (0,4,7), (0,3,7), (0,4,7,11), (0,3,7,10), (0,4,7,14), (0,4,7,11,18)
TRACKS = {
    "sunny-morning": ("upbeat",   120, [(0,MAJ),(7,MAJ),(9,MIN),(5,MAJ)],  16, 60),
    "still-water":   ("calm",      66, [(0,MAJ7),(9,MIN7),(5,MAJ7),(7,ADD9)], 12, 60),
    "golden-hour":   ("nostalgic", 84, [(9,MIN),(5,MAJ),(0,MAJ),(7,MAJ)],  16, 57),
    "open-road":     ("energetic",132, [(7,MAJ),(2,MAJ),(4,MIN),(0,MAJ)],  24, 55),
    "daydream":      ("dreamy",    60, [(0,LYD),(2,MAJ),(9,MIN7),(4,MIN7)], 12, 60),
}

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "assets", "music")
    os.makedirs(out, exist_ok=True)
    for name, (style, bpm, prog, bars, root) in TRACKS.items():
        x = render(bpm, prog, bars, style, root)
        pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
        dst = os.path.join(out, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
                        "-af", "pan=stereo|c0=c0|c1=c0", "-c:a", "libvorbis", "-q:a", "3", dst], input=pcm, check=True)
        print(name, style, bpm, "bpm", round(len(x) / SR, 1), "s")

if __name__ == "__main__":
    main()
