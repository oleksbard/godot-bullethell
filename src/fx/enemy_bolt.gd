class_name EnemyBolt
extends Node3D
## A bolt fired by a ranged ENEMY (the Revenant) at the marine. It aims once — at the
## player's mass the instant it locks (or along an explicit aim_dir for a barrage fan) —
## then flies straight and level. No homing: strafe and it misses. It damages ONLY the
## player: it never scans the "imps" group, so it CANNOT harm other enemies. This is the
## mirror image of Projectile (which hits enemies and credits a gun); kept separate so the
## weapon bolt stays clean.

const SPEED := 16.0         # ~40% of the player bolt (38.25) — slow enough to sidestep
const HIT_DIST := 0.75      # horizontal hit radius vs the single player
const LIFETIME := 4.0
const MAX_RANGE := 40.0
const AIM_HEIGHT := 0.9     # aim at the marine's mass, not its feet

var player: Node3D          # the victim; set by the firing enemy
var damage := 2.5           # set by the firing enemy from its (wave-scaled) attack_damage
var speed := SPEED
var aim_dir := Vector3.ZERO # if non-zero, fly this heading (barrage fan); else aim at the player
var _dir := Vector3.ZERO
var _life := 0.0
var _traveled := 0.0
var _spent := false         # hit or expired -> awaiting free; never act (or hit) twice


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if _spent:
		return
	_life += delta
	if _life > LIFETIME:
		_spent = true
		queue_free()
		return

	# Lock the heading once (flat XZ — bolts fly level): an explicit aim_dir (barrage fan)
	# wins; otherwise aim at where the player is now. Then fly straight, no retargeting.
	if _dir == Vector3.ZERO:
		if aim_dir != Vector3.ZERO:
			_dir = Vector3(aim_dir.x, 0.0, aim_dir.z).normalized()
		elif is_instance_valid(player):
			var to := player.global_position - global_position
			to.y = 0.0
			if to.length() > 0.001:
				_dir = to.normalized()
		if _dir == Vector3.ZERO:
			queue_free()              # nothing to aim at when fired — no shot
			return
		rotation.y = atan2(-_dir.x, -_dir.z)

	global_position += _dir * speed * delta
	_traveled += speed * delta
	if _traveled > MAX_RANGE:
		_spent = true
		queue_free()
		return

	# Hit test against ONLY the player (horizontal). Never touches the enemy group, so a
	# revenant's shot can't kill its own kind. Slow bolt + generous radius -> no tunnelling.
	if is_instance_valid(player):
		var d := player.global_position - global_position
		d.y = 0.0
		if d.length() < HIT_DIST:
			_spent = true
			if player.has_method("take_damage"):
				player.take_damage(damage)
			queue_free()


func _build() -> void:
	# Hostile RED tracer — unmistakably different from the player's warm yellow/orange bolt
	# (albedo 1,0.85,0.4). Bigger too, so incoming fire reads at a glance.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.12, 0.08)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.03, 0.03)      # deep crimson glow
	mat.emission_energy_multiplier = 7.0       # blooms via the scene glow — reads as a threat tracer
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sph := SphereMesh.new()
	sph.radius = 0.11
	sph.height = 0.22
	var mi := MeshInstance3D.new()
	mi.mesh = sph
	mi.material_override = mat
	add_child(mi)
