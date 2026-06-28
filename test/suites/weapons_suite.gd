extends RefCounted
## Weapon tests: ring build, inventory-driven loadout, projectiles, gun range,
## stats, reload, turret mount. Split from run_tests.gd. `t` is the TestContext.

const TestContext := preload("res://test/test_context.gd")
const WeaponRingScript := preload("res://src/weapons/weapon_ring.gd")
const ProjectileScript := preload("res://src/fx/projectile.gd")
const GunScript := preload("res://src/weapons/gun.gd")
const TurretMountScript := preload("res://src/weapons/turret_mount.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const MarineScript := preload("res://src/marine/marine.gd")
const InventoryScript := preload("res://src/inventory/inventory.gd")
const WeaponDefScript := preload("res://src/weapons/weapon_def.gd")
const WeaponCatalogScript := preload("res://src/weapons/weapon_catalog.gd")
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const ShotSfxScript := preload("res://src/audio/shot_sfx.gd")


func run(t: TestContext) -> void:
	_test_weapon_def(t)
	_test_weapon_catalog(t)
	await _test_weapon_ring(t)
	await _test_weapon_ring_inventory(t)
	await _test_projectile_kills(t)
	await _test_projectile_hits_path(t)
	await _test_projectile_misses(t)
	await _test_projectile_aim_dir(t)
	await _test_projectile_range(t)
	await _test_projectile_hits_elevated(t)
	await _test_gun_range(t)
	await _test_extra_guns_share_target(t)
	await _test_gun_stats_from_item(t)
	await _test_gun_reload(t)
	await _test_turret_mount(t)
	await _test_shot_sfx_configure(t)
	_test_spread_aim(t)
	await _test_sawed_off_burst(t)
	await _test_sawed_off_model(t)


func _test_weapon_ring(t: TestContext) -> void:
	t.suite = "WeaponRing"
	var wr: Node3D = WeaponRingScript.new()
	wr.gun_count = 6
	wr.player = Node3D.new()
	t.root().add_child(wr.player)
	t.root().add_child(wr)
	await t.frame()
	t.ok(wr._guns.size() == 6, "builds the requested gun count (got %d)" % wr._guns.size())

	var wr2: Node3D = WeaponRingScript.new()
	wr2.gun_count = 99                         # over the max
	wr2.player = Node3D.new()
	t.root().add_child(wr2.player)
	t.root().add_child(wr2)
	await t.frame()
	t.ok(wr2._guns.size() == 12, "clamps gun count to 12 (got %d)" % wr2._guns.size())

	var p1: Node = wr.player
	var p2: Node = wr2.player
	wr.free(); wr2.free()
	p1.free(); p2.free()


func _test_weapon_ring_inventory(t: TestContext) -> void:
	t.suite = "WeaponRing.inventory"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var inv: Node = InventoryScript.build()
	m.add_child(inv)
	m.inventory = inv
	var wr: Node3D = WeaponRingScript.new()
	wr.player = m
	holder.add_child(wr)
	await t.frame()
	t.ok(wr._guns.size() == 2, "ring builds 2 guns from the 2 equipped pistols (got %d)" % wr._guns.size())

	var p: Object = inv.equipped_pistols()[0]
	inv.pick_up(inv.backpack, p)                 # unequip one -> changed -> rebuild
	t.ok(wr._guns.size() == 1, "removing a backpack pistol drops a gun (got %d)" % wr._guns.size())

	inv.drop(inv.stash, p, Vector2i(0, 0))       # parked in the stash: still unequipped
	t.ok(wr._guns.size() == 1, "a stashed pistol stays unequipped (got %d)" % wr._guns.size())
	holder.free()


func _test_projectile_kills(t: TestContext) -> void:
	t.suite = "Projectile"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	holder.add_child(imp)
	imp.global_position = Vector3(5.0, 0.0, 0.0)
	var p: Node3D = ProjectileScript.new()
	p.target = imp
	holder.add_child(p)
	p.global_position = Vector3(0.0, 0.6, 0.0)
	await t.frame()

	var killed := false
	for i in 200:
		p._process(0.05)                      # step the bolt toward the imp
		if imp.is_queued_for_deletion():
			killed = true
			break
	t.ok(killed, "a bolt reaches its target imp and kills it")
	await t.frame()
	holder.free()


func _test_projectile_hits_path(t: TestContext) -> void:
	t.suite = "Projectile.path"
	var holder := Node3D.new()
	t.root().add_child(holder)
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
	await t.frame()

	for i in 200:
		p._process(0.016)
		if blocker.is_queued_for_deletion() or assigned.is_queued_for_deletion():
			break
	t.ok(blocker.is_queued_for_deletion() and not assigned.is_queued_for_deletion(),
		"bolt hits the imp in its path, not only its assigned target")
	holder.free()


func _test_projectile_misses(t: TestContext) -> void:
	t.suite = "Projectile.miss"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	holder.add_child(imp)
	imp.global_position = Vector3(0.0, 0.0, -10.0)   # straight ahead (-Z), far off
	imp.set_process(false)
	var p: Node3D = ProjectileScript.new()
	p.target = imp
	holder.add_child(p)
	p.global_position = Vector3(0.0, 0.6, 0.0)
	await t.frame()

	p._process(0.016)                                 # locks heading toward -Z
	imp.global_position = Vector3(20.0, 0.0, -10.0)   # imp dodges off the bolt's line

	var hit := false
	for i in 200:
		p._process(0.05)
		if imp.is_queued_for_deletion():
			hit = true
			break
	t.ok(not hit, "a bolt flies straight and misses a target that left its path")
	holder.free()


func _test_projectile_aim_dir(t: TestContext) -> void:
	t.suite = "Projectile.aim_dir"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var p: Node3D = ProjectileScript.new()
	p.aim_dir = Vector3(1.0, 0.0, 0.0)            # fly +X, no target assigned
	holder.add_child(p)
	p.global_position = Vector3.ZERO
	await t.frame()
	p._process(0.1)
	t.ok(p.global_position.x > 0.1 and not p.is_queued_for_deletion(),
		"a bolt with aim_dir flies that heading even with no target")
	holder.free()


func _test_projectile_range(t: TestContext) -> void:
	t.suite = "Projectile.range"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var p: Node3D = ProjectileScript.new()
	p.aim_dir = Vector3(1.0, 0.0, 0.0)
	p.max_range = 3.0                              # despawn after 3 units, hitting nothing
	holder.add_child(p)
	p.global_position = Vector3.ZERO
	await t.frame()
	var gone := false
	for i in 100:
		p._process(0.05)
		if p.is_queued_for_deletion():
			gone = true
			break
	t.ok(gone, "a bolt despawns once it flies past its max_range")
	holder.free()


func _test_projectile_hits_elevated(t: TestContext) -> void:
	t.suite = "Projectile.elevated"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var imp: Node3D = ImpScript.new()
	holder.add_child(imp)
	imp.global_position = Vector3(4.0, 1.4, 0.0)   # standing high on a hill
	imp.set_process(false)
	var p: Node3D = ProjectileScript.new()
	p.aim_dir = Vector3(1.0, 0.0, 0.0)             # flies level (+X), well below the imp's centre
	holder.add_child(p)
	p.global_position = Vector3(0.0, 0.6, 0.0)
	await t.frame()
	var killed := false
	for i in 100:
		p._process(0.05)
		if imp.is_queued_for_deletion():
			killed = true
			break
	t.ok(killed, "a level bolt hits an imp standing higher on the terrain (XZ hit test)")
	holder.free()


func _test_extra_guns_share_target(t: TestContext) -> void:
	t.suite = "WeaponRing.share"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var player := Node3D.new()
	holder.add_child(player)
	var imp: Node3D = ImpScript.new()
	holder.add_child(imp)
	imp.global_position = Vector3(3.0, 0.0, 0.0)    # one imp, in range
	imp.set_process(false)
	var wr: Node3D = WeaponRingScript.new()
	wr.gun_count = 4                                # more guns than imps
	wr.player = player
	holder.add_child(wr)
	await t.frame()
	await t.frame()
	var all_on := true
	for g in wr._guns:
		if g._target != imp:
			all_on = false
	t.ok(all_on, "with more guns than imps, every gun fires at an existing imp (none idle)")
	holder.free()


func _test_gun_range(t: TestContext) -> void:
	t.suite = "WeaponRing.range"
	var holder := Node3D.new()
	t.root().add_child(holder)
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
	await t.frame()
	await t.frame()

	t.ok(wr._guns[0]._target == near, "the in-range closest imp is targeted")
	t.ok(wr._guns[0]._target != far and wr._guns[1]._target != far,
		"the out-of-range imp is never targeted")
	holder.free()


func _test_gun_stats_from_item(t: TestContext) -> void:
	t.suite = "WeaponRing.stats"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var m: Node3D = MarineScript.new()
	holder.add_child(m)
	var inv: Node = InventoryScript.build()
	m.add_child(inv)
	m.inventory = inv
	var wr: Node3D = WeaponRingScript.new()
	wr.player = m
	holder.add_child(wr)
	await t.frame()
	# Level up an equipped pistol and force the ring to rebuild from the inventory.
	inv.equipped_pistols()[0].item_level = 5
	inv.changed.emit()
	var equipped: Array = inv.equipped_pistols()
	var dmg_ok := true
	for i in wr._guns.size():
		if not is_equal_approx(wr._guns[i].damage, equipped[i].damage_value()):
			dmg_ok = false
	t.ok(dmg_ok, "each gun fires with its equipped pistol's level-scaled damage")
	t.ok(wr._guns[0].damage > GunScript.DAMAGE, "the leveled pistol's gun deals more than base damage (%.0f > %.0f)"
		% [wr._guns[0].damage, GunScript.DAMAGE])
	holder.free()


func _test_gun_reload(t: TestContext) -> void:
	t.suite = "Gun.reload"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var g: Node3D = GunScript.new()
	g.mag_size = 3
	g.reload_time = 0.5
	g.fire_interval = 0.0                         # fire whenever off cooldown, so we can empty fast
	var shots := [0]
	g.fired.connect(func(_o: Vector3, _t: Node3D, _d: float, _a: Vector3) -> void: shots[0] += 1)
	holder.add_child(g)                           # _ready -> _ammo = mag_size (3)
	await t.frame()
	var target := Node3D.new()
	holder.add_child(target)
	target.global_position = Vector3(0.0, 0.0, -2.0)
	g.set_target(target)

	for i in 12:                                  # empties the magazine, then can't fire while reloading
		g._process(0.05)
	t.ok(shots[0] == 3, "fires exactly one magazine (3) then stops to reload (got %d)" % shots[0])
	t.ok(g._reloading, "the gun is reloading after the magazine empties")

	g._process(0.6)                               # wait out the 0.5s reload
	t.ok(not g._reloading and g._ammo == 3, "reload completes and refills the magazine")
	g._process(0.05)
	t.ok(shots[0] == 4, "the gun fires again after reloading (got %d)" % shots[0])
	holder.free()


func _test_turret_mount(t: TestContext) -> void:
	t.suite = "TurretMount"
	var tm: Node3D = TurretMountScript.new()
	t.root().add_child(tm)
	await t.frame()                           # _ready builds the strut + ball
	tm.set_span(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 1.0, 0.0))
	t.ok(tm._strut.position.is_equal_approx(Vector3(0.5, 1.0, 0.0)), "strut sits at the midpoint of the span")
	t.ok(absf(tm._strut.scale.z - 1.0) < 0.001, "strut length spans from->to (z scale %.2f)" % tm._strut.scale.z)
	t.ok(tm._ball.position.is_equal_approx(Vector3(1.0, 1.0, 0.0)), "pivot ball seats at the far (gun) end")
	tm.free()


