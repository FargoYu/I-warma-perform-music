@tool
extends AudioStreamPlayer
## Autoload player: scene changes and room restarts do not restart the music.

@export_range(0.0, 1.0, 0.01) var music_volume: float = 0.5:
	set(value):
		music_volume = clampf(value, 0.0, 1.0)
		volume_linear = music_volume

func _ready() -> void:
	volume_linear = music_volume
	if not Engine.is_editor_hint():
		play()
