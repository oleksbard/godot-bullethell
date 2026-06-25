class_name Gib
extends MeshInstance3D
## A chunk of a blown-up imp: a small beveled box launched with a velocity + spin,
## falls under gravity, settles on the ground, then shrinks away and frees itself.
## Created by Gore; `color`/`size`/`launch()` are set right after instancing.

const MeshFactory := preload("res://src/lib/mesh_factory.gd")

const GRAVITY := 20.0
const LIFETIME := 1.8
const FADE := 0.5           # shrink over the last FADE seconds

var color := Color(0.45, 0.08, 0.08)
var size := 0.2

var _vel := Vector3.ZERO
var _spin := Vector3.ZERO
var _life := 0.0
var _settled := false


func launch(vel: Vector3, spin: Vector3) -> void:
	_vel = vel
	_spin = spin


func _ready() -> void:
	mesh = MeshFactory.beveled_box(Vector3(size, size, size), size * 0.2)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m


func _process(delta: float) -> void:
	_life += delta
	if _life > LIFETIME:
		queue_free()
		return

	if not _settled:
		_vel.y -= GRAVITY * delta
		global_position += _vel * delta
		rotation += _spin * delta
		var floor_y := size * 0.5 + 0.02
		if global_position.y <= floor_y:
			global_position.y = floor_y
			_settled = true

	var remaining := LIFETIME - _life
	if remaining < FADE:
		scale = Vector3.ONE * clampf(remaining / FADE, 0.05, 1.0)
