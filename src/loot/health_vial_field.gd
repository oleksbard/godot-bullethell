class_name HealthVialField
extends Node3D
## Drops health vials onto the island "from time to time" and never more than the marine
## actually needs. Wired by Main with the marine + its stats. The drop strategy lives here:
##
##   • Every DROP_INTERVAL, IF a drop is warranted, it rolls DROP_CHANCE to actually drop one
##     (so vials are uncommon, not clockwork). A warranted-but-unrolled interval just waits for
##     the next one; a not-warranted interval re-checks sooner (RECHECK) so a vial can appear
##     promptly once the marine gets hurt.
##   • A drop is warranted only while the marine is HURT, fewer than MAX_VIALS are on the map,
##     AND the vials already lying around don't already cover the missing HP — i.e. it won't
##     scatter 3 vials (60 HP) when the marine is only down 15. The live cap is effectively
##     ceil(missing_hp / heal), clamped to MAX_VIALS.
##   • Vials drop AWAY from the marine (MIN_FROM_PLAYER), so they're often off-screen under the
##     top-down camera — the "+" token on the screen border (offscreen_indicators.gd) guides you
##     there, and fetching one is a deliberate risk. They don't magnetise.
##
## ponytail: per-vial nodes tracked via the "health_vials" group; the cap is tiny (3) so a group
## scan each attempt is plenty — no pool/MultiMesh needed.

const HealthVialScript := preload("res://src/loot/health_vial.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")

const MAX_VIALS := 3            # hard ceiling on vials on the map at once
const DROP_INTERVAL := 12.0     # seconds between drop rolls
const DROP_CHANCE := 0.33       # probability a warranted interval actually drops a vial
const RECHECK := 2.0            # shorter retry after a not-warranted interval (full HP / already covered)
const SPAWN_MARGIN := 2.5       # keep drops inside the coast
const MIN_FROM_PLAYER := 7.0    # drop this far from the marine -> usually off-screen

var player: Node3D
var stats: Node                 # PlayerStats; read to gate drops on missing HP. null -> always warranted
var drop_chance := DROP_CHANCE  # per-interval drop probability (var so tests can force it to 1.0)

var _rng := RandomNumberGenerator.new()
var _timer := DROP_INTERVAL


func _ready() -> void:
	_rng.seed = 90210


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	if not _should_drop():
		_timer = RECHECK            # full HP / already covered -> re-check soon
		return
	_timer = DROP_INTERVAL          # a warranted interval -> one chance, then wait a full interval
	if _rng.randf() < drop_chance:
		_drop_one()


## A drop is warranted only while the marine is hurt, under the hard cap, and the vials already
## on the map don't already cover the missing HP (so we never drop more health than is needed).
func _should_drop() -> bool:
	var count := _alive_vials()
	if count >= MAX_VIALS:
		return false
	if stats == null:
		return true                 # no stats (e.g. a bare test) -> always warranted, just capped
	var missing: float = stats.max_health - stats.health
	if missing <= 0.0:
		return false                # full HP
	return float(count) * HealthVialScript.HEAL < missing   # existing vials don't yet cover the gap


## Count of live vials currently on the map.
func _alive_vials() -> int:
	var n := 0
	for v in get_tree().get_nodes_in_group(HealthVialScript.GROUP):
		if is_instance_valid(v):
			n += 1
	return n


func _drop_one() -> void:
	var vial := HealthVialScript.new()
	vial.player = player
	add_child(vial)
	vial.global_position = _scatter_point()


## A random point on the island — inside the coast and away from the marine.
func _scatter_point() -> Vector3:
	var origin := Vector3(player.global_position.x, 0.0, player.global_position.z) if player != null else Vector3.ZERO
	for _attempt in 24:
		var ang := _rng.randf_range(0.0, TAU)
		var max_r: float = IslandShape.radius(ang) - SPAWN_MARGIN
		if max_r <= 0.0:
			continue
		var r := _rng.randf_range(0.0, max_r)
		var p := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		if p.distance_to(origin) >= MIN_FROM_PLAYER:
			return p
	return Vector3.ZERO         # fell through (marine cornered) -> centre is a fine fallback
