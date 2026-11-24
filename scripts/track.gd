class_name Track
## Procedural, endless highway centre line (same formulas as racing-3d).
## The road is described by distance `s` along it; heading and height are
## smooth sums of sines, and x/z positions are integrated into a lookup table.
## Forward is -Z when the heading is 0, and +X is to the right.

const DS := 2.0                       # table resolution in metres
const LANES: Array[float] = [-6.0, -2.0, 2.0, 6.0]
const ROAD_HALF := 10.0
const RAIL_O := 10.55                 # guard rail offset from the centre line
const LIMIT := 8.7                    # lateral offset where the car body touches the rail
const H0 := 0.3 * 0.9320390859672263  # 0.3 * sin(1.2)
const HOFF := 3.0 * 0.644217687237691 # 3 * sin(0.7)

static var _xs := PackedFloat64Array([0.0])
static var _zs := PackedFloat64Array([0.0])


static func heading(s: float) -> float:
	return 0.55 * sin(s / 520.0) + 0.3 * sin(s / 200.0 + 1.2) - H0


static func curvature(s: float) -> float:
	return (0.55 / 520.0) * cos(s / 520.0) + (0.3 / 200.0) * cos(s / 200.0 + 1.2)


static func height(s: float) -> float:
	return 9.0 * sin(s / 300.0) + 3.0 * sin(s / 115.0 + 0.7) - HOFF


static func slope(s: float) -> float:
	return (9.0 / 300.0) * cos(s / 300.0) + (3.0 / 115.0) * cos(s / 115.0 + 0.7)


static func _ensure(s: float) -> void:
	var need := int(ceil(s / DS)) + 2
	while _xs.size() < need:
		var i := _xs.size() - 1
		var th := heading((i + 0.5) * DS)
		_xs.append(_xs[i] + sin(th) * DS)
		_zs.append(_zs[i] - cos(th) * DS)


## Centre-line position at distance s (y is the road height).
static func point(s: float) -> Vector3:
	s = maxf(s, 0.0)
	_ensure(s + DS)
	var f := s / DS
	var i := int(f)
	var t := f - i
	return Vector3(lerpf(_xs[i], _xs[i + 1], t), height(s), lerpf(_zs[i], _zs[i + 1], t))


## Unit vector across the road, to the right (flat).
static func right(s: float) -> Vector3:
	var th := heading(s)
	return Vector3(cos(th), 0.0, sin(th))


## Flat forward direction along the road.
static func forward_flat(s: float) -> Vector3:
	var th := heading(s)
	return Vector3(sin(th), 0.0, -cos(th))


## Road frame at s, offset x metres to the right. The basis follows the car
## convention used in this project: +Z = forward along the road (with slope),
## +Y = up, +X = left.
static func xform(s: float, x := 0.0, yaw := 0.0) -> Transform3D:
	var th := heading(s) + yaw
	var r := Vector3(cos(th), 0.0, sin(th))
	var fwd := Vector3(sin(th), slope(s), -cos(th)).normalized()
	var up := r.cross(fwd).normalized()
	var p := point(s) + right(s) * x
	return Transform3D(Basis(-r, up, fwd), p)


## Terrain height beside the road; rises into rolling hills further out.
static func ground_y(s: float, o: float) -> float:
	var a := absf(o)
	var y := height(s) - 0.05
	if a > 16.0:
		var k := minf(1.0, (a - 16.0) / 140.0)
		var n := 0.5 + 0.5 * sin(s * 0.011 + o * 0.023) * cos(s * 0.007 - o * 0.017)
		y += k * k * 30.0 * n
	return y


## Projects a world position onto the road, starting from a guess of s.
## Returns Vector2(s, x): distance along the road and offset to the right.
static func project(pos: Vector3, s_guess: float) -> Vector2:
	var s := s_guess
	for i in 3:
		var p := point(s)
		var d := pos - p
		s += d.dot(forward_flat(s))
	var p2 := point(s)
	return Vector2(s, (pos - p2).dot(right(s)))
