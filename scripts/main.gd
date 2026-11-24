extends Node3D
## Game flow (states, scoring, crashes, pickups, effects), the same rules as
## racing-3d's main.js. Everything is built in code; main.tscn is just this node.

const MAX_LIVES := 3
const WEB_TILT_JS := """
(function () {
  if (window._hbTiltInit) return;
  window._hbTiltInit = true;
  window._hbTilt = 0; window._hbHasTilt = false; window._hbWantTilt = false;
  // iOS reports gravity with the opposite sign to Android.
  var ios = typeof DeviceMotionEvent !== 'undefined' && typeof DeviceMotionEvent.requestPermission === 'function';
  var sign = ios ? 1 : -1;
  window.addEventListener('devicemotion', function (e) {
    var g = e.accelerationIncludingGravity;
    if (!g || g.x == null || g.y == null) return;
    window._hbHasTilt = true;
    var deg = (screen.orientation && typeof screen.orientation.angle === 'number') ? screen.orientation.angle : (Number(window.orientation) || 0);
    var a = deg * Math.PI / 180;
    var sx = g.x * Math.cos(a) - g.y * Math.sin(a);
    window._hbTilt = Math.max(-1, Math.min(1, sign * sx / (9.81 * 0.42)));
  });
  // iOS only grants motion access from a user gesture.
  var ask = function () {
    if (!window._hbWantTilt || !ios) return;
    window._hbWantTilt = false;
    try { DeviceMotionEvent.requestPermission().catch(function () {}); } catch (err) {}
  };
  window.addEventListener('touchend', ask, true);
  window.addEventListener('pointerup', ask, true);
})();
"""

var world: World
var traffic: Traffic
var pickups: Pickups
var effects: Effects
var player: PlayerCar
var cam: CameraRig
var ui: UI
var sound: Sound

var state := "menu"          # menu | garage | playing | crashing | paused | gameover | settings
var settings_return := "menu"
var score := 0.0
var run_coins := 0
var crashes := 0
var combo := 0
var combo_timer := 0.0
var near_misses := 0
var drift_pts := 0.0
var over_timer := 0.0
var garage_index := 0
var save_dirty := false

var _smoke: Array[CPUParticles3D] = []
var _flames: Array[Node3D] = []
var _scrape: CPUParticles3D
var _tilt := 0.0
var _perf_frames := 0
var _perf_time := 0.0
var _render_scale := 1.0
var _warmup := 10            # frames left of showing every effect once (shader warm-up)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = World.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	effects = Effects.new()
	effects.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(effects)
	traffic = Traffic.new()
	traffic.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(traffic)
	pickups = Pickups.new()
	pickups.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(pickups)
	player = PlayerCar.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	cam = CameraRig.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	cam.current = true
	_scrape = effects.make_scrape_sparks()
	effects.add_child(_scrape)
	sound = Sound.new()
	add_child(sound)
	ui = UI.new()
	add_child(ui)
	ui.action.connect(_on_action)

	player.crashed_into.connect(_on_crash)
	traffic.near_miss.connect(_on_near_miss)
	pickups.coin_collected.connect(_on_coin)
	pickups.nitro_collected.connect(_on_nitro)
	Save.settings_changed.connect(_on_settings_changed)

	if OS.has_feature("web"):
		JavaScriptBridge.eval(WEB_TILT_JS, true)

	traffic.prewarm()
	_build_player_car(Save.selected)
	_apply_graphics()
	_to_menu()
	# Build the whole view before the first frame.
	world.update(player.s, 300.0, 100)


# ---------- Player car ----------

func _build_player_car(id: String) -> void:
	player.setup(Cars.spec(id))
	for p in _smoke:
		p.queue_free()
	for f in _flames:
		f.queue_free()
	_smoke.clear()
	_flames.clear()
	for w in player.wheels_rear:
		var sm := effects.make_smoke()
		sm.position = w.position + Vector3(0, -player.wheel_radius * 0.6, 0)
		player.add_child(sm)
		_smoke.append(sm)
	for e in player.exhausts:
		var f := effects.make_flame()
		f.position = e
		player.add_child(f)
		_flames.append(f)


# ---------- States ----------

func _set_state(s: String) -> void:
	state = s
	var screen_for := {"menu": "menu", "garage": "garage", "playing": "hud", "crashing": "hud",
		"paused": "pause", "gameover": "gameover", "settings": "settings"}
	ui.show_screen(screen_for[s])
	if s == "menu":
		ui.menu(Save.best, Save.coins, Save.get_s("steering"))
	var frozen := s == "paused" or (s == "settings" and settings_return == "paused")
	get_tree().paused = frozen
	if s != "playing":
		ui.touch.release_all()
		for a in ["steer_left", "steer_right", "nitro", "drift"]:
			Input.action_release(a)
	ui.touch.tilt_mode = Save.get_s("steering") == "tilt"