func _test_shot_sfx_configure(t: TestContext) -> void:
	t.suite = "ShotSfx"
	var s: Node = ShotSfxScript.new()
	t.root().add_child(s)
	await t.frame()
	s.configure(["res://sound/pistol_01.mp3", "res://sound/pistol_02.mp3"], [])
	t.ok(s._streams.size() == 2, "configure() loads the given clip set (got %d)" % s._streams.size())
	s.play()                          # must not crash with the reconfigured set
	t.ok(true, "play() runs after reconfigure")
	s.free()


func _test_sawed_off_burst(t: TestContext) -> void:
	t.suite = "Gun.spread_fire"
	var holder := Node3D.new()
	t.root().add_child(holder)
	var g: Node3D = GunScript.new()
	g.def = WeaponCatalogScript.get_def(WeaponCatalogScript.SAWED_OFF)
	g.mag_size = 2
	g.fire_interval = 0.0
	var shots := [0]
	g.fired.connect(func(_o: Vector3, _t: Node3D, _d: float, _a: Vector3) -> void: shots[0] += 1)
	holder.add_child(g)                           # _ready -> _ammo = 2
	await t.frame()
	var target := Node3D.new()
	holder.add_child(target)
	target.global_position = Vector3(0.0, 0.0, -2.0)
	g.set_target(target)
	g._process(0.05)                              # fire ONE shell
	t.ok(shots[0] == g.def.pellets, "one shell fires exactly `pellets` projectiles (got %d, want %d)" % [shots[0], g.def.pellets])
	holder.free()


