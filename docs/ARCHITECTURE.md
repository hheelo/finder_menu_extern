# 架构

## 组件职责

### RightClickFinderExtension

- 向 Finder 提供项目菜单与文件夹背景菜单
- 只在 `menu(for:)` 和菜单回调期间读取 `selectedItemURLs` / `targetedURL`
- 直接完成剪贴板、文件创建以及打开 VS Code / Codex
- 直接用 Terminal / iTerm2 打开所选目录或文件所在目录
- 通过 `rightclick://run?tool=...&cwd=...` 唤起宿主 App 运行 CLI
- 操作不可用时将菜单置灰，失败时显示本地提示

### RightClick

- 提供启用指引、扩展状态、终端选择和错误状态
- 严格解析 CLI 深链接；默认后台执行，可选前台确认启动目录
- 使用 `osascript` 参数控制用户选择的终端，不拼接脚本源码
- 提供本地环境诊断和 Finder 重启入口

### RightClickCore

- 不依赖 AppKit，可被宿主 App、扩展和测试复用
- 定义动作、文件模板、选区语义、CLI 链接和普通 App 设置
- 集中处理文件名冲突、URL 编码和 shell 参数转义

## 安全边界

- 不把完整 shell 命令塞进 URL；URL 只携带固定工具标识与工作目录
- 使用 `URLComponents` 编码路径，宿主只接受唯一的 `tool` / `cwd` 参数
- 工作目录必须是已存在的绝对目录；用户可开启启动前确认
- Finder 使用非激活配置唤起宿主，避免 RightClick 抢占前台
- shell 命令作为 `osascript` 参数传递，不插入 AppleScript 源码
- 文件创建使用 `.withoutOverwriting`，自动生成 `Untitled 2.ext`
- shell 工作目录使用单引号转义
- 宿主在后台等待 `osascript`，扩展进程不等待终端或编辑器
- 不自动移除 macOS quarantine 属性

## 无证书分发

- App 和内嵌扩展使用 Ad-hoc 签名（`Sign to Run Locally`）
- Release 是同时包含 Apple Silicon 和 Intel 的通用二进制
- DMG 同时发布 SHA-256 校验文件
- App Group 已移除，因此不需要开发团队或 provisioning profile
- GitHub Actions 对主分支与 PR 运行测试，在 `v*` Tag 测试通过后创建 Release
- Release 验证宿主/扩展版本、Bundle ID、签名、Universal 2 和 DMG 内容
- 旧 App 压缩到 Application Support，避免同 Bundle ID 扩展并存

## 已知系统约束

- Finder Sync 只在 `directoryURLs` 覆盖的目录显示项目菜单
- 当前默认监控 `/`，面向直接分发；之后应允许用户缩小范围
- Finder 扩展必须在系统设置中由用户显式启用
- Terminal / iTerm2 自动化首次使用会触发 macOS 权限提示
- Ad-hoc 签名版本首次下载运行时需要用户在“隐私与安全性”中允许
- 无 Developer ID 的版本不能通过 Apple 公证
