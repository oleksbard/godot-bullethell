class_name InventoryItem
extends RefCounted
## A grid-inventory item: a shape (set of occupied cells) + a kind + a rotation.
## Shapes are stored normalized (min col/row = 0); cells() returns them rotated
## `rot` quarter-turns clockwise and re-normalized. All per-weapon data (shape,
## stats, descriptions) lives in the WeaponCatalog, keyed by `kind` — this script
## just applies the shared level-scaling on top and exposes a generic tooltip API.

enum Kind { PISTOL, SAWED_OFF }

const Self := preload("res://src/inventory/inventory_item.gd")   # cold-load safe self-ref
const WeaponCatalogScript := preload("res://src/weapons/weapon_catalog.gd")   # per-weapon data
const WeaponDefScript := preload("res://src/weapons/weapon_def.gd")

# Rarity bands — derived from item_level (see rarity()).
const RARITY_NORMAL := "Normal"
const RARITY_RARE := "Rare"
const RARITY_UNIQUE := "Unique"
const RARITY_LEGENDARY := "Legendary"

# Level scaling (all tunable, shared across weapons). Stats grow with item_level;
# base values come from the weapon's catalog def. Power is normalized so a level-1
# weapon = POWER_BASE. The roll is biased toward low levels with a falloff that
# flattens as rarity_bonus rises (the "Increased Rarity" strategy).
const DMG_PER_LEVEL := 0.4              # +40% base damage per level
const FIRE_SPEEDUP_PER_LEVEL := 0.05   # -5% fire interval per level
const FIRE_INTERVAL_MIN := 0.6         # floor so high levels don't fire absurdly fast
const RELOAD_SPEEDUP_PER_LEVEL := 0.07 # -7% reload time per level (higher level reloads faster)
const RELOAD_MIN := 0.8                # floor so high levels don't reload instantly
const POWER_BASE := 10.0               # a level-1 weapon's power
const BASE_PRICE := 10.0               # souls to buy a level-1 item; price = round(BASE_PRICE * level^PRICE_EXP)
const PRICE_EXP := 1.5
const SELL_FRACTION := 0.65            # an owned item sells back for this fraction of its buy price
const MAX_ITEM_LEVEL := 8
const RARITY_FALLOFF_BASE := 0.45      # weight ratio between adjacent levels (rarity_bonus 0)
const RARITY_FALLOFF_MAX := 0.95

var kind: int = Kind.PISTOL
var item_type: int = WeaponDefScript.ItemType.GUN
var item_level: int = 1                # rolled level; rarity + stats + power derive from it
var base_cells: Array[Vector2i] = []
var rot: int = 0


## The catalog def for this item's kind (single source of per-weapon data).
func _def() -> WeaponDefScript:
	return WeaponCatalogScript.get_def(kind)


## A fresh level-1 item of `kind` (rot 0): shape + type pulled from the catalog.
static func for_kind(k: int) -> Self:
	var it := Self.new()
	it.kind = k
	var def := WeaponCatalogScript.get_def(k)
	it.base_cells = def.cells.duplicate()
	it.item_type = def.item_type
	return it


## A fresh level-1 pistol item (rot 0). Used for the starting loadout + tests.
static func pistol() -> Self:
	return for_kind(Kind.PISTOL)


## A shop-rolled pistol: its level is rolled from the Increased-Rarity curve, which
## widens its reach as the player levels up and as rarity_bonus rises.
static func rolled_pistol(player_level: int, rarity_bonus: float, rng: RandomNumberGenerator) -> Self:
	return rolled_weapon(Kind.PISTOL, player_level, rarity_bonus, rng)


## A shop-rolled item of any weapon `kind`; level rolled from the Increased-Rarity curve.
static func rolled_weapon(k: int, player_level: int, rarity_bonus: float, rng: RandomNumberGenerator) -> Self:
	var it := for_kind(k)
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
	return _def().name


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


## Level-scaled damage. Level 1 = the weapon's base damage from the catalog.
func damage_value() -> float:
	return roundf(_def().damage * (1.0 + DMG_PER_LEVEL * float(item_level - 1)))


## Level-scaled fire interval: faster at higher levels, floored.
func fire_interval_value() -> float:
	return maxf(FIRE_INTERVAL_MIN, _def().fire_interval * (1.0 - FIRE_SPEEDUP_PER_LEVEL * float(item_level - 1)))


## Magazine size — shots fired before the gun must reload.
func magazine_size() -> int:
	return _def().magazine


## Level-scaled reload time (seconds): higher-level guns reload faster, floored.
func reload_time_value() -> float:
	return maxf(RELOAD_MIN, _def().reload * (1.0 - RELOAD_SPEEDUP_PER_LEVEL * float(item_level - 1)))


## Combat-value score, normalized so a level-1 weapon = POWER_BASE (10). Scales with
## DPS (damage × shots/sec). The level-up menu sums this over equipped items.
func power() -> int:
	var def := _def()
	var base_dps := def.damage * 60.0 / def.fire_interval
	var dps := damage_value() * 60.0 / fire_interval_value()
	return roundi(POWER_BASE * dps / base_dps)


## Soul cost to buy this item from the shop (scales with level).
func buy_price() -> int:
	return roundi(BASE_PRICE * pow(float(item_level), PRICE_EXP))


## Souls returned for selling an owned item — SELL_FRACTION of its buy price.
func sell_price() -> int:
	return roundi(float(buy_price()) * SELL_FRACTION)


## The Type tag value: Gun | Artifact | Other.
func type_name() -> String:
	match _def().item_type:
		WeaponDefScript.ItemType.GUN: return "Gun"
		WeaponDefScript.ItemType.ARTIFACT: return "Artifact"
	return "Other"


## Header tags (pills under the rarity/level line): the weapon's traits + its Type.
## Generic — the tooltip renders whatever it gets.
func tags() -> Array:
	var out: Array = _def().traits.duplicate()
	out.append(type_name())
	return out


## Flavour line shown under the stats.
func flavor() -> String:
	return _def().flavor


## Ordered stat lines for the tooltip, built generically from the def + scaled values.
## The ItemTooltip hides false/zero entries, so pattern-specific rows (Pellets/Spread)
## and unimplemented stats (Knockback/Piercing/Ricochet) only show when they apply.
func stats() -> Array:
	var def := _def()
	var rows: Array = [
		["Damage", roundi(damage_value())],
		["Rate of Fire", roundi(60.0 / fire_interval_value())],
		["Reload", reload_time_value()],
		["Range", roundi(def.range)],
		["Magazine", magazine_size()],
	]
	if def.pattern == WeaponDefScript.Pattern.SPREAD:
		rows.append(["Pellets", def.pellets])
		rows.append(["Spread°", roundi(rad_to_deg(def.spread_arc))])
	rows.append_array([
		["Knockback", 0],
		["Piercing", 0],
		["Ricochet", 0],
	])
	return rows


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