## The sawed-off builds its own procedural body — distinct from the pistol, but on the
## same grip-at-origin / muzzle-at-barrel_tip convention so the hand mount can't break.
func _test_sawed_off_model(t: TestContext) -> void:
	t.suite = "Gun.sawed_off"
	var holder := Node3D.new()
	t.root().add_child(holder)

	var pistol: Node3D = GunScript.new()
	pistol.def = WeaponCatalogScript.get_def(WeaponCatalogScript.PISTOL)
	holder.add_child(pistol)

	var sg: Node3D = GunScript.new()
	sg.def = WeaponCatalogScript.get_def(WeaponCatalogScript.SAWED_OFF)
	holder.add_child(sg)                              # _ready -> _build_body
	await t.frame()

	t.ok(sg.def.body == WeaponDefScript.Body.SAWED_OFF, "the sawed-off def selects the SAWED_OFF body")
	t.ok(_mesh_parts(sg) > _mesh_parts(pistol),
		"the sawed-off builds a distinct, chunkier body (%d parts > pistol %d)" % [_mesh_parts(sg), _mesh_parts(pistol)])
	t.ok(sg._body_mat != null, "the sawed-off shares one body material -> reload tint still works")
	t.ok(sg._flash.position.is_equal_approx(sg.def.barrel_tip),
		"the muzzle flash sits at def.barrel_tip (pivot/connection intact)")
	holder.free()


