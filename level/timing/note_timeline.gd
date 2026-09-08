class_name NoteTimeline
extends RefCounted

var _entries: Array[Dictionary] = []


static func build(
	sequence: Array[int],
	bpm: float,
	perfect_window_sec: float,
	early_window_sec: float,
	late_window_sec: float,
	judgment_offset_sec: float = 0.0,
	note_times_sec: PackedFloat32Array = PackedFloat32Array(),
):
	var timeline = (load("res://level/timing/note_timeline.gd") as GDScript).new()
	var cursor := 0.0
	var safe_bpm := maxf(bpm, 0.0001)
	for index in sequence.size():
		var duration := float(sequence[index]) * 120.0 / safe_bpm
		var contact := cursor + duration
		if note_times_sec.size() == sequence.size():
			contact = note_times_sec[index]
			duration = contact - cursor
		var center := contact + judgment_offset_sec
		timeline._entries.append({
			"index": index,
			"sides": sequence[index],
			"move_start_sec": cursor,
			"duration_sec": duration,
			"contact_sec": contact,
			"judgment_sec": center,
			"too_fast_before_sec": center - early_window_sec,
			"perfect_start_sec": center - perfect_window_sec,
			"perfect_end_sec": center + perfect_window_sec,
			"miss_after_sec": center + late_window_sec,
		})
		cursor = contact
	return timeline


func size() -> int:
	return _entries.size()


func is_empty() -> bool:
	return _entries.is_empty()


func entry(index: int) -> Dictionary:
	if index < 0 or index >= _entries.size():
		return {}
	return _entries[index].duplicate(true)


func contact_times() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for item in _entries:
		result.append(float(item["contact_sec"]))
	return result


func judgment_times() -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for item in _entries:
		result.append(float(item["judgment_sec"]))
	return result


func duration_sec() -> float:
	return float(_entries[-1]["contact_sec"]) if not _entries.is_empty() else 0.0
