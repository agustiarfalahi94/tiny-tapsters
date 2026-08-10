#!/usr/bin/env python3
"""Rebuild every bundled audio asset at one consistent loudness.

Why this exists
---------------
The app mixes three sources that were mastered by three different processes:
Suno tracks, generated sound effects, and field recordings from Wikimedia
Commons. Left alone their loudness differs by more than 20 dB, so the music
drowned the pop, and an animal call could arrive either inaudible or startling.
Setting player volumes cannot fix that, because a player volume scales a file
whose level you do not know.

So every asset is normalised to the same RMS here, once, at build time. After
that the player volumes in `SoundEffects` and `MusicService` mean what they
say: music at 0.35 really is a bit under an effect at 0.9.

The second thing this fixes: the animal calls were first encoded at 22.05 kHz
from 44.1 kHz sources, which threw away everything above 11 kHz and made them
sound muffled. Everything is 44.1 kHz now.

Requirements
------------
macOS `afconvert` (ships with the OS). There is no ffmpeg on this machine,
which is why the resampling and encoding go through afconvert and the gain
maths is done here in plain Python.

Usage
-----
    python3 tool/normalize_audio.py <source-dir>

`<source-dir>` holds the originals. Music and effects are the files the app's
author supplied; the animal calls are the Commons downloads listed in
ASSET_CREDITS.md, saved under `<source-dir>/animals/` as `<name>.<ext>`.
Anything missing is skipped with a warning, so a partial rebuild is fine.
"""

import array
import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave

# Everything lands here. -16 dBFS RMS is a normal level for game audio: loud
# enough on a phone speaker, with room left before clipping.
TARGET_RMS_DBFS = -16.0

# No asset may peak above this. Anything that would go over is folded back by
# the soft limiter below rather than clipped flat.
PEAK_CEILING_DBFS = -1.0

# A quiet field recording is quiet because of its noise floor as much as its
# subject. Past this much lift you amplify hiss, not the animal — +12 dB on a
# 60 kbps source is what made the horse and the elephant crackle.
MAX_GAIN_DB = 12.0

# Field recordings get a stricter pair of limits than studio material. The
# music and effects were produced with headroom and take limiting cleanly; a
# 60 kbps Commons recording does not, and pushing one is what crackled.
FIELD_MAX_GAIN_DB = 9.0
FIELD_MAX_LIMITING_DB = 2.0

# How much the limiter may lean on a file to reach the target. The first
# version let it work as hard as it liked, and waveshaping a transient that
# hard *is* the crackle. Three decibels is inaudible; past that, the asset is
# simply allowed to sit quieter than target.
MAX_LIMITING_DB = 5.0

RATE = 44100
FADE_SECONDS = 0.04

# name -> (source file, output path, bitrate, trim-to-loudest-seconds or None)
ASSETS = {
    "main_theme": ("Tiny Tappers - Main Theme.mp3", "assets/music/main_theme.m4a", 96000, None),
    "game_song": ("Tiny Tappers - Game Song.mp3", "assets/music/game_song.m4a", 96000, None),
    "lose": ("lose.mp3", "assets/sfx/lose.m4a", 96000, None),
    "win_low": ("2 stars.mp3", "assets/sfx/win_low.m4a", 96000, None),
    "win_high": ("3 stars.mp3", "assets/sfx/win_high.m4a", 96000, None),
}

ANIMALS = ["cat", "dog", "horse", "cow", "chicken", "lion", "monkey",
           "elephant", "frog"]
ANIMAL_BITRATE = 96000
ANIMAL_TRIM = 2.0


def decode(src, dest):
    """Source -> 44.1 kHz mono 16-bit wav.

    afconvert refuses the mixdown flags (-50) when the source is already mono
    at the target rate — there is nothing for it to convert — so fall back to
    a plain conversion in that case.
    """
    base = ["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}"]
    for args in ([*base, "--mix", "-c", "1", src, dest], [*base, src, dest]):
        result = subprocess.run(args, capture_output=True)
        if result.returncode == 0:
            return
    raise RuntimeError(f"afconvert could not decode {src}: "
                       f"{result.stderr.decode().strip()}")


def encode(src, dest, bitrate):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    subprocess.run(
        ["afconvert", "-f", "m4af", "-d", "aac", "-b", str(bitrate), src, dest],
        check=True, capture_output=True,
    )


def read_wav(path):
    with wave.open(path) as w:
        return array.array("h", w.readframes(w.getnframes())), w.getframerate()


def write_wav(path, samples, rate):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(samples.tobytes())


def dbfs(value):
    return -math.inf if value <= 0 else 20 * math.log10(value / 32768.0)


def rms(samples):
    if not samples:
        return 0.0
    return math.sqrt(sum(s * s for s in samples) / len(samples))


