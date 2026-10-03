# Godot 4.7：Warma 平台物理学习笔记

这份文档记录这个项目的物理设计、实现原因和调试方法。目标不是只记住当前代码，而是理解 Godot 4.7 中 `CharacterBody2D`、碰撞查询、碰撞层和物理帧之间的关系。

## 1. 先建立正确的模型

这个项目里 Warma 和长颈鹿都是 `CharacterBody2D`。它们不是 `RigidBody2D`，也不会因为普通接触自动交换真实世界中的动量。

- `CharacterBody2D`：脚本负责重力、速度和移动，适合玩家、敌人和可控角色。
- `RigidBody2D`：由物理引擎负责积分和碰撞响应，适合需要真实质量、冲量和自由旋转的物体。
- `StaticBody2D`：由关卡提供固定碰撞，不参与移动。
- `Area2D`：检测进入/离开区域，通常不阻挡移动。

长颈鹿虽然有 `mass` 和 `apply_external_impulse()`，仍然是可控的 `CharacterBody2D`。这里的“冲量”是项目自己的事件接口：未来子弹或其他事件可以调用它改变 `velocity`，并不是把长颈鹿改造成 `RigidBody2D`。

因此，本项目的规则是：

1. Godot 负责回答“这段运动会不会碰撞，以及可以安全移动多远”。
2. 脚本负责决定重力、跳跃、抬升和外部事件。
3. 普通 Warma 接触不会把水平速度传给长颈鹿。

## 2. 场景和碰撞层

逻辑分辨率是 `256x144`，物理更新频率是 `120Hz`。小尺寸游戏中，一帧位移可能已经接近一个像素，所以移动和碰撞修正必须保持一致。

当前碰撞层使用位掩码：

| 层 | 对象 | 用途 |
|---|---|---|
| `1` | 地形 | 地砖和固定关卡碰撞 |
| `2` | Warma | 玩家完整碰撞体 |
| `4` | 长颈鹿 | 长颈鹿完整碰撞体 |
| `32` | 门区域 | 进入门的触发区域 |

碰撞层表示“我属于哪一类”，碰撞遮罩表示“我主动检测哪一类”。例如：

- Warma 默认检测地形；移动时根据当前轴向规则决定是否检测长颈鹿。
- 长颈鹿默认检测地形；下落时检测 Warma，水平外力运动时也检测 Warma。
- `GroundProbe` 的遮罩是地形和长颈鹿，用于判断支撑。
- `HeadProbe` 只检测长颈鹿，用于识别从下方跳入。

## 3. 完整碰撞体

长颈鹿只有一个 `RectangleShape2D`，大小为 `8x16`。这个形状同时负责：

- 左侧和右侧阻挡；
- Warma 站在长颈鹿顶部；
- 长颈鹿落在 Warma 顶部；
- Warma 从下方碰到长颈鹿；
- 长颈鹿落到地面。

不要用“左边一根柱子、右边一根柱子、顶部一个平台”拼出同一个角色。多个辅助碰撞体会让边角、法线和恢复方向变得难以推理。传感器可以存在，但传感器不应该替代实体碰撞。

Warma 的碰撞多边形大小为 `5x16`，边界是 `x=-2..3, y=-8..8`，中心偏右 `0.5px`。两个探针按这个实际边界对齐，完整碰撞多边形不变。精灵图片只是显示内容，不是物理边界；调试时应该以 `CollisionPolygon2D` 和 `CollisionShape2D` 为准。

## 4. 轴向移动为什么存在

项目没有直接调用一个整体的 `move_and_slide()` 来处理两个角色的全部行为，而是把一帧运动拆成水平和垂直两个查询：

1. 计算这一帧的水平速度和垂直速度；
2. 查询水平位移；
3. 提交水平位移；
4. 查询垂直位移；
5. 提交垂直位移。

这样做是为了明确区分两种规则：

- Warma 撞到长颈鹿侧面时应停止水平移动；
- 长颈鹿落到 Warma 顶部时应停止垂直移动，但不应把 Warma 横向挤走；
- Warma 在长颈鹿下方可以水平移动，但不应把长颈鹿横向拖走。

