class_name Marine
extends Node3D
## The marine's controller: WASD movement, facing, a walk cycle, and a clamp to
## the hell island's coastline. The body is the imported rigged model
## (models/marine_01.glb); this script instances it and drives its skeleton.
##
## The glb is rigged in a T-pose (arms straight out) with no real animations, so
## the pose is authored here:
##   * Legs swing front/back about their local X relative to rest.
##   * Arms are *aimed* at a target direction (down + slightly out, plus a
##     forward/back reach while walking) — direction-aiming is axis-independent,
##     so "how far the hands sit from the body" is one intuitive knob (ARM_OUT)
##     instead of a guessed rotation axis.
## Movement/turning happen on this root; the bob moves the *model's* local Y so
## the camera-followed root never shakes.

const IslandShape := preload("res://src/lib/island_shape.gd")
const MODEL: PackedScene = preload("res://models/marine_01.glb")

const SPEED := 6.0
const TURN_SPEED := 12.0
const EDGE_MARGIN := 1.0

# Fitting the imported model. marine_01.glb faces +Z but Godot/the controller
# forward is -Z, so it needs a 180° yaw or it walks backward.
const MODEL_YAW := PI
const MODEL_Y_OFFSET := 0.0

# Walk + rest pose.
const WALK_FREQ := 9.0
const LEG_SWING := 0.6      # leg front/back swing (radians) at full speed
const ARM_OUT := 0.32       # how far the hands sit out from the torso (bigger = looser)
const ARM_SWING := 0.30     # forward/back arm reach added while walking
const BOB_HEIGHT := 0.06

var current_velocity := Vector3.ZERO

var _model: Node3D
var _skel: Skeleton3D
var _b_lup := -1      # LeftUpLeg
var _b_rup := -1      # RightUpLeg
var _b_larm := -1     # LeftArm
var _b_rarm := -1     # RightArm
var _rest := {}       # leg bone idx -> rest rotation Quaternion
var _arm := {}        # arm bone idx -> aim data {pinv: Basis, rb: Basis, dir: Vector3}
var _walk_phase := 0.0
var _walk_amt := 0.0


func _ready() -> void:
	_model = MODEL.instantiate()
	_model.rotation.y = MODEL_YAW
	_model.position.y = MODEL_Y_OFFSET
	add_child(_model)

	_skel = _find_skeleton(_model)
	if _skel == null:
		push_warning("marine_01.glb has no Skeleton3D — animation disabled.")
		return

	# The imported AnimationPlayer holds only a 1-frame bind pose; stop it from
	# fighting the bones we pose each frame.
	var ap := _model.find_child("AnimationPlayer", true, false)
	if ap != null:
		ap.active = false

	_b_lup = _skel.find_bone("LeftUpLeg")
	_b_rup = _skel.find_bone("RightUpLeg")
	for b in [_b_lup, _b_rup]:
		if b != -1:
			_rest[b] = _skel.get_bone_pose_rotation(b)

	_b_larm = _cache_arm("LeftArm", "LeftForeArm")
	_b_rarm = _cache_arm("RightArm", "RightForeArm")


func _process(delta: float) -> void:
	_handle_movement(delta)
	_animate_walk(delta)


func _handle_movement(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0

	var move := Vector3.ZERO
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		move = Vector3(dir.x, 0.0, dir.y)         # screen-aligned: W = away from camera
		var target_yaw := atan2(-move.x, -move.z)  # Godot forward is -Z
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * TURN_SPEED, 0.0, 1.0))

	current_velocity = move * SPEED
	position += current_velocity * delta
	_clamp_to_island()


## Keep the marine inside the coastline so it can't walk off into the void.
## Reuses the same IslandShape the mesh is built from, so the clamp matches the
## visible edge exactly.
func _clamp_to_island() -> void:
	var flat := Vector2(position.x, position.z)
	if flat.length() < 0.001:
		return
	var ang := atan2(position.z, position.x)
	var max_r: float = IslandShape.radius(ang) - EDGE_MARGIN
	if flat.length() > max_r:
		var clamped := flat.normalized() * max_r
		position.x = clamped.x
		position.z = clamped.y      # flat is Vector2(x, z) — .y holds world Z


func _animate_walk(delta: float) -> void:
	var frac := clampf(current_velocity.length() / SPEED, 0.0, 1.0)
	_walk_amt = lerpf(_walk_amt, frac, clampf(delta * 10.0, 0.0, 1.0))
	if frac > 0.01:
		_walk_phase += delta * WALK_FREQ
	if _skel == null:
		return
	var s := sin(_walk_phase) * _walk_amt
	_swing_bone(_b_lup, s * LEG_SWING)     # legs swing opposite each other
	_swing_bone(_b_rup, -s * LEG_SWING)
	_aim_arm(_b_larm, 1.0, -s)             # arms hang out to the sides, reach to counter the legs
	_aim_arm(_b_rarm, -1.0, s)
	_model.position.y = MODEL_Y_OFFSET + absf(sin(_walk_phase)) * BOB_HEIGHT * _walk_amt


## Rotate a leg bone about its local X by `ang`, relative to its rest pose.
func _swing_bone(b: int, ang: float) -> void:
	if b == -1:
		return
	_skel.set_bone_pose_rotation(b, _rest[b] * Quaternion(Vector3.RIGHT, ang))


## Cache what _aim_arm needs: the bone's global rest direction (toward its child),
## its global rest basis, and its parent's inverse global rest basis. Returns the
## bone index (or -1).
func _cache_arm(bone_name: String, child_name: String) -> int:
	var b := _skel.find_bone(bone_name)
	var child := _skel.find_bone(child_name)
	if b == -1 or child == -1:
		return -1
	var gb := _skel.get_bone_global_rest(b)
	var gc := _skel.get_bone_global_rest(child)
	var pidx := _skel.get_bone_parent(b)
	var pbasis := _skel.get_bone_global_rest(pidx).basis if pidx != -1 else Basis()
	_arm[b] = {
		"pinv": pbasis.inverse(),
		"rb": gb.basis,
		"dir": (gc.origin - gb.origin).normalized(),   # arm's pointing direction at rest
	}
	return b


## Aim an upper arm so it points down + out (`side` = +1 left / -1 right), with a
## forward/back `reach` (-1..1) folded in for the walk swing. Skeleton space: the
## character's front is +Z, left is +X, down is -Y.
func _aim_arm(b: int, side: float, reach: float) -> void:
	if not _arm.has(b):
		return
	var d: Dictionary = _arm[b]
	var target := Vector3(side * ARM_OUT, -1.0, reach * ARM_SWING).normalized()
	var swing := Quaternion(d["dir"], target)              # global rotation: rest dir -> target
	var new_basis := Basis(swing) * (d["rb"] as Basis)     # bone's new global basis
	var local: Basis = (d["pinv"] as Basis) * new_basis    # back into parent-local space
	_skel.set_bone_pose_rotation(b, local.get_rotation_quaternion())


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null
