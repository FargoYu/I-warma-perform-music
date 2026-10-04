# Extensibility Findings — Showcase 房间体系的架构事实

本文档记录 Showcase 房间体系（`rooms/showcase/`，35 个房间）开发过程中核实过的架构事实、修复的缺陷与遗留的扩展点。所有断言附 `文件:行号` 证据；测试文件（`tests/showcase_*.gd`）由并行开发维护、行号会漂移，因此只引用文件与函数名；脚本与 defs 的行号以当前工作区为准。不确定之处标注"待验证"。

## 1. 本轮创建统计

- **35 个房间**落地于 `rooms/showcase/`：27 个内容房间（`tools/showcase_room_defs.gd:30-640` 的 `ROOMS`）+ showcase_hub + 7 个分类 index（`tools/showcase_room_defs.gd:646-823` 的 `NAV_ROOMS`），由 `tools/generate_showcase_rooms.gd` 生成。
- **核心代码只改了一处文件（`objects/elevator.gd`），共三处改动**：`_ready` 移除 `process_mode = Node.PROCESS_MODE_ALWAYS`（现为 `objects/elevator.gd:31-32` 的注释，见 3a）；`_body_intersects_added_strip` 生长阻挡近端判据改为接触前 0.05px 夹停（新常数 `GROWTH_CLEARANCE`，见 3g）；`_growth_blocked` 新增电梯互撞循环（见 3h）。其余全部通过**场景组合 + Inspector 配置**完成——每个房间是 `rooms/room.gd` 基类 + `objects/*.tscn` 实例的纯组合，没有任何 room-specific 脚本或节点。
- **生成器/defs 是新工具，不是运行时框架**：`tools/generate_showcase_rooms.gd` 是离线 SceneTree 脚本（`--script` 运行），"owns no gameplay logic"（`tools/generate_showcase_rooms.gd:10-11`），产物是普通 `.tscn` 文本；`tools/showcase_room_defs.gd` 是纯数据（ASCII 地图 + 实体清单）。运行时没有新增任何脚本、组名、Autoload 或组件——游戏在不知道 showcase 存在的情况下加载这些房间。
- 生成器输出确定性已验证：同一 defs 重跑，31/35 个 `.tscn` 逐字节一致；其余 4 个（`elv_horizontal`、`mlt_elevator_relay`、`trt_elevator`、`chl_vertical_climb`）是磁盘产物落后于刚修改的 defs，重跑后同步——不是非确定性。

## 2. 架构优点（每条附证据）

**a) 门、告示牌、前景文字全部可组合复用。**
- 门只靠一个导出属性工作：`@export_file("*.tscn") var next_room`，留空即禁用（`objects/door.gd:5,19`）。生成器为每个房间按坐标发射 Door 实例并写 `next_room`（`tools/generate_showcase_rooms.gd:272-278`），35 个房间的 67 扇门（nav 40 + 内容房 27）零特殊代码。
- 告示牌全靠导出（`objects/signboard.gd:4-14`）：内容房的提示牌（`tools/generate_showcase_rooms.gd:306-310`）与导航房"每扇门上方一块标签牌"（同文件 `:312-321`，放在 `cell.y*16-24`）是同一组件的两种用法。
- 前景文字（EntryText）同理（`objects/screen_text.gd:7-49`，发射于 `tools/generate_showcase_rooms.gd:323-327`）。hub 的整面导航墙 = 7 扇门 + 7 块标签牌，没有一行新代码。

**b) Elevator 的 set_button_source / signal 双向接线，且一钮可驱多梯。**
- 按钮侧接线：`objects/button.gd:22-27`（`_ready` 读 `target_elevator`，调 `elevator.set_button_source(self)`）。
- 电梯侧接线：`objects/elevator.gd:46-49`（`_ready` 读 `button_path`，调 `set_button_source`）。
- 信号契约：`activation_changed` 连接/换源时断开旧连接，一个电梯同一时刻只有一个按钮源、后连者替换（`objects/elevator.gd:74-88`）。
- 一钮多梯：`trt_elevator` 的 BtnA 同时驱动 LiftA 与 LiftB（`tools/showcase_room_defs.gd:537-539`）；LiftA 走按钮侧接线（生成器发 `target_elevator`，`tools/generate_showcase_rooms.gd:288`），LiftB 走电梯侧接线（生成器发 `button_path`，同文件 `:301-302`）——两条接线方向在同一个房间里各验证一次。

