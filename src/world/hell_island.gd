extends RefCounted
## Builds the hell island: the same organic floating landmass as the prototype's
## coastline (IslandShape), reskinned as charred basalt — dark warm rock with a
## triplanar normal map, scattered rocks, and a few glowing "ember" rocks. Returns
## a single Node3D for the caller to add. Reference via `const HellIsland := preload(...)`.

const ColorUtil := preload("res://src/lib/color_util.gd")
const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")
const ObstacleFieldScript := preload("res://src/world/obstacle_field.gd")
const COLUMN_SHADER := preload("res://src/world/column_xray.gdshader")

const OUTER_LAVA_Y := -1.2   # the lava sea sits this far below the island top


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "HellIsland"

	var rng := RandomNumberGenerator.new()
	rng.seed = 666
	var seg := 60

	var crust := Color(0.27, 0.22, 0.20)   # charred top crust — bright enough to read after the ambient cut, so the rock grain shows
	var rock_a := Color(0.20, 0.12, 0.11)  # warm dark basalt
	var rock_b := Color(0.12, 0.08, 0.09)  # near-black rock

	var rings := [
		{"rs": 1.00, "y": 0.0},
		{"rs": 0.97, "y": -2.6},
		{"rs": 0.74, "y": -5.6},
		{"rs": 0.44, "y": -8.4},
		{"rs": 0.20, "y": -10.6},
	]
	var band_cols := [rock_a, rock_b, rock_a, rock_b]
	var apex := Vector3(0.0, -12.6, 0.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Flat charred top: fan from centre to the coast ring, one uniform colour (a
	# centre-fan with per-tri colour variance shows radial wedge seams).
	for i in seg:
		var v0 := IslandShape.ring_vertex(rings[0]["rs"], rings[0]["y"], i, seg)
		var v1 := IslandShape.ring_vertex(rings[0]["rs"], rings[0]["y"], (i + 1) % seg, seg)
		_add_tri(st, Vector3.ZERO, v1, v0, crust, Vector3.UP)

	# Sides: stitch each ring to the next.
	for k in range(rings.size() - 1):
		for i in seg:
			var a := IslandShape.ring_vertex(rings[k]["rs"], rings[k]["y"], i, seg)
			var b := IslandShape.ring_vertex(rings[k]["rs"], rings[k]["y"], (i + 1) % seg, seg)
			var c := IslandShape.ring_vertex(rings[k + 1]["rs"], rings[k + 1]["y"], i, seg)
			var d := IslandShape.ring_vertex(rings[k + 1]["rs"], rings[k + 1]["y"], (i + 1) % seg, seg)
			_add_tri(st, a, b, c, ColorUtil.vary(band_cols[k], rng), _outward(a, b, c))
			_add_tri(st, b, d, c, ColorUtil.vary(band_cols[k], rng), _outward(b, d, c))

	# Underside: close down to the point.
	var last: Dictionary = rings[rings.size() - 1]
	for i in seg:
		var c := IslandShape.ring_vertex(last["rs"], last["y"], i, seg)
		var d := IslandShape.ring_vertex(last["rs"], last["y"], (i + 1) % seg, seg)
		_add_tri(st, apex, c, d, ColorUtil.vary(rock_b, rng), Vector3.DOWN)

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _rock_material()
	root.add_child(mi)

	# The molten sea the island floats in, with dark columns rising out of it beyond
	# the coast. Decorative (outside the play area) — no obstacle footprints.
	var col_mats: Array = []                  # x-ray column materials, fed the player pos each frame
	_build_outer_lava(root)
	_add_outer_columns(root, rng, col_mats)

	# Movement obstacles, recorded as they're placed (columns + lava-stones block;
	# dark rocks are stepped on top of; thin lava is passable decoration). Columns go
	# first so the rest avoids them; rubble fills last.
	var field := ObstacleFieldScript.new()
	_add_spires(root, rng, field, col_mats)
	_add_boulder_clusters(root, rng, field)
	_add_fissures(root, rng, field)
	_scatter_rocks(root, rng, field)
	root.set_meta("obstacles", field)
	root.set_meta("column_mats", col_mats)
	return root


## Vertex-colour rock with a triplanar procedural normal map (no UVs needed).
static func _rock_material() -> StandardMaterial3D:
	# Low-frequency fractal (FBM) noise: organic, multi-scale rock grain. The old
	# frequency (0.9) produced uncorrelated per-pixel static, which — tiled across
	# the ground — aliased into a regular "rows and columns" lattice.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.035
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	var ntex := NoiseTexture2D.new()
	ntex.width = 1024          # bigger tile = the repeat grid ("squares") is far less obvious
	ntex.height = 1024
	ntex.seamless = true
	ntex.as_normal_map = true
	ntex.bump_strength = 2.4   # was 1.8/3.2; deep enough to read, not so deep the tiling shouts
	ntex.noise = noise

	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.93   # was 0.86; raised back up so the ground stops glinting past the glow threshold and blooming
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.normal_enabled = true
	m.normal_texture = ntex
	m.normal_scale = 1.7   # was 0.9/2.4; visible grain without screaming the tiling
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.10, 0.10, 0.10)   # bigger tile in world space -> fewer repeats on screen -> no "squares" grid
	return m


## Flat-shaded triangle with a single colour; normal flipped to face `ref` so
## lighting is correct regardless of winding.
static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, ref: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.000001:
		return
	n = n.normalized()
	if n.dot(ref) < 0.0:
		n = -n
	for v in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)


