class_name Traffic
extends Node3D
## Traffic to dodge (spawning and lane logic from racing-3d's traffic.js).
## Each car is a real RigidBody3D. Until it is hit, its velocity is set every
## physics frame so it follows its lane exactly (no gravity, it hovers a few
## centimetres over the road). The collision with the player is therefore a
## real momentum exchange. Once hit, the car is left to physics: gravity on,
## tyre friction on its box, a random spin, and it can knock other cars too.

signal near_miss(car: TrafficCar)

const AHEAD := 430.0

var _pool := {}             # template index -> Array[TrafficCar]
var cars: Array[TrafficCar] = []
var _next_s := 0.0
var _start_s := 0.0
var _total_weight := 0.0


func _ready() -> void:
	for t in Cars.TRAFFIC:
		_total_weight += t.weight


## Loads one car of every model into the pool, so the first spawns don't stutter.
func prewarm() -> void:
	for ti in Cars.TRAFFIC.size():
		var car := TrafficCar.new()
		car.build(ti)
		add_child(car)
		_recycle(car)


func reset(at_s: float) -> void:
	for c in cars:
		_recycle(c)
	cars.clear()
	_start_s = at_s
	_next_s = at_s + 90.0


func _recycle(c: TrafficCar) -> void:
	c.deactivate()
	if not _pool.has(c.ti):
		_pool[c.ti] = []
	_pool[c.ti].append(c)


func _spawn(at_s: float, lane: int) -> void:
	var r := randf() * _total_weight
	var ti := 0
	while ti < Cars.TRAFFIC.size() - 1 and r > Cars.TRAFFIC[ti].weight:
		r -= Cars.TRAFFIC[ti].weight
		ti += 1
	var car: TrafficCar
	if _pool.has(ti) and not _pool[ti].is_empty():
		car = _pool[ti].pop_back()
	else:
		car = TrafficCar.new()
		car.build(ti)
		add_child(car)
	car.s = at_s
	car.lane = lane
	car.x = Track.LANES[lane]
	car.target_x = car.x
	car.base_v = (18.0 if car.truck else 21.0) + randf() * 9.0
	car.v = car.base_v
	car.passed = false
	car.min_gap = 99.0
	car.lc_timer = 1.0 + randf() * 5.0 if randf() < 0.3 else INF
	car.activate()
	cars.append(car)


func _lane_free(lane: int, at_s: float, self_car: TrafficCar) -> bool:
	for o in cars:
		if o == self_car or o.hit:
			continue
		if absf(o.x - Track.LANES[lane]) < 2.5 and absf(o.s - at_s) < 16.0:
			return false
	return true


## Moves traffic for one physics step. Returns nothing; near misses are signalled.
func step(dt: float, player: PlayerCar, racing: bool) -> void:
	var diff := clampf((player.s - _start_s) / 9000.0, 0.0, 1.0)

	# Spawn at a frontier ahead of the player.
	var frontier := player.s + AHEAD
	while _next_s < frontier:
		var lanes := [0, 1, 2, 3]
		lanes.shuffle()
		var count := 2 if randf() < 0.22 + diff * 0.35 else 1
		for i in count:
			var cs := _next_s + randf() * 8.0
			if cs < player.s + 160.0 and absf(Track.LANES[lanes[i]] - player.x) < 3.0:
				continue
			if _lane_free(lanes[i], cs, null):
				_spawn(cs, lanes[i])
		_next_s += 48.0 - 22.0 * diff + randf() * 22.0

	for car in cars:
		if car.hit:
			continue
		# Follow a slower car ahead in the same lane.
		var limit := car.base_v
		for o in cars:
			if o == car:
				continue
			var ds := o.s - car.s
			if ds > 0.0 and ds < 16.0 and absf(o.x - car.x) < 2.6:
				limit = minf(limit, 0.0 if o.hit else o.v)
		car.v += (limit - car.v) * minf(1.0, dt * 3.0)
		car.v = maxf(car.v, 0.0)
		# Occasional lane change.
		car.lc_timer -= dt
		if car.lc_timer <= 0.0:
			car.lc_timer = INF
			var opts := []
			for l in [car.lane - 1, car.lane + 1]:
				if l >= 0 and l < 4:
					opts.append(l)
			var nl: int = opts.pick_random()
			if _lane_free(nl, car.s, car):
				car.lane = nl
				car.target_x = Track.LANES[nl]
		var dx := car.target_x - car.x
		car.x += signf(dx) * minf(absf(dx), 1.7 * dt)
		car.yaw = clampf(dx * 0.06, -0.12, 0.12)
		car.s += car.v * dt
		car.drive(dt)

	# Near misses, in road space (s along, x across).
	for car in cars:
		if car.hit:
			continue
		var len_sum := (player.length + car.length) / 2.0
		var wid_sum := player.half_width + car.half_width
		var ds := car.s - player.s
		if absf(ds) < len_sum:
			var gap := absf(car.x - player.x) - wid_sum
			car.min_gap = minf(car.min_gap, gap)
		if not car.passed and ds < -len_sum:
			car.passed = true
			if racing and car.min_gap >= 0.0 and car.min_gap < 1.3 and player.speed > car.v + 8.0:
				near_miss.emit(car)

	# Recycle cars far behind, far ahead or fallen off.
	for i in range(cars.size() - 1, -1, -1):
		var car := cars[i]
		if car.hit:
			var p := Track.project(car.global_position, car.s)
			car.s = p.x
		if car.s < player.s - 45.0 or car.s > player.s + 900.0 or car.global_position.y < Track.height(car.s) - 15.0:
			_recycle(car)
			cars.remove_at(i)


