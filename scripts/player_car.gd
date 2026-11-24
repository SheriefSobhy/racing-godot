class_name PlayerCar
extends VehicleBody3D
## The player's car: a VehicleBody3D on four VehicleWheel3D (raycast
## suspension, tyre grip). Auto-accelerates to the car's top speed; NITRO
## raises top speed and acceleration; DRIFT lowers rear grip and swings the
## tail out, which fills the nitro bar.
## Arcade helpers keep it drivable on a phone: speed-sensitive steering,
## downforce, a yaw stabiliser, and a straightening assist after crashes.

signal crashed_into(body: Node, at: Vector3)

const START_S := 400.0
const WHEEL_REST := 0.16
const GRIP_FRONT := 5.0
const GRIP_REAR := 5.2
const DRIFT_REAR_GRIP := 0.7
const DRIFT_FRONT_GRIP := 1.6
const LATERAL_G := 20.0           # steering is limited to about this much sideways acceleration
const DRIFT_ANGLE := 0.42          # target slide angle while drifting (radians)
const DOWNFORCE := 1.1             # newtons per (m/s)^2

var spec: Dictionary = Cars.PLAYER[0]
var model: Node3D
var half_width := 1.05
var length := 4.5
var wheel_radius := 0.525
var top := 1.2            # roof height

## Road-space state, updated every physics frame.
var s := START_S
var x := 2.0
var speed := 0.0          # forward speed in m/s
var heading_err := 0.0    # car heading minus road heading (radians, + = nose right)
var slide := 0.0          # angle between the nose and the direction of travel (+ = nose right)

## Driving state.
var control := false      # true while racing (auto-accelerate, inputs)
var steer_in := 0.0       # -1..1 from the input, + = right
var nitro_in := false
var drift_in := false
var steer := 0.0
var nitro := 0.3          # 0..1
var boosting := false
var drifting := false
var drift_dir := 0.0
var scraping := false
var invuln := 0.0
var recover := 0.0        # seconds of extra straightening after a crash

var wheels_front: Array[VehicleWheel3D] = []
var wheels_rear: Array[VehicleWheel3D] = []
var exhausts: Array[Vector3] = []    # local exhaust positions
var _flip_time := 0.0


func _ready() -> void:
	mass = 1200.0
	collision_layer = 2
	collision_mask = 1 | 4
	contact_monitor = true
	max_contacts_reported = 6
	continuous_cd = true
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.42, 0.05)
	angular_damp = 1.5
	can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.3
	pm.bounce = 0.1
	physics_material_override = pm
	body_entered.connect(_on_body_entered)


## Builds the car for a spec: model, collision box and wheels.
func setup(car_spec: Dictionary) -> void:
	spec = car_spec
	for c in get_children():
		if c is VehicleWheel3D or c is CollisionShape3D or c == model:
			remove_child(c)
			c.queue_free()
	wheels_front.clear()
	wheels_rear.clear()
	exhausts.clear()

	model = Cars.instance(spec.model)
	model.scale = Vector3.ONE * Cars.SCALE
	add_child(model)
	var box := Cars.body_aabb(model)
	box = AABB(box.position * Cars.SCALE, box.size * Cars.SCALE)
	half_width = box.size.x / 2.0
	length = box.size.z
	top = box.end.y

	# Collision: the body box, lifted clear of the road so only the wheels touch it.
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var bottom := 0.38
	var top := box.end.y
	shape.size = Vector3(box.size.x * 0.96, top - bottom, box.size.z * 0.97)
	cs.shape = shape
	cs.position = Vector3(0, (top + bottom) / 2.0, box.get_center().z)
	add_child(cs)

	# Glossier paint so the sky shows in it.
	var body_mesh := model.get_node_or_null("body") as MeshInstance3D
	if body_mesh and body_mesh.mesh.get_surface_count() > 0:
		var m := body_mesh.mesh.surface_get_material(0)
		if m is StandardMaterial3D:
			var gm := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			gm.metallic = 0.35
			gm.roughness = 0.32
			gm.metallic_specular = 0.6
			body_mesh.material_override = gm

	# Wheels: move each wheel mesh from the model into a VehicleWheel3D.
	var wm := Cars.wheels(model)
	for wname in wm:
		var mesh: MeshInstance3D = wm[wname]
		var front := String(wname).contains("front")
		var w := VehicleWheel3D.new()
		w.name = wname
		var centre := mesh.position * Cars.SCALE
		wheel_radius = 0.3 * Cars.SCALE
		w.position = centre + Vector3(0, WHEEL_REST - 0.06, 0)
		w.set_meta("centre", centre)
		w.wheel_radius = wheel_radius
		w.wheel_rest_length = WHEEL_REST
		w.suspension_travel = 0.2
		w.suspension_stiffness = 55.0
		w.suspension_max_force = 24000.0
		w.damping_compression = 2.6
		w.damping_relaxation = 3.4
		w.wheel_friction_slip = GRIP_FRONT if front else GRIP_REAR
		w.wheel_roll_influence = 0.02
		w.use_as_steering = front
		w.use_as_traction = not front
		model.remove_child(mesh)
		mesh.position = Vector3.ZERO
		mesh.scale = Vector3.ONE * Cars.SCALE
		w.add_child(mesh)
		add_child(w)
		if front:
			wheels_front.append(w)
		else:
			wheels_rear.append(w)
	for side: float in [-1.0, 1.0]:
		exhausts.append(Vector3(side * 0.35 * Cars.SCALE, 0.35 * Cars.SCALE, box.position.z + 0.05))


