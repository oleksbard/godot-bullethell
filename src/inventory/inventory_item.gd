class_name InventoryItem
extends RefCounted
## A grid-inventory item: a shape (set of occupied cells) + a kind + a rotation.
## Shapes are stored normalized (min col/row = 0); cells() returns them rotated
## `rot` quarter-turns clockwise and re-normalized. Generic — only PISTOL exists
## now, but any shape works. The LevelUpMenu renders it; nothing here touches the tree.

enum Kind { PISTOL }
enum ItemType { GUN, ARTIFACT, OTHER }   # the "Type" tag shown in the tooltip header

const Self := preload("res://src/inventory/inventory_item.gd")   # cold-load safe self-ref
const GunScript := preload("res://src/weapons/gun.gd")           # for the pistol's real combat stats
const PISTOL_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2),   # X. / X. / XX
]

const RARITY_NORMAL := "Normal"   # only tier in-game; Rare/Unique/Legendary land with loot

var kind: int = Kind.PISTOL
var item_type: int = ItemType.GUN
var base_cells: Array[Vector2i] = []
var rot: int = 0


## A fresh pistol item (rot 0).
static func pistol() -> Self:
	var it := Self.new()
	it.kind = Kind.PISTOL
	it.base_cells = PISTOL_CELLS.duplicate()
	return it


# --- tooltip metadata (generic; the ItemTooltip reads these and knows no kinds) ---

## Display name for the tooltip header.
func display_name() -> String:
	match kind:
		Kind.PISTOL: return "Pistol"
	return "Item"


## Rarity tier (Normal | Rare | Unique | Legendary). Always Normal for now.
func rarity() -> String:
	return RARITY_NORMAL


## Item level. Not implemented yet — every item is level 1.
func level() -> int:
	return 1


## The Type tag value: Gun | Artifact | Other.
func type_name() -> String:
	match item_type:
		ItemType.GUN: return "Gun"
		ItemType.ARTIFACT: return "Artifact"
	return "Other"


## Header tags (shown as pills under the rarity/level line): the item's Type plus
## any boolean traits (e.g. a projectile weapon is tagged "Projectile"). Generic:
## new kinds return their own list and the tooltip renders whatever it gets.
func tags() -> Array:
	match kind:
		Kind.PISTOL: return ["Projectile", type_name()]
	return [type_name()]


## Flavour line shown under the stats.
func flavor() -> String:
	match kind:
		Kind.PISTOL:
			return "Standard-issue sidearm. When the shotgun's empty and the chainsaw's stalled, it's just you, seven rounds, and a very bad attitude."
	return ""


## Ordered stat lines for the tooltip: each is [label, value]. The ItemTooltip
## hides any false bool or zero number and renders bools as Yes — so a stat that
## isn't implemented (value 0 / false) simply doesn't show. Generic: new kinds
## return their own list and the tooltip needs no changes.
func stats() -> Array:
	match kind:
		Kind.PISTOL:
			return [
				["Damage", GunScript.DAMAGE],                        # real: the bolt's damage
				["Rate of Fire", roundi(60.0 / GunScript.FIRE_INTERVAL)],  # real: shots/min from the fire interval
				["Range", 12],                                       # ponytail: display-only; ~WeaponRing.MAX_RANGE
				["Knockback", 2],                                    # ponytail: display-only; melee/bolt knockback not wired yet
				["Magazine", 7],                                     # not implemented; spec value
				["Piercing", 0],                                     # not implemented (0 -> hidden)
				["Ricochet", 0],                                     # not implemented (0 -> hidden)
			]
	return []


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
