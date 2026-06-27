class_name WaveSpawner
extends Node3D
## Spawns waves of imps scattered across the island. Wave 1 = 15 imps; each cleared
## wave doubles the next and raises per-imp HP by HP_PER_WAVE. Imps don't all appear
## at once — they portal in one at a
## time, and the gap between spawns shrinks each wave (later waves materialize
## faster). Each imp arrives frozen in a spawn portal for EMERGE_TIME before it
## starts hunting. Imps register themselves in the "imps" group, so nothing else
## needs a direct reference to them.

signal imp_spawned(imp: Node)    # each portalled-in imp (Main binds it to the XP-orb field)
signal wave_started(wave: int)   # a new wave began (Main resets the HUD level-up stack)
signal wave_cleared()            # drip done & 0 imps left (Main vacuums leftover XP orbs)

const ImpScript := preload("res://src/enemies/imp.gd")
const PortalScript := preload("res://src/fx/portal.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")
const ObstacleFieldScript := preload("res://src/world/obstacle_field.gd")

const WAVE_1_COUNT := 15
const HP_PER_WAVE := 3.0         # imp HP added per wave (pistol dmg 5: w1=1 shot, w2-3=2 shots, w4-5=3...)
const ATTACK_DMG_PER_WAVE := 1.0 # imp melee damage added per wave (wave 1 = 1, wave 2 = 2, ...)
const XP_PER_WAVE := 1.0         # imp XP value added per wave (tougher imps worth more)
const WAVE_DELAY := 5.0          # pause after a wave is cleared
const SPAWN_MARGIN := 2.0        # keep spawns inside the coast
const MIN_FROM_CENTER := 6.0     # don't spawn on top of the player (spawns at centre)
const EMERGE_TIME := 1.0         # seconds an imp stays frozen in its portal

const SPAWN_INTERVAL_1 := 0.6    # seconds between spawns in wave 1
const SPAWN_SPEEDUP := 0.8       # interval ×= this each wave -> later waves spawn faster
const SPAWN_INTERVAL_MIN := 0.1  # floor so high waves don't all pop at once

# Power scaling: the player's equipped loadout power makes the next wave bigger and
# its imps tougher (absolute factor — see Inventory.loadout_power). Read once per
# wave so mid-wave equip changes don't retroactively spike the live wave.
const POWER_BASELINE := 20.0     # two starting level-1 pistols -> factor 1.0 (no change)
const POWER_FACTOR_CAP := 6.0    # clamp so a runaway loadout can't make waves explode
const COUNT_POWER_WEIGHT := 0.6  # how much power inflates the imp count (0 = none, 1 = full factor)
const STAT_POWER_WEIGHT := 0.5   # how much power inflates per-imp HP + damage
# Types (hook, not built this PR — only one imp model exists): once variants land,
# gate them by factor — e.g. factor > 1.4 -> some "brute" imps (×2 HP/size),
# factor > 2.0 -> fast imps. See _variant_for().

var player: Node3D
var inventory: Node              # Inventory (set by Main); read for loadout power. null -> factor 1.0
var obstacles: ObstacleFieldScript   # island columns/lava/rocks (set by Main); handed to each imp
var _power_factor := 1.0         # loadout-power factor for the current wave (read at _start_wave)
var _rng := RandomNumberGenerator.new()
var _wave := 0                   # wave number (1,2,3…), drives the spawn interval
var _wave_count := WAVE_1_COUNT  # doubles each cleared wave: 15 -> 30 -> 60 ...
var _to_spawn := 0               # imps left to portal in this wave
var _spawn_interval := SPAWN_INTERVAL_1
var _spawn_timer := 0.0
var _between := false
var _between_timer := 0.0


func _ready() -> void:
	_rng.seed = 1337
	_start_wave(WAVE_1_COUNT)


func _process(delta: float) -> void:
	if _between:
		_between_timer -= delta
		if _between_timer <= 0.0:
			_between = false
			_start_wave(_wave_count * 2)
		return

	# Drip the wave in one imp at a time on the wave's interval.
	if _to_spawn > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_one()
			_to_spawn -= 1
			_spawn_timer = _spawn_interval
		return

	# Whole wave is out and the field is clear -> pause, then the next wave.
	if _alive() == 0:
		_between = true
		_between_timer = WAVE_DELAY
		wave_cleared.emit()


## Begin spawning a wave of `count` imps; each wave drips faster than the last.
## `count` is the unscaled baseline (kept for the doubling sequence); the loadout
## power factor inflates how many actually spawn.
func _start_wave(count: int) -> void:
	_wave += 1
	_wave_count = count          # unscaled baseline -> next wave doubles this
	_power_factor = _read_power_factor()
	_to_spawn = roundi(float(count) * lerpf(1.0, _power_factor, COUNT_POWER_WEIGHT))
	_spawn_interval = maxf(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_1 * pow(SPAWN_SPEEDUP, _wave - 1))
	_spawn_timer = 0.0           # first imp portals in right away
	wave_started.emit(_wave)


## The current loadout's power factor (1.0 at the starting loadout, capped). Stronger
## loadout -> bigger, tougher waves. No inventory (e.g. tests) -> 1.0.
func _read_power_factor() -> float:
	if inventory == null or not inventory.has_method("loadout_power"):
		return 1.0
	return clampf(float(inventory.loadout_power()) / POWER_BASELINE, 1.0, POWER_FACTOR_CAP)


## Forward hook for enemy variants (only one imp type exists today, so this is a no-op).
## Once variants land, pick a type from `pf`: e.g. pf > 1.4 -> chance of a brute,
## pf > 2.0 -> chance of a fast imp.
func _variant_for(_pf: float) -> void:
	pass


## Count of live imps still in the wave.
func _alive() -> int:
	var n := 0
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if is_instance_valid(imp):
			n += 1
	return n


## Portal in one imp: spawn the imp frozen-and-materializing, plus the portal FX.
func _spawn_one() -> void:
	var pt := _scatter_point()
	var imp := ImpScript.new()
	imp.player = player
	imp.obstacles = obstacles
	var stat_mult := lerpf(1.0, _power_factor, STAT_POWER_WEIGHT)   # power makes imps tougher
	imp.max_hp = (ImpScript.BASE_HP + float(_wave - 1) * HP_PER_WAVE) * stat_mult
	imp.hp = imp.max_hp
	imp.attack_damage = (ImpScript.BASE_ATTACK_DAMAGE + float(_wave - 1) * ATTACK_DMG_PER_WAVE) * stat_mult
	imp.xp_value = ImpScript.BASE_XP + float(_wave - 1) * XP_PER_WAVE   # reward tracks wave, not loadout
	imp.position = pt
	add_child(imp)
	imp.emerge(EMERGE_TIME)      # frozen + scaling up while the portal is open

	var portal := PortalScript.new()
	portal.position = pt
	portal.imp = imp             # if this imp dies before emerging, the portal fails
	add_child(portal)
	imp_spawned.emit(imp)


## A random point on the island — inside the coast, away from the centre.
func _scatter_point() -> Vector3:
	for _attempt in 20:
		var ang := _rng.randf_range(0.0, TAU)
		var max_r: float = IslandShape.radius(ang) - SPAWN_MARGIN
		if max_r <= MIN_FROM_CENTER:
			continue
		var r := _rng.randf_range(MIN_FROM_CENTER, max_r)
		var x := cos(ang) * r
		var z := sin(ang) * r
		return Vector3(x, IslandShape.surface_height(x, z), z)
	return Vector3(MIN_FROM_CENTER, IslandShape.surface_height(MIN_FROM_CENTER, 0.0), 0.0)
