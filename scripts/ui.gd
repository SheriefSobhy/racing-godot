class_name UI
extends CanvasLayer
## All screens, built in code: HUD, Start menu, Pause, Settings, Game Over
## and Garage. Buttons emit `action(name)`; main.gd does the rest.

signal action(name: String)

const ACCENT := Color(1.0, 0.78, 0.2)
const NITRO_C := Color(0.3, 0.78, 1.0)
const PANEL_BG := Color(0.05, 0.07, 0.12, 0.82)

var theme_ui: Theme
var screens := {}
var touch: TouchControls

# HUD widgets
var _speed: Label
var _speed_unit: Label
var _score: Label
var _coins: Label
var _lives_shown := -1
var _nitro_fill: StyleBoxFlat
var _nitro_bar: ProgressBar
var _popup: Label
var _popup_time := 0.0
var _fps: Label
var _flash: ColorRect
var _cam_btn: Button
var _pause_btn: Button
var _life_dots: Array[Panel] = []

# Menu / game over / garage widgets
var _menu_best: Label
var _menu_coins: Label
var _steer_btns := {}
var _go_title: Label
var _go_score: Label
var _go_best: Label
var _go_stats: Label
var _gar_name: Label
var _gar_coins: Label
var _gar_stats: VBoxContainer
var _gar_action: Button
var _pause_cam: Button

# Settings widgets
var _sliders := {}
var _toggles := {}
var _view_btns := {}
var _gfx_btns := {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme_ui = _make_theme()
	_build_hud()
	_build_menu()
	_build_pause()
	_build_settings()
	_build_gameover()
	_build_garage()
	refresh_settings()


func _process(delta: float) -> void:
	if _popup_time > 0.0:
		_popup_time -= delta
		_popup.modulate.a = clampf(_popup_time / 0.4, 0.0, 1.0)
		_popup.scale = Vector2.ONE * (1.0 + maxf(0.0, _popup_time - 1.0) * 0.4)
		if _popup_time <= 0.0:
			_popup.visible = false
	if _flash.visible:
		_flash.color.a -= delta * 1.8
		if _flash.color.a <= 0.0:
			_flash.visible = false
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


# ---------- Theme and helpers ----------

func _box(c: Color, radius := 14, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(3)
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	t.set_stylebox("normal", "Button", _box(Color(0.14, 0.18, 0.27, 0.95), 14, Color(1, 1, 1, 0.12)))
	t.set_stylebox("hover", "Button", _box(Color(0.2, 0.26, 0.38, 0.95), 14, Color(1, 1, 1, 0.25)))
	t.set_stylebox("pressed", "Button", _box(Color(0.9, 0.62, 0.12, 1.0), 14))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _box(Color(0.12, 0.13, 0.16, 0.8), 14))
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.02))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_font_size("font_size", "Button", 28)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, 22))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.75))
	t.set_constant("outline_size", "Label", 6)
	var grab := _box(ACCENT, 12)
	grab.content_margin_left = 0
	t.set_stylebox("slider", "HSlider", _box(Color(1, 1, 1, 0.18), 6))
	t.set_stylebox("grabber_area", "HSlider", _box(Color(ACCENT, 0.8), 6))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, 6))
	var g := Image.create(30, 30, false, Image.FORMAT_RGBA8)
	g.fill(Color(0, 0, 0, 0))
	for y in 30:
		for x in 30:
			if Vector2(x - 14.5, y - 14.5).length() <= 14.0:
				g.set_pixel(x, y, Color.WHITE)
	var gt := ImageTexture.create_from_image(g)
	t.set_icon("grabber", "HSlider", gt)
	t.set_icon("grabber_highlight", "HSlider", gt)
	t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.45), 8))
	t.set_stylebox("fill", "ProgressBar", _box(NITRO_C, 8))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	return t


