# Showcase Rooms 机制清单与房间目录

本文档分两部分：第一部分是当前项目实际存在的可组合 gameplay building blocks（机制清单）；第二部分是 `rooms/showcase/` 下的 Showcase Room 目录。所有条目都来自实际代码，不含推测的机制。

运行 Showcase Hub（不改变默认启动流程）：

```powershell
godot --path . res://rooms/showcase/showcase_hub.tscn
```

Hub → 七个分类 index 房间 → 各个 Showcase Room。每扇门用 `W` 进入，每个 Showcase Room 的出口门回到它的分类 index。

---

## 第一部分：Mechanic Inventory

逻辑分辨率 256×144，物理 120Hz，求解器 32 次迭代、0.01px 最大穿透。碰撞层：1=地形(Blocks/Elevator)，2=Warma，4=Giraffe，16=Pickup，32=Door。

### 1. Warma（玩家）— `objects/warma.tscn` + `objects/warma.gd`

- CharacterBody2D，layer 2，`safe_margin = 0.001`。
- 碰撞多边形 **x=-2..3, y=-8..8**（5×16，几何中心偏右 +0.5；这是已批准的固定尺寸，测试锁定）。
- Inspector：`move_speed`(60)、`jump_velocity`(-150)、`jump_cut_speed`(60)、`gravity`(300)、`music_bullet_speed`(24)、`music_bullet_growth_duration`(0.24)、`music_bullet_interval`(0=无冷却)、`fall_limit`(144)、`death_flash_duration`(0.08)。
- 组合输入：A/D 移动；J 可变高度跳（短按小跳、长按大跳）；松开 J 把上升速度截断到 `jump_cut_speed`；按住 J 时跳跃缓冲(0.15s)持续刷新，落地即自动连跳；支撑宽限(0.10s)吸收移动平台的帧序间隙。
- 支撑检测：GroundProbe（全脚宽 ShapeCast，只接受向上法线）+ 电梯的 `snap_body_to_support` 连续支撑契约。平台边缘只托住一部分脚也算支撑、可起跳。
- 一格高（16px）空隙入口：`TIGHT_GAP_ALIGNMENT` 最多对齐 0.75px，并验证完整身体可穿过；普通墙和长颈鹿仍然阻挡。
- 头顶冲量：HeadProbe 识别从下方跳入的长颈鹿，调用统一入口 `apply_external_impulse`（只竖直方向）。
- 死亡：`die()` → 冻结所在房间（`freeze_for_death`）→ 闪烁两次动画 → `reset_scene()`。落到 `fall_limit` 也触发。
- 已有测试：`player_physics_test`（多边形/尺寸/连跳/穿缝）、`precision_platforming_test`（边缘/头顶/窄缝）、`wall_jump_test`（贴墙起跳）、`death_reset_test`（死亡与重置）。

### 2. Giraffe — `objects/giraffe.tscn` + `objects/giraffe.gd`

- CharacterBody2D，layer 4，**8×16 单一完整碰撞体**，`safe_margin = 0`，`custom_solver_bias = 1.0`。
- Inspector：`gravity`(300)、`mass`(1.0)、`music_run_speed`(24)、`music_run_duration`(0.8)。
- 公开接口：`apply_external_impulse(impulse)`（外部事件改变速度的唯一入口）；`run_in_direction(direction)`（音乐子弹触发定速奔跑）。
- 行为不变量：普通接触不传递 Warma 水平速度；可多只堆叠；堆叠中任一只水平滑动不拖动另一只；失去支撑正常下落；真实侧面接触仍然阻挡；被 Warma 从下方顶起时只受竖直冲量。
- 已有测试：`giraffe_physics_test`、`giraffe_stacking_test`、`precision_platforming_test`（头部/脚边）。

### 3. Elevator — `objects/elevator.gd` + 四个方向场景

- AnimatableBody2D，layer 1（属于地形），`sync_to_physics`。方向即场景：`elevator_up/down/left/right.tscn`，各自已保存旋转后的碰撞与可视形状。
- Inspector：`min_height`(3，下限 3)、`max_height`(32)、`height_speed`(24)、`starts_extended`、`button_path`(NodePath)、`elevator_color`。
- 公开接口：`set_button_source(node)`、`set_button_active(bool)`、`set_height/get_height`、`snap_body_to_support(body, tolerance)`、`supports_body(body, tolerance)`、`get_support_surface_y()`。
- 行为不变量：伸缩杆可穿过 Blocks/tiles 生长，但新增条带内有 actor **或其他电梯杆**时停止（电梯互为实体：相向生长撞上即双向夹停，各自保留按钮目标，一方缩回后另一方自动恢复运动；静态杆对生长杆同样实心——见 EXTENSIBILITY_FINDINGS 3h）；UP 电梯是唯一移动支撑面，携带完整 Warma/Giraffe 堆叠，且不会把承载者推进头顶地形；正在上升（跳跃）的物体不会被重新吸附；缩回和向下运动先移动被承载者再提交形状。
- 每个 `_ready` 复制自己的 CollisionShape2D 资源——同场景多实例不共享形状（测试锁定）。
- 按钮连接两条路：Button 的 `target_elevator` 或 Elevator 的 `button_path`。一个电梯同一时刻只有一个按钮源（后连接者替换前者）。
- 已有测试：`elevator_regression_test`（方向几何/支撑/堆叠/接缝/阻挡/资源隔离/上升排斥/重置）。

### 4. Button（压力板）— `objects/button.tscn` + `objects/button.gd`

- Area2D，检测 layer 2|4。Warma 或 Giraffe 的身体矩形与压力区重叠即激活。
- Inspector：`target_elevator`(NodePath)、`pressure_size`(14×4)。压力形状默认位于按钮上方（`PressureShape` 位置 (0,-6)）。
- 信号：`activation_changed(active)`。公开接口：`set_activated/activate/deactivate/is_activated`。
- 已有测试：`new_features_test`（Warma/Giraffe 踩板、控制电梯）。

### 5. Door — `objects/door.tscn` + `objects/door.gd`

- Area2D，Warma 站入区域后按 W 进入 `next_room`（`@export_file("*.tscn")`）。留空则门不可用。
- 公开接口：`enter_room()`。每次切换释放旧房间场景；`GameState` 保留。
- 已有测试：`room_transition_test`（W 触发/重复进入守卫/空目标/独立实例）。

### 6. Music bullet — `objects/music_bullet.tscn` + `objects/music_bullet.gd`

- Area2D，扫描 layer 1|4（地形+长颈鹿），穿过 Warma 与所有 Area2D。
- Inspector：`speed`(24)、`growth_duration`(0.24)、`lifetime`(12)。由 Warma 的 `music_bullet_speed/growth_duration` 决定实际值。
- 行为：成长动画（约 3 帧）结束才开始飞行；ShapeCast 全位移扫描防高速穿墙；撞地形消失；撞长颈鹿触发 `run_in_direction`；被地形保护的长颈鹿不会被隔墙命中。
- 已有测试：`music_bullet_test`（成长/飞行/地形/长颈鹿/穿体/rapid fire）。

