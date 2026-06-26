class_name Marine
extends Node3D
## The marine's controller: WASD movement, combat facing, a walk cycle, and a
## clamp to the hell island's coastline. The body is the imported rigged model
## (models/marine_01.glb); this script instances it and drives its skeleton.
##
## Facing is decoupled from movement: the body only turns *while the player is
## moving*, and it turns toward the point "between" its two targeted imps so it
## sits centred with the arms splayed evenly. Standing still, the body holds and
## the arms keep tracking on their own. WASD moves it in screen space, so it can
## strafe or backpedal; the legs reverse their swing when moving backward relative
## to facing, so it reads as a backpedal rather than a moonwalk.
##
## The glb is rigged in a T-pose (arms straight out) with no real animations, so
## the pose is authored here:
##   * Legs swing front/back about their local X relative to rest.
##   * Each arm *aims at its own imp* (right hand → nearest, left → 2nd-nearest),
##     clamped to ARM_SPLAY off the body's facing. The guns are rigidly fixed in
##     the hands (see get_hand_mounts()), barrel aligned with the arm, so the
##     whole arm rotates to point the gun — the gun never twists on its own.
## Movement/turning happen on this root; the bob moves the *model's* local Y so
## the camera-followed root never shakes.

signal died                  # emitted once when health hits 0 (Main shows the game-over menu)

