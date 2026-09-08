extends SceneTree

const LevelScene := preload("res://level/level.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level = LevelScene.instantiate()
	var trace_path := "/tmp/polyrhythm_gameplay_runtime_trace.json"
	level.timing_trace_path = trace_path
	get_root().add_child(level)
	await process_frame
	if level.countdown.countdown_finished.is_connected(level._on_countdown_finished):
		level.countdown.countdown_finished.disconnect(level._on_countdown_finished)
	level.dialogue_overlay.hide()
	level.rotator.restart_current_transition()
	var now := [1_000_000]
	level.conductor.time_source_usec = func() -> int: return now[0]
	level.conductor.judgment_offset_sec = 0.0
	level._on_countdown_finished()
	now[0] += 250_000
	var input := InputEventKey.new()
	input.physical_keycode = KEY_SPACE
	input.pressed = true
	level.conductor._unhandled_input(input)
	# Six misses exhaust the starting gauge; derive the deadline from this stage.
	now[0] = 1_000_000 + roundi((level.conductor.scheduled_judgment_times[5] + 0.2) * 1_000_000)
	level.conductor._process(0.0)
	_expect(level.conductor.paused, "gameplay clock pauses on result")
	_expect(level.conductor.game_time > 0.5, "gameplay clock advances before result")
	_expect(not level.music.playing, "level music stops when result opens")
	_expect(level.rotator.current_index > 0, "overdue notes advance during gameplay")
	_expect(level.conductor.timing_trace.size() == 1, "gameplay input is recorded without runtime errors")
	_expect(level._level_ended, "failed run reaches result flow without runtime errors")
	_expect(level.result_overlay.visible, "failed run shows the result overlay")
	_expect(FileAccess.file_exists(trace_path), "failed run persists its timing trace")
	DirAccess.remove_absolute(trace_path)
	level.queue_free()
	if _failures > 0:
		push_error("Gameplay runtime tests failed: %d" % _failures)
		quit(1)
		return
	print("Gameplay runtime tests passed: 8 assertions")
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
