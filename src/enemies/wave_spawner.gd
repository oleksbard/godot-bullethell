class_name WaveSpawner
extends Node3D
## Spawns waves of imps scattered across the island. Wave 1 = 32 imps; each later
## wave grows ~×WAVE_GROWTH and raises per-imp HP by HP_PER_WAVE. Imps don't all appear
## at once — they portal in one at a
## time, and the gap between spawns shrinks each wave (later waves materialize
## faster). Each imp arrives frozen in a spawn portal for EMERGE_TIME before it
## starts hunting. Imps register themselves in the "imps" group, so nothing else
## needs a direct reference to them.

signal imp_spawned(imp: Node)    # each portalled-in imp (Main binds it to the XP-orb field)
signal wave_started(wave: int)   # a new wave began (Main resets the HUD level-up stack)
signal wave_cleared()            # drip done & 0 imps left (Main banks uncollected souls to the vault)

const ImpScript := preload("res://src/enemies/imp.gd")
const ZombieScript := preload("res://src/enemies/zombie.gd")
const LeapCoordinatorScript := preload("res://src/enemies/leap_coordinator.gd")
const BuffCoordinatorScript := preload("res://src/enemies/buff_coordinator.gd")
const PortalScript := preload("res://src/fx/portal.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")
const ObstacleFieldScript := preload("res://src/world/obstacle_field.gd")

const WAVE_1_COUNT := 32
const COUNT_STEP := 6            # imps added per wave (linear), so the count climbs gently, not ×2
const COUNT_CAP := 90            # baseline-count plateau so the field never floods (power + horde stack on top)
const HP_PER_WAVE := 2.0         # imp HP added per wave (pistol dmg 5; gentler slope so kills don't lag the player)
const ATTACK_DMG_PER_WAVE := 0.5 # imp melee damage added per wave (w1=1, w5=3, w10=5.5 — survivable vs the fixed 60 HP marine)
const XP_PER_WAVE := 1.0         # imp XP value added per wave (tougher imps worth more)
const WAVE_DELAY := 1.5          # brief breather after the wave menu closes before the next wave drips in

# Milestone rhythm: difficulty rides on more than raw count. Every HORDE_EVERY wave is a
# denser, faster rush; every ELITE_EVERY wave seeds a few champion imps (mini-bosses).
const HORDE_EVERY := 5           # every 5th wave is a horde
const HORDE_COUNT_MULT := 1.5    # horde waves spawn this much more
const HORDE_PACE := 0.6          # horde waves drip this much faster (spawn interval ×=)
const ELITE_EVERY := 10          # every 10th wave seeds champion imps
const CHAMP_HP_MULT := 4.0       # champion: this much tankier
const CHAMP_SIZE_MULT := 1.6     # champion: this much bigger (body_scale)
const CHAMP_XP_MULT := 3.0       # champion: worth this much more XP
const CHAMP_BONUS_SOULS := 5     # champion: always drops this many extra souls (mini-boss jackpot)

# Soul drops: every imp drops 1 soul; deeper waves give a rising chance of extra souls from
# the *same* imp (re-rolled, so a lucky high-wave kill can cough up several bonus motes).
const SOUL_BONUS_PER_WAVE := 0.05    # extra-soul chance added per wave past the first
const SOUL_BONUS_CHANCE_CAP := 0.5   # ceiling on the per-roll extra-soul chance
const SOUL_BONUS_MAX := 3            # most bonus souls a normal imp can roll
const SPAWN_MARGIN := 2.0        # keep spawns inside the coast
const MIN_FROM_CENTER := 6.0     # don't spawn on top of the player (spawns at centre)
const EMERGE_TIME := 1.0         # seconds an imp stays frozen in its portal

# Zombie mix: a zombie costs ZOMBIE_COST of the wave's point budget (an imp costs 1).
# They appear from wave 2; the eligible share climbs with the wave and is capped so the
# imp horde never fully gives way.
const ZOMBIE_COST := 2
const ZOMBIE_START_WAVE := 2
const ZOMBIE_SHARE_PER_WAVE := 0.06
const ZOMBIE_SHARE_CAP := 0.4
const ZOMBIE_SOUL_BASE := 2          # a zombie drops ~2x an imp's souls (1) before the wave bonus

