class_name ExpandableGrid
extends "res://src/inventory/inventory_grid.gd"
## The backpack grid: a fixed potential FIELD of cells, a permanent BASE of active
## cells, a substrate layer of expansion items that unlock locked cells, and the
## inherited content layer (guns in `occupancy`). `valid` = base ∪ extender cells,
## recomputed on every substrate change, so the inherited gun fits/place keep working
## unchanged. Placement dispatches on item_type: EXPANSION -> substrate, GUN ->
## content. Reference via `const ExpandableGridScript := preload(...)`.

const WeaponDefScript := preload("res://src/weapons/weapon_def.gd")

var field: Dictionary = {}        # Vector2i -> true: the potential cells (e.g. 8x6)
var base: Dictionary = {}         # Vector2i -> true: permanent active cells
var ext_occ: Dictionary = {}      # Vector2i -> expansion InventoryItem (substrate layer)
var ext_origin: Dictionary = {}   # expansion InventoryItem -> Vector2i (its origin)


## A backpack field of `cols` x `rows`, with `base_cells` permanently active.
static func backpack(base_cells: Array, cols: int, rows: int) -> ExpandableGrid:
	var g: ExpandableGrid = load("res://src/inventory/expandable_grid.gd").new()
	for r in rows:
		for c in cols:
			g.field[Vector2i(c, r)] = true
	for cell in base_cells:
		g.base[cell] = true
	g._recompute_valid()
	return g


## valid = base ∪ extender cells. Called after every substrate change.
func _recompute_valid() -> void:
	valid = {}
	for cell in base:
		valid[cell] = true
	for cell in ext_occ:
		valid[cell] = true


func field_cells() -> Array:
	return field.keys()


func locked_cells() -> Array:
	var out: Array = []
	for cell in field:
		if not valid.has(cell):
			out.append(cell)
	return out


func substrate_items() -> Array:
	return ext_origin.keys()


func _is_expansion(item: InventoryItemScript) -> bool:
	return item.item_type == WeaponDefScript.ItemType.EXPANSION


## EXPANSION -> every cell must be in-field and currently locked (rules out overlap
## with base or other extenders); `ignore` is irrelevant since extenders never sit on
## valid cells. GUN -> inherited content fit (valid + free).
func fits(item: InventoryItemScript, origin: Vector2i, ignore: InventoryItemScript = null) -> bool:
	if not _is_expansion(item):
		return super.fits(item, origin, ignore)
	for c in item.cells():
		var cell: Vector2i = origin + c
		if not field.has(cell):
			return false
		if valid.has(cell):
			return false
	return true


func place(item: InventoryItemScript, origin: Vector2i) -> void:
	if not _is_expansion(item):
		super.place(item, origin)
		return
	for c in item.cells():
		ext_occ[origin + c] = item
	ext_origin[item] = origin
	_recompute_valid()


func remove(item: InventoryItemScript) -> void:
	if not ext_origin.has(item):
		super.remove(item)
		return
	for cell in ext_occ.keys():
		if ext_occ[cell] == item:
			ext_occ.erase(cell)
	ext_origin.erase(item)
	_recompute_valid()


## Top item at a cell: the gun if one rests there, else the extender beneath it.
## Returns null if the cell holds neither.
func item_at(cell: Vector2i) -> InventoryItemScript:
	var gun: Variant = occupancy.get(cell)
	if gun != null:
		return gun
	return ext_occ.get(cell)


## The placement origin of `item`: extenders live in `ext_origin`, guns in `origin_of`.
func origin_for(item: InventoryItemScript) -> Vector2i:
	if ext_origin.has(item):
		return ext_origin[item]
	return origin_of.get(item, Vector2i.ZERO)


## A gun is always pickable; an extender only if no gun rests on any of its cells.
func can_pick_up(item: InventoryItemScript) -> bool:
	if not ext_origin.has(item):
		return true
	var origin: Vector2i = ext_origin[item]
	for c in item.cells():
		if occupancy.has(origin + c):
			return false
	return true
