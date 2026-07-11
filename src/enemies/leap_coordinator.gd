class_name LeapCoordinator
extends Node
## Grants the imp leap-special one at a time, with a global cooldown. Imps don't decide
## to leap themselves — this scans the live swarm each frame and, when the cooldown is up
## and no leap is in flight, triggers the nearest eligible imp's charged pounce. Holding a
## single "leap token" is what enforces "only one leap at a time" regardless of swarm size.
## Injected into the tree by the WaveSpawner (which sets `player`); a null coordinator
## (e.g. tests that never add one) simply means no leaps. Reference via a preload const.

const ImpScript := preload("res://src/enemies/imp.gd")

const COOLDOWN := 7.0          # seconds between leaps (re-armed when a leap resolves) — ~25% fewer than 5.0 over the ~6.4s cycle
const MIN_RANGE := 3.0         # don't leap from right on top of the player...
const MAX_RANGE := 10.0        # ...or from beyond ~pistol distance (pistol range ≈ 11)

var player: Node3D             # the leap target source (set by the spawner)
var _cooldown := COOLDOWN       # start armed-down so a wave never opens with an instant leap
var _active: Node = null       # the imp currently charging/leaping (the single token holder)


func _process(delta: float) -> void:
	# A leap is in flight: hold the token until that imp lands (or dies), then re-arm.
	if _active != null:
		if not is_instance_valid(_active) or not _active.is_leaping():
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
		best.begin_leap(player.global_position)
		_active = best


## Nearest alive, fully-emerged, idle imp inside the leap range band (null if none).
func _pick_eligible() -> Node:
	var best: Node = null
	var best_d := INF
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if not is_instance_valid(imp) or not imp.can_special_leap or not imp.can_leap():
			continue                    # imps only — the zombie sets can_special_leap=false
		var d: float = (imp.global_position - player.global_position).length()
		if d < MIN_RANGE or d > MAX_RANGE or d >= best_d:
			continue
		best = imp
		best_d = d
	return best
