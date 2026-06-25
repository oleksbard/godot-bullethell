class_name Projectile
extends Node3D
## A glowing bolt fired by a gun. It homes toward its assigned imp for guidance,
## but it is NOT locked to it: each frame it kills the first imp its travel
## actually crosses (swept), and if its assigned target dies it retargets to the
## nearest imp rather than flying off. Expires after LIFETIME.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const ImpScript := preload("res://src/enemies/imp.gd")

const SPEED := 38.25        # 15% slower than the original 45
const HIT_DIST := 0.7
const LIFETIME := 2.0
const AIM_HEIGHT := 0.6     # aim at the imp's mass, not its feet

var target: Node3D
var _dir := Vector3.ZERO
var _life := 0.0


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME:
		queue_free()
		return

	# Home toward a target for guidance; reacquire the nearest imp if it died.
	if not is_instance_valid(target):
		target = _nearest_imp()
	if is_instance_valid(target):
		var aim := target.global_position + Vector3(0.0, AIM_HEIGHT, 0.0)
		var to := aim - global_position
		if to.length() > 0.001:
			_dir = to.normalized()

	var prev := global_position
	global_position += _dir * SPEED * delta

	# Collide with whatever imp this step actually crossed first — not only the
	# assigned target, so a closer imp in the path takes the hit.
	var hit := _first_hit(prev, global_position)
	if hit != null:
		hit.die()
		queue_free()


## The imp whose body the segment a→b passes closest along its travel (smallest
## param t), within HIT_DIST. null if the path hits nothing.
func _first_hit(a: Vector3, b: Vector3) -> Node3D:
	var ab := b - a
	var len2 := ab.length_squared()
	var best: Node3D = null
	var best_t := INF
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if not is_instance_valid(imp):
			continue
		var p: Vector3 = (imp as Node3D).global_position + Vector3(0.0, AIM_HEIGHT, 0.0)
		var t := 0.0
		if len2 > 0.000001:
			t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		if (a + ab * t).distance_to(p) < HIT_DIST and t < best_t:
			best_t = t
			best = imp
	return best


func _nearest_imp() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if not is_instance_valid(imp):
			continue
		var d := global_position.distance_squared_to((imp as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = imp
	return best


func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 6.0       # blooms via the scene glow — reads as a tracer
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sph := SphereMesh.new()
	sph.radius = 0.065         # 50% smaller than the original 0.13
	sph.height = 0.13
	var mi := MeshInstance3D.new()
	mi.mesh = sph
	mi.material_override = mat
	add_child(mi)