### 7. Extinguisher pickup / 装备 — `objects/extinguisher_pickup.tscn`

- Area2D；Warma 触碰即 `pick_up_extinguisher()`（`GameState.has_extinguisher = true`）并消失。
- 装备状态由 Autoload `GameState` 跨房间保留；`room.gd` 记录进入房间时的状态，死亡重置恢复到进入时。
- 已有测试：`death_reset_test`、`room_transition_test`、`music_bullet_test`。

### 8. GameState（Autoload）— `objects/game_state.tscn` + `objects/game_state.gd`

- `has_extinguisher: bool`；`speed_multiplier` 离散档位 [0.1, 0.2, 0.5, 1.0]（左右箭头调节），`signal speed_changed`，`reset_speed()`。
- 已有测试：`new_features_test`（速度档位）、`title_screen_test`（启动时不泄键）。

### 9. Room 基类 — `rooms/room.gd`

- `@tool` Node2D。`reset_scene()`：恢复进入时装备状态并 `reload_current_scene()`；`freeze_for_death()`：`PROCESS_MODE_DISABLED` 冻结整棵房间树。
- 房间 = 场景组合：Background（编辑器隐藏）+ 地形（Blocks TileMapLayer 或 Block 实例）+ Player + Door + HUD + 任意 objects/ 实例 + EntryText/Signboard。房间脚本不包含 gameplay。

### 10. 前景文字 — `objects/screen_text.tscn`（EntryText）与 `objects/signboard.tscn`

- ScreenText：`message/font_size/text_color/display_duration/centered/center_on_screen`；时长 0 = 常驻。同一视口同时只显示一条 foreground message（组内仲裁）。
- Signboard：靠近显示、离开隐藏；`message/text_position/centered/text_above_sign/text_distance/text_width/font_size/area_size`。
- 已有测试：`foreground_messages_test`、`title_screen_test`。

### 11. 地形 — `objects/block.tscn`（单块）与 `objects/blocks.tscn`（TileMapLayer）+ `objects/tileset.tres`

- 两者同一贴图（block.png）、同一碰撞（16 宽 × 15.98 高，上下各 0.01px 内缩），物理等价。
- Block 是可独立摆放的 StaticBody2D（组 `block`），原点在方块中心；TileMapLayer 用于绘制连续地形。
- 已有测试：`room_transition_test`（契约）、`precision_platforming_test`（tile/block 接缝与窄缝等价性）。

### 12. HUD / Background — `objects/hud.tscn`、`objects/background.tscn`

- HUD：CanvasLayer，按键提示 + 速度显示（`PROCESS_MODE_ALWAYS`）。
- Background：z=-10 背景图。

---

## 第二部分：Showcase Room 目录

命名与结构（生成器 `tools/generate_showcase_rooms.gd` + 定义 `tools/showcase_room_defs.gd` 产出 `rooms/showcase/*.tscn`）：

| 前缀 | 分类 |
|---|---|
| `fnd_` | FOUNDATION 单机制 |
| `fnd_giraffe_` | GIRAFFE 单机制（无独立 `grf_` 前缀，长颈鹿基础房挂在 `fnd_` 命名下） |
| `elv_` | ELEVATOR 单机制 |
| `cmb_` | COMBINATIONS 双机制 |
| `mlt_` | MULTI 三机制以上 |
| `trt_` | TORTURE 物理压力测试 |
| `chl_` | CHALLENGE 综合关卡 |

### 2.0 总览

`rooms/showcase/` 共 **35 个房间**：27 个内容房间（fnd_* 6、fnd_giraffe_* 3、elv_* 3、cmb_* 7、mlt_* 3、trt_* 3、chl_* 2）+ showcase_hub + 7 个分类 index。全部由 `tools/generate_showcase_rooms.gd` 从 `tools/showcase_room_defs.gd` 声明式生成（ASCII 地图 `#` = 一个 block.tscn 实例，things/doors = objects/ 实体），**不含任何 room-specific 代码**——每个房间都是 `rooms/room.gd` 基类 + 可复用场景的纯组合。

**启动方式**（不改变默认启动流程，默认入口仍是 `rooms/title.tscn`）：

```powershell
godot --path . res://rooms/showcase/showcase_hub.tscn
```

**生成器工作流**：改 `tools/showcase_room_defs.gd` → 运行生成器 → 提交 defs 与产物两者。

```powershell
godot --headless --path . --script res://tools/generate_showcase_rooms.gd
```

生成器输出是确定性的：同一 defs 重跑逐字节一致（本轮实测 31/35 个房间重跑逐字节一致，其余 4 个是磁盘产物落后于刚修改的 defs——重跑后同步，非不确定性）。生成器自带校验（地图 16×9、实体不重叠、button 必须嵌在 `#` 格、door target 必须是已定义房间或存在的 res:// 路径，`tools/generate_showcase_rooms.gd:90-170`），但**不校验"预期的空槽"**——地图笔误靠物理测试兜底（见 `trt_precision` 与 EXTENSIBILITY_FINDINGS 3f）。

**物理换算（120Hz）**：物理 120 tick/s（`project.godot` `physics/common/physics_ticks_per_second=120`），求解器 32 次迭代、0.01px 最大穿透。手动 QA 推算行程时按 1 tick = 1/120 s 换算：

| 量 | 数值 | 每 tick |
|---|---|---|
| Warma 行走 | 60 px/s | 0.5 px/tick |
| 电梯 8/12/16/24/48 px/s | — | 0.0667/0.1/0.1333/0.2/0.4 px/tick |
| 重力 300 px/s² | 每 tick 下落速度 +2.5 px/s | +0.0208 px/tick |
| 满按跳（长按 J） | 上升 38.1 px（第 60 tick 到顶）、滞空 120 tick | 水平漂移 ~60 px |
| 音符 | 成长 ~0.24s（3 帧）后起飞，24 px/s | 0.2 px/tick |
| 音符驱鹿 | 命中后 24 px/s × 0.8s ≈ 19.2 px + 摩擦滑行 ~3 px | 每发 ≈ 22 px |
| 支撑宽限 / 跳跃缓冲 | 0.10s / 0.15s | 12 / 18 tick |
| 死亡闪烁 | 0.08s × 2 段 × 2 次 ≈ 0.32s | 冻结期间电梯曾实测漂移 1.9px @12px/s（已修，见 EXTENSIBILITY_FINDINGS 3a） |

慢速观察可用 `←/→` 调节 GameState 速度档（0.1/0.2/0.5/1.0），档位只改 `Engine.time_scale`，不改变几何结论。

