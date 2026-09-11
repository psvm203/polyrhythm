"""Author stage 9 against attacks in the original MP3; numpy + ffmpeg required.

Run: python3 scripts/generate_matadora_map.py
The 48-bar arrangement is authored explicitly, then snapped to measured audio
attacks. No random selection, repeated stage loop, or audio re-encoding.
"""

import hashlib
import json

import numpy as np

from generate_music_maps import ROOT, SR, analyze, decode


# Beat offsets within one 4/4 bar. The 1.5 / 2.5 syncopations follow the
# recurring strong percussion; short half-beat runs resolve into a rest.
MOTIFS = {
    "open": [0, 1.5, 2.5],
    "answer": [0, 1.5, 2.5, 3],
    "step": [0, 1, 2.5],
    "lift": [0, 1, 1.5, 2.5],
    "drive": [0, 1, 1.5, 2, 2.5, 3],
    "skip": [0, 1.5, 2, 2.5],
    "late": [0, 1.5, 2.5, 3, 3.5],
    "pair": [0, 1, 1.5, 2.5, 3],
    "pulse": [0, 1, 2, 3],
    "roll": [0, 1, 1.5, 2, 2.5],
    "space": [0, 2.5],
    "reply": [1.5, 2.5, 3],
    "rise": [0, 1, 2, 3.5],
    "pickup": [0.5, 1.5, 2.5, 3.5],
    "return": [0, 1.5, 2.5, 3, 3.5],
    "close": [0, 1.5, 2.5, 3],
}

# Boundaries follow waveform changes: first impact at bar 8, one-bar drop at
# 23, second impact at 24, breakdown at 32, rebuild at 36 and return at 39.
SECTIONS = [
    ("introduction", ["open", "answer", "step", "lift", "open", "pair", "pulse", "rise"]),
    ("first_drive", ["drive", "skip", "pair", "late", "roll", "drive", "answer", "open"]),
    ("accent_exchange", ["pulse", "pair", "roll", "answer", "drive", "lift", "pulse"]),
    ("turnaround", ["pickup"]),
    ("second_drive", ["pair", "drive", "roll", "late", "skip", "drive", "pair", "open"]),
    ("breakdown", ["space", "reply", "open", "space"]),
    ("rebuild", ["lift", "pair", "rise"]),
    ("finale", ["return", "skip", "late", "drive", "pair", "roll", "drive", "answer", "close"]),
]


def generate():
    source = ROOT / "level/data/music/matadora.mp3"
    samples = decode(source)
    _, _, peaks, strengths, (_, bpm, phase) = analyze(samples, 130.0)
    beat = 60 / bpm
    duration = len(samples) / SR
    contacts, indices, shapes, sections = [], [], [], []
    bar = 0
    for name, motifs in SECTIONS:
        first_note = len(contacts)
        start_bar = bar
        for motif in motifs:
            for offset in MOTIFS[motif]:
                index = bar * 4 + offset
                # Two beats to settle after countdown; preserve the ending tail.
                target = phase + index * beat
                if index < 2 or target > duration - 0.35:
                    continue
                candidates = np.flatnonzero(abs(peaks - target) <= 0.035)
                if not len(candidates):
                    continue
                chosen = candidates[np.argmax(strengths[candidates])]
                contact = round(float(peaks[chosen]), 6)
                if contacts and contact - contacts[-1] < 0.19:
                    continue
                gap = (contact - (contacts[-1] if contacts else 0)) / beat
                # Shapes communicate the rhythm: triangles for quick responses,
                # pentagons for syncopation, larger polygons for held spacing.
                sides = 3 if gap < 0.75 else 4 if gap < 1.25 else 5 if gap < 1.75 else 6 if gap < 2.75 else 8
                if offset == 0 and gap >= 0.75:
                    sides = 8 if bar == start_bar else 6
                if offset == 2.5 and gap >= 0.75:
                    sides = 5
                contacts.append(contact)
                indices.append(index)
                shapes.append(sides)
            bar += 1
        sections.append(dict(name=name, start_bar=start_bar, end_bar=bar,
                             start_sec=round(phase + start_bar * 4 * beat, 6),
                             end_sec=round(min(duration, phase + bar * 4 * beat), 6),
                             motifs=motifs, first_note=first_note,
                             note_count=len(contacts) - first_note))
    assert bar == 48
    assert len(contacts) == len(shapes) and len(contacts) > 180
    assert min(np.diff(contacts)) >= 0.19
    assert len(set(shapes)) >= 5
    data = dict(sides_sequence=shapes, repeat_count=1, bpm=bpm,
                duration_sec=round(duration, 6),
                music_path="res://level/data/music/matadora.mp3",
                music_start_offset_sec=0.0, note_times_sec=contacts,
                boss_name="", boss_health=0, events=[])
    output = "# Matadora: authored phrases matched to original MP3 attacks.\n"
    output += "# Regenerate: python3 scripts/generate_matadora_map.py\n"
    for section in sections:
        output += f"# {section['name']}: {section['start_sec']:.2f}-{section['end_sec']:.2f}s, {section['note_count']} notes\n"
    output += "\n".join(f"{key}: {json.dumps(value)}" for key, value in data.items()) + "\n"
    (ROOT / "level/data/level_9.yaml").write_text(output)
    report = dict(stage=9, track="Matadora", source="music/matadora.mp3",
                  source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  measured_bpm=bpm, phase_sec=phase, excerpt_start_sec=0.0,
                  duration_sec=duration, note_count=len(contacts),
                  beat_indices=indices, note_times_sec=contacts,
                  source_onsets_sec=contacts, codec_adjustment_max_ms=0,
                  max_grid_deviation_ms=max(abs(t - (phase + i * beat)) for t, i in zip(contacts, indices)) * 1000,
                  sections=sections)
    report_path = ROOT / "docs/music_maps.json"
    reports = json.loads(report_path.read_text())
    reports = [item for item in reports if item["stage"] != 9] + [report]
    report_path.write_text(json.dumps(sorted(reports, key=lambda item: item["stage"]), indent=2) + "\n")
    print(f"Matadora: {bpm:.3f} BPM, {duration:.2f}s, {len(contacts)} notes, minimum gap {min(np.diff(contacts)):.3f}s")
    for section in sections:
        print(section)


if __name__ == "__main__":
    generate()
