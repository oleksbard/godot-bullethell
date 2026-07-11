class_name XpOrbField
extends Node3D
## Owns every live XP orb. Wired by Main: connect WaveSpawner.imp_spawned -> on_imp_spawned
## (so each imp's death drops an orb), and WaveSpawner.wave_cleared -> bank_leftovers (so every
## mote the player DIDN'T collect goes to the soul vault — re-dropped one-per-kill next wave).
## Sits at world origin; orbs are its children.
## ponytail: per-orb nodes + queue_free; pool / MultiMesh only if orb counts ever spike.

signal drained()                 # every leftover mote has drifted off to the vault -> Main opens the wave menu

const XpOrbScript := preload("res://src/loot/xp_orb.gd")

const SCATTER := 0.7              # how far bonus soul-motes scatter out from the corpse (XZ)
const DRAIN_TIMEOUT := 4.0        # safety: drain anyway if an orb somehow can't reach the player

var player: Node3D                # the marine; handed to each spawned orb
var stats: Node                   # PlayerStats — drains the soul vault for bonus drops, banks leftovers
var _rng := RandomNumberGenerator.new()   # seeded -> deterministic bonus-mote scatter
var _draining := false            # waiting for the leftover motes to drift off + the field to empty before the menu opens
var _drain_timer := 0.0


func _ready() -> void:
	_rng.seed = 0x5EED


## While draining (after a wave clear), emit `drained` once every leftover mote has drifted
## off to the vault and freed itself — or after DRAIN_TIMEOUT as a safety net.
func _process(delta: float) -> void:
	if not _draining:
		return
	_drain_timer -= delta
	if get_child_count() == 0 or _drain_timer <= 0.0:
		_draining = false
		drained.emit()


## Bind one imp's death to an orb drop. Connected to WaveSpawner.imp_spawned by Main.
func on_imp_spawned(imp: Node) -> void:
	imp.died.connect(drop_orb)


## Drop the kill's loot (matches Imp.died's arguments): one main orb carrying the XP plus
## one soul, then `soul_value - 1` bonus soul-motes scattered around the corpse (XP already
## paid by the main orb, so the extras carry 0 XP — they're pure souls). Finally, if the
## vault holds any uncollected souls from last wave, drop one extra mote from it — one per
## kill until the vault empties, so the player has to chase down what they left behind.
func drop_orb(world_pos: Vector3, xp_value: float, soul_value: int = 1) -> void:
	_spawn_orb(world_pos, xp_value)
	for _i in maxi(0, soul_value - 1):
		_spawn_orb(world_pos + _scatter(), 0.0)
	if stats != null and stats.draw_banked_soul():
		_spawn_orb(world_pos + _scatter(), 0.0)


## A random XZ offset within SCATTER — where bonus motes land around the corpse.
func _scatter() -> Vector3:
	return Vector3(_rng.randf_range(-SCATTER, SCATTER), 0.0, _rng.randf_range(-SCATTER, SCATTER))


## Instance one orb worth `xp_value` (plus its single soul) at `world_pos`.
func _spawn_orb(world_pos: Vector3, xp_value: float) -> void:
	var orb := XpOrbScript.new()
	orb.player = player
	orb.xp_value = xp_value
	add_child(orb)
	orb.global_position = world_pos


## Wave clear: every mote the player didn't collect goes to the soul vault (re-dropped next
## wave, one bonus per kill) instead of the marine — but its XP is still credited, so leaving
## orbs behind costs souls, not levels. The motes drift off screen; _process then emits
## `drained` once the field is empty (see above), which opens the wave menu.
func bank_leftovers() -> void:
	var leftover_xp := 0.0
	var soul_count := get_child_count()
	for orb in get_children():
		leftover_xp += orb.xp_value
		if orb.has_method("bank_drift"):
			orb.bank_drift()
	if leftover_xp > 0.0 and player != null and player.has_method("gain_xp"):
		player.gain_xp(leftover_xp)
	if soul_count > 0 and stats != null:
		stats.bank_souls(soul_count)
	_draining = true
	_drain_timer = DRAIN_TIMEOUT
