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

# Rarity bands — derived from item_level (see rarity()).
const RARITY_NORMAL := "Normal"
const RARITY_RARE := "Rare"
const RARITY_UNIQUE := "Unique"
const RARITY_LEGENDARY := "Legendary"

# Level scaling (all tunable). Stats grow with item_level; power is normalized so a
# level-1 pistol = POWER_BASE. The roll is biased toward low levels with a falloff
# that flattens as rarity_bonus rises (the "Increased Rarity" strategy).
const DMG_PER_LEVEL := 0.4              # +40% base damage per level
const FIRE_SPEEDUP_PER_LEVEL := 0.05   # -5% fire interval per level
const FIRE_INTERVAL_MIN := 0.6         # floor so high levels don't fire absurdly fast
const POWER_BASE := 10.0               # a level-1 pistol's power
const MAX_ITEM_LEVEL := 8
const RARITY_FALLOFF_BASE := 0.45      # weight ratio between adjacent levels (rarity_bonus 0)
const RARITY_FALLOFF_MAX := 0.95

var kind: int = Kind.PISTOL
var item_type: int = ItemType.GUN
var item_level: int = 1                # rolled level; rarity + stats + power derive from it
var base_cells: Array[Vector2i] = []
var rot: int = 0


## A fresh level-1 pistol item (rot 0). Used for the starting loadout + tests.
static func pistol() -> Self:
	var it := Self.new()
	it.kind = Kind.PISTOL
	it.base_cells = PISTOL_CELLS.duplicate()
	return it


## A shop-rolled pistol: its level is rolled from the Increased-Rarity curve, which
## widens its reach as the player levels up and as rarity_bonus rises.
static func rolled_pistol(player_level: int, rarity_bonus: float, rng: RandomNumberGenerator) -> Self:
	var it := pistol()
	it.item_level = roll_level(player_level, rarity_bonus, rng)
	return it


## Roll an item level in 1..max_level, biased toward 1. max_level grows with the
## player's level (no Legendary at level 1); rarity_bonus flattens the bias upward.
## Pure + deterministic given `rng` — unit-testable.
static func roll_level(player_level: int, rarity_bonus: float, rng: RandomNumberGenerator) -> int:
	var max_level := clampi(1 + (player_level - 1) / 2, 1, MAX_ITEM_LEVEL)
	if max_level <= 1:
		return 1
	var falloff := clampf(RARITY_FALLOFF_BASE + rarity_bonus, 0.0, RARITY_FALLOFF_MAX)
	var weights: Array[float] = []
	var total := 0.0
	for i in max_level:                # i = 0..max_level-1 maps to level i+1
		var w: float = pow(falloff, float(i))
		weights.append(w)
		total += w
	var pick := rng.randf() * total
	var acc := 0.0
	for i in max_level:
		acc += weights[i]
		if pick <= acc:
			return i + 1
	return max_level


# --- tooltip metadata (generic; the ItemTooltip reads these and knows no kinds) ---

## Display name for the tooltip header.
func display_name() -> String:
	match kind:
		Kind.PISTOL: return "Pistol"
	return "Item"


## Rarity tier (Normal | Rare | Unique | Legendary), banded from the item level.
func rarity() -> String:
	if item_level >= 6:
		return RARITY_LEGENDARY
	if item_level >= 4:
		return RARITY_UNIQUE
	if item_level >= 2:
		return RARITY_RARE
	return RARITY_NORMAL


## Item level (the rolled value). Drives rarity, stats, and power.
func level() -> int:
	return item_level


## Level-scaled bolt damage (pistol). Level 1 = the gun's base damage.
func damage_value() -> float:
	return roundf(GunScript.DAMAGE * (1.0 + DMG_PER_LEVEL * float(item_level - 1)))


## Level-scaled fire interval (pistol): faster at higher levels, floored.
func fire_interval_value() -> float:
	return maxf(FIRE_INTERVAL_MIN,
		GunScript.FIRE_INTERVAL * (1.0 - FIRE_SPEEDUP_PER_LEVEL * float(item_level - 1)))


## Combat-value score, normalized so a level-1 pistol = POWER_BASE (10). Scales with
## DPS (damage × shots/sec). The level-up menu sums this over equipped items.
func power() -> int:
	var base_dps := GunScript.DAMAGE * 60.0 / GunScript.FIRE_INTERVAL
	var dps := damage_value() * 60.0 / fire_interval_value()
	return roundi(POWER_BASE * dps / base_dps)


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
				["Damage", roundi(damage_value())],                  # real: the bolt's damage (level-scaled)
				["Rate of Fire", roundi(60.0 / fire_interval_value())],  # real: shots/min (level-scaled)
				["Power", power()],                                  # normalized combat value (level-1 pistol = 10)
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
