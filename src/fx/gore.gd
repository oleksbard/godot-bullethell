class_name Gore
extends RefCounted
## Gore for an enemy: a burst of flying body-part chunks (gibs) — no ground decals, the
## whole effect is airborne meat. spawn_death() blows the body apart (a wide burst biased
## forward along the killing bolt); spawn_hit() sprays a smaller wound burst in the bolt's
## direction. Callers pass a `gore_amount` (their projectile type) so a heavy weapon throws
## more chunks. Reference via `const Gore := preload(...)` and call Gore.spawn_death(...).

const GibScript := preload("res://src/fx/gib.gd")

# ── Counts ───────────────────────────────────────────────────────────────────
const KILL_GIBS := 12          # base chunks a kill throws (+ gore_amount from the killer)
const HIT_GIBS := 6            # chunks a non-lethal hit sprays off the wound
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


## Blow the body apart at `pos`: KILL_GIBS (+ gore_amount) chunks in a wide burst biased
## along `hit_dir`. Optional `gib_colors` mixes tints (e.g. the zombie's red+green meat);
## an empty list tints every chunk with `color` (the enemy's body colour).
static func spawn_death(parent: Node, pos: Vector3, color: Color, gore_amount: int, hit_dir: Vector3 = Vector3.ZERO, gib_colors: Array = []) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fwd := _forward(hit_dir, rng)
	var count := mini(KILL_GIBS + maxi(0, gore_amount), GIB_CAP)
	_burst(parent, pos, color, rng, fwd, count, KILL_CONE, gib_colors)


## Lighter feedback for a hit that does NOT kill: a small flesh burst sprayed forward along
## `hit_dir` (a tight cone), tinted with the enemy's body colour.
static func spawn_hit(parent: Node, pos: Vector3, color: Color, hit_dir: Vector3 = Vector3.ZERO) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fwd := _forward(hit_dir, rng)
	_burst(parent, pos, color, rng, fwd, HIT_GIBS, HIT_CONE, [])


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
