# 系统概要与学习路径

## 一、先认识整体

这是 Godot 4.7 的 2D 平台游戏。Warma 可以移动、跳跃、拾取灭火器、发射音符、阅读告示牌与通过门换房间。长颈鹿受到音符攻击后按受击方向移动一段时间。方块组成地形，编辑器插件提供网格画笔。

实体碰撞由自研矩形求解器负责。不要用 `CharacterBody2D`、`move_and_slide()` 或 `Area2D` 接管现有逻辑；交互物使用同一坐标系下的矩形查询。

| 文件或目录 | 职责 |
| --- | --- |
| `project.godot` | 入口、输入、显示、120 Hz 物理、自动加载和插件配置 |
| `main.tscn` / `scripts/game.gd` | 游戏宿主，加载房间、换房间、重开与 P/F1 |
| `start.tscn` / `end.tscn` / `scripts/scene_screen.gd` | 开场和结束画面，按任意键切场景或退出 |
| `levels/` | 房间布局，根节点使用 `rect_world.gd` |
| `scripts/rect_world.gd` | 收集对象，统一输入、物理、子弹、拾取、门、告示牌和死亡 |
| `physics/rect_state.gd` | 实体权威位置、尺寸、速度、运动意图与接地状态 |
| `physics/rect_solver.gd` | 接触关系、连续事件推进、精确锚定与非穿透验证 |
| `objects/rect_body.gd` | 实体配置和绘制，长颈鹿受击移动计时 |
| `objects/warma.gd` | 装备状态、装备绘制与音符喷嘴位置 |
| `objects/block_grid.gd` | 方块网格，每格注册为静态矩形 |
| `objects/extinguisher_pickup.gd` | 拾取范围与视觉效果 |
| `objects/door.gd` | 门图片、范围与目标房间路径 |
| `objects/signboard.gd` | 告示牌图片、文字配置与上方提示框 |
| `scripts/game_state.gd` | 本轮装备状态和本次运行的时间档位；重开清除装备，流速保留 |
| `scripts/bullet.gd` | 音符显示数据，运动与命中由世界处理 |
| `addons/block_painter/` | 方块画笔、擦除与撤销 |
| `tests/` | 物理、玩法、按键、显示与画笔验证 |

## 二、运行与搭建房间

先按 F5 试玩，再打开 `levels/level_01.tscn` 看场景树。选择各个对象观察 Inspector，移动一个对象后按 F6，比较配置与运行效果。

选择 `PaintBlocksHere`，启用 2D 工具栏的“方块画笔”：左键绘制、右键擦除、Ctrl+Z 撤销、Esc 退出。默认格子 16×16，画笔跟随网格位置与编辑器缩放。

从文件系统拖入以下场景即可添加对象：

- `objects/warma.tscn`：一个房间配置一个主角，位置为碰撞矩形左上角，尺寸 5×16。
- `objects/giraffe.tscn`：尺寸 8×16，位置也是矩形左上角。
- `objects/block_grid.tscn`：默认每格 16×16。
- `objects/extinguisher_pickup.tscn`：位置是 8×8 拾取区中心，不阻挡实体。
- `objects/door.tscn`：位置是 16×16 图片左上角，不阻挡实体。
- `objects/signboard.tscn`：位置是 16×16 图片左上角，不阻挡实体。

实体初始位置不能互相重叠，否则世界记录 `setup_errors` 并停止物理。Godot 的 Output / Debugger 会报告实际场景路径、冲突节点路径与坐标；即使重叠的是两只长颈鹿，也会阻止主角下落和移动。运行 `tests/run_level_loading.ps1` 可检查所有已保存关卡的布局，并验证 level_04 独立运行和通过 level_03 的门进入后的下落、移动与落地。允许平移分组与整体世界缩放；世界内部的实体和分组应保持零旋转、单位缩放。

新房间可以复制已有房间，根节点仍使用 `scripts/rect_world.gd`。游戏从 `start.tscn` 开始；选中开场根节点，在 Inspector 的 **Target Scene** 中选择按任意键后进入的场景。默认指向 `main.tscn`，其 **Level** 决定初始房间；也可以直接选择房间场景进行独立运行。换房间后，主角出现在目标房间预先摆放的 Warma 位置。

最后一关的门将 **Target Room** 设置为 `res://end.tscn`，即可进入结束画面。结束根节点的 **Quit On Key** 已启用，按任意键退出游戏；按键松开和键盘重复事件不触发。开场与结束场景的 Title、Prompt 节点可直接在编辑器修改文字和位置。

## 三、配置门与告示牌