**c) Block 与 TileMap 物理等价，使程序化地形可行。**
- Block 是 16×15.98 的 StaticBody2D（`objects/block.tscn` 的 RectangleShape2D，上下各 0.01px 内缩），与 `objects/blocks.tscn` 的 TileMap 碰撞等价（README"地形使用 block.tscn 实例拼成"一节）。
- 生成器据此把 ASCII 地图逐格发射成 Block 实例（`tools/generate_showcase_rooms.gd:259-264`），不需要 TileMap 授权；等价性使"行 y 的砖块顶面 = y*16+0.01"成为全项目统一常数（`tests/showcase_test_foundation.gd` 头注），电梯的 0.02px 沿轴内缩正是为了与这个面齐平（`objects/elevator.gd:128-132` 注释）。

**d) 组名协议让跨对象系统无需场景树耦合。**
- 注册：`objects/warma.gd:41`（player）、`objects/giraffe.gd:17`（giraffe）、`objects/elevator.gd:30`（elevators）、`objects/button.gd:14`（buttons）、`objects/block.tscn`（block）。
- 消费：按钮扫 player/giraffe 组判定压下（`objects/button.gd:32-33`）；电梯扫 player/giraffe 组做载物/阻挡（`objects/elevator.gd:277-283`）；Warma 扫 elevators 组获取移动支撑契约（`objects/warma.gd:273-275`）、扫 giraffe 组识别头顶支撑（`objects/warma.gd:248`）；长颈鹿扫 elevators 组吸附、扫 giraffe 组找骑乘者（`objects/giraffe.gd:33-35,76`）；告示牌扫 player 组（`objects/signboard.gd:39`）。
- 效果：按钮→电梯、电梯→骑乘者、音符→长颈鹿这些跨对象系统只依赖"场景里有这些实例"，不依赖父节点或路径——任何房间实例化这些场景即获得全部行为，这正是 35 个房间零代码成立的原因。

- **取舍记录**：生成的 `.tscn` 头部不带 uid（`[gd_scene format=3]`），保证"defs → 生成器 → tscn"逐字节确定（red-team 实测两次生成 md5 全同、仓库产物 35/35 同步）。代价：经编辑器重存会引入 uid diff 并脱离生成器——约定"showcase 房间只由生成器再生产出"。

## 3. 发现并修复的缺陷

### 3a. 电梯在死亡动画期间继续漂移

- **现象**：死亡动画期间电梯实测漂移 1.9px（12px/s × 0.16s 实测窗口；死亡闪烁全程约 0.32s，`objects/warma.gd:146-154`）。
- **位置**：`objects/elevator.gd` `_ready` 原有一行 `process_mode = Node.PROCESS_MODE_ALWAYS`。
- **根因**：`room.freeze_for_death()` 用 `PROCESS_MODE_DISABLED` 冻结整棵房间树（`rooms/room.gd:26-29`），而 `PROCESS_MODE_ALWAYS` 对冻结免疫——`_physics_process` 在闪烁期间继续伸缩电梯。
- **修复**：移除该行，保持默认 `PROCESS_MODE_INHERIT`（`objects/elevator.gd:31-32` 注释记录了原因）。
- **回归测试**：`tests/elevator_regression_test.gd` `_death_freeze_stops_lift`（冻结后 30 tick 高度必须不变）；`tests/showcase_contract_test.gd` TEST 8（在 fnd_button 房间里实测死亡冻结，若全房间无法实例化则退化为运行时拼装房间探针）。
- **范围说明**：该回归测试按"测试先行"政策直接放入既有的电梯回归套件 `tests/elevator_regression_test.gd`（其正统归属），因此本次会话对这一个既有跟踪文件有一处新增——这是核心代码唯一改动（elevator.gd）的配套，而非对既有游戏行为的修改；red-team 架构审查（第 2 轮）已确认为最小修复并追认。

### 3b. 生成器 Terrain 节点缺 parent="."——35 个房间全部无法实例化

- **现象**：生成的 35 个 `.tscn` 全部实例化失败。
- **位置**：`tools/generate_showcase_rooms.gd` 的 Terrain 节点发射（现 `:260` 已带 `parent="."`）。
- **根因**：`.tscn` 文本中子节点必须声明 `parent`；缺省的 `[node name="Terrain" type="Node2D"]` 被 `SceneState::instantiate` 拒绝。
- **修复**：生成器补 `parent="."`。
- **回归测试**：`tests/showcase_contract_test.gd` TEST 1（全房间加载覆盖）；`tests/showcase_test_combinations.gd` `_load_room` 至今保留对该缺陷的专门守卫（检测到无 parent 的 Terrain 会给出指向生成器行的失败信息）。
- **教训**：生成器本身也是资产，需要**立即的加载测试**——"文件写出成功"不等于"可实例化"。

