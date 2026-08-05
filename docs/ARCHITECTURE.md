# 架构

## 组件职责

### RightClickFinderExtension

- 向 Finder 提供项目菜单与文件夹背景菜单
- 把 `RightClickCore` 描述的菜单结构渲染成 `NSMenu`，本身不决定菜单内容
- 只在 `menu(for:)` 和菜单回调期间读取 `selectedItemURLs` / `targetedURL`
- 菜单项 tag 同时携带动作和菜单位置；点击空白处或侧边栏菜单时继续忽略窗口中
  可能残留的项目选区，避免操作落到旧选区
- 直接完成剪贴板与文件创建（这两件事在扩展内即可完成）
- 不启动任何外部 App：扩展被沙箱化，`NSWorkspace` 指定 App 启动会被拒绝，
  「用 X 打开」与「运行 CLI」一律编码成深链交给宿主
- 通过带本机随机令牌的 `rightclick://run?tool=...&cwd=...&token=...` 请求宿主
  运行 CLI；令牌由扩展生成并保存在自己的沙箱容器中
- 通过 `rightclick://open?app=...&path=...` 请求宿主用指定 App 打开
- 通过 `rightclick://terminal?cwd=...` 请求宿主在该目录打开终端。用哪个终端
  由宿主解析：扩展有独立的 UserDefaults 且 App Group 已移除，读不到用户设置
- 操作不可用时将菜单置灰；失败只记日志，不弹窗（见「已知系统约束」）

### RightClick

- 以 `LSUIElement` 附属应用运行：Dock 无图标，双击 App 打开窗口
- 被任何 Finder 深链唤起时都不显示窗口；错误保留在状态中，只有用户主动双击
  App 时才显示宿主窗口
- 提供启用指引、扩展状态、终端选择和错误状态
- macOS 14.4 起使用系统 API 检查扩展状态；14.0–14.3 使用 `pluginkit` 用户选择
  标记兜底，避免把已启用的扩展误报为未启用
- 严格解析 CLI 深链接；只有令牌与本机扩展容器一致的请求才直接启动终端
- 使用 `osascript` 参数控制用户选择的终端，不拼接脚本源码
- 代扩展执行外部 App 的启动，并在失败时向用户呈现错误
- 解析终端：默认优先 iTerm2，未安装时回退 Terminal；显式选中 iTerm2 但未安装
  时同样回退，避免 AppleScript 对着不存在的应用报错。「在终端中打开」与
  「运行 AI CLI」共用这一套解析
- 提供本地环境诊断和 Finder 重启入口
- 内置 Sparkle 应用内更新：只在用户主动启动时后台查一次，不做定时检查，
  深链唤起时不查（否则会在用户操作文件时弹出更新界面）

### RightClickCore

- 不依赖 AppKit，可被宿主 App、扩展和测试复用
- 定义动作、文件模板、选区语义、CLI 链接和普通 App 设置
- 描述菜单结构：菜单位置 → 菜单项、分组与置灰规则，可脱离 Finder 单独测试
- 定义外部 App（VS Code / Codex / Terminal / iTerm2）的 Bundle ID 与查找顺序，
  菜单动作与环境诊断共用同一份规则
- 集中处理文件名冲突、URL 编码和 shell 参数转义

## 安全边界

- 不把完整 shell 命令塞进 URL；URL 只携带固定工具标识与工作目录
- `rightclick://open` 只接受白名单内的 App 标识（见 `ExternalApplication.known`），
  宿主不会被诱导去启动任意程序
- 打开目标必须全部是已存在的绝对路径，只要有一个不存在就整体拒绝
- 使用 `URLComponents` 编码路径，宿主只接受唯一的 `tool` / `cwd` / `token` 参数
- 工作目录必须是已存在的绝对目录，CLI 请求还必须携带本机随机令牌
- Finder 始终以非激活方式唤起宿主，深链成功或失败都不会切到前台
- shell 命令作为 `osascript` 参数传递，不插入 AppleScript 源码
- 登录 shell 与 `osascript` 共用有超时和输出上限的进程执行器；stdout/stderr
  写入权限为 `0600` 的临时文件，避免管道缓冲区或子进程持有写端造成互锁
- 文件创建使用 `.withoutOverwriting`，自动生成 `Untitled 2.ext`
- shell 工作目录使用单引号转义
- 宿主在后台等待 `osascript`，扩展进程不等待终端或编辑器
- 不自动移除 macOS quarantine 属性
- 更新包由 EdDSA 私钥签名，`SUPublicEDKey` 是对应公钥；该体系与 Apple 证书
  无关，Ad-hoc 签名也能安全校验。私钥只经标准输入进入 CI，不写入命令行参数
- 发布前流水线用同一把私钥验回签名，签名无效则拒绝发布
- Sparkle 工具包按固定版本与 SHA-256 下载，防止签名工具本身被替换

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
- 扩展内绝不能用 `NSAlert.runModal()`：模态会占住扩展主线程，而 `menu(for:)`
  也在主线程上，一旦弹出右键菜单将永久不再出现
- 扩展的 `NSLog` 只写 stderr 且被丢弃，排查一律用 `os.Logger`，
  级别不低于 `notice`（`info` 默认不落盘）
- URL 事件先于 `applicationDidFinishLaunching` 到达。附属应用在启动期和下一轮
  runloop 都要收起窗口，避免 SwiftUI 延迟创建的窗口闪现
- `com.openai.codex` 实际是 ChatGPT.app 的 Bundle ID
- iTerm2 的 AppleScript `create window ... command X` 不经过 shell，`X` 含
  `&&` 之类操作符会直接失败且连窗口都建不起来（返回 missing value）。
  必须先建默认 profile 的会话再 `write text`，与 Terminal 的 `do script` 等价
- SwiftUI 为投递 `onOpenURL` 会新建窗口，即使已有窗口开着也照建不误。因此
  深链处理必须按「窗口编号」逐个比对：原本可见的保持不动，期间新出现的收掉。
  只看「之前有没有窗口」不够，会漏掉「窗口开着又多出一个」的情形。
  新窗口可能在处理函数返回之后才创建，所以下一个 runloop 还要再查一次
- `applicationShouldHandleReopen` 一律返回 false：返回 true 会让 AppKit
  执行默认行为再开一个窗口。也不能因「本进程是无声启动」就拒绝 reopen，
  用户可能在宿主被深链唤起后才去双击 App
- Terminal / iTerm2 自动化首次使用会触发 macOS 权限提示
- Ad-hoc 签名版本首次下载运行时需要用户在“隐私与安全性”中允许
- 无 Developer ID 的版本不能通过 Apple 公证
- 没有 Developer ID 就无法轮换 EdDSA 密钥（轮换需要证书建立信任链）。
  私钥丢失或泄露等于永久失去对存量用户的更新能力
- Sparkle 下载的更新包不带 quarantine（已实测：curl 下载同一 DMG 只有
  `com.apple.provenance`），因此只有首次安装需要放行一次