**0.01px 支撑面规则**：Block 碰撞 16×15.98（`objects/block.tscn`），行 y 的砖块顶面在 `y*16+0.01`；水平电梯支撑面 = `pos.y - 4`（无沿轴内缩，`objects/elevator.gd:285-293`）。因此**水平桥/空中走廊的锚点一律写 `pos.y = y*16 + 4.01`**，使支撑面与相邻砖块碰撞面精确齐平（0.00px 台阶，双向可走）；任何留下 0.01px 高低差的锚定都会让接缝单向挡死（实测记录：支撑面高于砖面 0.01px 时，从砖顶走向电梯在桥面悬边处停死——GroundProbe 的地形分支先返回，电梯吸附契约永不生效）。涉及：`elv_horizontal` Bridge1/Bridge2、`mlt_elevator_relay` Bridge1、`trt_elevator` LiftD/LiftE。完整缺陷记录见 EXTENSIBILITY_FINDINGS 3e。

### 2.1 总表

| 房间 | Purpose（回答什么问题） | Mechanics | 自动测试 | 核心代码变化 |
|---|---|---|---|---|
| fnd_movement | A/D 与可变高度跳的基础操作 | Warma、Door、Signboard | showcase_test_foundation | 否 |
| fnd_precision | 浮空单块上的边缘支撑起跳 | Warma、Door | showcase_test_foundation | 否 |
| fnd_wall_jump | 贴墙起跳不穿墙不卡住 | Warma、Door | showcase_test_foundation | 否 |
| fnd_button | 瞬时压力板与电梯伸缩联动 | Button、Elevator | showcase_test_foundation | 否 |
| fnd_music_bullet | 拾取灭火器、音符驱赶长颈鹿 | Pickup、Music bullet、Giraffe | showcase_test_foundation | 否 |
| fnd_death_reset | 深坑坠落与 R 的死亡重置 | Warma 死亡、Room 重置 | showcase_test_foundation / contract | 否 |
| fnd_giraffe_contact | 长颈鹿侧面挡路/头顶可站/不拖动 | Giraffe | showcase_test_giraffe_elevator | 否 |
| fnd_giraffe_stack | 三只叠罗汉成阶梯 | Giraffe 堆叠 | showcase_test_giraffe_elevator | 否 |
| fnd_giraffe_bump | 从下方顶起头顶长颈鹿 | Warma 头顶冲量、Giraffe | showcase_test_giraffe_elevator | 否 |
| elv_up | 按钮驱动的向上伸缩 + 常伸电梯平台 | Button、Elevator(up) | showcase_test_giraffe_elevator | 否 |
| elv_down | 向下伸缩在吞人前停止 | Elevator(down) | showcase_test_giraffe_elevator | 否 |
| elv_horizontal | 常伸水平桥与砖块无缝对接 | Elevator(left/right) | showcase_test_giraffe_elevator | 否 |
| cmb_giraffe_elevator | 长颈鹿压钮 = 电梯锁存 | Giraffe、Button、Elevator | showcase_test_combinations | 否 |
| cmb_bullet_plate | 音符把长颈鹿赶到钮上解锁电梯 | Music bullet、Giraffe、Button、Elevator | showcase_test_combinations | 否 |
| cmb_elevator_door | 先登杆、鹿压钮、乘梯到高台门 | 全部上述 + Door | showcase_test_combinations | 否 |
| cmb_pickup_a / _b | 装备状态跨房间保留 | Pickup、GameState、Door | showcase_test_combinations / contract | 否 |
| cmb_reset_giraffe | 长颈鹿掉坑后 R 复原 | Giraffe、R 重置 | showcase_test_combinations | 否 |
| cmb_reset_elevator | 电梯运动中 R 复原高度位置 | Elevator、R 重置 | showcase_test_combinations | 否 |
| mlt_giraffe_logistics | 赶鹿压钮 + 乘梯上高台的物流线 | 三机制串联 | showcase_test_multi_challenge | 否 |
| mlt_stack_freight | 常伸电梯 + 长颈鹿两级塔 | Elevator、Giraffe | showcase_test_multi_challenge | 否 |
| mlt_elevator_relay | 过桥、鹿压钮锁存、电梯塔、跳高塔 | 四机制接力 | showcase_test_multi_challenge | 否 |
| trt_elevator | 双梯同钮异速/下伸保护/空中走廊 | Elevator 压力场 | showcase_test_torture / contract | 否 |
| trt_giraffe | 驮者被射失撑、台上鹿当台阶 | Giraffe 压力场 | showcase_test_torture | 否 |
| trt_precision | 墙缝/一格台阶/边缘起跳 | Warma 精准移动 | showcase_test_torture | 否 |
| chl_musical_freight | 赶鹿-乘梯-支撑宽限越深渊 | 综合关卡 | showcase_test_multi_challenge | 否 |
| chl_vertical_climb | 电梯台+长颈鹿+双阶梯柱+塔顶门 | 综合关卡 | showcase_test_multi_challenge | 否 |

全部房间的"核心代码变化"均为**否——纯 Inspector/场景组合**；两处需要解释的设计签名在对应小节注明（cmb_elevator_door 的"先上电梯再让长颈鹿压钮"、elv_horizontal 的常伸桥）。

### 2.2 导航结构（hub + 7 个 index）

导航房在 defs 的 `NAV_ROOMS`（`tools/showcase_room_defs.gd:646-823`），没有手写 things：生成器自动放置出生点 (0,7)（`tools/generate_showcase_rooms.gd:16,67-68`），并为每扇带 `label` 的门在门上方 `cell.y*16-24` 处生成一块 Signboard（`tools/generate_showcase_rooms.gd:312-321`）。EntryText 显示 2.5s。每扇门 `W` 进入；内容房出口门 target = 它的分类 index。

| 房间 | 门（cell → 目标） | 标签 |
|---|---|---|
| showcase_hub | 1/3/5/7/9/11/13 → 七个分类 index | 基础/长颈鹿/电梯/组合/多机制/压力测试/挑战 |
| foundation_index | 1/3/5/7/9/11 → fnd_movement/precision/wall_jump/button/music_bullet/death_reset；14 → hub | 移动跳跃/精准平台/贴墙起跳/压力板/音符/死亡重置/返回 |
| giraffe_index | 2/6/10 → fnd_giraffe_contact/stack/bump；14 → hub | 接触/叠罗汉/顶起/返回 |
| elevator_index | 2/6/10 → elv_up/down/horizontal；14 → hub | 向上/向下/水平/返回 |
| combinations_index | 1/3/5/7/9/11 → cmb_giraffe_elevator/bullet_plate/elevator_door/pickup_a/reset_giraffe/reset_elevator；14 → hub | 鹿压钮/赶鹿上台/乘梯进门/拾取跨房/重置长颈鹿/重置电梯/返回 |
| multi_index | 2/6/10 → mlt_giraffe_logistics/stack_freight/elevator_relay；14 → hub | 物流线/叠塔/双桥接力/返回 |
| torture_index | 2/6/10 → trt_elevator/giraffe/precision；14 → hub | 电梯/长颈鹿/精准/返回 |
| challenge_index | 4/9 → chl_musical_freight/vertical_climb；14 → hub | 音符货运/垂直攀爬/返回 |

导航不变量：从 hub 沿 `next_room` 门图必须可达全部 35 个房间（`tests/showcase_contract_test.gd` TEST 2）；真实 W 门转换环 hub → foundation_index → fnd_movement → 返回（TEST 3）；导航房门名 Door1..N 唯一，否则 Godot 只注册最后一个同名 Area2D（缺陷 3c 的回归覆盖）。