这种设计的代价是：脚本必须正确提交 Godot 返回的碰撞位移，不能只看碰撞结果。

## 5. `test_only` 和 `get_travel()`

`move_and_collide(motion, true, safe_margin, false)` 中的第二个参数是 `test_only`。它的含义是：

> 执行碰撞查询，但不要自动改变 CharacterBody2D 的位置。

所以 `test_only` 不是“移动”。代码必须自己提交结果：

```gdscript
var collision := move_and_collide(motion, true, safe_margin, false)
if collision == null:
    global_position += motion
else:
    global_position += collision.get_travel()
```

项目中还必须遵守轴向约束：

```gdscript
var travel := collision.get_travel()
if not is_zero_approx(motion.x):
    global_position.x += travel.x
else:
    global_position.y += travel.y
```

不能在垂直查询后直接提交完整的 `travel`。碰撞恢复可能包含一个横向分量；如果把它也写入 `global_position`，长颈鹿落地时就可能横向漂移。

之前的悬空 bug 正是因为检测到垂直碰撞后只清零速度、却丢弃了 `get_travel()`。角色停在上一帧位置，脚下就会留下随速度变化的缝隙。

## 6. `safe_margin` 不等于自动贴地

`safe_margin` 是碰撞检测和恢复使用的余量，不是“把角色吸到地面”的开关。

当前配置中：

- Warma 的 `safe_margin` 是 `0.001`；
- 长颈鹿场景的 `safe_margin` 是 `0.0`；
- 物理求解器使用 `120Hz`、32 次迭代和小接触分离参数。

这些参数可以影响检测的稳定性，但不能弥补脚本丢掉的位移。正确的顺序是：

1. 查询碰撞；
2. 读取 `get_travel()`；
3. 提交当前轴的 travel；
4. 对被法线阻挡的轴清零速度。

## 7. 两个探针各自负责什么

### GroundProbe

`GroundProbe` 是 Warma 脚下的 `ShapeCast2D`，宽度与完整脚边一致。它检测地面或长颈鹿顶部，用来回答：

- Warma 是否有支撑？
- 是否允许开始跳跃？
- 落地后是否已经回到稳定状态？

它是传感器，不是阻挡器。真正防止穿透的是 Warma 的完整碰撞体和移动查询。

只要脚的一部分仍压在平台上，就有支撑。判定要求接触法线向上，接触点距离脚底不超过 `0.02px`；侧墙或真正的悬空不能提供跳跃资格。脚探针使用零 `margin`，避免在紧贴墙壁时先检测到墙侧、遮住脚下地面的查询结果。

### HeadProbe

`HeadProbe` 是 Warma 头顶的 `ShapeCast2D`。它只实现一个额外的游戏规则：Warma 从长颈鹿下方跳起时，可以把长颈鹿一起顶起。

它不能单独决定实体是否碰撞。为了避免“贴着侧面时误判为从下方撞击”，`_lift_giraffes_above()` 同时检查：

- 碰撞法线的 `y` 分量是否指向 Warma；
- 长颈鹿中心是否真的位于 Warma 上方。

头探针同样按 `5px` 的真实头宽对齐，向上扫过本次起跳帧的实际位移，避免在头部横向或竖直方向尚未接触时提前抬升长颈鹿。

侧面接触或长颈鹿顶部接触不会触发抬升。

起跳时还要注意两个 `CharacterBody2D` 的物理帧顺序：Warma 在跳跃帧已经选定 `jump_velocity`，长颈鹿则会在自己的物理回调开始时先积分一次重力。因此抬升速度会预先扣除这一次重力步长，确保两个形状从第一帧开始保持相同的位移；否则到跳跃顶点时会积累约一个像素的重叠，碰撞恢复会把长颈鹿额外向上推出。

## 8. 长颈鹿压在 Warma 上方

“长颈鹿在 Warma 上方”是垂直承载关系，不应该被当成水平墙。

