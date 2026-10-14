# I warma perform music — Demo v0.2

这是 Warma 平台游戏的一次物理重构。工程使用 Godot 4.7，以集中式轴对齐矩形（AABB）求解器处理实体运动与碰撞，保持角色的实际碰撞尺寸。关卡场景负责配置，世界脚本统一推进物理和玩法，节点负责显示。

本仓库是 **Demo v0.2** 的 Godot 源码工程，包含 16 个主线房间和一个独立演示房间 `level_X`。

## 快速运行

1. 安装 Godot 4.7（标准版，无需 .NET），导入本目录的 `project.godot`。
2. 等待首次资源导入完成，按 **F5** 运行。
3. 开场按任意键进入第一房间；打开单个房间按 **F6** 可独立试玩。

Windows 发布版解压后双击 `Warma-Demo-v0.2.exe` 即可运行，无需安装 Godot。源码工程请先在编辑器完成导入，再按 F5。逻辑画面 256×144，默认窗口 1024×576，物理更新 120 Hz。

## 操作

| 按键 | 功能 |
| --- | --- |
| A / D | 左右移动 |
| J | 跳跃；长按时一旦可以起跳就自动连续跳跃，松开可缩短跳跃 |
| K | 获得灭火器后，每次点按发射一个音符，无攻击冷却；长按不连发 |
| ← / → | 游戏时间减速 / 加速一档：x0.1、x0.2、x0.5、x1；到达极限后无效 |
| W | Warma 与门的范围重叠时，进入门指定的房间 |
| N | 立即获得灭火器 |
| M | 使用当前房间场景树中的第一扇门，无需靠近 |
| R | 重载当前房间，回到该房间最初设置的出生点，保留已获得的灭火器（F5 / F6 一致） |
| P | F5 暂停 / 继续 |
| F1 | F5 显示 / 隐藏实体碰撞边界 |

门使用 `door.png`，层级在背景与主角之间；在 Inspector 的 **Target Room** 中选择房间或 `end.tscn`。告示牌使用 `signboard.png`；在 **Text** 中填写文字，接触时自动显示无底色的黑字，离开隐藏，新告示牌立即替换旧提示。当前主线连接为开场 → `level_01` → … → `level_16` → 结束；独立演示房间 `level_X` 也连接到结束画面。结束画面按任意键退出。装备随房间切换保留，退出游戏不存档。暂停期间 W/N/M 不执行。

游戏时间默认 x1，左下角仅显示当前倍率，采用告示牌的黑字样式。每次按下方向键只调整一档，长按不重复调档；暂停时也可调整。所选流速在换房间和重开后保留，退出游戏后恢复 x1。所有流速下均可快速点按 K，每次按下立即发射一个音符。

Warma 掉出关卡边界后会闪烁并重载当前房间，回到该关卡最初设置的出生位置，保留已获得的灭火器。灭火器一旦获得，就会在本次游戏中一直持有；退出游戏不存档。

## 音效

已启用轻松愉快的 15 个原创音效，覆盖落地、发射、受击、拾取、换房、重试和界面提示。行走、起跳与告示牌交互保持安静，没有背景音乐。未使用的音频素材已删除。音效保持正常音高，不跟随游戏时间倍率变化。资源、音量调节和重新生成方法见 [音效包说明](Assets/Audio/README.md)。

音频回归可运行 `godot --headless --path . --script res://tests/test_audio.gd`。

## 工程结构

| 路径 | 内容 |
| --- | --- |
| `levels/` | 主线与独立演示房间 |
| `objects/`、`Assets/` | 游戏对象与像素素材 |
| `scripts/`、`physics/` | 玩法、场景管理与矩形物理求解器 |
| `addons/block_painter/` | 关卡方块画笔，支持绘制、擦除与撤销 |
| `tests/` | 回归脚本及测试场景 |
| `show/` | 架构说明与成品视频；不参与游戏运行 |

学习与搭建说明见 [系统概要与学习路径](SYSTEM_GUIDE.md)，详细架构见 [全游戏架构说明](show/全游戏架构说明.md)。

## 导出 Windows 版本

安装 Godot 4.7.2 与匹配的导出模板，通过 **项目 → 导出 → Windows Desktop** 导出发布构建。已提供 x86_64 导出预设，默认输出到 `dist/Warma-Demo-v0.2-Windows-x86_64/Warma-Demo-v0.2.exe`，PCK 嵌入 EXE。测试、文档视频、音效生成工具、编辑器插件和本地中间文件均不进入运行包。

完整发布流程可执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_release.ps1 -GodotPath 'C:\path\to\godot.exe'
```

脚本执行导入、回归、Release 导出、独立启动和导出资源检查，生成带操作说明的 ZIP 及 SHA-256 校验文件，供上传到 Release。发布说明见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。旧版本本地 EXE 收纳在忽略目录 `build/previous/`，发布包以 `dist/` 为准。

源码提交保留 `.gd.uid` 和素材 `.import` 文件，它们记录资源标识与导入设置；`.godot/` 缓存可自动重建。测试截图 `artifacts/`、本地导出 `build/` / `dist/` 与制作中间文件已由 `.gitignore` 排除。

## 回归验证

回归命令（PowerShell）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_physics.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_level_loading.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_gameplay.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_real_input.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_display.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_block_painter.ps1
godot --headless --path . --script res://tests/test_audio.gd
```

这些脚本的默认 Godot 路径是开发机的 Steam 安装目录；其他环境请在命令末尾追加 `-GodotPath 'C:\path\to\godot.exe'`。显示测试需要真实图形设备，并会重新生成 `artifacts/` 截图。各脚本打印场景数、检查数与失败数，以实际运行输出为准。

2026-10-14 发布整理时，使用 Godot 4.7.2 验证：

| 测试 | 结果 |
| --- | --- |
| 物理 | 143119 checks，0 failures |
| 关卡加载 | 2138 checks，0 failures |
| 真实按键 | 932 checks，0 failures |
| 方块画笔 | 62 checks，0 failures |
| 玩法 | 2108 checks，0 failures；包含 16 个房间的门连接与结束流程 |
| 显示 | 283 checks，0 failures |
| 音效 | 110 checks，0 failures；资源与注册表一一对应，无背景音乐自动播放 |
| 结束画面 | 任意键退出，0 failures |
| 导出资源与流程 | 59 checks，0 failures；读取 EXE 内嵌资源，验证废弃资源排除与 16 房间连接 |
| Windows Release | 独立 EXE 启动检查通过 |

全部回归断言已通过。部分测试在退出时仍有 Godot 对象 / 资源清理警告；没有脚本解析或运行错误。房间切换检查不等同于手动完成全部谜题。
