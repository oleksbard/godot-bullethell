class_name WeaponRing
extends Node3D
## The player's guns, floating in fixed slots around them (Brotato-style). Tracks
## the player's *position* (not rotation, so guns don't spin when the marine
## turns), bobs them gently, and each frame aims the i-th gun at the i-th closest
## imp. No firing yet — aiming only.

const GunScript := preload("res://src/weapons/gun.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const ProjectileScript := preload("res://src/fx/projectile.gd")
const ShotSfxScript := preload("res://src/audio/shot_sfx.gd")

const RADIUS := 0.8          # how far the guns float from the player (close — almost in hand)
const HEIGHT := 1.0          # float height (~hand height)
const BOB_AMP := 0.08
const BOB_FREQ := 2.0

# Max targeting range in world units. ~12 ≈ 500px ≈ two-thirds of the screen
# height (ortho size 18 over 720px ≈ 40px/unit). Imps farther than this are
# ignored, so a gun with nothing in range simply holds fire.
const MAX_RANGE := 12.0

@export var gun_count := 2   # clamped to 1..12

var player: Node3D
var _guns: Array[Node3D] = []
var _bob := 0.0
var _sfx: Node


func _ready() -> void:
	_sfx = ShotSfxScript.new()
	add_child(_sfx)

	gun_count = clampi(gun_count, 1, 12)
	for i in gun_count:
		var g: Node3D = GunScript.new()
		g.fired.connect(_on_gun_fired)
		add_child(g)
		# Stagger first shots so the guns fire individually, not in lockstep.
		g.stagger(GunScript.FIRE_INTERVAL * float(i) / float(gun_count))
		_guns.append(g)


func _process(delta: float) -> void:
	if player == null:
		return
	global_position = player.global_position     # follow position, ignore rotation
	_bob += delta * BOB_FREQ
	for i in _guns.size():
		var ang := TAU * float(i) / float(_guns.size())
		var y := HEIGHT + sin(_bob + float(i)) * BOB_AMP
		_guns[i].position = Vector3(cos(ang) * RADIUS, y, sin(ang) * RADIUS)
	_assign_targets()


## Sort the live imps by distance to the player and aim gun i at the i-th closest;
## guns with no enemy left to cover hold their last heading.
func _assign_targets() -> void:
	var live: Array = []
	for n in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if is_instance_valid(n):
			live.append(n)
	var origin := player.global_position
	live.sort_custom(func(a, b):
		return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	for i in _guns.size():
		if i < live.size() and origin.distance_to(live[i].global_position) <= MAX_RANGE:
			_guns[i].set_target(live[i])
		else:
			_guns[i].clear_target()           # nothing in range -> this gun holds fire


## A gun fired — spawn a bolt in world space (under our parent, the composition
## root) so it doesn't move with the ring.
func _on_gun_fired(origin: Vector3, target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	_sfx.play()                          # random pistol shot per fire
	var p: Node3D = ProjectileScript.new()
	p.target = target
	get_parent().add_child(p)
	p.global_position = origin