const IslandShape := preload("res://src/lib/island_shape.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const DamageNumberScript := preload("res://src/fx/damage_number.gd")
const BlobShadow := preload("res://src/fx/blob_shadow.gd")
const MODEL: PackedScene = preload("res://models/marine_01.glb")

const SPEED := 6.0
const TURN_SPEED := 12.0
const EDGE_MARGIN := 1.0

# Fitting the imported model. marine_01.glb faces +Z but Godot/the controller
# forward is -Z, so it needs a 180° yaw or it walks backward.
const MODEL_YAW := PI
const MODEL_Y_OFFSET := 0.0

# Walk + arm aim.
const WALK_FREQ := 9.0
const LEG_SWING := 0.6              # leg front/back swing (radians) at full speed
const ARM_SPLAY := deg_to_rad(85.0) # max each arm may swing off the body's facing
const ARM_DOWN_TILT := 0.25         # how far the aimed arms angle down toward the target
const AIM_SPEED := 7.0              # how fast an arm swings to a new target (some lag, not instant)
const ARM_CENTER_BAND := deg_to_rad(25.0)  # imps this near dead-ahead are fair game for either hand
const ARM_REST_FWD := 0.2           # idle arms hang down + a little forward
const ARM_REST_OUT := 0.12          # ...and splayed a little outward
const RIGHT_SIDE := -1.0            # right hand covers the dev<0 half-sphere (verified by render)
const LEFT_SIDE := 1.0              # left hand covers the dev>0 half-sphere
const GRIP_ROLL := deg_to_rad(0.0)   # spare: roll the held pistol about its barrel (0 = none)
const GRIP_YAW := deg_to_rad(0.0)  # flip the held pistol about its vertical axis so the muzzle points at the enemy, not back at the marine
const BOB_HEIGHT := 0.06

# Taking damage.
const HIT_FLASH_TIME := 0.12        # white hurt-flash duration (same idea as the imps')
const FLASH_ENERGY := 2.0           # peak emission energy of the flash
const DMG_NUMBER_COLOR := Color(1.0, 0.3, 0.2)   # red flying number for damage taken
const DEATH_FALL_TIME := 0.7        # how long the death topple takes

# Overhead health bar — a flat bar above the head, shown only when hurt (< 100%).
const OHB_WIDTH := 1.1
const OHB_HEIGHT := 0.15
const OHB_Y := 2.45                 # height above the marine's origin
const OHB_BG := Color(0.06, 0.01, 0.01)
const OHB_FILL := Color(0.85, 0.12, 0.08)

var current_velocity := Vector3.ZERO

var _model: Node3D
var _skel: Skeleton3D
var _b_lup := -1      # LeftUpLeg
var _b_rup := -1      # RightUpLeg
var _b_larm := -1     # LeftArm
var _b_rarm := -1     # RightArm
var _rest := {}       # leg bone idx -> rest rotation Quaternion
var _arm := {}        # arm bone idx -> aim data {pinv: Basis, rb: Basis, dir: Vector3}
var _hand_mounts: Array[Node3D] = []   # grip points at the hands (guns hang here)
var _sorted_imps: Array = []           # imps sorted nearest-first, refreshed per frame
var _hand_targets: Array = [null, null]  # [right, left] imp each hand covers (null = rest down)
var _r_dir := Vector3.FORWARD          # smoothed aim direction of the right arm
var _l_dir := Vector3.FORWARD          # smoothed aim direction of the left arm
var _walk_phase := 0.0
var _walk_amt := 0.0

var stats: Node                        # PlayerStats holding health/xp; set by Main
var inventory: Node                    # Inventory holding the grid loadout; set by Main
var _alive := true
var _flash_mats: Array[StandardMaterial3D] = []   # duplicated model materials we pulse white on hit
var _flash := 0.0                      # seconds left of the hurt-flash
var _hp_bar: Node3D                    # overhead health bar (flat, world-aligned, shown when hurt)
var _hp_fill_pivot: Node3D             # left-anchored fill, scaled by the health ratio


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

	# Grip points at the hands; the WeaponRing parents the held guns here so they
	# ride the arms. Order is [right, left] to match gun slot order.
	_make_hand_mount("RightHand", _b_rarm)
	_make_hand_mount("LeftHand", _b_larm)

	_setup_flash_mats()
	_build_overhead_bar()


## Duplicate each model material with emission enabled (energy 0) so a hit can pulse
## the whole marine white — the same hurt-flash the imps get.
func _setup_flash_mats() -> void:
	if _model == null:
		return
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		var base := inst.get_active_material(0)
		var dup: StandardMaterial3D = (base as StandardMaterial3D).duplicate() if base is StandardMaterial3D else StandardMaterial3D.new()
		dup.emission_enabled = true
		dup.emission = Color(1.0, 1.0, 1.0)
		dup.emission_energy_multiplier = 0.0
		inst.set_surface_override_material(0, dup)
		_flash_mats.append(dup)


## Grip points at the hands, in [right, left] order. The WeaponRing's first guns
## parent here so they sit in the marine's grip. Empty if the rig has no hands
## (animation degrades to floating guns).
func get_hand_mounts() -> Array[Node3D]:
	return _hand_mounts


func _process(delta: float) -> void:
	_update_flash(delta)         # runs even while dead, so the death flash plays
	if not _alive:
		return
	_refresh_targets()
	_pick_hand_targets()
	_handle_movement(delta)
	_animate_walk(delta)
	_aim_arms(delta)
	_update_overhead_bar()


## Marine took `amount` damage (from an imp). Flash white, pop a red flying number,
## drain the shared PlayerStats, and die when it hits 0.
func take_damage(amount: float) -> void:
	if not _alive:
		return
	_flash = HIT_FLASH_TIME
	DamageNumberScript.spawn(get_parent(), global_position + Vector3(0.0, 2.0, 0.0), amount, DMG_NUMBER_COLOR)
	if stats != null:
		stats.take_damage(amount)
		if stats.health <= 0.0:
			_die()


## Award XP from a collected loot orb — forwards to PlayerStats (which fills the HUD
## bar and may emit `leveled_up`). No-op once dead or before stats are set.
func gain_xp(amount: float) -> void:
	if not _alive or stats == null:
		return
	stats.add_xp(amount)


## Bank souls from a collected soul-mote — forwards to PlayerStats. No-op once dead.
func gain_souls(amount: int) -> void:
	if not _alive or stats == null:
		return
	stats.add_souls(amount)


## Health hit 0: stop combat, flash, topple over, and tell Main (which raises the
## game-over menu after the fall plays).
func _die() -> void:
	if not _alive:
		return
	_alive = false
	_flash = HIT_FLASH_TIME
	if _hp_bar != null:
		_hp_bar.visible = false          # hide the overhead bar once dead
	died.emit()
	if _model != null:
		var tw := _model.create_tween().set_parallel(true)
		tw.tween_property(_model, "rotation:x", -PI * 0.5, DEATH_FALL_TIME).set_ease(Tween.EASE_IN)
		tw.tween_property(_model, "position:y", MODEL_Y_OFFSET - 0.2, DEATH_FALL_TIME).set_ease(Tween.EASE_IN)


## Decay the white hurt-flash and push its energy onto the duplicated materials.
func _update_flash(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(_flash - delta, 0.0)
	var e := (_flash / HIT_FLASH_TIME) * FLASH_ENERGY
	for m in _flash_mats:
		m.emission_energy_multiplier = e


## A flat health bar above the head: dark backing + a left-anchored crimson fill.
## Lies in the XY plane (faces +Z); _update_overhead_bar orients it flat + up each
## frame. Hidden until the marine is hurt.
func _build_overhead_bar() -> void:
	_hp_bar = Node3D.new()
	add_child(_hp_bar)
	_hp_bar.visible = false
	_hp_bar.add_child(_bar_quad(OHB_WIDTH, OHB_HEIGHT, OHB_BG))

	_hp_fill_pivot = Node3D.new()
	_hp_fill_pivot.position.x = -OHB_WIDTH * 0.5         # pivot at the bar's left edge
	_hp_bar.add_child(_hp_fill_pivot)
	var fill := _bar_quad(OHB_WIDTH, OHB_HEIGHT * 0.78, OHB_FILL)
	fill.position = Vector3(OHB_WIDTH * 0.5, 0.0, 0.01)  # span pivot..pivot+W; +Z draws over the backing
	_hp_fill_pivot.add_child(fill)


## A flat unshaded coloured quad (centred), for the overhead bar.
func _bar_quad(w: float, h: float, col: Color) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	return mi


## Position the overhead bar flat above the head (world-aligned, never spinning with
## the body) and scale its fill to the current health. Shown only when hurt (< 100%).
func _update_overhead_bar() -> void:
	if _hp_bar == null:
		return
	if stats == null:
		_hp_bar.visible = false
		return
	var ratio := clampf(stats.health / maxf(stats.max_health, 0.001), 0.0, 1.0)
	_hp_bar.visible = ratio < 0.999
	_hp_fill_pivot.scale.x = ratio
	# Override the global transform so the bar stays flat + screen-aligned regardless
	# of the marine's facing, hovering above the head.
	_hp_bar.global_transform = Transform3D(
		Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)),
		global_position + Vector3(0.0, OHB_Y, 0.0))


