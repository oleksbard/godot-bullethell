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
const BARREL_TIP := Vector3(0.0, 0.02, -0.34)   # muzzle of the pistol barrel

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


## The imp this gun is currently aiming at (null if none). Used by the WeaponRing
## to splay a held gun toward its own target.
func get_target() -> Node3D:
	return _target


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
	# A small pistol: a low slide, a stubby barrel out the -Z front, and a raked
	# grip below. Roughly hand-sized so it sits naturally in the marine's grip.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.18)
	mat.metallic = 0.5
	mat.roughness = 0.45
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var slide := MeshInstance3D.new()
	slide.mesh = MeshFactory.beveled_box(Vector3(0.1, 0.12, 0.36), 0.03)
	slide.material_override = mat
	add_child(slide)

	var barrel := MeshInstance3D.new()
	barrel.mesh = MeshFactory.beveled_box(Vector3(0.07, 0.09, 0.18), 0.02)
	barrel.material_override = mat
	barrel.position = Vector3(0.0, 0.02, -0.25)   # pokes out the -Z front
	add_child(barrel)

	var grip := MeshInstance3D.new()
	grip.mesh = MeshFactory.beveled_box(Vector3(0.08, 0.22, 0.1), 0.025)
	grip.material_override = mat
	grip.position = Vector3(0.0, -0.15, 0.1)      # hangs down-back of the slide
	grip.rotation.x = deg_to_rad(16.0)            # raked back like a real grip
	add_child(grip)

	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.85, 0.55)   # warm gunfire light
	_flash.light_energy = 0.0
	_flash.omni_range = 3.5
	_flash.position = BARREL_TIP
	add_child(_flash)
