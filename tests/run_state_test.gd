extends SceneTree

const RunStateScript = preload("res://level/run_state.gd")

var _failures := 0


func _init() -> void:
	_test_successful_run()
	_test_failed_run()
	_test_demo_mode()
	if _failures == 0:
		print("Run state tests passed: 18 assertions")
		quit(0)
	else:
		push_error("Run state tests failed: %d assertion(s)" % _failures)
		quit(1)


func _test_successful_run() -> void:
	var state := RunStateScript.new()
	state.setup(2)
	state.apply_judgment("Too Fast", 0, -80.0)
	state.apply_judgment("Too Fast", 0, -75.0)
	state.apply_judgment("Perfect", 0, -10.0)
	state.apply_judgment("Slow", 1, 30.0)
	_expect(state.resolved_notes == 2, "all notes resolve")
	_expect(state.score == 1700, "score accumulates")
	_expect(state.max_combo == 2, "combo accumulates")
	_expect(is_equal_approx(state.accuracy(), 85.0), "accuracy is calculated")
	_expect(state.rank() == "A", "completed run receives rank")
	_expect(is_equal_approx(state.average_offset_ms(), 10.0), "average timing offset is calculated")
	_expect(is_equal_approx(state.mean_absolute_error_ms(), 20.0), "mean absolute timing error is calculated")
	_expect(state.early_inputs == 1, "repeated early input on one note is counted once")
	state.setup(1)
	_expect(state.score == 0 and state.resolved_notes == 0 and state.gauge == state.START_GAUGE, "setup resets reusable state")


func _test_failed_run() -> void:
	var state := RunStateScript.new()
	var failed := [false]
	state.failed.connect(func() -> void: failed[0] = true)
	state.setup(10)
	for index in 6:
		state.apply_judgment("Too Slow", index)
	_expect(failed[0], "empty gauge emits failure")
	_expect(state.gauge == 0.0, "gauge is clamped at zero")
	_expect(state.rank(false) == "F", "failed run receives F rank")
	var resolved_before := state.resolved_notes
	state.apply_judgment("Perfect", 7)
	_expect(state.resolved_notes == resolved_before, "failed run ignores later judgments")


func _test_demo_mode() -> void:
	var state := RunStateScript.new()
	var failures := [0]
	state.failed.connect(func() -> void: failures[0] += 1)
	state.demo_mode = true
	state.setup(30)
	for index in 8:
		state.apply_judgment("Too Slow", index)
	_expect(failures[0] == 0 and state.gauge == 0.0, "demo mode suppresses failure at zero gauge")
	_expect(state.resolved_notes == 8, "demo mode keeps resolving misses after zero gauge")
	state.apply_judgment("Perfect", 8)
	_expect(state.score == 1000 and state.gauge == 2.0, "demo mode keeps scoring and recovering health")
	state.apply_judgment("Too Fast", 9)
	_expect(failures[0] == 0 and state.gauge == 0.0, "early input cannot end demo mode")
	state.demo_mode = false
	state.apply_judgment("Too Slow", 9)
	_expect(failures[0] == 1, "turning demo mode off restores failure on the next miss")


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