## Pick the imp each hand covers: the nearest one on that hand's half-sphere
## (relative to the current facing), so the arms never cross. Imps near dead-ahead
## (within ARM_CENTER_BAND) are eligible for either hand. null = nothing to shoot
## on that side, so the hand rests down.
func _pick_hand_targets() -> void:
	var body_yaw := rotation.y
	_hand_targets[0] = _nearest_on_side(body_yaw, RIGHT_SIDE)
	_hand_targets[1] = _nearest_on_side(body_yaw, LEFT_SIDE)


func _nearest_on_side(body_yaw: float, want_sign: float) -> Node3D:
	for imp in _sorted_imps:                      # already nearest-first
		var to: Vector3 = (imp as Node3D).global_position - global_position
		to.y = 0.0
		if to.length_squared() < 0.0001:
			continue
		var dev := wrapf(atan2(-to.x, -to.z) - body_yaw, -PI, PI)
		if want_sign * dev >= -ARM_CENTER_BAND:   # on this hand's side (or in the centre band)
			return imp
	return null


## The imp a held gun should fire at (index 0 = right hand, 1 = left). The
## WeaponRing reads this so the held pistols shoot where the arms point.
func get_hand_target(index: int) -> Node3D:
	if index < 0 or index >= _hand_targets.size():
		return null
	var t: Variant = _hand_targets[index]
	# Guard: while the marine is dead _pick_hand_targets stops refreshing, so a cached
	# imp may have been freed since. Never hand back a freed instance.
	return t if is_instance_valid(t) else null


## Sort the live imps nearest-first once per frame; facing + per-arm aim read it.
func _refresh_targets() -> void:
	_sorted_imps.clear()
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if is_instance_valid(imp):
			_sorted_imps.append(imp)
	var origin := global_position
	_sorted_imps.sort_custom(func(a, b):
		return origin.distance_squared_to((a as Node3D).global_position) < origin.distance_squared_to((b as Node3D).global_position))


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

	# The body turns ONLY while moving, toward the midpoint between its two targeted
	# imps (so it stays centred and the arms splay evenly). Standing still it holds;
	# the arms keep tracking independently.
	if move != Vector3.ZERO:
		var target_yaw := _body_facing_yaw(move)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * TURN_SPEED, 0.0, 1.0))

	current_velocity = move * SPEED                 # world-space, decoupled from facing
	position += current_velocity * delta
	_clamp_to_island()


## Yaw to face the point "between" the two hands' targets (their bisector). Falls
## back to whichever hand has a target, then the movement direction, then the
## current heading.
func _body_facing_yaw(move: Vector3) -> float:
	var d0 := _dir_to(_hand_targets[0])
	var d1 := _dir_to(_hand_targets[1])
	if d0 != Vector3.ZERO and d1 != Vector3.ZERO:
		var bis := d0.normalized() + d1.normalized()
		if bis.length() > 0.05:
			return atan2(-bis.x, -bis.z)        # Godot forward is -Z
		return atan2(-d0.x, -d0.z)              # targets opposite — just face the right one
	if d0 != Vector3.ZERO:
		return atan2(-d0.x, -d0.z)
	if d1 != Vector3.ZERO:
		return atan2(-d1.x, -d1.z)
	if move != Vector3.ZERO:
		return atan2(-move.x, -move.z)
	return rotation.y


## Horizontal vector from the marine to `node` (ZERO if null/invalid/coincident).
func _dir_to(node: Node) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.ZERO
	var to: Vector3 = (node as Node3D).global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return Vector3.ZERO
	return to


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