func _flush_save() -> void:
	if save_dirty:
		Save.save_progress()
		save_dirty = false


func _showroom_car(at_s: float) -> void:
	player.freeze = true
	player.control = false
	player.reset_run()
	player.place(at_s, 0.0)
	player.model.visible = true
	for f in _flames:
		effects.set_flame(f, false)
	for sm in _smoke:
		sm.emitting = false
	_scrape.emitting = false


func _to_menu() -> void:
	_flush_save()
	traffic.reset(PlayerCar.START_S)
	pickups.reset(PlayerCar.START_S)
	effects.clear()
	if Save.selected != player.spec.id:
		_build_player_car(Save.selected)
	_showroom_car(PlayerCar.START_S)
	cam.set_orbit(PI * 0.8)
	_set_state("menu")


func _start_race() -> void:
	get_tree().paused = false
	if Save.selected != player.spec.id:
		_build_player_car(Save.selected)
	player.reset_run()
	player.freeze = false
	player.place(PlayerCar.START_S, 2.0, 0.0)
	player.control = true
	traffic.reset(player.s)
	pickups.reset(player.s)
	effects.clear()
	score = 0.0
	run_coins = 0
	crashes = 0
	combo = 0
	combo_timer = 0.0
	near_misses = 0
	drift_pts = 0.0
	over_timer = 0.0
	world.update(player.s, 40.0, 100)
	cam.reset()
	_set_state("playing")
	ui.popup("GO!", UI.NITRO_C)


func _pause() -> void:
	if state != "playing":
		return
	_flush_save()
	_set_state("paused")


func _resume() -> void:
	if state == "paused":
		_set_state("playing")


func _game_over() -> void:
	var s := int(score)
	var is_best := s > Save.best
	if is_best:
		Save.best = s
	save_dirty = true
	_flush_save()
	ui.gameover(s, Save.best, is_best, run_coins, near_misses, player.s - PlayerCar.START_S)
	player.control = false
	player.freeze = true
	for f in _flames:
		effects.set_flame(f, false)
	for sm in _smoke:
		sm.emitting = false
	_scrape.emitting = false
	player.model.visible = true
	cam.set_orbit(PI * 0.8)
	_set_state("gameover")


func _open_garage() -> void:
	garage_index = Cars.index_of(Save.selected)
	if state == "gameover":
		traffic.reset(player.s)
		pickups.reset(player.s)
		_showroom_car(player.s)
	_refresh_garage()
	_set_state("garage")


func _refresh_garage() -> void:
	var spec: Dictionary = Cars.PLAYER[garage_index]
	if player.spec.id != spec.id:
		_build_player_car(spec.id)
		_showroom_car(player.s)
	ui.garage(spec, garage_index, Cars.PLAYER.size())


func _garage_action() -> void:
	var spec: Dictionary = Cars.PLAYER[garage_index]
	if not spec.id in Save.owned:
		if Save.coins < spec.price:
			return
		Save.coins -= spec.price
		Save.owned.append(spec.id)
		sound.play("coin", 0.8)
	Save.selected = spec.id
	save_dirty = true
	_flush_save()
	_refresh_garage()


func _cycle_view() -> void:
	var i := Save.VIEWS.find(Save.get_s("view"))
	Save.set_s("view", Save.VIEWS[(i + 1) % Save.VIEWS.size()])
	Save.save_settings()
	ui.refresh_settings()
	if state == "playing":
		ui.popup("CAMERA: " + Save.VIEW_NAMES[Save.get_s("view")], Color.WHITE)


