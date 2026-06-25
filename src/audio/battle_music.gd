class_name BattleMusic
extends Node
## Battle music bed. Plays the tracks in random order (never the same one twice
## in a row), sits quietly under the SFX (MUSIC_DB), and fades out when no imps
## are alive. If the lull is short the same track fades back in; if it fully
## faded out, the next wave starts a fresh random track.

const ImpScript := preload("res://src/enemies/imp.gd")

const TRACKS := [
	"res://music/battle_01.mp3",
	"res://music/battle_02.mp3",
	"res://music/battle_03.mp3",
]
const MUSIC_DB := -18.0          # quiet bed — under shots (~-8) and impacts (-16)
const SILENCE_DB := -60.0        # treated as "off"
const FADE_IN_DB_PER_SEC := 300.0   # near-instant (~0.15s) when a wave appears
const FADE_OUT_DB_PER_SEC := 26.0   # gentle (~1.6s) once the wave is cleared

var _player: AudioStreamPlayer
var _streams: Array[AudioStream] = []
var _rng := RandomNumberGenerator.new()
var _last := -1                  # last track index — avoid back-to-back repeats


func _ready() -> void:
	_rng.randomize()
	for path in TRACKS:
		var s: AudioStream = load(path)
		if s is AudioStreamMP3:
			s.loop = false       # we chain random tracks ourselves on `finished`
		_streams.append(s)
	_player = AudioStreamPlayer.new()
	_player.volume_db = SILENCE_DB
	_player.finished.connect(_play_random)   # one track ends -> next random one
	add_child(_player)


func _process(delta: float) -> void:
	var fighting := _enemies_alive()
	if fighting and not _player.playing:
		_play_random()
	var target := MUSIC_DB if fighting else SILENCE_DB
	var rate := FADE_IN_DB_PER_SEC if fighting else FADE_OUT_DB_PER_SEC
	_player.volume_db = move_toward(_player.volume_db, target, rate * delta)
	# Fully faded with nothing to fight -> stop, so the next wave gets a fresh track.
	if not fighting and _player.playing and _player.volume_db <= SILENCE_DB:
		_player.stop()


## True as soon as one live imp exists (returns early — cheap during a wave).
func _enemies_alive() -> bool:
	for imp in get_tree().get_nodes_in_group(ImpScript.GROUP):
		if is_instance_valid(imp):
			return true
	return false


func _play_random() -> void:
	if _streams.is_empty():
		return
	var idx := _rng.randi_range(0, _streams.size() - 1)
	while _streams.size() > 1 and idx == _last:
		idx = _rng.randi_range(0, _streams.size() - 1)
	_last = idx
	_player.stream = _streams[idx]
	_player.play()
