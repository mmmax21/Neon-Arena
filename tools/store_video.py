#!/usr/bin/env python3
"""Build the TapTap gameplay video from a tests/store_capture.gd frame dump.

Usage: python3 tools/store_video.py <capture-dir> <out.mp4> <ffmpeg> [start-end ...]

The capture dir holds frames/NNNNN.jpg (60 fps), sfx/*.wav (the game's synthesized sounds)
and sfx_log.json (frame, sound) pairs. The soundtrack is rebuilt from those exact sounds with
the game's throttle and pitch jitter, then the listed time ranges (seconds) are cut together
with short audio fades at each cut and encoded as H.264 / AAC.
"""
import json
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

RATE = 22050


def read_wav(path):
    with wave.open(str(path)) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
        if w.getnchannels() == 2:
            data = data.reshape(-1, 2).mean(axis=1)
        if w.getframerate() != RATE:
            n = int(len(data) * RATE / w.getframerate())
            data = np.interp(np.linspace(0, len(data) - 1, n), np.arange(len(data)), data)
    return data


def mix(cap: Path):
    log = json.loads((cap / "sfx_log.json").read_text())
    fps, frames = log["fps"], log["frames"]
    sounds = {p.stem: read_wav(p) for p in (cap / "sfx").glob("*.wav")}
    out = np.zeros(int(frames / fps * RATE) + RATE * 2, dtype=np.float32)
    last = {}
    rng = np.random.default_rng(7)
    for frame, name in log["events"]:
        if name not in sounds:
            continue
        t = frame / fps
        gap = 0.040 if name == "hit" else 0.025  # same throttle as sfx.gd
        if name in last and t - last[name] < gap:
            continue
        last[name] = t
        s = sounds[name]
        pitch = rng.uniform(0.92, 1.08)
        n = int(len(s) / pitch)
        s = np.interp(np.linspace(0, len(s) - 1, n), np.arange(len(s)), s)
        i = int(t * RATE)
        out[i:i + n] += s[: len(out) - i]
    # Soft limiter: many overlapping sounds would clip.
    out = np.tanh(out * 1.4) / np.tanh(1.4)
    out *= 0.89 / max(1e-6, np.max(np.abs(out)))
    pcm = (out * 32767).astype(np.int16)
    path = cap / "mix.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    return path, fps


def main():
    cap, out, ffmpeg = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    ranges = [tuple(float(x) for x in r.split("-")) for r in sys.argv[4:]] or [(0.0, 1e9)]
    audio, fps = mix(cap)
    parts, labels = [], []
    for k, (a, b) in enumerate(ranges):
        d = b - a
        parts.append(f"[0:v]trim=start={a}:end={b},setpts=PTS-STARTPTS[v{k}]")
        parts.append(
            f"[1:a]atrim=start={a}:end={b},asetpts=PTS-STARTPTS,"
            f"afade=t=in:d=0.08,afade=t=out:st={max(0.0, d - 0.12)}:d=0.12[a{k}]")
        labels.append(f"[v{k}][a{k}]")
    graph = ";".join(parts) + ";" + "".join(labels) + f"concat=n={len(ranges)}:v=1:a=1[v][a]"
    cmd = [ffmpeg, "-y", "-hide_banner", "-loglevel", "error",
           "-framerate", str(fps), "-i", str(cap / "frames" / "%05d.jpg"), "-i", str(audio),
           "-filter_complex", graph, "-map", "[v]", "-map", "[a]",
           "-c:v", "libx264", "-preset", "slow", "-crf", "19", "-pix_fmt", "yuv420p",
           "-profile:v", "high", "-r", str(fps),
           "-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-movflags", "+faststart", str(out)]
    subprocess.run(cmd, check=True)
    print(out)


if __name__ == "__main__":
    main()
