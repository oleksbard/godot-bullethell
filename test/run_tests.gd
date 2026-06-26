extends SceneTree
## Zero-dependency headless test runner (mirrors the sibling godot-prototype).
##
## Run:  ./test/run_tests.sh
##  (or:  godot --headless --path . --script res://test/run_tests.gd)
##
## Exits 0 if all checks pass, 1 otherwise — CI-friendly. Pure logic runs
## synchronously; node behaviour needs the node in the tree + `await process_frame`
## so `_ready()` fires. See docs/guidelines/testing.md.

const IslandShape := preload("res://src/lib/island_shape.gd")
const MarineScript := preload("res://src/marine/marine.gd")
const PlayerStatsScript := preload("res://src/marine/player_stats.gd")
const WaveSpawnerScript := preload("res://src/enemies/wave_spawner.gd")
const WeaponRingScript := preload("res://src/weapons/weapon_ring.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const PortalScript := preload("res://src/fx/portal.gd")
const ProjectileScript := preload("res://src/fx/projectile.gd")
const GunScript := preload("res://src/weapons/gun.gd")
const ShotSfxScript := preload("res://src/audio/shot_sfx.gd")
const ImpactSfxScript := preload("res://src/audio/impact_sfx.gd")
const XpOrbScript := preload("res://src/loot/xp_orb.gd")
const XpOrbFieldScript := preload("res://src/loot/xp_orb_field.gd")
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const InventoryGridScript := preload("res://src/inventory/inventory_grid.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")
const GridViewScript := preload("res://src/ui/grid_view.gd")
const ItemTooltipScript := preload("res://src/ui/item_tooltip.gd")
const LevelUpMenuScript := preload("res://src/ui/level_up_menu.gd")
const HudScript := preload("res://src/ui/hud.gd")

var _passed := 0
var _failed := 0
var _suite := ""


func _initialize() -> void:
	print("── running tests ──")
	_test_island_shape()
	_test_inventory_item()
	_test_inventory_grid()
	_test_inventory()
	_test_item_tooltip()
	_test_grid_view()
	_test_marine_clamp()
	await _test_marine_model()
	await _test_marine_faces_enemy()
	await _test_hand_sides()
	await _test_marine_backpedal()
	await _test_wave_spawner()
	await _test_weapon_ring()
	await _test_imp_die()
	await _test_imp_take_damage()
	await _test_imp_xp_drop()
	await _test_xp_orb()
	await _test_xp_orb_field()
	await _test_imp_hit_react()
	await _test_imp_emerge()
	await _test_player_damage()
	await _test_marine_gain_xp()
	await _test_imp_attack()
	await _test_portal_fail()
	await _test_projectile_kills()
	await _test_wave_progression()
	await _test_wave_signals()
	await _test_gun_range()
	await _test_weapon_ring_inventory()
	_test_arm_splay()
	await _test_imp_separation()
	await _test_projectile_hits_path()
	await _test_projectile_misses()
	await _test_shot_sfx()
	await _test_impact_sfx()
	await _test_level_up_menu()
	await _test_hud_clear_medals()
	await _test_hud_xp_animation()
	await _test_souls()
	print("──")
	print("%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_island_shape() -> void:
	_suite = "IslandShape"
	var in_bounds := true
	for i in 360:
		var r := IslandShape.radius(deg_to_rad(float(i)))
		if r < IslandShape.BASE * 0.6 or r > IslandShape.BASE * 1.4:
			in_bounds = false
	_ok(in_bounds, "radius() stays within [0.6, 1.4] * BASE for all angles")
	_ok(is_equal_approx(IslandShape.radius(0.5), IslandShape.radius(0.5 + TAU)),
		"radius() is periodic over TAU")


func _test_marine_clamp() -> void:
	_suite = "Marine.clamp"
	var m: Node3D = MarineScript.new()       # not added to tree: _ready/rig not needed
	m.position = Vector3(50.0, 0.0, 30.0)    # far outside the island
	m._clamp_to_island()
	var d := Vector2(m.position.x, m.position.z).length()
	var ang := atan2(m.position.z, m.position.x)
	var max_r: float = IslandShape.radius(ang) - MarineScript.EDGE_MARGIN
	_ok(d <= max_r + 0.01, "clamp pulls an outside point onto the island")

	var inside := Vector3(1.0, 0.0, 1.0)
	m.position = inside
	m._clamp_to_island()
	_ok(m.position.is_equal_approx(inside), "clamp leaves an inside point untouched")
	m.free()


func _test_marine_model() -> void:
	_suite = "Marine.model"
	var m: Node3D = MarineScript.new()
	get_root().add_child(m)
	await process_frame                      # _ready() instances the glb + finds bones

	_ok(m._skel != null, "instances a Skeleton3D from marine_01.glb")
	_ok(m._b_lup != -1 and m._b_rup != -1 and m._b_larm != -1 and m._b_rarm != -1,
		"resolves the walk bones (LeftUpLeg/RightUpLeg/LeftArm/RightArm)")
	_ok(m.get_hand_mounts().size() == 2, "attaches both hand mounts for held guns (got %d)" % m.get_hand_mounts().size())
	m.free()


func _test_marine_faces_enemy() -> void:
	_suite = "Marine.facing"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	# One imp on each side, both ahead (-Z) — the body should face between them (-Z).
	var a: Node3D = ImpScript.new()
	holder.add_child(a)
	a.global_position = Vector3(3.0, 0.0, -4.0)
	var b: Node3D = ImpScript.new()
	holder.add_child(b)
	b.global_position = Vector3(-3.0, 0.0, -4.0)
	await process_frame                            # _ready: rig + imps join the group

	m._refresh_targets()
	m._pick_hand_targets()
	var yaw: float = m._body_facing_yaw(Vector3.ZERO)
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var dot := fwd.dot(Vector3(0.0, 0.0, -1.0))
	_ok(dot > 0.95, "body faces the midpoint between its two targets (dot %.2f)" % dot)
	holder.free()


func _test_hand_sides() -> void:
	_suite = "Marine.hands"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)                            # faces -Z (yaw 0): +X is its right
	var r: Node3D = ImpScript.new()
	holder.add_child(r)
	r.global_position = Vector3(4.0, 0.0, 0.0)     # right half
	var l: Node3D = ImpScript.new()
	holder.add_child(l)
	l.global_position = Vector3(-4.0, 0.0, 0.0)    # left half
	await process_frame

	m._refresh_targets()
	m._pick_hand_targets()
	_ok(m.get_hand_target(0) == r and m.get_hand_target(1) == l,
		"right hand takes the right-half imp, left takes the left — no crossing")

	# Move both imps to the right half: the left hand then has nothing (rests down).
	l.global_position = Vector3(5.0, 0.0, 0.0)
	m._refresh_targets()
	m._pick_hand_targets()
	_ok(m.get_hand_target(1) == null, "a hand with no imp on its side has no target (rests down)")
	holder.free()


func _test_marine_backpedal() -> void:
	_suite = "Marine.backpedal"
	var m: Node3D = MarineScript.new()
	get_root().add_child(m)
	await process_frame
	if m._skel == null or m._b_lup == -1:
		_ok(false, "rig present for backpedal test")
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

	_ok(not fwd_pose.is_equal_approx(back_pose), "leg swing reverses when backpedaling vs advancing")
	m.free()


func _test_wave_spawner() -> void:
	_suite = "WaveSpawner"
	var sp: Node3D = WaveSpawnerScript.new()
	sp.player = Node3D.new()
	get_root().add_child(sp.player)
	get_root().add_child(sp)                  # _ready() starts dripping in wave 1
	_pump_spawn(sp, 15)

	var imps := get_nodes_in_group("imps")    # self is the SceneTree
	_ok(imps.size() == 15, "wave 1 drips in to 15 imps (got %d)" % imps.size())

	var all_inside := true
	for imp in imps:
		var p: Vector3 = (imp as Node3D).position
		var ang := atan2(p.z, p.x)
		if Vector2(p.x, p.z).length() > IslandShape.radius(ang):
			all_inside = false
	_ok(all_inside, "every imp spawns inside the coastline")

	var sp_player: Node = sp.player
	sp.free()                                 # frees the imps too
	sp_player.free()


func _test_weapon_ring() -> void:
	_suite = "WeaponRing"
	var wr: Node3D = WeaponRingScript.new()
	wr.gun_count = 6
	wr.player = Node3D.new()
	get_root().add_child(wr.player)
	get_root().add_child(wr)
	await process_frame
	_ok(wr._guns.size() == 6, "builds the requested gun count (got %d)" % wr._guns.size())

	var wr2: Node3D = WeaponRingScript.new()
	wr2.gun_count = 99                         # over the max
	wr2.player = Node3D.new()
	get_root().add_child(wr2.player)
	get_root().add_child(wr2)
	await process_frame
	_ok(wr2._guns.size() == 12, "clamps gun count to 12 (got %d)" % wr2._guns.size())

	var p1: Node = wr.player
	var p2: Node = wr2.player
	wr.free(); wr2.free()
	p1.free(); p2.free()


func _test_imp_die() -> void:
	_suite = "Imp.die"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	holder.add_child(imp)
	await process_frame
	_ok(get_nodes_in_group("imps").has(imp), "imp registers in the 'imps' group")

	var blood_before := get_nodes_in_group("blood").size()
	imp.die(4)                                # killer passes the blood amount (projectile type)
	_ok(get_nodes_in_group("imps").size() == 0, "die() removes it from the target group")
	# n directional spray decals + 1 round impact pool laid on top.
	_ok(get_nodes_in_group("blood").size() - blood_before == 5,
		"die(n) spawns n spray decals + 1 impact pool (%d new)" % (get_nodes_in_group("blood").size() - blood_before))
	await process_frame                       # let the queued free run
	holder.free()                             # frees gibs + blood too


func _test_imp_take_damage() -> void:
	_suite = "Imp.take_damage"
	var holder := Node3D.new()
	get_root().add_child(holder)

	# A tougher (later-wave) imp survives a hit it can't yet afford, then dies.
	var imp: Node3D = ImpScript.new()
	imp.max_hp = 6.0
	imp.hp = 6.0
	holder.add_child(imp)
	await process_frame
	var blood_before := get_nodes_in_group("blood").size()
	imp.take_damage(GunScript.DAMAGE)             # one 5-dmg bolt — not enough vs 6 HP
	_ok(get_nodes_in_group("imps").has(imp), "6-HP imp survives a single 5-dmg bolt")
	_ok(get_nodes_in_group("blood").size() - blood_before == 1,
		"a non-lethal hit leaves exactly 1 blood decal (%d new)" % (get_nodes_in_group("blood").size() - blood_before))
	imp.take_damage(GunScript.DAMAGE)             # second bolt finishes it (10 >= 6)
	_ok(get_nodes_in_group("imps").size() == 0, "second bolt drops it (HP <= 0 -> die)")

	# A base-HP imp dies to one pistol bolt (dmg 5 >= BASE_HP 3).
	var base: Node3D = ImpScript.new()
	holder.add_child(base)
	await process_frame
	base.take_damage(GunScript.DAMAGE)
	_ok(base.is_queued_for_deletion(),
		"base imp (%d HP) dies to one pistol bolt (dmg %d)" % [int(ImpScript.BASE_HP), int(GunScript.DAMAGE)])

	await process_frame
	holder.free()


func _test_imp_xp_drop() -> void:
	_suite = "Imp.xp"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	imp.xp_value = 9.0
	holder.add_child(imp)
	await process_frame
	var got := [Vector3.ZERO, -1.0]                  # [pos, xp]
	imp.died.connect(func(pos: Vector3, xp: float) -> void: got[0] = pos; got[1] = xp)
	imp.global_position = Vector3(3.0, 0.0, 1.0)
	imp.die()
	_ok(is_equal_approx(got[1], 9.0), "imp emits its xp_value on death (%.1f)" % got[1])
	_ok(got[0].is_equal_approx(Vector3(3.0, 0.0, 1.0)), "imp emits its death position")
	await process_frame                              # let the queued free run
	holder.free()


func _test_xp_orb() -> void:
	_suite = "XpOrb"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var player := Node3D.new()
	holder.add_child(player)                          # at origin

	# In magnet range -> flies toward the marine.
	var orb: Node3D = XpOrbScript.new()
	orb.player = player
	holder.add_child(orb)
	orb.set_process(false)
	orb.global_position = Vector3(2.0, 0.5, 0.0)      # dist 2 < MAGNET, > COLLECT
	await process_frame
	var d0 := orb.global_position.distance_to(player.global_position)
	for i in 5:
		orb._process(0.05)
	var d1 := orb.global_position.distance_to(player.global_position)
	_ok(d1 < d0 - 0.1, "an orb within magnet range flies toward the marine (%.2f -> %.2f)" % [d0, d1])
	orb.free()

	# Out of magnet range -> stays put; vacuum() overrides that.
	var orb2: Node3D = XpOrbScript.new()
	orb2.player = player
	holder.add_child(orb2)
	orb2.set_process(false)
	orb2.global_position = Vector3(10.0, 0.5, 0.0)    # dist 10 > MAGNET
	await process_frame
	var e0 := orb2.global_position.distance_to(player.global_position)
	for i in 5:
		orb2._process(0.05)
	var e1 := orb2.global_position.distance_to(player.global_position)
	_ok(absf(e1 - e0) < 0.1, "an orb beyond magnet range stays put (%.2f -> %.2f)" % [e0, e1])
	orb2.vacuum()
	for i in 5:
		orb2._process(0.05)
	var e2 := orb2.global_position.distance_to(player.global_position)
	_ok(e2 < e0 - 0.1, "vacuum() pulls a far orb toward the marine (%.2f)" % e2)
	orb2.free()

	# Within collect range -> credits XP once and frees itself.
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var st: Node = PlayerStatsScript.new()
	st.xp = 0.0
	st.xp_to_next = 100.0
	m.add_child(st)
	m.stats = st
	await process_frame
	var orb3: Node3D = XpOrbScript.new()
	orb3.player = m
	orb3.xp_value = 5.0
	holder.add_child(orb3)
	orb3.set_process(false)
	orb3.global_position = m.global_position + Vector3(0.3, 0.0, 0.0)   # within COLLECT
	await process_frame
	orb3._process(0.05)
	_ok(orb3.is_queued_for_deletion(), "an orb within collect range is collected (freed)")
	_ok(is_equal_approx(st.xp, 5.0), "collecting an orb credits the player's XP (%.1f)" % st.xp)
	_ok(st.souls == 1, "collecting an orb banks one soul (souls %d)" % st.souls)
	holder.free()


func _test_xp_orb_field() -> void:
	_suite = "XpOrbField"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var player := Node3D.new()
	holder.add_child(player)
	var field: Node3D = XpOrbFieldScript.new()
	field.player = player
	holder.add_child(field)

	var imp: Node3D = ImpScript.new()
	imp.xp_value = 4.0
	holder.add_child(imp)
	await process_frame
	field.on_imp_spawned(imp)                         # what Main wires to spawner.imp_spawned

	var before := field.get_child_count()
	imp.global_position = Vector3(2.0, 0.0, 0.0)
	imp.die()                                         # emits died -> field.drop_orb
	_ok(field.get_child_count() == before + 1, "a tracked imp's death drops one orb into the field")

	var orb := field.get_child(field.get_child_count() - 1)
	orb.set_process(false)
	field.vacuum_all()
	_ok(orb._vacuum, "vacuum_all() flags every orb to fly in")

	await process_frame
	holder.free()


func _test_imp_hit_react() -> void:
	_suite = "Imp.hit"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	imp.max_hp = 10.0
	imp.hp = 10.0                                  # tough enough to survive the test hit
	holder.add_child(imp)
	await process_frame                            # _ready builds the model + _anim_mats
	imp.global_position = Vector3(5.0, 0.0, 0.0)

	imp.take_damage(2.0, 1, Vector3(1.0, 0.0, 0.0))   # non-lethal, bolt travelling +X
	_ok(not imp._dead, "a non-lethal hit doesn't kill")
	_ok(imp._knock.x > 0.1, "hit shoves the imp along the bolt's travel (knockback)")
	_ok(imp._slow > 0.0 and imp._hit_flash > 0.0, "hit triggers a brief slow + flash")

	for i in 20:
		imp._update_hit_flash(0.05)                # ~1s later
	_ok(imp._hit_flash == 0.0, "the hurt-flash decays back to zero")
	holder.free()


func _test_projectile_kills() -> void:
	_suite = "Projectile"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	holder.add_child(imp)
	imp.global_position = Vector3(5.0, 0.0, 0.0)
	var p: Node3D = ProjectileScript.new()
	p.target = imp
	holder.add_child(p)
	p.global_position = Vector3(0.0, 0.6, 0.0)
	await process_frame

	var killed := false
	for i in 200:
		p._process(0.05)                      # step the bolt toward the imp
		if imp.is_queued_for_deletion():
			killed = true
			break
	_ok(killed, "a bolt reaches its target imp and kills it")
	await process_frame
	holder.free()


func _test_wave_progression() -> void:
	_suite = "WaveSpawner.waves"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var sp: Node3D = WaveSpawnerScript.new()
	sp.player = Node3D.new()
	holder.add_child(sp.player)
	holder.add_child(sp)                      # _ready -> starts dripping in wave 1

	_pump_spawn(sp, 15)
	_ok(get_nodes_in_group("imps").size() == 15, "wave 1 drips in to 15 imps (got %d)" % get_nodes_in_group("imps").size())
	var w1_interval: float = sp._spawn_interval

	for imp in get_nodes_in_group("imps"):
		imp.die()                             # clear the field; die() leaves the group at once
	sp._process(0.1)                          # notices the wave is clear -> starts the gap
	sp._process(WaveSpawnerScript.WAVE_DELAY + 0.1) # gap elapses -> next wave begins
	_pump_spawn(sp, 30)
	_ok(get_nodes_in_group("imps").size() == 30, "next wave doubles to 30 (got %d)" % get_nodes_in_group("imps").size())
	_ok(sp._spawn_interval < w1_interval,
		"wave 2 drips faster than wave 1 (%.2f < %.2f s)" % [sp._spawn_interval, w1_interval])

	await process_frame
	holder.free()


func _test_wave_signals() -> void:
	_suite = "WaveSpawner.signals"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var sp: Node3D = WaveSpawnerScript.new()
	sp.player = Node3D.new()
	holder.add_child(sp.player)

	var started := [0]
	var spawned := [0]
	var cleared := [0]
	var first_xp := [-1.0]
	sp.wave_started.connect(func(w: int) -> void: started[0] = w)
	sp.imp_spawned.connect(func(imp: Node) -> void:
		spawned[0] += 1
		if first_xp[0] < 0.0:
			first_xp[0] = imp.xp_value)
	sp.wave_cleared.connect(func() -> void: cleared[0] += 1)

	holder.add_child(sp)                              # _ready -> _start_wave(15) -> wave_started(1)
	_ok(started[0] == 1, "wave_started fires with wave 1 on ready (got %d)" % started[0])

	_pump_spawn(sp, 15)
	_ok(spawned[0] == 15, "imp_spawned fires once per spawned imp (got %d)" % spawned[0])
	_ok(is_equal_approx(first_xp[0], ImpScript.BASE_XP),
		"a wave-1 imp carries BASE_XP (%.1f)" % first_xp[0])

	for imp in get_nodes_in_group("imps"):
		imp.die()
	sp._process(0.1)                                  # notices the field is clear
	_ok(cleared[0] == 1, "wave_cleared fires when the field clears (got %d)" % cleared[0])

	await process_frame
	holder.free()


## Step the spawner until it has dripped in `target` imps (each _process spawns
## at most one, on the wave's interval).
func _pump_spawn(sp: Node, target: int) -> void:
	for i in 500:
		if get_nodes_in_group("imps").size() >= target:
			return
		sp._process(0.2)


func _test_imp_emerge() -> void:
	_suite = "Imp.emerge"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var player := Node3D.new()
	holder.add_child(player)                  # at origin
	var imp: Node3D = ImpScript.new()
	imp.player = player
	holder.add_child(imp)
	imp.global_position = Vector3(8.0, 0.0, 0.0)
	imp.emerge(1.0)
	await process_frame

	var start := imp.global_position
	for i in 10:
		imp._process(0.05)                    # 0.5s elapsed (< emerge time) -> frozen
	_ok(imp.global_position.distance_to(start) < 0.01, "imp stays put while in the portal")
	_ok(imp.scale.x < 1.0, "imp is still scaling up mid-emerge (%.2f)" % imp.scale.x)

	for i in 30:
		imp._process(0.05)                    # past 1s -> emerged, free to hunt
	_ok(imp.global_position.distance_to(start) > 0.5, "imp moves once it has emerged")
	holder.free()


func _test_portal_fail() -> void:
	_suite = "Portal.fail"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	holder.add_child(imp)
	var portal: Node3D = PortalScript.new()
	portal.imp = imp                          # set before add_child so _ready watches it
	holder.add_child(portal)
	await process_frame

	_ok(not portal._failed, "portal is steady while its imp lives")
	imp.free()                                # imp killed before it finished emerging
	portal._process(0.05)
	_ok(portal._failed, "portal fails when its imp dies while the portal is active")
	holder.free()


func _test_player_damage() -> void:
	_suite = "Marine.damage"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var stats: Node = PlayerStatsScript.new()
	stats.max_health = 10.0
	stats.health = 10.0
	m.add_child(stats)
	m.stats = stats
	var died := [false]
	m.died.connect(func(): died[0] = true)
	await process_frame                       # _ready builds the model + flash mats

	m.take_damage(4.0)
	_ok(is_equal_approx(stats.health, 6.0), "a hit drains player health (%.0f)" % stats.health)
	_ok(not died[0], "player survives a non-lethal hit")
	m.take_damage(20.0)                       # overkill
	_ok(stats.health <= 0.0 and died[0], "player dies at 0 HP and emits `died`")
	holder.free()


func _test_marine_gain_xp() -> void:
	_suite = "Marine.gain_xp"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var stats: Node = PlayerStatsScript.new()
	stats.xp = 0.0
	stats.xp_to_next = 100.0          # high so add_xp(7) doesn't wrap into a level-up
	m.add_child(stats)
	m.stats = stats
	await process_frame               # _ready builds the model
	m.gain_xp(7.0)
	_ok(is_equal_approx(stats.xp, 7.0), "gain_xp credits PlayerStats XP (%.1f)" % stats.xp)
	holder.free()


func _test_imp_attack() -> void:
	_suite = "Imp.attack"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var stats: Node = PlayerStatsScript.new()
	stats.max_health = 50.0
	stats.health = 50.0
	m.add_child(stats)
	m.stats = stats
	var imp: Node3D = ImpScript.new()
	imp.player = m
	imp.attack_damage = 3.0
	holder.add_child(imp)
	await process_frame
	imp.global_position = m.global_position + Vector3(0.5, 0.0, 0.0)   # inside ATTACK_RANGE

	var before: float = stats.health
	for i in 12:
		imp._process(0.1)                     # > ATTACK_COOLDOWN -> lands at least one hit
	_ok(stats.health < before, "an imp in melee range damages the player (%.0f -> %.0f)" % [before, stats.health])
	holder.free()


func _test_gun_range() -> void:
	_suite = "WeaponRing.range"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var player := Node3D.new()
	holder.add_child(player)
	var near: Node3D = ImpScript.new()
	holder.add_child(near)
	near.global_position = Vector3(5.0, 0.0, 0.0)        # within MAX_RANGE
	var far: Node3D = ImpScript.new()
	holder.add_child(far)
	far.global_position = Vector3(40.0, 0.0, 0.0)        # well beyond MAX_RANGE
	near.set_process(false)                              # keep them put
	far.set_process(false)
	var wr: Node3D = WeaponRingScript.new()
	wr.gun_count = 2
	wr.player = player
	holder.add_child(wr)
	await process_frame
	await process_frame

	_ok(wr._guns[0]._target == near, "the in-range closest imp is targeted")
	_ok(wr._guns[0]._target != far and wr._guns[1]._target != far,
		"the out-of-range imp is never targeted")
	holder.free()


func _test_weapon_ring_inventory() -> void:
	_suite = "WeaponRing.inventory"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var inv: Node = InventoryScript.build()
	m.add_child(inv)
	m.inventory = inv
	var wr: Node3D = WeaponRingScript.new()
	wr.player = m
	holder.add_child(wr)
	await process_frame
	_ok(wr._guns.size() == 2, "ring builds 2 guns from the 2 equipped pistols (got %d)" % wr._guns.size())

	var p: Object = inv.equipped_pistols()[0]
	inv.pick_up(inv.backpack, p)                 # unequip one -> changed -> rebuild
	_ok(wr._guns.size() == 1, "removing a backpack pistol drops a gun (got %d)" % wr._guns.size())

	inv.drop(inv.stash, p, Vector2i(0, 0))       # parked in the stash: still unequipped
	_ok(wr._guns.size() == 1, "a stashed pistol stays unequipped (got %d)" % wr._guns.size())
	holder.free()


func _test_arm_splay() -> void:
	_suite = "Marine.splay"
	# A small aim offset is followed exactly — the arm swings toward its target.
	var within := MarineScript.splay_yaw(0.0, 0.3)
	_ok(is_equal_approx(within, 0.3), "a small aim offset is followed (%.2f rad)" % within)
	# An extreme aim is clamped so the arm doesn't over-rotate behind the body.
	var far := MarineScript.splay_yaw(0.0, 2.9)   # near 180° to the side
	_ok(is_equal_approx(far, MarineScript.ARM_SPLAY),
		"an extreme aim clamps to ARM_SPLAY (%.2f rad)" % far)
	# Symmetric the other way, and offset by a non-zero body yaw.
	var neg := MarineScript.splay_yaw(1.0, 1.0 - 2.9)
	_ok(is_equal_approx(neg, 1.0 - MarineScript.ARM_SPLAY),
		"clamps symmetrically around the body yaw (%.2f rad)" % neg)


func _test_imp_separation() -> void:
	_suite = "Imp.separation"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var player: Node3D = Node3D.new()    # at origin; both imps start inside STOP_DIST
	holder.add_child(player)
	var a: Node3D = ImpScript.new()
	holder.add_child(a)
	a.global_position = Vector3(0.2, 0.0, 0.0)
	var b: Node3D = ImpScript.new()
	holder.add_child(b)
	b.global_position = Vector3(-0.2, 0.0, 0.0)
	a.player = player
	b.player = player
	await process_frame                  # _ready -> both in the group

	var before := a.global_position.distance_to(b.global_position)
	for i in 40:
		a._process(0.05)
		b._process(0.05)
	var after := a.global_position.distance_to(b.global_position)
	_ok(after > before + 0.5, "overlapping imps push apart (%.2f -> %.2f)" % [before, after])
	holder.free()


func _test_projectile_hits_path() -> void:
	_suite = "Projectile.path"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var blocker: Node3D = ImpScript.new()
	holder.add_child(blocker)
	blocker.global_position = Vector3(2.0, 0.0, 0.0)     # in the path, closer
	var assigned: Node3D = ImpScript.new()
	holder.add_child(assigned)
	assigned.global_position = Vector3(10.0, 0.0, 0.0)   # the target, farther, same line
	blocker.set_process(false)
	assigned.set_process(false)
	var p: Node3D = ProjectileScript.new()
	p.target = assigned
	holder.add_child(p)
	p.global_position = Vector3(0.0, 0.6, 0.0)
	await process_frame

	for i in 200:
		p._process(0.016)
		if blocker.is_queued_for_deletion() or assigned.is_queued_for_deletion():
			break
	_ok(blocker.is_queued_for_deletion() and not assigned.is_queued_for_deletion(),
		"bolt hits the imp in its path, not only its assigned target")
	holder.free()


func _test_projectile_misses() -> void:
	_suite = "Projectile.miss"
	var holder := Node3D.new()
	get_root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	holder.add_child(imp)
	imp.global_position = Vector3(0.0, 0.0, -10.0)   # straight ahead (-Z), far off
	imp.set_process(false)
	var p: Node3D = ProjectileScript.new()
	p.target = imp
	holder.add_child(p)
	p.global_position = Vector3(0.0, 0.6, 0.0)
	await process_frame

	p._process(0.016)                                 # locks heading toward -Z
	imp.global_position = Vector3(20.0, 0.0, -10.0)   # imp dodges off the bolt's line

	var hit := false
	for i in 200:
		p._process(0.05)
		if imp.is_queued_for_deletion():
			hit = true
			break
	_ok(not hit, "a bolt flies straight and misses a target that left its path")
	holder.free()


func _test_shot_sfx() -> void:
	_suite = "ShotSfx"
	var s: Node = ShotSfxScript.new()
	get_root().add_child(s)
	await process_frame                  # _ready loads the clips + pool
	var loaded: int = s._streams.size()
	var all_valid: bool = loaded == 5
	for st in s._streams:
		if st == null:
			all_valid = false
	_ok(all_valid, "loads all 5 pistol clips (got %d)" % loaded)
	# Evened volumes: the quietest clip (05) gets boosted well above the loudest (01).
	_ok(s._volumes.size() == 5 and s._volumes[4] > s._volumes[0] + 10.0,
		"per-clip trims even the levels (loud %.1f dB vs quiet %.1f dB)" % [s._volumes[0], s._volumes[4]])
	s.play()                             # must not error even with no audio device
	_ok(true, "play() runs without error")
	s.free()


func _test_impact_sfx() -> void:
	_suite = "ImpactSfx"
	var s: Node = ImpactSfxScript.new()
	get_root().add_child(s)
	await process_frame                  # _ready loads the clips + pool
	var loaded: int = s._streams.size()
	var all_valid: bool = loaded == 3
	for st in s._streams:
		if st == null:
			all_valid = false
	_ok(all_valid, "loads all 3 impact clips (got %d)" % loaded)
	_ok(ImpactSfxScript.IMPACT_DB < ShotSfxScript.MASTER_DB,
		"impact is quieter than the shot level (%.1f < %.1f dB)" % [ImpactSfxScript.IMPACT_DB, ShotSfxScript.MASTER_DB])
	s.play()                             # must not error even with no audio device
	_ok(true, "play() runs without error")
	s.free()


func _test_inventory_item() -> void:
	_suite = "InventoryItem"
	var p := InventoryItemScript.pistol()
	_ok(p.kind == InventoryItemScript.Kind.PISTOL, "pistol() is a PISTOL")
	_ok(_sorted_cells(p.cells()) == _sorted_cells([
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]),
		"rot 0 is the base L (X./X./XX)")

	p.rot = 2
	_ok(_sorted_cells(p.cells()) == _sorted_cells([
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)]),
		"rot 2 (180) is the right-hand pistol (XX/.X/.X)")

	# All four rotations are 4 cells and distinct shapes.
	var shapes := {}
	for r in 4:
		p.rot = r
		_ok(p.cells().size() == 4, "rot %d keeps 4 cells" % r)
		shapes[str(_sorted_cells(p.cells()))] = true
	_ok(shapes.size() == 4, "the four rotations are distinct (%d)" % shapes.size())


