class_name ImpactSfx
extends Node
## Plays a random bullet-impact thud when a bolt kills an imp. Deliberately
## quieter than the gunshots (IMPACT_DB) so the shots stay dominant. Pooled
## players so a flurry of kills doesn't cut each other off; slight pitch jitter
## varies repeats. The three clips are already within ~1.5 dB of each other, so
## (unlike ShotSfx) they need no per-clip evening — one volume covers all.

const CLIPS := [
	"res://sound/impact_01.mp3",
	"res://sound/impact_02.mp3",
	"res://sound/impact_03.mp3",
]
const IMPACT_DB := -16.0      # well below the shot level — a soft "more quiet" thud
const POOL := 6
const PITCH_JITTER := 0.12

var _streams: Array[AudioStream] = []
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for path in CLIPS:
		var s: AudioStream = load(path)
		if s is AudioStreamMP3:
			s.loop = false        # one-shot — never loop a hit
		_streams.append(s)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = IMPACT_DB
		add_child(p)
		_players.append(p)


## Fire-and-forget: play a random impact clip on the next pooled player.
func play() -> void:
	if _streams.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[_rng.randi_range(0, _streams.size() - 1)]
	p.pitch_scale = 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	p.play()
