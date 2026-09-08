extends Control

const EditorTheme = preload("res://editor/ui/editor_theme.gd")
const LevelDataScript = preload("res://level/data/level_data.gd")
const ProgressStoreScript = preload("res://level/progress_store.gd")
const AudioStreamLoaderScript = preload("res://level/audio/audio_stream_loader.gd")
const PolygonPaletteButtonScript = preload("res://editor/components/polygon_palette_button.gd")
const SequenceHistoryScript = preload("res://editor/model/sequence_history.gd")
const LevelDocumentScript = preload("res://editor/model/level_document.gd")
const LEVEL_SCENE := "res://level/level.tscn"
const MAIN_SCENE := "res://main/main_screen.tscn"
const PREVIEW_PATH := "user://custom_level_preview.yaml"
const AUTOSAVE_PATH := "user://custom_level_autosave.yaml"
const EVENT_TYPES := [
	{"label": "보스 가드", "name": "boss_guard"},
	{"label": "사무라이 분할", "name": "samurai_split", "when_sides": 6, "replace_with": [3, 3]},
	{"label": "시간 정지", "name": "time_stop", "duration_sec": 0.65},
]

var _boss_health := 0
var _events: Array[Dictionary] = []
var _history: SequenceHistory = SequenceHistoryScript.new()
var _applying_history := false
var _updating_seek := false
var _preview_music_path := ""
var _document: RefCounted = LevelDocumentScript.new()
var _pending_action := ""
var _saving_pending_action := false


func _ready() -> void:
	theme = EditorTheme.create()
	EditorTheme.primary(%PlayButton)
	%BackButton.pressed.connect(_request_exit)
	%UndoButton.pressed.connect(_undo)
	%RedoButton.pressed.connect(_redo)
	%CloseEditorButton.pressed.connect(_exit_editor)
	%ReturnEditorButton.pressed.connect(_hide_exit_dialog)
	%SaveChangesButton.pressed.connect(_save_pending_changes)
	%DiscardChangesButton.pressed.connect(_discard_pending_changes)
	%CancelChangesButton.pressed.connect(_cancel_pending_action)
	%GuideButton.pressed.connect(%GuideOverlay.open)
	%ImportButton.pressed.connect(_request_import)
	%ExportButton.pressed.connect(%ExportDialog.popup_centered_ratio.bind(0.75))
	%MusicButton.pressed.connect(%MusicDialog.popup_centered_ratio.bind(0.75))
	%ValidateButton.pressed.connect(_validate)
	%PlayButton.pressed.connect(_test_play)
	%ImportDialog.file_selected.connect(_import_yaml)
	%ExportDialog.file_selected.connect(_on_export_selected)
	%ExportDialog.canceled.connect(_cancel_pending_action)
	%MusicDialog.file_selected.connect(func(path: String) -> void: %MusicPath.text = path)
	%MusicPreviewButton.pressed.connect(_toggle_music_preview)
	%MusicStopButton.pressed.connect(_stop_music_preview)
	%MusicSeek.value_changed.connect(_seek_music_preview)
	%MusicPreview.finished.connect(_stop_music_preview)
	%AutosaveTimer.timeout.connect(_save_autosave)
	%EventType.add_item("이벤트 선택")
	for event_type in EVENT_TYPES:
		%EventType.add_item(event_type["label"])
	%EventApply.pressed.connect(_apply_selected_event)
	%EventRemove.pressed.connect(_remove_selected_events)
	for sides in range(3, 9):
		var button := PolygonPaletteButtonScript.new()
		button.setup(sides)
		button.pressed.connect(%Timeline.add_tile.bind(sides))
		%ShapePalette.add_child(button)
	%Timeline.sequence_changed.connect(_on_sequence_changed)
	%Timeline.selection_changed.connect(func(_index: int) -> void: _sync_event_controls())
	%Timeline.tile_inserted.connect(_shift_events_for_insert)
	%Timeline.tile_removed.connect(_shift_events_for_remove)
	%Timeline.tile_moved.connect(_move_event_target)
	%Bpm.value_changed.connect(_on_document_setting_changed)
	%MusicOffset.value_changed.connect(_on_document_setting_changed)
	%MusicPath.text_changed.connect(_on_document_setting_changed)
	%TimelineMode.pressed.connect(_set_map_mode.bind(false))
	%MapMode.pressed.connect(_set_map_mode.bind(true))
	%Timeline.set_sequence([3, 4, 5, 4, 6, 3])
	%MusicPath.text = "res://level/data/BR-Freaky_feat_LezaLee_-fulllength-loopable-121_9BPM-Dm.WAV"
	var returning_from_preview := ProgressStoreScript.custom_level_path == PREVIEW_PATH
	if not ProgressStoreScript.custom_level_path.is_empty() and FileAccess.file_exists(ProgressStoreScript.custom_level_path):
		_import_yaml(ProgressStoreScript.custom_level_path, not returning_from_preview)
		if returning_from_preview:
			_document.restore_saved_state(ProgressStoreScript.editor_working_file_path, ProgressStoreScript.editor_saved_signature)
	elif FileAccess.file_exists(AUTOSAVE_PATH):
		_populate(LevelDataScript.from_yaml(AUTOSAVE_PATH).dictionary())
		%Status.text = "자동 저장된 레벨을 복구했습니다."
		_document.restore_saved_state(ProgressStoreScript.editor_working_file_path, ProgressStoreScript.editor_saved_signature)
	else:
		_mark_saved_state("")
	%Timeline.grab_focus()
	_set_map_mode(false)
	_reset_history()
	_update_summary()
	_sync_event_controls()


