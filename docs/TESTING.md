# 发布验证清单

单元测试和签名验证不能替代 Finder 扩展的真实系统测试。每个正式版本发布前，
至少在一台没有安装过 RightClick 的 Mac 上完成以下检查。

## 自动验证

```sh
xcodebuild -project RightClick.xcodeproj \
  -scheme RightClick \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test

VERSION=0.6.0 ./scripts/build-release.sh
```

第二条命令会验证 App、Finder 扩展、通用架构、Ad-hoc 签名与 DMG 内容。

`RightClickAppTests` 是无宿主逻辑测试：被测文件直接编入测试包，不启动
`LSUIElement` App，也不依赖已安装的同 Bundle ID 副本或 Sparkle。装有
`/Applications/RightClick.app` 时应同样能在数秒内跑完两个测试 bundle。

## 干净机器

- 从 GitHub Release 下载 DMG，而不是使用本地构建产物
- 验证 SHA-256 文件
- 将 RightClick 拖入 Applications
- 确认 Finder、Dock 和系统设置中显示正式 App 图标
- 确认 Gatekeeper 首次阻止时，可以通过“隐私与安全性 → 仍要打开”放行
- 在 App 中打开扩展设置并启用 RightClick Finder Extension
- 在桌面文件、桌面空白处、Finder 文件、窗口空白处、侧边栏，以及一个
  含空格/中文/单引号的目录中检查右键菜单
- 保持 Finder 窗口中另一个文件处于选中状态，再右键窗口空白处和侧边栏目录，
  确认复制、打开、新建及终端动作都作用于右键目录而不是残留选区
- 测试复制路径、复制文件名和多选
- 逐一创建七种文件，确认同名文件不会覆盖
- 测试 VS Code / Codex App 存在与缺失两种状态
- 测试 Codex CLI / Claude Code 存在与缺失两种状态
- 测试 Terminal 与 iTerm2，并检查首次自动化权限提示
- 触发 CLI 动作，确认终端在正确目录启动，RightClick 不切到前台、不增加窗口，
  界面也不会短暂闪现
- 快速触发两个 CLI 动作，确认两个终端请求都执行且始终没有 RightClick 窗口
- 关闭 RightClick 的最后一个窗口但不退出进程，再双击 App，确认会新建并显示窗口
- 将 RightClick 窗口最小化或隐藏后再双击 App，确认只恢复原窗口而不重复创建
- 从浏览器打开格式合法但没有本机令牌的
  `rightclick://run?tool=codex&cwd=/tmp`，确认不开终端且不显示 RightClick 窗口
- 从浏览器打开无令牌的 `rightclick://error?message=...`，确认不显示通知、不写入
  错误历史，也不显示 RightClick 窗口
- 从浏览器分别打开令牌错误的 run、terminal、open、error 和未知
  `rightclick://` 链接，确认不会执行动作或显示通知
- v0.6.x 过渡期：安装旧版并先触发一次 terminal/open 动作，再升级但不重启
  Finder；确认旧扩展的无令牌请求仍可用，主窗口出现橙色“重启 Finder”提示。
  该无令牌兼容分支计划在 v0.7.0 移除
- 卸载 VS Code 后触发“用 VS Code 打开”，确认收到本地通知、错误进入最近 10 条
  历史，并且 RightClick 不抢焦点；拒绝通知权限时仍应保留错误历史
- 右键 `/Applications` 中的 App 新建 TXT，确认目标是 App 的父目录（或收到权限
  错误），绝不能写入 `.app` 包内部
- 右键 `.xcodeproj` 后“在终端中打开”，确认终端目录是工程包的父目录
- 升级旧版本，确认 Applications 中只留下一个 RightClick.app
- 保持 Finder 运行并升级旧版本；启动新 App 后确认 Finder 自动退出并重新打开，
  且右键菜单加载的是新扩展
- 运行 `pluginkit -m -A -D -v -i com.hheelo.RightClick.FinderExtension`，
  确认只列出 Applications 中的一份扩展

## 存储位置

- Apple Silicon：至少一台当前正式版 macOS
- Intel：至少一台仍受支持的 macOS
- 可选：外置磁盘、网络卷和 iCloud Drive

把验证日期、macOS 版本、CPU 架构以及失败项记录在对应 GitHub Release 或 Issue
中。Intel 与外部卷未验证时，不应在 Release Notes 中声明已全面支持。
