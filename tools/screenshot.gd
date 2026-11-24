extends SceneTree
## Captures screenshots of the game for checking visuals.
## godot --path . -s res://tools/screenshot.gd -- out=C:/tmp/shots [gfx=high|low]
## Saves menu, race, drift + nitro, hood view, garage, settings, pause and game over.

var main: Node3D
var save: Node
var out := "user://shots"
var frame := 0
var step := 0
var t := 0.0
var steps := []
var _pending := ""
var _gfx := "high"


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	out = args.get("out", out)
	DirAccess.make_dir_recursive_absolute(out)
	save = root.get_node("Save")
	_gfx = args.get("gfx", "high")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	# [seconds to wait, action, screenshot name]
	steps = [
		[2.0, "", "menu"],
		[0.1, "play", ""],
		[5.0, "", "race"],
		[0.1, "drift_on", ""],
		[1.6, "", "drift"],
		[0.1, "nitro_on", ""],
		[1.0, "", "nitro"],
		[0.1, "all_off", ""],
		[0.1, "hood", ""],
		[1.0, "", "hood"],
		[0.1, "bumper", ""],
		[1.0, "", "bumper"],
		[0.1, "far", ""],
		[1.5, "", "far"],
		[0.1, "pause", ""],
		[0.5, "", "pause"],
		[0.1, "settings", ""],
		[0.5, "", "settings"],
		[0.1, "quit", ""],
		[0.1, "garage", ""],
		[1.5, "", "garage"],
		[0.1, "car_next", ""],
		[0.1, "car_next", ""],
		[1.5, "", "garage2"],
		[0.1, "garage_back", ""],
		[0.1, "play", ""],
		[2.0, "crash3", ""],
		[3.0, "", "gameover"],
	]


func _process(delta: float) -> bool:
	frame += 1
	if frame < 5:
		return false
	if frame == 5:
		# Autoloads are ready only now.
		save.call("set_s", "gfx", _gfx)
		save.call("set_s", "show_fps", true)
		save.call("set_s", "view", "chase")
		main.call("_apply_graphics")
	if _pending != "":
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out.path_join(_pending + ".png"))
		print("saved ", _pending)
		_pending = ""
	t += delta
	if step >= steps.size():
		return true
	var st: Array = steps[step]
	if t < st[0]:
		return false
	t = 0.0
	step += 1
	var act: String = st[1]
	match act:
		"":
			pass
		"drift_on":
			Input.action_press("drift")
			Input.action_press("steer_right", 0.6)
		"nitro_on":
			Input.action_release("drift")
			Input.action_release("steer_right")
			Input.action_press("nitro")
		"all_off":
			for a in ["drift", "nitro", "steer_left", "steer_right"]:
				Input.action_release(a)
		"hood", "bumper", "far":
			save.call("set_s", "view", act)
		"crash3":
			main.set("crashes", 2)
			main.set("crashes", 3)
			main.set("state", "crashing")
			main.set("over_timer", 0.5)
		_:
			main.call("_on_action", act)
	_pending = st[2]
	return false
