extends RefCounted
## The island's coastline shape + ring topology — pure, deterministic, testable.
## Reference via `const IslandShape := preload(...)`. Grass planting and the
## player's edge clamp both query this so everything matches the real coastline.

const BASE := 30.6   ## base radius in world units (3x the prototype's 12, then -15%)


## Organic coastline: base radius modulated by a few sine waves so the outline
## wobbles like a real island instead of a circle (or a square).
static func radius(angle: float) -> float:
	return BASE * (
		1.0
		+ 0.16 * sin(3.0 * angle + 0.7)
		+ 0.09 * sin(5.0 * angle - 1.3)
		+ 0.06 * sin(7.0 * angle + 2.1)
	)


## A vertex on ring `rs` (fraction of full radius) at height `y`, for segment
## `i` of `seg` around the circle.
static func ring_vertex(rs: float, y: float, i: int, seg: int) -> Vector3:
	var ang := TAU * float(i) / float(seg)
	var r := radius(ang) * rs
	return Vector3(r * cos(ang), y, r * sin(ang))