Warma 会通过 `_has_giraffe_above()` 判断：

- 长颈鹿底面是否接近 Warma 顶面；
- 两者在 X 方向是否仍有重叠。

如果满足条件，Warma 的水平查询只检测地形，因此可以从长颈鹿下方水平移动。与此同时：

- 长颈鹿没有读取 Warma 的静止水平位移，所以不会被带着走；
- 长颈鹿自己的垂直查询仍然处理重力和接触；
- 当接触变成真正的侧面接触时，Warma 会重新启用长颈鹿碰撞层，不能穿过长颈鹿侧面。

这是一个明确的游戏规则，不是依赖物理引擎自动产生摩擦或推动效果。

### 一格高空隙的入口

地形上下各缩进 `0.01px`，因此一格高空隙的实际高度约为 `16.02px`，可以容纳完整 `16px` 的角色。但跳跃的竖直离散步长会跳过这个极窄的入口高度，所以对齐后水平行走可通过，直接跳入却可能持续撞墙。

水平受阻时，仅对上下两面都存在、容得下完整身体的一格高空隙尝试最多 `0.75px` 的入口高度对齐。先检查竖直调整路径，再用完整身体检查剩余水平运动；两条路径都安全才提交。小于角色身高的空隙仍然阻挡，普通墙壁不会触发对齐，也不会忽略长颈鹿碰撞。这项修正不改变贴图、缩放、碰撞多边形或方块形状。

## 9. 长颈鹿的运动流程

长颈鹿每个物理帧执行：

1. 累加重力到 `velocity.y`；
2. 如果有水平速度，查询水平运动；
3. 查询垂直运动，检测地形和其他长颈鹿；下落时还检测 Warma；
4. 将对应轴的 travel 提交到位置；
5. 只有被对应法线阻挡时才清零该轴速度。

长颈鹿向上移动时暂时不扫描 Warma，目的是允许 Warma 从下方顶起它。进入下落阶段后恢复垂直碰撞。

长颈鹿之间也使用完整实体碰撞，垂直查询包含长颈鹿层，因此可以稳定叠放。水平查询仅暂时排除正在自己头顶上方接触的长颈鹿，查询结束后立即恢复该身体的碰撞；旁边其他长颈鹿仍然阻挡。上下两只之间没有速度传递或平台跟随，任意一只都能独立滑动，水平重叠消失后上方那只正常下落。

未来的投射物不应该直接修改长颈鹿的坐标。应该调用：

```gdscript
 giraffe.apply_external_impulse(Vector2(24.0, 0.0))
```

这样外力仍然进入同一个速度和碰撞流程。

## 10. 如何读测试

玩家测试位于 `tests/player_physics_test.gd`，验证：

- 16 像素地砖通道；
- 地砖接缝；
- 短跳、中跳和大跳；
- 空中重新按跳跃不会二段跳。

`tests/precision_platforming_test.gd` 另外验证两端脚边落地与起跳、悬空和侧墙不误判、头部边缘抬升、一格高空隙从左右进入、不同跳跃步长与起跳高度，以及截图对应的 `rooms/Standard/room2.tscn`。

长颈鹿测试位于 `tests/giraffe_physics_test.gd`，验证：

- 左右侧面不能穿透；
- 普通接触不改变长颈鹿 X 坐标；
- 长颈鹿落到 Warma 顶部；
- Warma 站在长颈鹿上时顶部接触没有缝隙；
- 长颈鹿压顶时 Warma 可以水平移动；
- 长颈鹿压顶时不会被 Warma 横向带动；
- Warma 从下方跳起可以抬升长颈鹿；
- 贴边跳跃不会误触发抬升；
- 贴边下落和跳跃干扰后仍然精确落地；
- 正负水平外力都能移动长颈鹿。

`tests/giraffe_stacking_test.gd` 验证两种节点顺序下的三只叠放、上下两只分别向左右滑动时不产生摩擦带动、滑出支撑后下落，以及头顶有长颈鹿时仍保留其他长颈鹿的侧面阻挡。`tests/foreground_messages_test.gd` 验证告示牌覆盖进场消息、重叠触发区与直接传送下的消息互斥、常驻 HUD 保留，以及告示牌文字的间距和相机定位。

