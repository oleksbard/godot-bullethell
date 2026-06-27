extends RefCounted
## Marine tests: rig, facing, hand assignment, walk, arm splay, damage, XP.
## Split from run_tests.gd. `t` is the shared TestContext.

const TestContext := preload("res://test/test_context.gd")
const MarineScript := preload("res://src/marine/marine.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const PlayerStatsScript := preload("res://src/marine/player_stats.gd")


func run(t: TestContext) -> void:
	await _test_marine_model(t)
	await _test_marine_faces_enemy(t)
	await _test_hand_sides(t)
	await _test_marine_backpedal(t)
	_test_arm_splay(t)
	_test_hand_target_freed(t)
	await _test_player_damage(t)
	await _test_marine_gain_xp(t)


func _test_marine_model(t: TestContext) -> void:
	t.suite = "Marine.model"
	var m: Node3D = MarineScript.new()
	t.root().add_child(m)
	await t.frame()                      # _ready() instances the glb + finds bones

	t.ok(m._skel != null, "instances a Skeleton3D from marine_01.glb")
	t.ok(m._b_lup != -1 and m._b_rup != -1 and m._b_larm != -1 and m._b_rarm != -1,
		"resolves the walk bones (LeftUpLeg/RightUpLeg/LeftArm/RightArm)")
	t.ok(m.get_hand_mounts().size() == 2, "attaches both hand mounts for held guns (got %d)" % m.get_hand_mounts().size())
	m.free()


func _test_marine_faces_enemy(t: TestContext) -> void:
	t.suite = "Marine.facing"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	# One imp on each side, both ahead (-Z) — the body should face between them (-Z).
	var a: Node3D = ImpScript.new()
	holder.add_child(a)
	a.global_position = Vector3(3.0, 0.0, -4.0)
	var b: Node3D = ImpScript.new()
	holder.add_child(b)
	b.global_position = Vector3(-3.0, 0.0, -4.0)
	await t.frame()                            # _ready: rig + imps join the group

	m._refresh_targets()
	m._pick_hand_targets()
	var yaw: float = m._body_facing_yaw(Vector3.ZERO)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var dot := fwd.dot(Vector3(0.0, 0.0, -1.0))
	t.ok(dot > 0.95, "body faces the midpoint between its two targets (dot %.2f)" % dot)
	holder.free()


func _test_hand_sides(t: TestContext) -> void:
	t.suite = "Marine.hands"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)                            # faces -Z (yaw 0): +X is its right
	var r: Node3D = ImpScript.new()
	holder.add_child(r)
	r.global_position = Vector3(4.0, 0.0, 0.0)     # right half
	var l: Node3D = ImpScript.new()
	holder.add_child(l)
	l.global_position = Vector3(-4.0, 0.0, 0.0)    # left half
	await t.frame()

	m._refresh_targets()
	m._pick_hand_targets()
	t.ok(m.get_hand_target(0) == r and m.get_hand_target(1) == l,
		"right hand takes the right-half imp, left takes the left — no crossing")

	# Move both imps to the right half: the left hand then has nothing (rests down).
	l.global_position = Vector3(5.0, 0.0, 0.0)
	m._refresh_targets()
	m._pick_hand_targets()
	t.ok(m.get_hand_target(1) == null, "a hand with no imp on its side has no target (rests down)")
	holder.free()


func _test_marine_backpedal(t: TestContext) -> void:
	t.suite = "Marine.backpedal"
	var m: Node3D = MarineScript.new()
	t.root().add_child(m)
	await t.frame()
	if m._skel == null or m._b_lup == -1:
		t.ok(false, "rig present for backpedal test")
		m.free()
		return

	m.rotation.y = -PI / 2.0          # forward (-Z) now points +X
	m._walk_amt = 1.0
	m._walk_phase = PI / 2.0          # sin = 1 -> max, deterministic swing

	m.current_velocity = Vector3(6.0, 0.0, 0.0)     # moving +X == forward
	m._animate_walk(0.0)                             # delta 0: don't advance the phase
	var fwd_pose: Quaternion = m._skel.get_bone_pose_rotation(m._b_lup)

	m._walk_phase = PI / 2.0
	m.current_velocity = Vector3(-6.0, 0.0, 0.0)    # moving -X == backpedal
	m._animate_walk(0.0)
	var back_pose: Quaternion = m._skel.get_bone_pose_rotation(m._b_lup)

	t.ok(not fwd_pose.is_equal_approx(back_pose), "leg swing reverses when backpedaling vs advancing")
	m.free()


func _test_arm_splay(t: TestContext) -> void:
	t.suite = "Marine.splay"
	# A small aim offset is followed exactly — the arm swings toward its target.
	var within := MarineScript.splay_yaw(0.0, 0.3)
	t.ok(is_equal_approx(within, 0.3), "a small aim offset is followed (%.2f rad)" % within)
	# An extreme aim is clamped so the arm doesn't over-rotate behind the body.
	var far := MarineScript.splay_yaw(0.0, 2.9)   # near 180° to the side
	t.ok(is_equal_approx(far, MarineScript.ARM_SPLAY),
		"an extreme aim clamps to ARM_SPLAY (%.2f rad)" % far)
	# Symmetric the other way, and offset by a non-zero body yaw.
	var neg := MarineScript.splay_yaw(1.0, 1.0 - 2.9)
	t.ok(is_equal_approx(neg, 1.0 - MarineScript.ARM_SPLAY),
		"clamps symmetrically around the body yaw (%.2f rad)" % neg)


func _test_hand_target_freed(t: TestContext) -> void:
	t.suite = "Marine.hand"
	var m: Node3D = MarineScript.new()            # not added; _hand_targets starts [null, null]
	var dummy := Node3D.new()
	m._hand_targets[0] = dummy
	dummy.free()                                  # simulate the imp dying after it was cached
	t.ok(m.get_hand_target(0) == null, "get_hand_target returns null for a freed imp (no crash)")
	t.ok(m.get_hand_target(1) == null, "get_hand_target returns null when the hand rests (no target)")
	m.free()


func _test_player_damage(t: TestContext) -> void:
	t.suite = "Marine.damage"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var stats: Node = PlayerStatsScript.new()
	stats.max_health = 10.0
	stats.health = 10.0
	m.add_child(stats)
	m.stats = stats
	var died := [false]
	m.died.connect(func(): died[0] = true)
	await t.frame()                           # _ready builds the model + flash mats

	m.take_damage(4.0)
	t.ok(is_equal_approx(stats.health, 6.0), "a hit drains player health (%.0f)" % stats.health)
	t.ok(not died[0], "player survives a non-lethal hit")
	m.take_damage(20.0)                       # overkill
	t.ok(stats.health <= 0.0 and died[0], "player dies at 0 HP and emits `died`")
	holder.free()


func _test_marine_gain_xp(t: TestContext) -> void:
	t.suite = "Marine.gain_xp"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var stats: Node = PlayerStatsScript.new()
	stats.xp = 0.0
	stats.xp_to_next = 100.0          # high so add_xp(7) doesn't wrap into a level-up
	m.add_child(stats)
	m.stats = stats
	await t.frame()               # _ready builds the model
	m.gain_xp(7.0)
	t.ok(is_equal_approx(stats.xp, 7.0), "gain_xp credits PlayerStats XP (%.1f)" % stats.xp)
	holder.free()