func _set_map_mode(enabled: bool) -> void:
	%TimelineMode.set_pressed_no_signal(not enabled)
	%MapMode.set_pressed_no_signal(enabled)
	%Timeline.set_map_mode(enabled)
	%TimelineScroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if enabled else ScrollContainer.SCROLL_MODE_DISABLED


func _collect() -> Dictionary:
	var data: Dictionary = _document.snapshot()
	data.merge({
		"sides_sequence": %Timeline.sequence.duplicate(),
		"repeat_count": 1,
		"bpm": %Bpm.value,
		"music_path": %MusicPath.text.strip_edges(),
		"music_start_offset_sec": %MusicOffset.value,
		"boss_health": _boss_health,
		"events": _events.duplicate(true),
	}, true)
	_document.replace(data)
	return _document.snapshot()


func _populate(data: Dictionary) -> void:
	_document.replace(data)
	data = _document.snapshot()
	%Timeline.set_sequence(data.get("sides_sequence", []))
	%Bpm.value = float(data.get("bpm", 120.0))
	%MusicPath.text = str(data.get("music_path", ""))
	%MusicOffset.value = float(data.get("music_start_offset_sec", 0.0))
	_boss_health = int(data.get("boss_health", 0))
	_events.clear()
	for event in data.get("events", []):
		if event is Dictionary:
			_events.append((event as Dictionary).duplicate(true))
	%Timeline.set_events(_events)


func _update_summary() -> void:
	%SequenceSummary.text = "시퀀스   /   도형 %d개" % %Timeline.sequence.size()


func _on_sequence_changed(sequence: Array[int]) -> void:
	_update_summary()
	_record_document_change()
	_queue_autosave()


func _reset_history() -> void:
	_history.reset(_history_state())
	_update_history_buttons()


func _undo() -> void:
	if not _history.can_undo():
		return
	_apply_history(_history.undo())


func _redo() -> void:
	if not _history.can_redo():
		return
	_apply_history(_history.redo())


func _record_document_change() -> void:
	if _applying_history:
		return
	_history.record(_history_state())
	_update_history_buttons()


func _on_document_setting_changed(_value: Variant) -> void:
	_record_document_change()
	_queue_autosave()


func _update_history_buttons() -> void:
	%UndoButton.disabled = not _history.can_undo()
	%RedoButton.disabled = not _history.can_redo()


func _apply_history(state: Variant) -> void:
	if not state is Dictionary:
		return
	_applying_history = true
	_populate(state)
	_applying_history = false
	_update_summary()
	_sync_event_controls()
	_update_history_buttons()
	_queue_autosave()


func _history_state() -> Dictionary:
	return _collect()


func _apply_selected_event() -> void:
	var tile: int = %Timeline.selected_index
	var type_index: int = %EventType.selected - 1
	if tile < 0 or type_index < 0:
		return
	var template: Dictionary = EVENT_TYPES[type_index]
	if template.get("when_sides", 0) > 0 and %Timeline.sequence[tile] != template["when_sides"]:
		%Status.text = "⚠ 이 이벤트는 %d각형에만 적용할 수 있습니다." % template["when_sides"]
		return
	var event := _find_or_create_event(template)
	var targets: Array = event.get("at", [])
	if not targets.has(tile + 1):
		targets.append(tile + 1)
		targets.sort()
		event["at"] = targets
	_commit_event_change()


func _remove_selected_events() -> void:
	var polygon_number: int = %Timeline.selected_index + 1
	if polygon_number <= 0:
		return
	for index in range(_events.size() - 1, -1, -1):
		var targets: Array = _events[index].get("at", [])
		targets.erase(polygon_number)
		_events[index]["at"] = targets
		if targets.is_empty():
			_events.remove_at(index)
	_commit_event_change()


