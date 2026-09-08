extends SceneTree

const NoteTimelineScript = preload("res://level/timing/note_timeline.gd")

var _assertions := 0
var _failures := 0


func _init() -> void:
	var timeline = NoteTimelineScript.build([3, 4], 120.0, 0.025, 0.050, 0.100, 0.010)
	_expect(timeline.size() == 2, "timeline contains every note")
	_expect(not timeline.is_empty(), "timeline reports content")
	var first: Dictionary = timeline.entry(0)
	_expect_approx(first["move_start_sec"], 0.0, "first movement starts at zero")
	_expect_approx(first["duration_sec"], 3.0, "triangle duration follows BPM")
	_expect_approx(first["contact_sec"], 3.0, "first contact is cumulative")
	_expect_approx(first["judgment_sec"], 3.01, "offset moves judgment center")
	_expect_approx(first["too_fast_before_sec"], 2.96, "early boundary is precomputed")
	_expect_approx(first["perfect_start_sec"], 2.985, "Perfect start is precomputed")
	_expect_approx(first["perfect_end_sec"], 3.035, "Perfect end is precomputed")
	_expect_approx(first["miss_after_sec"], 3.11, "miss deadline is precomputed")
	var second: Dictionary = timeline.entry(1)
	_expect_approx(second["move_start_sec"], 3.0, "second movement follows first contact")
	_expect_approx(second["contact_sec"], 7.0, "second contact is cumulative")
	_expect_approx(timeline.duration_sec(), 7.0, "duration returns final contact")
	_expect(timeline.contact_times() == PackedFloat32Array([3.0, 7.0]), "contact array is compatible with conductor")
	first["contact_sec"] = 99.0
	_expect_approx(timeline.entry(0)["contact_sec"], 3.0, "entries are returned as immutable copies")
	_expect(timeline.entry(-1).is_empty(), "invalid index is safe")
	var chart = NoteTimelineScript.build([6, 3], 121.9, 0.025, 0.050, 0.100, 0.010, PackedFloat32Array([0.97, 1.46]))
	_expect_approx(chart.entry(0)["contact_sec"], 0.97, "hexagon lands on explicit audio onset")
	_expect_approx(chart.entry(1)["duration_sec"], 0.49, "next polygon uses the gap between audio onsets")
	_expect_approx(chart.entry(1)["judgment_sec"], 1.47, "calibration offset applies to audio-timed notes")
	_finish()


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(is_equal_approx(actual, expected), message)


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error(message)


func _finish() -> void:
	if _failures > 0:
		push_error("Note timeline tests failed: %d of %d" % [_failures, _assertions])
		quit(1)
		return
	print("Note timeline tests passed: %d assertions" % _assertions)
	quit()
