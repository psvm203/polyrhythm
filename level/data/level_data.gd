class_name LevelData
extends RefCounted

var bpm: float = 120.0
# Zero ends the stage when all notes resolve.
var duration_sec: float = 0.0
var music_path: String = ""
var music_start_offset_sec: float = 0.0
var boss_name: String = ""
var boss_health: int = 0
var events: Array[Dictionary] = []
var tutorial_speaker: String = "POLY"
var tutorial_lines: Array[String] = []
var _yaml: Dictionary = {}


static func from_yaml(path: String) -> LevelData:
	var result := LevelData.new()
	result._yaml = result._parse_yaml(path)
	result.bpm = _positive_float(result._yaml.get("bpm", result.bpm), result.bpm)
	result.duration_sec = maxf(_finite_float(result._yaml.get("duration_sec", 0.0), 0.0), 0.0)
	result.music_path = str(result._yaml.get("music_path", ""))
	result.music_start_offset_sec = maxf(_finite_float(result._yaml.get("music_start_offset_sec", 0.0), 0.0), 0.0)
	result.boss_name = str(result._yaml.get("boss_name", ""))
	result.boss_health = maxi(_safe_int(result._yaml.get("boss_health", 0), 0), 0)
	var raw_events: Variant = result._yaml.get("events", [])
	if not raw_events is Array:
		raw_events = []
	for event in raw_events:
		if event is Dictionary:
			result.events.append((event as Dictionary).duplicate(true))
	result.tutorial_speaker = str(result._yaml.get("tutorial_speaker", "POLY"))
	var raw_lines: Variant = result._yaml.get("tutorial_lines", [])
	if not raw_lines is Array:
		raw_lines = []
	for line in raw_lines:
		result.tutorial_lines.append(str(line))
	return result


func expanded_sequence() -> Array[int]:
	return expand_layout(_yaml)


func _parse_yaml(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Level data not found: %s" % path)
		return {}
	var layout := {}
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var separator := line.find(":")
		if separator > 0:
			layout[line.left(separator).strip_edges()] = JSON.parse_string(line.substr(separator + 1).strip_edges())
	return layout


static func expand_layout(layout: Dictionary) -> Array[int]:
	var pattern: Array[int] = []
	var raw_sequence: Variant = layout.get("sides_sequence", [])
	if raw_sequence is Array:
		for sides in raw_sequence:
			var side_count := _safe_int(sides, 0)
			if side_count >= 3 and side_count <= 12:
				pattern.append(side_count)
	# Runtime callers need at least one valid polygon even if a custom file was
	# deleted, truncated, or edited outside the level editor.
	if pattern.is_empty():
		pattern.append(3)
	var result: Array[int] = []
	var repeat_count := clampi(_safe_int(layout.get("repeat_count", 1), 1), 1, 1000)
	for _repeat in repeat_count:
		result.append_array(pattern)
	return result


static func _safe_int(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	if value is String and (value as String).is_valid_int():
		return (value as String).to_int()
	return fallback


static func _finite_float(value: Variant, fallback: float) -> float:
	var parsed := fallback
	if value is int or value is float:
		parsed = float(value)
	elif value is String and (value as String).is_valid_float():
		parsed = (value as String).to_float()
	return parsed if is_finite(parsed) else fallback


static func _positive_float(value: Variant, fallback: float) -> float:
	var parsed := _finite_float(value, fallback)
	return parsed if parsed > 0.0 else fallback


static func validate(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for diagnostic in validate_detailed(data):
		errors.append(diagnostic["message"])
	return errors


static func validate_detailed(data: Dictionary, source_path: String = "") -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	var sequence: Variant = data.get("sides_sequence", [])
	if not sequence is Array or sequence.is_empty():
		_append_diagnostic(diagnostics, "missing_sequence", "sides_sequence", "도형 배열을 하나 이상 입력하세요.", source_path)
	if sequence is Array:
		for sides in sequence:
			var side_count := _safe_int(sides, 0)
			if side_count < 3 or side_count > 12:
				_append_diagnostic(diagnostics, "invalid_polygon", "sides_sequence", "도형의 변 개수는 3~12여야 합니다.", source_path)
				break
	if _finite_float(data.get("bpm", 0.0), 0.0) <= 0.0:
		_append_diagnostic(diagnostics, "invalid_bpm", "bpm", "BPM은 0보다 커야 합니다.", source_path)
	if _safe_int(data.get("repeat_count", 1), 0) < 1:
		_append_diagnostic(diagnostics, "invalid_repeat_count", "repeat_count", "반복 횟수는 1 이상이어야 합니다.", source_path)
	var music := str(data.get("music_path", ""))
	if music.is_empty() or not FileAccess.file_exists(music):
		_append_diagnostic(diagnostics, "missing_music", "music_path", "재생할 음악 파일을 찾을 수 없습니다.", source_path)
	return diagnostics


static func _append_diagnostic(
		diagnostics: Array[Dictionary],
		code: String,
		field: String,
		message: String,
		source_path: String,
) -> void:
	diagnostics.append({
		"code": code,
		"field": field,
		"message": message,
		"source_path": source_path,
	})


static func to_yaml(data: Dictionary) -> String:
	var keys := ["sides_sequence", "repeat_count", "bpm", "duration_sec", "music_path", "music_start_offset_sec", "boss_name", "boss_health", "events", "tutorial_speaker", "tutorial_lines"]
	var lines := PackedStringArray(["# Polyrhythm custom level"])
	for key in keys:
		if data.has(key):
			lines.append("%s: %s" % [key, JSON.stringify(data[key])])
	return "\n".join(lines) + "\n"


func dictionary() -> Dictionary:
	return _yaml.duplicate(true)


func clamped_music_start_offset(stream_length_sec: float) -> float:
	if stream_length_sec <= 0.0:
		return maxf(music_start_offset_sec, 0.0)
	return clampf(music_start_offset_sec, 0.0, stream_length_sec)


func boss_damage(result: String, guard_note: bool) -> int:
	if guard_note:
		return 8 if result == "Perfect" else 0
	return 2 if result == "Perfect" else 1 if result == "Fast" or result == "Slow" else 0
