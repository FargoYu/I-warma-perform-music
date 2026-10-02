# Warma 平台跳跃示例（Godot 4.7）

逻辑分辨率为 **256×144**，默认窗口为 **1024×576**，即 4 倍整数缩放。

## 操作

- `A/D`：左右移动
- `J`：跳跃；轻按小跳，长按大跳
- `W`：在门附近进入

## 主要结构

- `main.tscn`：关卡、Warma、长颈鹿、门和 HUD。
- `scripts/player.gd`：Warma 的移动、跳跃、地面探测和向上托起长颈鹿。
- `giraffe.tscn`：可重复实例化的 `CharacterBody2D` 长颈鹿。
- `scripts/giraffe.gd`：长颈鹿的重力、实体碰撞和可复用的外部冲量入口。
- `tileset.tres`：16×16 TileSet；方块碰撞上下各缩进 0.01px。
- `docs/GODOT_LEARNING.md`：面向学习的 Godot 4.7 物理、碰撞查询和调试说明。

## 长颈鹿物理规则

长颈鹿使用单一完整碰撞体，由 `CharacterBody2D` 显式处理重力和移动；普通 Warma 接触只会产生移动约束，不会把 Warma 的水平速度转移给长颈鹿。长颈鹿压在 Warma 上方时，Warma 可以水平移动，长颈鹿不会被横向带走。

- Warma 横向碰到长颈鹿侧面时会停止，不能穿过它；长颈鹿的 X 位置也保持不变。
- Warma 从长颈鹿头顶走开时，不会靠摩擦把它带走。
- Warma 站在长颈鹿上可以正常起跳，长颈鹿不会跟着起跳。
- 长颈鹿在 Warma 头顶时不会把 Warma 压入地面。
- Warma 从下方起跳时，会给头顶长颈鹿一个仅竖直方向的物理冲量。

Warma 与长颈鹿通过同一个完整实体碰撞体处理顶部、底部和左右接触。轴向查询使用 `test_only` 后必须提交 `get_travel()`；垂直查询只提交垂直 travel，避免接触恢复把角色横向挤走。长颈鹿在普通接触时不主动扫描 Warma 的静止水平位移，从而不会被横向带走；下落和外部主动运动时会恢复对应方向的实体碰撞。Warma 的 `HeadProbe` 只负责识别从下方跳入的长颈鹿，并调用统一的外部冲量入口。长颈鹿位于 Warma 顶部时，Warma 的水平查询会把它视为垂直支撑而不是水平墙；真正的侧面接触仍然阻挡穿透。

## 小尺寸物理精度

本项目使用轴向 test-only 碰撞查询、`get_travel()` 提交和 2D 物理求解器设置提高小尺寸实体的精度：

- 120 次物理更新/秒
- 最大允许穿透：0.01px
- 最大接触分离：0.05px
- 接触复用半径：0.01px
- 求解迭代：32

Warma 使用 `CharacterBody2D.safe_margin = 0.001`；长颈鹿的完整形状使用零恢复余量，避免上下接触产生横向修正。

## 自动测试

```powershell
godot --headless --path . --script res://tests/player_physics_test.gd
godot --headless --path . --script res://tests/giraffe_physics_test.gd
```
