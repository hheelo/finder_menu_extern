# 架构

## 组件职责

### RightClickFinderExtension

- 向 Finder 提供项目菜单与文件夹背景菜单
- 把 `RightClickCore` 描述的菜单结构渲染成 `NSMenu`，本身不决定菜单内容
- 只在 `menu(for:)` 和菜单回调期间读取 `selectedItemURLs` / `targetedURL`
- 菜单项 tag 同时携带动作和菜单位置；点击空白处或侧边栏菜单时继续忽略窗口中
  可能残留的项目选区，避免操作落到旧选区
- 直接完成剪贴板与文件创建（这两件事在扩展内即可完成）；复制支持普通路径、
  文件名、file URL、Shell 单引号引用路径与父目录，多选统一以换行分隔
- 不启动任何外部 App：扩展被沙箱化，`NSWorkspace` 指定 App 启动会被拒绝，
  「用 X 打开」与「运行 CLI」一律编码成深链交给宿主
- run、run-configured、open、terminal 与 error 五类深链都使用扩展容器中的本机随机密钥生成
  HMAC-SHA256 v2 签名；URL 只携带 `v`、`ts`、`nonce` 与 `sig`，密钥本身不进入 URL
- 通过 `rightclick://open?app=...&path=...&v=2&ts=...&nonce=...&sig=...`
  请求宿主用白名单中的 App 打开
- 通过签名的 `rightclick://terminal?cwd=...` 请求宿主在该目录打开终端。用哪个终端
  由宿主解析：扩展有独立的 UserDefaults 且 App Group 已移除，读不到用户设置
- 扩展内直接失败时用经过认证的 `rightclick://error` 交给宿主；宿主本身无法启动
  时只记日志，避免错误上报递归

### RightClick

- 以 `LSUIElement` 附属应用运行：Dock 无图标，双击 App 打开窗口
- 被 Finder 深链唤起时不显示窗口；可信失败使用通知中心，并保留最近 10 条带
  时间戳的错误历史。用户拒绝通知权限时仍可在主窗口查看历史
- 提供启用指引、扩展状态、菜单配置、终端与新标签页/新窗口选择、自定义 CLI、
  模板同步、错误历史和 Finder 会话刷新
- macOS 14.4 起使用系统 API 检查扩展状态；14.0–14.3 使用 `pluginkit` 用户选择
  标记兜底，避免把已启用的扩展误报为未启用
- 严格解析五类深链；签名错误、过期或 nonce 重放的请求只记安全日志，不触发通知或用户可见错误，
  防止网页刷通知或伪造提示
- 使用 `osascript` 参数控制用户选择的终端，不拼接脚本源码
- 代扩展执行外部 App 的启动，并在失败时向用户呈现错误
- 解析终端：默认优先 iTerm2，未安装时回退 Terminal；显式选中 iTerm2 但未安装
  时同样回退，避免 AppleScript 对着不存在的应用报错。「在终端中打开」与
  「运行 AI CLI」共用这一套解析。CLI 默认新建标签页，也可在设置中改为新窗口
- 提供本地环境诊断和 Finder 重启入口。诊断使用实际登录 Shell，先做
  非交互查找，再按 Shell 能力回退到交互模式，且只接受真实可执行文件
- 诊断结果落盘缓存 24 小时；Finder 扩展状态不进缓存，始终使用当前实况。
  只在已有权威诊断明确判定 CLI 缺失时拦截；未检测过则照常执行
- 内置 Sparkle 应用内更新：只在界面确实呈现给用户时后台查一次，
  不做定时检查，深链无声唤起时不创建 Sparkle 更新器或启动检查

### RightClickCore

- 不依赖 AppKit，可被宿主 App、扩展和测试复用
- 定义动作、文件模板、菜单配置、选区语义、CLI 链接和普通 App 设置
- 描述菜单结构：菜单位置 → 菜单项、分组与置灰规则，可脱离 Finder 单独测试
- 定义受支持编辑器与终端的 Bundle ID、启动能力和查找顺序，
  菜单动作与环境诊断共用同一份规则
- 集中处理文件名冲突、URL 编码和 shell 参数转义

## 安全边界

- 不把完整 shell 命令塞进 URL；可配置 CLI 的 URL 只携带配置 ID 与工作目录。
  宿主从权限为 `0600` 的配置文件查找可执行名和逐项参数
- `rightclick://open` 只接受白名单内的 App 标识（见 `ExternalApplication.known`），
  宿主不会被诱导去启动任意程序
- 打开目标必须全部是已存在的绝对路径，只要有一个不存在就整体拒绝；
  每次最多 128 个目标，超出时整体拒绝并上报可读错误，不静默截断
- 使用统一的 `DeepLinkComponents` 严格检查 scheme、host、凭据、fragment、查询项
  白名单与字段数量，避免四种 invocation 的规则漂移
- 工作目录必须是已存在的绝对目录；run、open、terminal、error 都校验 HMAC
  签名及其全部语义参数，时间戳只接受当前时间前后 30 秒
- 宿主用进程内 nonce 缓存拒绝同一签名重放。宿主重启会清空缓存，因此在原签名
  30 秒有效期内跨进程重放仍是已知边界；彻底消除需要持久化 nonce
