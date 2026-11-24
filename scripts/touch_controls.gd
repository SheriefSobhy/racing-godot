class_name TouchControls
extends Control
## On-screen driving buttons: steer left / right (bottom left), DRIFT and
## NITRO (bottom right). Each is a TouchScreenButton, Godot's native
## multi-touch button, so every finger works on its own: hold steer and NITRO
## or DRIFT at the same time, or slide a finger from left to right
## (passby_press). They press the same input actions as the keyboard.
## Buttons are placed from the screen size (not this node's size) and light
## up while pressed. In tilt mode the steering buttons are hidden.
## With `debug` on (the FPS counter setting), the last touch position and the
## button under it are shown, to check touch input on a phone.

signal tapped(name: String)

const NITRO_COLOR := Color(0.25, 0.75, 1.0)
const DRIFT_COLOR := Color(1.0, 0.55, 0.2)
const STEER_COLOR := Color(1, 1, 1)

## Button sizes in canvas units (the canvas is 720 units tall).
const SIZES := {
	"steer_left": Vector2(230, 230),
	"steer_right": Vector2(230, 230),
	"drift": Vector2(230, 200),
	"nitro": Vector2(230, 270),
}
const MARGIN := 22.0
const GAP := 18.0

var tilt_mode := false:
	set(v):
		tilt_mode = v
		_layout()
var nitro_level := 0.0           # 0..1, drawn on the NITRO button
var debug := false:
	set(v):
		debug = v
		if _debug_label:
			_debug_label.visible = v
## Buttons tapped through here (name -> Control), e.g. camera and pause.
var tap_targets := {}

var _buttons := {}               # action -> TouchScreenButton
var _debug_label: Label
var _last_touch := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for action in SIZES:
		var b := TouchScreenButton.new()
		b.name = action
		b.action = action
		b.passby_press = true
		b.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
		var sz: Vector2 = SIZES[action]
		b.texture_normal = _button_texture(action, sz, false)
		b.texture_pressed = _button_texture(action, sz, true)
		var shape := RectangleShape2D.new()
		shape.size = sz
		b.shape = shape
		b.shape_centered = true
		if action == "drift" or action == "nitro":
			var l := Label.new()
			l.text = action.to_upper()
			l.add_theme_font_size_override("font_size", 40)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
			l.add_theme_constant_override("outline_size", 8)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.size = sz
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(l)
		b.pressed.connect(queue_redraw)
		b.released.connect(queue_redraw)
		add_child(b)
		_buttons[action] = b
	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 20)
	_debug_label.add_theme_color_override("font_color", Color(0.7, 1, 0.7))
	_debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug_label.add_theme_constant_override("outline_size", 5)
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.visible = debug
	add_child(_debug_label)
	get_viewport().size_changed.connect(_layout)
	_layout()


## The visible canvas size (after stretch), e.g. 1560 x 720 on a 19.5:9 phone.
func _screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _layout() -> void:
	if _buttons.is_empty():
		return
	var vs := _screen_size()
	position = Vector2.ZERO
	size = vs
	var y_bottom := vs.y - MARGIN
	_buttons.steer_left.position = Vector2(MARGIN, y_bottom - SIZES.steer_left.y)
	_buttons.steer_right.position = Vector2(MARGIN + SIZES.steer_left.x + GAP, y_bottom - SIZES.steer_right.y)
	_buttons.nitro.position = Vector2(vs.x - MARGIN - SIZES.nitro.x, y_bottom - SIZES.nitro.y)
	_buttons.drift.position = Vector2(vs.x - MARGIN - SIZES.nitro.x - GAP - SIZES.drift.x, y_bottom - SIZES.drift.y)
	_buttons.steer_left.visible = not tilt_mode
	_buttons.steer_right.visible = not tilt_mode
	_debug_label.position = Vector2(vs.x * 0.5 - 300, vs.y - 120)
	_debug_label.size = Vector2(600, 100)
	queue_redraw()


func _button_rect(action: String) -> Rect2:
	var b: TouchScreenButton = _buttons[action]
	return Rect2(b.position, SIZES[action])


## Rounded button image with a border, and an arrow for the steer buttons.
## The pressed version is filled brighter, so the button lights up.
func _button_texture(action: String, sz: Vector2, pressed: bool) -> ImageTexture:
	var w := int(sz.x)
	var h := int(sz.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var border: Color = NITRO_COLOR if action == "nitro" else (DRIFT_COLOR if action == "drift" else STEER_COLOR)
	var fill := Color(border, 0.55) if pressed else Color(1, 1, 1, 0.16)
	var edge := Color(border, 1.0) if pressed else Color(border, 0.7)
	var r := 34.0
	var bw := 5.0
	for y in h:
		for x in w:
			# Distance outside the rounded rectangle (<= 0 inside).
			var qx := maxf(absf(x + 0.5 - w / 2.0) - (w / 2.0 - r), 0.0)
			var qy := maxf(absf(y + 0.5 - h / 2.0) - (h / 2.0 - r), 0.0)
			var d := Vector2(qx, qy).length() - r
			if d > 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > -bw:
				img.set_pixel(x, y, edge)
			else:
				img.set_pixel(x, y, fill)
	if action == "steer_left" or action == "steer_right":
		var dir := -1.0 if action == "steer_left" else 1.0
		var c := Vector2(w / 2.0, h / 2.0)
		var tip := c + Vector2(dir * 48, 0)
		var b1 := c + Vector2(-dir * 38, -58)
		var b2 := c + Vector2(-dir * 38, 58)
		var col := Color(1, 1, 1, 1.0 if pressed else 0.85)
		for y in h:
			for x in w:
				if Geometry2D.point_is_inside_triangle(Vector2(x + 0.5, y + 0.5), tip, b1, b2):
					img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		var pos: Vector2 = make_input_local(event).position
		if event is InputEventScreenTouch and event.pressed:
			for n in tap_targets:
				var c: Control = tap_targets[n]
				if c.is_visible_in_tree() and c.get_global_rect().grow(8).has_point(pos):
					tapped.emit(n)
					break
		if debug:
			var hit := "-"
			for a in _buttons:
				if _buttons[a].visible and _button_rect(a).has_point(pos):
					hit = a
			var kind := "drag" if event is InputEventScreenDrag else ("down" if event.pressed else "up")
			_last_touch = "touch #%d %s at (%d, %d) -> %s" % [event.index, kind, pos.x, pos.y, hit]
			_update_debug()


func _process(_delta: float) -> void:
	if debug:
		_update_debug()


func _update_debug() -> void:
	var held := []
	for a in ["steer_left", "steer_right", "drift", "nitro"]:
		if Input.is_action_pressed(a):
			held.append(a)
	_debug_label.text = "%s\npressed: %s" % [_last_touch, ", ".join(held) if not held.is_empty() else "none"]


## Drops any held buttons (when leaving the race).
func release_all() -> void:
	for a in ["steer_left", "steer_right", "drift", "nitro"]:
		Input.action_release(a)
	queue_redraw()


func _draw() -> void:
	# Nitro fill level behind the NITRO button, from the bottom.
	if _buttons.is_empty():
		return
	var r := _button_rect("nitro").grow(-10)
	var h := r.size.y * nitro_level
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NITRO_COLOR, 0.35)
	sb.set_corner_radius_all(24)
	draw_style_box(sb, Rect2(r.position.x, r.end.y - h, r.size.x, h))
