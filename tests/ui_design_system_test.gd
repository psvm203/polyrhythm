extends SceneTree

const MAIN_SCENE := preload("res://main/main_screen.tscn")
const PAUSE_SCENE := preload("res://level/ui/pause_overlay.tscn")
const RESULT_SCENE := preload("res://level/ui/result_overlay.tscn")
const CALIBRATION_SCENE := preload("res://main/timing_calibration_overlay.tscn")
const EDITOR_SCENE := preload("res://editor/level_editor.tscn")
const STAGE_RECORD_SCRIPT := preload("res://main/stage_record.gd")
const GAMEPLAY_HUD_SCENE := preload("res://level/ui/gameplay_hud.tscn")
const GAMEPLAY_HUD_SCRIPT := preload("res://level/ui/gameplay_hud.gd")
const THEME := preload("res://main/poly_theme.tres")

var _assertions := 0
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_theme_tokens()
	_test_main_settings_layout()
	_test_pause_layout()
	_test_gameplay_hud_layout()
	_test_overlay_theme_inheritance()
	_test_level_editor_localization()
	await _test_result_timing_feedback()
	if _failures > 0:
		push_error("UI design system tests failed: %d of %d assertions" % [_failures, _assertions])
		quit(1)
		return
	print("UI design system tests passed: %d assertions" % _assertions)
	quit()


func _test_theme_tokens() -> void:
	for state in [&"normal", &"hover", &"focus", &"pressed", &"disabled"]:
		_expect(THEME.has_stylebox(state, &"Button"), "button %s style exists" % state)
	_expect(THEME.get_font_size(&"font_size", &"Button") >= 20, "button text remains readable")
	var normal := THEME.get_stylebox(&"normal", &"Button")
	_expect(normal.content_margin_left >= 18.0, "button has horizontal breathing room")
	_expect(normal.content_margin_top >= 10.0, "button has vertical breathing room")


func _test_main_settings_layout() -> void:
	var scene := MAIN_SCENE.instantiate()
	var settings_layout: Control = scene.get_node("SettingsScreen/SettingsLayout")
	var logo: Control = settings_layout.get_node("SmallLogo")
	var panel: Control = settings_layout.get_node("SettingsPanelSlot/SettingsPanel")
	var rows: VBoxContainer = panel.get_node("Margin/Rows")
	_expect(not logo.visible, "settings title logo is hidden to reserve vertical space")
	_expect(settings_layout.offset_bottom - settings_layout.offset_top >= 860.0, "settings layout uses available vertical space")
	_expect(panel.custom_minimum_size.y >= 840.0, "settings panel shows all options")
	_expect(rows.get_theme_constant("separation") >= 8, "settings rows have clear separation")
	for row_name in ["Master", "Music", "Sfx", "Vibration", "Timing"]:
		var row: HBoxContainer = rows.get_node(row_name)
		_expect(row.get_theme_constant("separation") >= 14, "%s controls are separated" % row_name)
		var slider: HSlider = row.get_node(row_name + "Slider")
		_expect(slider.custom_minimum_size.x >= 340.0, "%s slider remains easy to target" % row_name)
	_expect(rows.get_node("Timing/Label").text == "입력 오프셋", "main settings names the timing offset directly")
	var calibration_button: Button = rows.get_node("Timing/CalibrationButton")
	var enabled_button: Button = rows.get_node("Master/MasterEnabled")
	_expect(calibration_button.text == "보정", "main settings uses the concise calibration action")
	_expect(calibration_button.get_theme_stylebox("normal") == enabled_button.get_theme_stylebox("pressed"), "calibration action uses the enabled toggle surface")
	var calibration_color := calibration_button.get_theme_color("font_color")
	_expect(calibration_color.g >= 0.95 and calibration_color.b >= 0.9, "calibration action uses the enabled cyan text color")
	var cards: GridContainer = scene.get_node("StageScreen/StageLayout/CardsSlot/Cards")
	var stage_names := ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight"]
	for index in stage_names.size():
		var stage: PanelContainer = cards.get_child(index)
		var button: Button = stage.get_node("Stage%sButton" % stage_names[index])
		_expect(button.get_theme_stylebox("focus") is StyleBoxEmpty, "stage %d focus keeps card content visible" % (index + 1))
	_expect(STAGE_RECORD_SCRIPT.LOCK_OFFSET_Y >= 32.0, "locked-stage padlock sits clearly below the disc center")
	scene.free()


