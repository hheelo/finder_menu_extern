# 路线图

## M0：可编译骨架

- [x] SwiftUI 宿主 App
- [x] Finder Sync Extension
- [x] RightClickCore 共享框架
- [x] 无 App Group 的 CLI 深链接
- [x] 核心单元测试

## M1：最小可用版本

- [x] 复制路径与文件名
- [x] 新建 7 种文件
- [x] VS Code / Codex 由扩展直接打开
- [x] Terminal / iTerm2 启动 Codex CLI / Claude Code
- [x] 扩展启用状态和系统设置入口
- [ ] 在全新用户环境中完成 Finder 端到端验证
- [ ] 菜单操作失败时展示用户可见通知
- [ ] 确认 Codex App 的正式 Bundle ID，并增加自动探测

## M2：无证书分发

- [x] Ad-hoc 签名通用构建
- [x] DMG 与 SHA-256 打包
- [x] 一键本地安装脚本
- [x] Tag 驱动的 GitHub Release 工作流
- [ ] 提供 Homebrew Cask
- [ ] 在 Intel Mac 上完成安装验证

## M3：可配置版本

- [ ] 菜单项启用、排序和分组
- [ ] 自定义文件模板、默认文件名与编码
- [ ] 可配置 CLI 命令与参数
- [ ] 增加 Warp、Ghostty、WezTerm、Kitty
- [ ] 用户选择监控目录并持久化设置
- [ ] 中文 / 英文本地化

## M4：稳定分发

- [ ] Developer ID 签名、公证和 Sparkle 更新
- [ ] 完整的分步首次启动向导与权限诊断
- [ ] 崩溃与请求日志（默认本地）
- [ ] UI 自动化和签名后 smoke test
