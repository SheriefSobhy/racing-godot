class_name World
extends Node3D
## Streams the endless highway in 80 m chunks: road and shoulders (with
## collision), guard rails (with collision), terrain, trees, buildings,
## lamps and sign gantries. Also owns the sky, sun and fog.
## Layout and numbers follow racing-3d's world.js.

const CHUNK := 80.0
const AHEAD_HIGH := 560.0
const AHEAD_LOW := 400.0
const PERIOD := 4800.0          # UV wrap period (multiple of every texture tile and of CHUNK)
const ROAD_TILE := 24.0         # the road texture covers 20 m x 24 m
const GRASS_TILE := 7.0
const CONCRETE_TILE := 3.0
const FACADE_TILE := 14.0
const SHOULDER := 12.5
const LAMP_O := 11.7
const GROUND: Array[float] = [12.5, 16.0, 22.0, 32.0, 46.0, 65.0, 90.0, 125.0, 170.0, 240.0]
const SUN_DIR := Vector3(0.553042, 0.743008, 0.376940)   # from racing-3d's sky.json
const HORIZON := Color8(157, 162, 176)

const TEX := "res://assets/textures/"

var high := true
var ahead := AHEAD_HIGH
var env: Environment
var sun: DirectionalLight3D

var _chunks := {}               # chunk index -> Node3D
var _staged_count := 0             # staged chunk builds in progress
var _mats := {}
var _backdrop: MeshInstance3D
var _phys_mat := PhysicsMaterial.new()
var _post_mesh: BoxMesh


func _ready() -> void:
	_phys_mat.friction = 0.25
	_make_materials()
	_make_environment()
	_make_backdrop()


# ---------- Quality ----------

func set_quality(is_high: bool) -> void:
	high = is_high
	ahead = AHEAD_HIGH if high else AHEAD_LOW
	sun.shadow_enabled = high
	env.fog_depth_begin = 140.0 if high else 100.0
	env.fog_depth_end = 620.0 if high else 440.0
	for k in ["road", "concrete", "grass"]:
		var m: StandardMaterial3D = _mats[k]
		m.normal_enabled = high and m.normal_texture != null
	# Trees are built per chunk, so rebuild everything visible.
	for i in _chunks.keys():
		_chunks[i].queue_free()
	_chunks.clear()


# ---------- Materials, sky, light ----------

func _tex(name: String) -> Texture2D:
	return load(TEX + name) as Texture2D


func _mat(albedo: Texture2D, normal: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = albedo
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if normal:
		m.normal_texture = normal
		m.normal_enabled = true
		m.normal_scale = 0.8
	return m


func _make_materials() -> void:
	_mats.road = _mat(_tex("road.webp"), _tex("asphalt_n.webp"))
	_mats.road.roughness = 0.82
	_mats.concrete = _mat(_tex("concrete.webp"), _tex("concrete_n.webp"))
	_mats.grass = _mat(_tex("grass.webp"), _tex("grass_n.webp"))
	_mats.grass.vertex_color_use_as_albedo = true
	var rail := StandardMaterial3D.new()
	rail.albedo_color = Color(0.72, 0.74, 0.77)
	rail.metallic = 0.7
	rail.roughness = 0.35
	rail.vertex_color_use_as_albedo = true
	rail.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats.rail = rail
	var trees := _mat(_tex("trees.webp"))
	trees.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	trees.alpha_scissor_threshold = 0.45
	trees.cull_mode = BaseMaterial3D.CULL_DISABLED
	trees.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	trees.roughness = 1.0
	_mats.trees = trees
	for i in 4:
		_mats["facade%d" % i] = _mat(_tex("facade%d.webp" % i))
	_post_mesh = BoxMesh.new()
	_post_mesh.size = Vector3(0.12, 0.8, 0.12)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.45, 0.47, 0.5)
	pm.metallic = 0.5
	pm.roughness = 0.5
	_post_mesh.material = pm
	var misc := StandardMaterial3D.new()
	misc.vertex_color_use_as_albedo = true
	misc.roughness = 0.7
	_mats.misc = misc


func _make_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/sky/sky.webp")
	sky_mat.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.1
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = HORIZON
	env.fog_light_energy = 1.0
	env.fog_density = 1.0
	env.fog_sky_affect = 0.0
	env.fog_depth_curve = 1.0
	env.fog_depth_begin = 140.0
	env.fog_depth_end = 620.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_bias = 0.05
	sun.shadow_blur = 1.0
	add_child(sun)
	sun.look_at_from_position(SUN_DIR, Vector3.ZERO, Vector3.UP)


