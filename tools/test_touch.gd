extends SceneTree
## Simulates finger touches on the on-screen buttons (as on a phone) and
## checks that steering, nitro and drift respond, including two fingers at
## once. Also saves a screenshot of the HUD with the buttons.
## godot --path . -s res://tools/test_touch.gd -- out=C:/tmp/touch.png

var main: Node
var f := 0
var out := ""
var x0 := 0.0
var fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	(load("res://scripts/ui.gd") as GDScript).set("force_touch", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _centre(action: String) -> Vector2:
	var b: TouchScreenButton = main.get("ui").touch._buttons[action]
	return b.position + TouchControls.SIZES[action] / 2.0


func _check(what: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _process(_d: float) -> bool:
	f += 1
	var p: PlayerCar = main.get("player")
	match f:
		5:
			root.get_node("Save").call("set_s", "steering", "buttons")
			root.get_node("Save").call("set_s", "show_fps", true)
			main.call("_on_action", "play")
		60:
			var t: Control = main.get("ui").touch
			_check("touch controls visible", t.is_visible_in_tree())
			var r: Rect2 = t._button_rect("steer_left")
			_check("left button on screen (%s)" % r, root.get_visible_rect().encloses(r))
			x0 = p.x
			_touch(0, _centre("steer_left"), true)
		62:
			_check("steer_left pressed by finger 0", Input.is_action_pressed("steer_left"))
			_touch(1, _centre("nitro"), true)
		64:
			_check("nitro pressed by finger 1 while finger 0 steers", Input.is_action_pressed("nitro") and Input.is_action_pressed("steer_left"))
			if out != "":
				root.get_viewport().get_texture().get_image().save_png(out)
		150:
			_check("car moved left (x %.2f -> %.2f)" % [x0, p.x], p.x < x0 - 1.0)
			_check("nitro used (bar %.2f)" % p.nitro, p.nitro < 0.3)
			_touch(0, _centre("steer_left"), false)
			_touch(1, _centre("nitro"), false)
		152:
			_check("released", not Input.is_action_pressed("steer_left") and not Input.is_action_pressed("nitro"))
			_touch(2, _centre("steer_right"), true)
			_touch(3, _centre("drift"), true)
		154:
			_check("steer_right + drift together", Input.is_action_pressed("steer_right") and Input.is_action_pressed("drift"))
			_touch(2, _centre("steer_right"), false)
			_touch(3, _centre("drift"), false)
			print("RESULT ", "OK" if fails == 0 else "%d FAILED" % fails)
			return true
	return false
