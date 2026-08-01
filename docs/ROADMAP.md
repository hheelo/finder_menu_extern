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
- [x] 菜单操作失败时展示用户可见提示
- [x] 确认 Codex App 的 Bundle ID（`com.openai.codex` 即 ChatGPT.app）

## M2：无证书分发

- [x] Ad-hoc 签名通用构建
- [x] DMG 与 SHA-256 打包
- [x] 一键本地安装脚本
- [x] Tag 驱动的 GitHub Release 工作流
- [x] 升级时注销旧扩展，并将旧 App 压缩到非应用目录
- [x] PR / Main CI 与 Release 测试门禁
- [x] 自动验证签名、Bundle ID、版本、Universal 2 和 DMG 内容
- [ ] 提供 Homebrew Cask
- [ ] 在 Intel Mac 上完成安装验证

## M2.5：安装与稳定性

- [x] 严格校验 CLI 深链接和工作目录
- [x] 通过参数向 AppleScript 传递命令
- [x] 终端启动移出主线程
- [x] CLI 启动前确认
- [x] Finder 操作失败提示与不可用菜单置灰
- [x] 环境诊断与诊断报告复制
- [x] 新建文件后在 Finder 中选中
- [x] 使用文件资源属性判断目录
- [x] 原生 macOS App 图标
- [x] Finder 菜单明确提供 Terminal / iTerm2 打开目录
- [x] CLI 宿主非激活后台启动
- [ ] 按 `docs/TESTING.md` 完成干净机器验证矩阵

## M3：可配置版本

- [ ] 菜单项启用、排序和分组
- [ ] 自定义文件模板、默认文件名与编码
- [ ] 可配置 CLI 命令与参数
- [ ] 增加 Warp、Ghostty、WezTerm、Kitty
- [ ] 用户选择监控目录并持久化设置
- [ ] 中文 / 英文本地化

## M4：稳定分发

- [x] Sparkle 应用内更新（EdDSA 签名，无需 Developer ID）
- [ ] Developer ID 签名与公证
- [ ] 完整的分步首次启动向导
- [ ] 崩溃与请求日志（默认本地）
- [ ] UI 自动化和签名后 smoke test
