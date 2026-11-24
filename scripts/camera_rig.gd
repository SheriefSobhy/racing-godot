class_name CameraRig
extends Camera3D
## Race camera (same behaviour as racing-3d's camera.js). The chase views sit
## on the road behind the car, so hills and curves stay smooth; hood and
## bumper are mounted on the car. Uses Save settings: view, fov, dist,
## height, follow, shake, speed_fx.

var shake := 0.0
var _x := 0.0
var _lx := 0.0
var _dist := 7.0
var _h := 2.7
var _fov := 62.0
var _started := false
var _orbit := 0.0


func _ready() -> void:
	near = 0.25
	far = 1500.0
	fov = Save.get_s("fov")
	_fov = fov


func reset() -> void:
	_started = false
	shake = 0.0
	_dist = Save.get_s("dist")
	_h = Save.get_s("height")


func kick(amount: float) -> void:
	shake = maxf(shake, amount)


func base_fov() -> float:
	return float(Save.get_s("fov"))


## frozen: game paused (no shake jitter and no shake decay).
func follow_car(dt: float, car: PlayerCar, frozen := false) -> void:
	var view: String = Save.get_s("view")
	var look := Vector3.ZERO
	var follow: float = Save.get_s("follow")
	if view == "chase" or view == "far":
		var far_view := view == "far"
		var k := 1.0 - exp(-dt * follow) if _started else 1.0
		var kd := 1.0 - exp(-dt * 4.0) if _started else 1.0
		# Road position of the interpolated car, so it is smooth at any frame rate.
		var rp := Track.project(car.get_global_transform_interpolated().origin, car.s)
		_x += (rp.y * 0.82 - _x) * k
		_lx += (rp.y * 0.7 - _lx) * k
		var base_dist: float = Save.get_s("dist") * (1.6 if far_view else 1.0)
		var pull := base_dist * 0.17 if Save.get_s("speed_fx") and car.boosting else 0.0
		_dist += (base_dist + pull - _dist) * kd
		var target_h: float = Save.get_s("height") * (1.8 if far_view else 1.0)
		_h += (target_h - _h) * kd
		var cs := rp.x - _dist
		global_position = Track.point(cs) + Track.right(cs) * _x + Vector3(0, _h, 0)
		var ls := rp.x + (16.0 if far_view else 10.0)
		look = Track.point(ls) + Track.right(ls) * _lx + Vector3(0, 0.9, 0)
	else:
		# Car-local mounts (the car faces +Z).
		var t := car.get_global_transform_interpolated()
		if view == "hood":
			global_position = t * Vector3(0, car.top * 0.8, car.length * 0.2)
			look = t * Vector3(0, car.top * 0.72, 30)
		else:
			global_position = t * Vector3(0, 0.55, car.length * 0.5 + 0.05)
			look = t * Vector3(0, 0.5, 30)
		_x = car.x * 0.82
		_lx = car.x * 0.7
	_started = true

	if shake > 0.0 and not frozen:
		if Save.get_s("shake"):
			var a := shake * shake * (1.0 if view == "chase" or view == "far" else 0.35)
			global_position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * a
		shake = maxf(0.0, shake - dt * 1.4)
	var up := Vector3.UP if view == "chase" or view == "far" else car.global_basis.y
	if global_position.distance_squared_to(look) > 0.01:
		look_at(look, up)

	var target_fov := base_fov()
	if Save.get_s("speed_fx"):
		target_fov += clampf(car.speed / float(car.spec.max_speed), 0.0, 1.0) * 7.0 + (9.0 if car.boosting else 0.0)
	_fov += (target_fov - _fov) * (1.0 - exp(-dt * 4.0))
	fov = _fov


## Slow orbit around the car for the menus.
## side_shift moves the car to the right of the screen (metres), to leave
## room for a menu panel on the left.
func orbit(dt: float, car: Node3D, radius: float, height: float, rate: float, side_shift := 0.0) -> void:
	_orbit += dt * rate
	var p := car.global_position
	var t := car.global_transform
	global_position = p + t.basis.x * sin(_orbit) * radius + t.basis.z * cos(_orbit) * radius + Vector3(0, height, 0)
	look_at(p + Vector3(0, 0.6, 0), Vector3.UP)
	if side_shift != 0.0:
		look_at(p + Vector3(0, 0.6, 0) - global_basis.x * side_shift, Vector3.UP)
	fov = base_fov()
	_fov = fov
	_started = false


func set_orbit(a: float) -> void:
	_orbit = a
