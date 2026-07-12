class_name RevenantCoordinator
extends Node
## Grants the revenant missile-barrage one at a time, on a global cooldown. Revenants don't
## decide to barrage themselves — this scans the swarm each frame and, when the cooldown is up
## and no barrage is active, tells the eligible revenant NEAREST the player to begin_barrage().
## Only revenants (can_special_barrage) are considered. Added to the tree by the WaveSpawner
## (which sets `player`); a null coordinator (e.g. tests that never add one) means no barrages.

const EnemyScript := preload("res://src/enemies/enemy.gd")

const COOLDOWN := 15.0         # seconds between barrages (re-armed when a barrage resolves)

var player: Node3D             # the barrage target source (set by the spawner)
var _cooldown := COOLDOWN       # start armed-down so a wave never opens with an instant barrage
var _active: Node = null       # the revenant currently barraging (the single token holder)


func _process(delta: float) -> void:
	if _active != null:
		if not is_instance_valid(_active) or not _active.is_barraging():
			_active = null
			_cooldown = COOLDOWN
		return
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	if player == null:
		return
	var best: Node = _pick_eligible()
	if best != null:
		best.begin_barrage()
		_active = best


## The eligible revenant nearest the player (null if none). Nearest -> the closest threat
## unleashes the volley, so it reads as a reaction to the player closing in.
func _pick_eligible() -> Node:
	var best: Node = null
	var best_d := INF
	for r in get_tree().get_nodes_in_group(EnemyScript.GROUP):
		if not is_instance_valid(r) or not r.can_special_barrage or not r.can_barrage():
			continue
		var d: float = (r.global_position - player.global_position).length()
		if d < best_d:
			best = r
			best_d = d
	return best