## Puts the car on the road at (s, x), facing along it, at a given speed.
func place(at_s: float, at_x: float, v := 0.0) -> void:
	s = at_s
	x = at_x
	var t := Track.xform(at_s, at_x)
	t.origin += t.basis.y * 0.1
	global_transform = t
	linear_velocity = t.basis.z * v
	angular_velocity = Vector3.ZERO
	steer = 0.0
	steering = 0.0
	for w in wheels_rear:
		w.engine_force = 0.0
		w.brake = 0.0
	# A frozen VehicleBody3D doesn't update its wheels, so put them back on
	# the car by hand (they would stay where the car was before).
	for w in wheels_front + wheels_rear:
		w.transform = Transform3D(Basis(), w.get_meta("centre"))
	reset_physics_interpolation()


func reset_run() -> void:
	nitro = 0.3
	boosting = false
	drifting = false
	drift_dir = 0.0
	scraping = false
	invuln = 0.0
	recover = 0.0
	steer_in = 0.0
	nitro_in = false
	drift_in = false
	_flip_time = 0.0


func _physics_process(dt: float) -> void:
	if freeze:
		return
	var b := global_basis
	var fwd := b.z
	speed = linear_velocity.dot(fwd)
	var p := Track.project(global_position, s)
	s = p.x
	x = p.y
	var road_fwd := Track.forward_flat(s)
	var fwd_flat := Vector3(fwd.x, 0, fwd.z).normalized()
	heading_err = atan2(fwd_flat.cross(road_fwd).y, fwd_flat.dot(road_fwd))
	var vel_flat := Vector3(linear_velocity.x, 0, linear_velocity.z)
	slide = 0.0
	if vel_flat.length() > 3.0:
		var u := vel_flat.normalized()
		slide = atan2(fwd_flat.cross(u).y, fwd_flat.dot(u))

	# Inputs
	var steer_target := steer_in if control else 0.0
	steer = lerpf(steer, steer_target, minf(1.0, dt * 9.0))
	boosting = control and nitro_in and nitro > 0.01
	drifting = control and drift_in and linear_velocity.dot(road_fwd) > 14.0

	var road_v := linear_velocity.dot(road_fwd)
	var lat_v := linear_velocity.dot(Track.right(s))
	var k := Track.curvature(s)
	var up := b.y
	var yaw_rate := angular_velocity.dot(up)
	var inertia := mass * 2.2

	# Longitudinal: auto-accelerate towards top speed.
	var max_v: float = spec.max_speed * (1.32 if boosting else 1.0)
	var ref_v := road_v if drifting else speed
	var force := 0.0
	var brake_f := 0.0
	if not control:
		brake_f = 12.0
	elif ref_v < max_v:
		var a: float = spec.accel * (2.2 if boosting else 1.0) * (1.0 - 0.55 * clampf(ref_v / max_v, 0.0, 1.0))
		force = mass * a
	else:
		force = -mass * (ref_v - max_v) * 1.2
	if drifting:
		# Drifting: the rear tyres are sliding, so drive the car along the road
		# directly (with racing-3d's 7%/s drift slowdown), not through the wheels.
		force -= mass * road_v * 0.07
		apply_central_force(road_fwd * force)
		force = 0.0
	for w in wheels_rear:
		w.engine_force = force / wheels_rear.size()
		w.brake = brake_f
	for w in wheels_front:
		w.brake = brake_f * 0.6

	# Nitro bar
	if boosting:
		nitro = maxf(0.0, nitro - dt / (3.2 * spec.nitro))
	elif control:
		nitro = minf(1.0, nitro + dt * 0.02)

	# Steering: the wheels turn less at speed, limited to about LATERAL_G of
	# sideways grip. Positive VehicleBody3D steering turns left, so negate.
	var v := absf(speed)
	var steer_max: float = clampf(LATERAL_G * 2.6 / (v * v + 1.0), 0.008, 0.5) * spec.handling
	# Feed-forward for the road's curve, so steering is about lane changes.
	var ff := atan(k * 2.6)
	var target_steering := -(steer * steer_max + ff)

	# Drift direction: the steer side, else the way the road bends.
	if drifting:
		if absf(steer) > 0.2:
			drift_dir = signf(steer)
		elif drift_dir == 0.0:
			drift_dir = signf(k) if k != 0.0 else 1.0
	else:
		drift_dir = 0.0
	var grip_r := DRIFT_REAR_GRIP if drifting else GRIP_REAR
	var grip_f := DRIFT_FRONT_GRIP if drifting else GRIP_FRONT
	var blend := minf(1.0, dt * (10.0 if drifting else 3.0))
	for w in wheels_rear:
		w.wheel_friction_slip = lerpf(w.wheel_friction_slip, grip_r, blend)
	for w in wheels_front:
		w.wheel_friction_slip = lerpf(w.wheel_friction_slip, grip_f, blend)

	var torque := 0.0
	if drifting:
		# Front wheels point along the direction of travel (countersteer).
		target_steering = clampf(slide, -0.6, 0.6) - steer * 0.1
		# Hold the tail out at the drift angle; steering into it widens it.
		var target := drift_dir * (DRIFT_ANGLE + 0.12 * maxf(0.0, steer * drift_dir))
		torque = (-(target - slide) * 9.0 - (yaw_rate + road_v * k) * 2.5) * inertia
		# Sideways motion follows the steering, as in racing-3d's drift model
		# (this also supplies the grip needed to follow the curve).
		var lat_target: float = steer * (5.0 + road_v * 0.13) * spec.handling * 1.3
		apply_central_force(Track.right(s) * (lat_target - lat_v) * 2.5 * mass)
		# Sliding tyres scrub speed; give it back along the direction of travel
		# so the drift keeps racing-3d's pace.
		if vel_flat.length() > 1.0:
			apply_central_force(vel_flat.normalized() * mass * 16.0 * absf(sin(slide)))
		var gain := 0.1 * (0.4 + minf(1.0, absf(steer) + absf(k) * 400.0)) * minf(1.0, road_v / 40.0)
		nitro = minf(1.0, nitro + gain * dt)
	else:
		# Stabiliser: damp sideways sliding when not drifting.
		var gain_s := 6.0 if recover <= 0.0 else 14.0
		torque = (slide * gain_s) * inertia - yaw_rate * (1.0 if recover <= 0.0 else 4.0) * inertia * 0.5
		# After a crash (or when badly off course) also turn back to the road.
		if recover > 0.0 or absf(heading_err) > 0.5:
			torque += heading_err * 10.0 * inertia
	steering = lerpf(steering, target_steering, minf(1.0, dt * 12.0))
	# The car's nose turns right with negative torque about up.
	if control or recover > 0.0:
		apply_torque(up * torque)

	# Kill sideways slide that the stabiliser could not (mostly after crashes).
	if recover > 0.0 and not drifting:
		var right_v := linear_velocity.dot(b.x)
		apply_central_force(-b.x * right_v * mass * 1.5)

	# Anti-roll: keep the car upright relative to the road (like stiff
	# anti-roll bars), so hard steering and drifts never tip it over.
	var road_up := Track.xform(s, x).basis.y
	var tilt_axis := up.cross(road_up)
	var ang_tilt := angular_velocity - up * yaw_rate
	apply_torque((tilt_axis * 40.0 - ang_tilt * 6.0) * inertia)

	# Downforce keeps it planted at 300 km/h.
	apply_central_force(-up * DOWNFORCE * speed * speed)

	# Scraping along the guard rail slows the car.
	var rail_gap := Track.RAIL_O - absf(x) - half_width
	scraping = rail_gap < 0.25 and v > 5.0
	if scraping:
		apply_central_force(-linear_velocity * mass * 0.5)

	if invuln > 0.0:
		invuln -= dt
	if recover > 0.0:
		recover -= dt

	# Flipped over or fell off the world: put it back on the road.
	var road_y := Track.height(s)
	if up.y < 0.3 or global_position.y < road_y - 8.0:
		_flip_time += dt
	else:
		_flip_time = 0.0
	if _flip_time > 1.2 or global_position.y < road_y - 20.0:
		place(s, clampf(x, -7.0, 7.0), maxf(speed, 10.0) * 0.5)
		invuln = maxf(invuln, 1.5)
		_flip_time = 0.0


## Called by the game when a crash is counted.
func on_crash() -> void:
	invuln = 2.0
	recover = 1.6
	linear_velocity *= 0.55


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("traffic"):
		var at := (global_position + (body as Node3D).global_position) * 0.5 + Vector3(0, 0.7, 0)
		crashed_into.emit(body, at)


## True while the given rear wheel is sliding (for smoke and skid marks).
func wheel_sliding(w: VehicleWheel3D) -> bool:
	return w.is_in_contact() and (drifting or w.get_skidinfo() < 0.4) and absf(speed) > 6.0
