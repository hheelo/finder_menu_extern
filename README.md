# RightClick

RightClick 是一个原生 macOS Finder 扩展，为右键菜单补充开发者常用操作：

- 复制所选文件的路径或文件名（支持多选）
- 用 Visual Studio Code 或 Codex 打开
- 在 Terminal / iTerm2 中运行 Codex CLI 或 Claude Code
- 新建 TXT、Markdown、Python、Shell、HTML、JSON、CSV 文件

## 工程结构

```text
RightClick.app
├── SwiftUI 设置与状态界面
├── ActionExecutor（打开 App、启动终端命令）
└── RightClickFinderExtension.appex
    └── Finder 菜单、复制、新建文件、请求转发

RightClickCore.framework
└── 动作模型、选区规则、文件模板、共享请求与设置
```

Finder 扩展保持轻量：复制和新建文件在扩展进程中完成；打开应用、AppleScript
和 CLI 启动通过 App Group 请求队列交给宿主 App。

## 本地构建

1. 安装 XcodeGen：`brew install xcodegen`
2. 运行 `xcodegen generate`
3. 打开 `RightClick.xcodeproj`
4. 将 `com.example`、`group.com.example.RightClick` 替换为自己的标识
5. 给 App 与 Finder Extension 选择同一个开发团队，并创建同名 App Group
6. 运行 `RightClick` scheme
7. 点击 App 内的“打开扩展设置”，启用 RightClick Finder Extension

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

## 分发策略

首选 Developer ID 直接分发并公证。宿主 App 需要调用本机编辑器、CLI 和终端，
不以 Mac App Store 沙盒版本为第一目标。Finder Sync 最初是为同步软件设计的；
本项目将 `/` 作为监控根目录以提供全局右键菜单，因此上架前需要重新评估审核策略。

更多设计与里程碑见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 和
[docs/ROADMAP.md](docs/ROADMAP.md)。
