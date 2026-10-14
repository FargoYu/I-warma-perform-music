# Demo v0.2 — Windows x86_64

2026-10-14

- 包含 16 个主线解谜房间，开场、换房、结束流程完整连接。
- 新增 15 个轻松愉快的音效，覆盖落地、音符发射、长颈鹿受击、拾取、换房、重试和界面提示。
- 行走、起跳与告示牌交互保持安静；删除未使用的音效和背景音乐。
- 重开和换房保留已获得的灭火器及当前时间倍率。
- Windows 发布包自带嵌入式游戏资源，无需安装 Godot。

下载 `Warma-Demo-v0.2-Windows-x86_64.zip`，解压后运行 `Warma-Demo-v0.2.exe`。按键说明包含在压缩包的 README.txt 中。

本次为测试 Demo：装备和时间倍率只在本次运行中保留，退出游戏不存档。N、M、F1 测试快捷键保留。

源码构建：安装 Godot 4.7.2 及匹配的 Windows 导出模板，在 PowerShell 执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_release.ps1 -GodotPath 'C:\path\to\godot.exe'
```

脚本依次执行资源导入、回归测试、Release 导出、独立启动检查、导出资源与关卡流程检查，并生成 ZIP 与 SHA-256 校验文件。输出位于 dist，检查日志位于 artifacts/release。详细验证结果见 README 的回归验证部分。
