@tool
extends Node2D
## Build the example layout with a 16-pixel TileMapLayer grid.

@onready var blocks: TileMapLayer = $Blocks
@onready var completion_label: Label = %CompletionLabel

func _ready() -> void:
	add_to_group("game")
	# Show the supplied background while playing, but leave the editor canvas
	# at Godot's default color so pixel edges are easy to inspect.
	$Background.visible = not Engine.is_editor_hint()
	_build_block_layout()

func _build_block_layout() -> void:
	pass

func show_completion() -> void:
	completion_label.visible = true
