extends SceneTree
## Times world chunk building (GDScript mesh + collision generation).

var w: World

func _initialize() -> void:
	w = World.new()
	root.add_child(w)

func _process(_d: float) -> bool:
	for q in [true, false]:
		w.high = q
		var t0 := Time.get_ticks_usec()
		var n := 20
		for i in n:
			w.call("_build_chunk", 10 + i)
			w.clear()
		print("high=%s avg chunk build: %.1f ms" % [q, (Time.get_ticks_usec() - t0) / 1000.0 / n])
	return true
