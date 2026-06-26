class_name GridView
extends Control
## Renders one InventoryGrid: a dark ember-bordered slot per valid cell and a
## placeholder coloured block per placed item (real item art comes later). Also maps
## a local mouse position to a grid cell so the LevelUpMenu can pick/place. Pure view:
## it reads the grid live and redraws; it never mutates the grid.

const CELL := 44                  # px per cell
const GAP := 2                    # px between cells
const ITEM_INSET := 3.0           # shrink item blocks so the slot grid shows through

const SLOT_BG := Color(0.05, 0.02, 0.02, 0.9)
const SLOT_BORDER := Color(0.62, 0.22, 0.1)
const PISTOL_COLOR := Color(0.45, 0.55, 0.75, 0.95)

var grid: Object                  # InventoryGrid; set via setup()
var cell_size := CELL             # px per cell; raised by the menu to scale the grid up crisply


## Bind a grid and size the control to span it.
func setup(g: Object) -> void:
	grid = g
	custom_minimum_size = _span()
	queue_redraw()


## Re-measure + redraw after the grid's contents change.
func refresh() -> void:
	custom_minimum_size = _span()
	queue_redraw()


## Local pixel position -> grid cell (may be outside the mask; caller checks fits()).
func cell_at(local_pos: Vector2) -> Vector2i:
	var step := cell_size + GAP
	return Vector2i(floori(local_pos.x / step), floori(local_pos.y / step))


## Top-left pixel of a cell (local space).
func cell_origin(cell: Vector2i) -> Vector2:
	return Vector2(cell.x, cell.y) * float(cell_size + GAP)


func _draw() -> void:
	if grid == null:
		return
	var inset := ITEM_INSET * float(cell_size) / float(CELL)   # scale the inset with the cell
	for cell in grid.valid:
		var r := Rect2(cell_origin(cell), Vector2(cell_size, cell_size))
		draw_rect(r, SLOT_BG)
		draw_rect(r, SLOT_BORDER, false, 2.0)
	for item in grid.items_in_reading_order():
		var origin: Vector2i = grid.origin_of[item]
		for c in item.cells():
			var r := Rect2(cell_origin(origin + c), Vector2(cell_size, cell_size)).grow(-inset)
			draw_rect(r, _item_color(item))


func _span() -> Vector2:
	if grid == null:
		return Vector2.ZERO
	var max_c := 0
	var max_r := 0
	for cell in grid.valid:
		max_c = maxi(max_c, cell.x)
		max_r = maxi(max_r, cell.y)
	return Vector2(float(max_c + 1) * (cell_size + GAP), float(max_r + 1) * (cell_size + GAP))


func _item_color(_item: Object) -> Color:
	return PISTOL_COLOR            # only pistols exist now; key on kind later