### 2.3 FOUNDATION（fnd_*，6 个）

#### fnd_movement — FOUNDATION · 移动与跳跃
- **Purpose**：A/D 移动与 J 可变高度跳的最小可玩示范。
- **Mechanics**：Warma（1）、Door（5）、Signboard/EntryText（10）、Block 地形（11）。
- **Expected behavior**：地面行走 60px/s（0.5px/tick）；轻点 J 小跳、长按 J 满跳上升 38.1px；两级台阶（row 7 顶 112.01、row 6 顶 96.01）逐级 16px 跳上；门 (14,5) 站在二级台阶上。
- **Manual test**：①A/D 左右走；②轻点 J 与长按 J 对比跳高；③逐级跳上两级台阶；④站上门按 W 回 foundation_index。
- **Automated tests**：`tests/showcase_test_foundation.gd`（fnd_movement 站立高度/台阶跳跃）；`tests/showcase_contract_test.gd`（加载、可达性、出生点重置）。
- **Invariants**：Warma 碰撞多边形 x=-2..3, y=-8..8（`objects/warma.gd:7-8`，测试锁定）；站立中心 = 支撑面 y − 8（砖顶 y*16+0.01）。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### fnd_precision — FOUNDATION · 精准平台
- **Purpose**：部分脚在边缘上也算支撑、一样能起跳。
- **Mechanics**：Warma（1）、Door（5）、Block 地形（11）。
- **Expected behavior**：三块浮台逐级上升：(7-8,6) 顶 96.01（从地面满跳 32px）、(11-12,5) 顶 80.01、(14,4) 顶 64.01；门 (14,3) 站在最上一块。站在块边缘只剩部分脚掌时 GroundProbe 仍判定支撑、可起跳。
- **Manual test**：①依次满跳上三块浮台；②站到某块边缘让部分脚悬空，按 J 确认能起跳；③进门回 index。
- **Automated tests**：`tests/showcase_test_foundation.gd`（fnd_precision 站位）；`tests/precision_platforming_test.gd`（边缘支撑规则本体）。
- **Invariants**：GroundProbe 覆盖完整脚宽、只接受向上法线、脚面差 ≤0.02px（`objects/warma.gd:260-269`）。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### fnd_wall_jump — FOUNDATION · 贴墙起跳
- **Purpose**：贴着墙起跳不会穿墙也不会被卡住。
- **Mechanics**：Warma（1）、Door（5）、Block 地形（11）。
- **Expected behavior**：col 8 一列两块（32px）墙立在地面；向墙走贴住后按 J，上升段贴墙滑移、水平速度被墙面截停但不穿透；墙顶 96.01 可满跳站上；门 (13,7) 在墙右侧地面。
- **Manual test**：①向墙走直到贴住；②贴墙按 J 起跳数次；③满跳上墙顶；④跳回地面进门。
- **Automated tests**：`tests/showcase_test_foundation.gd`（fnd_wall_jump）；`tests/wall_jump_test.gd`（规则本体）。
- **Invariants**：轴向 test-only 移动、只提交本轴 travel（`objects/warma.gd:185-198`）——接触恢复不会把角色横移。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### fnd_button — FOUNDATION · 压力板与电梯
- **Purpose**：瞬时压力板驱动电梯伸缩的基本联动（站上伸出、离开缩回）。
- **Mechanics**：Button（4）、Elevator up（3）、Door（5）。
- **Expected behavior**：站上 Btn1 (7,8) → Lift1 (9,8) 以 12px/s（0.1px/tick）从 3 伸到 24（杆顶支撑面 104.005）；离开按钮立刻缩回，且 UP 电梯缩回时载着骑乘者一起降回。从按钮位置满跳可以"趁早"落上仍在伸/刚到顶的杆顶，再从杆顶跳 8px 上 2×2 台（顶 96.01）进门 (13,5)。
- **Manual test**：①站上按钮看杆伸出；②满跳跳上杆顶；③离钮后趁杆未缩太多跳上 2×2 台；④进门。
- **Automated tests**：`tests/showcase_test_foundation.gd`（fnd_button 伸缩/端点高度）；`tests/elevator_regression_test.gd`（支撑/缩回载物）；`tests/showcase_contract_test.gd` TEST 8（死亡冻结停止电梯）。
- **Invariants**：激活 = Warma/Giraffe 身体矩形与压区（14×4 @ (0,-6)）重叠（`objects/button.gd:29-45`）；UP 电梯伸/缩两个方向都携带承载栈（`objects/elevator.gd:67-72`）；`min_height` 下限 3（`objects/elevator.gd:36`）。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### fnd_music_bullet — FOUNDATION · 灭火器与音符
- **Purpose**：拾取灭火器、发射音符、命中长颈鹿让它奔跑。
- **Mechanics**：Pickup（7）、Music bullet（6）、Giraffe（2）、Door（5）。
- **Expected behavior**：触碰 pickup 后 `GameState.has_extinguisher = true`、装备可见；K 发射音符（成长 ~0.24s 后起飞，0.2px/tick）；命中长颈鹿触发 `run_in_direction`，长颈鹿向右跑 ~22px/发，撞 (12,7) 方块停住。未拾取时 K 无效（`objects/warma.gd:170-172`）。
- **Manual test**：①走进拾取物；②对长颈鹿按 K 数发，观察奔跑与撞墙停住；③进门。
- **Automated tests**：`tests/showcase_test_foundation.gd`（fnd_music_bullet）；`tests/music_bullet_test.gd`（成长/飞行/命中本体）。
- **Invariants**：音符扫描 layer 1|4、穿过 Warma 与 Area2D、撞地形消失（`objects/music_bullet.gd`）；被地形隔开的长颈鹿不会被隔墙命中。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### fnd_death_reset — FOUNDATION · 死亡与重置
- **Purpose**：掉下深坑或按 R 都会重置本房间。
- **Mechanics**：Warma 死亡（1）、Room 基类重置（9）、Door（5）。
- **Expected behavior**：地面 cols 10-12 缺口为深坑；身体底沿触及 `fall_limit=144` 或按 R → `die()` 冻结所在房间（`freeze_for_death`）→ 闪烁两次（0.08s×4 段）→ `reset_scene()` 重载本房并恢复进入时的装备状态。
- **Manual test**：①走进深坑坠落，观察闪烁与自动重置；②按 R 再触发一次；③进门。
- **Automated tests**：`tests/showcase_test_foundation.gd`（fnd_death_reset R 重载）；`tests/showcase_contract_test.gd` TEST 4/7（出生点还原、坑坠落重置）；`tests/death_reset_test.gd`（规则本体）。
- **Invariants**：`fall_limit=144`（`objects/warma.gd:23,125`）；`reset_scene()` 恢复 `GameState.has_extinguisher` 到进入时（`rooms/room.gd:16-24`）。
- **核心代码变化**：否——纯 Inspector/场景组合。

### 2.4 GIRAFFE（fnd_giraffe_*，3 个）

