"""Rebuild campaign charts from local audio. Requires numpy and ffmpeg.

Run: python3 scripts/generate_music_maps.py --source-dir /path/to/originals
Times refer to audible transients in the exported audio, after event expansion.
No random number generator is used. The report retains every matched onset.
"""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SR, HOP, FFT = 22050, 128, 1024
TRACKS = [
    ("Freaky", "BR-Freaky_feat_LezaLee_-fulllength-loopable-121_9BPM-Dm.WAV", 121.9),
    ("Electric Elegance", "JD-ElectricElegance-loopable-114BPM-Bbm.WAV", 114),
    ("City Strut", "JD-CityStrut-loopable-120BPM-Dm.WAV", 120),
    ("Jump Up", "JD-JumpUp_JadeBluHouseinstrumental_-loopable-128BPM-Gm.WAV", 128),
    ("Take Me Over", "BR-TakeMeOver-fulllength-loopable-132BPM-Dm.WAV", 132),
    ("Music Is Life", "JD_-_Music_Is_Life_-__original_instrumental_mix__-_loopable_-_140_BPM_-_E_flat_minor.WAV", 140),
    ("Keep Me Down", "JD-KeepMeDown-instrumental-loopable-174BPM-Cm.WAV", 174),
    ("Freak Tonight", "JD-FreakTonight-instrumental-loopable-177BPM-Ebm_wav.WAV", 177),
]


def decode(path):
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le",
        "-ac", "1", "-ar", str(SR), "-",
    ])
    return np.frombuffer(raw, dtype="<f4")


