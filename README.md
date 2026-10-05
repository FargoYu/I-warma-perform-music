# Warma 平台跳跃示例（Godot 4.7）

逻辑分辨率为 **256×144**，默认窗口为 **1024×576**，即 4 倍整数缩放。

## 操作

- `A/D`：左右移动
- `J`：跳跃；轻按小跳，长按大跳
- `W`：在门附近切换到门指定的房间
- `K`：拾取灭火器后发射音乐子弹，默认无发射冷却，每次按下都可发射；子弹碰到方块会消失，击中长颈鹿会让它沿发射方向移动
- `R`：死亡并重置当前房间；下落到屏幕底部也会触发死亡

死亡时主角闪烁两次，然后恢复进入当前房间时的状态，包括位置、长颈鹿、拾取物和装备，并清除音符。死亡动画封装在 `Warma.play_death_animation()` 中，之后可单独替换；Inspector 的 `Death Flash Duration` 控制每次隐藏或显示的时长（默认 0.08 秒）。

## 主要结构

- [rooms/title.tscn](rooms/title.tscn)：项目默认启动的临时标题页；按任意键进入第一关。
- [rooms/main.tscn](rooms/main.tscn)：第一关，保留原来的地形和对象摆放。
- [rooms/roomX.tscn](rooms/roomX.tscn)：基础房间模板，包含背景、16×16 地面、Warma、门和 HUD。
- [rooms/room.gd](rooms/room.gd)：共用房间显示逻辑，记录进入时的装备状态，并负责死亡期间冻结和场景重置。
- [objects/warma.tscn](objects/warma.tscn) 和 [warma.gd](objects/warma.gd)：可复用玩家，包含装备、探针、移动、跳跃及死亡动画；`Fall Limit` 默认是屏幕底部的 144，角色脚底触及时死亡，可在 Inspector 调整。
- [objects/block.tscn](objects/block.tscn)：可单独摆放的 16×16 静态方块，节点原点位于方块中心。
- [objects/blocks.tscn](objects/blocks.tscn) 和 [tileset.tres](objects/tileset.tres)：可复用 TileMapLayer 和 TileSet，继续支持绘制地形；碰撞上下各缩进 0.01px。
- [objects/giraffe.tscn](objects/giraffe.tscn) 和 [giraffe.gd](objects/giraffe.gd)：完整实体碰撞与外部冲量接口。
- [objects/music\_bullet.tscn](objects/music_bullet.tscn) 和 [music\_bullet.gd](objects/music_bullet.gd)：成长动画、地形阻挡及长颈鹿反应；ShapeCast2D 检查整段位移防止高速穿墙，`Lifetime` 控制清理时间，不依赖主房间坐标。
- [objects/door.tscn](objects/door.tscn) 和 [door.gd](objects/door.gd)：按 W 打开 Inspector 指定的下一房间。
- [objects/extinguisher\_pickup.tscn](objects/extinguisher_pickup.tscn) 和 [held\_extinguisher.tscn](objects/held_extinguisher.tscn)：拾取物与手持装备。
- [objects/background.tscn](objects/background.tscn) 和 [hud.tscn](objects/hud.tscn)：可复用背景与 HUD。
- [objects/game\_state.tscn](objects/game_state.tscn) 和 [game\_state.gd](objects/game_state.gd)：Autoload，保留跨房间的灭火器持有状态。

## 创建房间与配置门

### 标题、进场文字与告示牌

标题页的 `StartPrompt` 与关卡的 `EntryText` 都实例化 [objects/screen\_text.tscn](objects/screen_text.tscn)。在 Inspector 中设置 `Message`（文字内容）、`Font Size`（字号）、`Text Color`（颜色）和 `Display Duration`（显示秒数）。`Centered` 与 `Center On Screen` 默认开启，文字会随字号、换行和视口大小保持在屏幕中央。关闭 `Center On Screen` 后，`Text Position` 指定文本中心；再关闭 `Centered` 后，指定左上角并使用左对齐。时长为 0 时持续显示；第一关和第二关的进场示例显示 2 秒。把这个对象实例化到其他房间即可使用，不需要改房间脚本。

