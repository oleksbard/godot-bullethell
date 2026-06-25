class_name WaveSpawner
extends Node3D
## Spawns waves of imps scattered across the island. Wave 1 = 15 imps; the count
## will scale per wave later. Imps register themselves in the "imps" group, so
## nothing else needs a direct reference to them.

const ImpScript := preload("res://src/enemies/imp.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")

const WAVE_1_COUNT := 15
const WAVE_DELAY := 5.0         # pause after a wave is cleared
const SPAWN_MARGIN := 2.0       # keep spawns inside the coast
const MIN_FROM_CENTER := 6.0    # don't spawn on top of the player (spawns at centre)

var player: Node3D
var _rng := RandomNumberGenerator.new()
var _wave_count := WAVE_1_COUNT  # doubles each cleared wave: 15 -> 30 -> 60 ...
var _between := false
var _timer := 0.0


func _ready() -> void:
	_rng.seed = 1337
	spawn_wave(_wave_count)


func _process(delta: float) -> void:
	if _between:
		_timer -= delta
		if _timer <= 0.0:
			_between = false
			_wave_count *= 2
			spawn_wave(_wave_count)
		return
	if _alive() == 0:
		_between = true
		_timer = WAVE_DELAY


## Count of live imps still in the wave.
func _alive() -> int:
	var n := 0
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if is_instance_valid(imp):
			n += 1
	return n


func spawn_wave(count: int) -> void:
	for i in count:
		var imp := ImpScript.new()
		imp.player = player
		imp.position = _scatter_point()
		add_child(imp)


## A random point on the island — inside the coast, away from the centre.
func _scatter_point() -> Vector3:
	for _attempt in 20:
		var ang := _rng.randf_range(0.0, TAU)
		var max_r: float = IslandShape.radius(ang) - SPAWN_MARGIN
		if max_r <= MIN_FROM_CENTER:
			continue
		var r := _rng.randf_range(MIN_FROM_CENTER, max_r)
		return Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	return Vector3(MIN_FROM_CENTER, 0.0, 0.0)
