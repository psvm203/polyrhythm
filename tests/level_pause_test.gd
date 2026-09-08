extends SceneTree

const LevelScene := preload("res://level/level.tscn")

var _failures := 0
var _assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level = LevelScene.instantiate()
	root.add_child(level)
	level.countdown.countdown_finished.disconnect(level._on_countdown_finished)
	level.dialogue_overlay.hide()
	level.rotator.restart_current_transition()
	var now := [1_000_000]
	level.conductor.time_source_usec = func() -> int: return now[0]
	level.conductor.detailed_timing_logs = false
	level._on_countdown_finished()
	await physics_frame
	await process_frame
	level._event_system.setup([{"name": "time_stop", "at": [2], "duration_sec": 0.01}])
	now[0] += 500_000
	level.conductor._process(0.0)
	var progress: float = level.rotator.get_transition_elapsed()

	# The boss timer completes while the menu still owns a pause.
	level._trigger_time_stop()
	level._set_game_paused(true)
	now[0] += 2_000_000
	await create_timer(0.05).timeout
	_expect(not level._time_stopped, "boss timer finishes while menu is open")
	_expect(level.conductor.paused and level.rotator.paused, "menu keeps clock and geometry paused")
	_expect(level.music.stream_paused, "menu keeps music paused after boss timer")
	_expect(is_equal_approx(level.rotator.get_transition_elapsed(), progress), "visual elapsed stays frozen")
	level._set_game_paused(false)
	_expect(not level.conductor.paused and not level.rotator.paused, "closing last pause resumes gameplay")
	_expect(not level.music.stream_paused, "closing last pause resumes audio")
	_expect(is_equal_approx(level.conductor._get_game_time(), 0.5), "overlapping pauses exclude elapsed wall time")

	# Closing the menu first must leave the boss pause intact.
	level._trigger_time_stop()
	level._set_game_paused(true)
	level._set_game_paused(false)
	_expect(level.conductor.paused and level.music.stream_paused, "menu resume cannot cancel boss pause")
	await create_timer(0.05).timeout
	_expect(not level.conductor.paused and not level.rotator.paused, "boss timer resumes after menu closes")
	_expect(not level.music.stream_paused, "boss timer resumes music")

	# A long update stops on the event polygon instead of missing beyond it.
	now[0] += 5_000_000
	level.conductor._process(0.0)
	_expect(level._time_stopped and level.conductor.paused, "catch-up enters boss stop synchronously")
	_expect(level.rotator.current_index == 1, "catch-up cannot skip the event polygon")
	_expect(level._run_state.resolved_notes == 1, "only preceding note resolves before the stop")
	level.conductor.pause_clock()
	await create_timer(0.05).timeout
	level.music.stream_paused = false
	level.music.stop()
	# Allow the audio thread to release its playback before terminating the test.
	await create_timer(0.6).timeout
	level.free()
	print("Level pause tests: %d assertions, %d failures" % [_assertions, _failures])
	quit(1 if _failures else 0)


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures += 1
		push_error(message)
