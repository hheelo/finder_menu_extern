# RightClick

RightClick 是一个原生 macOS Finder 扩展，为右键菜单补充开发者常用操作：

- 复制所选文件的路径、文件名、相对路径、file URL、Shell 引用路径或父目录
  （支持多选，分隔符可选换行 / 空格 / 逗号；相对路径以 git 仓库根为基准，
  不在仓库里时以当前 Finder 窗口目录为基准）
- 用 Visual Studio Code、ChatGPT、Cursor、Zed、Sublime Text、Xcode、JetBrains 或系统默认应用打开
- 支持 Terminal、iTerm2、Warp、Ghostty、WezTerm、Kitty；可选新标签页或新窗口
- 运行 Codex CLI / Claude Code，或用 PATH 命令名、绝对路径和逐项参数配置自己的 CLI
- 新建内置模板文件、自定义模板文件、文件夹，或从文本剪贴板新建文件；内置模板可覆盖文件名与编码
- 可启用、禁用和排序菜单项，也可全部收进一个 RightClick 子菜单
- 菜单设置可导入导出；配置损坏时先私密备份并等待用户明确恢复，不会静默覆盖
- 可把 Finder 菜单限制在用户选择的目录及其子目录
- 宿主界面、Finder 菜单、错误通知与系统权限说明支持简体中文和英文
- 支持文件、文件夹、窗口空白处、桌面和 Finder 侧边栏
- Finder 动作全程不显示宿主窗口；AI CLI 请求经本机扩展认证后直接打开终端
- 宿主以附属应用运行，Dock 里不占图标；双击 App 即可打开设置与诊断
- 首次启动用三步向导完成扩展启用、默认终端选择与 Finder 试用引导
- 原生 macOS App 图标与本地环境诊断

## 工程结构

```text
RightClick.app
├── SwiftUI 设置、扩展状态与启用入口
├── ActionExecutor（启动终端命令）
├── RightClickAppLogic.framework（启动、深链与窗口纯逻辑）
└── RightClickFinderExtension.appex
    ├── RightClickFinderAdapter.framework（选区与 AppKit 菜单边界）
    └── Finder 回调、复制、新建文件、打开编辑器

RightClickCore.framework
└── 动作模型、选区规则、文件模板、CLI 链接、设置与共享本地化资源
```

Finder 扩展直接完成复制和文件创建；打开编辑器、终端或运行 CLI 时，通过签名
深链唤起宿主 App。自定义 CLI 深链只包含配置 ID 与工作目录，不包含可执行名或参数。
项目不依赖 App
Group、开发团队或 provisioning profile。

## 安装

### 从 DMG 安装

从 [GitHub Releases](https://github.com/hheelo/finder_menu_extern/releases)
下载最新的 `RightClick-版本号.dmg`，将 App 拖入 Applications。

当前版本使用 Ad-hoc 签名，没有 Developer ID 公证。首次打开时：

1. 尝试打开 RightClick
2. 前往“系统设置 → 隐私与安全性”
3. 点击“仍要打开”
4. 回到 RightClick，点击“启用 Finder 扩展”

### 更新

从 v0.5.0 起，RightClick 内置应用内更新：打开 App 点「检查更新」即可，
不需要再下载 DMG、不需要拖拽、也不会再出现「来源不明」提示——
Sparkle 下载的更新包不带 macOS 隔离属性，Gatekeeper 不会介入。
用户自己打开 App 时会自动后台查一次；被 Finder 菜单唤起时不查，
避免在你操作文件时冒出更新界面。

更新包用 EdDSA 密钥签名校验，与 Ad-hoc 签名并行工作。

### 一键本地安装

已安装 Xcode 的开发者可以运行：

```sh
git clone https://github.com/hheelo/finder_menu_extern.git
cd finder_menu_extern
./scripts/install.sh
```

脚本会构建通用 App、进行 Ad-hoc 签名、备份已有版本、安装到
`~/Applications`，注册 Finder 扩展并启动 RightClick。旧版本会压缩到
`~/Library/Application Support/RightClick/Backups`，不会在 Applications
目录留下同 Bundle ID 的扩展副本。
如果 `/Applications/RightClick.app` 已存在，脚本会在构建前停止并提示继续使用
DMG/Sparkle 更新或先手动移除旧版本，避免系统同时发现两份 Finder 扩展。
构建和 DMG 验证结束后也会注销并清理临时扩展，避免 Finder 同时发现多份
RightClick Finder Extension。

如果升级后 Finder 仍显示旧菜单，可在 RightClick 中点击“重启 Finder”。
从 v0.2.3 开始，RightClick 会在启用扩展后为每个新构建自动重启一次
Finder，避免覆盖升级后继续使用旧扩展会话。

## 安全与诊断

- `rightclick://` 只接受固定动作、白名单应用或本机 `0600` 配置中的 CLI ID
- 工作目录必须是现有的绝对文件夹路径
- Finder 的打开与 CLI 操作都由 RightClick 在后台处理，不显示宿主窗口
- 新版深链使用 HMAC-SHA256 签名，随机密钥不进入 URL；时间戳与 nonce 限制重放
- 路径通过 `osascript` 参数传递，不会插入 AppleScript 源码
- 设置页可管理菜单、终端、自定义 CLI 与模板，可选启用菜单栏入口，并检测 Finder 扩展、编辑器与 CLI
- Terminal 的“新标签页”使用系统快捷键，首次使用需在“隐私与安全性 → 辅助功能”中允许 RightClick；也可改用新窗口
- 主窗口可复制诊断信息，便于提交 Issue
- 设置页可导出最近 200 条本地动作日志和异常终止标记；日志不包含文件路径、
  文件名、命令参数或深链内容

## 开发

1. 安装 XcodeGen：`brew install xcodegen`
2. 运行 `xcodegen generate`
3. 打开 `RightClick.xcodeproj`
4. 运行 `RightClick` scheme
5. 点击 App 内的“启用 Finder 扩展”

命令行验证：

```sh
xcodegen generate
xcodebuild -project RightClick.xcodeproj \
  -scheme RightClick \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

本地生成并验证 Universal 2 DMG：

```sh
VERSION=1.0.1 ./scripts/build-release.sh
```

产物位于 `.build/release/output`，包含 DMG 和 SHA-256 校验文件。
构建脚本会验证签名、Bundle ID、宿主/扩展版本、`arm64`/`x86_64`
架构以及 DMG 挂载内容。

## 发布

每次推送和 Pull Request 都会运行编译与单元测试。推送 `v` 开头的 Tag
会在测试通过后构建并验证 Ad-hoc 签名的通用 DMG、生成校验文件并创建
GitHub Release：

```sh
git tag v0.2.5
git push origin v0.2.5
```

没有 Developer ID 时，macOS 会要求用户首次手动允许打开。Homebrew 或安装脚本
不能安全消除此限制。本项目不会自动移除 quarantine 属性。

更多设计与里程碑见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 和
[docs/ROADMAP.md](docs/ROADMAP.md)。发布前的真实环境验证步骤见
[docs/TESTING.md](docs/TESTING.md)。