## Count the MeshInstance3D children of a gun (its built body parts + the flash quad).
func _mesh_parts(g: Node) -> int:
	var n := 0
	for c in g.get_children():
		if c is MeshInstance3D:
			n += 1
	return n


func _test_spread_aim(t: TestContext) -> void:
	t.suite = "Gun.spread_aim"
	var base := Vector3(0, 0, -1)
	var arc := deg_to_rad(40.0)
	var dirs: Array = GunScript.spread_aim(base, 6, arc)
	t.ok(dirs.size() == 6, "spread_aim returns one heading per pellet (got %d)" % dirs.size())
	var within := true
	for d in dirs:
		if base.angle_to(d) > arc * 0.5 + 0.001:
			within = false
	t.ok(within, "every (random) pellet stays within half the spread arc")
	var one: Array = GunScript.spread_aim(base, 1, 0.0)
	t.ok(one.size() == 1 and (one[0] as Vector3).is_equal_approx(base), "1 pellet fires straight")


func _test_weapon_def(t: TestContext) -> void:
	t.suite = "WeaponDef"
	var d: Object = WeaponDefScript.from({})
	t.ok(d.pattern == WeaponDefScript.Pattern.SINGLE, "default pattern is SINGLE")
	t.ok(d.pellets == 1 and is_zero_approx(d.spread_arc), "defaults: 1 pellet, no spread")
	var s: Object = WeaponDefScript.from({"damage": 9.0, "pattern": WeaponDefScript.Pattern.SPREAD, "pellets": 5})
	t.ok(is_equal_approx(s.damage, 9.0) and s.pellets == 5, "from() applies overrides")
	t.ok(s.pattern == WeaponDefScript.Pattern.SPREAD, "from() applies the pattern override")

func _test_weapon_catalog(t: TestContext) -> void:
	t.suite = "WeaponCatalog"
	# Catalog int keys must line up with the InventoryItem.Kind enum.
	t.ok(WeaponCatalogScript.PISTOL == InventoryItemScript.Kind.PISTOL, "catalog PISTOL key == Kind.PISTOL")
	var p: Object = WeaponCatalogScript.get_def(WeaponCatalogScript.PISTOL)
	t.ok(is_equal_approx(p.damage, 5.0), "pistol def base damage is 5")
	t.ok(is_equal_approx(p.fire_interval, 1.7) and p.magazine == 7, "pistol def fire interval + magazine match today")
	t.ok(p.pattern == WeaponDefScript.Pattern.SINGLE, "pistol fires SINGLE")
	var sg: Object = WeaponCatalogScript.get_def(WeaponCatalogScript.SAWED_OFF)
	t.ok(sg.pattern == WeaponDefScript.Pattern.SPREAD and sg.pellets >= 2, "sawed-off fires SPREAD with multiple pellets")
	t.ok(WeaponCatalogScript.weapon_kinds().size() >= 2, "catalog lists at least pistol + sawed-off")
