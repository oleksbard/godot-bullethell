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
const ExpandableGridScript := preload("res://src/inventory/expandable_grid.gd")
const WeaponCatalogScript := preload("res://src/weapons/weapon_catalog.gd")
const ArtifactResolverScript := preload("res://src/artifacts/artifact_resolver.gd")

# Backpack mask: _OO_ / OOOO / OOOO / OOOO (14 cells).
const BACKPACK_CELLS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(2, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
	Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
]
const STASH_COLS := 8
const STASH_ROWS := 8
const FIELD_COLS := 8
const FIELD_ROWS := 6
const BASE_OFFSET := Vector2i(2, 1)            # centers the 14-cell base in the 8x6 field
const EXPANSION_PRICE_GROWTH := 1.6            # price multiplier per expansion already owned

var backpack: ExpandableGridScript
var stash: InventoryGridScript


## Build the player's starting inventory: two pistols seated in the backpack so both
## start equipped, reproducing the spec layout (_OO_ / XOXX / XOOX / XXOX).
static func build() -> Self:
	var inv := Self.new()
	var base_cells: Array[Vector2i] = []
	for c in BACKPACK_CELLS:
		base_cells.append(c + BASE_OFFSET)
	inv.backpack = ExpandableGridScript.backpack(base_cells, FIELD_COLS, FIELD_ROWS)
	inv.stash = InventoryGridScript.rect(STASH_COLS, STASH_ROWS)
	var left := InventoryItemScript.pistol()            # rot 0, left column + foot
	inv.backpack.place(left, Vector2i(0, 1) + BASE_OFFSET)   # -> (2, 2)
	var right := InventoryItemScript.pistol()
	right.rot = 2                                        # 180° L, right column + head
	inv.backpack.place(right, Vector2i(2, 1) + BASE_OFFSET)  # -> (4, 2)
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


## Total combat power of the equipped guns, including artifact buffs — drives the next wave.
func loadout_power() -> int:
	var mods_by_item: Dictionary = ArtifactResolverScript.resolve(backpack)
	var p := 0.0
	for it in equipped_guns():
		var m: Object = mods_by_item.get(it, null)
		var factor := 1.0
		if m != null:
			factor = m.damage_mul * m.fire_rate_mul        # power ~ DPS = damage × rate
		p += float(it.power()) * factor
	return roundi(p)


## How many expansion items the player owns (placed in the backpack + stored in the
## stash). Drives the shop's escalating expansion price.
func expansion_count() -> int:
	var n: int = backpack.ext_origin.size()
	for it in stash.items_in_reading_order():
		if it.item_type == WeaponDefScript.ItemType.EXPANSION:
			n += 1
	return n


## The current soul price of an expansion of `kind`: base price × growth^owned.
func expansion_price(kind: int) -> int:
	var base_price: int = WeaponCatalogScript.get_def(kind).base_price
	return roundi(float(base_price) * pow(EXPANSION_PRICE_GROWTH, float(expansion_count())))


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