### 3c. 多门房间的每扇门都叫 "Door"——hub 6/7 扇门失效

- **现象**：showcase_hub 的 7 扇门只有最后一扇响应 `W`。
- **位置**：`tools/generate_showcase_rooms.gd` 门节点命名（现 `:273-276` 发射 `Door1..DoorN`）。
- **根因**：同一场景内多个同名 Area2D，Godot 场景注册只保留最后一个同名节点，其余静默丢弃。
- **修复**：按计数器唯一命名 Door1..DoorN（生成器内注释记录了原因）。
- **回归测试**：`tests/showcase_contract_test.gd` TEST 2（从 hub 遍历所有门的 `next_room` 可达性）+ TEST 3（真实 W 键转换环）。

### 3d. 房间设计几何缺陷（三轮，均为"设计意图/实测/修正"）

**3d-1. fnd_giraffe_bump：长颈鹿放在基座砖上**
- 设计意图：长颈鹿立在基座砖上，玩家从下方顶起它。
- 实测：顶起冲量只在起跳帧发射——`_lift_giraffes_above` 的 HeadProbe 扫描长度 = 起跳帧实际位移 + ~0.07px（满跳首帧 ≈1.32px，`objects/warma.gd:284`）；16px 基座砖挡在 Warma 头部与长颈鹿之间，头部扫描永远够不着长颈鹿。
- 修正：长颈鹿静置玩家头顶（`tools/showcase_room_defs.gd:216-218`，player (8,7) 与 giraffe (8,6) 同列相邻）。
- 回归测试：`tests/showcase_test_giraffe_elevator.gd` fnd_giraffe_bump 段。

**3d-2. trt_giraffe：shelf 顶长颈鹿**
- 设计意图：高台顶上的长颈鹿参与互动。
- 实测：其底面高出 Warma 头顶 32px；空中头碰只把竖直速度清零（`objects/warma.gd:114-121` 的竖直碰撞分支），而冲量唯一入口 `apply_external_impulse` 只被 `_lift_giraffes_above` 在起跳帧调用——够不着就不互动，该实体成了死装饰。
- 修正：改为台阶长颈鹿——Giraffe2 叠在 Giraffe1 上、Giraffe3 放基座砖 (11,7) 上（`tools/showcase_room_defs.gd:566-569`），头部高度全部落入可接触范围。
- 回归测试：`tests/showcase_test_torture.gd` `_torture_giraffe` a-d（含"跳离台阶鹿不得顶起它"）。

**3d-3. chl_vertical_climb：坑后 Lift2 顶 48px 不可达**
- 设计意图：深坑后用 Lift2+Giraffe2 继续垂直攀爬。
- 实测：Lift2 顶高出对岸地面 48px，而全跳上升 38.1px（第 60 tick 到顶、滞空 120 tick、漂移 ~60px，`tests/showcase_test_multi_challenge.gd` 头注；不同起跳姿势的实测漂移区间 ~60-76px，待验证）；且长颈鹿占满 Lift2 的 8px 支撑跨度，落点窗口是亚像素缝隙——路线不可达。
- 修正：重构为双阶梯柱路线——柱 A（col 7 rows 6-7，顶 96.01）接住坑跳的下降沿（x≈122），柱 B（cols 9-11 rows 5-6，顶 80.01，与塔面齐平）接住 A 跳的下降沿（x≈162），再贴塔面满跳 32px 上塔（`tools/showcase_room_defs.gd:618-638` 现行地图）。
- 回归测试：`tests/showcase_test_multi_challenge.gd` `_test_chl_vertical_climb` 逐跳脚本化（坑→A→B→塔）。

### 3e. 0.01px 台阶的方向性——水平电梯支撑面的锚定规则