告示牌图片使用 `Z Index = -9`，位于背景（-10）之上、人物和砖块（0）之下。告示牌文字、进场文字和标题提示使用独立的 `CanvasLayer`（层级 100），显示在游戏对象前方。同一视口仅显示一条这类消息：接触告示牌会立即隐藏进场文字，接触新告示牌会先隐藏旧消息；离开后不恢复已经隐藏的消息。速度倍率等常驻 HUD 不参与消息替换。

告示牌根节点的 `Centered` 和 `Text Above Sign` 默认开启，文字在告示牌上方居中并跟随相机；`Text Distance` 控制文字底部与贴图顶部的距离（默认 12 个逻辑像素），`Text Width` 控制最大换行宽度。短消息会缩小文本框，靠近屏幕边缘时会调整位置以保持可见。关闭 `Text Above Sign` 后可用 `Text Position` 指定屏幕坐标，`Centered` 决定它表示文本中心还是左上角。

### 门

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
- 长颈鹿能落在其他长颈鹿上，也能多只叠放；上下任意一只水平移动都不会把另一只带走，失去支撑后正常下落，真正的侧面接触仍会阻挡。
- 一只长颈鹿踩在另一只（或多只）长颈鹿上时，被踩的那只仍能被音乐子弹推动着水平移动，叠放的骑乘者不会把它锁死。
- Warma 头顶的长颈鹿，以及叠放在它们上面的长颈鹿，会作为一整个承载链跟着她起跳上升、再跟着她落回原处。跳跃高度只由 Warma 自己决定，不随头顶长颈鹿的数量变化，也不会被它们挡住或穿透它们。
- 整个身体都在 Warma 头顶之上的长颈鹿不是水平障碍，她可以走进它下面，包括刚好一格高、需要贴着上下两个面的位置；与她同高、真正挡路的长颈鹿照常阻挡她，所以她不会横穿站在旁边的长颈鹿。

Warma 与长颈鹿通过同一个完整实体碰撞体处理顶部、底部和左右接触。轴向查询使用 `test_only` 后必须提交 `get_travel()`；垂直查询只提交垂直 travel，避免接触恢复把角色横向挤走。长颈鹿在普通接触时不主动扫描 Warma 的静止水平位移，从而不会被横向带走；下落和外部主动运动时会恢复对应方向的实体碰撞。Warma 头顶的承载关系直接由碰撞外形判定：底部边缘贴住承载者顶部边缘（0.75px 支撑容差，与升降台一致）且水平投影有重叠的长颈鹿即为承载对象，并沿垂直方向递归到它们上方叠放的长颈鹿。Warma 的垂直移动只把这些承载对象排除在碰撞之外，其余长颈鹿仍是实体天花板；承载对象按 Warma 本帧实际提交的位移整体平移，并被标记为“有支撑”，因此不会在她的跳跃之上再叠加一次自己的重力步进。Warma 的水平查询只把“整个身体都在她头顶之上”的长颈鹿（也就是承载对象，以及她能走进去的下方空间）排除在外，因此头顶有长颈鹿时她既不会被它当作侧墙卡住，也不会横穿任何与她同高的长颈鹿；真正的侧面接触仍然阻挡穿透。

长颈鹿水平移动时，会把同一垂直堆叠里的长颈鹿（踩在自己头上的骑乘者、以及自己脚下的支撑者）和头顶与它脚底齐平的 Warma 一起临时加入碰撞例外再扫描，这样上下接触只提供垂直支撑、不会读作侧墙。Warma 同样是 16px 高、以原点为中心的身体，她的头顶齐平长颈鹿脚底时整个身体都在它下方、只可能是支撑，因此 Warma 站在一格深的坑里紧贴坑壁、长颈鹿站在坑沿正上方时，音乐子弹仍能把它正常推走；两者同高并肩站立时 Warma 照常是实心侧墙。堆叠关系按脚底/头顶平面贴合、且两只 8px 宽身体存在真实横向重叠来计算；单纯按中心点是否对齐判定会在长颈鹿停靠时被推歪几像素后漏判，导致音乐子弹给出的水平移动被错误清零。

