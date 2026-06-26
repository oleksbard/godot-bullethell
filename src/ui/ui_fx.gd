class_name UiFx
extends Control
## A throwaway expanding-ring "pop" for UI feedback (item pickup/drop). It grows and
## fades, then frees itself. Runs while the tree is paused (the level-up menu pauses
## the game), so it's safe to spawn from the menu.

const Self := preload("res://src/ui/ui_fx.gd")   # cold-load safe self-ref

const DURATION := 0.4

var _radius := 8.0
var _color := Color.WHITE
var _width := 4.0


## Spawn a ring centred at `center` (in `parent`'s local space) growing to `max_radius`.
static func ring(parent: Control, center: Vector2, color: Color, max_radius: float, width: float = 4.0) -> void:
	var fx: Self = Self.new()
	fx.process_mode = Node.PROCESS_MODE_ALWAYS         # animate even though the tree is paused
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.z_index = 90                                    # above grids, below ghost (100) + tooltip (200)
	fx.position = center
	fx._color = color
	fx._width = width
	parent.add_child(fx)
	var tw := fx.create_tween().set_parallel(true)
	tw.tween_method(fx._set_radius, max_radius * 0.25, max_radius, DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(fx, "modulate:a", 0.0, DURATION).from(1.0)
	tw.chain().tween_callback(fx.queue_free)


func _set_radius(r: float) -> void:
	_radius = r
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 64, _color, _width, true)