- **现象**：从砖顶走向水平电梯时在桥面悬边处停死（实测记录：`tests/showcase_test_multi_challenge.gd` 头注"an earlier 80.00 anchoring formed a 0.01 px lip that stopped walking Warma dead at the bridge face"）。
- **位置**：水平电梯支撑面 = `pos.y - 4`，横截面无内缩（`objects/elevator.gd:285-293`）；砖块碰撞顶面 = `y*16+0.01`（`objects/block.tscn` 15.98 高）。
- **根因**：两个表面锚定差 0.01px 时，较高一面的边沿构成 0.01px 悬边。Warma 的轴向移动不做台阶攀爬，而 `_has_ground_support` 的 GroundProbe（地形）分支先返回 true（`objects/warma.gd:260-276`），电梯的 `snap_body_to_support` 吸附契约——本可把脚拉齐、消除重叠——永远轮不到执行。
- **修复**：水平电梯支撑面一律锚定到与相邻砖块碰撞面齐平：`pos.y = y*16 + 4.01`（支撑面 = `y*16+0.01`）。0.00px 台阶双向可走；经验规则是 **0.01px 以下的台阶双向可走，0.01px 及以上的台阶单向挡死**。落地位置：`tools/showcase_room_defs.gd:285-286`（elv_horizontal）、`:512`（mlt_elevator_relay）、`:543-544`（trt_elevator LiftD/LiftE）。
- **回归测试**：`tests/showcase_test_multi_challenge.gd` `_test_mlt_elevator_relay` 缝隙探针（从砖塔不跳走过缝上桥）；`tests/showcase_test_torture.gd` `_torture_elevator` e 段（LiftD|LiftE|右基柱空中走廊全程着地步行）。

### 3f. trt_precision 的墙缝格被地图行笔误填死

- **现象**："跳入墙缝"物理测试立即失败——16px 的缝里有一块砖。
- **位置**：`tools/showcase_room_defs.gd` trt_precision 地图行，(6,5) 格。
- **根因**：生成器校验只查"button 必须嵌在 '#' 格"（`tools/generate_showcase_rooms.gd:142-146`）与边界/重叠，**不查"预期的空槽"**——地图行的笔误静默通过生成。
- **修复**：地图行改正（现行 defs 该格为空）。
- **回归测试**：`tests/showcase_test_torture.gd` `_torture_precision` a 段（跳入墙缝并穿出）+ `_slot_blocker_evidence`（若回归，失败信息会直接指出"哪个 Block 填在墙缝格 (104,88)"）。
- **教训**：地图笔误靠物理测试兜底；生成器校验适合补"预期空槽"白名单（见第 6 节建议 5）。

### 3g. 下行杆把站着的沃玛压进地面——生长阻挡误用支撑容差

- **现象**：elv_down 房间，杆向下生长碰到站在按钮上的沃玛后停住，但杆端停在头顶以内 ~0.7px：沃玛每帧被物理去穿透往地面里磨（帧内压入、净位置几乎不变），视觉上持续被压进地面。用户实测报告。
- **位置**：`objects/elevator.gd` `_body_intersects_added_strip` 近端判据原为 `projected_axis.x < new_axis - SUPPORT_TOLERANCE`。
- **根因**：`SUPPORT_TOLERANCE`(0.75px) 是"支撑吸附"契约，被当作生长阻挡的穿透容差复用——杆端越过身体近端 0.75px 才夹停。上行电梯在同等接触前就把 0.75px 内的身体抓走（`_carries_stack` 支撑契约），无此问题；下行/横向电梯无法搬运障碍，这个永久重叠只能靠物理去穿透消化，把站立的身体磨进脚下的地面。**为什么既有测试没发现**：`showcase_test_giraffe_elevator.gd` elv_down 段把该容差抄进了断言（"h ≤ 64.76"、"end ≤ 头顶 +0.76"），而沃玛位置断言的 ±0.1 容差大于帧内压入的净位移——测试把 bug 编码成了规格。
- **修复**：近端判据改为提前夹停 `projected_axis.x < new_axis + GROWTH_CLEARANCE`（新常数 0.05px）：杆端在接触前 ≥0.05px 处冻结（按帧步进量化，间隙 ∈ (0.05, 0.05+step]），任何方向都不再与无法搬运的身体重叠。上行电梯的载物路径不变——被载者落入条带的分支仍走既有 exception（支撑于旧端点且未起跳）。
- **回归测试**：`tests/elevator_regression_test.gd` `_growth_freezes_clear_of_grounded_bodies`（下行/左/右三方向：杆矩形与身体矩形不得相交、身体不得被推移；上行方向靠支撑契约抓取、无重叠路径，由 `_rise_blocked` 覆盖其天花板场景）；`tests/showcase_test_giraffe_elevator.gd` elv_down 段改为几何不变量（杆端 ≤ 头顶 −0.04px，严于旧断言 +0.76px）。
- **教训**：容差常量跨语义复用前要过一遍每个使用点的方向性——"吸附容差"用在阻挡判据上就从保护变成了伤害；断言应写几何/物理不变量，不要把实现容差抄进期望值。