func _on_action(a: String) -> void:
	match a:
		"play", "restart":
			_start_race()
		"garage":
			_open_garage()
		"settings":
			if state == "menu" or state == "paused":
				settings_return = state
				ui.refresh_settings()
				_set_state("settings")
		"settings_done":
			Save.save_settings()
			_set_state(settings_return)
			if settings_return == "menu":
				ui.menu(Save.best, Save.coins, Save.get_s("steering"))
		"settings_reset":
			Save.reset_settings()
			ui.refresh_settings()
			_apply_graphics()
		"pause":
			_pause()
		"resume":
			_resume()
		"quit":
			get_tree().paused = false
			_to_menu()
		"camera":
			if state == "playing" or state == "paused":
				_cycle_view()
		"view_changed":
			Save.save_settings()
		"gfx_changed":
			Save.save_settings()
			_apply_graphics()
		"car_prev":
			garage_index = (garage_index + Cars.PLAYER.size() - 1) % Cars.PLAYER.size()
			_refresh_garage()
		"car_next":
			garage_index = (garage_index + 1) % Cars.PLAYER.size()
			_refresh_garage()
		"car_action":
			_garage_action()
		"garage_back":
			if player.spec.id != Save.selected:
				_build_player_car(Save.selected)
				_showroom_car(player.s)
			_set_state("menu")
		"steer_buttons", "steer_tilt":
			var mode := "tilt" if a == "steer_tilt" else "buttons"
			Save.set_s("steering", mode)
			Save.save_settings()
			if mode == "tilt" and OS.has_feature("web"):
				JavaScriptBridge.eval("window._hbWantTilt = true;", true)
			ui.menu(Save.best, Save.coins, mode)


func _on_settings_changed() -> void:
	ui.refresh_settings()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == "playing":
			_pause()
		elif state == "paused":
			_resume()
		elif state == "settings":
			_on_action("settings_done")
	elif event.is_action_pressed("camera"):
		_on_action("camera")
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ENTER:
		if state == "menu" or state == "gameover":
			_start_race()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pause()
		_flush_save()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_save()


# ---------- Graphics ----------

func _apply_graphics() -> void:
	var high: bool = Save.get_s("gfx") == "high"
	world.set_quality(high)
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if high else Viewport.MSAA_DISABLED
	_render_scale = 1.0 if high else 0.8
	vp.scaling_3d_scale = _render_scale
	world.update(player.s, 40.0, 100)


# ---------- Gameplay events ----------

func _on_crash(body: Node, at: Vector3) -> void:
	var car := body as Traffic.TrafficCar
	if car == null or car.hit:
		return
	var side := signf(car.x - player.x)
	if side == 0.0:
		side = 1.0
	car.knock(player.linear_velocity, side)
	effects.burst(at, Color(1, 0.65, 0.2), 18, 9.0, 0.3)
	if state != "playing" or player.invuln > 0.0:
		return
	crashes += 1
	player.on_crash()
	sound.play("crash", randf_range(0.9, 1.1))
	cam.kick(0.9)
	combo = 0
	ui.flash()
	Input.vibrate_handheld(160)
	if crashes >= MAX_LIVES:
		state = "crashing"
		over_timer = 1.6
		player.control = false
		ui.popup("WRECKED!", Color(1, 0.35, 0.3))
	else:
		ui.popup("CRASH!  %d LEFT" % (MAX_LIVES - crashes), Color(1, 0.45, 0.35))


func _on_near_miss(_car: Traffic.TrafficCar) -> void:
	combo_timer = 3.0
	combo = mini(combo + 1, 5)
	var pts := 150 * combo
	score += pts
	near_misses += 1
	sound.play("whoosh", 1.0 + combo * 0.08, -4.0)
	player.nitro = minf(1.0, player.nitro + 0.05)
	ui.popup("NEAR MISS x%d  +%d" % [combo, pts] if combo > 1 else "NEAR MISS  +%d" % pts, Color(0.5, 1.0, 0.6))


func _on_coin(at: Vector3) -> void:
	sound.play("coin", randf_range(0.97, 1.05), -3.0)
	run_coins += 1
	score += 10
	Save.coins += 1
	save_dirty = true
	effects.burst(at, Color(1, 0.82, 0.3), 6, 3.0, 0.5)


func _on_nitro(at: Vector3) -> void:
	sound.play("nitro", 1.2)
	player.nitro = minf(1.0, player.nitro + 0.4)
	score += 50
	ui.popup("NITRO  +40%", UI.NITRO_C)
	effects.burst(at, Color(0.36, 0.78, 1.0), 12, 5.0, 0.6)


# ---------- Loop ----------

func _read_steer() -> float:
	var st := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	if st == 0.0 and Save.get_s("steering") == "tilt":
		var raw := 0.0
		if OS.has_feature("web"):
			raw = float(JavaScriptBridge.eval("window._hbTilt || 0", true))
		else:
			raw = clampf(Input.get_accelerometer().x / (9.81 * 0.42), -1.0, 1.0)
		if Save.get_s("tilt_invert"):
			raw = -raw
		_tilt += (raw - _tilt) * 0.35
		st = 0.0 if absf(_tilt) < 0.06 else (_tilt - signf(_tilt) * 0.06) / 0.94
	return clampf(st, -1.0, 1.0)


