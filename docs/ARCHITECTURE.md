# 架构

## 组件职责

### RightClickFinderExtension

- 向 Finder 提供项目菜单与文件夹背景菜单
- 只在 `menu(for:)` 和菜单回调期间读取 `selectedItemURLs` / `targetedURL`
- 直接完成剪贴板和文件创建等短操作
- 将打开应用、终端自动化等操作写入 App Group 请求队列
- 通过 `rightclick://perform?id=...` 唤起宿主 App

### RightClick

- 提供启用指引、终端选择和错误状态
- 消费请求队列
- 使用 `NSWorkspace` 打开 VS Code / Codex
- 使用 `osascript` 控制用户选择的终端

### RightClickCore

- 不依赖 AppKit，可被宿主 App、扩展和测试复用
- 定义动作、文件模板、选区语义、共享设置和请求协议
- 集中处理文件名冲突和 shell 参数转义

## 安全边界

- 不把完整 shell 命令塞进 URL；URL 只携带随机请求 ID
- 路径通过 JSON 编码写入 App Group
- 文件创建使用 `.withoutOverwriting`，自动生成 `Untitled 2.ext`
- shell 工作目录使用单引号转义
- 扩展进程不等待终端或编辑器

## 已知系统约束

- Finder Sync 只在 `directoryURLs` 覆盖的目录显示项目菜单
- 当前默认监控 `/`，面向直接分发；之后应允许用户缩小范围
- Finder 扩展必须在系统设置中由用户显式启用
- Terminal / iTerm2 自动化首次使用会触发 macOS 权限提示
- App Group 和 Bundle ID 必须替换为开发者团队实际拥有的值
