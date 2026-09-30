extends SceneTree

const LevelScene := preload("res://level/level.tscn")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var progress = preload("res://level/progress_store.gd")
	progress.save_path = "/tmp/polyrhythm_gameplay_progress_%d.cfg" % OS.get_process_id()
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
	var displayed_results: Array[String] = []
	level.conductor.judged.connect(func(_result, _index, _delta): displayed_results.append(level.judgement.label.text))
	level._on_countdown_finished()
	now[0] += 250_000
	var input := InputEventKey.new()
	input.physical_keycode = KEY_SPACE
	input.pressed = true
	level.conductor._unhandled_input(input)
	# Six misses exhaust the starting gauge; derive the deadline from this stage.
	now[0] = 1_000_000 + roundi((level.conductor.scheduled_judgment_times[5] + 0.2) * 1_000_000)
	level.conductor._process(0.0)
	_expect(displayed_results.size() == 7, "early input and all six misses still emit judgments")
	_expect(displayed_results[0] == "Too Fast" and displayed_results[1] == "Too Fast", "Too Slow immediately after Too Fast does not replace the label")
	_expect(displayed_results[2] == "Too Slow", "the following Too Slow displays normally")
	_expect(level._run_state.judgments["Too Slow"] == 6 and level._run_state.gauge == 0.0, "hidden Too Slow still counts and depletes the gauge")
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
	# A successful Stage 1 keeps playing through the tail, then ends at 55s.
	var timed_level = LevelScene.instantiate()
	timed_level.timing_trace_path = trace_path
	get_root().add_child(timed_level)
	timed_level.countdown.countdown_finished.disconnect(timed_level._on_countdown_finished)
	timed_level.dialogue_overlay.hide()
	timed_level.rotator.restart_current_transition()
	now[0] = 1_000_000
	timed_level.conductor.time_source_usec = func() -> int: return now[0]
	timed_level.conductor.judgment_offset_sec = 0.0
	timed_level.conductor.detailed_timing_logs = false
	timed_level._on_countdown_finished()
	_expect(timed_level.level_data.duration_sec == 55.0, "stage one has a 55-second duration")
	for contact in timed_level.conductor.scheduled_judgment_times:
		_expect(contact < 55.0, "stage one has no notes beyond the cutoff")
		now[0] = 1_000_000 + ceili(contact * 1_000_000)
		timed_level.conductor._unhandled_input(input)
	_expect(timed_level._run_state.resolved_notes == timed_level._run_state.total_notes, "all shortened stage notes resolve")
	_expect(not timed_level._level_ended and timed_level.music.playing, "final note leaves music playing until cutoff")
	now[0] = 55_999_000
	timed_level._process(0.0)
	_expect(not timed_level._level_ended, "stage remains active at 54.999 seconds")
	timed_level._set_game_paused(true)
	now[0] += 5_000_000
	timed_level._set_game_paused(false)
	timed_level._process(0.0)
	_expect(not timed_level._level_ended, "pause time does not count toward cutoff")
	now[0] += 1_000
	timed_level._process(0.0)
	_expect(timed_level._level_ended and timed_level.result_overlay.visible, "55 seconds opens the result screen")
	_expect(not timed_level.music.playing and timed_level.conductor.paused, "55 seconds stops music and gameplay together")
	DirAccess.remove_absolute(trace_path)
	current_scene = timed_level
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.physical_keycode = KEY_ESCAPE
	cancel.pressed = true
	get_root().push_input(cancel)
	_expect(get_root().is_input_handled(), "result consumes Escape before leaving the scene")
	await scene_changed
	_expect(current_scene.scene_file_path == "res://main/main_screen.tscn", "Escape from result returns to the main scene")
	for _frame in range(180):
		await process_frame
		if not current_scene._transition_controller.is_transitioning():
			break
	_expect(current_scene.get_node("StageScreen").visible, "Escape returns to stage selection")
	current_scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(progress.save_path)
	if _failures > 0:
		push_error("Gameplay runtime tests failed: %d" % _failures)
		quit(1)
		return
	print("Gameplay runtime tests passed")
	quit()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
