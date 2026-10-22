extends CanvasLayer

const SettingsStoreScript = preload("res://main/settings_store.gd")

signal resume_requested
signal restart_requested
signal exit_requested
signal timing_offset_changed(offset_sec: float)

@onready var fullscreen_toggle: Button = %FullscreenToggle
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var timing_slider: HSlider = %TimingSlider
@onready var vibration_slider: HSlider = %VibrationSlider
@onready var master_value: Label = %MasterValue
@onready var music_value: Label = %MusicValue
@onready var sfx_value: Label = %SfxValue
@onready var timing_value: Label = %TimingValue
@onready var vibration_value: Label = %VibrationValue
@onready var master_enabled: Button = %MasterEnabled
@onready var music_enabled: Button = %MusicEnabled
@onready var sfx_enabled: Button = %SfxEnabled
@onready var vibration_enabled: Button = %VibrationEnabled
@onready var skip_seen_dialogue: Button = %SkipSeenDialogue
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var calibration_button: Button = %CalibrationButton
@onready var timing_calibration: CanvasLayer = %TimingCalibrationOverlay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var input_manager := _input_manager()
	if input_manager != null:
		input_manager.connect("active_device_changed", _update_controller_prompt.unbind(1))
	hide()
	%ResumeButton.pressed.connect(resume_requested.emit)
	%RestartButton.pressed.connect(restart_requested.emit)
	%ExitButton.pressed.connect(exit_requested.emit)
	calibration_button.pressed.connect(timing_calibration.open)
	timing_calibration.offset_selected.connect(_apply_calibrated_offset)
	timing_calibration.closed.connect(calibration_button.grab_focus)
	fullscreen_toggle.toggled.connect(_set_fullscreen)
	resolution_option.item_selected.connect(SettingsStoreScript.save_resolution)
	master_slider.value_changed.connect(_set_volume.bind("master_volume", master_value))
	music_slider.value_changed.connect(_set_volume.bind("music_volume", music_value))
	sfx_slider.value_changed.connect(_set_volume.bind("sfx_volume", sfx_value))
	vibration_slider.value_changed.connect(_set_vibration_strength)
	vibration_enabled.toggled.connect(_set_vibration_enabled)
	timing_slider.value_changed.connect(_set_timing_offset)
	master_enabled.toggled.connect(_set_enabled.bind("master_enabled", master_enabled))
	music_enabled.toggled.connect(_set_enabled.bind("music_enabled", music_enabled))
	sfx_enabled.toggled.connect(_set_enabled.bind("sfx_enabled", sfx_enabled))
	skip_seen_dialogue.toggled.connect(_set_skip_seen_dialogue)
	_sync_settings()
	_update_controller_prompt()


func open() -> void:
	_sync_settings()
	show()
	%ResumeButton.grab_focus()


func close() -> void:
	hide()


func set_exit_visible(value: bool) -> void:
	%RestartButton.visible = value
	%ExitButton.visible = value


func _unhandled_input(event: InputEvent) -> void:
	var input_manager := _input_manager()
	var pause_input := bool(input_manager.call("is_pause_input", event)) if input_manager != null else false
	if visible and not timing_calibration.visible and (event.is_action_pressed("ui_cancel") or pause_input):
		resume_requested.emit()
		get_viewport().set_input_as_handled()


func _update_controller_prompt() -> void:
	%ResumeButton.text = "계속하기"


func _input_manager() -> Node:
	return get_node_or_null("/root/InputDeviceManager")


func _sync_settings() -> void:
	var settings := SettingsStoreScript.load_settings()
	SettingsStoreScript.apply(settings)
	_setup_resolution(settings)
	fullscreen_toggle.set_pressed_no_signal(settings["fullscreen"])
	_update_fullscreen_text(fullscreen_toggle.button_pressed)
	_sync_slider(master_slider, master_value, settings["master_volume"])
	_sync_slider(music_slider, music_value, settings["music_volume"])
	_sync_slider(sfx_slider, sfx_value, settings["sfx_volume"])
	_sync_slider(vibration_slider, vibration_value, settings["controller_vibration_strength"])
	timing_slider.set_value_no_signal(settings["timing_offset_ms"])
	_update_timing_offset_label(settings["timing_offset_ms"])
	_sync_toggle(master_enabled, settings["master_enabled"])
	_sync_toggle(music_enabled, settings["music_enabled"])
	_sync_toggle(sfx_enabled, settings["sfx_enabled"])
	_sync_toggle(vibration_enabled, settings["controller_vibration_enabled"])
	_sync_skip_seen_dialogue(settings["skip_seen_dialogue"])


func _sync_slider(slider: HSlider, value_label: Label, percent: float) -> void:
	slider.set_value_no_signal(percent)
	value_label.text = "%d%%" % roundi(percent)


func _set_fullscreen(enabled: bool) -> void:
	_update_fullscreen_text(enabled)
	SettingsStoreScript.save_setting("fullscreen", enabled)


func _update_fullscreen_text(enabled: bool) -> void:
	fullscreen_toggle.text = "On" if enabled else "Off"
	resolution_option.disabled = enabled


func _set_volume(value: float, setting_key: String, value_label: Label) -> void:
	value_label.text = "%d%%" % roundi(value)
	SettingsStoreScript.save_setting(setting_key, value)


func _set_timing_offset(value: float) -> void:
	_update_timing_offset_label(value)
	SettingsStoreScript.save_setting("timing_offset_ms", value)
	timing_offset_changed.emit(value / 1000.0)


func _apply_calibrated_offset(value: float) -> void:
	timing_slider.set_value_no_signal(value)
	_set_timing_offset(value)


func _set_vibration_strength(value: float) -> void:
	vibration_value.text = "%d%%" % roundi(value)
	SettingsStoreScript.save_setting("controller_vibration_strength", value)


func _set_vibration_enabled(enabled: bool) -> void:
	_sync_toggle(vibration_enabled, enabled)
	SettingsStoreScript.save_setting("controller_vibration_enabled", enabled)


func _update_timing_offset_label(value: float) -> void:
	timing_value.text = "%+d ms" % roundi(value)


func _set_enabled(enabled: bool, setting_key: String, toggle: Button) -> void:
	_sync_toggle(toggle, enabled)
	SettingsStoreScript.save_setting(setting_key, enabled)


func _sync_toggle(toggle: Button, enabled: bool) -> void:
	toggle.set_pressed_no_signal(enabled)
	toggle.text = "On" if enabled else "Off"


func _set_skip_seen_dialogue(enabled: bool) -> void:
	_sync_skip_seen_dialogue(enabled)
	SettingsStoreScript.save_setting("skip_seen_dialogue", enabled)


func _sync_skip_seen_dialogue(enabled: bool) -> void:
	skip_seen_dialogue.set_pressed_no_signal(enabled)
	skip_seen_dialogue.text = "On" if enabled else "Off"


func _setup_resolution(settings: Dictionary) -> void:
	resolution_option.clear()
	for size in SettingsStoreScript.RESOLUTIONS:
		resolution_option.add_item("%d × %d" % [size.x, size.y])
	resolution_option.select(SettingsStoreScript.resolution_index(settings))
