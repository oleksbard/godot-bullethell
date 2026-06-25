extends RefCounted
## Builds the hell island: the same organic floating landmass as the prototype's
## coastline (IslandShape), reskinned as charred basalt — dark warm rock with a
## triplanar normal map, scattered rocks, and a few glowing "ember" rocks. Returns
## a single Node3D for the caller to add. Reference via `const HellIsland := preload(...)`.

const ColorUtil := preload("res://src/lib/color_util.gd")
const MeshFactory := preload("res://src/lib/mesh_factory.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")


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

	_scatter_rocks(root, rng)
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


## Scatter dark rocks across the surface; ~a third glow like coals (emissive +
## the environment's glow makes them bloom — the cheap "hell" tell).
static func _scatter_rocks(root: Node3D, rng: RandomNumberGenerator) -> void:
	for i in 14:
		var ang := rng.randf_range(0.0, TAU)
		var maxr := IslandShape.radius(ang) - 1.2
		if maxr < 1.0:
			continue
		var d := rng.randf_range(0.0, maxr)
		var rs := rng.randf_range(0.35, 0.8)

		var m := StandardMaterial3D.new()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if rng.randf() < 0.3:
			m.albedo_color = ColorUtil.vary(Color(0.50, 0.10, 0.04), rng)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.30, 0.06)
			m.emission_energy_multiplier = 2.2
			m.roughness = 0.7
		else:
			m.albedo_color = ColorUtil.vary(Color(0.16, 0.11, 0.11), rng)
			m.roughness = clampf(0.92 + rng.randf_range(-0.06, 0.05), 0.0, 1.0)

		var mb := MeshInstance3D.new()
		mb.mesh = MeshFactory.beveled_box(Vector3(rs, rs * 0.7, rs), 0.08)
		mb.material_override = m
		mb.position = Vector3(cos(ang) * d, 0.04, sin(ang) * d)
		mb.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(mb)