static func _outward(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ctr := (a + b + c) / 3.0
	ctr.y = 0.0
	if ctr.length() < 0.001:
		return Vector3.UP
	return ctr.normalized()


## Scatter small rubble across the surface. The glowing (lava-stone) ones are
## impassable blockers; the dark ones are steps the marine + imps climb on top of.
static func _scatter_rocks(root: Node3D, rng: RandomNumberGenerator, field: ObstacleFieldScript) -> void:
	for i in 18:
		var ang := rng.randf_range(0.0, TAU)
		var maxr := IslandShape.radius(ang) - 1.2
		if maxr < 1.0:
			continue
		var d := rng.randf_range(0.0, maxr)
		var rs := rng.randf_range(0.3, 0.7)
		var c := Vector2(cos(ang) * d, sin(ang) * d)
		var fr := rs * 0.5
		if field.overlaps(c, fr):
			continue                              # don't stack on an already-placed object
		var glow := rng.randf() < 0.3

		var mb := MeshInstance3D.new()
		mb.mesh = MeshFactory.beveled_box(Vector3(rs, rs * 0.7, rs), 0.08)
		mb.material_override = _ember_mat(rng) if glow else _dark_rock_mat(rng)
		mb.position = Vector3(c.x, 0.04, c.y)
		mb.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(mb)
		if glow:
			field.add_block(c, fr)                # lava-stone: impassable
		else:
			field.add_step(c, fr, 0.04 + rs * 0.7 * 0.5)   # dark rock: top = centre + half-height


## A few larger boulder formations — 2-4 chunks near each other, so the field has
## real mass instead of uniform pebbles. Glowing ones block; dark ones are climbable.
static func _add_boulder_clusters(root: Node3D, rng: RandomNumberGenerator, field: ObstacleFieldScript) -> void:
	for i in 6:
		var ang := rng.randf_range(0.0, TAU)
		var maxr := IslandShape.radius(ang) - 1.8
		if maxr < 2.5:
			continue
		var d := rng.randf_range(2.0, maxr)
		var ctr := Vector3(cos(ang) * d, 0.0, sin(ang) * d)
		for b in rng.randi_range(2, 4):
			var sz := rng.randf_range(0.7, 1.5)
			var hgt := sz * rng.randf_range(0.5, 0.9)
			var off := Vector3(rng.randf_range(-0.9, 0.9), 0.0, rng.randf_range(-0.9, 0.9))
			var c := Vector2(ctr.x + off.x, ctr.z + off.z)
			var fr := sz * 0.5
			if field.overlaps(c, fr):
				continue
			var glow := rng.randf() < 0.16

			var mb := MeshInstance3D.new()
			mb.mesh = MeshFactory.beveled_box(Vector3(sz, hgt, sz), 0.12)
			mb.material_override = _ember_mat(rng) if glow else _dark_rock_mat(rng)
			mb.position = Vector3(c.x, 0.04, c.y)
			mb.rotation.y = rng.randf_range(0.0, TAU)
			root.add_child(mb)
			if glow:
				field.add_block(c, fr)            # lava-stone: impassable
			else:
				field.add_step(c, fr, 0.04 + hgt * 0.5)


## Jagged rock spires clustered around the coast — tall, tilted columns that break
## the flat silhouette and frame the arena. Impassable blockers, and given the x-ray
## material so the marine shows through when it's hidden behind one.
static func _add_spires(root: Node3D, rng: RandomNumberGenerator, field: ObstacleFieldScript, col_mats: Array) -> void:
	for i in 11:
		var ang := rng.randf_range(0.0, TAU)
		var maxr := IslandShape.radius(ang)
		var d := rng.randf_range(maxr * 0.74, maxr - 0.7)
		var base := Vector3(cos(ang) * d, 0.0, sin(ang) * d)
		for s in rng.randi_range(1, 3):
			var h := rng.randf_range(2.4, 4.4)
			var w := rng.randf_range(0.45, 0.85)
			var off := Vector3(rng.randf_range(-0.7, 0.7), 0.0, rng.randf_range(-0.7, 0.7))
			var c := Vector2(base.x + off.x, base.z + off.z)
			var fr := w * 0.6
			if field.overlaps(c, fr):
				continue

			var mat := _column_mat(rng)
			mat.set_shader_parameter("column_origin", Vector3(c.x, 0.0, c.y))
			col_mats.append(mat)
			var mb := MeshInstance3D.new()
			mb.mesh = MeshFactory.beveled_box(Vector3(w, h, w * 0.8), 0.12)
			mb.material_override = mat
			mb.position = base + off + Vector3(0.0, h * 0.5 - 0.3, 0.0)
			mb.rotation = Vector3(rng.randf_range(-0.16, 0.16), rng.randf_range(0.0, TAU), rng.randf_range(-0.16, 0.16))
			root.add_child(mb)
			field.add_block(c, fr)


## Thin fluid lava streams: a smooth wandering ribbon mesh (no block-snapping),
## tapering to a point at each end. Passable — recorded only as decoration so rocks
## don't render on top, never as a blocker.
static func _add_fissures(root: Node3D, rng: RandomNumberGenerator, field: ObstacleFieldScript) -> void:
	for c in 4:
		var ang := rng.randf_range(0.0, TAU)
		var sr := rng.randf_range(0.0, IslandShape.radius(ang) * 0.45)
		var pos := Vector2(cos(ang) * sr, sin(ang) * sr)
		var heading := rng.randf_range(0.0, TAU)
		var pts: Array[Vector2] = [pos]
		var solids := field.occupancy_count()    # columns + boulders placed before lava
		for s in rng.randi_range(18, 30):
			heading += rng.randf_range(-0.22, 0.22)   # gentle, continuous curve
			pos += Vector2(cos(heading), sin(heading)) * rng.randf_range(0.45, 0.7)
			if pos.length() > IslandShape.radius(atan2(pos.y, pos.x)) - 1.0:
				break
			if field.overlaps(pos, 0.4, solids):
				break                             # ran into a column/boulder — end the stream
			pts.append(pos)
		if pts.size() < 4:
			continue
		_build_lava_ribbon(root, pts, rng.randf_range(0.20, 0.32), _lava_mat(rng))
		for p in pts:
			field.add_decor(p, 0.3)


## A flat, tapering ribbon mesh through `pts` (XZ), width peaking in the middle and
## pinching to a point at both ends — reads as a molten stream, not stacked boxes.
static func _build_lava_ribbon(root: Node3D, pts: Array, max_hw: float, mat: StandardMaterial3D) -> void:
	var n := pts.size()
	var lefts: Array[Vector2] = []
	var rights: Array[Vector2] = []
	for i in n:
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == n - 1:
			dir = pts[n - 1] - pts[n - 2]
		else:
			dir = pts[i + 1] - pts[i - 1]
		if dir.length() < 0.0001:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		var perp := Vector2(-dir.y, dir.x)
		var hw := maxf(max_hw * sin(PI * float(i) / float(n - 1)), 0.02)   # taper both ends
		lefts.append(pts[i] + perp * hw)
		rights.append(pts[i] - perp * hw)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.06
	for i in n - 1:
		_ribbon_tri(st, lefts[i], rights[i], rights[i + 1], y)
		_ribbon_tri(st, lefts[i], rights[i + 1], lefts[i + 1], y)

	var mb := MeshInstance3D.new()
	mb.mesh = st.commit()
	mb.material_override = mat
	root.add_child(mb)


## One upward-facing ribbon triangle (CULL_DISABLED material, so winding is moot).
static func _ribbon_tri(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, y: float) -> void:
	for v in [a, b, c]:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(v.x, y, v.y))


