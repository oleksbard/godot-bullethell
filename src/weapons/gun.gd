class_name Gun
extends Node3D
## A floating placeholder gun (real model added later): a couple of beveled boxes
## forming a body + barrel, plus a muzzle-flash light. Smoothly yaws so its barrel
## (-Z) points at its target imp, and fires bolts on a cooldown — each shot pulses
## the muzzle light and emits `fired(origin, target)` for the WeaponRing to spawn
## a projectile.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")

signal fired(origin: Vector3, target: Node3D)

const TURN_SPEED := 18.0
const FIRE_INTERVAL := 1.7
const FLASH_ENERGY := 6.0      # peak muzzle-flash brightness
const FLASH_DECAY := 40.0      # energy/sec falloff — a quick realistic pop
const BARREL_TIP := Vector3(0.0, 0.02, -0.7)

# When held in a hand, the marine's body aims the gun (the WeaponRing locks its
# orientation to the body's forward), so the gun skips its own yaw.
var held := false

var _target: Node3D
var _cooldown := 0.0
var _flash: OmniLight3D


func _ready() -> void:
	_build_body()


func set_target(t: Node3D) -> void:
	_target = t


func clear_target() -> void:
	_target = null


## Offset the first shot so guns don't all fire on the same frame.
func stagger(t: float) -> void:
	_cooldown = t


func _process(delta: float) -> void:
	# Floating guns yaw their own barrel (-Z) toward the target; held guns are
	# aimed by the marine's body, so the WeaponRing sets their transform instead.
	if not held:
		var want_yaw := rotation.y
		if is_instance_valid(_target):
			var to := _target.global_position - global_position
			to.y = 0.0
			if to.length() > 0.01:
				want_yaw = atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, want_yaw, clampf(delta * TURN_SPEED, 0.0, 1.0))

	# Fire on cooldown when there's something to shoot.
	_cooldown -= delta
	if is_instance_valid(_target) and _cooldown <= 0.0:
		_fire()

	# Muzzle flash decays back to dark.
	if _flash.light_energy > 0.0:
		_flash.light_energy = move_toward(_flash.light_energy, 0.0, FLASH_DECAY * delta)


func _fire() -> void:
	_cooldown = FIRE_INTERVAL
	_flash.light_energy = FLASH_ENERGY
	fired.emit(to_global(BARREL_TIP), _target)


func _build_body() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.20)
	mat.metallic = 0.4
	mat.roughness = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var body := MeshInstance3D.new()
	body.mesh = MeshFactory.beveled_box(Vector3(0.18, 0.18, 0.5), 0.04)
	body.material_override = mat
	add_child(body)

	var barrel := MeshInstance3D.new()
	barrel.mesh = MeshFactory.beveled_box(Vector3(0.08, 0.08, 0.42), 0.02)
	barrel.material_override = mat
	barrel.position = Vector3(0.0, 0.02, -0.42)   # sticks out the -Z front
	add_child(barrel)

	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.85, 0.55)   # warm gunfire light
	_flash.light_energy = 0.0
	_flash.omni_range = 4.5
	_flash.position = BARREL_TIP
	add_child(_flash)
