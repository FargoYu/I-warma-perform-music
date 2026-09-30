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
    # The 256x144 viewport contains 16 columns by 9 rows of 16px tiles.
    blocks.clear()
    for x in range(16):
        blocks.set_cell(Vector2i(x, 8), 0, Vector2i(0, 0))

    # Two small platforms.
    for x in range(7, 13):
        blocks.set_cell(Vector2i(x, 6), 0, Vector2i(0, 0))
    for x in range(12, 16):
        blocks.set_cell(Vector2i(x, 4), 0, Vector2i(0, 0))

func show_completion() -> void:
    completion_label.visible = true
