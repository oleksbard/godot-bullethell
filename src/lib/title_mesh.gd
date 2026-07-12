extends RefCounted
## Procedural molten-monolith 3D title mesh. `TitleMesh.build("HELL\nMARINE")`
## returns an ArrayMesh of authored faces — no font, no textures:
##   - letter TOPOLOGY comes from a tiny hand-authored fill-grid (below), one entry
##     per letter used in the title. It only says which cells are solid.
##   - the GEOMETRY is generated: each glyph becomes one thick eroded mass whose
##     boundary vertices are noise-jittered (so the grid dissolves into a pitted
##     silhouette), with tapering DRIPS melting off the bottom edge.
##   - per-vertex heat is baked into vertex COLOR as a lava ramp (dark-red → orange
##     → yellow-white), hot across the whole form and hottest at the drips, for the
##     actively-molten look. Pair with molten_title.gdshader (EMISSION = COLOR).
## Faces are flat-shaded (per-tri normals, CULL_DISABLED) like MeshFactory. Fully
## deterministic. Reference via `const TitleMesh := preload(...)`.

const CELL := 0.13            # world units per grid cell (bigger = more readable letters)
const DEPTH := 0.22           # slab thickness (Z)
const LETTER_GAP := 1         # empty cells between letters
const LINE_GAP := 1           # empty rows between lines
const GLYPH_W := 5
const GLYPH_H := 7

const XY_JIT := 0.012         # silhouette erosion — subtle, keep strokes crisp (not wobbly)
const Z_JIT := 0.03           # front/back surface lump
const DRIP_CHANCE := 0.42     # fraction of bottom-edge cells that drip
const DRIP_MIN := 0.08
const DRIP_MAX := 0.34
const HEAT_BASE := 0.5        # molten but not white-hot: mostly mid-orange
const HEAT_VAR := 0.5
const HEAT_BASE_BIAS := 0.18  # extra heat toward the bottom (drips glow hottest)

# Fill-grids (5 wide × 7 tall) for the letters in HELL MARINE. '#' = solid.
const GLYPHS := {
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"A": ["..#..", ".#.#.", "#...#", "#...#", "#####", "#...#", "#...#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"N": ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"],
}


static func build(text: String) -> ArrayMesh:
	var lines := text.split("\n", false)
	if lines.is_empty():
		return ArrayMesh.new()

	# --- layout: measure each line, find the widest for centring ---
	var line_widths := PackedInt32Array()
	var max_cols := 0
	for line in lines:
		var n := line.length()
		var w := 0 if n == 0 else n * GLYPH_W + (n - 1) * LETTER_GAP
		line_widths.append(w)
		max_cols = maxi(max_cols, w)
	var total_rows := lines.size() * GLYPH_H + (lines.size() - 1) * LINE_GAP

	# --- collect solid cells in one global grid (centre each line) ---
	var filled := {}
	for i in lines.size():
		var line: String = lines[i]
		var start_col := int((max_cols - line_widths[i]) / 2.0)
		var row_base := i * (GLYPH_H + LINE_GAP)
		for j in line.length():
			var glyph = GLYPHS.get(line[j].to_upper())
			if glyph == null:
				continue
			var letter_col := start_col + j * (GLYPH_W + LETTER_GAP)
			for r in GLYPH_H:
				var rowstr: String = glyph[r]
				for c in GLYPH_W:
					if rowstr[c] == "#":
						filled[Vector2i(letter_col + c, row_base + r)] = true
	if filled.is_empty():
		return ArrayMesh.new()

	var min_y := -total_rows * 0.5 * CELL
	var max_y := total_rows * 0.5 * CELL
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.frequency = 3.0
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for cell in filled.keys():
		var col: int = cell.x
		var row: int = cell.y
		var center := Vector3(_wx(col + 0.5, max_cols), _wy(row + 0.5, total_rows), 0.0)

		var tlf := _node(col, row, 1, max_cols, total_rows)
		var trf := _node(col + 1, row, 1, max_cols, total_rows)
		var brf := _node(col + 1, row + 1, 1, max_cols, total_rows)
		var blf := _node(col, row + 1, 1, max_cols, total_rows)
		var tlb := _node(col, row, -1, max_cols, total_rows)
		var trb := _node(col + 1, row, -1, max_cols, total_rows)
		var brb := _node(col + 1, row + 1, -1, max_cols, total_rows)
		var blb := _node(col, row + 1, -1, max_cols, total_rows)

		_quad(st, tlf, blf, brf, trf, center, min_y, max_y, noise)      # front (+Z)
		_quad(st, tlb, trb, brb, blb, center, min_y, max_y, noise)      # back (-Z)

		if not filled.has(Vector2i(col - 1, row)):
			_quad(st, tlf, tlb, blb, blf, center, min_y, max_y, noise)  # left
		if not filled.has(Vector2i(col + 1, row)):
			_quad(st, trf, brf, brb, trb, center, min_y, max_y, noise)  # right
		if not filled.has(Vector2i(col, row - 1)):
			_quad(st, tlf, trf, trb, tlb, center, min_y, max_y, noise)  # top
		if not filled.has(Vector2i(col, row + 1)):
			_quad(st, blf, blb, brb, brf, center, min_y, max_y, noise)  # bottom
			if _hash01(col, row, 99) < DRIP_CHANCE:
				_drip(st, col, row, blf, brf, brb, blb, max_cols, total_rows, min_y, max_y, noise)

	return st.commit()


