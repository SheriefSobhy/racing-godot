extends Node
## Settings and progress, autoloaded as "Save".
## Settings go to user://settings.cfg and progress (best score, coins, cars)
## to user://save.cfg. On the web build these live in the browser's storage.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://save.cfg"

const VIEWS := ["chase", "far", "hood", "bumper"]
const VIEW_NAMES := {"chase": "CHASE", "far": "FAR CHASE", "hood": "HOOD", "bumper": "BUMPER"}

## Slider ranges: [min, max, step].
const RANGES := {
	"fov": [60.0, 90.0, 1.0],
	"dist": [4.0, 12.0, 0.5],
	"height": [1.5, 5.0, 0.1],
	"follow": [1.0, 12.0, 0.5],
	"sfx": [0.0, 100.0, 1.0],
	"music": [0.0, 100.0, 1.0],
}

const DEFAULTS := {
	"view": "chase", "fov": 62.0, "dist": 7.0, "height": 2.7, "follow": 6.0,
	"shake": true, "speed_fx": true, "gfx": "high", "show_fps": false,
	"sfx": 80.0, "music": 60.0, "muted": false, "steering": "buttons", "tilt_invert": false,
}

## Current settings (keys as in DEFAULTS).
var settings := {}

# Progress
var best := 0
var coins := 0
var owned: Array = ["vortex"]
var selected := "vortex"


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, &"Master")
	settings = DEFAULTS.duplicate()
	# Phones start on Low graphics; computers on High.
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		settings.gfx = "low"
	_load()
	apply_audio()


func get_s(key: String) -> Variant:
	return settings.get(key, DEFAULTS[key])


func set_s(key: String, value: Variant) -> void:
	if RANGES.has(key):
		var r: Array = RANGES[key]
		value = clampf(float(value), r[0], r[1])
	settings[key] = value
	apply_audio()
	settings_changed.emit()


func reset_settings() -> void:
	var gfx: String = settings.gfx
	var steering: String = settings.steering
	settings = DEFAULTS.duplicate()
	settings.gfx = gfx
	settings.steering = steering
	apply_audio()
	save_settings()
	settings_changed.emit()


func apply_audio() -> void:
	var muted: bool = get_s("muted")
	AudioServer.set_bus_mute(0, muted)
	_set_bus_volume("SFX", float(get_s("sfx")) / 100.0)
	_set_bus_volume("Music", float(get_s("music")) / 100.0)


func _set_bus_volume(bus_name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i == -1:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in settings:
		cfg.set_value("settings", k, settings[k])
	cfg.save(SETTINGS_PATH)


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "best", best)
	cfg.set_value("progress", "coins", coins)
	cfg.set_value("progress", "owned", owned)
	cfg.set_value("progress", "selected", selected)
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in DEFAULTS:
			var v: Variant = cfg.get_value("settings", k, DEFAULTS[k])
			if typeof(v) == typeof(DEFAULTS[k]) or (typeof(v) == TYPE_INT and typeof(DEFAULTS[k]) == TYPE_FLOAT):
				settings[k] = v
		for k in RANGES:
			var r: Array = RANGES[k]
			settings[k] = clampf(float(settings[k]), r[0], r[1])
		if not settings.view in VIEWS:
			settings.view = "chase"
		if settings.gfx != "low" and settings.gfx != "high":
			settings.gfx = "high"
	var save := ConfigFile.new()
	if save.load(SAVE_PATH) == OK:
		best = int(save.get_value("progress", "best", 0))
		coins = int(save.get_value("progress", "coins", 0))
		var o: Variant = save.get_value("progress", "owned", ["vortex"])
		if o is Array and not (o as Array).is_empty():
			owned = o
		selected = str(save.get_value("progress", "selected", "vortex"))
	if not "vortex" in owned:
		owned.append("vortex")
	if not selected in owned:
		selected = "vortex"
