class_name WeaponRing
extends Node3D
## The player's guns. The first two are *held*: parented to the marine's hand
## bones so they sit in its grip, with their aim locked to the body's forward
## (the marine faces the nearest imp, so the held guns point at it). Any guns
## beyond the hands float in fixed slots around the player (Brotato-style) and
## aim themselves. Each frame the i-th gun targets the i-th closest imp.

const GunScript := preload("res://src/weapons/gun.gd")
const ImpScript := preload("res://src/enemies/imp.gd")
const ProjectileScript := preload("res://src/fx/projectile.gd")
const ShotSfxScript := preload("res://src/audio/shot_sfx.gd")

const RADIUS := 0.8          # how far the floating guns sit from the player
const HEIGHT := 1.0          # float height (~hand height)
const BOB_AMP := 0.08
const BOB_FREQ := 2.0
const GRIP_FWD := 0.18       # push held guns forward of the wrist so the barrel clears the fist

# Max targeting range in world units. ~12 ≈ 500px ≈ two-thirds of the screen
# height (ortho size 18 over 720px ≈ 40px/unit). Imps farther than this are
# ignored, so a gun with nothing in range simply holds fire.
const MAX_RANGE := 12.0

@export var gun_count := 2   # clamped to 1..12

var player: Node3D
var _guns: Array[Node3D] = []
var _mounts: Array = []      # per-gun hand mount (Node3D) or null if it floats
var _bob := 0.0
var _sfx: Node


func _ready() -> void:
	_sfx = ShotSfxScript.new()
	add_child(_sfx)

	# Held guns go in the marine's hands; the rest float. A non-marine player
	# (e.g. tests) exposes no hands, so every gun floats.
	var hands: Array = []
	if player != null and player.has_method("get_hand_mounts"):
		hands = player.get_hand_mounts()

	gun_count = clampi(gun_count, 1, 12)
	for i in gun_count:
		var g: Node3D = GunScript.new()
		g.fired.connect(_on_gun_fired)
		# Stagger first shots so the guns fire individually, not in lockstep.
		g.stagger(GunScript.FIRE_INTERVAL * float(i) / float(gun_count))
		if i < hands.size():
			g.held = true
			(hands[i] as Node3D).add_child(g)     # ride the hand bone
			_mounts.append(hands[i])
		else:
			add_child(g)
			_mounts.append(null)
		_guns.append(g)


func _process(delta: float) -> void:
	if player == null:
		return
	global_position = player.global_position     # follow position, ignore rotation
	_bob += delta * BOB_FREQ

	# Held guns are pinned to the hand and oriented to the body's forward (so they
	# aim wherever the marine faces). Floating guns sit in a ring and self-aim.
	var float_total := 0
	for m in _mounts:
		if m == null:
			float_total += 1
	var body := player.global_transform.basis.orthonormalized()
	var fwd := -body.z
	var float_i := 0
	for i in _guns.size():
		if _mounts[i] != null:
			var t := _guns[i].global_transform
			t.basis = body
			t.origin = (_mounts[i] as Node3D).global_position + fwd * GRIP_FWD
			_guns[i].global_transform = t
		else:
			var ang := TAU * float(float_i) / float(maxi(float_total, 1))
			var y := HEIGHT + sin(_bob + float(i)) * BOB_AMP
			_guns[i].position = Vector3(cos(ang) * RADIUS, y, sin(ang) * RADIUS)
			float_i += 1
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