# --- a tapering spike melting off the bottom edge of a cell -------------------
static func _drip(st: SurfaceTool, col: int, row: int, blf: Vector3, brf: Vector3,
		brb: Vector3, blb: Vector3, max_cols: int, total_rows: int,
		min_y: float, max_y: float, noise: FastNoiseLite) -> void:
	var base_c := Vector3(_wx(col + 0.5, max_cols), _wy(row + 1, total_rows), 0.0)
	var dlen := lerpf(DRIP_MIN, DRIP_MAX, _hash01(col, row, 77))
	var apex := base_c + Vector3((_hash01(col, row, 78) * 2.0 - 1.0) * CELL * 0.2,
		-dlen, (_hash01(col, row, 79) * 2.0 - 1.0) * CELL * 0.2)
	var f := 0.35                                   # pinch the neck toward the cell centre
	var b0 := blf.lerp(base_c, f)
	var b1 := brf.lerp(base_c, f)
	var b2 := brb.lerp(base_c, f)
	var b3 := blb.lerp(base_c, f)
	_tri(st, b0, b1, apex, base_c, min_y, max_y, noise)
	_tri(st, b1, b2, apex, base_c, min_y, max_y, noise)
	_tri(st, b2, b3, apex, base_c, min_y, max_y, noise)
	_tri(st, b3, b0, apex, base_c, min_y, max_y, noise)


# --- geometry helpers ---------------------------------------------------------
static func _wx(gc: float, max_cols: int) -> float:
	return (gc - max_cols * 0.5) * CELL


static func _wy(gr: float, total_rows: int) -> float:
	return (total_rows * 0.5 - gr) * CELL


static func _node(gc: int, gr: int, zside: int, max_cols: int, total_rows: int) -> Vector3:
	var jx := (_hash01(gc, gr, 1) * 2.0 - 1.0) * XY_JIT    # xy jitter shared front/back → clean eroded prism
	var jy := (_hash01(gc, gr, 2) * 2.0 - 1.0) * XY_JIT
	var jz := (_hash01(gc, gr, 10 + zside) * 2.0 - 1.0) * Z_JIT
	return Vector3(_wx(gc, max_cols) + jx, _wy(gr, total_rows) + jy, zside * DEPTH * 0.5 + jz)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ref: Vector3, min_y: float, max_y: float, noise: FastNoiseLite) -> void:
	_tri(st, a, b, c, ref, min_y, max_y, noise)
	_tri(st, a, c, d, ref, min_y, max_y, noise)


## Emit one flat-shaded tri; normal is oriented outward from `ref`, and each vertex
## gets its lava colour from local heat.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ref: Vector3,
		min_y: float, max_y: float, noise: FastNoiseLite) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.000001:
		return
	n = n.normalized()
	var mid := (a + b + c) / 3.0
	if n.dot(mid - ref) < 0.0:
		n = -n
	for v in [a, b, c]:
		st.set_color(_lava(_heat(v, min_y, max_y, noise)))
		st.set_normal(n)
		st.add_vertex(v)


# --- heat / colour ------------------------------------------------------------
static func _heat(p: Vector3, min_y: float, max_y: float, noise: FastNoiseLite) -> float:
	var n := noise.get_noise_3d(p.x, p.y, p.z)             # -1..1
	var vertical := clampf((max_y - p.y) / maxf(max_y - min_y, 0.001), 0.0, 1.0)   # 0 top → 1 bottom
	return clampf(HEAT_BASE + n * 0.5 * HEAT_VAR + vertical * HEAT_BASE_BIAS, 0.0, 1.0)


static func _lava(h: float) -> Color:
	var cool := Color(0.22, 0.02, 0.0)
	var mid := Color(0.85, 0.18, 0.02)
	var hot := Color(1.0, 0.5, 0.12)
	if h < 0.5:
		return cool.lerp(mid, h / 0.5)
	return mid.lerp(hot, (h - 0.5) / 0.5)


static func _hash01(a: int, b: int, c: int) -> float:
	var h: int = a * 73856093
	h = h ^ (b * 19349663)
	h = h ^ (c * 83492791)
	return float(absi(h) % 100000) / 100000.0