#### fnd_giraffe_contact — GIRAFFE · 基础接触
- **Purpose**：侧面挡路、头顶可站、走开不会拖动它。
- **Mechanics**：Giraffe（2）、Door（5）。
- **Expected behavior**：长颈鹿 (8,7) 落定于中心 (136,120.01)；Warma 向右走撞其左面（x≈132）停住，长颈鹿不动；跳上头顶站 104.01；走开时长颈鹿位置与速度不变。
- **Manual test**：①向长颈鹿走，撞停；②跳上头顶站住；③走开，回头看长颈鹿没被带走；④进门。
- **Automated tests**：`tests/showcase_test_giraffe_elevator.gd`（fnd_giraffe_contact）；`tests/giraffe_physics_test.gd`（规则本体）。
- **Invariants**：普通接触不传递水平速度——`velocity` 只经 `apply_external_impulse` 改变（`objects/giraffe.gd:100-103`）；8×16 单一完整碰撞体、`safe_margin=0`、`custom_solver_bias=1.0`。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### fnd_giraffe_stack — GIRAFFE · 叠罗汉
- **Purpose**：长颈鹿会叠成阶梯，逐级跳上去。
- **Mechanics**：Giraffe 堆叠（2）、Door（5）。
- **Expected behavior**：三只落定成三层：Giraffe1 地面 120.01、Giraffe2 叠上 104.01、Giraffe3 再叠 88.01；头顶形成 112.01/96.01/80.01 阶梯；任一只水平滑动不拖动邻居；Warma 站顶跳走不带动塔。
- **Manual test**：①逐级跳上三层；②在顶层跳下；③贴塔侧走确认仍阻挡；④进门。
- **Automated tests**：`tests/showcase_test_giraffe_elevator.gd`（fnd_giraffe_stack）；`tests/giraffe_stacking_test.gd`（规则本体）。
- **Invariants**：堆叠判定 gap ≤0.75px 且水平重叠（`objects/giraffe.gd:74-83`）；水平扫描对骑乘者加碰撞例外（`objects/giraffe.gd:54-59`）。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### fnd_giraffe_bump — GIRAFFE · 从下方顶起
- **Purpose**：起跳把头顶的长颈鹿顶起来，它落回来还能再顶，R 可重置。
- **Mechanics**：Warma 头顶冲量（1）、Giraffe（2）、Door（5）。
- **Expected behavior**：长颈鹿 (8,6) 静置玩家头顶（其中心 104.01、Warma 中心 120.01）；每次起跳帧 HeadProbe（扫描长度 = 起跳帧位移 + ~0.07px，满跳首帧 ≈1.32px）命中后经 `apply_external_impulse` 只给竖直冲量；长颈鹿升-落循环可连顶；R 重置归位。
- **Manual test**：①原地连按 J 连续顶起；②观察长颈鹿落回原位；③按 R 复位；④进门。
- **Automated tests**：`tests/showcase_test_giraffe_elevator.gd`（fnd_giraffe_bump）；`tests/precision_platforming_test.gd`（头顶冲量）。
- **Invariants**：冲量唯一入口 `apply_external_impulse`（`objects/giraffe.gd:100-103`）；`_lift_giraffes_above` 只扫起跳帧实际位移、只接受向上接触法线且长颈鹿明确在上方（`objects/warma.gd:278-311`）；冲量预补长颈鹿的重力步使两者首帧位移一致（`objects/warma.gd:304-310`）。
- **核心代码变化**：否——纯 Inspector/场景组合。**设计签名**：长颈鹿必须静置玩家头顶——若把它放在基座砖上，16px 基座挡在头部与长颈鹿之间，起跳帧 1.32px 的头部扫描永远够不着（开发中实际踩过，见 EXTENSIBILITY_FINDINGS 3d-1）。

### 2.5 ELEVATOR（elv_*，3 个）

#### elv_up — ELEVATOR · 向上伸缩
- **Purpose**：按钮驱动的向上伸缩（左），以及常伸电梯当平台（右）。
- **Mechanics**：Button（4）、Elevator up（3）、Door（5）。
- **Expected behavior**：左侧 Btn1 (6,8) 压住时 Lift1 (8,8) 伸到 24（顶 104.005）、释放即缩回并载着骑乘者降回；右侧 Lift2 (212,128) `min=max=16, starts_extended` 为静态平台，支撑面 112.005 与相邻砖顶 112.01 齐平；门 (14,7) 在地面。
- **Manual test**：①站 Btn1 看杆伸出；②跳上杆顶，走离按钮被载着降回；③跳上右侧常伸平台；④进门。
- **Automated tests**：`tests/showcase_test_giraffe_elevator.gd`（elv_up 三实体与两端行为）；`tests/elevator_regression_test.gd`（UP 支撑/堆叠）。
- **Invariants**：`starts_extended` 的释放目标仍是 max（伸态为常态，`objects/elevator.gd:52-54`）；UP 电梯是唯一移动支撑面（`objects/elevator.gd:110-113`）。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### elv_down — ELEVATOR · 向下伸缩
- **Purpose**：向下的电梯会在吞掉你之前停下。
- **Mechanics**：Button（4）、Elevator down（3）、Door（5）。
- **Expected behavior**：Lift1 (6,2) 锚在 row 2 块底 (104,48)，向下伸最大 68（杆端 116）；玩家站上 Btn1 (6,8)（头顶 112.01）后杆向下生长，`_growth_blocked` 在接触头顶前以 `GROWTH_CLEARANCE`(0.05px) 间隙夹停——下行杆无法搬运障碍，杆端永不与身体重叠（见 EXTENSIBILITY_FINDINGS 3g）；离开按钮杆缩回 3。
- **Manual test**：①站上按钮；②看杆停在自己头顶上方不再下降；③走开看杆缩回；④进门。
- **Automated tests**：`tests/showcase_test_giraffe_elevator.gd`（elv_down）；`tests/elevator_regression_test.gd`（向下方向几何/下压保护）。
- **Invariants**：生长遇新增条带内 actor 或其他电梯杆停止（`objects/elevator.gd` `_growth_blocked`）；DOWN 电梯支撑面固定在锚端、不载物（`objects/elevator.gd:198-215`）。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### elv_horizontal — ELEVATOR · 水平伸缩
- **Purpose**：两座常伸电梯桥，平面与砖块齐平，走过去。
- **Mechanics**：Elevator right/left（3）、Door（5）。
- **Expected behavior**：Bridge1 (48,84.01) 向右伸 80（跨 48..128）、Bridge2 (208,68.01) 向左伸 32（跨 176..208），支撑面均为 pos.y−4，与相邻砖块碰撞面（80.01 / 64.01）精确齐平——从左台走过桥 1 直到中平台 (8-10,5-7) 全程无缝不需要跳；中平台跳 16px 上桥 2；桥 2 与右岸高台 (14-15,4，顶 64.01) 齐平直接走到门口 (15,3)。
- **Manual test**：①从左台直接走过桥 1 上中平台（全程不跳）；②在中平台跳上桥 2（16px）；③走过桥 2 上右岸进门。
- **Automated tests**：`tests/showcase_test_giraffe_elevator.gd`（elv_horizontal）；同一齐平规则的接力探针在 `tests/showcase_test_multi_challenge.gd`（mlt_elevator_relay 缝隙探针）与 `tests/showcase_test_torture.gd` e 段（空中走廊）。
- **Invariants**：水平支撑面无沿轴内缩（`objects/elevator.gd:285-293`）；锚点 `pos.y = y*16 + 4.01`（`tools/showcase_room_defs.gd:285-286`）——0.01px 台阶规则见 EXTENSIBILITY_FINDINGS 3e。
- **核心代码变化**：否——纯 Inspector/场景组合。**设计签名（常伸桥的原因）**：瞬时按钮下缩回桥永远追上独行玩家——桥若由按钮驱动，压钮者上桥后无人压钮，桥以 height_speed（个位数到两位数 px/s）缩回，而玩家行走 60px/s；唯一稳定的用法就是 `starts_extended` 常伸当静态平台。