## A large ground disc and a ring of distant hills that follow the camera,
## so the land reaches the horizon past the streamed terrain.
func _make_backdrop() -> void:
	var b := MeshBuf.new(false, true)
	var segs := 48
	var c0 := b.v(Vector3.ZERO, Vector2.ZERO, Vector3.UP, Color(0.36, 0.45, 0.27))
	var ring: Array[int] = []
	var hills: Array[int] = []
	for i in segs + 1:
		var a := TAU * i / segs
		var d := Vector3(cos(a), 0.0, sin(a))
		ring.append(b.v(d * 1400.0, Vector2.ZERO, Vector3.UP, Color(0.40, 0.47, 0.33)))
		var hh := 40.0 + 35.0 * (0.5 + 0.5 * sin(a * 5.0 + 1.0) * cos(a * 3.0))
		hills.append(b.v(d * 1350.0 + Vector3(0, hh, 0), Vector2.ZERO, -d, Color(0.47, 0.53, 0.50)))
	for i in segs:
		b.tri(c0, ring[i], ring[i + 1], Vector3.UP)
		b.quad(ring[i], ring[i + 1], hills[i + 1], hills[i], -Vector3(cos(TAU * i / segs), 0, sin(TAU * i / segs)))
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := ArrayMesh.new()
	b.commit(mesh, m)
	_backdrop = MeshInstance3D.new()
	_backdrop.mesh = mesh
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop.extra_cull_margin = 2000.0
	add_child(_backdrop)


## Keeps the backdrop under the camera and the shadowed area around it.
func follow(cam_pos: Vector3, road_y: float) -> void:
	_backdrop.global_position = Vector3(cam_pos.x, road_y - 25.0, cam_pos.z)


# ---------- Streaming ----------

## Keeps chunks from `behind` metres back to `ahead` metres in front of s.
## Builds at most `budget` new chunks per call. With staged=true a chunk is
## built over three frames, so phones don't drop a frame for it.
func update(s: float, behind := 40.0, budget := 1, staged := false) -> void:
	var first := maxi(0, floori((s - behind) / CHUNK))
	var last := floori((s + ahead) / CHUNK)
	for i in _chunks.keys():
		if i < first or i > last:
			_chunks[i].queue_free()
			_chunks.erase(i)
	var cur := maxi(first, floori(s / CHUNK))
	var d := 0
	while budget > 0 and (cur + d <= last or cur - d >= first):
		for i in ([cur] if d == 0 else [cur + d, cur - d]):
			if i < first or i > last or _chunks.has(i) or budget <= 0:
				continue
			if staged and _staged_count > 0:
				return
			_build_chunk(i, staged)
			budget -= 1
		d += 1


func clear() -> void:
	for i in _chunks.keys():
		_chunks[i].queue_free()
	_chunks.clear()


# ---------- Chunk building ----------