func _test_pause_layout() -> void:
	var scene := PAUSE_SCENE.instantiate()
	var panel: Control = scene.get_node("Dimmer/Center/Panel")
	var rows: VBoxContainer = panel.get_node("Margin/Rows")
	_expect(panel.custom_minimum_size.y >= 700.0, "pause settings panel fits every row")
	_expect(rows.get_theme_constant("separation") >= 8, "pause rows have clear separation")
	for row_name in ["Master", "Music", "Sfx", "Vibration", "Timing"]:
		var row: HBoxContainer = rows.get_node(row_name)
		_expect(row.get_theme_constant("separation") >= 12, "pause %s controls are separated" % row_name)
		var slider: HSlider = row.get_node(row_name + "Slider")
		_expect(slider.size_flags_vertical == Control.SIZE_SHRINK_CENTER, "pause %s slider is vertically centered" % row_name)
	_expect(rows.get_node("Timing/Label").text == "입력 오프셋", "pause settings names the timing offset directly")
	_expect(rows.get_node("Timing/CalibrationButton").text == "보정", "pause settings exposes timing calibration")
	var footer_spacer: Control = rows.get_node("FooterSpacer")
	_expect(footer_spacer.size_flags_vertical == Control.SIZE_EXPAND_FILL, "pause action spacer pushes buttons to the bottom")
	var footer: HBoxContainer = rows.get_node("FooterButtons")
	_expect(footer.get_index() == rows.get_child_count() - 1, "pause actions remain the final row")
	_expect(footer.get_child_count() == 3, "pause actions share one horizontal row")
	_expect(footer.get_node("ResumeButton").text == "계속하기", "pause menu offers continue")
	_expect(footer.get_node("RestartButton").text == "재시작", "pause menu offers restart")
	_expect(footer.get_node("ExitButton").text == "메인화면", "pause menu offers main screen")
	scene.free()


func _test_gameplay_hud_layout() -> void:
	var hud := GAMEPLAY_HUD_SCENE.instantiate()
	_expect(hud.get_node("Top/Score").text == "000000", "gameplay HUD score omits its label")
	_expect(not hud.has_node("Top/Accuracy"), "gameplay HUD omits accuracy")
	_expect(not hud.has_node("Top/Progress"), "gameplay HUD omits textual progress")
	_expect(not hud.has_node("StageProgress"), "gameplay HUD omits the progress bar")
	var full_color: Color = GAMEPLAY_HUD_SCRIPT.gauge_color(100.0)
	_expect(full_color != GAMEPLAY_HUD_SCRIPT.gauge_color(99.0), "full health has an exclusive color")
	_expect(GAMEPLAY_HUD_SCRIPT.gauge_color(80.0) != GAMEPLAY_HUD_SCRIPT.gauge_color(50.0), "high and medium health colors differ")
	_expect(GAMEPLAY_HUD_SCRIPT.gauge_color(50.0) != GAMEPLAY_HUD_SCRIPT.gauge_color(20.0), "medium and low health colors differ")
	hud.free()


func _test_overlay_theme_inheritance() -> void:
	var result := RESULT_SCENE.instantiate()
	var calibration := CALIBRATION_SCENE.instantiate()
	_expect(result.get_node("Dim").theme == THEME, "result screen uses shared theme")
	_expect(calibration.get_node("Dim").theme == THEME, "calibration screen uses shared theme")
	_expect(result.has_node("FocusCoordinator"), "result screen coordinates input focus")
	_expect(calibration.has_node("FocusCoordinator"), "calibration screen coordinates input focus")
	result.free()
	calibration.free()


