class_name InventoryItem
extends RefCounted
## A grid-inventory item: a shape (set of occupied cells) + a kind + a rotation.
## Shapes are stored normalized (min col/row = 0); cells() returns them rotated
## `rot` quarter-turns clockwise and re-normalized. Generic — only PISTOL exists
## now, but any shape works. The LevelUpMenu renders it; nothing here touches the tree.

enum Kind { PISTOL }

const Self := preload("res://src/inventory/inventory_item.gd")   # cold-load safe self-ref
const PISTOL_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2),   # X. / X. / XX
]

var kind: int = Kind.PISTOL
var base_cells: Array[Vector2i] = []
var rot: int = 0


## A fresh pistol item (rot 0).
static func pistol() -> Self:
	var it := Self.new()
	it.kind = Kind.PISTOL
	it.base_cells = PISTOL_CELLS.duplicate()
	return it


## Occupied cells at the current rotation, normalized so min col/row = 0.
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = base_cells.duplicate()
	for _i in posmod(rot, 4):
		out = _rotate_cw(out)
	return out


## One 90° clockwise step: (c, r) -> (-r, c), then re-normalize to min (0, 0).
static func _rotate_cw(cells_in: Array[Vector2i]) -> Array[Vector2i]:
	var rotated: Array[Vector2i] = []
	for c in cells_in:
		rotated.append(Vector2i(-c.y, c.x))
	return _normalize(rotated)


static func _normalize(cells_in: Array[Vector2i]) -> Array[Vector2i]:
	var min_x := 1 << 30
	var min_y := 1 << 30
	for c in cells_in:
		min_x = mini(min_x, c.x)
		min_y = mini(min_y, c.y)
	var out: Array[Vector2i] = []
	for c in cells_in:
		out.append(Vector2i(c.x - min_x, c.y - min_y))
	return out
