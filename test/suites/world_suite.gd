extends RefCounted
## World tests: island shape, obstacle field, layout, and the marine's clamp/push
## against it. Split from run_tests.gd. `t` is the shared TestContext.

const TestContext := preload("res://test/test_context.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")
const HellIsland := preload("res://src/world/hell_island.gd")
const ObstacleFieldScript := preload("res://src/world/obstacle_field.gd")
const MarineScript := preload("res://src/marine/marine.gd")


func run(t: TestContext) -> void:
	_test_island_shape(t)
	_test_surface_height(t)
	_test_marine_clamp(t)
	_test_obstacle_field(t)
	_test_island_no_overlap(t)
	_test_marine_obstacle_push(t)


func _test_island_shape(t: TestContext) -> void:
	t.suite = "IslandShape"
	var in_bounds := true
	for i in 360:
		var r := IslandShape.radius(deg_to_rad(float(i)))
		if r < IslandShape.BASE * 0.6 or r > IslandShape.BASE * 1.4:
			in_bounds = false
	t.ok(in_bounds, "radius() stays within [0.6, 1.4] * BASE for all angles")
	t.ok(is_equal_approx(IslandShape.radius(0.5), IslandShape.radius(0.5 + TAU)),
		"radius() is periodic over TAU")


## surface_height: deterministic, flat at/beyond the coast, bounded by HILL_AMP,
## and with real relief in the interior.
func _test_surface_height(t: TestContext) -> void:
	t.suite = "IslandShape.surface_height"
	t.ok(is_equal_approx(IslandShape.surface_height(3.0, -4.0), IslandShape.surface_height(3.0, -4.0)),
		"surface_height is deterministic")

	var ang := 0.7
	var coast := IslandShape.radius(ang)
	var beyond := Vector2(cos(ang), sin(ang)) * coast * 1.5
	t.ok(is_equal_approx(IslandShape.surface_height(beyond.x, beyond.y), 0.0),
		"surface_height is 0 beyond the coast")

	var at := Vector2(cos(ang), sin(ang)) * coast
	t.ok(absf(IslandShape.surface_height(at.x, at.y)) < 0.05,
		"surface_height tapers to ~0 at the coast")

	var bounded := true
	var any_relief := false
	for i in 40:
		for j in 40:
			var x := lerpf(-20.0, 20.0, float(i) / 39.0)
			var z := lerpf(-20.0, 20.0, float(j) / 39.0)
			var h := IslandShape.surface_height(x, z)
			if absf(h) > IslandShape.HILL_AMP + 0.001:
				bounded = false
			if absf(h) > 0.1:
				any_relief = true
	t.ok(bounded, "surface_height stays within +/- HILL_AMP")
	t.ok(any_relief, "surface_height has real relief in the interior")


func _test_marine_clamp(t: TestContext) -> void:
	t.suite = "Marine.clamp"
	var m: Node3D = MarineScript.new()       # not added to tree: _ready/rig not needed
	m.position = Vector3(50.0, 0.0, 30.0)    # far outside the island
	m._clamp_to_island()
	var d := Vector2(m.position.x, m.position.z).length()
	var ang := atan2(m.position.z, m.position.x)
	var max_r: float = IslandShape.radius(ang) - MarineScript.EDGE_MARGIN
	t.ok(d <= max_r + 0.01, "clamp pulls an outside point onto the island")

	var inside := Vector3(1.0, 0.0, 1.0)
	m.position = inside
	m._clamp_to_island()
	t.ok(m.position.is_equal_approx(inside), "clamp leaves an inside point untouched")
	m.free()