const SPAWN_INTERVAL_1 := 0.6    # seconds between spawns in wave 1
const SPAWN_SPEEDUP := 0.8       # interval ×= this each wave -> later waves spawn faster
const SPAWN_INTERVAL_MIN := 0.1  # floor so high waves don't all pop at once

# Power scaling: the player's equipped loadout power makes the next wave bigger and
# its imps tougher (absolute factor — see Inventory.loadout_power). Read once per
# wave so mid-wave equip changes don't retroactively spike the live wave.
const POWER_BASELINE := 20.0     # two starting level-1 pistols -> factor 1.0 (no change)
const POWER_FACTOR_CAP := 6.0    # clamp so a runaway loadout can't make waves explode
const COUNT_POWER_WEIGHT := 0.6  # how much power inflates the imp count (0 = none, 1 = full factor)
const STAT_POWER_WEIGHT := 0.25  # how much power inflates per-imp HP + damage (×1.0..×2.25; was 0.5/×3.5 — the player upgrading shouldn't also super-charge imp stats)
# Types: once more variants land, gate them by factor — e.g. factor > 1.4 -> chance of
# a brute imp (×2 HP/size), factor > 2.0 -> chance of a fast imp.

var player: Node3D
var inventory: Node              # Inventory (set by Main); read for loadout power. null -> factor 1.0
var obstacles: ObstacleFieldScript   # island columns/lava/rocks (set by Main); handed to each imp
var _power_factor := 1.0         # loadout-power factor for the current wave (read at _start_wave)
var _rng := RandomNumberGenerator.new()
var _wave := 0                   # wave number (1,2,3…); drives the count, HP, and spawn interval
var _to_spawn := 0               # imps left to portal in this wave
var _champions_left := 0         # elite-wave champions still to spawn (the first N imps of the wave)
var _spawn_interval := SPAWN_INTERVAL_1
var _spawn_timer := 0.0
var _between := false
var _between_timer := 0.0
var _awaiting_next := false      # wave cleared; idle until the wave menu closes (resume_after_menu)


func _ready() -> void:
	_rng.seed = 1337
	# Leap special: one coordinator grants enemy pounces one-at-a-time (global cooldown).
	# It finds enemies by group, so it just needs the player; no per-enemy wiring.
	var leaper := LeapCoordinatorScript.new()
	leaper.player = player
	add_child(leaper)
	# Buff special: one coordinator grants the zombie AoE-haste channel one-at-a-time.
	add_child(BuffCoordinatorScript.new())
	_start_wave()


func _process(delta: float) -> void:
	# Cleared the wave: the menu flow owns the timing now (souls fly in, menu opens, player
	# continues). Idle so the next wave can't start mid-fly-in or while the menu is open.
	if _awaiting_next:
		return

	if _between:
		_between_timer -= delta
		if _between_timer <= 0.0:
			_between = false
			_start_wave()
		return

	# Drip the wave in one enemy at a time on the wave's interval (each spends its points).
	if _to_spawn > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_one()
			_spawn_timer = _spawn_interval
		return

	# Whole wave is out and the field is clear -> hand off to the menu flow.
	if _alive() == 0:
		_awaiting_next = true
		wave_cleared.emit()


## The wave menu has closed (Main wires this to WaveMenu.closed): take a short breather,
## then drip in the next wave.
func resume_after_menu() -> void:
	_awaiting_next = false
	_between = true
	_between_timer = WAVE_DELAY


## Begin the next wave. The baseline count climbs linearly to a plateau (so the field
## never floods); horde waves multiply it and drip faster, elite waves seed champions,
## and the loadout power factor inflates the count further.
func _start_wave() -> void:
	_wave += 1
	_between = false             # cancel any inter-wave breather (direct call or on-timer)
	_power_factor = _read_power_factor()
	var base := mini(COUNT_CAP, WAVE_1_COUNT + COUNT_STEP * (_wave - 1))
	var pace := 1.0
	if _wave % HORDE_EVERY == 0:                              # horde: denser + faster
		base = roundi(float(base) * HORDE_COUNT_MULT)
		pace = HORDE_PACE
	_to_spawn = roundi(float(base) * lerpf(1.0, _power_factor, COUNT_POWER_WEIGHT))
	_champions_left = (_wave / ELITE_EVERY) if _wave % ELITE_EVERY == 0 else 0   # elite: N mini-bosses
	_spawn_interval = maxf(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_1 * pow(SPAWN_SPEEDUP, _wave - 1) * pace)
	_spawn_timer = 0.0           # first imp portals in right away
	wave_started.emit(_wave)


