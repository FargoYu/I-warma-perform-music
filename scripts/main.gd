@tool
extends Node2D
## 关卡脚本：用 TileMapLayer 刷出本示例的方块布局。

@onready var blocks: TileMapLayer = $Blocks
@onready var completion_label: Label = %CompletionLabel

func _ready() -> void:
	add_to_group("game")
	_build_block_layout()

func _build_block_layout() -> void:
	# 每个格子是 16x16。第 10 行是地面。
	for x in range(20):
		blocks.set_cell(Vector2i(x, 10), 0, Vector2i(0, 0))

	# 两个小平台，之后可以在这里继续增加或改颜色砖块。
	for x in range(7, 13):
		blocks.set_cell(Vector2i(x, 8), 0, Vector2i(0, 0))
	for x in range(15, 19):
		blocks.set_cell(Vector2i(x, 6), 0, Vector2i(0, 0))

func show_completion() -> void:
	completion_label.visible = true
