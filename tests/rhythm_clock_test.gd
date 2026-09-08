extends SceneTree

const RhythmClockScript = preload("res://level/timing/rhythm_clock.gd")

var _assertions := 0
var _failures := 0


func _init() -> void:
	var now := [1_000_000]
	var clock = RhythmClockScript.new()
	clock.time_source_usec = func() -> int: return now[0]
	_expect(clock.elapsed_usec() == 0, "idle clock is zero")
	clock.start()
	_expect(clock.running, "start marks clock running")
	_expect(clock.start_usec == 1_000_000, "start captures monotonic timestamp")
	now[0] += 250_000
	_expect(clock.elapsed_usec() == 250_000, "clock measures elapsed microseconds")
	_expect(is_equal_approx(clock.elapsed_sec(), 0.25), "clock exposes elapsed seconds")
	clock.pause()
	_expect(clock.is_paused(), "pause freezes clock")
	now[0] += 2_000_000
	_expect(clock.elapsed_usec() == 250_000, "paused duration does not advance")
	clock.resume()
	_expect(not clock.is_paused(), "resume unfreezes clock")
	_expect(clock.paused_total_usec == 2_000_000, "clock accounts for paused duration")
	now[0] += 125_000
	_expect(clock.elapsed_usec() == 375_000, "clock continues after resume")
	clock.pause()
	clock.pause()
	now[0] += 100_000
	clock.resume()
	clock.resume()
	_expect(clock.elapsed_usec() == 375_000, "duplicate pause and resume are idempotent")
	clock.reset()
	_expect(not clock.running, "reset stops clock")
	_expect(clock.elapsed_usec() == 0, "reset clears elapsed time")
	clock.start(0)
	clock.pause(0)
	_expect(clock.is_paused(), "zero timestamp is a valid pause")
	_expect(clock.elapsed_usec(1000000) == 0, "zero timestamp pause freezes time")
	clock.resume(1000000)
	_expect(clock.elapsed_usec(1250000) == 250000, "zero timestamp pause is excluded")
	_finish()


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error(message)


func _finish() -> void:
	if _failures > 0:
		push_error("Rhythm clock tests failed: %d of %d" % [_failures, _assertions])
		quit(1)
		return
	print("Rhythm clock tests passed: %d assertions" % _assertions)
	quit()
