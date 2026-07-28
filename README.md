# RightClick

RightClick 是一个原生 macOS Finder 扩展，为右键菜单补充开发者常用操作：

- 复制所选文件的路径或文件名（支持多选）
- 用 Visual Studio Code 或 Codex 打开
- 在 Terminal / iTerm2 中运行 Codex CLI 或 Claude Code
- 新建 TXT、Markdown、Python、Shell、HTML、JSON、CSV 文件

## 工程结构

```text
RightClick.app
├── SwiftUI 设置、扩展状态与启用入口
├── ActionExecutor（启动终端命令）
└── RightClickFinderExtension.appex
    └── Finder 菜单、复制、新建文件、打开编辑器

RightClickCore.framework
└── 动作模型、选区规则、文件模板、CLI 链接与设置
```

Finder 扩展直接完成复制、新建文件以及打开编辑器。运行 CLI 时，扩展通过只包含
工具名称与工作目录的 `rightclick://run` 链接唤起宿主 App。项目不依赖 App
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

### 一键本地安装

已安装 Xcode 的开发者可以运行：

```sh
git clone https://github.com/hheelo/finder_menu_extern.git
cd finder_menu_extern
./scripts/install.sh
```

脚本会构建通用 App、进行 Ad-hoc 签名、备份已有版本、安装到
`~/Applications`，注册 Finder 扩展并启动 RightClick。

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

本地生成 DMG：

```sh
VERSION=0.1.0 ./scripts/build-release.sh
```

产物位于 `.build/release/output`，包含 DMG 和 SHA-256 校验文件。

## 发布

推送 `v` 开头的 Tag 会触发 GitHub Actions，自动构建 Ad-hoc 签名的通用
DMG、生成校验文件并创建 GitHub Release：

```sh
git tag v0.1.0
git push origin v0.1.0
```

没有 Developer ID 时，macOS 会要求用户首次手动允许打开。Homebrew 或安装脚本
不能安全消除此限制。本项目不会自动移除 quarantine 属性。

更多设计与里程碑见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 和
[docs/ROADMAP.md](docs/ROADMAP.md)。