## The molten sea around the island: a big mottled emissive plane below the rim.
static func _build_outer_lava(root: Node3D) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(260.0, 260.0)
	var mb := MeshInstance3D.new()
	mb.mesh = pm
	mb.position = Vector3(0.0, OUTER_LAVA_Y, 0.0)
	mb.material_override = _lava_sea_mat()
	root.add_child(mb)


## Dark columns rising out of the outer lava beyond the coast — tall framing pillars.
## Decorative (the player can't reach them) but x-ray, like the inner spires.
static func _add_outer_columns(root: Node3D, rng: RandomNumberGenerator, col_mats: Array) -> void:
	var placed: Array[Vector2] = []
	for i in 16:
		var ang := rng.randf_range(0.0, TAU)
		var coast := IslandShape.radius(ang)
		var d := rng.randf_range(coast * 1.08, coast * 1.7)
		var c := Vector2(cos(ang) * d, sin(ang) * d)
		var w := rng.randf_range(0.6, 1.4)
		var clash := false
		for q in placed:
			if c.distance_to(q) < w + 1.5:
				clash = true
				break
		if clash:
			continue
		placed.append(c)

		var h := rng.randf_range(3.5, 9.0)
		var mat := _column_mat(rng)
		mat.set_shader_parameter("column_origin", Vector3(c.x, 0.0, c.y))
		col_mats.append(mat)
		var mb := MeshInstance3D.new()
		mb.mesh = MeshFactory.beveled_box(Vector3(w, h, w * 0.85), 0.14)
		mb.material_override = mat
		mb.position = Vector3(c.x, OUTER_LAVA_Y + h * 0.5, c.y)   # base sits at the lava surface
		mb.rotation = Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.0, TAU), rng.randf_range(-0.1, 0.1))
		root.add_child(mb)