def loudest_window(samples, rate, seconds):
    """The `seconds`-long stretch carrying the most energy.

    Field recordings routinely open with several seconds of wind before the
    animal makes a sound; a child pressing the speaker button needs the call.
    """
    width = int(seconds * rate)
    if len(samples) <= width:
        return samples
    cumulative = [0]
    for s in samples:
        cumulative.append(cumulative[-1] + s * s)
    step = max(1, rate // 20)
    best_start, best_energy = 0, -1
    for start in range(0, len(samples) - width, step):
        energy = cumulative[start + width] - cumulative[start]
        if energy > best_energy:
            best_energy, best_start = energy, start
    return samples[best_start:best_start + width]


# Below this fraction of the ceiling the limiter is not in the signal path at
# all. High on purpose: every sample it touches is a sample it distorts.
LIMITER_KNEE = 0.9


def soft_limit(value, ceiling):
    """Fold the very top of the range over instead of chopping it off.

    Only the last decibel or so passes through here, and gain is capped
    (MAX_LIMITING_DB) so the limiter never has much to do. Leaning on it
    harder is audible as crackle, which is exactly what it sounded like.
    """
    knee = ceiling * LIMITER_KNEE
    if abs(value) <= knee:
        return value
    excess = (abs(value) - knee) / (ceiling - knee)
    shaped = knee + (ceiling - knee) * math.tanh(excess)
    return math.copysign(shaped, value)


def apply_gain_and_fade(samples, gain, rate, fade):
    edge = int(fade * rate) if fade else 0
    ceiling = 10 ** (PEAK_CEILING_DBFS / 20) * 32768.0
    out = array.array("h")
    for i, s in enumerate(samples):
        v = soft_limit(s * gain, ceiling)
        if edge:
            if i < edge:
                v *= i / edge
            elif i > len(samples) - edge:
                v *= max(0.0, (len(samples) - i) / edge)
        out.append(max(-32768, min(32767, int(round(v)))))
    return out


def process(src, dest, bitrate, trim, work, field=False):
    raw = os.path.join(work, "raw.wav")
    decode(src, raw)
    samples, rate = read_wav(raw)
    if trim:
        samples = loudest_window(samples, rate, trim)

    level = rms(samples)
    peak = max((abs(s) for s in samples), default=0)
    if level == 0 or peak == 0:
        raise ValueError("silent source")

    # Aim for the target RMS, but stay within reach of the peak: the limiter
    # may make up MAX_LIMITING_DB and no more. A file that still cannot reach
    # the target is left quieter rather than distorted — a couple of decibels
    # of imbalance is a far smaller problem than crackle.
    max_gain = FIELD_MAX_GAIN_DB if field else MAX_GAIN_DB
    max_limiting = FIELD_MAX_LIMITING_DB if field else MAX_LIMITING_DB
    wanted = (10 ** (TARGET_RMS_DBFS / 20) * 32768.0) / level
    headroom = (10 ** (PEAK_CEILING_DBFS / 20) * 32768.0) / peak
    ceiling_gain = min(
        headroom * 10 ** (max_limiting / 20), 10 ** (max_gain / 20)
    )
    gain = min(wanted, ceiling_gain)

    # A trimmed clip is a hard cut out of a longer recording, so it needs a
    # fade to avoid a click. A whole track already starts and ends cleanly.
    edge = FADE_SECONDS if trim else 0
    out = apply_gain_and_fade(samples, gain, rate, edge)

    # The limiter itself lowers the average on peaky material, so the first
    # pass can land a couple of dB under target. Correct and re-run; two
    # passes bring everything inside a few tenths of a dB of each other,
    # which is the entire point of this script.
    for _ in range(3):
        achieved = rms(out)
        error = (10 ** (TARGET_RMS_DBFS / 20) * 32768.0) / achieved
        if abs(20 * math.log10(error)) < 0.2:
            break
        gain = min(gain * error, ceiling_gain)
        out = apply_gain_and_fade(samples, gain, rate, edge)

    normalised = os.path.join(work, "norm.wav")
    write_wav(normalised, out, rate)

    if dest.endswith(".wav"):
        shutil.copyfile(normalised, dest)
    else:
        encode(normalised, dest, bitrate)

    return {
        "before_rms": dbfs(level), "before_peak": dbfs(peak),
        "after_rms": dbfs(rms(out)), "after_peak": dbfs(max(abs(s) for s in out)),
        "gain_db": 20 * math.log10(gain), "seconds": len(out) / rate,
        "bytes": os.path.getsize(dest),
    }


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    source_dir = sys.argv[1]

    jobs = [(name, os.path.join(source_dir, src), dest, rate, trim, False)
            for name, (src, dest, rate, trim) in ASSETS.items()]
    for animal in ANIMALS:
        matches = [f for f in os.listdir(os.path.join(source_dir, "animals"))
                   if os.path.splitext(f)[0] == animal]
        if not matches:
            print(f"  ! no source for {animal}", file=sys.stderr)
            continue
        jobs.append((animal, os.path.join(source_dir, "animals", matches[0]),
                     f"assets/animal_sounds/{animal}.m4a", ANIMAL_BITRATE,
                     ANIMAL_TRIM, True))

    print(f"{'asset':12} {'RMS before':>11} {'RMS after':>10} {'peak':>7} "
          f"{'gain':>7} {'len':>6} {'size':>8}")
    for name, src, dest, rate, trim, field in jobs:
        if not os.path.exists(src):
            print(f"  ! missing source: {src}", file=sys.stderr)
            continue
        with tempfile.TemporaryDirectory() as work:
            r = process(src, dest, rate, trim, work, field=field)
        print(f"{name:12} {r['before_rms']:>10.1f}d {r['after_rms']:>9.1f}d "
              f"{r['after_peak']:>6.1f}d {r['gain_db']:>+6.1f}d "
              f"{r['seconds']:>5.2f}s {r['bytes']:>7}B")


if __name__ == "__main__":
    main()