func _test_inventory_grid() -> void:
	_suite = "InventoryGrid"
	# The backpack shape: _OO_ / OOOO / OOOO / OOOO
	var cells: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
	var g := InventoryGridScript.from_cells(cells)

	var left := InventoryItemScript.pistol()           # rot 0 down the left column
	_ok(g.fits(left, Vector2i(0, 1)), "left pistol fits at (0,1)")
	_ok(not g.fits(left, Vector2i(0, 0)), "pistol at (0,0) hits the top-row hole -> rejected")
	_ok(not g.fits(left, Vector2i(3, 1)), "pistol off the right edge -> rejected")

	g.place(left, Vector2i(0, 1))
	_ok(g.item_at(Vector2i(0, 1)) == left, "place records occupancy")

	var right := InventoryItemScript.pistol()
	right.rot = 2                                       # 180° L down the right column
	_ok(g.fits(right, Vector2i(2, 1)), "right pistol fits at (2,1) beside the left one")
	g.place(right, Vector2i(2, 1))
	_ok(g.items_in_reading_order().size() == 2, "two distinct items placed")

	var extra := InventoryItemScript.pistol()
	_ok(not g.fits(extra, Vector2i(0, 1)), "overlapping an existing item -> rejected")
	_ok(g.fits(left, Vector2i(0, 1), left), "an item fits over its own cells (ignore=self)")

	g.remove(left)
	_ok(g.item_at(Vector2i(0, 1)) == null, "remove clears occupancy")
	_ok(g.items_in_reading_order().size() == 1, "one item left after remove")