## Spins the wheels of every car (visual only).
func animate(dt: float) -> void:
	for car in cars:
		car.spin_wheels(dt)


class TrafficCar:
	extends RigidBody3D

	var ti := 0
	var truck := false
	var s := 0.0
	var x := 0.0
	var lane := 0
	var target_x := 0.0
	var base_v := 20.0
	var v := 20.0
	var yaw := 0.0
	var lc_timer := INF
	var passed := false
	var min_gap := 99.0
	var hit := false
	var length := 4.5
	var half_width := 1.0
	var hover := 0.06
	var _wheels: Array[Node3D] = []
	var _wheel_r := 0.5
	var _pm := PhysicsMaterial.new()

	func build(index: int) -> void:
		ti = index
		var t: Dictionary = Cars.TRAFFIC[index]
		truck = t.truck
		add_to_group("traffic")
		var model := Cars.instance(t.model)
		var sc: float = t.scale
		model.scale = Vector3.ONE * sc
		# Turn off shadows on the wheels; the body still casts one.
		add_child(model)
		for w in Cars.wheels(model).values():
			_wheels.append(w)
			(w as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wheel_r = 0.3 * sc
		var box := Cars.body_aabb(model)
		box = AABB(box.position * sc, box.size * sc)
		length = box.size.z
		half_width = box.size.x / 2.0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var bottom := 0.3
		shape.size = Vector3(box.size.x * 0.96, box.end.y - bottom, box.size.z * 0.97)
		cs.shape = shape
		cs.position = Vector3(0, (box.end.y + bottom) / 2.0, box.get_center().z)
		add_child(cs)
		hover = 0.02
		mass = 3000.0 if t.model == "truck" or t.model == "delivery" else 1500.0
		collision_layer = 4
		collision_mask = 1 | 2 | 4
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = Vector3(0, 0.5, 0)
		_pm.friction = 0.0
		_pm.bounce = 0.15
		physics_material_override = _pm
		can_sleep = false
		body_entered.connect(_on_body_entered)

	func activate() -> void:
		hit = false
		visible = true
		process_mode = Node.PROCESS_MODE_INHERIT
		gravity_scale = 0.0
		_pm.friction = 0.0
		contact_monitor = false
		linear_damp = 0.0
		angular_damp = 0.0
		freeze = false
		var t := _target()
		global_transform = t
		linear_velocity = t.basis.z * v
		angular_velocity = Vector3.ZERO
		reset_physics_interpolation()

	func deactivate() -> void:
		visible = false
		freeze = true
		process_mode = Node.PROCESS_MODE_DISABLED
		# Park it far away so it can't be touched.
		global_position = Vector3(0, -500, 0)

	func _target() -> Transform3D:
		# Traffic drives along +s, the same way as the player.
		var t := Track.xform(s, x, yaw)
		t.origin += t.basis.y * hover
		return t

	## Follows the lane exactly by setting the velocity that reaches the
	## target pose by the next physics step.
	func drive(dt: float) -> void:
		var t := _target()
		linear_velocity = (t.origin - global_position) / dt
		var q := (t.basis.get_rotation_quaternion() * global_basis.get_rotation_quaternion().inverse()).normalized()
		var angle := q.get_angle()
		if angle > PI:
			angle -= TAU
		angular_velocity = q.get_axis() * angle / dt if absf(angle) > 0.0001 else Vector3.ZERO

	## Crashed: from now on it is a free rigid body.
	func knock(from_velocity: Vector3, side: float) -> void:
		if hit:
			return
		hit = true
		gravity_scale = 1.0
		_pm.friction = 0.6
		linear_damp = 0.3
		angular_damp = 0.8
		contact_monitor = true
		max_contacts_reported = 2
		# Extra kick on top of the physics impulse, for a more dramatic spin.
		apply_central_impulse((from_velocity * 0.15 + global_basis.x * -side * 4.0 + Vector3.UP * 1.5) * mass)
		apply_torque_impulse(Vector3.UP * (2.0 + randf() * 2.5) * (1.0 if randf() < 0.5 else -1.0) * mass * 1.2)

	func _on_body_entered(body: Node) -> void:
		# A wrecked car can knock others into a chain crash.
		if hit and body is TrafficCar and not (body as TrafficCar).hit:
			var other := body as TrafficCar
			other.knock(linear_velocity * 0.5, signf((other.global_position - global_position).dot(global_basis.x)))

	func spin_wheels(dt: float) -> void:
		var fv := linear_velocity.dot(global_basis.z)
		var a := fv * dt / _wheel_r
		for w in _wheels:
			w.rotate_object_local(Vector3.RIGHT, a)