## A small round coin icon.
func _coin_icon(px: int) -> TextureRect:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := px / 2.0 - 0.5
	for y in px:
		for x in px:
			var d := Vector2(x - r, y - r).length()
			if d <= r:
				img.set_pixel(x, y, Color(1.0, 0.82, 0.2) if d < r - 3.0 else Color(0.75, 0.5, 0.05))
	var t := TextureRect.new()
	t.texture = ImageTexture.create_from_image(img)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return t


func _screen(name: String) -> Control:
	var c := Control.new()
	c.name = name
	c.theme = theme_ui
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	add_child(c)
	screens[name] = c
	return c


func _label(text: String, fsize := 26, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


func _btn(text: String, act: String, min_w := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 64)
	b.focus_mode = Control.FOCUS_NONE
	if act != "":
		b.pressed.connect(func() -> void: action.emit(act))
	return b


## A panel with a vertical list, for the menu screens. With left=true it
## sits on the left half, leaving the car visible on the right.
func _panel(parent: Control, min_w := 520.0, left := false) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	if left:
		center.anchor_right = 0.55
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_w, 0)
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(v)
	return v


func show_screen(name: String) -> void:
	for k in screens:
		screens[k].visible = k == name
	touch.visible = name == "hud" and is_touch()
	if not touch.visible:
		touch.release_all()
	# With touch controls, CAM and pause are tapped through TouchControls.
	var mf := Control.MOUSE_FILTER_IGNORE if touch.visible else Control.MOUSE_FILTER_STOP
	_cam_btn.mouse_filter = mf
	_pause_btn.mouse_filter = mf


static func is_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


# ---------- HUD ----------

