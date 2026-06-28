class_name WeaponCatalog
extends RefCounted
## The data-driven weapon registry: one WeaponDef per weapon, keyed by an int that
## matches InventoryItem.Kind. Adding a weapon = add a Kind enum value + one entry
## here (+ assets). Reference via `const WeaponCatalogScript := preload(...)`.
## Keyed by plain int (not InventoryItem.Kind) so this file has no dependency on
## inventory_item — keeps the preload graph acyclic.

const WeaponDefScript := preload("res://src/weapons/weapon_def.gd")

const PISTOL := 0       # == InventoryItem.Kind.PISTOL (asserted in tests)
const SAWED_OFF := 1    # == InventoryItem.Kind.SAWED_OFF
const EXPAND_1X1 := 2    # == InventoryItem.Kind.EXPAND_1X1
const EXPAND_2X2 := 3    # == InventoryItem.Kind.EXPAND_2X2
const RUNE_OF_WRATH := 4       # == InventoryItem.Kind.RUNE_OF_WRATH
const HELLFIRE_COIL := 5
const QUICKSILVER_SIGIL := 6
const HOARDERS_MARK := 7
const GREATER_WRATH := 8
const CHAIN_SIGIL := 9
const RESONATOR := 10
const CONDUIT := 11
const THE_FURNACE := 12
const THE_SUN := 13

# Artifact tier tables (1 = Common .. 5 = Mythic): first wave each tier can roll,
# the shop roll weight (rarer tiers less likely), and the flat soul price.
const ARTIFACT_TIER_FIRST_WAVE := {1: 1, 2: 3, 3: 6, 4: 10, 5: 15}
const ARTIFACT_TIER_WEIGHT := {1: 100, 2: 60, 3: 30, 4: 12, 5: 4}
const ARTIFACT_TIER_PRICE := {1: 20, 2: 45, 3: 100, 4: 220, 5: 480}
const ARTIFACT_ICON := "res://assets/artifact_00.png"   # shared placeholder art for all artifacts

# rot-0 grid shapes.
const PISTOL_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2),   # X. / X. / XX
]
const SAWED_OFF_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2),                   # X / X / X (3 tall, 1 wide)
]
const EXPAND_1X1_CELLS: Array[Vector2i] = [Vector2i(0, 0)]
const EXPAND_2X2_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),   # XX / XX
]

const PISTOL_CLIPS := [
	"res://sound/pistol_01.mp3", "res://sound/pistol_02.mp3", "res://sound/pistol_03.mp3",
	"res://sound/pistol_04.mp3", "res://sound/pistol_05.mp3",
]
const PISTOL_PEAKS_DB := [-1.0, -4.3, -14.2, -16.6, -20.4]   # measured (see old ShotSfx)
const SAWED_OFF_CLIPS := ["res://sound/sawed-off_01.mp3", "res://sound/sawed-off_02.mp3"]

static var _defs: Dictionary = {}


## The def for `kind` (built once, lazily). Returns the pistol def for unknown kinds
## so a stray kind never crashes a consumer.
static func get_def(kind: int) -> WeaponDefScript:
	if _defs.is_empty():
		_build()
	return _defs.get(kind, _defs[PISTOL])


static func weapon_kinds() -> Array:
	return _kinds_of(WeaponDefScript.ItemType.GUN)


static func expansion_kinds() -> Array:
	return _kinds_of(WeaponDefScript.ItemType.EXPANSION)


static func artifact_kinds() -> Array:
	return _kinds_of(WeaponDefScript.ItemType.ARTIFACT)


static func tier_first_wave(tier: int) -> int:
	return ARTIFACT_TIER_FIRST_WAVE.get(tier, 1)


static func tier_weight(tier: int) -> int:
	return ARTIFACT_TIER_WEIGHT.get(tier, 0)


## Artifact kinds whose tier has unlocked by `wave` (the shop's wave-gated roll pool).
static func kinds_for_wave(wave: int) -> Array:
	var out: Array = []
	for k in artifact_kinds():
		if tier_first_wave(get_def(k).tier) <= wave:
			out.append(k)
	return out


static func _kinds_of(item_type: int) -> Array:
	if _defs.is_empty():
		_build()
	var out: Array = []
	for k in _defs:
		if _defs[k].item_type == item_type:
			out.append(k)
	return out


