class_name TouchControls
extends Control
## On-screen driving buttons, drawn with simple shapes: steer left/right
## (bottom left), DRIFT and NITRO (bottom right). Each finger is tracked
## separately, so you can steer and hold nitro at the same time, and slide a
## finger from left to right. They press the same input actions as the
## keyboard (steer_left, steer_right, drift, nitro).
## In tilt mode the steering buttons are hidden.

const COLOR_FILL := Color(1, 1, 1, 0.14)
const COLOR_PRESSED := Color(1, 1, 1, 0.38)
const COLOR_LINE := Color(1, 1, 1, 0.55)
const NITRO_COLOR := Color(0.25, 0.75, 1.0)
const DRIFT_COLOR := Color(1.0, 0.55, 0.2)

signal tapped(name: String)

var tilt_mode := false
## Buttons tapped through here (name -> Control), e.g. camera and pause.
var tap_targets := {}
var nitro_level := 0.0           # 0..1, drawn on the NITRO button

# finger index -> {"pos": Vector2, "button": String}
var _fingers := {}
var _pressed := {}               # button -> true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _rects() -> Dictionary:
	var w := size.x
	var h := size.y
	var r := {
		"drift": Rect2(w - 410, h - 190, 180, 160),
		"nitro": Rect2(w - 215, h - 245, 190, 215),
	}
	if not tilt_mode:
		r["steer_left"] = Rect2(24, h - 205, 175, 175)
		r["steer_right"] = Rect2(215, h - 205, 175, 175)
	return r


func _button_at(p: Vector2) -> String:
	var rects := _rects()
	for k in rects:
		if (rects[k] as Rect2).grow(14).has_point(p):
			return k
	return ""


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var e := make_input_local(event) as InputEventScreenTouch
		if e.pressed:
			for n in tap_targets:
				var c: Control = tap_targets[n]
				if c.is_visible_in_tree() and c.get_global_rect().grow(8).has_point(e.position):
					tapped.emit(n)
					return
			var b := _button_at(e.position)
			_fingers[e.index] = {"pos": e.position, "button": b}
		else:
			var idx := e.index
			if not _fingers.has(idx):
				idx = _nearest(e.position)
			_fingers.erase(idx)
		_sync()
	elif event is InputEventScreenDrag:
		var e := make_input_local(event) as InputEventScreenDrag
		_fingers[e.index] = {"pos": e.position, "button": _button_at(e.position)}
		_sync()


func _nearest(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for i in _fingers:
		var d := (_fingers[i].pos as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _sync() -> void:
	var now := {}
	for i in _fingers:
		var b: String = _fingers[i].button
		if b != "":
			now[b] = true
	for k in ["steer_left", "steer_right", "drift", "nitro"]:
		var was: bool = _pressed.has(k)
		var on: bool = now.has(k)
		if on and not was:
			Input.action_press(k)
		elif was and not on:
			Input.action_release(k)
	_pressed = now
	queue_redraw()


func release_all() -> void:
	_fingers.clear()
	_sync()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var rects := _rects()
	for k in rects:
		var r: Rect2 = rects[k]
		var on := _pressed.has(k)
		var sb := StyleBoxFlat.new()
		sb.bg_color = COLOR_PRESSED if on else COLOR_FILL
		sb.border_color = COLOR_LINE
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(28)
		if k == "nitro":
			sb.border_color = NITRO_COLOR
		elif k == "drift":
			sb.border_color = DRIFT_COLOR
		draw_style_box(sb, r)
		var c := r.get_center()
		if k == "steer_left" or k == "steer_right":
			var d := -1.0 if k == "steer_left" else 1.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(d * 34, 0), c + Vector2(-d * 26, -40), c + Vector2(-d * 26, 40)]), Color(1, 1, 1, 0.85))
		else:
			if k == "nitro":
				# Fill level of the nitro bar, from the bottom.
				var fr := Rect2(r.position.x + 10, r.end.y - 10 - (r.size.y - 20) * nitro_level, r.size.x - 20, (r.size.y - 20) * nitro_level)
				var fb := StyleBoxFlat.new()
				fb.bg_color = Color(NITRO_COLOR, 0.35)
				fb.set_corner_radius_all(18)
				draw_style_box(fb, fr)
			var text := "NITRO" if k == "nitro" else "DRIFT"
			var fs := 34
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
			draw_string_outline(font, c + Vector2(-tw / 2.0, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.6))
			draw_string(font, c + Vector2(-tw / 2.0, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