func _find_or_create_event(template: Dictionary) -> Dictionary:
	for event in _events:
		if event.get("name", "") == template["name"]:
			return event
	var created := template.duplicate(true)
	created.erase("label")
	created["at"] = []
	_events.append(created)
	return created


func _commit_event_change() -> void:
	%Timeline.set_events(_events)
	_record_document_change()
	_sync_event_controls()
	_queue_autosave()


func _sync_event_controls() -> void:
	var polygon_number: int = %Timeline.selected_index + 1
	%SelectionInfo.text = "%02d번 도형 · %d각형" % [polygon_number, %Timeline.sequence[polygon_number - 1]] if polygon_number > 0 else "타임라인에서 도형을 선택하세요"
	%EventApply.disabled = polygon_number <= 0
	%EventRemove.disabled = polygon_number <= 0 or not _has_event_at(polygon_number)
	if %EventType.item_count == 0:
		return
	%EventType.select(0)
	for type_index in EVENT_TYPES.size():
		for event in _events:
			if event.get("name", "") == EVENT_TYPES[type_index]["name"] and event.get("at", []).has(polygon_number):
				%EventType.select(type_index + 1)
				return


func _has_event_at(polygon_number: int) -> bool:
	for event in _events:
		if event.get("at", []).has(polygon_number):
			return true
	return false


func _shift_events_for_insert(index: int) -> void:
	_remap_event_targets(func(value: int) -> int: return value + 1 if value >= index + 1 else value)


func _shift_events_for_remove(index: int) -> void:
	var removed := index + 1
	_remap_event_targets(func(value: int) -> int: return -1 if value == removed else value - 1 if value > removed else value)


func _move_event_target(from_index: int, to_index: int) -> void:
	var source := from_index + 1
	var target := to_index + 1
	_remap_event_targets(func(value: int) -> int:
		if value == source:
			return target
		if source < target and value > source and value <= target:
			return value - 1
		if target < source and value >= target and value < source:
			return value + 1
		return value
	)


func _remap_event_targets(mapper: Callable) -> void:
	for event in _events:
		var remapped: Array[int] = []
		for value in event.get("at", []):
			var mapped := int(mapper.call(int(value)))
			if mapped > 0:
				remapped.append(mapped)
		remapped.sort()
		event["at"] = remapped
	%Timeline.set_events(_events)


func _queue_autosave() -> void:
	if is_inside_tree():
		%AutosaveTimer.start()


func _save_autosave() -> void:
	_write_yaml(AUTOSAVE_PATH)


func _request_exit() -> void:
	if _has_unsaved_changes():
		_show_unsaved_dialog("exit")
	else:
		_show_exit_dialog()


func _request_import() -> void:
	if _has_unsaved_changes():
		_show_unsaved_dialog("import")
	else:
		%ImportDialog.popup_centered_ratio(0.75)


func _show_unsaved_dialog(action: String) -> void:
	_pending_action = action
	%UnsavedDialog.show()
	if is_inside_tree():
		%CancelChangesButton.grab_focus()


func _save_pending_changes() -> void:
	if not _document.current_file_path.is_empty():
		if _export_yaml(_document.current_file_path):
			_continue_pending_action()
		return
	_saving_pending_action = true
	%UnsavedDialog.hide()
	%ExportDialog.popup_centered_ratio(0.75)


func _discard_pending_changes() -> void:
	%UnsavedDialog.hide()
	_continue_pending_action()


func _cancel_pending_action() -> void:
	_saving_pending_action = false
	_pending_action = ""
	%UnsavedDialog.hide()
	if is_inside_tree():
		%Timeline.grab_focus()


func _continue_pending_action() -> void:
	var action := _pending_action
	_pending_action = ""
	_saving_pending_action = false
	%UnsavedDialog.hide()
	match action:
		"exit": _exit_editor()
		"import": %ImportDialog.popup_centered_ratio(0.75)


func _has_unsaved_changes() -> bool:
	_collect()
	return _document.has_unsaved_changes()


func _mark_saved_state(path: String) -> void:
	_collect()
	_document.mark_saved(path)
	ProgressStoreScript.editor_working_file_path = path
	ProgressStoreScript.editor_saved_signature = _document.saved_signature


func _exit_editor() -> void:
	_clear_autosave()
	get_tree().change_scene_to_file(MAIN_SCENE)


func _clear_autosave() -> void:
	%AutosaveTimer.stop()
	var autosave_path := ProjectSettings.globalize_path(AUTOSAVE_PATH)
	if FileAccess.file_exists(AUTOSAVE_PATH):
		DirAccess.remove_absolute(autosave_path)


