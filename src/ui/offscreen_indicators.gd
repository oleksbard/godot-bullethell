extends Control
## Draws arrow markers on the screen border pointing toward any imp that is
## currently off-screen. Add it under a CanvasLayer so it overlays the 3D view.
## Self-contained: reads the active 3D camera + the "imps" group each frame.

const ImpScript := preload("res://src/enemies/imp.gd")

const MARGIN := 30.0                         # inset from the screen edge
const SIZE := 18.0                           # arrow size
const COLOR := Color(1.0, 0.28, 0.12, 0.92)  # hellish red-orange


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
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if not is_instance_valid(imp):
			continue
		var wp: Vector3 = (imp as Node3D).global_position + Vector3(0.0, 0.6, 0.0)
		var behind := cam.is_position_behind(wp)
		var sp := cam.unproject_position(wp)
		if not behind and rect.has_point(sp):
			continue                          # visible on screen — no marker needed
		var dir := sp - center
		if behind:
			dir = -dir                        # mirror points that are behind the camera
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		_draw_arrow(_edge_point(center, dir, rect), dir)


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
