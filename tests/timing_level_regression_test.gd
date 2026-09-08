extends SceneTree

const LevelDataScript = preload("res://level/data/level_data.gd")
const EventSystemScript = preload("res://level/events/level_event_system.gd")
const TimelineScript = preload("res://level/timing/note_timeline.gd")

const STAGES := [
	"res://level/data/level_1.yaml",
	"res://level/data/level_2.yaml",
	"res://level/data/level_3.yaml",
	"res://level/data/level_4.yaml",
	"res://level/data/level_5.yaml",
	"res://level/data/level_6.yaml",
	"res://level/data/level_7.yaml",
	"res://level/data/level_8.yaml",
]

var _assertions := 0
var _failures := 0


func _init() -> void:
	for stage_index in STAGES.size():
		_test_stage(stage_index + 1, STAGES[stage_index])
	_test_editor_round_trip()
	_finish()


func _test_stage(stage_number: int, path: String) -> void:
	var data = LevelDataScript.from_yaml(path)
	_expect(data.bpm > 0.0, "stage %d BPM remains valid" % stage_number)
	_expect(FileAccess.file_exists(data.music_path), "stage %d music remains available" % stage_number)
	var original: Array[int] = data.expanded_sequence()
	var events = EventSystemScript.new()
	events.setup(data.events)
	var transformed: Array[int] = events.transform_sequence(original)
	var timeline = TimelineScript.build(transformed, data.bpm, 0.025, 0.050, 0.100, 0.0, data.note_times_sec)
	_expect(timeline.size() == transformed.size(), "stage %d timeline preserves transformed note count" % stage_number)
	var legacy_cursor := 0.0
	for index in transformed.size():
		legacy_cursor = data.note_times_sec[index]
		var entry: Dictionary = timeline.entry(index)
		_expect_approx(entry["contact_sec"], legacy_cursor, "stage %d note %d contact matches audio onset" % [stage_number, index + 1])
		_expect_approx(entry["judgment_sec"], legacy_cursor, "stage %d note %d center matches visible contact" % [stage_number, index + 1])
		_expect(float(entry["miss_after_sec"]) > float(entry["perfect_end_sec"]), "stage %d note %d windows remain ordered" % [stage_number, index + 1])
	_expect_approx(timeline.duration_sec(), legacy_cursor, "stage %d timeline ends on its last audio onset" % stage_number)
	if stage_number == 3:
		_expect(transformed.size() >= original.size(), "samurai replacements never drop notes")
		_expect(transformed.count(3) > original.count(3), "samurai split produces triangle beats")
	else:
		_expect(transformed.size() == original.size(), "stage %d event keeps note count" % stage_number)


func _test_editor_round_trip() -> void:
	var custom := {
		"sides_sequence": [3, 4, 5],
		"repeat_count": 2,
		"bpm": 1800.0,
		"music_path": "res://level/data/BR-Freaky_feat_LezaLee_-fulllength-loopable-121_9BPM-Dm.WAV",
		"music_start_offset_sec": 1.25,
		"boss_name": "",
		"boss_health": 0,
		"events": [],
		"tutorial_speaker": "",
		"tutorial_lines": [],
	}
	var path := "/tmp/polyrhythm_timing_custom_level.yaml"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(LevelDataScript.to_yaml(custom))
	file.close()
	var loaded = LevelDataScript.from_yaml(path)
	var sequence: Array[int] = loaded.expanded_sequence()
	_expect(sequence == [3, 4, 5, 3, 4, 5], "editor YAML round-trip preserves sequence")
	_expect_approx(loaded.bpm, 1800.0, "editor YAML round-trip preserves BPM")
	_expect_approx(loaded.music_start_offset_sec, 1.25, "editor YAML round-trip preserves music offset")
	var timeline = TimelineScript.build(sequence, loaded.bpm, 0.025, 0.050, 0.100)
	_expect(timeline.size() == 6, "custom level creates playable timeline")
	var expected_duration := float(3 + 4 + 5 + 3 + 4 + 5) * 120.0 / 1800.0
	_expect_approx(timeline.duration_sec(), expected_duration, "custom level preview and gameplay share duration")
	DirAccess.remove_absolute(path)


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) <= 0.00001, message)


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error(message)


func _finish() -> void:
	if _failures > 0:
		push_error("Timing level regression tests failed: %d of %d" % [_failures, _assertions])
		quit(1)
		return
	print("Timing level regression tests passed: %d assertions" % _assertions)
	quit()
