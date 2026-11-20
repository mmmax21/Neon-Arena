extends Node
func _ready() -> void:
	var main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var ar = main.arena
	for id in ar.LAYOUTS:
		var d: Dictionary = ar._layout_data(id)
		var solids: Array = d["pillars"] + d["blocks"]
		var total := 0.0
		var count := 0
		for gx in range(60, 1250, 60):
			for gy in range(60, 690, 60):
				var p := Vector2(gx, gy)
				var nearest := INF
				for v in solids:
					nearest = minf(nearest, p.distance_to(Vector2(v.x, v.y)) - v.z)
				if nearest > 0:
					total += nearest
					count += 1
		print(id, " avg=", total / count)
	get_tree().quit()
