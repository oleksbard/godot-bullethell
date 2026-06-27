extends RefCounted
## The island's coastline shape + ring topology — pure, deterministic, testable.
## Reference via `const IslandShape := preload(...)`. Grass planting and the
## player's edge clamp both query this so everything matches the real coastline.

const BASE := 30.6   ## base radius in world units (3x the prototype's 12, then -15%)
const HILL_AMP := 1.6          ## peak rolling-hill height (world units)
const HILL_TAPER_START := 0.82 ## radial fraction where the hills start fading to a flat coast


## Organic coastline: base radius modulated by a few sine waves so the outline
## wobbles like a real island instead of a circle (or a square).
static func radius(angle: float) -> float:
	return BASE * (
		1.0
		+ 0.16 * sin(3.0 * angle + 0.7)
		+ 0.09 * sin(5.0 * angle - 1.3)
		+ 0.06 * sin(7.0 * angle + 2.1)
	)


## Gentle rolling-hill height of the island top at world XZ. A low-frequency
## sine-sum undulation (same spirit as radius()), bounded to +/- HILL_AMP and
## tapered to 0 toward the coast so the rim stays flat and meets the cliff. Pure
## and allocation-free — safe to call per-body per-frame; the mesh, the bodies,
## and every ground-placed decoration all sample this one function.
static func surface_height(x: float, z: float) -> float:
	var ang := atan2(z, x)
	var coast := radius(ang)
	if coast < 0.001:
		return 0.0
	var f := sqrt(x * x + z * z) / coast      # 0 at centre .. 1 at coast
	if f >= 1.0:
		return 0.0
	var taper := 1.0 - smoothstep(HILL_TAPER_START, 1.0, f)
	# A few mid-frequency waves so SEVERAL hills fit across the camera view. The old
	# 0.07-0.18 freqs had 35-90u wavelengths => barely one hill per island, which read
	# as flat. These give ~10-20u hills. |.| <= 1.8 total -> normalise to [-1, 1].
	var h := (
		sin(x * 0.33 + 0.4) * cos(z * 0.31 - 0.9)
		+ 0.5 * sin(x * 0.60 - 1.7) * cos(z * 0.55 + 2.3)
		+ 0.3 * sin((x + z) * 0.45 + 0.6)
	)
	return (h / 1.8) * HILL_AMP * taper


## A vertex on ring `rs` (fraction of full radius) at height `y`, for segment
## `i` of `seg` around the circle.
static func ring_vertex(rs: float, y: float, i: int, seg: int) -> Vector3:
	var ang := TAU * float(i) / float(seg)
	var r := radius(ang) * rs
	return Vector3(r * cos(ang), y, r * sin(ang))