### 2.6 COMBINATIONS（cmb_*，7 个）

#### cmb_giraffe_elevator — COMBO · 长颈鹿压按钮
- **Purpose**：长颈鹿压住按钮，电梯就一直伸着——用组合实现"锁存"。
- **Mechanics**：Giraffe（2）、Button（4）、Elevator up（3）、Door（5）。
- **Expected behavior**：长颈鹿 (5,7) 落定即压住正下方 Btn1 (5,8)，电梯常伸 32（顶 96.005，与 2×2 台 96.01 齐平）；玩家满跳 32px 上杆顶（88.01），再从杆顶同高满跳 ~52px 上台进门 (13,5)；R 重置后长颈鹿复位、仍压钮。
- **Manual test**：①等长颈鹿落定、电梯升满；②跳上杆顶；③同高跳上高台；④进门；⑤按 R 验证复位后依旧锁存。
- **Automated tests**：`tests/showcase_test_combinations.gd` `_test_giraffe_elevator`；`tests/showcase_contract_test.gd`（重置契约）。
- **Invariants**：长颈鹿身体 8px 宽把按钮窗口从压区 14px 扩到 |dx|≤11（`tools/showcase_room_defs.gd` + `objects/button.gd:84-88`）；锁存 = 长颈鹿持续重叠，无任何新状态。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### cmb_bullet_plate — COMBO · 把长颈鹿赶上台
- **Purpose**：用音符把长颈鹿赶到按钮上，别让它冲过头。
- **Mechanics**：Pickup（7）、Music bullet（6）、Giraffe（2）、Button（4）、Elevator up（3）、Door（5）。
- **Expected behavior**：从 72 出发每发音符推进 ~22px，4 发后进入 Btn1 (10,8) 窗口（157..179，实测停在 ~160）；若冲过头，Lift1 (13,8) 缩回的杆面（x=212）会替它刹车；电梯 0.2px/tick 升满 32（顶 96.005，与塔 96.01 齐平）；杆顶小跳上塔进门 (15,5)。
- **Manual test**：①拾取灭火器；②K 连发把鹿赶向按钮（观察停位）；③鹿压钮后跳上电梯顶；④小跳上塔进门。
- **Automated tests**：`tests/showcase_test_combinations.gd` `_test_bullet_plate`。
- **Invariants**：一发 ≈22px 的可复现性（24px/s × 0.8s + 摩擦 ~3px）；缩回杆面作为鹿的挡停物是几何事实而非脚本。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### cmb_elevator_door — COMBO · 让电梯载着你上升
- **Purpose**：先用音符把长颈鹿赶上按钮，趁电梯上升进门——完整验证"载物栈 + 锁存"两个机制。
- **Mechanics**：Pickup（7）、Giraffe（2）、Button（4）、Elevator up（3）、Door（5）。
- **Expected behavior**：设计签名**"先上电梯再让长颈鹿压钮"**——玩家先小跳站上缩回的杆顶（min 3，顶 125.005，离地 3px 需小跳），再发音符把鹿 (4,7) 赶到 Btn1 (8,8)；UP 电梯在生长方向同样携带骑乘者，从 3 载人到 48（顶 80.005）；杆顶跳 16px 上 shelf（row 4 cols 12-14，顶 64.01）进门 (13,3)。
- **Manual test**：①小跳上缩回的杆顶站好；②K 连发赶鹿压钮；③被载着上升直到 48；④跳上 shelf 进门。
- **Automated tests**：`tests/showcase_test_combinations.gd` `_test_elevator_door`。
- **Invariants**：UP 电梯生长方向载物（`objects/elevator.gd:63-72`）；被承载者不会被生长推入头顶地形（`objects/elevator.gd:158-159`）。
- **核心代码变化**：否——纯 Inspector/场景组合（签名原因：瞬时按钮无人值守即缩回；先站杆再压钮同时验证载物栈与长颈鹿锁存，且规避"跳上正在移动的杆"的高难度输入）。

#### cmb_pickup_a / cmb_pickup_b — COMBO · 拾取与跨房间（起点/终点）
- **Purpose**：装备（灭火器）跟着你进来了吗？
- **Mechanics**：Pickup（7）、GameState（8）、Music bullet（6，b 房）、Giraffe（2，b 房）、Door（5）。
- **Expected behavior**：a 房拾取后进门到 b：装备仍可见、K 可发射并击中 b 房长颈鹿 (8,7)；门回 a 时拾取物已消失（`GameState.has_extinguisher=true` 时 pickup 在 `_ready` 自毁，`objects/extinguisher_pickup.gd:5-8`）。
- **Manual test**：①a 房拾取、进门；②b 房按 K 射长颈鹿；③门回 a，确认拾取物不再出现。
- **Automated tests**：`tests/showcase_test_combinations.gd` `_test_pickup_cross_room`（含真实 W 进门）；`tests/showcase_contract_test.gd` TEST 6（拾取/重置卫生）；`tests/room_transition_test.gd`。
- **Invariants**：GameState 跨房保留（Autoload 不随场景释放）；`reset_scene()` 恢复进入时装备状态（`rooms/room.gd:16-24`）。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### cmb_reset_giraffe — COMBO · 重置找回长颈鹿
- **Purpose**：把长颈鹿射进深坑，再按 R 复原。
- **Mechanics**：Pickup（7）、Music bullet（6）、Giraffe（2）、R 重置（9）、Door（5）。
- **Expected behavior**：地面 cols 10-12 为深坑；音符把长颈鹿 (8,7) 赶进坑后，长颈鹿掉出世界**不被回收**（giraffe 无 fall_limit，对比 `objects/warma.gd:125`）；按 R 整场景重载，长颈鹿复原。
- **Manual test**：①拾取；②把长颈鹿打进坑，看它掉出屏幕；③按 R，长颈鹿回到原位；④进门。
- **Automated tests**：`tests/showcase_test_combinations.gd` `_test_reset_giraffe`。
- **Invariants**：`reset_scene()` 重载场景即恢复全部实例（`rooms/room.gd:21`）；"掉出世界不回收"是被本房间利用的行为——给它加 despawn 前先读 EXTENSIBILITY_FINDINGS 6。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### cmb_reset_elevator — COMBO · 重置正在动的电梯
- **Purpose**：电梯升到一半按 R，高度和位置都会复原。
- **Mechanics**：Button（4）、Elevator up（3）、R 重置（9）、Door（5）。
- **Expected behavior**：压 Btn1 (6,8) 后 Lift1 (8,8) 以 8px/s 伸向 40；运动中按 R → 场景重载 → 电梯回到 min 3、按钮未激活，一切从头。
- **Manual test**：①压钮让杆升到一半；②按 R；③确认杆从缩回态重新开始；④进门。
- **Automated tests**：`tests/showcase_test_combinations.gd` `_test_reset_elevator`；`tests/elevator_regression_test.gd`（room reset 段）。
- **Invariants**：状态复原不依赖逐字段快照——整个场景重载（`rooms/room.gd:16-24`）。
- **核心代码变化**：否——纯 Inspector/场景组合。

