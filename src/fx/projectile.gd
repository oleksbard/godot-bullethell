class_name Projectile
extends Node3D
## A glowing bolt fired by a gun. It aims once — at its target's position the
## instant it spawns — then flies in a straight line. It does NOT home or
## retarget: if the imp moves out of the way, the bolt misses. Along that
## straight path it damages the first imp it actually crosses (swept), so a closer
## imp that wanders into the line still takes the hit. Expires after LIFETIME.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const ImpScript := preload("res://src/enemies/imp.gd")

signal hit_enemy            # emitted when this bolt hits an imp (drives the impact SFX)

const SPEED := 38.25        # 15% slower than the original 45
const HIT_DIST := 0.7
const LIFETIME := 2.0
const AIM_HEIGHT := 0.6     # aim at the imp's mass, not its feet

# Blood this projectile type leaves per kill (rolled per hit). The basic bolt is
# weak — a light spatter. Heavier weapons set a bigger range.
const BLOOD_MIN := 1
const BLOOD_MAX := 4

var target: Node3D
var damage := 5.0           # set by the WeaponRing from the firing gun's DAMAGE
var _dir := Vector3.ZERO
var _life := 0.0


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME:
		queue_free()
		return

	# Lock the heading once, on the first frame, toward where the target is now —
	# then fly straight. No homing, no retargeting: a dodged shot misses.
	if _dir == Vector3.ZERO:
		if is_instance_valid(target):
			var to := (target.global_position + Vector3(0.0, AIM_HEIGHT, 0.0)) - global_position
			if to.length() > 0.001:
				_dir = to.normalized()
		if _dir == Vector3.ZERO:
			queue_free()              # nothing to aim at when fired — no shot
			return

	var prev := global_position
	global_position += _dir * SPEED * delta

	# Collide with whatever imp this step actually crossed first — not only the
	# assigned target, so a closer imp in the path takes the hit.
	var hit := _first_hit(prev, global_position)
	if hit != null:
		hit_enemy.emit()
		hit.take_damage(damage, randi_range(BLOOD_MIN, BLOOD_MAX), _dir)   # dir: blood + gibs spray forward on the kill
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
