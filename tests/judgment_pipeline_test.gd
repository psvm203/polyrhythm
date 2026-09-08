extends SceneTree

const JudgmentPipelineScript = preload("res://level/timing/judgment_pipeline.gd")

var _assertions := 0
var _failures := 0


func _init() -> void:
	var pipeline = JudgmentPipelineScript.new()
	pipeline.configure(0.025, 0.050, 0.100)
	var cases := {
		-0.051: "Too Fast",
		-0.050: "Fast",
		-0.025: "Perfect",
		0.000: "Perfect",
		0.025: "Perfect",
		0.026: "Slow",
		0.100: "Slow",
		0.101: "Too Slow",
	}
	for delta in cases:
		_expect(pipeline.classify_delta(delta) == cases[delta], "classifies %.3f" % delta)
	var early: Dictionary = pipeline.evaluate(9.97, 10.0)
	_expect(early["result"] == "Fast", "evaluation returns result")
	_expect_approx(early["delta_ms"], -30.0, "evaluation returns millisecond delta")
	_expect(early["defer_until_contact"], "accepted early input is deferred")
	_expect(early["advance_note"], "accepted input advances note")
	var too_early: Dictionary = pipeline.evaluate(9.90, 10.0)
	_expect(not too_early["advance_note"], "Too Fast keeps current note")
	_expect(not pipeline.is_miss_due(10.1, 10.0), "late edge remains playable")
	_expect(pipeline.is_miss_due(10.101, 10.0), "past late edge is missed")
	pipeline.configure(0.040, 0.020, 0.010)
	_expect_approx(pipeline.early_window_sec, 0.040, "invalid early window is normalized")
	_expect_approx(pipeline.late_window_sec, 0.040, "invalid late window is normalized")
	pipeline.configure(0.025, 0.050, 0.100)
	_expect(pipeline.overdue_count(PackedFloat32Array([1.0, 2.0, 3.0]), 0, 2.5) == 2, "long frame catches every overdue note")
	_expect(pipeline.overdue_count(PackedFloat32Array([1.0, 2.0, 3.0]), 2, 2.5) == 0, "catch-up respects current note")
	var negative_offset: Dictionary = pipeline.evaluate(0.9, 0.9, 1.0)
	_expect(negative_offset["defer_until_contact"], "negative offset exact hit waits for visual contact")
	var positive_offset: Dictionary = pipeline.evaluate(1.08, 1.1, 1.0)
	_expect(not positive_offset["defer_until_contact"], "positive offset early hit after contact displays immediately")
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
		push_error("Judgment pipeline tests failed: %d of %d" % [_failures, _assertions])
		quit(1)
		return
	print("Judgment pipeline tests passed: %d assertions" % _assertions)
	quit()
