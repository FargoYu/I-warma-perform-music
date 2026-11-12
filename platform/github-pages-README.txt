沃要吹灭火器 — GitHub 源码与 Pages 发布

网站访客只需打开网址即可游玩，无需 CMD、Python 或 Godot。
电脑键盘和安卓手机触屏使用同一个网址。源码包里的 docs/index.html 已包含完整网页版。
这也是可以在电脑上直接双击打开的单 HTML：引擎、关卡、音频与图像都已嵌入其中。

一、上传源码

1. 解压 Source 压缩包，找到同时包含 project.godot、README.md、docs/ 和 .github/ 的目录。
2. 将这个目录中的内容作为 GitHub 仓库根目录。不要只上传 ZIP，也不要多套一层文件夹。
3. 建议通过 GitHub Desktop 添加本地仓库、提交并发布到 GitHub；已有仓库则提交并推送。
   Windows EXE、Android APK 和本地工具链不属于仓库源码，请作为 GitHub Release 附件提供。

本次单 HTML 小于 GitHub 网页上传的单文件 25 MiB 上限，也可以直接通过网页上传。
完整源码包含多个目录，使用 GitHub Desktop 更方便保留目录结构和后续更新。
当前源码的单个文件均低于普通 Git 仓库的 100 MiB 上限，不需要 Git LFS。

二、启用 GitHub Pages

1. 在 GitHub 仓库打开 Settings → Pages。
2. 将 Build and deployment → Source 设为 GitHub Actions。
3. 打开 Actions → Deploy Warma to GitHub Pages，点击 Run workflow，使用仓库默认分支。
4. 等流程完成后，在 Pages 设置页或本次部署记录中打开站点地址。

普通项目仓库的网址形式是 https://你的用户名.github.io/仓库名/ 。
游戏资源已嵌入 HTML，因此放在项目仓库子路径下也能加载。
工作流只上传 docs/，不会把 Godot 源码、签名密钥或工具链放到网站上。
无需自行设置 Token 或 Secrets；部署使用 GitHub Actions 提供的仓库令牌和 OIDC。

默认分支为 main 或 master 时，后续提交 docs/ 的更改会自动更新网站。
默认分支使用其他名字时，可手动运行工作流，或修改 .github/workflows/pages.yml 的 branches。
仓库若设有 GitHub Pages 环境审批规则，按仓库既有流程完成审批即可。

三、后续更新

修改 Godot 工程后，重新导出 Web，再使用项目的发布整理工具更新 docs/ 和发布 ZIP。
确认本次生成的 docs/index.html 与随包许可证已更新，再一起提交。
Pages 工作流使用已经准备好的 docs/ 文件，不会在 GitHub 上重新编译 Godot。
Web 发布包和 docs/ 使用同一份单 HTML，同时支持本地打开和静态网站托管。

四、网站所需文件

docs/index.html：完整游戏，包含引擎、游戏数据、浏览器音频组件和图像。
docs/FONT-LICENSE.txt：字体许可证。
随包的 Godot 引擎及第三方许可证也应一同保留。
docs/.nojekyll：静态文件标记。

网站不需要 Start-Web.cmd、serve.py、Android APK 或 Windows EXE。
打开网站使用 https:// 地址；电脑本地可直接双击同一份 index.html。

官方说明：
https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site
https://docs.github.com/en/get-started/start-your-journey/deploying-your-website-automatically
https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github