### 3h. 行为契约扩展：电梯互为实体（用户需求，非缺陷）

- **需求**：相向生长的电梯撞上后同时夹停，但各自保留按钮目标的运动趋势；一方缩回让出条带后，另一方按原方向恢复运动。左右方向同理。**电梯仍不与 Blocks/tiles 碰撞**（伸缩杆穿透地形的设计不变）。
- **位置**：`objects/elevator.gd` `_growth_blocked` 新增第二个障碍循环——遍历 `elevators` 组（排除自身），用 `_body_bounds` 取对方杆的碰撞矩形，套用与 actor 相同的 `_body_intersects_added_strip` 判据（近端 `GROWTH_CLEARANCE` 提前夹停）。
- **为什么零成本获得"夹停后自动恢复"**：电梯的运动模型本来就是逐帧"读按钮目标 → 未被阻挡则向目标步进"——阻挡只是跳过本帧步进，从不注销目标。因此夹停是纯粹的帧间状态，对方缩回、条带重新打开的下一帧，运动自动恢复。双向夹停也无需配对逻辑：两根杆各自独立做同一判断，逐帧收敛为"两杆末端间隙 ≥GROWTH_CLEARANCE"的稳定卡停（按帧步进量化，间隙 ≤ 0.05+双方步长）。
- **正交性**：静态杆（`starts_extended` 或已到目标的桥）同样实心——生长杆停在桥面下方间隙处，与"杆穿砖"形成对照；下行杆遇到"上行杆+骑乘者"时，骑乘者由既有 actor 规则先挡住（头顶优先于杆尖），电梯规则只补"无 actor 时杆与杆不相穿"。相邻齐平（共线、截面恰好相切）的两杆不互相阻挡——截面判据用严格不等式，与砖缝拼接一致。
- **回归测试**：`tests/elevator_regression_test.gd` `_lifts_jam_and_resume_vertically`（上下对撞：双向夹停、间隙 ≥0.05、各自伸满受阻 <59；释放下行杆→上行杆伸满；再压下行杆→停在已伸满杆尖上方；释放上行杆→下行杆伸满）、`_lifts_jam_and_resume_horizontally`（左右对撞同理）、`_static_lift_is_solid_to_growing_lifts`（静态横杆挡住上行杆，且上行杆仍可穿过 Block 到位前的同一走廊）。
- **备注**：这是第二次核心代码改动（仍仅 `objects/elevator.gd`），由用户明确需求驱动；"核心代码只改了两处"的统计相应更新（3a 死亡冻结 + 3g 下压修复 + 本条为契约扩展，非缺陷修复）。

## 4. 新发现的耦合（未修复，留作扩展点）

**骑乘者跨站两根相邻同步电梯时，同步回缩被卡死。**
- 现象（trt_elevator 实测）：骑乘者身体（43.5..48.5）同时落在 LiftA（36..44）与 LiftB（48..56）的支撑范围内时，两杆同步回缩的 20 tick 探针零行程——`tests/showcase_test_torture.gd` `_evaluate_seam_ride` 的 "JAMMED" 诊断分支专门记录该状态；**生长方向不受影响**（grow 探针带 `require_motion=true` 通过）。
- 位置/根因：`objects/elevator.gd:250-275` `_can_push_supported_bodies` 为骑乘者加的碰撞例外只覆盖"本杆 + 同栈身体"，**另一根杆仍是阻挡物**——先处理的一杆试图把骑乘者下压 0.1px 时 `test_move` 撞上另一根（本帧尚未移动的）杆顶，拒绝移动；另一杆同理，互锁冻结，直到骑乘者走下接缝。
- 掩蔽效应：生长方向的双重推送（两杆各推一次骑乘者）被 Warma 逐帧 `snap_body_to_support` 吸附契约掩蔽——实测骑乘者/平面位移比 1.045（≈1.0 + 采样残差，而非朴素的 2.0；`tests/showcase_test_torture.gd` `_evaluate_seam_ride` 的 ratio 输出）。
- 评估：修复需要 elevator-elevator 推送协调（例如相邻杆互加碰撞例外，或共享支撑平面仲裁）——这是真实扩展点，不是 bug 修复。**当前不建议立即修的理由**：(1) 只有 torture 场景能构造触发条件（相邻同钮电梯 + 跨缝骑乘者），正式内容未出现；(2) 失败模式是安全的行程冻结（无穿模、无弹射），玩家走下接缝即恢复；(3) 修复会触碰 `_can_push_supported_bodies` 的例外语义，波及全部电梯回归测试。

