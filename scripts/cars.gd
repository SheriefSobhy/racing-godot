class_name Cars
## Player car specs (same stats as racing-3d) and traffic models.
## Models are Kenney's Car Kit (CC0): the front faces +Z, the wheels are
## child meshes named wheel-front-left etc. Speeds are in m/s (x3.6 = km/h).

const MODEL_DIR := "res://assets/models/cars/"
## Kenney's cars are about 2.6 units long; this makes them about 4.5 m.
const SCALE := 1.75

const PLAYER := [
	{"id": "vortex", "name": "VORTEX GT", "price": 0, "model": "race",
		"max_speed": 70.0, "accel": 13.0, "handling": 1.0, "nitro": 1.0},
	{"id": "kestrel", "name": "KESTREL RS", "price": 300, "model": "sedan-sports",
		"max_speed": 74.0, "accel": 15.0, "handling": 1.12, "nitro": 1.05},
	{"id": "solaris", "name": "SOLARIS X", "price": 800, "model": "hatchback-sports",
		"max_speed": 78.0, "accel": 16.0, "handling": 1.05, "nitro": 1.3},
	{"id": "umbra", "name": "UMBRA Z9", "price": 1500, "model": "race-future",
		"max_speed": 84.0, "accel": 18.0, "handling": 1.25, "nitro": 1.3},
]

## Traffic: model, spawn weight, scale and whether it is a slow truck.
const TRAFFIC := [
	{"model": "sedan", "weight": 3.0, "scale": 1.75, "truck": false},
	{"model": "suv", "weight": 2.0, "scale": 1.75, "truck": false},
	{"model": "suv-luxury", "weight": 1.5, "scale": 1.75, "truck": false},
	{"model": "taxi", "weight": 1.0, "scale": 1.75, "truck": false},
	{"model": "van", "weight": 1.5, "scale": 1.85, "truck": true},
	{"model": "truck", "weight": 1.0, "scale": 2.0, "truck": true},
	{"model": "delivery", "weight": 1.0, "scale": 2.0, "truck": true},
]

static var _scenes := {}


static func spec(id: String) -> Dictionary:
	for c in PLAYER:
		if c.id == id:
			return c
	return PLAYER[0]


static func index_of(id: String) -> int:
	for i in PLAYER.size():
		if PLAYER[i].id == id:
			return i
	return 0


## A new instance of a Kenney model (unscaled).
static func instance(model: String) -> Node3D:
	if not _scenes.has(model):
		_scenes[model] = load(MODEL_DIR + model + ".glb")
	return (_scenes[model] as PackedScene).instantiate()


## Size of the body mesh of a model instance, in its own (unscaled) units.
static func body_aabb(root: Node3D) -> AABB:
	var body := root.get_node_or_null("body") as MeshInstance3D
	if body == null:
		return AABB(Vector3(-0.6, 0, -1.3), Vector3(1.2, 0.8, 2.6))
	var a := body.get_aabb()
	a.position += body.position
	return a


## Wheel meshes of a model, keyed by name ("wheel-front-left", ...).
static func wheels(root: Node3D) -> Dictionary:
	var out := {}
	for c in root.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("wheel-"):
			out[String(c.name)] = c
	return out