def analyze(samples, tagged_bpm):
    # Centered spectral flux, emphasizing bass/drum attacks over sustained pads.
    padded = np.pad(samples, (FFT // 2, FFT // 2))
    frames = np.lib.stride_tricks.sliding_window_view(padded, FFT)[::HOP]
    spectrum = np.abs(np.fft.rfft(frames * np.hanning(FFT), axis=1))
    flux = np.maximum(0, np.diff(np.log1p(10 * spectrum), axis=0, prepend=0))
    low = flux[:, 2:12].mean(axis=1)
    high = flux[:, 12:180].mean(axis=1)
    envelope = low / (np.percentile(low, 95) + 1e-8) + high / (np.percentile(high, 95) + 1e-8)
    times = np.arange(len(envelope)) * HOP / SR
    peaks = np.flatnonzero((envelope[1:-1] > envelope[:-2]) & (envelope[1:-1] >= envelope[2:])) + 1
    peaks = peaks[envelope[peaks] > np.percentile(envelope, 65)]
    # Refine tempo and phase against the entire waveform, not just the filename.
    best = (-1, tagged_bpm, 0)
    for bpm in np.linspace(tagged_bpm - 0.15, tagged_bpm + 0.15, 61):
        beat = 60 / bpm
        for phase in np.arange(0, beat, 0.003):
            grid = np.arange(phase, min(times[-1], 160), beat)
            score = np.mean(np.interp(grid, times, envelope))
            if score > best[0]:
                best = (float(score), float(bpm), float(phase))
    return times, envelope, times[peaks], envelope[peaks], best


def polygon_sequence(contacts, beat_indices, beat):
    sequence = []
    previous = 0.0
    for contact, beat_index in zip(contacts, beat_indices):
        gap = (contact - previous) / beat
        sides = 3 if gap < 1.5 else 4 if gap < 2.5 else 5 if gap < 3.5 else 6 if gap < 4.5 else 8
        # Mark the recurring four-beat pulse with a hexagon and its midpoint
        # with a square. Explicit contact times keep every shape on the music.
        if beat_index % 4 == 0:
            sides = max(sides, 6)
        elif beat_index % 2 == 0:
            sides = max(sides, 4)
        sequence.append(sides)
        previous = contact
    return sequence


def generate(stage, name, filename, tagged_bpm, source_dir=ROOT / "level/data"):
    source = (ROOT / "level/data" if stage == 1 else source_dir) / filename
    samples = decode(source)
    times, envelope, peaks, strengths, fit = analyze(samples, tagged_bpm)
    _, bpm, phase = fit
    beat = 60 / bpm
    duration = 55.0 if stage == 1 else (192 if stage >= 7 else 128) * beat
    # Pick a full musical phrase with sustained percussion, leaving a 2-beat lead-in.
    starts = [0.0] if stage == 1 else np.arange(phase, len(samples) / SR - duration, 16 * beat)
    start = max(starts, key=lambda t: float(np.mean(np.interp(np.arange(t, t + duration, beat), times, envelope))))
    if stage == 1:
        start = 0.0
    contacts, matches, beat_indices = [], [], []
    step = 2 if stage == 1 else 1
    if stage >= 7:
        step = 0.5
    first = max(0, int(np.ceil((start + 2 * beat - phase) / beat)))
    last = int(np.floor((start + duration - 0.5 - phase) / beat))
    for index in np.arange(first, last + 0.01, step):
        target = phase + index * beat
        candidates = np.flatnonzero(abs(peaks - target) <= 0.035)
        if not len(candidates):
            continue
        chosen = candidates[np.argmax(strengths[candidates])]
        # Analyze strong offbeats too; the difficulty filter below selects playable notes.
        if index % 1 and strengths[chosen] < np.percentile(strengths, 65):
            continue
        contact = round(float(peaks[chosen] - start), 6)
        if contacts and contact - contacts[-1] < 0.16:
            continue
        contacts.append(contact)
        matches.append(round(float(peaks[chosen]), 6))
        beat_indices.append(float(index))
    music_path = f"res://level/data/{filename}" if stage == 1 else f"res://level/data/music/stage_{stage}.ogg"
    if stage > 1:
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-i", str(source), "-ss", f"{start:.9f}",
            "-t", f"{duration:.9f}", "-c:a", "vorbis", "-strict", "experimental", "-ac", "2", "-q:a", "6",
            str(ROOT / music_path.removeprefix("res://")),
        ], check=True)
    # Re-check the packaged codec output; retain only unambiguous nearby attacks.
    codec_adjustments = []
    if stage > 1:
        _, _, encoded_peaks, _, _ = analyze(decode(ROOT / music_path.removeprefix("res://")), bpm)
        verified = []
        for contact, match, index in zip(contacts, matches, beat_indices):
            nearest = float(encoded_peaks[np.argmin(abs(encoded_peaks - contact))])
            adjustment = abs(nearest - contact)
            if adjustment <= 0.020:
                verified.append((round(nearest, 6), match, index))
                codec_adjustments.append(adjustment * 1000)
        contacts, matches, beat_indices = map(list, zip(*verified))
    if stage >= 7:
        # Fast music plays at half-time: preserve measured attacks on every second beat.
        relaxed = [(t, m, i) for t, m, i in zip(contacts, matches, beat_indices) if i % 2 == 0]
        contacts, matches, beat_indices = map(list, zip(*relaxed))
    assert len(contacts) >= 20, (stage, len(contacts))
    sequence = polygon_sequence(contacts, beat_indices, beat)
    events = []
    boss, health = "", 0
    if stage == 3:
        # Ordinary triangle pairs preserve the chart's paired accents, without a boss event.
        for index in range(4, len(sequence) - 1, 8):
            sequence[index:index + 2] = [3, 3]
    if stage == 4:
        boss, health = "CHRONOMANCER", len(contacts)
        events = [{"name": "time_stop", "at": list(range(16, len(sequence) + 1, 16)), "duration_sec": 0.65}]
    data = dict(sides_sequence=sequence, repeat_count=1, bpm=round(bpm, 6),
                duration_sec=round(duration, 6), music_path=music_path, music_start_offset_sec=0.0,
                note_times_sec=contacts, boss_name=boss, boss_health=health, events=events)
    output = "# Audio-derived chart; regenerate with scripts/generate_music_maps.py\n"
    output += "\n".join(f"{key}: {json.dumps(value, ensure_ascii=False)}" for key, value in data.items()) + "\n"
    (ROOT / f"level/data/level_{stage}.yaml").write_text(output)
    report = dict(stage=stage, track=name, source=filename, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  tagged_bpm=tagged_bpm, measured_bpm=bpm, phase_sec=phase, excerpt_start_sec=float(start),
                  duration_sec=duration, note_count=len(contacts), beat_indices=beat_indices,
                  note_times_sec=contacts, codec_adjustment_max_ms=max(codec_adjustments, default=0),
                  source_onsets_sec=matches, max_grid_deviation_ms=max(abs(t - (phase + i * beat)) for t, i in zip(matches, beat_indices)) * 1000)
    print(f"Stage {stage}: {name}, {bpm:.3f} BPM, start {start:.3f}s, {duration:.2f}s, {len(contacts)} notes", flush=True)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=ROOT / "level/data",
                        help="External folder containing original WAV files for stages 2–8")
    args = parser.parse_args()
    missing = [str((ROOT / "level/data" if i == 1 else args.source_dir) / track[1])
               for i, track in enumerate(TRACKS, 1)
               if not ((ROOT / "level/data" if i == 1 else args.source_dir) / track[1]).is_file()]
    if missing:
        parser.error("Original WAV files are required for regeneration; supply --source-dir. Missing: " + ", ".join(missing))
    reports = [generate(i, *track, source_dir=args.source_dir) for i, track in enumerate(TRACKS, 1)]
    (ROOT / "docs/music_maps.json").write_text(json.dumps(reports, indent=2) + "\n")