## Swing each arm toward its own imp (right → nearest, left → 2nd-nearest),
## clamped to ARM_SPLAY off the body's facing and eased toward the new heading.
## Because the gun is fixed to the hand with its barrel along the arm, aiming the
## arm aims the gun.
func _aim_arms(delta: float) -> void:
	if _skel == null:
		return
	var body_yaw := rotation.y
	_r_dir = _aim_one(_b_rarm, _hand_targets[0], body_yaw, _r_dir, RIGHT_SIDE, delta)
	_l_dir = _aim_one(_b_larm, _hand_targets[1], body_yaw, _l_dir, LEFT_SIDE, delta)


## Ease arm bone `b` toward its desired heading and apply it. With a target it
## aims there (clamped to ARM_SPLAY off the facing); with none it drops to a
## natural rest down. Smoothing a direction vector makes aim↔rest blend cleanly.
func _aim_one(b: int, target: Node, body_yaw: float, cur_dir: Vector3, side: float, delta: float) -> Vector3:
	if not _arm.has(b):
		return cur_dir
	var desired: Vector3
	if is_instance_valid(target):
		var to: Vector3 = (target as Node3D).global_position - global_position
		to.y = 0.0
		var aim_yaw := atan2(-to.x, -to.z) if to.length_squared() > 0.0001 else body_yaw
		var final_yaw := splay_yaw(body_yaw, aim_yaw)
		desired = Vector3(-sin(final_yaw), -ARM_DOWN_TILT, -cos(final_yaw))
	else:
		desired = _rest_dir(body_yaw, side)        # nothing on this side -> hang down

	cur_dir = cur_dir.lerp(desired.normalized(), clampf(delta * AIM_SPEED, 0.0, 1.0))
	if cur_dir.length() < 0.001:
		cur_dir = desired
	cur_dir = cur_dir.normalized()
	var target_skel := (_skel.global_transform.basis.inverse() * cur_dir).normalized()
	_apply_arm(b, target_skel)
	return cur_dir


## Natural resting aim for an idle hand: mostly straight down, a little forward and
## a little out to its side, relative to the body's facing.
func _rest_dir(body_yaw: float, side: float) -> Vector3:
	var fwd := Vector3(-sin(body_yaw), 0.0, -cos(body_yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)       # body's right-ish (perpendicular)
	return (Vector3.DOWN + fwd * ARM_REST_FWD + right * (side * ARM_REST_OUT)).normalized()


## Clamp an aim yaw to within ARM_SPLAY of the body's facing. Pure, so it's testable.
static func splay_yaw(body_yaw: float, aim_yaw: float) -> float:
	var dev := clampf(wrapf(aim_yaw - body_yaw, -PI, PI), -ARM_SPLAY, ARM_SPLAY)
	return body_yaw + dev


## Rotate upper arm `b` so its rest pointing direction lines up with `target_skel`
## (a direction in skeleton space).
func _apply_arm(b: int, target_skel: Vector3) -> void:
	if not _arm.has(b):
		return
	var d: Dictionary = _arm[b]
	var swing := Quaternion(d["dir"], target_skel)         # rest dir -> target
	var new_basis := Basis(swing) * (d["rb"] as Basis)     # bone's new global basis
	var local: Basis = (d["pinv"] as Basis) * new_basis    # back into parent-local space
	_skel.set_bone_pose_rotation(b, local.get_rotation_quaternion())


## Attach a grip point at a hand bone, oriented so a gun parented there (identity
## local transform) has its barrel (-Z) aligned with the arm's pointing direction.
## Then aiming the arm aims the gun; the gun never rotates on its own. No-op if the
## rig lacks the hand bone or its arm wasn't cached.
func _make_hand_mount(hand_name: String, arm_bone: int) -> void:
	if _skel == null:
		return
	var hand_bi := _skel.find_bone(hand_name)
	if hand_bi == -1 or not _arm.has(arm_bone):
		return

	# Desired grip basis in skeleton space: -Z along the arm, +Y roughly up.
	var arm_dir: Vector3 = (_arm[arm_bone]["dir"] as Vector3).normalized()
	var z_axis := -arm_dir
	var up_hint := Vector3.UP
	if absf(z_axis.dot(up_hint)) > 0.95:
		up_hint = Vector3.FORWARD
	var x_axis := up_hint.cross(z_axis).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var desired := Basis(x_axis, y_axis, z_axis)
	# Roll about the barrel so the pistol's top faces up, and turn it about its
	# vertical axis so it points the right way.
	desired = desired * Basis(Vector3(0.0, 0.0, 1.0), GRIP_ROLL)
	desired = desired * Basis(Vector3(0.0, 1.0, 0.0), GRIP_YAW)
	var grip_local := _skel.get_bone_global_rest(hand_bi).basis.inverse() * desired

	var att := BoneAttachment3D.new()
	att.bone_name = hand_name
	_skel.add_child(att)
	var grip := Node3D.new()
	grip.basis = grip_local
	att.add_child(grip)
	_hand_mounts.append(grip)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null