- v0.7.0 起只接受 v2 HMAC 签名；旧版 `token=` 与无签名 terminal/open 请求均拒绝，
  密钥不进入 URL
- Finder 始终以非激活方式唤起宿主，深链成功或失败都不会切到前台
- shell 命令作为 `osascript` 参数传递，不插入 AppleScript 源码
- 登录 shell 与 `osascript` 共用有超时和输出上限的进程执行器；stdout/stderr
  写入权限为 `0600` 的临时文件，避免管道缓冲区或子进程持有写端造成互锁
- 文件创建使用 `.withoutOverwriting`，自动生成 `Untitled 2.ext`；
  检查名称到落盘之间若发生并发冲突，最多重新选名 8 次，始终不覆盖已有文件
- 菜单配置由宿主写入 Finder 扩展容器，目录权限 `0700`、文件权限 `0600`；
  扩展每次构建菜单重新读取，损坏或未知版本一律回退完整默认菜单
- 自定义模板只从普通文件镜像，不跟随符号链接、不遍历子目录，单文件最大 10 MB；
  Finder 扩展只读取自己容器里的 `0600` 镜像
- `.app`、`.xcodeproj` 等 package 虽是磁盘目录，但新建文件和终端工作目录按
  Finder 文件语义上浮到父目录，避免破坏签名或污染工程包
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
- GitHub Actions 对主分支与 PR 运行测试并构建 Universal Release，
  在 `v*` Tag 测试通过后创建 Release
- Release 验证宿主/扩展版本、Bundle ID、签名、Universal 2 和 DMG 内容
- `derive-build-number.sh` 是 semver → CFBundleVersion 的唯一实现，本地安装、发布
  构建和 Release 工作流共同调用
- 旧 App 压缩到 Application Support，避免同 Bundle ID 扩展并存

## 已知系统约束

- Finder Sync 只在 `directoryURLs` 覆盖的目录显示项目菜单
- 当前默认监控 `/`，面向直接分发；之后应允许用户缩小范围
- Finder 扩展必须在系统设置中由用户显式启用
- Finder Sync 没有公开 API 触发内联重命名；新建后只能选中项目，不模拟键盘事件
- 用户通过“显示包内容”显式进入 package 的子目录后，子目录仍按普通目录处理；
  只有 package 本身会被视为 Finder 文件并上浮到父目录
- 扩展内绝不能用 `NSAlert.runModal()`：模态会占住扩展主线程，而 `menu(for:)`
  也在主线程上，一旦弹出右键菜单将永久不再出现
- 扩展的 `NSLog` 只写 stderr 且被丢弃，排查一律用 `os.Logger`，
  级别不低于 `notice`（`info` 默认不落盘）
- URL 事件先于 `applicationDidFinishLaunching` 到达。AppDelegate 与 SwiftUI
  场景共用按首次访问初始化的 `AppModel`，因此 URL 先到也可以直接处理；冷启动
  收到 URL 时先隐藏整个应用，阻止默认窗口在启动过程中闪现
- `com.openai.codex` 实际是 ChatGPT.app 的 Bundle ID；深链标识仍保留 `codex`
  作为已发布的跨进程契约，用户可见名称显示 ChatGPT
- iTerm2 的 AppleScript `create window ... command X` 不经过 shell，`X` 含
  `&&` 之类操作符会直接失败且连窗口都建不起来（返回 missing value）。
  必须先建默认 profile 的会话再 `write text`，与 Terminal 的 `do script` 等价
- 深链不能挂在 SwiftUI 的 `onOpenURL` 上：SwiftUI 会先创建并显示窗口再投递，
  随后收起仍会肉眼可见地闪一下。AppDelegate 直接接收 URL 并交给模型，深链
  路径从源头不进入 `WindowGroup`；窗口场景也用空的 `handlesExternalEvents`
  集合明确拒绝所有外部事件
- `applicationShouldHandleReopen` 在有窗口时自行恢复并返回 false；最后一个窗口
  已关闭时返回 true，让 AppKit/SwiftUI 新建窗口。不能因「本进程是无声启动」
  就拒绝 reopen，用户可能在宿主被深链唤起后才去双击 App。启动刷新与
  后台更新检查共用同一个「界面已呈现」判定，覆盖这条后续恢复路径
- Terminal / iTerm2 自动化首次使用会触发 macOS 权限提示。iTerm2 原生支持创建
  标签页；Terminal 的脚本字典不允许创建 tab，需通过 System Events 发送 ⌘T，
  因而“新标签页”还需要辅助功能权限。拒绝时会停止而不会写入当前标签页，用户可改用新窗口
- Ad-hoc 签名版本首次下载运行时需要用户在“隐私与安全性”中允许
- 无 Developer ID 的版本不能通过 Apple 公证
- 没有 Developer ID 就无法轮换 EdDSA 密钥（轮换需要证书建立信任链）。
  私钥丢失或泄露等于永久失去对存量用户的更新能力
- Sparkle 下载的更新包不带 quarantine（已实测：curl 下载同一 DMG 只有
  `com.apple.provenance`），因此只有首次安装需要放行一次
