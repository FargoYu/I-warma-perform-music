# Warma 极简平台跳跃示例（Godot 4.7）

这是一个可以直接运行的最小平台跳跃关卡。游戏逻辑分辨率是 **320×180**，启动窗口默认是 **960×540**（3 倍放大），并且保持像素清晰。

## 运行

1. 用 Godot 4.7 打开这个文件夹。
2. 双击 `main.tscn`，或直接按右上角的运行按钮。
3. 操作：`A/D` 左右移动，`J` 跳跃，走到门附近后按 `W`。
4. 成功进门后，屏幕中央会显示黑色的“已进门”。

## 文件分别做什么

- `main.tscn`：把背景、TileMapLayer、玩家、门和文字放在一起的场景。
- `scripts/main.gd`：在 TileMapLayer 里刷出地面和两个平台，并显示过关文字。
- `scripts/player.gd`：玩家移动、重力和单段跳。
- `scripts/door.gd`：检测玩家是否在门的 Area2D 内，以及 W 键。
- `tileset.tres`：把 `block.png` 做成 16×16 的 TileSet，并设置方块碰撞。
- `Assets/Sprites/`：你提供的四张素材。

`main.gd` 使用了 `@tool`，所以打开场景时编辑器也会把示例砖块画出来；真正运行时会再次执行同一段布局代码。

## 两种“大小”不要混淆

`320×180` 是游戏世界的逻辑大小，所以素材的像素位置很好计算；`960×540` 是显示器上看到的启动窗口大小。想改默认显示大小时，只改 `project.godot` 中的：

```ini
window/size/window_width_override=960
window/size/window_height_override=540
```

不要把 `viewport_width` 和 `viewport_height` 改成显示器分辨率，否则像素关卡的坐标会一起改变。运行后也可以直接拖动窗口边缘调整大小。

## 之后最常改的参数

打开 `scripts/player.gd` 顶部，就能看到：

```gdscript
@export var move_speed: float = 60.0
@export var jump_velocity: float = -112.0
@export var gravity: float = 300.0
```

速度越大，左右走得越快；`jump_velocity` 的绝对值越大，跳得越高；`gravity` 越大，下落越快。因为变量用了 `@export`，运行前也能在 Godot Inspector 里改。

## 增加或移动砖块

打开 `scripts/main.gd` 的 `_build_block_layout()`：

- `Vector2i(x, 10)` 是地面第 10 行。
- `Vector2i(x, 8)` 是第一个平台。
- `Vector2i(x, 6)` 是第二个平台。

例如把 `range(7, 13)` 改成 `range(5, 15)`，第一个平台就会变长。以后有了其他颜色的砖块，只要给 TileSet 增加新的 atlas source，就能把 `source_id` 和 `atlas_coords` 换成新砖块。

## 推荐的学习顺序

先只改 `move_speed`，观察变化；再改平台的 `range()`；然后阅读 `player.gd` 里的 `is_on_floor()`，理解为什么它限制了只能一段跳；最后再尝试在 `door.gd` 中把“已进门”换成切换到下一关。
