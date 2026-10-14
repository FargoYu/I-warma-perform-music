extends Node
## A bounded pool for short, non-spatial puzzle feedback.

signal sfx_played(cue: StringName)

const SOUNDS := {
	&"land": preload("res://Assets/Audio/SFX/land.wav"),
	&"shoot_01": preload("res://Assets/Audio/SFX/shoot_01.wav"),
	&"shoot_02": preload("res://Assets/Audio/SFX/shoot_02.wav"),
	&"shoot_03": preload("res://Assets/Audio/SFX/shoot_03.wav"),
	&"giraffe_hit": preload("res://Assets/Audio/SFX/giraffe_hit.wav"),
	&"wall_hit": preload("res://Assets/Audio/SFX/wall_hit.wav"),
	&"pickup": preload("res://Assets/Audio/SFX/pickup.wav"),
	&"door": preload("res://Assets/Audio/SFX/door.wav"),
	&"restart": preload("res://Assets/Audio/SFX/restart.wav"),
	&"confirm": preload("res://Assets/Audio/SFX/confirm.wav"),
	&"pause": preload("res://Assets/Audio/SFX/pause.wav"),
	&"resume": preload("res://Assets/Audio/SFX/resume.wav"),
	&"time_down": preload("res://Assets/Audio/SFX/time_down.wav"),
	&"time_up": preload("res://Assets/Audio/SFX/time_up.wav"),
	&"complete": preload("res://Assets/Audio/SFX/complete.wav"),
}
const POOL_SIZE := 16

var _voices: Array[AudioStreamPlayer] = []
var _last_played: Dictionary = {}
var _shot_index := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in POOL_SIZE:
		var voice := AudioStreamPlayer.new()
		voice.name = "SFX%d" % index
		voice.bus = &"SFX"
		add_child(voice)
		_voices.append(voice)

func play_sfx(cue: StringName, gain_db: float = 0.0) -> void:
	if not SOUNDS.has(cue):
		return
	# Cap simultaneous impacts without losing rapid individual shot feedback.
	var now := Time.get_ticks_msec()
	if cue in [&"wall_hit", &"giraffe_hit", &"land"]:
		if now - int(_last_played.get(cue, -1000)) < 65:
			return
	_last_played[cue] = now
	var selected: AudioStreamPlayer = null
	for voice in _voices:
		if not voice.playing:
			selected = voice
			break
	if selected == null:
		# Prefer stealing a quiet impact over a pickup or completion cue.
		selected = _voices[0]
		for voice in _voices:
			if voice.volume_db < selected.volume_db:
				selected = voice
	selected.stop()
	selected.stream = SOUNDS[cue]
	selected.volume_db = gain_db
	selected.pitch_scale = 1.0
	selected.play()
	sfx_played.emit(cue)

func play_shot() -> void:
	var cues: Array[StringName] = [&"shoot_01", &"shoot_02", &"shoot_03"]
	play_sfx(cues[_shot_index % cues.size()], -2.0)
	_shot_index += 1

func set_sfx_volume_db(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"SFX"), clampf(value, -60.0, 6.0))

func set_puzzle_paused(value: bool) -> void:
	play_sfx(&"pause" if value else &"resume", -4.0)

