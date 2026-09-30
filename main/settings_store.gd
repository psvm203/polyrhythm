class_name SettingsStore
extends RefCounted

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"
const DEFAULTS := {
	"fullscreen": false,
	"master_volume": 100.0,
	"music_volume": 100.0,
	"sfx_volume": 100.0,
	"master_enabled": true,
	"music_enabled": true,
	"sfx_enabled": true,
	"skip_seen_dialogue": false,
	"timing_offset_ms": 0.0,
	"controller_vibration_enabled": true,
	"controller_vibration_strength": 70.0,
	"resolution_width": 1280,
	"resolution_height": 720,
}
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(960, 540),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const AUDIO_BUSES := {"master": &"Master", "music": &"MenuMusic", "sfx": &"SFX"}
const MIN_TIMING_OFFSET_MS := -150.0
const MAX_TIMING_OFFSET_MS := 150.0


static func load_settings() -> Dictionary:
	var config := ConfigFile.new()
	var values := DEFAULTS.duplicate()
	if config.load(SAVE_PATH) == OK:
		for key in DEFAULTS:
			values[key] = config.get_value(SECTION, key, DEFAULTS[key])
	return normalized(values)


static func save_setting(key: String, value: Variant) -> void:
	save_settings({key: value})


static func save_settings(changes: Dictionary) -> void:
	var values := load_settings()
	for key in changes:
		if not DEFAULTS.has(key):
			push_error("Unknown setting: %s" % key)
			continue
		values[key] = changes[key]
	values = normalized(values)
	var config := ConfigFile.new()
	for setting_key in values:
		config.set_value(SECTION, setting_key, values[setting_key])
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_error("Failed to save settings: %s" % error_string(error))
	apply(values)


static func apply(settings: Dictionary) -> void:
	var values := normalized(settings)
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	if not values["fullscreen"]:
		DisplayServer.window_set_size(Vector2i(values["resolution_width"], values["resolution_height"]))
	for prefix in AUDIO_BUSES:
		_set_bus_volume(AUDIO_BUSES[prefix], values["%s_volume" % prefix], values["%s_enabled" % prefix])


static func normalized(settings: Dictionary) -> Dictionary:
	var values := {
		"fullscreen": bool(settings.get("fullscreen", DEFAULTS["fullscreen"])),
		"skip_seen_dialogue": bool(settings.get("skip_seen_dialogue", DEFAULTS["skip_seen_dialogue"])),
		"timing_offset_ms": clampf(
			float(settings.get("timing_offset_ms", DEFAULTS["timing_offset_ms"])),
			MIN_TIMING_OFFSET_MS,
			MAX_TIMING_OFFSET_MS,
		),
		"controller_vibration_enabled": bool(settings.get("controller_vibration_enabled", DEFAULTS["controller_vibration_enabled"])),
		"controller_vibration_strength": clampf(float(settings.get("controller_vibration_strength", DEFAULTS["controller_vibration_strength"])), 0.0, 100.0),
	}
	for prefix in AUDIO_BUSES:
		values["%s_volume" % prefix] = clampf(float(settings.get("%s_volume" % prefix, 100.0)), 0.0, 100.0)
		values["%s_enabled" % prefix] = bool(settings.get("%s_enabled" % prefix, true))
	var requested := Vector2i(int(settings.get("resolution_width", 1280)), int(settings.get("resolution_height", 720)))
	var default_size := Vector2i(DEFAULTS["resolution_width"], DEFAULTS["resolution_height"])
	var size := requested if requested in RESOLUTIONS else default_size
	values["resolution_width"] = size.x
	values["resolution_height"] = size.y
	return values


static func resolution_index(settings: Dictionary) -> int:
	var size := Vector2i(settings["resolution_width"], settings["resolution_height"])
	return maxi(RESOLUTIONS.find(size), 0)


static func save_resolution(index: int) -> void:
	var size := RESOLUTIONS[clampi(index, 0, RESOLUTIONS.size() - 1)]
	save_settings({"resolution_width": size.x, "resolution_height": size.y})


static func _set_bus_volume(bus_name: StringName, percent: float, enabled: bool) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(maxf(percent / 100.0, 0.0001)))
	AudioServer.set_bus_mute(bus_index, not enabled or percent <= 0.0)