func _test_inventory() -> void:
	_suite = "Inventory"
	var inv: Node = InventoryScript.build()
	_ok(inv.backpack.items_in_reading_order().size() == 2, "starts with 2 items in the backpack")
	_ok(inv.equipped_pistols().size() == 2, "both starting pistols are equipped")
	# Exact starting placement matches the spec layout.
	_ok(inv.backpack.item_at(Vector2i(0, 1)) != null and inv.backpack.item_at(Vector2i(1, 3)) != null,
		"left pistol occupies the left column + foot")
	_ok(inv.backpack.item_at(Vector2i(2, 1)) != null and inv.backpack.item_at(Vector2i(3, 3)) != null,
		"right pistol occupies the right column + head")

	var changes := [0]
	inv.changed.connect(func(): changes[0] += 1)

	var left: Object = inv.equipped_pistols()[0]
	inv.pick_up(inv.backpack, left)
	_ok(inv.equipped_pistols().size() == 1, "picking a pistol out of the backpack unequips it")
	_ok(changes[0] == 1, "pick_up emits changed")

	_ok(inv.drop(inv.stash, left, Vector2i(0, 0)), "the pistol drops into the stash")
	_ok(inv.equipped_pistols().size() == 1, "a stashed pistol is still unequipped")
	_ok(changes[0] == 2, "drop emits changed")

	inv.free()