func _test_level_editor_localization() -> void:
	var editor := EDITOR_SCENE.instantiate()
	var header: HBoxContainer = editor.get_node("Root/Header")
	_expect(header.get_node("ImportButton").text == "불러오기", "level editor localizes the load action")
	_expect(header.get_node("ExportButton").text == "저장", "level editor localizes the save action")
	_expect(header.get_node("PlayButton").text == "▶ 플레이", "level editor localizes play")
	_expect(header.get_node("UndoButton").tooltip_text.contains("Ctrl+Z"), "level editor exposes undo")
	_expect(header.get_node("RedoButton").tooltip_text.contains("Ctrl+Y"), "level editor exposes redo")
	_expect(editor.get_node("Root/Settings/Rhythm/Rows/Fields/BpmLabel").text == "BPM", "level editor keeps the concise BPM label")
	var grid: GridContainer = editor.get_node("Root/Settings/Rhythm/Rows/Fields")
	_expect(editor.get_node("%EventApply").text == "적용", "level editor localizes event apply")
	_expect(editor.get_node("%EventRemove").text == "제거", "level editor localizes event removal")
	var guide: Control = editor.get_node("GuideOverlay")
	_expect(guide.get_node("Dimmer/Center/Panel/Margin/Rows/Header/HeaderText/Title").text == "레벨 에디터 도움말", "level editor guide title is localized")
	var exit_dialog: ColorRect = editor.get_node("ExitDialog")
	_expect(not exit_dialog.visible, "level editor exit dialog starts hidden")
	editor._show_exit_dialog()
	_expect(exit_dialog.visible, "level editor escape flow opens the exit dialog")
	_expect(editor.get_node("ExitDialog/Center/Panel/Margin/Rows/Buttons/CloseEditorButton").text == "닫기", "level editor exit action is explicit")
	_expect(editor.get_node("ExitDialog/Center/Panel/Margin/Rows/Buttons/ReturnEditorButton").text == "돌아가기", "level editor return action is explicit")
	editor._hide_exit_dialog()
	_expect(not exit_dialog.visible, "return action closes the exit dialog")
	var unsaved_dialog: ColorRect = editor.get_node("UnsavedDialog")
	editor._mark_saved_state("")
	_expect(not editor._has_unsaved_changes(), "level editor starts clean after an explicit baseline")
	grid.get_node("Bpm").value += 1.0
	_expect(editor._has_unsaved_changes(), "level editor detects changes independently of autosave")
	editor._request_import()
	_expect(unsaved_dialog.visible, "loading another level protects unsaved changes")
	var unsaved_buttons: HBoxContainer = unsaved_dialog.get_node("Center/Panel/Margin/Rows/Buttons")
	_expect(unsaved_buttons.get_node("SaveChangesButton").text == "저장", "unsaved dialog offers save")
	_expect(unsaved_buttons.get_node("DiscardChangesButton").text == "버리기", "unsaved dialog offers discard")
	_expect(unsaved_buttons.get_node("CancelChangesButton").text == "취소", "unsaved dialog offers cancel")
	editor._cancel_pending_action()
	_expect(not unsaved_dialog.visible, "cancel keeps the current document open")
	editor._reset_history()
	var original_bpm: float = grid.get_node("Bpm").value
	grid.get_node("Bpm").value = original_bpm + 10.0
	editor._record_document_change()
	editor._undo()
	_expect(is_equal_approx(grid.get_node("Bpm").value, original_bpm), "undo restores document settings")
	editor._redo()
	_expect(is_equal_approx(grid.get_node("Bpm").value, original_bpm + 10.0), "redo reapplies document settings")
	editor.free()


func _test_result_timing_feedback() -> void:
	var result := RESULT_SCENE.instantiate()
	get_root().add_child(result)
	await process_frame
	var stats := {
		"accuracy": 100.0,
		"score": 1000000,
		"judgments": {"Perfect": 1, "Fast": 0, "Slow": 0, "Too Slow": 0},
		"average_offset_ms": 49.9,
		"mean_absolute_error_ms": 49.9,
		"early_inputs": 3,
	}
	result.show_result(stats, true, "S")
	_expect(not result.timing_panel.visible, "timing feedback stays hidden below 50 ms")
	_expect(not result.calibration_button.is_visible_in_tree(), "calibration action stays hidden with timing feedback")
	_expect(result.retry_button.text == "Retry", "completed result keeps the retry label")
	_expect(result.stage_select_button.text == "Back", "completed result keeps the back label")
	result.show_result(stats, false, "F")
	_expect(result.retry_button.text == "재시도", "failed result localizes the retry label")
	_expect(result.stage_select_button.text == "돌아가기", "failed result localizes the back label")
	stats["average_offset_ms"] = 50.0
	result.show_result(stats, true, "S")
	_expect(result.timing_panel.visible, "timing feedback appears at positive 50 ms")
	_expect(result.calibration_button.is_visible_in_tree(), "calibration action appears with timing feedback")
	_expect(result.timing_report.text.contains("입력 오프셋을 보정해보세요."), "timing feedback recommends offset calibration")
	result.calibration_button.pressed.emit()
	_expect(result.timing_calibration.visible, "calibration action opens the timing calibration overlay")
	result.timing_calibration.close()
	stats["average_offset_ms"] = -50.0
	result.show_result(stats, true, "S")
	_expect(result.timing_panel.visible, "timing feedback appears at negative 50 ms")
	_expect(result.timing_report.text.contains("-50.0 ms"), "timing feedback preserves offset direction")
	_expect(not result.timing_report.text.contains("입력 경향"), "timing tendency is omitted")
	_expect(not result.timing_report.text.contains("이른 추가 입력"), "early input count is omitted")
	result.queue_free()


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	push_error("Assertion failed: %s" % message)
	_failures += 1
