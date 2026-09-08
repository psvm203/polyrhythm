extends SceneTree

const LevelDataScript = preload("res://level/data/level_data.gd")
const LevelEventSystemScript = preload("res://level/events/level_event_system.gd")

var _failures := 0


func _init() -> void:
	var data := LevelDataScript.new()
	var stage_two := LevelDataScript.from_yaml("res://level/data/level_2.yaml")
	var stage_three := LevelDataScript.from_yaml("res://level/data/level_3.yaml")
	var stage_one := LevelDataScript.from_yaml("res://level/data/level_1.yaml")
	var stage_four := LevelDataScript.from_yaml("res://level/data/level_4.yaml")
	var stage_two_events := LevelEventSystemScript.new()
	var stage_three_events := LevelEventSystemScript.new()
	var stage_four_events := LevelEventSystemScript.new()
	stage_two_events.setup(stage_two.events)
	stage_three_events.setup(stage_three.events)
	stage_four_events.setup(stage_four.events)
	stage_two_events.transform_sequence(stage_two.expanded_sequence())
	var transformed_stage_three := stage_three_events.transform_sequence(stage_three.expanded_sequence())
	stage_four_events.transform_sequence(stage_four.expanded_sequence())
	var expanded: Array[int] = data.expand_layout({"sides_sequence": [3, 5, 4], "repeat_count": 3})
	_expect(expanded == [3, 5, 4, 3, 5, 4, 3, 5, 4], "pattern repeats in order")
	_expect(expanded.size() == 9, "expanded note count is correct")
	_expect(expanded[0] == 3 and expanded[-1] == 4, "source order is preserved")
	_expect(data.expand_layout({}) == [3], "missing sequence falls back to a safe triangle")
	_expect(data.expand_layout({"sides_sequence": [0, 2, 13, "bad"]}) == [3], "invalid polygon sides cannot reach geometry generation")
	_expect(data.expand_layout({"sides_sequence": [4], "repeat_count": 100000}).size() == 1000, "corrupt repeat counts are bounded")
	_expect(not data.validate({"sides_sequence": "bad", "bpm": {}, "repeat_count": null}).is_empty(), "validation handles malformed value types")
	var diagnostics := data.validate_detailed({"sides_sequence": [], "bpm": 0, "repeat_count": 0, "music_path": ""}, "user://broken.yaml")
	_expect(diagnostics[0]["code"] == "missing_sequence" and diagnostics[0]["field"] == "sides_sequence", "validation exposes stable diagnostic codes and fields")
	_expect(diagnostics[0]["source_path"] == "user://broken.yaml", "validation diagnostics retain their source path")
	_expect(stage_two.expanded_sequence().size() == 160, "stage two has a full arrangement")
	_expect(stage_three.expanded_sequence().size() == 192, "stage three has a full arrangement")
	_expect(stage_three.bpm > stage_two.bpm, "final stage increases tempo")
	_expect(stage_three.boss_name == "SHAPE SAMURAI", "final stage introduces the samurai boss")
	_expect(transformed_stage_three.size() == 224, "samurai splits 32 hexagons into triangle pairs")
	_expect(stage_three_events.occurs("samurai_split", 5) and transformed_stage_three[5] == 3 and transformed_stage_three[6] == 3, "samurai event replaces its target hexagon")
	var conditional_split := LevelEventSystemScript.new()
	conditional_split.setup([{"name": "split", "at": [1], "when_sides": 6, "replace_with": [3, 3]}])
	_expect(conditional_split.transform_sequence([5]) == [5], "shape condition prevents an invalid event replacement")
	_expect(stage_four.boss_name == "CHRONOMANCER", "stage four introduces the time mage")
	_expect(stage_four_events.occurs("time_stop", 15) and not stage_four_events.occurs("time_stop", 14), "time stop event targets its YAML polygon")
	_expect(is_equal_approx(float(stage_four_events.value("time_stop", "duration_sec", 0.0)), 0.65), "event exposes its YAML parameters")
	var indexed_events := LevelEventSystemScript.new()
	indexed_events.setup([{"name": "cue", "at": [2, 5]}])
	indexed_events.transform_sequence([3, 4, 5, 6, 7])
	_expect(indexed_events.occurs("cue", 1) and indexed_events.occurs("cue", 4), "events can target explicit one-based indices")
	_expect(ResourceLoader.exists(stage_one.music_path, "AudioStream"), "YAML music path resolves to audio")
	_expect(stage_one.expanded_sequence().size() == 28, "stage one arrangement ends before its 55-second cutoff")
	var serialized := LevelDataScript.to_yaml(stage_two.dictionary())
	_expect("boss_health: 260" in serialized, "YAML export includes boss settings")
	_expect("tutorial_lines:" in serialized, "YAML export includes story")
	var decimal_bpm := stage_two.dictionary()
	decimal_bpm["bpm"] = 121.75
	_expect("bpm: 121.75" in LevelDataScript.to_yaml(decimal_bpm), "YAML export preserves decimal BPM")
	data.music_start_offset_sec = 12.5
	_expect(data.clamped_music_start_offset(60.0) == 12.5, "music offset is preserved")
	data.music_start_offset_sec = 80.0
	_expect(data.clamped_music_start_offset(60.0) == 60.0, "music offset is capped to stream length")
	data.music_start_offset_sec = -2.0
	_expect(data.clamped_music_start_offset(60.0) == 0.0, "negative music offset is clamped")
	_expect(stage_two_events.occurs("boss_guard", 7), "eighth boss note activates guard event")
	_expect(not stage_two_events.occurs("boss_guard", 6), "ordinary boss note has no guard event")
	_expect(stage_two.boss_damage("Perfect", true) == 8, "Perfect breaks guard")
	_expect(stage_two.boss_damage("Slow", true) == 0, "imprecise hit is blocked")
	_expect(stage_two.boss_damage("Perfect", false) == 2, "Perfect damages boss")
	if _failures == 0:
		print("Level data tests passed: 33 assertions")
		quit(0)
	else:
		push_error("Level data tests failed: %d assertion(s)" % _failures)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
