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

VERSION=0.2.2 ./scripts/build-release.sh
```

第二条命令会验证 App、Finder 扩展、通用架构、Ad-hoc 签名与 DMG 内容。

## 干净机器

- 从 GitHub Release 下载 DMG，而不是使用本地构建产物
- 验证 SHA-256 文件
- 将 RightClick 拖入 Applications
- 确认 Finder、Dock 和系统设置中显示正式 App 图标
- 确认 Gatekeeper 首次阻止时，可以通过“隐私与安全性 → 仍要打开”放行
- 在 App 中打开扩展设置并启用 RightClick Finder Extension
- 在桌面、用户目录和一个含空格/中文/单引号的目录中检查右键菜单
- 测试复制路径、复制文件名和多选
- 逐一创建七种文件，确认同名文件不会覆盖
- 测试 VS Code / Codex App 存在与缺失两种状态
- 测试 Codex CLI / Claude Code 存在与缺失两种状态
- 测试 Terminal 与 iTerm2，并检查首次自动化权限提示
- 关闭“运行 CLI 前切到前台确认”，确认 Finder 启动 CLI 时 RightClick 不抢前台
- 从浏览器手动打开无效 `rightclick://` 链接，确认不会启动 CLI
- 升级旧版本，确认 Applications 中只留下一个 RightClick.app
- 升级后重启 Finder，确认加载的是新扩展
- 运行 `pluginkit -m -A -D -v -i com.hheelo.RightClick.FinderExtension`，
  确认只列出 Applications 中的一份扩展

## 存储位置

- Apple Silicon：至少一台当前正式版 macOS
- Intel：至少一台仍受支持的 macOS
- 可选：外置磁盘、网络卷和 iCloud Drive

把验证日期、macOS 版本、CPU 架构以及失败项记录在对应 GitHub Release 或 Issue
中。Intel 与外部卷未验证时，不应在 Release Notes 中声明已全面支持。
