class_name ObstacleField
extends RefCounted
## Movement obstacles generated alongside the hell island and queried by the marine
## and imps. Reference via `const ObstacleFieldScript := preload(...)`.
##
## Two primitives, both in the XZ plane:
##   * blockers — discs (point-capsules a == b, radius). Columns and lava-stones
##     (the glowing molten rocks) are impassable; resolve() pushes a body out.
##     (The capsule a != b form is still supported by resolve for future segments.)
##   * steps — discs (centre, radius) with a top height. resolve() lifts a body
##     standing over one onto its top, so dark rocks are climbed, not clipped into.
## Thin lava streams are passable, so they are decoration only (footprint reserved
## so rocks don't render on top of them, but they never block or lift).
##
## Pure math (no nodes), so the placement + resolution logic is unit-testable.

var blockers: Array[Dictionary] = []   # {a: Vector2, b: Vector2, r: float}
var steps: Array[Dictionary] = []      # {c: Vector2, r: float, top: float}
var _occ: Array[Dictionary] = []       # {c: Vector2, r: float} footprints, for overlap rejection


## A solid footprint at `c` (radius `r`) — a column or a lava-stone: blocks movement
## and occupies space.
func add_block(c: Vector2, r: float) -> void:
	blockers.append({"a": c, "b": c, "r": r})
	_occ.append({"c": c, "r": r})


## A dark rock at `c` (radius `r`) whose top sits at world height `top`: a body over
## it is lifted onto `top` instead of clipping inside.
func add_step(c: Vector2, r: float, top: float) -> void:
	steps.append({"c": c, "r": r, "top": top})
	_occ.append({"c": c, "r": r})


## Reserve a footprint (centre `c`, radius `r`) for passable decoration (a lava
## stream): it blocks nothing and lifts nothing, but later rocks won't sit on it.
func add_decor(c: Vector2, r: float) -> void:
	_occ.append({"c": c, "r": r})


## Does footprint (centre `c`, radius `r`) overlap an already-placed one? `limit`
## caps how many of the earliest footprints to test (-1 = all) — a fissure passes
## the count from before it started so its own segments don't reject each other.
func overlaps(c: Vector2, r: float, limit: int = -1) -> bool:
	var n := _occ.size() if limit < 0 else mini(limit, _occ.size())
	for i in n:
		var o: Dictionary = _occ[i]
		if c.distance_to(o["c"]) < r + o["r"]:
			return true
	return false


func occupancy_count() -> int:
	return _occ.size()


## Resolve a body at `pos` (radius `body_r`): push it out of every blocker it
## overlaps in XZ, then lift it onto the tallest rock it stands over — or onto the
## `ground` baseline (the terrain height under the body) if it's on no rock.
func resolve(pos: Vector3, body_r: float, ground: float = 0.0) -> Vector3:
	var p := Vector2(pos.x, pos.z)
	# A couple of relaxation passes so a body wedged against two blockers settles.
	for _pass in 2:
		for blk in blockers:
			var near := _closest_on_seg(p, blk["a"], blk["b"])
			var away := p - near
			var d := away.length()
			var min_d: float = blk["r"] + body_r
			if d < min_d:
				if d > 0.0001:
					p = near + away / d * min_d
				else:
					p = near + Vector2(min_d, 0.0)   # dead centre on the segment: shove along +X
	# Stand on top of the tallest rock whose disc we're over (else the ground baseline).
	var top := ground
	for s in steps:
		if p.distance_to(s["c"]) < s["r"] and s["top"] > top:
			top = s["top"]
	return Vector3(p.x, top, p.y)


## Closest point on segment a→b to point p (handles the degenerate a == b spire case).
static func _closest_on_seg(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return a
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return a + ab * t
