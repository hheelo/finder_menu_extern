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

VERSION=0.2.5 ./scripts/build-release.sh
```

第二条命令会验证 App、Finder 扩展、通用架构、Ad-hoc 签名与 DMG 内容。

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
- 触发 CLI 动作，确认 RightClick 切到前台并展示包含工作目录的完整命令；取消后
  不应打开终端窗口
- 快速触发两个 CLI 动作，确认两个请求依次出现且不会互相覆盖
- 从浏览器打开格式合法的 `rightclick://run?tool=codex&cwd=/tmp`，确认仍然必须
  显示完整命令并等待用户确认
- 从浏览器分别打开无效的 run、terminal、open 和未知 `rightclick://` 链接，确认
  不会执行动作，并显示与请求类型对应的错误原因
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
