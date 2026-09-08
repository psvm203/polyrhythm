extends SceneTree

# Run both from the workspace and with --main-pack to verify packaged data.
const Catalog = preload("res://level/data/stage_catalog.gd")
const Data = preload("res://level/data/level_data.gd")
const AudioLoader = preload("res://level/audio/audio_stream_loader.gd")
const Events = preload("res://level/events/level_event_system.gd")

var failures := 0


func _init() -> void:
	for stage in Catalog.stage_numbers():
		var path := Catalog.data_path(stage)
		if not FileAccess.file_exists(path):
			failures += 1
			push_error("Stage %d YAML is missing from the package: %s" % [stage, path])
			continue
		var data = Data.from_yaml(path)
		var events = Events.new()
		events.setup(data.events)
		var sequence: Array[int] = events.transform_sequence(data.expanded_sequence())
		if sequence.size() <= 1 or sequence.size() != data.note_times_sec.size():
			failures += 1
			push_error("Stage %d loaded fallback or incomplete map data" % stage)
		var audio := AudioLoader.load_stream(data.music_path)
		if audio == null or audio.get_length() + 0.01 < data.duration_sec:
			failures += 1
			push_error("Stage %d packaged audio is missing or too short" % stage)
		print("Packaged stage %d: %d notes, %.2f seconds" % [stage, sequence.size(), data.duration_sec])
	print("Exported stage data tests: %d stages, %d failures" % [Catalog.stage_numbers().size(), failures])
	quit(1 if failures else 0)