func _test_item_tooltip() -> void:
	_suite = "ItemTooltip"
	var p := InventoryItemScript.pistol()
	_ok(p.display_name() == "Pistol", "pistol display name")
	_ok(p.rarity() == "Normal" and p.level() == 1, "pistol is Normal / Lvl 1")
	_ok(p.flavor().length() > 0, "pistol has flavour text")

	var rows := ItemTooltipScript.format_stats(p)
	var shown := {}
	for r in rows:
		shown[r[0]] = r[1]
	_ok(shown.has("Damage") and shown["Damage"] == "5", "Damage shows as 5")
	_ok(not shown.has("Projectile"), "Projectile is no longer a stat row (it's a header tag)")
	_ok(not shown.has("Piercing") and not shown.has("Ricochet"),
		"zero-valued stats (Piercing/Ricochet) are hidden")
	_ok(shown.has("Magazine") and shown["Magazine"] == "7", "Magazine shows 7")

	# Type + tags: pistol is a Gun and is tagged both Projectile and Gun.
	_ok(p.type_name() == "Gun", "pistol Type is Gun")
	_ok(p.tags().has("Projectile") and p.tags().has("Gun"), "pistol header tags include Projectile + Gun")

	# Manual flavour wrap: no line exceeds the limit, and no word is lost.
	var wrapped := ItemTooltipScript._wrap(p.flavor(), 20)
	var longest := 0
	for line in wrapped.split("\n"):
		longest = maxi(longest, line.length())
	_ok(longest <= 20, "wrap keeps lines within the char limit (longest %d)" % longest)
	_ok(wrapped.replace("\n", " ") == p.flavor(), "wrap preserves the words and order")


