# 游戏背景音乐

原始素材：`title_2_warm_flute_piano.mp3`（保留原文件）。

游戏使用 `title_2_warma_flute_loop.ogg`：删除 60.303 秒之后约 2.697 秒的无声尾部，并把末尾与开头重叠 0.5 秒交叉淡化。文件从原曲 0.5 秒处开始，循环时接缝连续，没有额外的空白等待。

打开 `res://objects/background_music.tscn`，选择根节点 `BackgroundMusic`，在 Inspector 中调整 `Music Volume`（0 为静音，1 为原音量，默认 0.5）。运行时也可在 Remote 场景树中选中 `/root/BackgroundMusic` 实时调整。

这个场景注册为 Autoload，启动游戏时播放一次；换关、死亡重置、返回标题或进入结尾都继续播放同一个音乐实例。Ogg 导入设置启用了循环。
