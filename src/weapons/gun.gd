class_name Gun
extends Node3D
## A floating placeholder gun (real model added later): a couple of beveled boxes
## forming a body + barrel, plus a muzzle-flash light. Smoothly yaws so its barrel
## (-Z) points at its target imp, and fires bolts on a cooldown — each shot pulses
## the muzzle light and emits `fired(origin, target)` for the WeaponRing to spawn
## a projectile.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")

signal fired(origin: Vector3, target: Node3D, damage: float)

const TURN_SPEED := 18.0
const FIRE_INTERVAL := 1.7
const DAMAGE := 5.0            # base pistol damage per bolt (marine power is fixed — no upgrades yet)
const FLASH_ENERGY := 6.0      # peak muzzle-flash brightness
const FLASH_DECAY := 40.0      # energy/sec falloff — a quick realistic pop
const FLASH_SIZE := 0.55       # muzzle-flash sprite size (world units)
const BARREL_TIP := Vector3(0.0, 0.02, -0.34)   # muzzle of the pistol barrel

# When held in a hand, the marine's body aims the gun (the WeaponRing locks its
# orientation to the body's forward), so the gun skips its own yaw.
var held := false

static var _shared_flash_tex: Texture2D   # soft round flash sprite, shared by all guns

var _target: Node3D
var _cooldown := 0.0
var _flash: OmniLight3D
var _flash_quad: MeshInstance3D
var _flash_mat: StandardMaterial3D


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

	# Muzzle flash (light + sprite) decays back to dark.
	if _flash.light_energy > 0.0:
		_flash.light_energy = move_toward(_flash.light_energy, 0.0, FLASH_DECAY * delta)
		var f := _flash.light_energy / FLASH_ENERGY
		_flash_mat.albedo_color.a = clampf(f, 0.0, 1.0)
		_flash_quad.visible = f > 0.02


func _fire() -> void:
	_cooldown = FIRE_INTERVAL
	_flash.light_energy = FLASH_ENERGY
	_flash_quad.scale = Vector3.ONE * randf_range(0.85, 1.3)   # vary so shots don't look identical
	_flash_quad.visible = true
	fired.emit(to_global(BARREL_TIP), _target, DAMAGE)


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

	# Visible muzzle-flash sprite: a soft round additive billboard at the barrel
	# tip, popped on each shot and faded out with the flash light (see _process).
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.billboard_keep_scale = true        # honour the per-shot scale jitter
	_flash_mat.albedo_color = Color(1.0, 0.8, 0.45, 0.0)
	_flash_mat.albedo_texture = _flash_texture()

	_flash_quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(FLASH_SIZE, FLASH_SIZE)
	_flash_quad.mesh = qm
	_flash_quad.material_override = _flash_mat
	_flash_quad.position = BARREL_TIP
	_flash_quad.visible = false
	add_child(_flash_quad)


## A soft round flash sprite (white-hot core → warm → transparent edge), built
## once and shared by every gun (read-only).
static func _flash_texture() -> Texture2D:
	if _shared_flash_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 0.8, 0.4, 0.7), Color(1, 0.4, 0.1, 0.0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_shared_flash_tex = t
	return _shared_flash_tex