func _test_grid_view() -> void:
	_suite = "GridView"
	var gv: Control = GridViewScript.new()
	var step := GridViewScript.CELL + GridViewScript.GAP
	_ok(gv.cell_at(Vector2(5, 5)) == Vector2i(0, 0), "top-left pixels map to cell (0,0)")
	_ok(gv.cell_at(Vector2(step + 5, 5)) == Vector2i(1, 0), "one step right maps to cell (1,0)")
	_ok(gv.cell_at(Vector2(5, step * 2 + 5)) == Vector2i(0, 2), "two steps down maps to cell (0,2)")
	_ok(gv.cell_origin(Vector2i(2, 1)).is_equal_approx(Vector2(step * 2, step)),
		"cell_origin returns the cell's top-left pixel")
	gv.free()


func _test_level_up_menu() -> void:
	_suite = "LevelUpMenu"
	var inv: Node = InventoryScript.build()
	var st: Node = PlayerStatsScript.new()
	st.souls = 5
	var menu: CanvasLayer = LevelUpMenuScript.new()
	menu.inventory = inv
	menu.stats = st
	get_root().add_child(menu)
	await process_frame                       # _ready builds the UI

	menu.open(2)
	_ok(paused and menu.visible, "open() pauses the tree and shows the menu")
	_ok(menu._souls_label.text == "5 SOULS", "menu shows the banked soul count (%s)" % menu._souls_label.text)
	menu.open(3)
	_ok(menu._open, "open() is idempotent while already open")
	menu.close()
	_ok(not paused and not menu.visible, "close() unpauses and hides")

	# Held items are never lost: pick one up, then close returns it to its origin.
	menu.open(4)
	var p: Object = inv.equipped_pistols()[0]
	menu._begin_hold(inv.backpack, p)         # simulate a pick-up (UI click does this)
	_ok(inv.equipped_pistols().size() == 1, "holding a pistol unequips it")
	menu.close()
	_ok(inv.equipped_pistols().size() == 2, "close() returns the held pistol -> re-equipped")
	paused = false                            # safety: ensure unpaused for later tests
	menu.free()
	inv.free()
	st.free()


