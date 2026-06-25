extends RefCounted
## Procedural mesh builders. Reference via `const MeshFactory := preload(...)`.

## A chamfered box: 6 inset faces + 12 edge chamfers + 8 corner triangles.
## Normals are set outward per-tri; pair with a CULL_DISABLED material so the
## solid renders regardless of winding.
static func beveled_box(size: Vector3, bevel: float) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b: float = min(bevel, min(hx, min(hy, hz)) * 0.85)

	var px := {}
	var py := {}
	var pz := {}
	for i in 2:
		for j in 2:
			for k in 2:
				var sx := -1.0 if i == 0 else 1.0
				var sy := -1.0 if j == 0 else 1.0
				var sz := -1.0 if k == 0 else 1.0
				var key := Vector3i(i, j, k)
				px[key] = Vector3(sx * hx, sy * (hy - b), sz * (hz - b))
				py[key] = Vector3(sx * (hx - b), sy * hy, sz * (hz - b))
				pz[key] = Vector3(sx * (hx - b), sy * (hy - b), sz * hz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# 6 inset faces
	_quad(st, px[Vector3i(1,1,1)], px[Vector3i(1,1,0)], px[Vector3i(1,0,0)], px[Vector3i(1,0,1)])
	_quad(st, px[Vector3i(0,1,1)], px[Vector3i(0,0,1)], px[Vector3i(0,0,0)], px[Vector3i(0,1,0)])
	_quad(st, py[Vector3i(1,1,1)], py[Vector3i(0,1,1)], py[Vector3i(0,1,0)], py[Vector3i(1,1,0)])
	_quad(st, py[Vector3i(1,0,1)], py[Vector3i(1,0,0)], py[Vector3i(0,0,0)], py[Vector3i(0,0,1)])
	_quad(st, pz[Vector3i(1,1,1)], pz[Vector3i(1,0,1)], pz[Vector3i(0,0,1)], pz[Vector3i(0,1,1)])
	_quad(st, pz[Vector3i(1,1,0)], pz[Vector3i(0,1,0)], pz[Vector3i(0,0,0)], pz[Vector3i(1,0,0)])

	# 12 edge chamfers
	for i in 2:
		for j in 2:
			var e0 := Vector3i(i, j, 0)
			var e1 := Vector3i(i, j, 1)
			_quad(st, px[e0], py[e0], py[e1], px[e1])
	for i in 2:
		for k in 2:
			var f0 := Vector3i(i, 0, k)
			var f1 := Vector3i(i, 1, k)
			_quad(st, px[f0], pz[f0], pz[f1], px[f1])
	for j in 2:
		for k in 2:
			var g0 := Vector3i(0, j, k)
			var g1 := Vector3i(1, j, k)
			_quad(st, py[g0], pz[g0], pz[g1], py[g1])

	# 8 corner triangles
	for i in 2:
		for j in 2:
			for k in 2:
				var key := Vector3i(i, j, k)
				_tri(st, px[key], py[key], pz[key])

	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.000001:
		return
	n = n.normalized()
	var ref := a + b + c                 # centroid direction from origin == outward
	if n.dot(ref) < 0.0:
		n = -n
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)
