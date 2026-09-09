extends CanvasLayer

const ProgressStoreScript = preload("res://level/progress_store.gd")
const SettingsStoreScript = preload("res://main/settings_store.gd")

signal retry_requested
signal stage_select_requested

@onready var summary_label: Label = %Summary
@onready var rating_label: Label = %Rating
@onready var timing_panel: PanelContainer = %TimingPanel
@onready var timing_report: Label = %TimingReport
@onready var calibration_button: Button = %CalibrationButton
@onready var timing_calibration: CanvasLayer = %TimingCalibrationOverlay
@onready var retry_button: Button = %RetryButton
@onready var stage_select_button: Button = %StageSelectButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	retry_button.pressed.connect(retry_requested.emit)
	stage_select_button.pressed.connect(stage_select_requested.emit)
	calibration_button.pressed.connect(timing_calibration.open)
	timing_calibration.offset_selected.connect(_apply_calibrated_offset)
	timing_calibration.closed.connect(calibration_button.grab_focus)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or timing_calibration.visible or not event.is_action_pressed("ui_cancel"):
		return
	stage_select_requested.emit()
	get_viewport().set_input_as_handled()


func show_result(stats: Dictionary, completed: bool) -> void:
	retry_button.text = "Retry" if completed else "재시도"
	stage_select_button.text = "Back" if completed else "돌아가기"
	var rating := ProgressStoreScript.star_rating(stats["accuracy"], completed)
	rating_label.text = "★".repeat(rating["stars"]) if completed else ""
	rating_label.add_theme_color_override("font_color", _rating_color(rating["tier"]))
	var counts: Dictionary = stats["judgments"]
	summary_label.text = (
		"점수  %07d        정확도  %.1f%%\n\nPERFECT  %d    FAST  %d    SLOW  %d    MISS  %d"
		% [stats["score"], stats["accuracy"], counts["Perfect"], counts["Fast"], counts["Slow"], counts["Too Slow"]]
	)
	var average_offset := float(stats.get("average_offset_ms", 0.0))
	timing_panel.visible = absf(average_offset) >= 50.0
	timing_report.text = "평균 편차  %+.1f ms\n입력 오프셋을 보정해보세요." % average_offset
	show()
	retry_button.grab_focus()


func _apply_calibrated_offset(value: float) -> void:
	SettingsStoreScript.save_setting("timing_offset_ms", value)


func _rating_color(tier: String) -> Color:
	match tier:
		"diamond": return Color("76f7ff")
		"gold": return Color("ffd84d")
		"silver": return Color("c7d1dc")
		"bronze": return Color("c98252")
	return Color.TRANSPARENT
