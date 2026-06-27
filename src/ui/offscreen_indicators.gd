extends Control
## Draws markers on the screen border pointing toward off-screen things: red arrows for
## off-screen imps, and a green "+" token for each off-screen health vial. Add it under a
## CanvasLayer so it overlays the 3D view. Self-contained: reads the active 3D camera + the
## "imps" / "health_vials" groups each frame.

const ImpScript := preload("res://src/enemies/imp.gd")
const HealthVialScript := preload("res://src/loot/health_vial.gd")

const MARGIN := 30.0                         # inset from the screen edge
const SIZE := 18.0                           # arrow size
const COLOR := Color(1.0, 0.28, 0.12, 0.92)  # hellish red-orange (imps)
const MAX_MARKERS := 6                       # only arrow the nearest few off-screen imps

const VIAL_COLOR := Color(0.35, 1.0, 0.5, 0.95)  # healing green "+"
const VIAL_ARM := 9.0                        # half-length of each cross arm
const VIAL_THICK := 3.5                      # cross line width


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rect := get_viewport_rect()
	var center := rect.size * 0.5
	var cam_pos := cam.global_position

	# Imps: arrow the nearest few that are off-screen (red, distance-sorted).
	var markers: Array = []                   # off-screen imps: {d, at, dir}
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if not is_instance_valid(imp):
			continue
		var node := imp as Node3D
		var edge: Variant = _offscreen_edge(cam, rect, center, node.global_position + Vector3(0.0, 0.6, 0.0))
		if edge == null:
			continue
		markers.append({
			"d": cam_pos.distance_squared_to(node.global_position),
			"at": edge["at"],
			"dir": edge["dir"],
		})
	markers.sort_custom(func(a, b): return a["d"] < b["d"])
	for i in mini(MAX_MARKERS, markers.size()):
		_draw_arrow(markers[i]["at"], markers[i]["dir"])

	# Health vials: a "+" token at the border for each off-screen vial (capped at 3, draw all).
	for v in get_tree().get_nodes_in_group(HealthVialScript.GROUP):
		if not is_instance_valid(v):
			continue
		var edge: Variant = _offscreen_edge(cam, rect, center, (v as Node3D).global_position + Vector3(0.0, 0.6, 0.0))
		if edge != null:
			_draw_cross(edge["at"])


## Where the ray toward `wp` meets the inset screen rectangle, or null if `wp` is on-screen.
## Returns {at, dir} — the edge point and the unit screen direction toward it.
func _offscreen_edge(cam: Camera3D, rect: Rect2, center: Vector2, wp: Vector3) -> Variant:
	var behind := cam.is_position_behind(wp)
	var sp := cam.unproject_position(wp)
	if not behind and rect.has_point(sp):
		return null                           # visible on screen — no marker needed
	var dir := sp - center
	if behind:
		dir = -dir                            # mirror points that are behind the camera
	if dir.length() < 0.001:
		return null
	dir = dir.normalized()
	return {"at": _edge_point(center, dir, rect), "dir": dir}


## Where the ray from the centre along `dir` meets the inset screen rectangle.
func _edge_point(center: Vector2, dir: Vector2, rect: Rect2) -> Vector2:
	var half := rect.size * 0.5 - Vector2(MARGIN, MARGIN)
	var tx: float = (half.x / absf(dir.x)) if absf(dir.x) > 0.0001 else INF
	var ty: float = (half.y / absf(dir.y)) if absf(dir.y) > 0.0001 else INF
	return center + dir * min(tx, ty)


## A filled triangle pointing along `dir`, centred on `at`.
func _draw_arrow(at: Vector2, dir: Vector2) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var tip := at + dir * SIZE
	var a := at - dir * SIZE * 0.4 + perp * SIZE * 0.6
	var b := at - dir * SIZE * 0.4 - perp * SIZE * 0.6
	draw_colored_polygon(PackedVector2Array([tip, a, b]), COLOR)


## A green "+" centred on `at` — the off-screen health-vial token.
func _draw_cross(at: Vector2) -> void:
	draw_line(at - Vector2(VIAL_ARM, 0.0), at + Vector2(VIAL_ARM, 0.0), VIAL_COLOR, VIAL_THICK)
	draw_line(at - Vector2(0.0, VIAL_ARM), at + Vector2(0.0, VIAL_ARM), VIAL_COLOR, VIAL_THICK)