### 2.7 MULTI（mlt_*，3 个）

#### mlt_giraffe_logistics — MULTI · 长颈鹿物流线
- **Purpose**：让长颈鹿替你踩住按钮，再乘电梯上高台——三机制物流串联。
- **Mechanics**：Pickup（7）、Music bullet（6）、Giraffe（2）、Button（4）、Elevator up（3）、Door（5）。
- **Expected behavior**：3 发音符把长颈鹿 (4,7) 从 72 赶进 Btn1 (8,8) 窗口 129..143（实测 ~139），电梯 0.2px/tick 升满 32（顶 96.005，与高台 cols 13-14 rows 6-7 的 96.01 齐平）；鹿压钮全程保持激活；杆顶 (88.01) 同高满跳 ~36px 上高台进门 (14,5)。
- **Manual test**：①拾取；②三发赶鹿入位；③跳上电梯顶；④同高跳上高台进门。
- **Automated tests**：`tests/showcase_test_multi_challenge.gd` `_test_mlt_giraffe_logistics`（含拾取、窗口、载物、台面四段断言）。
- **Invariants**：长颈鹿窗口 = 压区中心 ±11；电梯顶 96.005 与砖顶 96.01 的 0.005px 差来自竖直电梯的 EDGE_INSET/2，落在 0.75px 吸附容差内（`objects/elevator.gd:285-293`）。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### mlt_stack_freight — MULTI · 电梯与叠塔
- **Purpose**：电梯平台 + 长颈鹿 = 两级塔。
- **Mechanics**：Elevator up 静态（3）、Giraffe（2）、Door（5）。
- **Expected behavior**：Lift1 (9,8) `min=max=32, starts_extended` 静态平台（顶 96.005），Giraffe1 (9,5) 落其上（中心 88.01，头 80.01）；shelf（row 4 cols 12-15，顶 64.01）；路线：地面→电梯顶（32px 跳）→鹿头（16px）→shelf（16px）→门 (14,3)；鹿在静态杆上零漂移、Warma 重量不压动它。
- **Manual test**：①跳上电梯顶；②跳上鹿头；③满跳上 shelf；④进门。
- **Automated tests**：`tests/showcase_test_multi_challenge.gd` `_test_mlt_stack_freight`（含静止与漂移断言）。
- **Invariants**：静态 UP 杆仍是移动支撑契约的载体（`snap_body_to_support` 每帧兜底，`objects/warma.gd:273-275`）；堆叠体在杆上位置逐帧稳定。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### mlt_elevator_relay — MULTI · 过桥接力
- **Purpose**：过桥、鹿压钮锁存电梯塔、跳上高塔——四机制接力。
- **Mechanics**：Elevator right（3）、Giraffe（2）、Button（4）、Elevator up（3）、Door（5）。
- **Expected behavior**：从左塔走过 96px 长的 Bridge1 (48,84.01，跨 48..144，两端与砖面齐平) 上中台 (9-11,5-8)；中台上长颈鹿 (10,4) 压住嵌在砖里的 Btn1 (10,5)，Lift1 (13,8) 锁存伸至 48（顶 80.005，与桥/台同面）；登上 Lift1 顶（72.01），贴右塔 (14-15,3-8，顶 48.01) 满跳 32px 上塔进门 (15,2)。
- **Manual test**：①从左塔走过桥（不跳）；②走上中台；③看鹿压钮、电梯升满；④上电梯顶、贴塔面满跳上塔；⑤进门。
- **Automated tests**：`tests/showcase_test_multi_challenge.gd` `_test_mlt_elevator_relay`（含接缝步行探针：从左塔不跳过缝上桥）。
- **Invariants**：Bridge1 max=96 恰好跨满 48..144——锚点 84.01 是 0.01px 规则的落地实例（EXTENSIBILITY_FINDINGS 3e）；鹿压钮锁存贯穿"过桥-登塔"全程，离钮即缩。
- **核心代码变化**：否——纯 Inspector/场景组合（本房间的接缝锚定经历过 0.01px 缺陷修复，见 3e）。

### 2.8 TORTURE（trt_*，3 个）

#### trt_elevator — TORTURE · 电梯压力场
- **Purpose**：电梯系统的极限用法：相邻双梯同钮异速、下压保护、空中双桥相接。
- **Mechanics**：Button（4）、Elevator up/down/left/right（3）、Giraffe（2）、Door（5）。
- **Expected behavior**：BtnA (1,8) 一个按钮驱动 LiftA (40,128，12px/s，max 40) 与 LiftB (52,128，48px/s，max 24)——异速同伸；Giraffe1 (2,4) 落在 LiftA 缩态顶 (117.01)，被上升的 LiftA 载上去。BtnC (6,8) 驱动 LiftC (6,2) 向下伸 max 68，玩家站在下方时杆在吞人前夹停。LiftD (160,100.01) 向右、LiftE (224,100.01) 向左，常伸 32，在 x=192 空中相接且顶面 (96.01) 与右基柱 (14,6) 齐平——可从 LiftD 步行穿越 D|E 接缝、再踏上右基柱。五根杆的碰撞形状资源两两独立。
- **Manual test**：①站 BtnA 看双杆异速伸出、长颈鹿被抬起；②站 BtnC 看下杆停在头顶上方；③跳上 LiftD，向右走过 D|E 接缝与右基柱；④进门。
- **Automated tests**：`tests/showcase_test_torture.gd` `_torture_elevator` a-f（静息/同钮双梯/接缝骑乘/下伸保护/空中走廊/形状隔离）；`tests/showcase_contract_test.gd` TEST 5（形状隔离）、TEST 8（死亡冻结）。
- **Invariants**：一钮多梯的两条接线方向在本房各用一次（BtnA.target_elevator→LiftA 走按钮侧，LiftB.button_path→BtnA 走电梯侧，`objects/button.gd:22-27` / `objects/elevator.gd:46-49`）；一个电梯同时只有一个按钮源，后连者替换（`objects/elevator.gd:74-88`）；骑乘者跨站 LiftA|LiftB 接缝时同步回缩会卡死——已知未修耦合，见 EXTENSIBILITY_FINDINGS 4。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### trt_giraffe — TORTURE · 长颈鹿压力场
- **Purpose**：驮者被射失撑掉落、台上长颈鹿当台阶、侧面挡路——堆叠与接触规则的极限组合。
- **Mechanics**：Pickup（7）、Music bullet（6）、Giraffe（2）、Door（5）。
- **Expected behavior**：Giraffe1 (7,7) 地面驮者、Giraffe2 (7,5) 叠其上（104.01）；音符 y=113 的弹道打到底层 Giraffe1（叠层 Giraffe2 底面 112.01 在弹道下方 0.99px 擦过）——Giraffe1 跑走后 Giraffe2 垂直下落、不被横拖；Giraffe3 (11,6) 站在基座砖 (11,7) 上当台阶（头 96.01），Warma 站上再跳走不会顶起它；Giraffe4 (13,7) 侧面挡路不动。
- **Manual test**：①拾取；②射底层驮者，看乘客直落；③跳上基座长颈鹿站住再跳走；④向 Giraffe4 走撞停；⑤进门。
- **Automated tests**：`tests/showcase_test_torture.gd` `_torture_giraffe` a-d。
- **Invariants**：驮者失撑后骑乘者垂直下落（水平扫描对骑乘者加例外，`objects/giraffe.gd:54-59`）；乘客起跳不给台阶鹿冲量——冲量只在"起跳帧 + 头顶对齐"时发射（`objects/warma.gd:278-311`）。
- **核心代码变化**：否——纯 Inspector/场景组合。**设计签名**：长颈鹿必须放在可接触的台阶位——放在高台顶上的长颈鹿底面高出头顶 32px，空中头碰只清零竖直速度、不补冲量，无法互动（开发中实际踩过，见 EXTENSIBILITY_FINDINGS 3d-2）。

