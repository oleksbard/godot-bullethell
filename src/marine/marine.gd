class_name Marine
extends Node3D
## The marine's controller: WASD movement, combat facing, a walk cycle, and a
## clamp to the hell island's coastline. The body is the imported rigged model
## (models/marine_01.glb); this script instances it and drives its skeleton.
##
## Facing is decoupled from movement: the marine always turns to face the nearest
## imp (combat stance) while WASD still moves it in screen space — so it can
## strafe or backpedal while keeping the guns on the threat. The legs reverse
## their swing when moving backward relative to facing, so it reads as a
## backpedal rather than a moonwalk.
##
## The glb is rigged in a T-pose (arms straight out) with no real animations, so
## the pose is authored here:
##   * Legs swing front/back about their local X relative to rest.
##   * Arms are *aimed* forward into a two-handed "hold" so the hand bones sit out
##     front — the guns are bone-attached there (see get_hand_mounts()).
## Movement/turning happen on this root; the bob moves the *model's* local Y so
## the camera-followed root never shakes.

const IslandShape := preload("res://src/lib/island_shape.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const MODEL: PackedScene = preload("res://models/marine_01.glb")

const SPEED := 6.0
const TURN_SPEED := 12.0
const EDGE_MARGIN := 1.0

# Fitting the imported model. marine_01.glb faces +Z but Godot/the controller
# forward is -Z, so it needs a 180° yaw or it walks backward.
const MODEL_YAW := PI
const MODEL_Y_OFFSET := 0.0

# Walk + hold pose.
const WALK_FREQ := 9.0
const LEG_SWING := 0.6      # leg front/back swing (radians) at full speed
const ARM_OUT := 0.22       # sideways spread of the held hands
const ARM_DOWN := 0.45      # how far the held hands drop below the shoulders
const ARM_FWD := 0.9        # forward reach of the two-handed hold (dominant axis)
const ARM_SWING := 0.12     # subtle forward/back hand sway while walking
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
var _hand_mounts: Array[Node3D] = []   # BoneAttachment3D at the hands (guns hang here)
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

	# Bone-attached mounts at the hands; the WeaponRing parents the held guns here
	# so they ride the arms. Order is [right, left] to match gun slot order.
	_make_hand_mount("RightHand")
	_make_hand_mount("LeftHand")


## Bone-attached points at the hands, in [right, left] order. The WeaponRing's
## first guns parent here so they sit in the marine's grip. Empty if the rig has
## no hands (animation degrades to floating guns).
func get_hand_mounts() -> Array[Node3D]:
	return _hand_mounts


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
		move = Vector3(dir.x, 0.0, dir.y)          # screen-aligned: W = away from camera

	# Face the nearest imp (combat stance), independent of where we're moving.
	# Fall back to facing the movement direction when no imps are around.
	var enemy_dir := _nearest_enemy_dir()
	var target_yaw := rotation.y
	if enemy_dir != Vector3.ZERO:
		target_yaw = atan2(-enemy_dir.x, -enemy_dir.z)   # Godot forward is -Z
	elif move != Vector3.ZERO:
		target_yaw = atan2(-move.x, -move.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * TURN_SPEED, 0.0, 1.0))

	current_velocity = move * SPEED                 # world-space, decoupled from facing
	position += current_velocity * delta
	_clamp_to_island()


## Horizontal vector to the closest live imp (ZERO if none). Used for facing.
func _nearest_enemy_dir() -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if not is_instance_valid(imp):
			continue
		var to: Vector3 = (imp as Node3D).global_position - global_position
		to.y = 0.0
		var d := to.length_squared()
		if d > 0.0001 and d < best_d:
			best_d = d
			best = to
	return best


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

	# Reverse the leg swing when moving backward relative to facing, so a
	# backpedal reads as one instead of a forward strut. Strafe (~perpendicular)
	# keeps the forward sign — it just looks like a sideways shuffle.
	var dir_sign := 1.0
	if current_velocity.length() > 0.05:
		var fb := current_velocity.normalized().dot(-global_transform.basis.z)
		if fb < -0.05:
			dir_sign = -1.0

	var s := sin(_walk_phase) * _walk_amt
	_swing_bone(_b_lup, s * LEG_SWING * dir_sign)     # legs swing opposite each other
	_swing_bone(_b_rup, -s * LEG_SWING * dir_sign)
	_aim_arm(_b_larm, 1.0, -s)              # two-handed forward hold, slight sway with the walk
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


## Aim an upper arm into the two-handed forward hold (`side` = +1 left / -1
## right), with a forward/back `reach` (-1..1) folded in for the walk sway.
## Skeleton space: the character's front is +Z, left is +X, down is -Y, so the
## hold points mostly +Z (forward) and a little -Y (down).
func _aim_arm(b: int, side: float, reach: float) -> void:
	if not _arm.has(b):
		return
	var d: Dictionary = _arm[b]
	var target := Vector3(side * ARM_OUT, -ARM_DOWN, ARM_FWD + reach * ARM_SWING).normalized()
	var swing := Quaternion(d["dir"], target)              # global rotation: rest dir -> target
	var new_basis := Basis(swing) * (d["rb"] as Basis)     # bone's new global basis
	var local: Basis = (d["pinv"] as Basis) * new_basis    # back into parent-local space
	_skel.set_bone_pose_rotation(b, local.get_rotation_quaternion())


## Attach a BoneAttachment3D to a hand bone (no-op if the rig lacks it). It rides
## the bone's animated pose, so a gun parented here stays in the marine's hand.
func _make_hand_mount(bone_name: String) -> void:
	if _skel == null:
		return
	var bi := _skel.find_bone(bone_name)
	if bi == -1:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = bone_name
	_skel.add_child(att)
	_hand_mounts.append(att)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null
