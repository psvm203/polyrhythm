extends Control

const FRAMES: Array[Texture2D] = [
	preload("res://level/assets/stage_9/ruins.jpg"),
	preload("res://level/assets/stage_9/rebuild_02.png"),
	preload("res://level/assets/stage_9/rebuild_03.png"),
	preload("res://level/assets/stage_9/rebuild_04.png"),
	preload("res://level/assets/stage_9/rebuild_05.png"),
	preload("res://level/assets/stage_9/rebuild_06.png"),
	preload("res://level/assets/stage_9/rebuild_07.png"),
	preload("res://level/assets/stage_9/rebuild_08.png"),
	preload("res://level/assets/stage_9/rebuild_09.png"),
	preload("res://level/assets/stage_9/restored.png"),
]
const FADE_DURATION := 1.5
const INK_SHADER = preload("res://level/ui/city_restoration.gdshader")

var target_progress := 0.0
var progress := 0.0
var _city: TextureRect
var _frame := 0
var _fade := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_city = TextureRect.new()
	_city.texture = FRAMES[0]
	_city.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_city.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ink := ShaderMaterial.new()
	ink.shader = INK_SHADER
	ink.set_shader_parameter("previous_frame", FRAMES[0])
	_city.material = ink
	add_child(_city)


func update_reconstruction(resolved: int, total: int) -> void:
	target_progress = clampf(float(resolved) / maxi(total, 1), 0.0, 1.0)


static func frame_index(value: float) -> int:
	return clampi(int(floorf(clampf(value, 0.0, 1.0) * FRAMES.size())), 0, FRAMES.size() - 1)


func _process(delta: float) -> void:
	progress = move_toward(progress, target_progress, delta * 0.22)
	# Keep the central polygon lane clear, with the city inset from the right edge.
	var side := minf(size.y * 0.76, size.x * 0.42)
	_city.size = Vector2.ONE * side
	_city.position = Vector2(size.x * 0.96 - side, size.y * 0.56 - side * 0.5)
	var next_frame := frame_index(progress)
	# Finish the active fade before accepting another step, avoiding a visual jump.
	if next_frame != _frame and _fade >= 1.0:
		_city.material.set_shader_parameter("previous_frame", FRAMES[_frame])
		_frame = next_frame
		_city.texture = FRAMES[_frame]
		_fade = 0.0
	_fade = minf(_fade + delta / FADE_DURATION, 1.0)
	_city.material.set_shader_parameter("fade", _fade)