func _test_hud_clear_medals() -> void:
	_suite = "Hud.medals"
	var stats: Node = PlayerStatsScript.new()
	var hud: CanvasLayer = HudScript.new()
	hud.stats = stats
	get_root().add_child(hud)
	await process_frame                       # _ready builds the HUD
	hud._add_lvlup_medal()
	hud._add_lvlup_medal()
	_ok(hud._lvlup_stack.get_child_count() == 2, "two medals on the stack")
	hud.clear_levelup_medals()
	await process_frame                       # let queue_free run
	_ok(hud._lvlup_stack.get_child_count() == 0, "clear_levelup_medals empties the stack")
	hud.free()
	stats.free()


func _test_hud_xp_animation() -> void:
	_suite = "Hud.xp"
	var stats: Node = PlayerStatsScript.new()
	var hud: CanvasLayer = HudScript.new()
	hud.stats = stats
	get_root().add_child(hud)
	await process_frame                       # _ready builds the HUD + seeds the bar

	var reached := [0]
	hud.level_reached.connect(func(l: int) -> void: reached[0] = l)

	# Gain less than a level: the bar animates toward it; no level-up.
	stats.add_xp(4.0)
	for i in 40:
		hud._animate_xp(0.05)
	_ok(reached[0] == 0, "no level_reached while the bar is below 100%")
	_ok(absf(hud._xp.value - 4.0) < 0.05 and hud._xp_level == 1,
		"bar animates to the gained XP, still level 1 (value %.1f)" % hud._xp.value)

	# Cross the threshold: stats level up at once, but the flourish waits for the bar.
	stats.add_xp(8.0)                         # total 12 > 10 -> stats.level becomes 2 now
	_ok(stats.level == 2, "stats level up immediately (authoritative)")
	_ok(reached[0] == 0, "the bar hasn't filled yet -> level_reached still not fired")

	var saw_full := false
	for i in 60:
		hud._animate_xp(0.05)
		if reached[0] != 0:
			saw_full = true
			break
	_ok(saw_full and reached[0] == 2, "level_reached(2) fires only when the bar hits 100%")
	_ok(hud._xp_level == 2, "the bar advances to level 2 after filling")

	hud.free()
	stats.free()


