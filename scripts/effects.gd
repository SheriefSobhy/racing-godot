class_name Effects
extends Node3D
## Tyre smoke, sparks, nitro flames and skid marks.
## Particles are CPUParticles3D (they work the same on the Mobile and the
## Compatibility renderer). Skid marks are one MultiMesh ring buffer of quads.

const SKID_MAX := 700
const SKID_STEP := 0.7          # metres between skid segments

var smoke_tex: Texture2D
var glow_tex: Texture2D

var _bursts: Array[CPUParticles3D] = []
var _burst_i := 0
var _skids: MultiMesh
var _skid_i := 0
var _skid_last := {}            # wheel key -> last mark position (or null)


func _ready() -> void:
	smoke_tex = _radial([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)], [0.0, 0.5, 1.0])
	glow_tex = _radial([Color(1, 1, 1, 1), Color(1, 1, 1, 0.65), Color(1, 1, 1, 0)], [0.0, 0.25, 1.0])
	for i in 6:
		var p := _make_sparks(true)
		add_child(p)
		_bursts.append(p)
	_make_skids()


func _radial(colors: Array, offsets: Array) -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _particle_mat(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.no_depth_test = false
	m.disable_fog = additive
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


## Tyre smoke for one wheel (add it to the car; it emits in world space).
func make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.7
	p.local_coords = false
	p.emitting = false
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = _particle_mat(smoke_tex, false)
	p.mesh = q
	p.direction = Vector3(0, 1, 0)
	p.spread = 40.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0, 0.6, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 3.6))
	curve.max_value = 4.0
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.9, 0.9, 0.9, 0.55), Color(0.85, 0.85, 0.85, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	p.color_ramp = ramp
	return p


func _make_sparks(one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.5
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.local_coords = false
	p.emitting = false
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	q.material = _particle_mat(glow_tex, true)
	p.mesh = q
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -12, 0)
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 1, 0.8, 1), Color(1, 0.65, 0.2, 1), Color(1, 0.3, 0.05, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	p.color_ramp = ramp
	return p


## Continuous sparks (for scraping the guard rail).
func make_scrape_sparks() -> CPUParticles3D:
	var p := _make_sparks(false)
	p.amount = 30
	p.lifetime = 0.35
	return p


## A one-shot burst at a world position.
func burst(at: Vector3, color: Color, count := 14, speed := 6.0, size := 0.22) -> void:
	var p := _bursts[_burst_i]
	_burst_i = (_burst_i + 1) % _bursts.size()
	p.global_position = at
	p.amount = count
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	(p.mesh as QuadMesh).size = Vector2(size, size)
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), color, Color(color.r, color.g, color.b, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	p.color_ramp = ramp
	p.restart()
	p.emitting = true


## Nitro flame: a glowing cone with flickering fire particles.
func make_flame() -> Node3D:
	var root := Node3D.new()
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.2
	cm.height = 1.4
	cm.radial_segments = 8
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	cm.material = m
	cone.mesh = cm
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Point the cone backwards (-Z), with its base at the exhaust.
	cone.rotation = Vector3(-PI / 2.0, 0, 0)
	cone.position = Vector3(0, 0, -0.5)
	cone.name = "Cone"
	root.add_child(cone)
	var inner := MeshInstance3D.new()
	var im := cm.duplicate() as CylinderMesh
	im.bottom_radius = 0.08
	var m2 := m.duplicate() as StandardMaterial3D
	m2.albedo_color = Color(0.55, 0.75, 1.0, 0.9)
	im.material = m2
	inner.mesh = im
	inner.rotation = cone.rotation
	inner.position = Vector3(0, 0, -0.3)
	inner.scale = Vector3(1, 0.6, 1)
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inner)
	var p := CPUParticles3D.new()
	p.name = "Fire"
	p.amount = 24
	p.lifetime = 0.22
	p.local_coords = true
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	q.material = _particle_mat(glow_tex, true)
	p.mesh = q
	p.direction = Vector3(0, 0, -1)
	p.spread = 6.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 8.0
	var fcurve := Curve.new()
	fcurve.add_point(Vector2(0, 1.0))
	fcurve.add_point(Vector2(1, 0.3))
	p.scale_amount_curve = fcurve
	p.gravity = Vector3.ZERO
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 0.9, 0.6, 1), Color(1, 0.45, 0.1, 0.8), Color(0.8, 0.1, 0.0, 0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	p.color_ramp = ramp
	root.add_child(p)
	root.visible = false
	return root


func set_flame(flame: Node3D, on: bool) -> void:
	flame.visible = on
	(flame.get_node("Fire") as CPUParticles3D).emitting = on
	if on:
		var cone := flame.get_node("Cone") as Node3D
		var k := 0.75 + randf() * 0.5
		cone.scale = Vector3(1, k, 1)
		cone.position = Vector3(0, 0, -0.7 * k)


# ---------- Skid marks ----------

func _make_skids() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.05, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	_skids = MultiMesh.new()
	_skids.transform_format = MultiMesh.TRANSFORM_3D
	_skids.mesh = q
	_skids.instance_count = SKID_MAX
	_skids.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _skids
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 100000.0
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mmi)


## Lays a skid mark for a wheel. Pass on=false when it stops sliding.
func skid(key: String, at: Vector3, normal: Vector3, on: bool, width := 0.32) -> void:
	if not on:
		_skid_last[key] = null
		return
	var last: Variant = _skid_last.get(key)
	if last == null:
		_skid_last[key] = at
		return
	var a: Vector3 = last
	var d := at - a
	var l := d.length()
	if l < SKID_STEP:
		return
	if l > 4.0:
		_skid_last[key] = at
		return
	var z := d / l
	var y := normal.normalized()
	var xax := y.cross(z).normalized()
	z = xax.cross(y)
	var b := Basis(xax * width, y, z * (l + 0.05))
	_skids.set_instance_transform(_skid_i, Transform3D(b, (a + at) * 0.5 + y * 0.025))
	_skid_i = (_skid_i + 1) % SKID_MAX
	_skids.visible_instance_count = maxi(_skids.visible_instance_count, _skid_i if _skids.visible_instance_count < SKID_MAX else SKID_MAX)
	if _skid_i == 0:
		_skids.visible_instance_count = SKID_MAX
	_skid_last[key] = at


func clear() -> void:
	_skids.visible_instance_count = 0
	_skid_i = 0
	_skid_last.clear()
	for p in _bursts:
		p.emitting = false
