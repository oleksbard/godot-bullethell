class_name Inventory
extends Node
## The player's grid inventory: a `backpack` (active/equipped) grid and a `stash`
## (inactive) grid. Source of truth for what's equipped: `equipped_pistols()` are the
## pistols sitting in the backpack, which the WeaponRing turns into the marine's guns.
## Emits `changed` on every placement change. Build it with Inventory.build().

signal changed

const Self := preload("res://src/inventory/inventory.gd")   # cold-load safe self-ref
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const InventoryGridScript := preload("res://src/inventory/inventory_grid.gd")
const WeaponDefScript := preload("res://src/weapons/weapon_def.gd")

# Backpack mask: _OO_ / OOOO / OOOO / OOOO (14 cells).
const BACKPACK_CELLS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(2, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
	Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
]
const STASH_COLS := 8
const STASH_ROWS := 8

var backpack: InventoryGridScript
var stash: InventoryGridScript


## Build the player's starting inventory: two pistols seated in the backpack so both
## start equipped, reproducing the spec layout (_OO_ / XOXX / XOOX / XXOX).
static func build() -> Self:
	var inv := Self.new()
	inv.backpack = InventoryGridScript.from_cells(BACKPACK_CELLS)
	inv.stash = InventoryGridScript.rect(STASH_COLS, STASH_ROWS)
	var left := InventoryItemScript.pistol()            # rot 0, left column + foot
	inv.backpack.place(left, Vector2i(0, 1))
	var right := InventoryItemScript.pistol()
	right.rot = 2                                        # 180° L, right column + head
	inv.backpack.place(right, Vector2i(2, 1))
	return inv


## Weapon items currently in the backpack, in reading order (these are equipped).
func equipped_guns() -> Array:
	var out: Array = []
	for it in backpack.items_in_reading_order():
		if it.item_type == WeaponDefScript.ItemType.GUN:
			out.append(it)
	return out


## Deprecated alias for equipped_guns() (all equipped items are guns today).
func equipped_pistols() -> Array:
	return equipped_guns()


## Total combat power of the equipped (backpack) pistols — drives the next wave.
func loadout_power() -> int:
	var p := 0
	for it in equipped_guns():
		p += it.power()
	return p


## Place `item` in the stash at the first cell (reading order) where it fits; returns
## whether it was placed (false = stash full). Used by the shop on a purchase.
func add_to_stash(item: InventoryItemScript) -> bool:
	var cells: Array = stash.valid.keys()
	cells.sort_custom(func(a, b): return (a.y < b.y) or (a.y == b.y and a.x < b.x))
	for origin in cells:
		if stash.fits(item, origin):
			stash.place(item, origin)
			changed.emit()
			return true
	return false


## Remove `item` from `grid` (e.g. when the player picks it up) and notify listeners.
func pick_up(grid: InventoryGridScript, item: InventoryItemScript) -> void:
	grid.remove(item)
	changed.emit()


## Place `item` at `origin` in `grid` if it fits; returns whether it was placed.
func drop(grid: InventoryGridScript, item: InventoryItemScript, origin: Vector2i) -> bool:
	if not grid.fits(item, origin):
		return false
	grid.place(item, origin)
	changed.emit()
	return true