运行方式：

```powershell
godot --headless --path . --script res://tests/player_physics_test.gd
godot --headless --path . --script res://tests/giraffe_physics_test.gd
godot --headless --path . --check-only --script res://tests/player_physics_test.gd
godot --headless --path . --check-only --script res://tests/giraffe_physics_test.gd
```

## Elevator direction scenes and moving support

Elevator no longer has a direction property. `objects/elevator.gd` contains the shared extension, blocking, and support logic and returns `Vector2.UP` from the virtual `_axis()`; `elevator_up.gd`, `elevator_down.gd`, `elevator_left.gd`, and `elevator_right.gd` each override `_axis()` for one direction, and `elevator_up.tscn`, `elevator_down.tscn`, `elevator_left.tscn`, and `elevator_right.tscn` are authored with the collision shape and visual already rotated, so a map placement looks correct before the game runs. `elevator.tscn` is retained as the upward compatibility scene.

A moving platform can update in a different order from the CharacterBody2D during one physics tick. The Elevator moves Warma, Giraffe, and a vertical support chain before committing its new collision size. Warma still uses `GroundProbe` for ordinary terrain and giraffe contacts, and also accepts the Elevator's `supports_body()` result while a body is resting on or falling toward the moving surface.

`supports_body()` must never mistake an active jump for support. A body whose `velocity.y` is negative is leaving the platform, so it is excluded from both support snapping and the carried stack; otherwise a jump whose per-frame rise is smaller than the contact tolerance (which happens at the slower `Engine.time_scale` values) would be re-snapped back onto the surface and its upward velocity cleared on the next physics frame. Each Elevator also duplicates its `CollisionShape2D` in `_ready`, so multiple instances of the same scene do not share a shape resource, and `_body_bounds` reads the body's real collision extents rather than assuming the collision polygon is centred on the node origin.

A lift behaves as a telescoping rod rather than a wall: its extension ignores static scenery (Blocks and tiles), so a rod placed inside or beside a Block still grows out of it. What still stops growth is an actor: an uncarried character in the newly added strip blocks it, and a carried rider stops the rod before it would be pushed into solid terrain. The upward direction keeps that safety rule, and the other three scenes use the same rule with their own extension axis and anchored support surface. Buttons only emit `activation_changed`; they do not contain direction-specific branches.

## 11. 推荐的调试顺序

遇到新的物理问题时，按下面顺序检查：

1. 打印两个角色的 `global_position`、`velocity` 和 `collision_mask`；
2. 打印 `KinematicCollision2D.get_normal()`、`get_travel()` 和 `get_remainder()`；
3. 确认问题发生在水平查询还是垂直查询；
4. 检查碰撞体是否真的重叠，而不是只看 Sprite；
5. 检查是否把 test-only 查询误认为已经移动；
6. 检查是否把垂直恢复量提交成了水平位移；
7. 最后才调整 `safe_margin`、求解器参数或碰撞形状。

如果一个问题只能通过把 Sprite 或整体 scale 放大来消失，通常说明物理边界、travel 提交或碰撞层规则还有问题，应该先修正这些逻辑。

## 12. 建议的学习顺序

1. 先修改 [rooms/main.tscn](../rooms/main.tscn) 中的碰撞层和碰撞体，观察实体边界；
2. 阅读 `CharacterBody2D.move_and_collide()` 的参数和返回值；
3. 用一个简单矩形实验 `test_only`、`get_travel` 和碰撞法线；
4. 再阅读 [warma.gd](../objects/warma.gd) 的水平/垂直两次查询；
5. 最后阅读 [giraffe.gd](../objects/giraffe.gd) 的外力接口和测试文件；
6. 每次改动都先添加一个能失败的测试，再运行两套物理测试。

这样学习到的是 Godot 物理系统的可迁移方法，而不只是某一个长颈鹿 bug 的补丁。
