extends SceneTree
## Headless driving test: an autopilot drives the real VehicleBody3D car.
## godot --headless --path . --fixed-fps 60 -s res://tools/test_drive.gd [-- car=umbra traffic=1 secs=60]
## Prints lane keeping, lane-change time, drift angle and crash counts.

var main: Node
var t := 0.0
var args := {}
var phase := ""
var target_x := 2.0
var max_err := 0.0
var lc_start := -1.0
var lc_time := -1.0
var drift_max_slide := 0.0
var drift_gain := 0.0
var drift_nitro0 := 0.0
var speeds: Array[float] = []
var min_y_up := 1.0
var resets := 0
var last_log := 0.0
var secs := 60.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	secs = float(args.get("secs", "60"))
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	if args.has("car"):
		root.get_node("Save").set("selected", args.car)
	main.call_deferred("_start_race")


func _press(action: String, v: float) -> void:
	if v > 0.0:
		Input.action_press(action, v)
	else:
		Input.action_release(action)


func _physics_process(delta: float) -> bool:
	if main == null or main.state != "playing" and main.state != "crashing":
		t += delta
		return t > secs + 5.0
	t += delta
	var p: PlayerCar = main.player
	if args.get("traffic", "0") == "0":
		main.traffic.reset(p.s + 1000.0)

	# Phases: 0-12 s hold lane 2, 12-20 s change to lane -6, 20-26 s drift, then traffic weaving.
	var drift := false
	if t < 12.0:
		phase = "lane"
		target_x = 2.0
	elif t < 20.0:
		phase = "change"
		if lc_start < 0.0:
			lc_start = t
			target_x = -6.0
	elif t < 26.0:
		phase = "drift"
		drift = true
		if drift_nitro0 == 0.0:
			drift_nitro0 = p.nitro
	else:
		phase = "free"
		target_x = _avoid(p)

	if phase == "change" and lc_time < 0.0 and absf(p.x - target_x) < 0.6:
		lc_time = t - lc_start
	if phase == "lane" and t > 4.0:
		max_err = maxf(max_err, absf(p.x - target_x))
	if phase == "drift":
		drift_max_slide = maxf(drift_max_slide, absf(p.slide))

	# Steering controller on road-space error and lateral speed.
	var lat_v := p.linear_velocity.dot(Track.right(p.s))
	var steer := clampf((target_x - p.x) * 0.35 - lat_v * 0.25, -1.0, 1.0)
	if drift:
		# Swing between lanes while drifting.
		target_x = -2.0 if fmod(t, 4.0) < 2.0 else 2.0
		steer = clampf((target_x - p.x) * 0.4 - lat_v * 0.15, -1.0, 1.0)
	_press("steer_right", maxf(steer, 0.0))
	_press("steer_left", maxf(-steer, 0.0))
	_press("drift", 1.0 if drift else 0.0)
	_press("nitro", 1.0 if (phase == "free" and p.nitro > 0.5) else 0.0)
	speeds.append(p.speed)
	min_y_up = minf(min_y_up, p.global_basis.y.y)

	if t - last_log >= float(args.get("log", "2")):
		last_log = t
		print("t=%5.1f %-6s s=%7.0f x=%6.2f v=%5.1f km/h=%3d slide=%5.2f head=%5.2f nitro=%.2f crashes=%d up=%.2f" % [
			t, phase, p.s, p.x, p.speed, roundi(p.speed * 3.6), p.slide, p.heading_err, p.nitro, main.crashes, p.global_basis.y.y])
	if t >= secs or main.state == "crashing":
		_report(p)
		return true
	return false


## Picks a lane free of traffic ahead.
func _avoid(p: PlayerCar) -> float:
	var best := target_x
	var best_gap := -1.0
	for lx in Track.LANES:
		var gap := 999.0
		for c in main.traffic.cars:
			if c.hit:
				continue
			var ds: float = c.s - p.s
			if ds > -3.0 and ds < 120.0 and absf(c.x - lx) < 2.6:
				gap = minf(gap, ds)
		var score := gap - absf(lx - p.x) * 3.0
		if score > best_gap:
			best_gap = score
			best = lx
	return best


func _report(p: PlayerCar) -> void:
	var avg := 0.0
	for v in speeds:
		avg += v
	avg /= maxf(1.0, speeds.size())
	print("RESULT car=%s lane_err_max=%.2f lane_change_s=%.2f drift_slide_max=%.2f drift_nitro_gain=%.2f avg_kmh=%d min_up=%.2f crashes=%d dist=%.0f state=%s" % [
		p.spec.id, max_err, lc_time, drift_max_slide, p.nitro - drift_nitro0 if phase != "drift" else 0.0,
		roundi(avg * 3.6), min_y_up, main.crashes, p.s - PlayerCar.START_S, main.state])
