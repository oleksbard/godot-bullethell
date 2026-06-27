class_name WeaponRing
extends Node3D
## The player's guns. The first two are *held*: rigidly fixed in the marine's
## hands with the barrel aligned to the arm, so the marine aims them by swinging
## the whole arm (see Marine._aim_arms) — they never twist on their own. Any guns
## beyond the hands float in fixed slots around the player (Brotato-style) and aim
## themselves. Each frame the i-th gun targets the i-th closest imp (for firing
## and bolt homing).

const GunScript := preload("res://src/weapons/gun.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const ProjectileScript := preload("res://src/fx/projectile.gd")
const ShotSfxScript := preload("res://src/audio/shot_sfx.gd")
const ImpactSfxScript := preload("res://src/audio/impact_sfx.gd")
const TurretMountScript := preload("res://src/weapons/turret_mount.gd")

const RADIUS := 0.8          # how far the floating guns sit from the player
const HEIGHT := 1.0          # float height (~hand height)
const BOB_AMP := 0.08
const BOB_FREQ := 2.0
const TURRET_ANCHOR := Vector3(0.0, 1.25, 0.0)   # torso hub the floating-gun struts spring from (player-local)
const TURRET_BALL_DROP := 0.07                    # seat the gun just above its pivot ball
const HELD_SEAT := 0.17      # seat the held gun forward of the wrist, into the palm, along the barrel
const HELD_LIFT := 0.12      # raise the held gun a touch so it sits up in the hand, not sunk

# Max targeting range in world units. ~12 ≈ 500px ≈ two-thirds of the screen
# height (ortho size 18 over 720px ≈ 40px/unit). Imps farther than this are
# ignored, so a gun with nothing in range simply holds fire.
const MAX_RANGE := 12.0

@export var gun_count := 2   # fallback when no inventory; clamped to 0..12

var player: Node3D
var _inventory: Node         # Inventory (or null -> fall back to gun_count)
var _guns: Array[Node3D] = []
var _mounts: Array = []      # per-gun hand mount (Node3D) or null if it floats
var _turrets: Array = []     # per-gun TurretMount (floating guns) or null (held guns)
var _bob := 0.0
var _sfx: Node
var _impact: Node


func _ready() -> void:
	_sfx = ShotSfxScript.new()
	add_child(_sfx)
	_impact = ImpactSfxScript.new()
	add_child(_impact)

	# Prefer the player's inventory as the source of equipped guns; a non-marine
	# player (e.g. tests) has no `inventory`, so we fall back to `gun_count`.
	if player != null:
		_inventory = player.get("inventory")
	if _inventory != null:
		_inventory.changed.connect(_rebuild)
	_rebuild()


## (Re)build the gun nodes: one per equipped pistol (or `gun_count` with no inventory).
## The first guns go in the marine's hands (the rest float); a non-marine player has
## no hands, so every gun floats. Called on ready and whenever the inventory changes.
func _rebuild() -> void:
	for g in _guns:
		g.queue_free()
	for t in _turrets:
		if t != null:
			t.queue_free()
	_guns.clear()
	_mounts.clear()
	_turrets.clear()

	var hands: Array = []
	if player != null and player.has_method("get_hand_mounts"):
		hands = player.get_hand_mounts()

	var pistols: Array = []
	var n := clampi(gun_count, 0, 12)
	if _inventory != null:
		pistols = _inventory.equipped_pistols()
		n = clampi(pistols.size(), 0, 12)

	for i in n:
		var g: Node3D = GunScript.new()
		g.fired.connect(_on_gun_fired)
		# Each gun fires with its equipped pistol's level-scaled stats (defaults to base otherwise).
		if i < pistols.size():
			g.damage = pistols[i].damage_value()
			g.fire_interval = pistols[i].fire_interval_value()
			g.mag_size = pistols[i].magazine_size()
			g.reload_time = pistols[i].reload_time_value()
		# Stagger first shots so the guns fire individually, not in lockstep.
		g.stagger(GunScript.FIRE_INTERVAL * float(i) / float(maxi(n, 1)))
		add_child(g)
		if i < hands.size():
			g.held = true
			_mounts.append(hands[i])              # grip reference; marine aims it
			_turrets.append(null)                 # held guns ride the arm, no turret
		else:
			_mounts.append(null)
			var turret: Node3D = TurretMountScript.new()   # floating gun: mount it on a procedural turret arm
			add_child(turret)
			_turrets.append(turret)
		_guns.append(g)


func _process(delta: float) -> void:
	if player == null:
		return
	global_position = player.global_position     # follow position, ignore rotation
	_bob += delta * BOB_FREQ
	_assign_targets()                            # set each gun's target first

	# Held guns copy their hand grip's orientation (which the marine swings to aim),
	# scale-stripped so the bone's skeleton scale can't shrink them. Floating guns
	# sit in a ring and self-aim.
	var float_total := 0
	for m in _mounts:
		if m == null:
			float_total += 1
	var float_i := 0
	for i in _guns.size():
		if _mounts[i] != null:
			var grip: Node3D = _mounts[i]
			var b := grip.global_transform.basis.orthonormalized()
			_guns[i].global_transform = Transform3D(b, grip.global_position + (-b.z) * HELD_SEAT + Vector3.UP * HELD_LIFT)
		else:
			# Slots are spaced evenly and rotate WITH the marine's body, so they keep a
			# fixed position around the model as it turns (the ring node itself stays
			# unrotated, so the gun's own aim yaw is unaffected).
			var ang := TAU * float(float_i) / float(maxi(float_total, 1)) + player.rotation.y
			var y := HEIGHT + sin(_bob + float(i)) * BOB_AMP
			var slot := Vector3(cos(ang) * RADIUS, y, sin(ang) * RADIUS)
			_guns[i].position = slot
			if _turrets[i] != null:
				_turrets[i].set_span(TURRET_ANCHOR, slot - Vector3(0.0, TURRET_BALL_DROP, 0.0))
			float_i += 1


## Give each gun a target (it fires only when one is set + in range). Held guns
## take the marine's per-hand target (its half-sphere pick, so they shoot where the
## arm points and never cross). Floating guns just take the i-th closest imp.
func _assign_targets() -> void:
	var live: Array = []
	for n in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if is_instance_valid(n):
			live.append(n)
	var origin := player.global_position
	live.sort_custom(func(a, b):
		return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	for i in _guns.size():
		var t: Node3D = null
		if _mounts[i] != null and player.has_method("get_hand_target"):
			t = player.get_hand_target(i)         # held: marine's half-sphere pick
		elif i < live.size():
			t = live[i]                           # floating: i-th closest
		if is_instance_valid(t) and origin.distance_to(t.global_position) <= MAX_RANGE:
			_guns[i].set_target(t)
		else:
			_guns[i].clear_target()           # nothing in range -> this gun holds fire


## Aggregate reload state for the HUD's reload debuff: how many guns are reloading,
## plus the longest remaining fraction (0..1) and seconds — these drive the cooldown
## sweep so it empties exactly as the last gun finishes.
func reload_state() -> Dictionary:
	var count := 0
	var frac := 0.0
	var seconds := 0.0
	for g in _guns:
		if is_instance_valid(g) and g.is_reloading():
			count += 1
			frac = maxf(frac, g.reload_fraction())
			seconds = maxf(seconds, g.reload_remaining())
	return {"count": count, "frac": frac, "seconds": seconds}


## A gun fired — spawn a bolt in world space (under our parent, the composition
## root) so it doesn't move with the ring.
func _on_gun_fired(origin: Vector3, target: Node3D, damage: float) -> void:
	if not is_instance_valid(target):
		return
	_sfx.play()                          # random pistol shot per fire
	var p: Node3D = ProjectileScript.new()
	p.target = target
	p.damage = damage
	p.hit_enemy.connect(_impact.play)    # softer thud when this bolt connects
	get_parent().add_child(p)
	p.global_position = origin