func _build_chunk(idx: int, staged := false) -> void:
	var node := Node3D.new()
	_chunks[idx] = node
	add_child(node)
	if staged:
		_staged_count += 1
	var s0 := idx * CHUNK
	var base := floorf(s0 / PERIOD) * PERIOD
	var n := int(CHUNK / Track.DS)
	var origin := Track.point(s0)
	var rng := RandomNumberGenerator.new()
	rng.seed = idx * 7919 + 13

	# Precomputed frames (centre point relative to the chunk origin, right vector).
	var P: Array[Vector3] = []
	var R: Array[Vector3] = []
	var S: Array[float] = []
	for i in n + 1:
		var s := s0 + i * Track.DS
		S.append(s)
		P.append(Track.point(s) - origin)
		R.append(Track.right(s))

	var road := MeshBuf.new()
	var concrete := MeshBuf.new()
	var grass := MeshBuf.new(false, true)
	var rail := MeshBuf.new(false, true)
	var trees := MeshBuf.new()
	var misc := MeshBuf.new(false, true)
	var facades: Array[MeshBuf] = [MeshBuf.new(), MeshBuf.new(), MeshBuf.new(), MeshBuf.new()]
	var faces := PackedVector3Array()
	var rail_boxes := []            # [centre, heading, length]

	# Road surface: one textured strip (lane markings are in the texture).
	for i in n + 1:
		var v := (S[i] - base) / ROAD_TILE
		var l := P[i] - R[i] * Track.ROAD_HALF
		var r := P[i] + R[i] * Track.ROAD_HALF
		road.tangent = R[i]
		road.v(l, Vector2(0, v), Vector3.UP)
		road.v(r, Vector2(1, v), Vector3.UP)
		if i > 0:
			road.quad(2 * i - 2, 2 * i - 1, 2 * i + 1, 2 * i, Vector3.UP)
		# Collision: road plus shoulders as one strip.
		if i > 0:
			var a := P[i - 1] - R[i - 1] * SHOULDER
			var b := P[i - 1] + R[i - 1] * SHOULDER
			var c := P[i] + R[i] * SHOULDER
			var d := P[i] - R[i] * SHOULDER
			faces.append_array([a, b, c, a, c, d])

	# Concrete shoulders and grass terrain as grids on both sides.
	for side: float in [-1.0, 1.0]:
		_grid(concrete, P, R, S, base, side, [Track.ROAD_HALF, SHOULDER], CONCRETE_TILE, false, origin.y)
		_grid(grass, P, R, S, base, side, GROUND, GRASS_TILE, true, origin.y)

	if staged:
		await get_tree().process_frame
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			_staged_count -= 1
			return

	# Guard rails: a steel beam on posts along both edges, with collision walls.
	var posts := PackedVector3Array()
	var post_yaw := PackedFloat32Array()
	for side: float in [-1.0, 1.0]:
		var rows: Array[int] = []
		var flip := false
		for i in n + 1:
			var p := P[i] + R[i] * (side * Track.RAIL_O)
			var nrm := -R[i] * side
			var c := Color(0.85, 0.87, 0.9)
			rows.append(rail.v(p + Vector3(0, 0.45, 0), Vector2.ZERO, nrm, c))
			rows.append(rail.v(p + Vector3(0, 0.62, 0) + nrm * 0.06, Vector2.ZERO, nrm, c))
			rows.append(rail.v(p + Vector3(0, 0.80, 0), Vector2.ZERO, nrm, c))
			rows.append(rail.v(p + Vector3(0, 0.84, 0) - nrm * 0.08, Vector2.ZERO, Vector3.UP, c))
			if i > 0:
				var k := (i - 1) * 4
				if i == 1:
					flip = rail.needs_flip(rows[0], rows[4], rows[5], nrm)
				for j in 3:
					rail.quad_w(rows[k + j], rows[k + 4 + j], rows[k + 5 + j], rows[k + j + 1], flip)
			# Collision: solid 1 m thick boxes, 10 m long, so a car sliding
			# sideways at speed is pushed back onto the road, never through.
			if i > 0 and i % 5 == 0:
				var a := P[i - 5] + R[i - 5] * (side * (Track.RAIL_O + 0.5))
				var b := P[i] + R[i] * (side * (Track.RAIL_O + 0.5))
				rail_boxes.append([(a + b) * 0.5 + Vector3(0, 0.9, 0), Track.heading((S[i - 5] + S[i]) * 0.5), a.distance_to(b) + 0.4])
			# Posts every 4 m.
			if i % 2 == 0:
				posts.append(P[i] + R[i] * (side * (Track.RAIL_O + 0.12)) + Vector3(0, 0.38, 0))
				post_yaw.append(-Track.heading(S[i]))

	# Street lamps every 40 m, alternating sides; the arm reaches over the road.
	for k in int(CHUNK / 40.0):
		var i := int(k * 40.0 / Track.DS)
		var side := 1.0 if (idx * 2 + k) % 2 == 0 else -1.0
		var th := Track.heading(S[i])
		var base_p := P[i] + R[i] * (side * LAMP_O)
		var grey := Color(0.5, 0.52, 0.55)
		misc.box(base_p + Vector3(0, 4.0, 0), Vector3(0.22, 8.0, 0.22), th, grey)
		misc.box(base_p - R[i] * side * 1.3 + Vector3(0, 7.95, 0), Vector3(2.6, 0.14, 0.14), th, grey)
		misc.box(base_p - R[i] * side * 2.6 + Vector3(0, 7.85, 0), Vector3(0.9, 0.16, 0.4), th, Color(0.95, 0.93, 0.8))

	# City zones: buildings come and go with a slow wave along the road.
	var city := sin(s0 / 700.0 + 1.5)
	var is_city := city > 0.3
	if is_city:
		for side: float in [-1.0, 1.0]:
			var count := 3 + rng.randi_range(0, 2)
			for k in count:
				var s := s0 + (k + 0.5) / count * CHUNK
				var w := 10.0 + rng.randf() * (CHUNK / count - 11.0)
				var d := 10.0 + rng.randf() * 12.0
				var h := 12.0 + rng.randf() * 45.0 * city
				var o := side * (36.0 + d / 2.0 + rng.randf() * 60.0)
				_building(facades[rng.randi_range(0, 3)], concrete, origin, s, o, w, d, h, rng)

	# Trees: crossed billboard cards from the tree atlas.
	var tree_count := roundi((8 if is_city else 30) * (1.0 if high else 0.6))
	for k in tree_count:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var o := side * (16.0 + pow(rng.randf(), 1.4) * (16.0 if is_city else 140.0))
		var s := s0 + rng.randf() * CHUNK
		var p := Track.point(s) + Track.right(s) * o - origin
		p.y = Track.ground_y(s, o) - 0.1 - origin.y
		var sc := 0.8 + rng.randf() * 0.7
		if rng.randf() < 0.55:
			_pine(trees, p, sc, rng.randf() * PI)
		else:
			_leafy(trees, p, sc, rng.randf() * PI)

	# Overhead sign gantry every 800 m.
	if idx % 10 == 5:
		var i := n / 2
		var th := Track.heading(S[i])
		var gantry := Color(0.55, 0.58, 0.61)
		for o: float in [-11.5, 11.5]:
			misc.box(P[i] + R[i] * o + Vector3(0, 3.55, 0), Vector3(0.45, 7.2, 0.45), th, gantry)
		misc.box(P[i] + Vector3(0, 6.6, 0), Vector3(23.4, 0.6, 0.6), th, gantry)
		for sg in [[-4.6, Color(0.11, 0.48, 0.26)], [4.6, Color(0.12, 0.37, 0.68)]]:
			var o: float = sg[0]
			misc.box(P[i] + R[i] * o + Vector3(0, 4.5, 0), Vector3(7.6, 2.3, 0.22), th, sg[1])
			misc.box(P[i] + R[i] * o + Vector3(0, 5.5, 0) + Track.forward_flat(S[i]) * -0.05, Vector3(5.8, 0.28, 0.3), th, Color.WHITE)
			misc.box(P[i] + R[i] * (o - 2.2) + Vector3(0, 4.85, 0) + Track.forward_flat(S[i]) * -0.05, Vector3(1.4, 0.4, 0.3), th, Color.WHITE)

	# Assemble: one mesh with a surface per material, one static body.
	if staged:
		await get_tree().process_frame
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			_staged_count -= 1
			return
	node.position = origin
	var mesh := ArrayMesh.new()
	road.commit(mesh, _mats.road)
	concrete.commit(mesh, _mats.concrete)
	grass.commit(mesh, _mats.grass)
	rail.commit(mesh, _mats.rail)
	trees.commit(mesh, _mats.trees)
	misc.commit(mesh, _mats.misc)
	for i in 4:
		facades[i].commit(mesh, _mats["facade%d" % i])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	node.add_child(mi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _post_mesh
	mm.instance_count = posts.size()
	for i in posts.size():
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, post_yaw[i]), posts[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mmi)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.physics_material_override = _phys_mat
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	for rb in rail_boxes:
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.0, 3.0, rb[2])
		var rcs := CollisionShape3D.new()
		rcs.shape = bs
		rcs.transform = Transform3D(Basis(Vector3.UP, -float(rb[1])), rb[0])
		body.add_child(rcs)
	node.add_child(body)
	if staged:
		_staged_count -= 1


