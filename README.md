# Warma 极简平台跳跃示例（Godot 4.7）

这是一个可直接运行的最小平台跳跃关卡。游戏逻辑分辨率是 **256×144**，默认窗口是 **768×432**，也就是 3 倍整数放大。

## 运行

1. 用 Godot 4.7 打开这个文件夹。
2. 打开 `main.tscn` 后按 F6，或按 F5 运行项目。
3. `A/D` 左右移动，`J` 跳跃，走到门附近后按 `W`。
4. 成功进门后，屏幕中央显示黑色的“已进门”。

## 文件作用

- `main.tscn`：背景、TileMapLayer、玩家、门和 HUD。
- `scripts/main.gd`：按 16 像素网格生成地面和平台。
- `scripts/player.gd`：玩家移动、重力和一段跳。
- `scripts/door.gd`：门的 Area2D 和 W 键。
- `tileset.tres`：把 `block.png` 做成带碰撞的 16×16 TileSet。

平台没有额外的 StaticBody2D，碰撞来自 TileMapLayer 使用的 TileSet。`warma.png` 是 6×17 像素，碰撞多边形的顶点是 `(-3,-9)`、`(3,-9)`、`(3,8)`、`(-3,8)`。

## 分辨率和像素对齐

256×144 的视口包含 16 列、 9 行 16 像素方块。地面是第 8 行，顶边是 `y=128`。玩家位于 `(85,120)`，碰撞多边形的底边是 `120+8=128`，两条边完全重合。

默认窗口 768×432 是 3 倍放大，项目启用了整数缩放。窗口尺寸不是整数倍时，Godot 会留出少量空白边缘，避免逻辑像素落在显示像素之间。

提供的 `background.png` 原始大小是 320×176，运行时从中心裁剪出 256×144。编辑器 2D 视图中会隐藏这张游戏背景，因此显示 Godot 默认底色。

## 调整参数

打开 `scripts/player.gd` 顶部：

```gdscript
@export var move_speed: float = 60.0
@export var jump_velocity: float = -112.0
@export var gravity: float = 300.0
```

`move_speed` 控制移动速度，`jump_velocity` 的绝对值控制跳跃高度，`gravity` 控制下落速度。
