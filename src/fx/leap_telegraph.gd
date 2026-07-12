class_name LeapTelegraph
extends Node3D
## The ground telegraph for an imp's leap: a chevron strip that fills from the imp toward
## the LOCKED landing point as the charge bar fills, its arrows pointing at the player
## (`i ► ► ► ► p`). The imp spawns it on charge start, drives set_progress() each frame, and
## calls fire() when it jumps. Self-orients between the two points. Reference via a preload const.

const STRIP_SHADER := preload("res://src/fx/leap_telegraph.gdshader")

const WIDTH := 0.7              # strip width (world units)
const CHEVRON_LEN := 0.7       # world units per arrowhead — fixed so arrows keep one shape at any leap distance
const Y_LIFT := 0.06           # float just above the ground (depth_test_disabled draws it over terrain anyway)
const COLOR := Color(1.0, 0.35, 0.08)   # ember-orange, matches the imps' eyes
const FIRE_TIME := 0.14        # white flash-out after launch, then free

var _strip_mat: ShaderMaterial


## Lay the strip from `from` (the imp) to `to` (the locked landing point).
func setup(from: Vector3, to: Vector3) -> void:
	var fwd := to - from
	fwd.y = 0.0
	var dist := maxf(fwd.length(), 0.001)
	fwd /= dist
	# Lay the quad flat with local +X = imp->target (UV.x 0 = imp, 1 = player), +Y up, +Z the
	# in-ground perpendicular. Built as an explicit basis + global_transform so it's correct
	# regardless of the parent's transform.
	var perp := Vector3(-fwd.z, 0.0, fwd.x)
	global_transform = Transform3D(Basis(fwd, Vector3.UP, perp), (from + to) * 0.5 + Vector3(0.0, Y_LIFT, 0.0))

	_strip_mat = ShaderMaterial.new()
	_strip_mat.shader = STRIP_SHADER
	_strip_mat.set_shader_parameter("color", Vector3(COLOR.r, COLOR.g, COLOR.b))
	# One arrow per CHEVRON_LEN of world length -> arrows keep a constant shape regardless of leap distance.
	_strip_mat.set_shader_parameter("chevrons", maxf(2.0, roundf(dist / CHEVRON_LEN)))
	var plane := PlaneMesh.new()               # lies flat in XZ, faces +Y; UV.x runs along +X
	plane.size = Vector2(dist, WIDTH)
	var strip := MeshInstance3D.new()
	strip.mesh = plane
	strip.material_override = _strip_mat
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strip)


## Fill 0..1, from the imp end toward the player.
func set_progress(p: float) -> void:
	if _strip_mat != null:
		_strip_mat.set_shader_parameter("progress", clampf(p, 0.0, 1.0))


## The imp launched — flash the strip white and free it.
func fire() -> void:
	if _strip_mat != null:
		_strip_mat.set_shader_parameter("progress", 1.0)
	var tw := create_tween()
	tw.tween_method(_set_flash, 1.0, 0.0, FIRE_TIME)
	tw.tween_callback(queue_free)


func _set_flash(v: float) -> void:
	if _strip_mat != null:
		_strip_mat.set_shader_parameter("flash", v)