## A grid strip on one side of the road at the given offsets: the concrete
## shoulder (flat) or the grass terrain (hills, tinted vertex colours).
func _grid(buf: MeshBuf, P: Array[Vector3], R: Array[Vector3], S: Array[float], base: float, side: float,
		offs: Array, tile: float, grass: bool, origin_y: float) -> void:
	var start := buf.count()
	var w := offs.size()
	var flip := false
	for i in P.size():
		var si := S[i]
		var v := (si - base) / tile
		var r := R[i]
		var pc := P[i]
		var h := Track.height(si) - 0.05 - origin_y
		buf.tangent = r
		for o0: float in offs:
			var o := side * o0
			var p := pc + r * o
			var col := Color.WHITE
			if grass:
				# Track.ground_y, inlined.
				var y := h
				if o0 > 16.0:
					var kk := minf(1.0, (o0 - 16.0) / 140.0)
					y += kk * kk * 30.0 * (0.5 + 0.5 * sin(si * 0.011 + o * 0.023) * cos(si * 0.007 - o * 0.017))
				p.y = y
				var t := 0.5 + 0.5 * sin(si * 0.013 + o * 0.05) * cos(si * 0.007 - o * 0.031)
				col = Color(0.42 + t * 0.1, 0.62 + t * 0.08, 0.3 + t * 0.06)
			else:
				p.y = pc.y - 0.02
			buf.v(p, Vector2(o / tile, v), Vector3.UP, col)
		if i > 0:
			if i == 1:
				flip = buf.needs_flip(start, start + 1, start + w + 1, Vector3.UP)
			for k in w - 1:
				var a := start + (i - 1) * w + k
				buf.quad_w(a, a + 1, start + i * w + k + 1, start + i * w + k, flip)


