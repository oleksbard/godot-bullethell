class_name TurretMount
extends Node3D
## A procedural "turret arm" for a floating gun: a thin dark-metal strut springing
## from a torso hub out to a small ember-glowing pivot ball the gun perches on, so the
## gun reads as mounted on the marine rather than free-floating. The WeaponRing makes
## one per floating gun and calls set_span() each frame to re-aim it as the marine
## turns and bobs. Pure visual — no logic, no targeting.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")

const STRUT_THICK := 0.05      # strut cross-section (world units)
const BALL_RADIUS := 0.085     # pivot ball the gun sits on
const METAL := Color(0.16, 0.16, 0.18)   # same dark metal as the gun body
const JOINT := Color(1.0, 0.45, 0.2)     # ember pivot accent (matches the world palette)
const JOINT_ENERGY := 0.85     # gentle — kept under the env glow threshold so it's a warm dot, not a flare

var _strut: MeshInstance3D
var _ball: MeshInstance3D


func _ready() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = METAL
	metal.metallic = 0.5
	metal.roughness = 0.5

	_strut = MeshInstance3D.new()
	_strut.mesh = MeshFactory.beveled_box(Vector3(STRUT_THICK, STRUT_THICK, 1.0), 0.015)
	_strut.material_override = metal
	add_child(_strut)

	var joint := StandardMaterial3D.new()
	joint.albedo_color = JOINT
	joint.emission_enabled = true
	joint.emission = JOINT
	joint.emission_energy_multiplier = JOINT_ENERGY
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_ball = MeshInstance3D.new()
	_ball.mesh = sphere
	_ball.material_override = joint
	add_child(_ball)


## Span the strut from `from` to `to` (in this mount's local space — it sits at the
## ring origin) and seat the pivot ball at `to`. Builds a basis whose +Z runs along
## the segment, scaled to its length; the box is symmetric so direction sign is moot.
func set_span(from: Vector3, to: Vector3) -> void:
	var delta := to - from
	var dist := delta.length()
	if dist < 0.001:
		return
	var zaxis := delta / dist
	var up := Vector3.UP if absf(zaxis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var xaxis := up.cross(zaxis).normalized()
	var yaxis := zaxis.cross(xaxis)
	_strut.transform = Transform3D(Basis(xaxis, yaxis, zaxis).scaled(Vector3(1.0, 1.0, dist)), (from + to) * 0.5)
	_ball.position = to
