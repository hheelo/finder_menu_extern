# 路线图

## M0：可编译骨架

- [x] SwiftUI 宿主 App
- [x] Finder Sync Extension
- [x] RightClickCore 共享框架
- [x] 无 App Group 的 CLI 深链接
- [x] 核心单元测试

## M1：最小可用版本

- [x] 复制路径、文件名、file URL、Shell 引用路径与父目录
- [x] 新建 7 种文件
- [x] VS Code / ChatGPT 由宿主后台打开
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
- [ ] 提供 Homebrew Cask（官方 tap 要求 Developer ID 签名与公证，受 M4 条件阻塞）
- [ ] 在 Intel Mac 上完成安装验证

## M2.5：安装与稳定性

- [x] 严格校验 CLI 深链接和工作目录
- [x] 通过参数向 AppleScript 传递命令
- [x] 终端启动移出主线程
- [x] CLI 深链使用 HMAC-SHA256、时间戳与 nonce 认证，宿主后台无窗口执行
- [x] CLI 终端可选新标签页或新窗口
- [x] Finder 操作失败提示与不可用菜单置灰
- [x] 环境诊断与诊断报告复制
- [x] 新建文件后在 Finder 中选中
- [x] 使用文件资源属性判断目录
- [x] 原生 macOS App 图标
- [x] Finder 菜单明确提供 Terminal / iTerm2 打开目录
- [x] CLI 宿主非激活后台启动
- [ ] 按 `docs/TESTING.md` 完成干净机器验证矩阵

## M3：可配置版本

- [x] 菜单项启用、排序和收进 RightClick 子菜单
- [x] 自定义文件模板目录与扩展容器镜像
- [x] 为内置模板配置默认文件名与编码
- [x] 可配置 CLI 命令与参数
- [x] 增加 Warp、Ghostty、WezTerm、Kitty
- [x] 增加 Cursor、Zed、Sublime Text、Xcode、JetBrains 与系统默认应用
- [x] 新建文件夹、从文本剪贴板新建文件
- [x] 用户选择监控目录并持久化设置（修改后按 Finder Sync 启动期约束重启 Finder）
- [ ] 简体中文 / 英文本地化（代码与自动验证完成；待 Finder 进程内双语实测）

## M3.5：体验打磨

- [x] Finder 菜单动作增加 SF Symbols 图标
- [x] 可选的菜单栏快捷入口

## M4：稳定分发

- [x] Sparkle 应用内更新（EdDSA 签名，无需 Developer ID）
- [ ] Developer ID 签名与公证
- [x] 完整的分步首次启动向导
- [x] 崩溃与请求日志（默认本地；有界动作日志、异常终止标记与隐私安全导出）
- [x] UI 自动化和签名后 smoke test

## M5：1.0.x 优化线

- [x] v1.0.2：修复 CLI 参数删除，消除动作日志、模板同步和 Finder 配置热路径，
  并为进程强杀等待增加上界
- [x] v1.0.3：完成动作与设置缓存、向导/进程轮询降频、nonce 与应用路径优化，
  扩展检测支持“无法检测”三态，并清理无调用代码和工程野文件
- [x] v1.0.4：以黄金 URL 锁定协议，统一签名 invocation、认证字段白名单、菜单
  tag 空间与 payload 编解码，并收敛深链执行生命周期、补齐直接分支测试
- [x] v1.0.5：拆分设置页、进程执行、窗口呈现和本地日志职责，归一系统常量与
  错误呈现，并将 Finder 动作结果和错误分类决策下沉 Core
- [x] v1.0.6：设置页四栏与可缩放窗口、菜单拖拽排序/恢复默认、向导跳过/重跑、
  主窗口诊断摘要/加载态，以及三个 Finder 重启入口确认
- [x] v1.0.7：补齐 VoiceOver 标签与诊断状态文字，加入主窗口/菜单栏快捷键和设置
  焦点顺序，以 ScaledMetric/自适应布局完成 Dynamic Type，并清理 Swift 6 变通
- [x] v1.0.8：新增独立 Bundle ID 的 macOS UI smoke，覆盖主窗口与设置窗口呈现；
  DMG 验证会真实启动其中的签名 App 并等待 SwiftUI 首屏就绪
- [x] v1.0.9：修复仅剩设置/诊断窗口时双击 App 无法重建主窗口的问题，并以
  LaunchServices reopen UI 回归锁定该窗口生命周期
- [x] v1.0.10：为旧系统 Finder 扩展检测增加超时与输出边界；超大自定义模板改为
  单独跳过并告警，不再阻断合法模板同步和过期镜像清理

## M6：1.1.x 稳定性线

- [x] v1.1.0：终止超时命令的完整进程树，串行化扩展状态检测，封闭模板同步的
  符号链接与大小竞态，补齐菜单栏设置刷新，并为发布版本增加一致性和递增保护
- [x] v1.1.1：增加配置迁移、损坏备份/显式恢复与导入导出；把 Finder 菜单边界和
  应用纯逻辑拆成独立测试模块；加入真实环境报告、Finder 性能基线、覆盖率、静态
  分析、失败 xcresult 与 macOS 14 最低系统 CI
- [x] v1.1.4：修复 emoji 与极限长度文件名的校验和去重后缀溢出；自定义模板改用
  单描述符、禁止跟随符号链接且有大小上限的读取，自动修复异常镜像节点，并消除
  SwiftUI 延迟释放已关闭主窗口导致 reopen 偶发失效的竞态
