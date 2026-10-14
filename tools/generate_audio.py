"""Original deterministic sound effect synthesis for IWPM. Requires numpy.

Run from any directory. Runtime sound effects go to Assets/Audio/SFX; the
report goes to artifacts/audio. No samples or external music are used.
"""
from pathlib import Path
import json
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Assets" / "Audio"
WORK = ROOT / "artifacts" / "audio"
SR = 44100
RNG = np.random.default_rng(20261014)
REPORT = {}


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def env(t, attack=.006, release=.045):
    return np.minimum(t / attack, 1) * np.clip((t[-1] - t) / release, 0, 1)


def tone(midi, duration, kind="wood"):
    t = np.arange(round(duration * SR)) / SR
    f = hz(midi)
    p = 2 * np.pi * f * t
    if kind == "wood":
        x = (np.sin(p) * np.exp(-t * 7) + .26 * np.sin(p * 3) * np.exp(-t * 19)
             + .09 * np.sin(p * 6.98) * np.exp(-t * 33))
    elif kind == "pluck":
        x = sum(np.sin(p * k) * np.exp(-t * (4 + 2.1 * k)) / k ** 1.8 for k in range(1, 6))
    elif kind == "bell":
        x = np.sin(p) * np.exp(-t * 4.5) + .21 * np.sin(p * 2) * np.exp(-t * 8)
    else:
        raise ValueError(kind)
    return x * env(t)


def noise(duration, cutoff=2500, high=False):
    t = np.arange(round(duration * SR)) / SR
    raw = RNG.normal(0, .3, len(t))
    kernel = np.exp(-2 * np.pi * cutoff * np.arange(128) / SR)
    kernel /= kernel.sum()
    low = np.convolve(raw, kernel)[:len(raw)]
    return (raw-low if high else low) * np.exp(-t * 20) * env(t, .002, .02)


def sweep(start, end, duration, airy=False):
    t = np.arange(round(duration * SR)) / SR
    f = start * (end / start) ** (t / duration)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 10)
    if airy:
        x += noise(duration, 1700) * .7
    return x * env(t, .004, .035)


def sequence(notes, spacing=.09, kind="bell", duration=.4):
    x = np.zeros(int(np.ceil((spacing * (len(notes) - 1) + duration) * SR)) + 2)
    for i, note in enumerate(notes):
        y = tone(note, duration, kind)
        pos = round(i * spacing * SR)
        x[pos:pos + len(y)] += y
    return x


def write_wav(path, x, peak=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    if peak is not None:
        x = x * (peak / max(float(np.max(np.abs(x))), 1e-9))
    assert np.isfinite(x).all() and np.max(np.abs(x)) < 1, path
    pcm = np.rint(x * 32767).astype("<i2")
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1 if x.ndim == 1 else x.shape[1])
        wav.setsampwidth(2)
        wav.setframerate(SR)
        wav.writeframes(pcm.tobytes())
    REPORT[path.name] = {"seconds": round(len(x) / SR, 3),
                         "peak_dbfs": round(20 * np.log10(max(np.max(np.abs(x)), 1e-9)), 2),
                         "rms_dbfs": round(20 * np.log10(max(np.sqrt(np.mean(x*x)), 1e-9)), 2)}
    return x


def make_sfx():
    sounds = {
        "land": sweep(140, 85, .12) * .6 + noise(.12, 850) * .3,
        "shoot_01": sweep(520, 760, .22, True) * .4 + tone(72, .22) * .6,
        "shoot_02": sweep(580, 850, .22, True) * .4 + tone(76, .22) * .6,
        "shoot_03": sweep(650, 950, .22, True) * .4 + tone(79, .22) * .6,
        "giraffe_hit": sequence([67, 72], .045, "wood", .26),
        "wall_hit": tone(84, .12, "wood") * .45 + noise(.12, 2200) * .3,
        "pickup": sequence([72, 76, 79, 84], .085, "bell", .55),
        "door": sequence([60, 67, 72], .09, "pluck", .42),
        "restart": sequence([76, 72, 67, 72], .10, "wood", .3),
        "confirm": sequence([72, 79], .075, "pluck", .3),
        "pause": sequence([76, 72], .07, "wood", .21),
        "resume": sequence([72, 76], .07, "wood", .21),
        "time_down": sequence([79, 76, 72], .065, "wood", .22),
        "time_up": sequence([72, 76, 79], .065, "wood", .22),
        "complete": sequence([72, 76, 79, 84, 79, 84, 88], .13, "bell", .95),
    }
    levels = {"land": .3, "wall_hit": .22}
    for name, x in sounds.items():
        write_wav(OUT / "SFX" / (name + ".wav"), x, levels.get(name, .52))


if __name__ == "__main__":
    WORK.mkdir(parents=True, exist_ok=True)
    make_sfx()
    (WORK / "audio_report.json").write_text(json.dumps(REPORT, indent=2), encoding="utf-8")
    print(json.dumps(REPORT, indent=2))