func _building(fb: MeshBuf, roof: MeshBuf, origin: Vector3, s: float, o: float, w: float, d: float, h: float,
		rng: RandomNumberGenerator) -> void:
	var c := Track.point(s) + Track.right(s) * o - origin
	var y0 := Track.ground_y(s, o) - 2.0 - origin.y
	var y1 := y0 + h + 2.0
	var th := Track.heading(s) + (rng.randf() - 0.5) * 0.1
	var ax := Vector3(cos(th), 0, sin(th))       # across the road
	var az := Vector3(sin(th), 0, -cos(th))      # along the road
	var hw := d / 2.0
	var hl := w / 2.0
	var corners: Array[Vector3] = [c - ax * hw - az * hl, c + ax * hw - az * hl, c + ax * hw + az * hl, c - ax * hw + az * hl]
	var lens: Array[float] = [d, w, d, w]
	var u := rng.randf() * 4.0
	var vt := (y1 - y0) / FACADE_TILE
	for k in 4:
		var a := corners[k]
		var b := corners[(k + 1) % 4]
		var nrm := (a + b) * 0.5 - c
		nrm.y = 0
		nrm = nrm.normalized()
		var ua := u / FACADE_TILE
		var ub := (u + lens[k]) / FACADE_TILE
		var i0 := fb.v(Vector3(a.x, y0, a.z), Vector2(ua, vt), nrm)
		var i1 := fb.v(Vector3(b.x, y0, b.z), Vector2(ub, vt), nrm)
		var i2 := fb.v(Vector3(b.x, y1, b.z), Vector2(ub, 0), nrm)
		var i3 := fb.v(Vector3(a.x, y1, a.z), Vector2(ua, 0), nrm)
		fb.quad(i0, i1, i2, i3, nrm)
		u += lens[k]
	var r: Array[int] = []
	for cc in corners:
		roof.tangent = Vector3.RIGHT
		r.append(roof.v(Vector3(cc.x, y1, cc.z), Vector2(cc.x, cc.z) / CONCRETE_TILE, Vector3.UP))
	roof.quad(r[0], r[1], r[2], r[3], Vector3.UP)


# ---------- Tree billboards (atlas: left half pine, right-top crown, right-bottom bark) ----------
# UVs are flipped vertically compared with racing-3d (Godot's v runs down).

func _card(buf: MeshBuf, p: Vector3, w: float, h: float, ang: float, u0: float, u1: float, v0: float, v1: float) -> void:
	var dx := Vector3(cos(ang), 0, sin(ang)) * (w / 2.0)
	var a := buf.v(p - dx, Vector2(u0, 1.0 - v0), Vector3.UP)
	var b := buf.v(p + dx, Vector2(u1, 1.0 - v0), Vector3.UP)
	var c := buf.v(p + dx + Vector3(0, h, 0), Vector2(u1, 1.0 - v1), Vector3.UP)
	var d := buf.v(p - dx + Vector3(0, h, 0), Vector2(u0, 1.0 - v1), Vector3.UP)
	buf.quad_raw(a, b, c, d)


func _pine(buf: MeshBuf, p: Vector3, sc: float, rot: float) -> void:
	var h := 13.0 * sc
	_card(buf, p, h * 0.5, h, rot, 0.0, 0.5, 0.0, 1.0)
	_card(buf, p, h * 0.5, h, rot + PI / 2.0, 0.0, 0.5, 0.0, 1.0)


