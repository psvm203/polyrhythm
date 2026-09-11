extends SceneTree

const Settings = preload("res://main/settings_store.gd")
const Progress = preload("res://level/progress_store.gd")
const MainScene = preload("res://main/main_screen.tscn")
const LevelScene = preload("res://level/level.tscn")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_settings_path := Settings.save_path
	var original_progress_path := Progress.save_path
	Settings.save_path = "/tmp/polyrhythm_demo_settings_%d.cfg" % OS.get_process_id()
	Progress.save_path = "/tmp/polyrhythm_demo_progress_%d.cfg" % OS.get_process_id()
	var trace_path := "/tmp/polyrhythm_demo_trace_%d.json" % OS.get_process_id()
	expect(not Settings.load_settings()["demo_mode"], "demo mode defaults to off")
	var main = MainScene.instantiate()
	root.add_child(main)
	var toggle: Button = main.get_node("%DemoModeToggle")
	toggle.button_pressed = true
	expect(Settings.load_settings()["demo_mode"], "main toggle persists demo mode")
	main._initialize_settings()
	expect(toggle.button_pressed and toggle.text == "On", "main settings restores the saved toggle")
	main.settings_screen.show()
	await process_frame
	await process_frame
	expect(main.get_global_rect().encloses(toggle.get_global_rect()), "demo mode toggle fits in main settings")
	main.free()
	var level = LevelScene.instantiate()
	level.timing_trace_path = trace_path
	root.add_child(level)
	level.countdown.countdown_finished.disconnect(level._on_countdown_finished)
	level.countdown.hide()
	level.dialogue_overlay.hide()
	var now := [1_000_000]
	level.conductor.time_source_usec = func() -> int: return now[0]
	level.conductor.judgment_offset_sec = 0.0
	level.conductor.detailed_timing_logs = false
	level._on_countdown_finished()
	expect(level._run_state.demo_mode, "level loads demo mode from settings")
	level._set_game_paused(true)
	var pause_toggle: Button = level.pause_overlay.get_node("%DemoModeToggle")
	expect(pause_toggle.button_pressed, "pause toggle matches saved mode")
	pause_toggle.button_pressed = false
	expect(not level._run_state.demo_mode and not Settings.load_settings()["demo_mode"], "pause toggle disables mode immediately and saves")
	pause_toggle.button_pressed = true
	expect(level._run_state.demo_mode and Settings.load_settings()["demo_mode"], "pause toggle enables mode immediately and saves")
	await process_frame
	expect(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(pause_toggle.get_global_rect()), "demo mode toggle fits in pause menu")
	level._set_game_paused(false)
	var times: PackedFloat32Array = level.conductor.scheduled_judgment_times
	now[0] = 1_000_000 + ceili((times[7] + 0.2) * 1_000_000)
	level.conductor._process(0.0)
	expect(level._run_state.gauge == 0.0 and level._run_state.resolved_notes == 8, "demo mode resolves misses beyond depleted health")
	expect(not level._level_ended and level.music.playing and not level.conductor.paused, "depleted health leaves gameplay and music running")
	now[0] = 1_000_000 + ceili(level.level_data.duration_sec * 1_000_000)
	level.conductor._process(0.0)
	level._process(0.0)
	expect(level._run_state.resolved_notes == level._run_state.total_notes, "demo mode resolves the entire chart")
	expect(level._level_ended and level.result_overlay.visible and not level.music.playing, "demo mode ends normally at the music cutoff")
	level.free()
	await create_timer(1.2).timeout
	DirAccess.remove_absolute(Settings.save_path)
	DirAccess.remove_absolute(Progress.save_path)
	DirAccess.remove_absolute(trace_path)
	Settings.save_path = original_settings_path
	Progress.save_path = original_progress_path
	print("Demo mode tests: %d failures" % failures)
	quit(1 if failures else 0)


func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
