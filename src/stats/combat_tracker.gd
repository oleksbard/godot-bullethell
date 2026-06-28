class_name CombatTracker
extends Node
## Subscribes to combat events and accumulates one wave's stats into a WaveStats.
## Injected by Main and wired to the spawner (wave start/clear, imp spawns), the
## WeaponRing (per-gun shots/hits), and PlayerStats (damage taken). Accumulates only
## while a wave is active; the timer rides _process (frozen with the tree when paused,
## so the between-wave shop doesn't inflate the duration).

const WaveStatsScript := preload("res://src/stats/wave_stats.gd")

var last_wave: WaveStatsScript = null

var _active := false
var _wave := 0
var _elapsed := 0.0
var _damage_dealt := 0.0
var _damage_taken := 0.0
var _souls := 0
var _kills_by_type: Dictionary = {}
var _by_gun: Dictionary = {}          # gun instance -> card dict


## Start a fresh wave: reset every accumulator and the timer.
func begin_wave(n: int) -> void:
	_active = true
	_wave = n
	_elapsed = 0.0
	_damage_dealt = 0.0
	_damage_taken = 0.0
	_souls = 0
	_kills_by_type = {}
	_by_gun = {}


func _process(delta: float) -> void:
	if _active:
		_elapsed += delta


## A bolt left the barrel — count a shot for `gun` (capturing the InventoryItem once
## for the recap's icon/rarity; `item` may be null for a fallback/floating gun).
func record_shot(gun: Object, item: Object) -> void:
	_card_for(gun, item)["shots"] += 1


## A bolt connected — credit `gun` with the damage and, if it was lethal, a kill.
func record_hit(gun: Object, amount: float, killed: bool) -> void:
	_damage_dealt += amount
	var c := _card_for(gun, null)
	c["damage"] += amount
	c["hits"] += 1
	if killed:
		c["kills"] += 1


## Tally a kill by enemy type and the souls it dropped (timing-independent: driven by
## the imp's death, not by when souls are vacuumed).
func record_kill_by_type(type: String, souls: int) -> void:
	_kills_by_type[type] = int(_kills_by_type.get(type, 0)) + 1
	_souls += souls


## Damage the player took (PlayerStats.damaged).
func record_damage_taken(amount: float) -> void:
	if _active:
		_damage_taken += amount


## Hook each spawned imp's death into the kills/souls tally (binds its type label).
func on_imp_spawned(imp: Object) -> void:
	imp.died.connect(_on_imp_died.bind(imp.enemy_type()))


## Finalise the wave: stamp the duration and build last_wave.
func end_wave() -> void:
	last_wave = _build_stats()
	_active = false


## A WaveStats from the CURRENT accumulators (used at death, mid-wave). Non-destructive.
func snapshot() -> WaveStatsScript:
	return _build_stats()


func _on_imp_died(_world_pos: Vector3, _xp: float, soul: int, type: String) -> void:
	if _active:
		record_kill_by_type(type, soul)


## The card for `gun`, creating it on first use. Captures the item + display name once
## (a later record with a non-null item backfills a card first seen via a hit).
func _card_for(gun: Object, item: Object) -> Dictionary:
	if not _by_gun.has(gun):
		var nm := "Gun"
		if item != null:
			nm = item.display_name()
		elif gun.get("def") != null:
			nm = gun.def.name
		_by_gun[gun] = {"item": item, "name": nm, "damage": 0.0, "shots": 0, "hits": 0, "kills": 0}
	elif item != null and _by_gun[gun]["item"] == null:
		_by_gun[gun]["item"] = item
		_by_gun[gun]["name"] = item.display_name()
	return _by_gun[gun]


func _build_stats() -> WaveStatsScript:
	var ws := WaveStatsScript.new()
	ws.wave = _wave
	ws.duration = _elapsed
	ws.damage_dealt = _damage_dealt
	ws.damage_taken = _damage_taken
	ws.souls_earned = _souls
	ws.kills_by_type = _kills_by_type.duplicate()
	var cards: Array = []
	for g in _by_gun:
		cards.append((_by_gun[g] as Dictionary).duplicate())
	ws.guns = cards
	return ws
