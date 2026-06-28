class_name InventorySfx
extends Node
## One-shot UI sounds for the grid inventory: pick (lift an item out of a slot) and
## drop (seat it into one). Owned by the WaveMenu, which plays while the tree is
## PAUSED — so this node runs with PROCESS_MODE_ALWAYS and its pooled players inherit
## it, otherwise the pause would mute them. A small shared pool keeps a fast
## click-drag from cutting clips off; slight pitch jitter varies repeats so they read
## as physical. One clip each for now; drop in pick_02/drop_02 and randomise later.

const PICK := "res://sound/inventory_pick.mp3"
const DROP := "res://sound/inventory_drop.mp3"
const VOLUME_DB := -6.0       # clear UI level; tune to taste against the music bed
const POOL := 4
const PITCH_JITTER := 0.06

var _pick: AudioStream
var _drop: AudioStream
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS    # play while the level-up menu pauses the tree
	_rng.randomize()
	_pick = _load_oneshot(PICK)
	_drop = _load_oneshot(DROP)
	for _i in POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = VOLUME_DB
		add_child(p)            # inherits ALWAYS from this node
		_players.append(p)


## Fire-and-forget: the "lift an item" sound.
func play_pick() -> void:
	_play(_pick)


## Fire-and-forget: the "seat an item into a slot" sound.
func play_drop() -> void:
	_play(_drop)


static func _load_oneshot(path: String) -> AudioStream:
	var s: AudioStream = load(path)
	if s is AudioStreamMP3:
		s.loop = false        # one-shot — never loop a UI blip
	return s


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	p.play()