#### trt_precision — TORTURE · 精准压力场
- **Purpose**：跳进墙缝、一格宽台阶、边缘起跳——Warma 移动系统的极限精度。
- **Mechanics**：Warma 窄缝/边缘（1）、Door（5）。
- **Expected behavior**：col 6 的墙（rows 3-4、6-7）在 (6,5) 留 16px 墙缝：助跑满跳从右侧贴墙进入，TIGHT_GAP_ALIGNMENT 最多对齐 0.75px，缝内骑在 y≈88、穿过后落回地面；一格台阶 (9,6)（顶 96.01）只托 ~3.5px 脚掌仍可支撑起跳；沿 (11,5)（80.01）、(13-14,4)（64.01）的一格宽链条上到门 (14,3)。
- **Manual test**：①右侧助跑满跳扎进墙缝，穿过后落地；②跳上一格台阶 (9,6)；③边缘起跳连上 (11,5)、(13-14,4)；④进门。
- **Automated tests**：`tests/showcase_test_torture.gd` `_torture_precision` a-c（含 `_slot_blocker_evidence` 墙缝堵塞证据函数）；`tests/precision_platforming_test.gd`、`tests/player_physics_test.gd`（规则本体）。
- **Invariants**：墙缝格 (6,5) 必须为空——生成器校验只查"button 必须在 # 格"、不查"预期的空槽"，地图笔误靠物理测试兜底（见 EXTENSIBILITY_FINDINGS 3f）；一格空隙入口的对齐上限 0.75px（`objects/warma.gd:10,200-242`）。
- **核心代码变化**：否——纯 Inspector/场景组合。

### 2.9 CHALLENGE（chl_*，2 个）

#### chl_musical_freight — CHALLENGE · 音符货运
- **Purpose**：赶鹿上钮、乘梯、跃过深渊——把"鹿压钮锁存"用于真正的关卡跨越。
- **Mechanics**：Pickup（7）、Music bullet（6）、Giraffe（2）、Button（4）、Elevator up（3）、Warma 支撑宽限（1）、Door（5）。
- **Expected behavior**：两发音符把长颈鹿 (4,7) 赶到 Btn1 (6,8) 的窗口 93..115（实测停在 ~112：第二发把鹿推到 Lift1 缩回杆面 x=116 前）；电梯升满 32（顶 96.005，与对岸 cols 12-15 rows 6-7 的 96.01 齐平）；深渊 x 144..192 宽 48px——从杆顶直接满跳最多到 x≈186，差 ~3px 必落坑；正确过法是从杆顶右缘（支撑范围到中心 ~126）走出，在失去支撑第 10 个 tick（0.1s 宽限内）按住 J，落在 x≈191。落坑会死亡重置，重赶即可。
- **Manual test**：①拾取、两发赶鹿；②小跳上缩回杆等升满；③从杆顶右缘走出，悬空约 0.08s 后按住 J；④落到对岸进门（失败落坑则等重置重来）。
- **Automated tests**：`tests/showcase_test_multi_challenge.gd` `_test_chl_musical_freight`（含"简报跳法"诊断探针与死亡重置恢复路径）。
- **Invariants**：全跳漂移 ~60px（滞空 120 tick × 0.5px/tick）；支撑宽限 0.10s（`objects/warma.gd:12`）；杆顶与对岸齐平是跨越成立的前提（0.01px 规则）。
- **核心代码变化**：否——纯 Inspector/场景组合。

#### chl_vertical_climb — CHALLENGE · 垂直攀爬
- **Purpose**：电梯台+长颈鹿+深坑+阶梯塔，一路向上的综合攀爬。
- **Mechanics**：Elevator up 静态（3）、Giraffe（2）、Warma 满跳几何（1）、Door（5）。
- **Expected behavior**：Lift1 (3,8) 静态 32（顶 96.005）载 Giraffe1 (3,5)（头 80.01）；满跳上电梯（32px）、跳上鹿头（16px）；满跳右越深坑（cols 6-7），下降沿在 x≈122 穿过 y=96.01，落在阶梯柱 A（col 7 rows 6-7，顶 96.01）；再满跳，下降沿 x≈162 落在阶梯柱 B（cols 9-11 rows 5-6，顶 80.01，与塔面齐平）；走到塔面贴住，满跳 32px 上塔（cols 12-15 rows 3-7，顶 48.01）进门 (13,2)。
- **Manual test**：①逐级跳上电梯与鹿头；②满跳越坑上柱 A；③再满跳上柱 B；④贴塔面满跳上塔；⑤进门。
- **Automated tests**：`tests/showcase_test_multi_challenge.gd` `_test_chl_vertical_climb`（逐跳脚本化：坑→A→B→塔）。
- **Invariants**：柱距与高度由全跳上升 38.1px / 漂移 ~60px 反推；静态杆 + 长颈鹿逐帧零漂移。
- **核心代码变化**：否——纯 Inspector/场景组合。**设计签名**：本房是重构产物——原路线坑后 Lift2 顶高出对岸地面 48px（超出 38.1px 满跳上升）且长颈鹿占满 8px 电梯座，实测不可达；现路线改为双阶梯柱（EXTENSIBILITY_FINDINGS 3d-3）。