## Dark charred basalt — varied per instance so adjacent rocks differ.
static func _dark_rock_mat(rng: RandomNumberGenerator) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = ColorUtil.vary(Color(0.16, 0.11, 0.11), rng)
	m.roughness = clampf(0.92 + rng.randf_range(-0.06, 0.05), 0.0, 1.0)
	return m


## Smouldering coal — emissive enough to bloom past the glow threshold.
static func _ember_mat(rng: RandomNumberGenerator) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = ColorUtil.vary(Color(0.50, 0.10, 0.04), rng)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.30, 0.06)
	m.emission_energy_multiplier = 2.2
	m.roughness = 0.7
	return m


## Molten stream — brighter, hotter orange so the ribbon reads as flowing lava.
static func _lava_mat(rng: RandomNumberGenerator) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = ColorUtil.vary(Color(0.55, 0.14, 0.03), rng)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.42, 0.10)
	m.emission_energy_multiplier = 1.4
	m.roughness = 0.6
	return m


## A column's x-ray material: charred rock that opens a soft, cyan-rimmed window
## where the marine is hidden behind it. The player position is fed in each frame
## (Main updates "player_world"); see column_xray.gdshader.
static func _column_mat(rng: RandomNumberGenerator) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = COLUMN_SHADER
	var c := ColorUtil.vary(Color(0.16, 0.11, 0.11), rng)
	m.set_shader_parameter("albedo", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("rough", clampf(0.92 + rng.randf_range(-0.06, 0.05), 0.0, 1.0))
	return m


## The outer molten sea: warm molten mottling over dark cooled crust, from a tiled
## noise baked into the albedo. Unshaded, so a huge flat plane can't catch the key
## light's specular and bloom into a white lightbox; warm but always under the glow
## threshold, so the bright pops stay with the inner ribbons, embers, and columns.
static func _lava_sea_mat() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var ntex := NoiseTexture2D.new()
	ntex.width = 512
	ntex.height = 512
	ntex.seamless = true
	ntex.noise = noise

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.78, 0.22, 0.06)   # peak molten; noise multiplies it down to dark crust
	m.albedo_texture = ntex
	m.uv1_scale = Vector3(26.0, 26.0, 26.0)    # fine molten cells near the coast
	return m