static func _build() -> void:
	_defs[PISTOL] = WeaponDefScript.from({
		"name": "Pistol",
		"item_type": WeaponDefScript.ItemType.GUN,
		"traits": ["Projectile"],
		"flavor": "Standard-issue sidearm. When the shotgun's empty and the chainsaw's stalled, it's just you, seven rounds, and a very bad attitude.",
		"cells": PISTOL_CELLS.duplicate(),
		"icon_path": "res://art/items/pistol.png",
		"placeholder_color": Color(0.45, 0.55, 0.75, 0.95),
		"damage": 5.0, "fire_interval": 1.7, "magazine": 7, "reload": 2.0, "range": 12.0,
		"pattern": WeaponDefScript.Pattern.SINGLE,
		"proj_speed": 38.25, "blood_min": 1, "blood_max": 4,
		"shot_clips": PISTOL_CLIPS.duplicate(), "shot_peaks_db": PISTOL_PEAKS_DB.duplicate(),
	})
	_defs[SAWED_OFF] = WeaponDefScript.from({
		"name": "Sawed-Off",
		"item_type": WeaponDefScript.ItemType.GUN,
		"traits": ["Projectile"],
		"flavor": "Both barrels, no apologies. Murder up close, useless past spitting distance — reload and pray.",
		"cells": SAWED_OFF_CELLS.duplicate(),
		"icon_path": "res://assets/sawed-off.png",
		"placeholder_color": Color(0.75, 0.5, 0.3, 0.95),
		"damage": 2.0, "fire_interval": 1.1, "magazine": 2, "reload": 1.6, "range": 6.5,
		"base_price": 14,                                     # pricier than the 10-soul default
		"pattern": WeaponDefScript.Pattern.SPREAD, "pellets": 6, "spread_arc": deg_to_rad(34.0),
		"proj_speed": 30.0, "blood_min": 2, "blood_max": 6,
		"body": WeaponDefScript.Body.SAWED_OFF, "barrel_tip": Vector3(0.0, 0.02, -0.32),
		"shot_clips": SAWED_OFF_CLIPS.duplicate(),
	})
	_defs[EXPAND_1X1] = WeaponDefScript.from({
		"name": "Iron Clasp",
		"item_type": WeaponDefScript.ItemType.EXPANSION,
		"traits": [],
		"flavor": "Drop it onto a locked backpack slot to unlock that space for guns. Lift it and move it any time — unless a weapon is resting on top.",
		"cells": EXPAND_1X1_CELLS.duplicate(),
		"icon_path": "res://assets/expand-1x1.png",
		"placeholder_color": Color(0.5, 0.45, 0.45, 0.95),
		"base_price": 15,
	})
	_defs[EXPAND_2X2] = WeaponDefScript.from({
		"name": "Hellforged Plate",
		"item_type": WeaponDefScript.ItemType.EXPANSION,
		"traits": [],
		"flavor": "Drop it onto locked backpack slots to unlock that space for guns. Lift it and move it any time — unless a weapon is resting on top.",
		"cells": EXPAND_2X2_CELLS.duplicate(),
		"icon_path": "res://assets/expand-2x2.png",
		"placeholder_color": Color(0.5, 0.45, 0.45, 0.95),
		"base_price": 55,
	})
	_build_artifacts()


## The 10 Phase-1 artifacts. Each is a 1×1 backpack item (item_type ARTIFACT) whose
## `effect` the ArtifactResolver reads; price/weight/first-wave come from its `tier`.
static func _build_artifacts() -> void:
	var S := WeaponDefScript.Scope
	var ART := Color(0.55, 0.3, 0.7, 0.95)
	var one := [Vector2i(0, 0)] as Array[Vector2i]
	_defs[RUNE_OF_WRATH] = _artifact_def("Rune of Wrath", 1,
		"Anger etched in stone — whatever stands beside it hits harder.", ART, one,
		{"scope": S.ADJACENT, "stat": "damage", "mul": 1.4})
	_defs[HELLFIRE_COIL] = _artifact_def("Hellfire Coil", 2,
		"It never stops winding.", ART, one,
		{"scope": S.ADJACENT, "stat": "fire_rate", "mul": 1.4})
	_defs[QUICKSILVER_SIGIL] = _artifact_def("Quicksilver Sigil", 2,
		"Reloads happen between heartbeats.", ART, one,
		{"scope": S.ADJACENT, "stat": "reload", "mul": 0.6})
	_defs[HOARDERS_MARK] = _artifact_def("Hoarder's Mark", 2,
		"Greed compounds. Surround it and it pays out.", ART, one,
		{"scope": S.ADJACENT, "stat": "damage", "mul_per": 0.12, "per": "adjacent_artifact", "cap": 0.36})
	_defs[GREATER_WRATH] = _artifact_def("Greater Wrath", 3,
		"The Rune, but louder.", ART, one,
		{"scope": S.ADJACENT, "stat": "damage", "mul": 1.7})
	_defs[CHAIN_SIGIL] = _artifact_def("Chain Sigil", 3,
		"Guns in a row egg each other on.", ART, one,
		{"scope": S.ADJACENT, "stat": "fire_rate", "mul_per": 0.10, "per": "adjacent_gun", "cap": 0.30})
	_defs[RESONATOR] = _artifact_def("Resonator", 3,
		"It makes the runes beside it scream louder.", ART, one,
		{"amp": "neighbors", "mul": 1.4})
	_defs[CONDUIT] = _artifact_def("Conduit", 3,
		"Power flows through it to wherever it's needed.", ART, one,
		{"conduit": true})
	_defs[THE_FURNACE] = _artifact_def("The Furnace", 4,
		"It heats the whole arsenal at once.", ART, one,
		{"scope": S.GLOBAL, "stat": "damage", "mul": 1.4})
	_defs[THE_SUN] = _artifact_def("The Sun", 5,
		"A second, smaller hell, carried in the pack.", ART, one,
		{"scope": S.GLOBAL, "stat": "damage", "mul": 1.6})


static func _artifact_def(name: String, tier: int, flavor: String, color: Color,
		one: Array[Vector2i], effect: Dictionary) -> WeaponDefScript:
	return WeaponDefScript.from({
		"name": name, "item_type": WeaponDefScript.ItemType.ARTIFACT, "tier": tier,
		"traits": ["Artifact"], "flavor": flavor,
		"cells": one.duplicate(), "icon_path": ARTIFACT_ICON, "placeholder_color": color,
		"base_price": ARTIFACT_TIER_PRICE[tier], "effect": effect,
	})