## 小尺寸物理精度

本项目使用轴向 test-only 碰撞查询、`get_travel()` 提交和 2D 物理求解器设置提高小尺寸实体的精度：

- 120 次物理更新/秒
- 最大允许穿透：0.01px
- 最大接触分离：0.05px
- 接触复用半径：0.01px
- 求解迭代：32

Warma 使用 `CharacterBody2D.safe_margin = 0.001`；长颈鹿的完整形状使用零恢复余量，避免上下接触产生横向修正。轴向提交只取请求位移在对应轴上的分量，并且永不超过请求本身：身体贴在支撑上时求解器会把该接触的恢复当作整个 travel 返回，此时垂直法线不约束水平轴，该轴照常提交请求位移（否则站在地面上的长颈鹿会被脚下的地面卡住推不动，法线为水平方向的真实墙壁照常阻挡）；反向的恢复也不能把身体顶得比自己的重力步进更深，避免低时间流速下把身体压进支撑再回弹。

沃玛的碰撞多边形保持 `x=-2..3, y=-8..8`。脚下形状探针覆盖完整脚宽，平台边缘只托住一部分脚也能起跳；触地判定只接受向上的接触法线和 `0.02px` 内的脚底接触。承载判定读取双方真实的碰撞外形（Warma 是不对称多边形，长颈鹿是 8×16 矩形），并按 0.75px 的接触容差递归整条竖直链，不依赖精灵、中心点或额外的探针节点。一格高空隙的入口最多对齐 `0.75px`，并检查完整身体的竖直和水平路径，解决跳跃离散步长跨过入口高度的问题；贴图、缩放、方块和人物碰撞体均不改变。

## Elevator direction scenes and moving support

The shared logic lives in `objects/elevator.gd`. Direction is not a property: each direction has its own script that overrides `_axis()`, and its own scene, whose saved collision shape and visual are already rotated for that direction so a map placement shows the final orientation immediately:

- `objects/elevator_up.tscn`: bottom anchor, stretches upward; this is the original vertical configuration.
- `objects/elevator_down.tscn`: top anchor, stretches downward.
- `objects/elevator_left.tscn`: right anchor, stretches left.
- `objects/elevator_right.tscn`: left anchor, stretches right.

All four scenes keep the same `min_height`, `max_height`, `height_speed`, `starts_extended`, and `button_path` properties; there is no `stretch_direction` to configure. Buttons still control an Elevator through the `activation_changed` signal; new rooms should choose one of the four direction-specific scenes.

The collision shape uses the same 0.02px total edge inset as `Block`, so a visually continuous Elevator/Block surface has no extra seam step. A lift is a telescoping rod, not a wall: its extension passes straight through Blocks and tiles instead of being stopped by them, so a rod anchored inside or beside a Block still grows out of it. An upward Elevator carries the complete Warma/Giraffe stack and still stops before pushing a carried body into an overhead Block, and an uncarried actor in the newly added strip blocks growth. Retraction and downward motion move supported bodies before committing the new shape.

Each Elevator duplicates its `CollisionShape2D` in `_ready`, so several lifts of the same scene in one room never share — and therefore never corrupt — a single shape resource. Support is only granted while a body is resting on or falling toward the surface: an actively rising body (negative `velocity.y`, such as a fresh jump) is never re-snapped or carried, so holding `J` launches reliably even at slow time scales where the per-frame jump displacement is below the contact tolerance. Elevator support and pressure-plate overlap both use `_body_bounds`, which reads the real collision extents and keeps Warma's `x=-2..3` polygon (centre `+0.5`) from shifting edge detection.
