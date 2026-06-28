class_name WeaponDef
extends RefCounted
## All per-weapon data, as one immutable struct. The WeaponCatalog builds one per
## weapon and every consumer (InventoryItem, Gun, WeaponRing, GridView, tooltip)
## reads from it instead of branching on a specific kind. Reference via
## `const WeaponDefScript := preload(...)`. Build with WeaponDef.from({...}).

enum ItemType { GUN, ARTIFACT, OTHER }       ## the "Type" tag shown in the tooltip
enum Pattern { SINGLE, SPREAD, BEAM }        ## firing behaviour; BEAM reserved (see Gun._fire)
enum Body { PISTOL, SAWED_OFF }              ## which procedural body Gun builds when model_scene is null

const Self := preload("res://src/weapons/weapon_def.gd")   # cold-load safe self-ref (no global class cache)

# Identity / UI
var name: String = "Item"
var item_type: int = ItemType.GUN
var traits: Array = []                        # extra tooltip pills, e.g. ["Projectile"]
var flavor: String = ""
var cells: Array[Vector2i] = []               # grid footprint (rot-0)
var icon_path: String = ""
var placeholder_color: Color = Color(0.45, 0.55, 0.75, 0.95)

# Base combat stats (level-1 values; InventoryItem applies the shared scaling)
var damage: float = 5.0
var fire_interval: float = 1.7
var magazine: int = 7
var reload: float = 2.0
var range: float = 12.0                        # display-only targeting range (≈ WeaponRing.MAX_RANGE)

# Firing
var pattern: int = Pattern.SINGLE
var pellets: int = 1                           # SPREAD pellet count
var spread_arc: float = 0.0                    # SPREAD total fan angle (radians)

# Projectile
var proj_speed: float = 38.25
var blood_min: int = 1
var blood_max: int = 4

# Audio
var shot_clips: Array = []                     # clip paths; empty -> no sound
var shot_peaks_db: Array = []                  # optional per-clip loudness trims (empty -> none)

# Visual
var model_scene: PackedScene = null            # an imported model; null -> Gun builds the `body` procedural mesh
var body: int = Body.PISTOL                    # which procedural body Gun builds when model_scene is null
var barrel_tip: Vector3 = Vector3(0.0, 0.02, -0.34)


## Build a WeaponDef from a partial dictionary; unset keys keep their defaults.
static func from(d: Dictionary) -> Self:
	var w := Self.new()
	for key in d:
		w.set(key, d[key])
	return w
