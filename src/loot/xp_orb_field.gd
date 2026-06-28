class_name XpOrbField
extends Node3D
## Owns every live XP orb. Wired by Main: connect WaveSpawner.imp_spawned -> on_imp_spawned
## (so each imp's death drops an orb), and WaveSpawner.wave_cleared -> vacuum_all (so leftover
## orbs all fly to the marine when a wave ends — no earned XP is lost). Sits at world origin;
## orbs are its children.
## ponytail: per-orb nodes + queue_free; pool / MultiMesh only if orb counts ever spike.

signal drained()                 # every vacuumed orb has flown into the player -> Main opens the wave menu

const XpOrbScript := preload("res://src/loot/xp_orb.gd")

const SCATTER := 0.7              # how far bonus soul-motes scatter out from the corpse (XZ)
const DRAIN_TIMEOUT := 4.0        # safety: drain anyway if an orb somehow can't reach the player

var player: Node3D                # the marine; handed to each spawned orb
var _rng := RandomNumberGenerator.new()   # seeded -> deterministic bonus-mote scatter
var _draining := false            # vacuuming + waiting for the field to empty before the menu opens
var _drain_timer := 0.0


func _ready() -> void:
	_rng.seed = 0x5EED


## While draining (after a wave-clear vacuum), emit `drained` once every orb has flown into
## the player and freed itself — or after DRAIN_TIMEOUT as a safety net.
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
## paid by the main orb, so the extras carry 0 XP — they're pure souls).
func drop_orb(world_pos: Vector3, xp_value: float, soul_value: int = 1) -> void:
	_spawn_orb(world_pos, xp_value)
	for _i in maxi(0, soul_value - 1):
		var off := Vector3(_rng.randf_range(-SCATTER, SCATTER), 0.0, _rng.randf_range(-SCATTER, SCATTER))
		_spawn_orb(world_pos + off, 0.0)


## Instance one orb worth `xp_value` (plus its single soul) at `world_pos`.
func _spawn_orb(world_pos: Vector3, xp_value: float) -> void:
	var orb := XpOrbScript.new()
	orb.player = player
	orb.xp_value = xp_value
	add_child(orb)
	orb.global_position = world_pos


## Pull every live orb to the marine regardless of distance (called on a cleared wave), then
## start draining: _process emits `drained` once they've all flown in (see above).
func vacuum_all() -> void:
	for orb in get_children():
		if orb.has_method("vacuum"):
			orb.vacuum()
	_draining = true
	_drain_timer = DRAIN_TIMEOUT
