class_name ShotSfx
extends Node
## Plays a random pistol-shot sample on each gun fire. The raw clips have very
## different loudness (measured peaks below span ~19 dB), so each one gets a
## per-clip volume trim at load that brings them to the SAME effective peak —
## 90% of the loudest clip's level — so the random shots sound even. Slight pitch
## jitter keeps repeats from sounding identical.

const CLIPS := [
	"res://sound/pistol_01.mp3",
	"res://sound/pistol_02.mp3",
	"res://sound/pistol_03.mp3",
	"res://sound/pistol_04.mp3",
	"res://sound/pistol_05.mp3",
]
# Measured max peak (dBFS) per clip, same order as CLIPS (ffmpeg volumedetect).
const CLIP_PEAKS_DB := [-1.0, -4.3, -14.2, -16.6, -20.4]
const MASTER_DB := -8.0       # overall modest level
const NINETY_PCT_DB := -0.92  # 20*log10(0.9): "90% of the loudest"
const POOL := 4
const PITCH_JITTER := 0.08

var _streams: Array[AudioStream] = []
var _volumes: Array[float] = []     # per-clip volume_db so all hit the same peak
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	configure(CLIPS, CLIP_PEAKS_DB)        # default: the pistol set


## Load an arbitrary clip set, evening each clip to a common effective peak. An empty
## peaks_db skips the per-clip trim (all clips play at the master level).
func configure(clips: Array, peaks_db: Array) -> void:
	_streams.clear()
	_volumes.clear()
	var have_peaks := peaks_db.size() == clips.size()
	var loudest := -120.0
	if have_peaks:
		for v in peaks_db:
			loudest = maxf(loudest, v)
	var target: float = loudest + MASTER_DB + NINETY_PCT_DB
	for i in clips.size():
		var s: AudioStream = load(clips[i])
		if s is AudioStreamMP3:
			s.loop = false
		_streams.append(s)
		_volumes.append((target - peaks_db[i]) if have_peaks else MASTER_DB)


## Fire-and-forget: play a random clip (volume-evened) on the next pooled player.
func play() -> void:
	if _streams.is_empty():
		return
	var idx := _rng.randi_range(0, _streams.size() - 1)
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[idx]
	p.volume_db = _volumes[idx]
	p.pitch_scale = 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	p.play()
