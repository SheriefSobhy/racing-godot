extends SceneTree
## Frame-time test: drives with a simple autopilot for 25 s (traffic on) and
## reports average FPS and the slowest frames. Run windowed:
## godot --path . [--rendering-method gl_compatibility] -s res://tools/perf.gd -- gfx=low|high

var main: Node3D
var t := 0.0
var frame := 0
var times: Array[float] = []
var gfx := "high"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("gfx="):
			gfx = a.substr(4)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		root.get_node("Save").call("set_s", "gfx", gfx)
		main.call("_apply_graphics")
		main.call("_on_action", "play")
	if frame < 3:
		return false
	t += delta
	var p: PlayerCar = main.get("player")
	var target := 2.0
	var lat_v := p.linear_velocity.dot(Track.right(p.s))
	var steer := clampf((target - p.x) * 0.35 - lat_v * 0.25, -1.0, 1.0)
	Input.action_press("steer_right", maxf(steer, 0.0)) if steer > 0 else Input.action_release("steer_right")
	Input.action_press("steer_left", maxf(-steer, 0.0)) if steer < 0 else Input.action_release("steer_left")
	main.set("crashes", 0)
	if t > 3.0:
		times.append(delta * 1000.0)
	if t > 25.0:
		times.sort()
		var sum := 0.0
		for x in times:
			sum += x
		var n := times.size()
		print("PERF gfx=%s renderer=%s frames=%d avg_fps=%.0f median_ms=%.1f p95_ms=%.1f p99_ms=%.1f max_ms=%.1f" % [
			gfx, RenderingServer.get_current_rendering_method(), n, n / (sum / 1000.0), times[n / 2], times[int(n * 0.95)], times[int(n * 0.99)], times[n - 1]])
		return true
	return false