## The current loadout's power factor (1.0 at the starting loadout, capped). Stronger
## loadout -> bigger, tougher waves. No inventory (e.g. tests) -> 1.0.
func _read_power_factor() -> float:
	if inventory == null or not inventory.has_method("loadout_power"):
		return 1.0
	return clampf(float(inventory.loadout_power()) / POWER_BASELINE, 1.0, POWER_FACTOR_CAP)


## Roll how many bonus souls this wave's imp drops. The per-roll chance climbs with the
## wave (capped), and each success re-rolls up to SOUL_BONUS_MAX -> deeper waves cough up
## more extra souls from the same imp. Wave 1 -> 0 chance -> always exactly 1 soul.
func _roll_soul_bonus() -> int:
	var chance := minf(SOUL_BONUS_CHANCE_CAP, float(_wave - 1) * SOUL_BONUS_PER_WAVE)
	var bonus := 0
	while bonus < SOUL_BONUS_MAX and _rng.randf() < chance:
		bonus += 1
	return bonus


## The fraction of a wave's spawn budget eligible to become zombies. Zero before
## ZOMBIE_START_WAVE; climbs with the wave; capped so imps always swarm. Pure (testable).
func _zombie_share(wave: int) -> float:
	if wave < ZOMBIE_START_WAVE:
		return 0.0
	return clampf(float(wave - 1) * ZOMBIE_SHARE_PER_WAVE, 0.0, ZOMBIE_SHARE_CAP)


## Count of live imps still in the wave.
func _alive() -> int:
	var n := 0
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if is_instance_valid(imp):
			n += 1
	return n


## Portal in one enemy: pick imp vs zombie, spawn it frozen-and-materializing with the
## portal FX, and spend its point cost. Champions (elite waves) are always imps and come
## first (while _champions_left > 0), so they spawn before any zombie roll.
func _spawn_one() -> void:
	var pt := _scatter_point()
	var is_champion := _champions_left > 0
	var make_zombie := (not is_champion) and _to_spawn >= ZOMBIE_COST and _rng.randf() < _zombie_share(_wave)

	var enemy: Node3D
	var base_hp: float
	var base_atk: float
	var base_xp: float
	var soul_base: int
	var cost: int
	if make_zombie:
		enemy = ZombieScript.new()
		base_hp = ZombieScript.BASE_HP
		base_atk = ZombieScript.BASE_ATTACK_DAMAGE
		base_xp = ZombieScript.BASE_XP
		soul_base = ZOMBIE_SOUL_BASE
		cost = ZOMBIE_COST
	else:
		enemy = ImpScript.new()
		base_hp = ImpScript.BASE_HP
		base_atk = ImpScript.BASE_ATTACK_DAMAGE
		base_xp = ImpScript.BASE_XP
		soul_base = 1
		cost = 1

	enemy.player = player
	enemy.obstacles = obstacles
	var stat_mult := lerpf(1.0, _power_factor, STAT_POWER_WEIGHT)
	enemy.max_hp = (base_hp + float(_wave - 1) * HP_PER_WAVE) * stat_mult
	enemy.hp = enemy.max_hp
	enemy.attack_damage = (base_atk + float(_wave - 1) * ATTACK_DMG_PER_WAVE) * stat_mult
	enemy.xp_value = base_xp + float(_wave - 1) * XP_PER_WAVE
	enemy.soul_value = soul_base + _roll_soul_bonus()
	if is_champion:                                          # elite-wave mini-boss (imp)
		_champions_left -= 1
		enemy.max_hp *= CHAMP_HP_MULT
		enemy.hp = enemy.max_hp
		enemy.xp_value *= CHAMP_XP_MULT
		enemy.body_scale = CHAMP_SIZE_MULT
		enemy.soul_value += CHAMP_BONUS_SOULS
	enemy.position = pt
	add_child(enemy)
	enemy.emerge(EMERGE_TIME)

	var portal := PortalScript.new()
	portal.position = pt
	portal.imp = enemy                                       # if it dies before emerging, the portal fails
	add_child(portal)
	_to_spawn -= cost
	imp_spawned.emit(enemy)


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
