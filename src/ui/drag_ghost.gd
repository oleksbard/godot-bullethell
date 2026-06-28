class_name DragGhost
extends Control
## The item being dragged, drawn following the cursor: a fit tint (green where it
## would drop, red where it won't) behind the item's icon — rotated to its current
## `rot` via GridView's shared draw — or coloured cells when the item has no art.
## Pure view: the WaveMenu sets the item, fit flag, and screen position.

const GridViewScript := preload("res://src/ui/grid_view.gd")

const FIT_OK := Color(0.3, 1.0, 0.3, 0.45)
const FIT_BAD := Color(1.0, 0.3, 0.3, 0.5)
const NO_ART := Color(0.45, 0.55, 0.75, 0.95)
const INSET := 3.0

var item: Object                  # InventoryItem being dragged
var cell_size := GridViewScript.CELL
var fit := false                  # does it fit where it currently hovers?


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixel-art icon
	z_index = 100                                        # above the grids, below the tooltip


## Bind the dragged item and the current cell size, then redraw.
func setup(it: Object, cell_px: int) -> void:
	item = it
	cell_size = cell_px
	queue_redraw()


## Update the fit feedback (cheap no-op if unchanged).
func set_fit(f: bool) -> void:
	if f != fit:
		fit = f
		queue_redraw()


func _draw() -> void:
	if item == null:
		return
	var step := float(cell_size + GridViewScript.GAP)
	var tint := FIT_OK if fit else FIT_BAD
	for c in item.cells():
		draw_rect(Rect2(Vector2(c.x, c.y) * step, Vector2(cell_size, cell_size)), tint)
	var tex := GridViewScript.icon_for(item)
	if tex != null:
		GridViewScript.draw_icon(self, tex, item, Vector2.ZERO, cell_size)
	else:
		var inset := INSET * float(cell_size) / float(GridViewScript.CELL)
		for c in item.cells():
			draw_rect(Rect2(Vector2(c.x, c.y) * step, Vector2(cell_size, cell_size)).grow(-inset), NO_ART)
