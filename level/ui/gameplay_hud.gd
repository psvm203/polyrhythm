extends CanvasLayer

@onready var score_label: Label = %Score
@onready var combo_label: Label = %Combo
@onready var gauge_bar: ProgressBar = %Gauge
@onready var progress_ring: Control = %ProgressRing
@onready var progress_label: Label = %ProgressPercent

var _gauge_fill := StyleBoxFlat.new()


func _ready() -> void:
	_gauge_fill.corner_radius_top_left = 8
	_gauge_fill.corner_radius_top_right = 8
	_gauge_fill.corner_radius_bottom_left = 8
	_gauge_fill.corner_radius_bottom_right = 8
	_gauge_fill.anti_aliasing = true
	gauge_bar.add_theme_stylebox_override("fill", _gauge_fill)
	_update_gauge_color(gauge_bar.value)


func update_stats(stats: Dictionary) -> void:
	score_label.text = "%06d" % stats["score"]
	combo_label.text = "%d Combo" % stats["combo"] if stats["combo"] > 1 else ""
	gauge_bar.value = stats["gauge"]
	_update_gauge_color(gauge_bar.value)
	var total := int(stats.get("total", 0))
	var resolved := int(stats.get("resolved", 0))
	var progress := clampf(float(resolved) / total, 0.0, 1.0) if total > 0 else 0.0
	progress_ring.set("progress", progress)
	progress_label.text = "%d%%" % floori(progress * 100.0)


func _update_gauge_color(value: float) -> void:
	_gauge_fill.bg_color = gauge_color(value, gauge_bar.max_value)
	gauge_bar.queue_redraw()


static func gauge_color(value: float, maximum: float = 100.0) -> Color:
	var ratio := clampf(value / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	if is_equal_approx(ratio, 1.0):
		return Color("76f7ff")
	if ratio >= 0.67:
		return Color("55efb0")
	if ratio >= 0.34:
		return Color("ffd166")
	return Color("ff5f78")


func setup_boss(name: String, health: int, samurai: bool = false, time_mage: bool = false) -> void:
	%BossPanel.visible = health > 0 and not time_mage
	%BossName.text = name
	%BossHealth.max_value = health
	%BossHealth.value = health
	%BossHint.text = "곧 시간 정지" if time_mage else "육각형 분할에 대비" if samurai else "곧 가드 비트"


func update_boss(health: int, guard_active: bool) -> void:
	%BossHealth.value = health
	%BossHint.text = "가드 비트: PERFECT 판정만 유효" if guard_active else "곧 가드 비트"


func update_samurai_attack(health: int, attack_active: bool) -> void:
	%BossHealth.value = health
	%BossHint.text = "육각형 분할: 삼각형에 맞춰 두 번 입력" if attack_active else "바뀌는 경로에 집중"


func update_time_spell(health: int, spell_active: bool, frozen: bool) -> void:
	%BossHealth.value = health
	%BossHint.text = "시간 정지" if frozen else "시간 해제: PERFECT 입력" if spell_active else "시간 흐름 복구"
