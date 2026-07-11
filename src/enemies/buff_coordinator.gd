class_name BuffCoordinator
extends Node
## Grants the zombie AoE-haste channel one at a time, on a global cooldown. Zombies don't
## decide to channel themselves — this scans the swarm each frame and, when the cooldown is
## up and no channel is active, tells the eligible zombie with the MOST buffable neighbours
## to begin_channel(). Only zombies (can_special_buff) are considered. Added to the tree by
## the WaveSpawner; it needs nothing but the tree (it finds enemies by group).

const EnemyScript := preload("res://src/enemies/enemy.gd")

const COOLDOWN := 25.0         # seconds between channels (re-armed when a channel resolves)
const MIN_TARGETS := 1         # only channel when at least this many enemies are in buff range

var _cooldown := COOLDOWN       # start armed-down so a wave never opens with an instant buff
var _active: Node = null       # the zombie currently channelling (the single token holder)


func _process(delta: float) -> void:
	if _active != null:
		if not is_instance_valid(_active) or not _active.is_channeling():
			_active = null
			_cooldown = COOLDOWN
		return
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	var best: Node = _pick_eligible()
	if best != null:
		best.begin_channel()
		_active = best


## The eligible zombie with the most other enemies in buff range (>= MIN_TARGETS), or null.
## ponytail: O(n^2) over the swarm, but only while the cooldown is up AND no zombie yet
## qualifies — normally a zombie has neighbours and it fires the first frame it's armed.
func _pick_eligible() -> Node:
	var group := get_tree().get_nodes_in_group(EnemyScript.GROUP)
	var best: Node = null
	var best_n := MIN_TARGETS - 1
	for z in group:
		if not is_instance_valid(z) or not z.can_special_buff or not z.can_channel():
			continue
		var n := 0
		for other in group:
			if other == z or not is_instance_valid(other):
				continue
			if (other.global_position - z.global_position).length() <= EnemyScript.BUFF_RANGE:
				n += 1
		if n > best_n:
			best = z
			best_n = n
	return best