func _test_souls() -> void:
	_suite = "Souls"
	var stats: Node = PlayerStatsScript.new()
	var got := [-1]
	stats.souls_changed.connect(func(s: int) -> void: got[0] = s)
	stats.add_souls()
	_ok(stats.souls == 1 and got[0] == 1, "add_souls() banks one and emits (souls %d)" % stats.souls)
	stats.add_souls(3)
	_ok(stats.souls == 4, "add_souls(n) accumulates (souls %d)" % stats.souls)

	var hud: CanvasLayer = HudScript.new()
	hud.stats = stats
	get_root().add_child(hud)
	await process_frame                       # _ready builds the counter + binds
	_ok(hud._souls_count.text == "4", "HUD counter shows the current souls (%s)" % hud._souls_count.text)
	stats.add_souls(2)
	_ok(hud._souls_count.text == "6", "HUD counter updates on souls_changed (%s)" % hud._souls_count.text)
	hud.free()
	stats.free()


## Sort a cell array by (row, col) so set-equality can use ==.
func _sorted_cells(cells: Array) -> Array:
	var out: Array = cells.duplicate()
	out.sort_custom(func(a, b): return (a.y < b.y) or (a.y == b.y and a.x < b.x))
	return out


func _ok(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  ok   [%s] %s" % [_suite, message])
	else:
		_failed += 1
		printerr("  FAIL [%s] %s" % [_suite, message])