## ObstacleField: blockers push a body out, lava capsules too, steps lift it on top,
## and the overlap test rejects stacked footprints (with a limit cutoff).
func _test_obstacle_field(t: TestContext) -> void:
	t.suite = "ObstacleField"
	var f: ObstacleFieldScript = ObstacleFieldScript.new()
	f.add_block(Vector2.ZERO, 1.0)

	# A body inside the blocker is pushed out to its radius + the body radius.
	var out: Vector3 = f.resolve(Vector3(0.3, 0.0, 0.0), 0.5)
	var od := Vector2(out.x, out.z).length()
	t.ok(is_equal_approx(od, 1.5), "blocker pushes a body out to r + body_r (%.3f)" % od)

	# A body well clear of every blocker is left where it is, on the ground.
	var clear: Vector3 = f.resolve(Vector3(5.0, 0.0, 0.0), 0.5)
	t.ok(clear.is_equal_approx(Vector3(5.0, 0.0, 0.0)), "a body clear of obstacles is untouched")

	# Capsule blocker (a != b): closest point is on the segment, body shoved off it.
	var g: ObstacleFieldScript = ObstacleFieldScript.new()
	g.blockers.append({"a": Vector2(0.0, 0.0), "b": Vector2(2.0, 0.0), "r": 0.1})
	var lv: Vector3 = g.resolve(Vector3(1.0, 0.0, 0.2), 0.3)
	t.ok(is_equal_approx(lv.z, 0.4) and is_equal_approx(lv.x, 1.0),
		"capsule blocker pushes a body off the segment (z=%.3f)" % lv.z)

	# Thin lava is decoration: it reserves a footprint but never blocks.
	var dec: ObstacleFieldScript = ObstacleFieldScript.new()
	dec.add_decor(Vector2.ZERO, 1.0)
	var through: Vector3 = dec.resolve(Vector3(0.1, 0.0, 0.0), 0.4)
	t.ok(through.is_equal_approx(Vector3(0.1, 0.0, 0.0)), "passable lava decoration never pushes a body")
	t.ok(dec.overlaps(Vector2(0.5, 0.0), 0.2), "lava decoration still reserves its footprint")

	# Step: a body over the disc is lifted onto its top; off it, back to the ground.
	var s: ObstacleFieldScript = ObstacleFieldScript.new()
	s.add_step(Vector2.ZERO, 1.0, 0.6)
	var on_top: Vector3 = s.resolve(Vector3(0.2, 0.0, 0.0), 0.4)
	var off: Vector3 = s.resolve(Vector3(5.0, 0.0, 0.0), 0.4)
	t.ok(is_equal_approx(on_top.y, 0.6), "step lifts a body onto its top")
	t.ok(is_equal_approx(off.y, 0.0), "off the step, the body is back on the ground")

	# overlaps(): rejects a footprint touching a placed one; limit caps the scan.
	var o: ObstacleFieldScript = ObstacleFieldScript.new()
	o.add_block(Vector2.ZERO, 1.0)
	t.ok(o.overlaps(Vector2(1.0, 0.0), 0.5), "overlaps() flags a footprint inside an existing one")
	t.ok(not o.overlaps(Vector2(2.0, 0.0), 0.5), "overlaps() clears a footprint that only just misses")
	o.add_block(Vector2(2.0, 0.0), 1.0)
	t.ok(not o.overlaps(Vector2(2.0, 0.0), 0.5, 1), "overlaps(limit) ignores footprints past the cutoff")

	# Ground baseline: with no step under the body, resolve returns the ground height.
	var gnd: ObstacleFieldScript = ObstacleFieldScript.new()
	var lifted: Vector3 = gnd.resolve(Vector3(5.0, 0.0, 0.0), 0.5, 1.2)
	t.ok(is_equal_approx(lifted.y, 1.2), "resolve returns the ground baseline when on no step")

	# A step lower than the ground loses to the ground; a higher step wins.
	gnd.add_step(Vector2.ZERO, 1.0, 0.4)
	var low: Vector3 = gnd.resolve(Vector3(0.1, 0.0, 0.0), 0.4, 1.2)
	t.ok(is_equal_approx(low.y, 1.2), "ground wins over a lower step")
	var g2: ObstacleFieldScript = ObstacleFieldScript.new()
	g2.add_step(Vector2.ZERO, 1.0, 2.0)
	var hi: Vector3 = g2.resolve(Vector3(0.1, 0.0, 0.0), 0.4, 1.2)
	t.ok(is_equal_approx(hi.y, 2.0), "a higher step wins over the ground")


## Generation guarantee: no two solid footprints (columns + rocks) are stacked.
func _test_island_no_overlap(t: TestContext) -> void:
	t.suite = "HellIsland.layout"
	var island: Node3D = HellIsland.build()
	var field: ObstacleFieldScript = island.get_meta("obstacles")

	# Gather the discrete footprints: spires (point-blockers, a == b) + step rocks.
	var foot: Array = []
	for blk in field.blockers:
		if (blk["a"] as Vector2).is_equal_approx(blk["b"]):
			foot.append({"c": blk["a"], "r": blk["r"]})
	for st in field.steps:
		foot.append({"c": st["c"], "r": st["r"]})

	var clean := true
	for i in foot.size():
		for j in range(i + 1, foot.size()):
			var dist: float = (foot[i]["c"] as Vector2).distance_to(foot[j]["c"])
			if dist < foot[i]["r"] + foot[j]["r"] - 0.001:
				clean = false
	t.ok(foot.size() > 10, "the island places a decent field of obstacles (%d)" % foot.size())
	t.ok(clean, "no two columns/rocks are stacked on each other")
	island.free()


## The marine's movement step rounds it out of a column and climbs it onto a rock.
func _test_marine_obstacle_push(t: TestContext) -> void:
	t.suite = "Marine.obstacle"
	var blocked: ObstacleFieldScript = ObstacleFieldScript.new()
	blocked.add_block(Vector2.ZERO, 1.0)
	var m: Node3D = MarineScript.new()            # not in tree: movement step needs no rig
	m.obstacles = blocked
	m.position = Vector3(0.3, 0.0, 0.0)            # inside the column
	m._handle_movement(0.016)                      # no keys -> resolve still pushes out
	var d := Vector2(m.position.x, m.position.z).length()
	t.ok(d >= 1.0 + MarineScript.BODY_RADIUS - 0.01, "a column shoves the marine clear (%.2f)" % d)

	# A rock taller than the local ground lifts the marine onto it. The rock top is set
	# above the terrain swell at the origin so this tests the climb, not the ground
	# (robust to surface_height amplitude/frequency tuning).
	var stepped: ObstacleFieldScript = ObstacleFieldScript.new()
	var rock_top := IslandShape.surface_height(0.0, 0.0) + 1.0
	stepped.add_step(Vector2.ZERO, 2.0, rock_top)
	m.obstacles = stepped
	m.position = Vector3(0.0, 0.0, 0.0)
	m._handle_movement(0.016)
	t.ok(is_equal_approx(m.position.y, rock_top), "the marine climbs onto a rock above the terrain (y=%.2f)" % m.position.y)

	# With no obstacles, the marine's movement step drops it onto the terrain height.
	var empty: ObstacleFieldScript = ObstacleFieldScript.new()
	m.obstacles = empty
	var spot := Vector2(4.0, -3.0)                 # an interior point with real relief (worldX, worldZ)
	m.position = Vector3(spot.x, 0.0, spot.y)
	m._handle_movement(0.016)                       # no keys -> resolve lifts to surface_height
	t.ok(is_equal_approx(m.position.y, IslandShape.surface_height(spot.x, spot.y)),
		"the marine stands on the terrain height (y=%.3f)" % m.position.y)
	m.free()
