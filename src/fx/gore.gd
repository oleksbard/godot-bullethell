class_name Gore
extends RefCounted
## Gore for an enemy: a burst of flying body-part chunks (gibs) — no ground decals, the
## whole effect is airborne meat. spawn_death() blows the body apart (a wide burst biased
## forward along the killing bolt); spawn_hit() sprays a smaller wound burst in the bolt's
## direction. Both scale the chunk count with the `damage` of the blow, so a weak weapon
## (SMG bolt) gibs far less than a heavy one (pistol) — plus a per-enemy `volume_mult` for
## bodies that gib heavier (zombie). Reference via `const Gore := preload(...)`.

const GibScript := preload("res://src/fx/gib.gd")

# ── Counts ───────────────────────────────────────────────────────────────────
const KILL_GIBS_PER_DAMAGE := 2.4   # kill chunks per point of the killing blow (5-dmg pistol ≈ 12, its old flat base)
const HIT_GIBS_PER_DAMAGE := 1.2    # non-lethal chunks per point of the hit (5-dmg pistol ≈ 6, its old flat base)
const KILL_GIBS_MIN := 3       # a kill always throws at least this many, however weak the blow
const HIT_GIBS_MIN := 1        # a non-lethal hit always sprays at least one fleck
const GIB_CAP := 26            # ponytail: hard ceiling per burst — gibs are per-node physics FX;
                               # pool / MultiMesh them if simultaneous wave-wipes ever spike node count

# ── Flight tuning (the knobs the burst is built from) ─────────────────────────
# DIRECTION — each chunk flies at a random yaw within ±cone of the bolt's travel, which
# points player -> monster -> onward, i.e. AWAY from the blow. Kept under ±90° so every
# chunk is thrown away from the blow (none spray back toward the player) while the cone
# still fans them out. A hit sprays a tighter forward jet off the wound.
const KILL_CONE := 1.2         # ±rad around the away-from-blow direction (~±69°: a forward fan)
const HIT_CONE := 0.7          # ±rad for a non-lethal hit (a tight forward jet)
# SPEED — horizontal launch speed range (units/s). Floor is well above zero so no chunk
# just dribbles out and piles on the corpse; ceiling is reined in so none rocket off far.
const SPEED_MIN := 4.0
const SPEED_MAX := 7.5
# ARC — upward launch speed range (units/s). Higher = higher pop + longer airtime, so the
# chunk lands farther out (radius grows with both speed and arc). Gravity lives on the gib.
const ARC_MIN := 3.5
const ARC_MAX := 6.0
# RADIUS — initial positional scatter around the body so chunks don't all erupt from one
# point; the speed/arc-driven travel spreads them the rest of the way.
const SPAWN_SCATTER := 0.35
const SPAWN_HEIGHT := 0.6      # erupt from roughly torso height
# CHUNKS — widely varied sizes so it reads as assorted body parts, not uniform cubes.
const GIB_SIZE_MIN := 0.10
const GIB_SIZE_MAX := 0.32
const SPIN := 18.0             # max rad/s tumble on each axis


## Blow the body apart at `pos`: chunks scaled by `damage` (× `volume_mult` for a heavier
## body) in a wide burst biased along `hit_dir`. Optional `gib_colors` mixes tints (e.g. the
## zombie's red+green meat); an empty list tints every chunk with `color` (the body colour).
static func spawn_death(parent: Node, pos: Vector3, color: Color, damage: float, hit_dir: Vector3 = Vector3.ZERO, gib_colors: Array = [], volume_mult: float = 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fwd := _forward(hit_dir, rng)
	var count := clampi(int(round(damage * KILL_GIBS_PER_DAMAGE * volume_mult)), KILL_GIBS_MIN, GIB_CAP)
	_burst(parent, pos, color, rng, fwd, count, KILL_CONE, gib_colors)


## Lighter feedback for a hit that does NOT kill: a small flesh burst sprayed forward along
## `hit_dir` (a tight cone), tinted with the enemy's body colour.
static func spawn_hit(parent: Node, pos: Vector3, color: Color, damage: float, hit_dir: Vector3 = Vector3.ZERO) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fwd := _forward(hit_dir, rng)
	var count := clampi(int(round(damage * HIT_GIBS_PER_DAMAGE)), HIT_GIBS_MIN, GIB_CAP)
	_burst(parent, pos, color, rng, fwd, count, HIT_CONE, [])


## Horizontal travel direction from the killing bolt; a random heading if none was supplied
## (e.g. a wave wipe) so the burst still reads directional rather than a symmetric pop.
static func _forward(hit_dir: Vector3, rng: RandomNumberGenerator) -> Vector3:
	var fwd := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if fwd.length() < 0.01:
		var a := rng.randf_range(0.0, TAU)
		return Vector3(cos(a), 0.0, sin(a))
	return fwd.normalized()


## Launch `count` chunks around `fwd`, spread within ±`cone`, each with its own speed, arc,
## spin, size and a little spawn scatter — an eruption of body parts.
static func _burst(parent: Node, pos: Vector3, color: Color, rng: RandomNumberGenerator, fwd: Vector3, count: int, cone: float, gib_colors: Array) -> void:
	var base := pos + Vector3(0.0, SPAWN_HEIGHT, 0.0)
	for i in count:
		var g := GibScript.new()
		g.color = gib_colors[rng.randi_range(0, gib_colors.size() - 1)] if not gib_colors.is_empty() else color
		g.size = rng.randf_range(GIB_SIZE_MIN, GIB_SIZE_MAX)
		parent.add_child(g)
		var scatter := Vector3(rng.randf_range(-SPAWN_SCATTER, SPAWN_SCATTER), 0.0, rng.randf_range(-SPAWN_SCATTER, SPAWN_SCATTER))
		g.global_position = base + scatter
		var horiz := fwd.rotated(Vector3.UP, rng.randf_range(-cone, cone))
		var vel := horiz * rng.randf_range(SPEED_MIN, SPEED_MAX)
		vel.y = rng.randf_range(ARC_MIN, ARC_MAX)
		var spin := Vector3(rng.randf_range(-SPIN, SPIN), rng.randf_range(-SPIN, SPIN), rng.randf_range(-SPIN, SPIN))
		g.launch(vel, spin)
