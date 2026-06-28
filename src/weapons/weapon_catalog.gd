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

# rot-0 grid shapes.
const PISTOL_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2),   # X. / X. / XX
]
const SAWED_OFF_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2),                   # X / X / X (3 tall, 1 wide)
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
	if _defs.is_empty():
		_build()
	return _defs.keys()


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
		"damage": 2.0, "fire_interval": 1.1, "magazine": 2, "reload": 1.6, "range": 8.0,
		"pattern": WeaponDefScript.Pattern.SPREAD, "pellets": 6, "spread_arc": deg_to_rad(34.0),
		"proj_speed": 30.0, "blood_min": 2, "blood_max": 6,
		"body": WeaponDefScript.Body.SAWED_OFF, "barrel_tip": Vector3(0.0, 0.02, -0.32),
		"shot_clips": SAWED_OFF_CLIPS.duplicate(),
	})