选中门，在 **Target Room** 文件选择器中指定目标 `.tscn`，例如 `res://levels/level_02.tscn`。目标根节点使用 `rect_world.gd` 或开场/结束的 `scene_screen.gd`。房间保存路径而不是互相嵌套的场景资源，因此可以互相连接。未配置或无效目标不会开始切换。门默认 Z Index 为 -50，背景为 -100，主角为 0，所以门覆盖背景但不会遮挡主角。

**Interaction Rect** 是相对门节点的范围，默认 `(0, 0, 16, 16)`。W 要求 Warma 的权威矩形与它有面积重叠，仅边缘相切不算进入。多个门同时可用时选择场景树深度优先顺序中的第一扇；M 直接使用当前房间的第一扇门。如果第一扇未配置，不会跳过它寻找其他门。N 直接授予装备。

选中告示牌，修改 **Text**，支持多行中文。提示只有黑字，没有底色。**Interaction Rect** 控制范围，**Text Width** 控制文字区域宽度，**Font Size** 控制字号，**Text Gap** 控制上方间隔。文字自动换行，在屏幕左右边缘调整位置。文字较多时应调整宽度、字号或告示牌位置，给上方留出空间。

世界每个物理步选择提示：接触时显示，离开全部告示牌时隐藏；新进入另一个告示牌区域时，旧提示立即隐藏，即使区域仍有重叠。如果同一步进入多个告示牌，按场景树顺序选择第一个。交互物可放入平移分组，世界会换算坐标。

## 四、跟着一帧理解代码

先读 `rect_state.gd`，再读 `rect_world.gd` 的 `rebuild()`、`_collect()` 和 `_physics_process()`。场景提供初始配置；注册后，`RectState` 中的标量位置才是权威。每步执行：

1. 读取输入，更新跳跃缓冲与离地宽限时间。`GameState` 用 `Engine.time_scale` 调整全局游戏时间，世界收到的 `delta` 已按所选档位缩放。
2. 每个实体只施加一次重力，设置水平意图与跳跃速度。
3. `solver.step(delta)` 求解接触并推进位置。
4. 用相对扫掠检测子弹，查询灭火器与告示牌范围。
5. `sync_visuals()` 将状态位置写回显示节点，检查死亡与越界。

门和快捷键在 `_unhandled_input()` 接收事件，忽略按住产生的重复事件。`room_requested` 将换房间请求传给宿主，宿主延迟替换世界，避免在输入回调中删除当前房间。独立 F6 房间通过 SceneTree 切场景。切换前保存装备，新房间恢复装备，并重置显示插值。

运动中的节点 `position` 只是显示输出，不应作为角色碰撞依据。交互检测使用主角的 `state.x/y/w/h`。新建世界或显式 `rebuild()` 时才重新读取布局。

## 五、深入物理核心

读 `rect_solver.gd` 的 `step()`，再追踪 `_solve_contacts()`、`_next_event_time()`、`_anchor_contacts()` 和 `_validate_nonpenetration()`。先理解一个方块与一个主角，再理解两个运动实体与堆叠。

水平速度来自 `intent_x`，接触可以将其向零削减，不能把一个角色的水平驱动转嫁成另一个角色的推力。求解器先解水平并冻结结果，再解垂直接触；垂直关系允许支撑与向上顶动。碰撞与支撑结束均通过连续边界事件推进，处理恰好一格高的通道。同刻接触统一锚定，只调整坐标，不缩小碰撞矩形。

数值异常或事件预算不足时保守停止，必要时回滚到合法位置，并记录 `diagnostics`。不会为了让角色通过而缩箱、硬推或增加入口吸附。`grounded` 来自接触查询，而不是贴图位置。

## 六、推荐学习顺序与验证

第一阶段：运行两个房间，尝试 W/N/M，修改告示牌文字与门目标。第二阶段：搭建平台，观察碰撞边界和跳跃。第三阶段：阅读状态、世界与装备脚本，跟踪一次拾取和换房间。第四阶段：对照 `test_physics.gd` 阅读求解器，观察单格入口、支撑释放、堆叠、屋顶与回滚。

修改玩法后运行 `run_gameplay.ps1` 与 `run_real_input.ps1`；修改物理后运行 `run_physics.ps1`；修改显示后运行 `run_display.ps1`；修改画笔后运行 `run_block_painter.ps1`。命令见 README。游戏测试覆盖门范围、第一扇门、非法目标、告示牌切换、装备保留与 F5/F6 换房间。真实按键测试覆盖 N/W/M 事件派发。显示测试生成 `artifacts/game_signboard.png` 供检查。

排错先看 `setup_errors` 与 `solver.diagnostics`，再判断是布局、输入、求解还是显示问题。测试通过表示覆盖场景满足检查，不能替代所有布局与长时间运行验证。