func _build_hud() -> void:
	var hud := _screen("hud")
	touch = TouchControls.new()
	touch.name = "Touch"
	hud.add_child(touch)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0.2, 0.1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	hud.add_child(_flash)

	# Top left: score, coins, crashes left.
	var tl := VBoxContainer.new()
	tl.position = Vector2(24, 36)
	tl.add_theme_constant_override("separation", 0)
	hud.add_child(tl)
	_score = _label("0", 44, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	tl.add_child(_score)
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 8)
	cr.add_child(_coin_icon(26))
	_coins = _label("0", 30, ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	cr.add_child(_coins)
	tl.add_child(cr)
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", 8)
	lr.add_child(_label("CRASHES LEFT", 20, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_LEFT))
	for i in 3:
		var d := Panel.new()
		d.custom_minimum_size = Vector2(22, 22)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lr.add_child(d)
		_life_dots.append(d)
	tl.add_child(lr)

	# Top centre: speed and nitro bar.
	var tc := VBoxContainer.new()
	tc.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tc.position = Vector2(-150, 10)
	tc.custom_minimum_size = Vector2(300, 0)
	tc.add_theme_constant_override("separation", 0)
	hud.add_child(tc)
	_speed = _label("0", 64)
	tc.add_child(_speed)
	_speed_unit = _label("KM/H", 20, Color(1, 1, 1, 0.75))
	tc.add_child(_speed_unit)
	_nitro_bar = ProgressBar.new()
	_nitro_bar.custom_minimum_size = Vector2(300, 22)
	_nitro_bar.show_percentage = false
	_nitro_bar.max_value = 100
	_nitro_fill = _box(NITRO_C, 8)
	_nitro_bar.add_theme_stylebox_override("fill", _nitro_fill)
	tc.add_child(_nitro_bar)
	var nl := _label("NITRO", 18, NITRO_C)
	tc.add_child(nl)

	# Top right: camera and pause.
	var tr := HBoxContainer.new()
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(-300, 20)
	tr.custom_minimum_size = Vector2(280, 0)
	tr.alignment = BoxContainer.ALIGNMENT_END
	hud.add_child(tr)
	_cam_btn = _btn("CAM", "camera", 120)
	tr.add_child(_cam_btn)
	_pause_btn = _btn("II", "pause", 90)
	tr.add_child(_pause_btn)
	# On touch screens these are tapped through TouchControls, so a second
	# finger works while the first one holds steer or nitro.
	touch.tap_targets = {"camera": _cam_btn, "pause": _pause_btn}
	touch.tapped.connect(func(n: String) -> void: action.emit(n))

	_popup = _label("", 52, ACCENT)
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.custom_minimum_size = Vector2(900, 80)
	_popup.position = Vector2(-450, -170)
	_popup.pivot_offset = Vector2(450, 40)
	_popup.visible = false
	hud.add_child(_popup)

	# FPS counter in the top-left corner (all screens).
	_fps = _label("", 18, Color(0.7, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	_fps.position = Vector2(8, 4)
	add_child(_fps)


func hud(score: int, coins: int, speed_kmh: int, nitro: float, boosting: bool, lives: int) -> void:
	_score.text = str(score)
	_coins.text = str(coins)
	_speed.text = str(speed_kmh)
	_nitro_bar.value = nitro * 100.0
	_nitro_fill.bg_color = Color(1, 0.6, 0.2) if boosting else NITRO_C
	if lives != _lives_shown:
		_lives_shown = lives
		for i in 3:
			_life_dots[i].add_theme_stylebox_override("panel", _box(Color(1, 0.25, 0.25) if i < lives else Color(1, 1, 1, 0.15), 11))
	touch.nitro_level = nitro
	touch.queue_redraw()


func popup(text: String, color := ACCENT) -> void:
	_popup.text = text
	_popup.add_theme_color_override("font_color", color)
	_popup.visible = true
	_popup_time = 1.4


func flash() -> void:
	_flash.color = Color(1, 0.2, 0.1, 0.45)
	_flash.visible = true


func set_cam_name(view: String) -> void:
	_cam_btn.text = "CAM"
	if _pause_cam:
		_pause_cam.text = "CAMERA: " + Save.VIEW_NAMES[view]


# ---------- Start menu ----------

func _build_menu() -> void:
	var s := _screen("menu")
	var v := _panel(s, 560, true)
	v.add_child(_label("HIGHWAY BLITZ", 60, ACCENT))
	v.add_child(_label("GODOT EDITION", 22, Color(1, 1, 1, 0.7)))
	_menu_best = _label("", 26)
	v.add_child(_menu_best)
	_menu_coins = _label("", 26, ACCENT)
	v.add_child(_menu_coins)
	var play := _btn("PLAY", "play", 420)
	play.custom_minimum_size.y = 80
	play.add_theme_font_size_override("font_size", 38)
	v.add_child(play)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_btn("GARAGE", "garage", 204))
	row.add_child(_btn("SETTINGS", "settings", 204))
	v.add_child(row)
	var sr := HBoxContainer.new()
	sr.alignment = BoxContainer.ALIGNMENT_CENTER
	sr.add_child(_label("STEERING", 22, Color(1, 1, 1, 0.75)))
	for mode in ["buttons", "tilt"]:
		var b := _btn(mode.to_upper(), "", 150)
		b.toggle_mode = true
		b.pressed.connect(func() -> void: action.emit("steer_" + mode))
		_steer_btns[mode] = b
		sr.add_child(b)
	v.add_child(sr)
	v.add_child(_label("Keys: Arrows / A D steer  |  Space nitro  |  Shift drift  |  C camera  |  Esc pause", 18, Color(1, 1, 1, 0.55)))


func menu(best: int, coins: int, steering: String) -> void:
	_menu_best.text = "BEST  %d" % best
	_menu_coins.text = "%d COINS" % coins
	for k in _steer_btns:
		_steer_btns[k].button_pressed = k == steering


# ---------- Pause ----------

func _build_pause() -> void:
	var s := _screen("pause")
	var v := _panel(s, 460)
	v.add_child(_label("PAUSED", 54, ACCENT))
	v.add_child(_btn("RESUME", "resume"))
	v.add_child(_btn("RESTART", "restart"))
	_pause_cam = _btn("CAMERA: CHASE", "camera")
	v.add_child(_pause_cam)
	v.add_child(_btn("SETTINGS", "settings"))
	v.add_child(_btn("QUIT TO MENU", "quit"))


# ---------- Settings ----------

func _build_settings() -> void:
	var s := _screen("settings")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 60
	panel.offset_right = -60
	panel.offset_top = 24
	panel.offset_bottom = -24
	s.add_child(panel)
	var outer := VBoxContainer.new()
	panel.add_child(outer)
	outer.add_child(_label("SETTINGS", 40, ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 40)
	scroll.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	# Left column: camera.
	left.add_child(_label("CAMERA VIEW", 22, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT))
	var vr := HBoxContainer.new()
	for view in Save.VIEWS:
		var b := _btn(Save.VIEW_NAMES[view].replace("FAR CHASE", "FAR"), "", 0)
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func() -> void: _apply_setting("view", view))
		_view_btns[view] = b
		vr.add_child(b)
	left.add_child(vr)
	_slider(left, "fov", "FIELD OF VIEW", "%d")
	_slider(left, "dist", "CAMERA DISTANCE", "%.1f m")
	_slider(left, "height", "CAMERA HEIGHT", "%.1f m")
	_slider(left, "follow", "SMOOTH FOLLOW (low = smoother)", "%.1f")
	_toggle(left, "shake", "CAMERA SHAKE")
	_toggle(left, "speed_fx", "SPEED FOV BOOST")

	# Right column: graphics, sound, controls.
	right.add_child(_label("GRAPHICS", 22, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT))
	var gr := HBoxContainer.new()
	for g in ["low", "high"]:
		var b := _btn(g.to_upper(), "", 0)
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(func() -> void: _apply_setting("gfx", g))
		_gfx_btns[g] = b
		gr.add_child(b)
	right.add_child(gr)
	_toggle(right, "show_fps", "FPS COUNTER")
	_slider(right, "sfx", "SOUND EFFECTS", "%d%%")
	_slider(right, "music", "MUSIC", "%d%%")
	_toggle(right, "muted", "MUTE ALL")
	_toggle(right, "tilt_invert", "INVERT TILT STEERING")

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(_btn("RESET", "settings_reset", 240))
	bottom.add_child(_btn("DONE", "settings_done", 240))
	outer.add_child(bottom)


func _apply_setting(key: String, value: Variant) -> void:
	Save.set_s(key, value)
	refresh_settings()
	if key == "view":
		action.emit("view_changed")
	elif key == "gfx":
		action.emit("gfx_changed")


func _slider(parent: VBoxContainer, key: String, title: String, fmt: String) -> void:
	var row := HBoxContainer.new()
	var l := _label(title, 21, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var val := _label("", 21, ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(val)
	parent.add_child(row)
	var sl := HSlider.new()
	var r: Array = Save.RANGES[key]
	sl.min_value = r[0]
	sl.max_value = r[1]
	sl.step = r[2]
	sl.custom_minimum_size = Vector2(0, 36)
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(func(v: float) -> void:
		Save.set_s(key, v)
		val.text = fmt % v)
	parent.add_child(sl)
	_sliders[key] = [sl, val, fmt]


func _toggle(parent: VBoxContainer, key: String, title: String) -> void:
	var b := _btn(title, "", 0)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func() -> void: _apply_setting(key, b.button_pressed))
	parent.add_child(b)
	_toggles[key] = [b, title]


func refresh_settings() -> void:
	for k in _sliders:
		var sl: HSlider = _sliders[k][0]
		sl.set_value_no_signal(float(Save.get_s(k)))
		(_sliders[k][1] as Label).text = (_sliders[k][2] as String) % float(Save.get_s(k))
	for k in _toggles:
		var b: Button = _toggles[k][0]
		var on: bool = Save.get_s(k)
		b.set_pressed_no_signal(on)
		b.text = "%s: %s" % [_toggles[k][1], "ON" if on else "OFF"]
	for k in _view_btns:
		_view_btns[k].set_pressed_no_signal(k == Save.get_s("view"))
	for k in _gfx_btns:
		_gfx_btns[k].set_pressed_no_signal(k == Save.get_s("gfx"))
	_fps.visible = Save.get_s("show_fps")
	set_cam_name(Save.get_s("view"))


# ---------- Game over ----------

func _build_gameover() -> void:
	var s := _screen("gameover")
	var v := _panel(s, 560, true)
	_go_title = _label("WRECKED!", 56, Color(1, 0.4, 0.3))
	v.add_child(_go_title)
	_go_score = _label("", 64)
	v.add_child(_go_score)
	_go_best = _label("", 28, ACCENT)
	v.add_child(_go_best)
	_go_stats = _label("", 22, Color(1, 1, 1, 0.8))
	v.add_child(_go_stats)
	var again := _btn("PLAY AGAIN", "play", 420)
	again.custom_minimum_size.y = 76
	v.add_child(again)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_btn("GARAGE", "garage", 204))
	row.add_child(_btn("MENU", "quit", 204))
	v.add_child(row)


func gameover(score: int, best: int, is_best: bool, coins: int, near: int, dist_m: float) -> void:
	_go_score.text = str(score)
	_go_best.text = "NEW BEST!" if is_best else "BEST  %d" % best
	_go_stats.text = "%d coins   |   %d near misses   |   %.1f km" % [coins, near, dist_m / 1000.0]


# ---------- Garage ----------

func _build_garage() -> void:
	var s := _screen("garage")
	# Bottom bar so the car stays visible above it.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.custom_minimum_size = Vector2(980, 0)
	panel.position = Vector2(-490, -300)
	s.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(_btn("<", "car_prev", 90))
	_gar_name = _label("", 44, ACCENT)
	_gar_name.custom_minimum_size = Vector2(420, 0)
	top.add_child(_gar_name)
	top.add_child(_btn(">", "car_next", 90))
	v.add_child(top)
	var mid := HBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	_gar_stats = VBoxContainer.new()
	_gar_stats.custom_minimum_size = Vector2(520, 0)
	_gar_stats.add_theme_constant_override("separation", 4)
	mid.add_child(_gar_stats)
	var right := VBoxContainer.new()
	_gar_coins = _label("", 26, ACCENT)
	right.add_child(_gar_coins)
	_gar_action = _btn("SELECT", "car_action", 300)
	right.add_child(_gar_action)
	right.add_child(_btn("BACK", "garage_back", 300))
	mid.add_child(right)
	v.add_child(mid)


func garage(spec: Dictionary, index: int, total: int) -> void:
	_gar_name.text = "%s  (%d/%d)" % [spec.name, index + 1, total]
	_gar_coins.text = "%d COINS" % Save.coins
	for c in _gar_stats.get_children():
		c.queue_free()
	var stats := [
		["TOP SPEED", float(spec.max_speed) * 3.6, 84.0 * 3.6 * 1.05, "%d km/h"],
		["ACCELERATION", spec.accel, 19.0, "%.0f"],
		["HANDLING", spec.handling, 1.3, "%.2f"],
		["NITRO", spec.nitro, 1.35, "%.2f"],
	]
	for st in stats:
		var row := HBoxContainer.new()
		var l := _label(st[0], 20, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_LEFT)
		l.custom_minimum_size = Vector2(180, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(220, 18)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 100
		bar.value = float(st[1]) / float(st[2]) * 100.0
		var fill := _box(ACCENT, 8)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		row.add_child(_label(st[3] % st[1], 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT))
		_gar_stats.add_child(row)
	var owned: bool = spec.id in Save.owned
	if not owned:
		_gar_action.text = "BUY  %d COINS" % spec.price
		_gar_action.disabled = Save.coins < spec.price
	elif Save.selected == spec.id:
		_gar_action.text = "SELECTED"
		_gar_action.disabled = true
	else:
		_gar_action.text = "SELECT"
		_gar_action.disabled = false