func _show_exit_dialog() -> void:
	%ExitDialog.show()
	if is_inside_tree():
		%ReturnEditorButton.grab_focus()


func _hide_exit_dialog() -> void:
	%ExitDialog.hide()
	if is_inside_tree():
		%Timeline.grab_focus()


func _toggle_music_preview() -> void:
	if %MusicPreview.playing:
		%MusicPreview.stream_paused = not %MusicPreview.stream_paused
		%MusicPreviewButton.text = "▶" if %MusicPreview.stream_paused else "⏸"
		return
	var path: String = %MusicPath.text.strip_edges()
	if path != _preview_music_path or %MusicPreview.stream == null:
		%MusicPreview.stream = _load_preview_music(path)
		_preview_music_path = path
	if %MusicPreview.stream == null:
		%Status.text = "⚠ 음악 파일을 재생할 수 없습니다."
		return
	%MusicSeek.max_value = %MusicPreview.stream.get_length()
	%MusicPreview.play(clampf(%MusicOffset.value, 0.0, %MusicSeek.max_value))
	%MusicPreviewButton.text = "⏸"


func _stop_music_preview() -> void:
	%MusicPreview.stop()
	%MusicPreviewButton.text = "▶"
	_updating_seek = true
	%MusicSeek.value = 0.0
	%MusicTime.text = "0:00 / %s" % _format_time(%MusicSeek.max_value)
	_updating_seek = false


func _seek_music_preview(value: float) -> void:
	if not _updating_seek and %MusicPreview.playing:
		%MusicPreview.seek(value)


func _load_preview_music(path: String) -> AudioStream:
	return AudioStreamLoaderScript.load_stream(path)


func _process(_delta: float) -> void:
	if not %MusicPreview.playing or %MusicPreview.stream_paused:
		return
	_updating_seek = true
	%MusicSeek.value = %MusicPreview.get_playback_position()
	%MusicTime.text = "%s / %s" % [_format_time(%MusicSeek.value), _format_time(%MusicSeek.max_value)]
	_updating_seek = false


func _format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), floori(seconds) % 60]


func _validate() -> bool:
	var diagnostics := LevelDataScript.validate_detailed(_collect(), _document.current_file_path)
	var messages := PackedStringArray()
	for diagnostic in diagnostics:
		messages.append("[%s] %s" % [diagnostic["field"], diagnostic["message"]])
	%Status.text = "✓ 플레이 가능한 레벨입니다." if diagnostics.is_empty() else "⚠ " + "\n⚠ ".join(messages)
	%Status.modulate = Color("55efb0") if diagnostics.is_empty() else Color("ff6680")
	return diagnostics.is_empty()


func _import_yaml(path: String, mark_as_saved: bool = true) -> void:
	var data := LevelDataScript.from_yaml(path).dictionary()
	_populate(data)
	_reset_history()
	_sync_event_controls()
	%Status.text = "불러옴: %s" % path
	_validate()
	if mark_as_saved:
		_mark_saved_state(path)


func _export_yaml(path: String) -> bool:
	if not _validate():
		return false
	if path.get_extension().to_lower() != "yaml":
		path += ".yaml"
	if not _write_yaml(path):
		return false
	_mark_saved_state(path)
	%Status.text = "저장됨: %s" % path
	return true


func _on_export_selected(path: String) -> void:
	if not _export_yaml(path):
		if _saving_pending_action:
			%UnsavedDialog.show()
		return
	if _saving_pending_action:
		_continue_pending_action()


func _write_yaml(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		%Status.text = "⚠ 파일을 저장할 수 없습니다: %s" % path
		return false
	file.store_string(LevelDataScript.to_yaml(_collect()))
	return true


func _test_play() -> void:
	if not _validate():
		return
	_write_yaml(PREVIEW_PATH)
	ProgressStoreScript.editor_working_file_path = _document.current_file_path
	ProgressStoreScript.editor_saved_signature = _document.saved_signature
	ProgressStoreScript.custom_level_path = PREVIEW_PATH
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if %GuideOverlay.visible:
			%GuideOverlay.close()
		elif %UnsavedDialog.visible:
			_cancel_pending_action()
		elif %ExitDialog.visible:
			_hide_exit_dialog()
		else:
			_request_exit()
		get_viewport().set_input_as_handled()
		return
	if %UnsavedDialog.visible or %ExitDialog.visible or %GuideOverlay.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.ctrl_pressed or event.meta_pressed) and event.keycode in [KEY_Z, KEY_Y]:
		_redo() if event.keycode == KEY_Y or event.shift_pressed else _undo()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_music_preview()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.unicode >= 51 and event.unicode <= 56:
		%Timeline.add_tile(event.unicode - 48)
		get_viewport().set_input_as_handled()
