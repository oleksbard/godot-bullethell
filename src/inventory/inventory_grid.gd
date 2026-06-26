class_name InventoryGrid
extends RefCounted
## One inventory grid: a mask of valid cells plus which item occupies each cell.
## Placement is validated against the mask (holes/edges) and current occupancy.
## Pure logic — the LevelUpMenu renders it; nothing here touches the scene tree.

const Self := preload("res://src/inventory/inventory_grid.gd")   # cold-load safe self-ref
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")

var valid: Dictionary = {}        # Vector2i -> true: cells that exist
var occupancy: Dictionary = {}    # Vector2i -> InventoryItem
var origin_of: Dictionary = {}    # InventoryItem -> Vector2i (top-left placement origin)


## A grid whose valid cells are exactly `cells`.
static func from_cells(cells: Array[Vector2i]) -> Self:
	var g := Self.new()
	for c in cells:
		g.valid[c] = true
	return g


## A full rectangular grid, cols x rows, every cell valid.
static func rect(cols: int, rows: int) -> Self:
	var cells: Array[Vector2i] = []
	for r in rows:
		for c in cols:
			cells.append(Vector2i(c, r))
	return from_cells(cells)


## Can `item` sit at `origin`? Every cell must be valid and free (or held by `ignore`).
func fits(item: InventoryItemScript, origin: Vector2i, ignore: InventoryItemScript = null) -> bool:
	for c in item.cells():
		var cell: Vector2i = origin + c
		if not valid.has(cell):
			return false
		var occ: Variant = occupancy.get(cell)
		if occ != null and occ != ignore:
			return false
	return true


func place(item: InventoryItemScript, origin: Vector2i) -> void:
	for c in item.cells():
		occupancy[origin + c] = item
	origin_of[item] = origin


func remove(item: InventoryItemScript) -> void:
	for cell in occupancy.keys():
		if occupancy[cell] == item:
			occupancy.erase(cell)
	origin_of.erase(item)


func item_at(cell: Vector2i) -> InventoryItemScript:
	return occupancy.get(cell)


## Distinct placed items in row-major reading order (top->bottom, left->right).
func items_in_reading_order() -> Array:
	var ordered: Array = valid.keys()
	ordered.sort_custom(func(a, b): return (a.y < b.y) or (a.y == b.y and a.x < b.x))
	var seen: Dictionary = {}
	var out: Array = []
	for cell in ordered:
		var it: Variant = occupancy.get(cell)
		if it != null and not seen.has(it):
			seen[it] = true
			out.append(it)
	return out