func _physics_process(dt: float) -> void:
	if get_tree().paused:
		return
	var racing := state == "playing"
	if racing:
		player.steer_in = _read_steer()
		player.nitro_in = Input.is_action_pressed("nitro")
		player.drift_in = Input.is_action_pressed("drift")
	else:
		player.steer_in = 0.0
		player.nitro_in = false
		player.drift_in = false
	if state == "playing" or state == "crashing":
		traffic.step(dt, player, racing)
		pickups.step(dt, player.s, player.x, racing)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if _warmup > 0:
		# Draw every effect once behind the start menu so its shaders are
		# compiled before the race.
		_warmup -= 1
		var on := _warmup > 0
		for f in _flames:
			effects.set_flame(f, on)
		for sm in _smoke:
			sm.emitting = on
		_scrape.emitting = on
		_scrape.global_position = player.global_position + Vector3(0, 0.5, 0)
		if _warmup == 8:
			effects.burst(player.global_position + Vector3(0, 1, 0), Color.ORANGE)
			effects.skid("warm", player.global_position, Vector3.UP, true)
			effects.skid("warm", player.global_position + Vector3(0, 0, 1), Vector3.UP, true)
		if _warmup == 0:
			effects.clear()
	match state:
		"playing", "crashing":
			_update_race(dt)
		"menu", "garage", "gameover":
			_update_showroom(dt)
		"paused":
			cam.follow_car(dt, player, true)
		"settings":
			if settings_return == "menu":
				_update_showroom(dt)
			else:
				cam.follow_car(dt, player, true)
	var frozen := get_tree().paused
	sound.engine(player if (state == "playing" or state == "crashing") else null, frozen)
	world.follow(cam.global_position, Track.height(player.s))
	traffic.animate(0.0 if frozen else dt)
	pickups.render_items()
	_adapt_resolution(delta)


func _update_race(dt: float) -> void:
	world.update(player.s, 40.0, 1, true)
	if state == "playing":
		score += maxf(player.speed, 0.0) * dt * 0.5 * (1.5 if player.boosting else 1.0)
		if player.drifting:
			drift_pts += player.speed * dt * 0.8
		elif drift_pts > 0.0:
			var pts := roundi(drift_pts)
			if pts >= 25:
				score += pts
				ui.popup("DRIFT  +%d" % pts, Color(1, 0.6, 0.25))
			drift_pts = 0.0
	if combo_timer > 0.0:
		combo_timer -= dt
		if combo_timer <= 0.0:
			combo = 0

	# Car effects
	for f in _flames:
		effects.set_flame(f, player.boosting)
	for i in player.wheels_rear.size():
		var w := player.wheels_rear[i]
		var sliding := player.wheel_sliding(w)
		_smoke[i].emitting = sliding
		effects.skid("w%d" % i, w.global_position - player.global_basis.y * player.wheel_radius, player.global_basis.y, sliding)
	_scrape.emitting = player.scraping
	if player.scraping:
		var side := signf(player.x)
		_scrape.global_position = player.global_position + Track.right(player.s) * side * player.half_width + Vector3(0, 0.5, 0) + Track.forward_flat(player.s) * randf_range(-1.5, 1.5)
	# Blink while invulnerable after a crash.
	player.model.visible = player.invuln <= 0.0 or int(player.invuln * 12.0) % 2 == 0

	cam.follow_car(dt, player)
	ui.hud(int(score), run_coins, roundi(maxf(player.speed, 0.0) * 3.6), player.nitro, player.boosting, MAX_LIVES - crashes)

	if state == "crashing":
		over_timer -= dt
		if over_timer <= 0.0:
			_game_over()


func _update_showroom(dt: float) -> void:
	world.update(player.s, 300.0, 2)
	match state:
		"garage":
			cam.orbit(dt, player, 7.2, 1.7, 0.35)
		"gameover":
			cam.orbit(dt, player, 8.5, 2.6, 0.15, 2.6)
		_:
			cam.orbit(dt, player, 7.5, 2.2, 0.22, 2.6)


## Lowers the 3D resolution if the device can't hold about 50 fps.
func _adapt_resolution(dt: float) -> void:
	if state != "playing":
		_perf_frames = 0
		_perf_time = 0.0
		return
	_perf_frames += 1
	_perf_time += dt
	if _perf_time > 2.5:
		var fps := _perf_frames / _perf_time
		if fps < 48.0 and _render_scale > 0.6:
			_render_scale = maxf(0.6, _render_scale - 0.1)
			get_viewport().scaling_3d_scale = _render_scale
		_perf_frames = 0
		_perf_time = 0.0
