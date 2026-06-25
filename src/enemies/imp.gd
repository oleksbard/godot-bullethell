class_name Imp
extends Node3D
## A "weak imp" — placeholder enemy (real model added later). Super-simple
## procedural body: a dark-red blob with glowing eyes. Drifts slowly toward the
## player and registers in the "imps" group so weapons can target it and the
## off-screen indicator can point at it.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const Gore := preload("res://src/fx/gore.gd")

const GROUP := "imps"
const SPEED := 1.6           # drift toward the player (set 0 for static)
const STOP_DIST := 0.8       # don't climb onto the player
const SEP_RADIUS := 1.2      # personal space — push apart inside this
const SEP_WEIGHT := 1.6      # how hard separation overrides the pull to the player
const BODY_COLOR := Color(0.45, 0.08, 0.08)

var player: Node3D
var _dead := false


func _ready() -> void:
	add_to_group(GROUP)
	_build_body()


## Killed by a projectile: leave gore, drop out of the target group, vanish.
func die() -> void:
	if _dead:
		return                          # guard: two bolts can land the same frame
	_dead = true
	remove_from_group(GROUP)            # stop other guns/bolts targeting a corpse
	Gore.spawn_death(get_parent(), global_position, BODY_COLOR)
	queue_free()


func _process(delta: float) -> void:
	if _dead or player == null:
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0

	# Steer toward the player, but pushed apart from nearby imps so they spread
	# out instead of overlapping into one clump.
	var steer := Vector3.ZERO
	if to_player.length() > STOP_DIST:
		steer += to_player.normalized()
	steer += _separation() * SEP_WEIGHT
	if steer.length() > 0.001:
		global_position += steer.normalized() * SPEED * delta

	if to_player.length() > 0.05:
		rotation.y = atan2(-to_player.x, -to_player.z)   # always face the player (-Z forward)


## Sum of repulsion from imps inside SEP_RADIUS (stronger the closer they are).
## ponytail: O(n) per imp -> O(n^2)/frame for the swarm; fine at these wave sizes,
## swap to a spatial grid if waves reach the many-hundreds.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group(GROUP):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector3 = global_position - (other as Node3D).global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.001 and d < SEP_RADIUS:
			push += away.normalized() * (1.0 - d / SEP_RADIUS)
	return push


func _build_body() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BODY_COLOR
	mat.roughness = 0.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var body := MeshInstance3D.new()
	body.mesh = MeshFactory.beveled_box(Vector3(0.7, 0.8, 0.6), 0.12)
	body.material_override = mat
	body.position.y = 0.5
	add_child(body)

	# Glowing eyes on the -Z front — pop against the hellish scene.
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.9, 0.2)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.85, 0.15)
	eye_mat.emission_energy_multiplier = 2.5
	eye_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for sx in [-0.16, 0.16]:
		var eye := MeshInstance3D.new()
		eye.mesh = MeshFactory.beveled_box(Vector3(0.12, 0.12, 0.08), 0.03)
		eye.material_override = eye_mat
		eye.position = Vector3(sx, 0.62, -0.31)
		add_child(eye)
