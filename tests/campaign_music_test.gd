extends SceneTree

const Catalog = preload("res://level/data/stage_catalog.gd")
const Data = preload("res://level/data/level_data.gd")
const Progress = preload("res://level/progress_store.gd")
const LevelScene = preload("res://level/level.tscn")
const MainScene = preload("res://main/main_screen.tscn")

var failures := 0
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_save_path := Progress.save_path
	Progress.save_path = "/tmp/polyrhythm_campaign_progress_%d.cfg" % OS.get_process_id()
	var original_stage := Progress.selected_stage
	var reports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://docs/music_maps.json"))
	var music_paths := {}
	for stage in Catalog.stage_numbers():
		Progress.selected_stage = stage
		var data = Data.from_yaml(Catalog.data_path(stage))
		expect(Data.validate(data.dictionary()).is_empty(), "stage %d chart validates" % stage)
		expect(not music_paths.has(data.music_path), "stage %d uses its own music" % stage)
		music_paths[data.music_path] = true
		var level = LevelScene.instantiate()
		level.timing_trace_path = "/tmp/polyrhythm_campaign_trace.json"
		root.add_child(level)
		level.countdown.countdown_finished.disconnect(level._on_countdown_finished)
		level.countdown.hide()
		var now := [1_000_000]
		level.conductor.time_source_usec = func() -> int: return now[0]
		level.conductor.detailed_timing_logs = false
		level.conductor.judgment_offset_sec = 0.0
		level._on_countdown_finished()
		var times: PackedFloat32Array = level.conductor.scheduled_judgment_times
		expect(times.size() == level._level_sequence.size(), "expanded geometry has one onset per polygon")
		expect(level.music.stream != null and level.music.stream.get_length() + 0.01 >= data.duration_sec, "music covers full stage")
		if stage == 2:
			expect(data.tutorial_lines.is_empty() and data.events.is_empty(), "reconstruction has no story or boss events")
			expect(level.get_node("BackgroundLayer/Background").restoration != null, "stage two loads reconstruction visuals")
		var report: Dictionary = reports[stage - 1]
		for index in times.size():
			var source_time: float = report["note_times_sec"][index]
			expect(absf(times[index] - source_time) <= 0.00001, "note matches packaged audio attack")
			now[0] = 1_000_000 + ceili(times[index] * 1_000_000)
			level.conductor._process(0.0)
			expect(level.rotator.get_entrance_edge_gap() < 0.1, "polygon edges meet on the audio attack")
			var tap := InputEventKey.new()
			tap.physical_keycode = KEY_SPACE
			tap.pressed = true
			level.conductor._unhandled_input(tap)
			# Time-stop pauses both clock and audio; the deterministic clock stays fixed.
			if level._time_stopped:
				await create_timer(0.7).timeout
			expect(level._run_state.resolved_notes == index + 1, "audio-timed input resolves exactly one polygon")
			expect(level._run_state.judgments["Perfect"] == index + 1, "all audio attacks score Perfect")
		if stage == 2:
			var city = level.get_node("BackgroundLayer/Background").restoration
			expect(is_equal_approx(city.target_progress, 1.0), "final note finishes reconstruction")
			city._process(5.0)
			expect(is_equal_approx(city.progress, 1.0), "restoration animation reaches complete city")
		expect(not level._level_ended, "music tail remains playable until configured end")
		now[0] = 1_000_000 + ceili(data.duration_sec * 1_000_000)
		level._process(0.0)
		expect(level._level_ended and not level.music.playing, "stage and music end together")
		expect(level._boss_health == 0, "boss health is achievable with generated chart")
		level.free()
	# Start locked, then exercise the actual settings button and reloaded persistence.
	var config := ConfigFile.new()
	config.set_value("progress", "highest_unlocked_stage", 1)
	config.set_value("stage_1", "score", 12345)
	config.save(Progress.save_path)
	var main = MainScene.instantiate()
	root.add_child(main)
	await process_frame
	expect(main._stage_buttons().size() == 9, "all nine cards are present")
	expect(main._stage_buttons()[8].disabled, "Matadora starts locked")
	main.get_node("%UnlockAllStagesButton").pressed.emit()
	expect(Progress.highest_unlocked_stage() == 9, "settings unlock persists all nine stages")
	expect(Progress.stage_record(1)["score"] == 12345, "unlock preserves existing records")
	for button in main._stage_buttons():
		expect(not button.disabled, "unlock immediately enables every stage card")
	expect(main.get_node("%UnlockAllStagesButton").text == "해금 완료", "settings confirms unlock")
	main.stage_screen.show()
	await process_frame
	await process_frame
	var cards: GridContainer = main.get_node("StageScreen/StageLayout/CardsSlot/Cards")
	var stage_nine: BaseButton = main._stage_buttons()[8]
	expect(stage_nine.get_node(stage_nine.focus_neighbor_top) == main._stage_buttons()[3], "Matadora keyboard focus reaches the card above")
	expect(main._stage_buttons()[3].get_node(main._stage_buttons()[3].focus_neighbor_bottom) == stage_nine, "keyboard focus reaches Matadora from the first row")
	for card in cards.get_children():
		expect(main.get_global_rect().encloses(card.get_global_rect()), "stage card fits in viewport")
		expect(card.get_global_rect().encloses(card.get_node("Items/Best").get_global_rect()), "record text fits inside card")
	main.settings_screen.show()
	await process_frame
	var unlock_button: Button = main.get_node("%UnlockAllStagesButton")
	expect(main.get_global_rect().encloses(unlock_button.get_global_rect()), "unlock button fits in settings viewport")
	var reset_button: Button = main.get_node("%ResetRecordsButton")
	expect(main.get_global_rect().encloses(reset_button.get_global_rect()), "reset button fits in settings viewport")
	Progress.mark_dialogue_seen("stage_1_tutorial")
	Progress.mark_stage_played(8)
	reset_button.pressed.emit()
	expect(main.get_node("%ResetRecordsDialog").visible, "reset asks for confirmation")
	expect(Progress.stage_record(1)["score"] == 12345, "opening confirmation preserves records")
	main.get_node("%ResetRecordsDialog").hide()
	main.get_node("%ResetRecordsDialog").canceled.emit()
	expect(Progress.highest_unlocked_stage() == 9, "cancel preserves unlocks")
	main.get_node("%ResetRecordsDialog").confirmed.emit()
	expect(Progress.highest_unlocked_stage() == 1 and Progress.last_played_stage() == 1, "reset restores initial progress")
	expect(Progress.pending_unlock_dialogue() == 0 and not Progress.has_seen_dialogue("stage_1_tutorial"), "reset clears dialogue history")
	for stage in Catalog.stage_numbers():
		expect(Progress.stage_record(stage)["score"] == 0 and not Progress.stage_record(stage)["cleared"], "reset clears every stage record")
	expect(main._stage_buttons()[7].disabled and not main.get_node("%UnlockAllStagesButton").disabled, "reset refreshes cards and unlock action")
	main.background_music.stop()
	main.stage_preview_music.stop()
	main.queue_free()
	# Release outstanding countdown timers and audio playback references.
	await create_timer(1.2).timeout
	Progress.selected_stage = original_stage
	DirAccess.remove_absolute(Progress.save_path)
	Progress.save_path = original_save_path
	DirAccess.remove_absolute("/tmp/polyrhythm_campaign_trace.json")
	print("Campaign music tests: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)


func expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)
