class_name Pickups
extends Node3D
## Coin lines and nitro pickups on the road (logic from racing-3d's
## pickups.js). Drawn with one MultiMesh each, collected in road space.

signal coin_collected(at: Vector3)
signal nitro_collected(at: Vector3)

const MAX_COINS := 160
const MAX_NITRO := 8

var coins: Array[Vector2] = []    # (s, x)
var nitros: Array[Vector2] = []
var _next_coin := 0.0
var _next_nitro := 0.0
var _time := 0.0
var _coin_mm: MultiMesh
var _nitro_mm: MultiMesh
var _ring_mm: MultiMesh


func _ready() -> void:
	var coin := CylinderMesh.new()
	coin.top_radius = 0.5
	coin.bottom_radius = 0.5
	coin.height = 0.12
	coin.radial_segments = 16
	coin.rings = 1
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(1.0, 0.78, 0.12)
	cm.metallic = 0.8
	cm.roughness = 0.3
	cm.emission_enabled = true
	cm.emission = Color(0.48, 0.32, 0.0)
	coin.material = cm
	_coin_mm = _mm(coin, MAX_COINS)

	var gem := SphereMesh.new()
	gem.radius = 0.6
	gem.height = 1.2
	gem.radial_segments = 4
	gem.rings = 1
	var nm := StandardMaterial3D.new()
	nm.albedo_color = Color(0.21, 0.71, 1.0)
	nm.emission_enabled = true
	nm.emission = Color(0.04, 0.31, 0.68)
	nm.roughness = 0.2
	gem.material = nm
	_nitro_mm = _mm(gem, MAX_NITRO)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.88
	ring.outer_radius = 1.02
	ring.rings = 18
	ring.ring_segments = 6
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.44, 0.84, 1.0, 0.8)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring.material = rm
	_ring_mm = _mm(ring, MAX_NITRO)


func _mm(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 100000.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mmi)
	return mm


func reset(at_s: float) -> void:
	coins.clear()
	nitros.clear()
	_next_coin = at_s + 70.0
	_next_nitro = at_s + 380.0
	render_items()


func _spawn_coin_line(at_s: float) -> void:
	var n := 6 + randi_range(0, 4)
	var l1 := randi_range(0, 3)
	var l2 := l1
	if randf() < 0.45:
		l2 = clampi(l1 + (-1 if randf() < 0.5 else 1), 0, 3)
	for i in n:
		var t := clampf((i - n / 3.0) / (n / 3.0), 0.0, 1.0)
		var k := t * t * (3.0 - 2.0 * t)
		coins.append(Vector2(at_s + i * 6.0, lerpf(Track.LANES[l1], Track.LANES[l2], k)))


func world_pos(item: Vector2, y: float) -> Vector3:
	return Track.point(item.x) + Track.right(item.x) * item.y + Vector3(0, y, 0)


func step(dt: float, ps: float, px: float, racing: bool) -> void:
	_time += dt
	var horizon := ps + 400.0
	while _next_coin < horizon:
		_spawn_coin_line(_next_coin)
		_next_coin += 130.0 + randf() * 170.0
	while _next_nitro < horizon:
		nitros.append(Vector2(_next_nitro, Track.LANES[randi_range(0, 3)]))
		_next_nitro += 520.0 + randf() * 480.0

	for i in range(coins.size() - 1, -1, -1):
		var c := coins[i]
		if racing and absf(c.x - ps) < 2.4 and absf(c.y - px) < 1.6:
			coins.remove_at(i)
			coin_collected.emit(world_pos(c, 0.95))
		elif c.x < ps - 10.0:
			coins.remove_at(i)
	for i in range(nitros.size() - 1, -1, -1):
		var c := nitros[i]
		if racing and absf(c.x - ps) < 2.6 and absf(c.y - px) < 1.9:
			nitros.remove_at(i)
			nitro_collected.emit(world_pos(c, 1.2))
		elif c.x < ps - 10.0:
			nitros.remove_at(i)


## Updates the MultiMesh instances (called every frame).
func render_items() -> void:
	var t := _time
	var n := 0
	for c in coins:
		if n >= MAX_COINS:
			break
		var p := world_pos(c, 0.95 + sin(t * 4.0 + c.x) * 0.08)
		# Coin faces along the road, spinning about the vertical axis.
		var b := Basis(Vector3.UP, -Track.heading(c.x) + t * 3.2 + c.x * 0.3) * Basis(Vector3.RIGHT, PI / 2.0)
		_coin_mm.set_instance_transform(n, Transform3D(b, p))
		n += 1
	_coin_mm.visible_instance_count = n

	n = 0
	for c in nitros:
		if n >= MAX_NITRO:
			break
		var p := world_pos(c, 1.2 + sin(t * 3.0 + c.x) * 0.15)
		_nitro_mm.set_instance_transform(n, Transform3D(Basis(Vector3.UP, t * 2.0), p))
		var sc := 1.0 + sin(t * 6.0) * 0.08
		# The torus lies flat by default; stand it up across the road.
		var rb := Basis(Vector3.UP, -Track.heading(c.x)) * Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.UP, t * 1.5)
		_ring_mm.set_instance_transform(n, Transform3D(rb.scaled(Vector3.ONE * sc), p))
		n += 1
	_nitro_mm.visible_instance_count = n
	_ring_mm.visible_instance_count = n
