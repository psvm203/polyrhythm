extends SceneTree

const City = preload("res://level/ui/city_restoration.gd")
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var city = City.new()
	root.add_child(city)
	city.size = Vector2(1600, 900)
	city.set_process(false)
	expect(City.FRAMES.size() == 10, "ten separate reconstruction images")
	for index in range(10):
		city.update_reconstruction(index * 10, 100)
		city._process(5.0)
		expect(city._city.texture == City.FRAMES[index], "step %d selects its own image" % index)
		expect(city._city.position.x > city.size.x * 0.5, "building image leaves the central polygon lane clear")
	expect(City.frame_index(-1.0) == 0 and City.frame_index(1.1) == 9, "frame selection clamps endpoints")
	expect(city.get_child_count() == 1, "only the building image remains")
	city.update_reconstruction(100, 100)
	city._process(5.0)
	expect(city._city.texture == City.FRAMES[9], "city ends fully restored")
	city.update_reconstruction(0, 100)
	city._process(5.0)
	expect(city._city.texture == City.FRAMES[0], "reset returns to ruins")
	city.update_reconstruction(10, 100)
	city._process(0.5)
	expect(city._fade > 0.0 and city._fade < 1.0, "step changes fade instead of cutting")
	expect(city._city.material.get_shader_parameter("previous_frame") == City.FRAMES[0], "fade retains the previous image")
	city._process(0.25)
	expect(is_equal_approx(city._fade, 0.5), "fade reaches its midpoint after 0.75 seconds")
	city.set_process(true)
	paused = true
	await process_frame
	expect(is_equal_approx(city._fade, 0.5), "pause freezes the active fade")
	paused = false
	city.set_process(false)
	city._process(0.75)
	expect(is_equal_approx(city._fade, 1.0), "fade finishes after 1.5 seconds")
	city.size = Vector2(900, 1200)
	city._process(0.0)
	expect(Rect2(Vector2.ZERO, city.size).encloses(city._city.get_rect()) and city._city.position.x > city.size.x * 0.5, "outer placement stays inside the viewport after resize")
	city.free()
	print("City restoration tests: %d failures" % failures)
	quit(1 if failures else 0)

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