## 5. 被拒绝的抽象

本轮**没有**为 showcase 添加任何运行时组件：没有 RoomTeleport（导航用普通 Door + `next_room` 组合：hub 7 扇门、每个 index 一排内容门 + 一扇返回门）、没有 AutoElevator（静态平台用 `starts_extended` + `min=max` 表达：elv_up 的 Lift2、mlt_stack_freight 的 Lift1、chl_vertical_climb 的 Lift1）、没有按钮 Latch/锁存组件、没有新组名或 Autoload。

瞬时按钮的"锁存"需求用**长颈鹿压钮**的组合解决，三处真实使用：
- `cmb_giraffe_elevator`：长颈鹿 (5,7) 正压 Btn1 (5,8)（`tools/showcase_room_defs.gd:308-309`）；
- `cmb_elevator_door`：音符把长颈鹿 (4,7) 赶往 Btn1 (8,8)（`tools/showcase_room_defs.gd:356-357`）；
- `mlt_elevator_relay`：长颈鹿 (10,4) 正压嵌砖的 Btn1 (10,5)（`tools/showcase_room_defs.gd:513-514`）。

**为什么组合已足够**：按钮激活 = 身体矩形与压区重叠（`objects/button.gd:29-45`），而长颈鹿是会被物理留在原地的实体（普通接触不传递水平速度，`objects/giraffe.gd:100-103`）——"锁存"因此不需要任何新状态，R 重置、死亡冻结、可达性等既有契约自动适用。三个房间、每房零行 room-specific 代码，是"组合 sufficient"的实证。新增一个 Latch 组件反而会引入第三种激活语义（按钮、电梯按钮源、锁存）需要互相对账。

## 6. 未来建议（按价值排序，均注明前提）

1. **Button latch/toggle 模式**（button.gd 加激活模式导出）。前提：出现"无人值守锁存"且没有长颈鹿可用的正式关卡设计——当前三处锁存全是长颈鹿压钮（第 5 节），需求尚属假设。价值：解除"锁存 = 养一只鹿"的设计约束。风险：这是第一个进入 button.gd 的运行时状态机，需要补激活语义回归。
2. **Elevator-elevator 推送协调**。前提：正式关卡出现可跨越接缝的相邻电梯（现阶段只有 trt_elevator 这一 torture 场景，见第 4 节）。方案方向：`_can_push_supported_bodies` 对相邻杆互加例外，或共享支撑平面仲裁。价值：解除接缝骑乘回缩冻结。风险：触碰全部电梯回归的例外语义。
3. **长颈鹿 despawn 线**（fall_limit 等价物）。前提：正式关卡出现"长颈鹿永久丢失且无法靠 R 恢复"的软锁（例如没有 R 的房间，或鹿掉进不参与重置的区域）。注意：`cmb_reset_giraffe` 当前**利用**"掉出世界不回收"这一行为（giraffe 无 fall_limit，对比 `objects/warma.gd:23,125`；房间见 `tools/showcase_room_defs.gd:404-424`），实现 despawn 时必须同步改写该房间的预期与测试。价值：防软锁。风险：改变既有房间语义。
4. **Door label 属性 vs Signboard 组合**。现状：导航房的门标签由生成器在门上方发射 Signboard（`tools/generate_showcase_rooms.gd:312-321`），手写房间需手动实例化两节点。前提：showcase 之外开始手工批量布门。若成真，可给 `objects/door.gd` 加 `@export label` 并在门内组合一块 Signboard；否则维持组合。价值：省一个节点与一步手工。风险：低——纯便利，组合路径永远保留。
5. **测试 helper 公共基类**。现状：六个 showcase 套件各自携带近似 helper（foundation 与 giraffe_elevator 有约 38 行逐字相同）。前提：第七个套件出现或现有套件需要统一行为（如统一 GUARD_MS/超时语义）。方案：`tests/showcase_test_base.gd`（RefCounted 工具类或 SceneTree 基类）。价值：断言语义一处修改全局生效。风险：低——纯测试侧重构，套件全部有行为断言保护。
6. **生成器"预期空槽"校验**。前提：地图行笔误再次发生（trt_precision 的 3f 是首例，物理测试兜底有效但滞后）。方案：defs 支持每房 `assert_empty` 格清单或新字形，生成期报错。价值：把兜底从"跑测试才发现"提前到"生成即失败"。风险：无运行时影响，纯工具改进。