func _leafy(buf: MeshBuf, p: Vector3, sc: float, rot: float) -> void:
	var r := 0.28 * sc
	var th := 4.2 * sc
	var sides := 5
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := p + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := p + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var u0 := 0.5 + float(k) / sides * 0.5
		var u1 := 0.5 + float(k + 1) / sides * 0.5
		var am := (a0 + a1) / 2.0
		var nrm := Vector3(cos(am), 0, sin(am))
		var top0 := p0.lerp(p, 0.3) + Vector3(0, th, 0)
		var top1 := p1.lerp(p, 0.3) + Vector3(0, th, 0)
		var i0 := buf.v(p0, Vector2(u0, 1.0), nrm)
		var i1 := buf.v(p1, Vector2(u1, 1.0), nrm)
		var i2 := buf.v(top1, Vector2(u1, 0.52), nrm)
		var i3 := buf.v(top0, Vector2(u0, 0.52), nrm)
		buf.quad(i0, i1, i2, i3, nrm)
	var cw := 7.5 * sc
	var cy := p + Vector3(0, th - 1.6 * sc, 0)
	for k in 3:
		_card(buf, cy, cw, cw, rot + k * PI / 3.0, 0.5, 1.0, 0.5, 1.0)


## Indexed geometry accumulator. quad() and tri() fix the winding so the
## front face points along the given normal.
class MeshBuf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var tangents := PackedFloat32Array()
	var use_colors := false
	## Set before v() calls to give normal-mapped surfaces a tangent (the
	## direction u grows in). Left at zero, the mesh gets no tangents.
	var tangent := Vector3.ZERO

	func _init(_unused := false, with_colors := false) -> void:
		use_colors = with_colors

	func count() -> int:
		return verts.size()

	func v(p: Vector3, uv: Vector2, n: Vector3, c := Color.WHITE) -> int:
		verts.append(p)
		uvs.append(uv)
		normals.append(n)
		if use_colors:
			colors.append(c)
		if tangent != Vector3.ZERO:
			tangents.append_array([tangent.x, tangent.y, tangent.z, 1.0])
		return verts.size() - 1

	func tri(a: int, b: int, c: int, n: Vector3) -> void:
		# Godot's front faces wind clockwise: front normal = (c - a) x (b - a).
		var fn := (verts[c] - verts[a]).cross(verts[b] - verts[a])
		if fn.dot(n) >= 0.0:
			indices.append_array([a, b, c])
		else:
			indices.append_array([a, c, b])

	func quad(a: int, b: int, c: int, d: int, n: Vector3) -> void:
		tri(a, b, c, n)
		tri(a, c, d, n)

	## True if triangle (a, b, c) faces away from n, so its quads must flip.
	func needs_flip(a: int, b: int, c: int, n: Vector3) -> bool:
		return (verts[c] - verts[a]).cross(verts[b] - verts[a]).dot(n) < 0.0

	## Quad with a winding decided once for a whole strip (see needs_flip).
	func quad_w(a: int, b: int, c: int, d: int, flip: bool) -> void:
		if flip:
			indices.append_array([a, c, b, a, d, c])
		else:
			indices.append_array([a, b, c, a, c, d])

	## Quad with no winding check (for double-sided cards).
	func quad_raw(a: int, b: int, c: int, d: int) -> void:
		indices.append_array([a, b, c, a, c, d])

	## An axis-aligned (yawed by the road heading) box with flat faces.
	func box(center: Vector3, size: Vector3, heading: float, c: Color) -> void:
		var ax := Vector3(cos(heading), 0, sin(heading)) * (size.x / 2.0)
		var ay := Vector3(0, size.y / 2.0, 0)
		var az := Vector3(sin(heading), 0, -cos(heading)) * (size.z / 2.0)
		for f in [[ax, ay, az], [-ax, ay, az], [ay, ax, az], [-ay, ax, az], [az, ax, ay], [-az, ax, ay]]:
			var nv: Vector3 = f[0]
			var u: Vector3 = f[1]
			var w: Vector3 = f[2]
			var nn := nv.normalized()
			var cc := center + nv
			var i0 := v(cc - u - w, Vector2.ZERO, nn, c)
			var i1 := v(cc + u - w, Vector2.ZERO, nn, c)
			var i2 := v(cc + u + w, Vector2.ZERO, nn, c)
			var i3 := v(cc - u + w, Vector2.ZERO, nn, c)
			quad(i0, i1, i2, i3, nn)

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if indices.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_TEX_UV] = uvs
		if use_colors:
			arr[Mesh.ARRAY_COLOR] = colors
		if tangents.size() == verts.size() * 4:
			arr[Mesh.ARRAY_TANGENT] = tangents
		arr[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
