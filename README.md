# Warma 平台跳跃示例（Godot 4.7）

逻辑分辨率为 **256×144**，默认窗口为 **1024×576**，即 4 倍整数缩放。

## 操作

- `A/D`：左右移动
- `J`：跳跃；轻按小跳，长按大跳
- `W`：在门附近切换到门指定的房间
- `K`：拾取灭火器后发射音乐子弹；子弹碰到方块会消失，击中长颈鹿会让它沿发射方向移动
- `R`：死亡并重置当前房间；下落到屏幕底部也会触发死亡

死亡时主角闪烁两次，然后恢复进入当前房间时的状态，包括位置、长颈鹿、拾取物和装备，并清除音符。死亡动画封装在 `Warma.play_death_animation()` 中，之后可单独替换；Inspector 的 `Death Flash Duration` 控制每次隐藏或显示的时长（默认 0.08 秒）。

## 主要结构

- [rooms/main.tscn](rooms/main.tscn)：项目默认启动房间，保留原来的地形和对象摆放。
- [rooms/roomX.tscn](rooms/roomX.tscn)：基础房间模板，包含背景、16×16 地面、Warma、门和 HUD。
- [rooms/room.gd](rooms/room.gd)：共用房间显示逻辑，记录进入时的装备状态，并负责死亡期间冻结和场景重置。
- [objects/warma.tscn](objects/warma.tscn) 和 [warma.gd](objects/warma.gd)：可复用玩家，包含装备、探针、移动、跳跃及死亡动画；`Fall Limit` 默认是屏幕底部的 144，角色脚底触及时死亡，可在 Inspector 调整。
- [objects/block.tscn](objects/block.tscn)：可单独摆放的 16×16 静态方块，节点原点位于方块中心。
- [objects/blocks.tscn](objects/blocks.tscn) 和 [tileset.tres](objects/tileset.tres)：可复用 TileMapLayer 和 TileSet，继续支持绘制地形；碰撞上下各缩进 0.01px。
- [objects/giraffe.tscn](objects/giraffe.tscn) 和 [giraffe.gd](objects/giraffe.gd)：完整实体碰撞与外部冲量接口。
- [objects/music_bullet.tscn](objects/music_bullet.tscn) 和 [music_bullet.gd](objects/music_bullet.gd)：成长动画、地形阻挡及长颈鹿反应；ShapeCast2D 检查整段位移防止高速穿墙，`Lifetime` 控制清理时间，不依赖主房间坐标。
- [objects/door.tscn](objects/door.tscn) 和 [door.gd](objects/door.gd)：按 W 打开 Inspector 指定的下一房间。
- [objects/extinguisher_pickup.tscn](objects/extinguisher_pickup.tscn) 和 [held_extinguisher.tscn](objects/held_extinguisher.tscn)：拾取物与手持装备。
- [objects/background.tscn](objects/background.tscn) 和 [hud.tscn](objects/hud.tscn)：可复用背景与 HUD。
- [objects/game_state.tscn](objects/game_state.tscn) 和 [game_state.gd](objects/game_state.gd)：Autoload，保留跨房间的灭火器持有状态。
- [rooms/node_2d.tscn](rooms/node_2d.tscn)：保留的旧精灵试验场景，不参与房间切换。
- [docs/GODOT_LEARNING.md](docs/GODOT_LEARNING.md)：物理、碰撞查询和调试说明。

## 创建房间与配置门

1. 在 FileSystem 中复制 [roomX.tscn](rooms/roomX.tscn)，将新房间保存在 `rooms/`。
2. 修改 `Blocks` 的地图，在房间内调整 `Player` 的出生位置，并实例化需要的 `objects/` 对象。
3. 选中房间内的 `Door` 根节点，在 Inspector 的 `Next Room` 文件选择器中选择目标房间的 `.tscn`。每扇门可以配置不同目标；留空时门不切换场景。
4. 默认示例为 [main.tscn](rooms/main.tscn) → [roomX.tscn](rooms/roomX.tscn) → [main.tscn](rooms/main.tscn)。站在门附近按 W 才切换，不再显示“已进门”。

房间只保存布局和对象实例，不再直接展开玩家或门的内部节点。切换会释放旧房间的临时对象，但 `GameState` 的装备状态仍保留。

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
godot --headless --path . --script res://tests/music_bullet_test.gd
godot --headless --path . --script res://tests/room_transition_test.gd
godot --headless --path . --script res://tests/death_reset_test.gd
```
