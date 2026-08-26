# 架构

## 组件职责

### RightClickFinderExtension

- 向 Finder 提供项目菜单与文件夹背景菜单
- 把 `RightClickCore` 描述的菜单结构渲染成 `NSMenu`，本身不决定菜单内容
- 使用 Core 提供的本地化标题和稳定 SF Symbol 标识渲染菜单，
  不根据翻译后的文字推断图标或动作
- 只在 `menu(for:)` 和菜单回调期间读取 `selectedItemURLs` / `targetedURL`
- 菜单项 tag 同时携带动作和菜单位置；点击空白处或侧边栏菜单时继续忽略窗口中
  可能残留的项目选区，避免操作落到旧选区
- 直接完成剪贴板复制；复制支持普通路径、文件名、file URL、Shell 单引号引用路径
  与父目录，多选统一以换行分隔
- 构建菜单时只探测剪贴板是否声明文本类型，不读取内容；只有用户真正点击
  “从剪贴板新建文件”后才取文本，避免大剪贴板拖慢每一次右键
- 不启动任何外部 App，也不直接写入 Finder 目标目录：扩展被沙箱化，Finder 的
  上下文 URL 不附带目录写授权；文件创建、「用 X 打开」与「运行 CLI」一律编码成
  深链交给未沙箱化宿主
- run、run-configured、open、terminal、create 与 error 六类深链都使用扩展容器中的本机随机密钥生成
  HMAC-SHA256 v2 签名；URL 只携带 `v`、`ts`、`nonce` 与 `sig`，密钥本身不进入 URL
- 通过 `rightclick://open?app=...&path=...&v=2&ts=...&nonce=...&sig=...`
  请求宿主用白名单中的 App 打开
- 通过签名的 `rightclick://terminal?cwd=...` 请求宿主在该目录打开终端。用哪个终端
  由宿主解析：扩展有独立的 UserDefaults 且 App Group 已移除，读不到用户设置
- 扩展内直接失败时用经过认证的 `rightclick://error` 交给宿主；宿主本身无法启动
  时只记日志，避免错误上报递归
- 每次菜单点击只把稳定动作名、阶段和错误分类追加到内存中的有界日志；达到 10 条
  或安静 200ms 后在后台批量写入扩展容器的 `0600` 文件。路径、文件名、动态 CLI
  内容和深链 URL 都不进入日志

### RightClick

- 以 `LSUIElement` 附属应用运行：Dock 无图标，双击 App 打开窗口
- 被 Finder 深链唤起时不显示窗口；可信失败使用通知中心，并保留最近 10 条带
  时间戳的错误历史。错误只有这一份状态来源，设置页与通知从同一条失败记录呈现；
  用户拒绝通知权限时仍可在主窗口查看历史
- 提供启用指引、扩展状态、菜单配置、终端与新标签页/新窗口选择、自定义 CLI、
  模板同步、错误历史和 Finder 会话刷新
- 设置窗口按菜单、终端、模板、诊断四栏组织，各栏独立滚动并允许窗口缩放；菜单项
  使用拖拽排序并可恢复默认。Settings 场景不再提供不可靠且不符合 macOS 惯例的
  “返回主窗口”工具栏按钮
- 设置页的图标按钮、模板编码和诊断结果都提供明确的 VoiceOver 名称；诊断状态同时
  使用文字、图标与颜色表达。固定字号和宽度通过 `ScaledMetric` 与自适应布局响应
  系统字号，主窗口和向导不再锁死内容尺寸
- 主窗口提供设置、检查更新和复制诊断快捷键；设置切栏后聚焦首个控件，菜单栏入口
  也为显示窗口、设置、诊断、Finder 重启和退出声明稳定快捷键
- macOS 14.4 起使用系统 API 检查扩展状态；14.0–14.3 使用 `pluginkit` 用户选择
  标记兜底；检测进程不可用、超时或输出异常时诊断显示“无法检测”并记录日志，
  不伪装成“未启用”
- 首次向导的扩展检测按 1 秒、2 秒、5 秒退避，五分钟后停止自动轮询并提供
  手动刷新，避免旧系统长期反复启动 `pluginkit`；用户可以稍后设置，也可以从设置
  重新运行三步向导，且不会清除现有菜单或终端配置
- 严格解析六类深链；签名错误、过期或 nonce 重放的请求只记安全日志，不触发通知或用户可见错误，
  防止网页刷通知或伪造提示
- 使用 `osascript` 参数控制用户选择的终端，不拼接脚本源码
- 代扩展执行文件创建和外部 App 启动，并在失败时向用户呈现错误
- 解析终端：默认优先 iTerm2，未安装时回退 Terminal；显式选中 iTerm2 但未安装
  时同样回退，避免 AppleScript 对着不存在的应用报错。「在终端中打开」与
  「运行 AI CLI」共用这一套解析。CLI 默认新建标签页，也可在设置中改为新窗口
- 提供本地环境诊断和 Finder 重启入口。诊断使用实际登录 Shell，先做
  非交互查找，再按 Shell 能力回退到交互模式，且只接受真实可执行文件
- 主窗口显示诊断通过/注意项摘要和刷新进度；主窗口、设置页与菜单栏发起 Finder
  重启前都会确认并说明所有 Finder 窗口将被关闭
- 诊断始终显示当前所选终端；缺失时明确说明会回退 Terminal。编辑器只显示
  已启用但缺失的项，全部可用时合并为一条成功摘要
- 诊断结果落盘缓存 24 小时；Finder 扩展状态不进缓存，始终使用当前实况。
  缓存同时记录语言、终端和完整菜单配置；任一变化都会重新收集，不展示旧上下文
  的结果
  只在已有权威诊断明确判定 CLI 缺失时拦截；未检测过则照常执行
- 菜单文本字段在 400ms 无新输入后合并落盘；Toggle、增删、排序和终端切换立即
  落盘。设置页关闭与 App 退出会同步冲刷，初始化发现终端能力缺失也会静默补写
- 内置菜单动作顺序只在菜单配置变化时重算；动作到稳定 tag、配置 ID 的转换使用
  预建查找表，tag 黄金测试保护已发布的跨进程编码
- CLI、终端与配置化 CLI 的异步执行生命周期统一由 `DeepLinkCoordinator.perform`
  管理，三条路径共享开始、成功、失败记录与可信错误呈现语义
- 内置 Sparkle 应用内更新：只在界面确实呈现给用户时后台查一次，
  不做定时检查，深链无声唤起时不创建 Sparkle 更新器或启动检查
- 宿主与扩展分别保留动作日志，设置页导出时按时间合并最近 200 条。存储 JSON
  使用紧凑格式，目录与文件权限只在首次创建时设置；宿主正常退出会显式冲刷。
  进程被强杀时最多丢失一个 200ms 去抖窗口内的记录。宿主启动时
  写会话标记、正常退出时删除；下次启动发现残留只报告“异常终止”，因为它也可能
  来自强制退出或断电，不能伪装成已确认的崩溃报告
- 进程执行、窗口呈现和本地动作日志的存储、会话、文件权限、报告职责均使用独立
  源文件；设置页 `body` 只组合按功能划分的区块，避免后续界面改造继续扩大入口文件
- `RightClickAppLogic` 保存版本、启动/窗口策略、深链解析、nonce 与向导轮询等纯逻辑，
  宿主和无宿主测试共享同一 framework，避免测试复制生产源文件时遗漏新增依赖

### RightClickFinderAdapter

- 隔离 FinderSync 与 AppKit 菜单渲染边界：稳定 tag、置灰、图标和 stale selection
  语义可在普通测试进程中验证，扩展只保留系统回调和动作执行
- Finder 菜单构建由 `BuildFinderMenu` signpost 覆盖；高负载配置基线在 CI 中重复构建
  菜单并设置宽松上界，用于捕获意外 I/O 或复杂度量级回归，而不是比较不同机器的微秒差异

### RightClickCore

- 不依赖 AppKit，可被宿主 App、扩展和测试复用
- 定义动作、文件模板、菜单配置、选区语义、CLI 链接和普通 App 设置
- 描述菜单结构：菜单位置 → 菜单项、分组与置灰规则，可脱离 Finder 单独测试
- `MenuTagSpace` 集中声明固定动作、自定义模板和配置化 CLI 的 tag 区段；三个公开
  payload 共享泛型编解码器，区段不相交测试防止配置上限扩张造成跨进程错派发
- `allMenuActions` 在当前 Swift 6 工具链中恢复为单表达式；黄金 tag 测试继续锁定
  已发布顺序，避免编译器层面的简化改变跨进程编码
- `actionOrder` 只排序内置动作；动态 CLI 与模板只按各自的稳定 `menuSlot` 排列，
  不叠加第二套排序机制
- `FinderActionPolicy` 统一决定动作目标、目标目录、本地/宿主执行结果与稳定错误分类；
  Finder 扩展只执行策略结果，不重复维护这些分支
- 定义受支持编辑器与终端的 Bundle ID、启动能力和查找顺序，
  菜单动作与环境诊断共用同一份规则
- 集中处理文件名冲突、URL 编码和 shell 参数转义
- `AppConstants` 集中宿主与扩展共用的 Bundle ID、系统工具 URL、应用搜索根目录和
  日志 subsystem；超时、重试、长度与数量上限在各自实现附近以具名常量表达
- 五类深链 invocation 统一遵循 `SignedInvocation`：生成、令牌守卫与签名字段由
  默认实现提供，各类型只声明 host 和业务查询项；黄金 URL 测试锁定发布格式
- `Localizable.xcstrings` 跟随 Core framework 打包，宿主与 Finder 扩展统一
  通过 `L10n` 从 framework bundle 取简体中文 / 英文文案

## 自动验证边界

- 逻辑单元测试继续以无宿主 bundle 运行，不启动 `LSUIElement` App，也不依赖
  Sparkle 或开发机上已安装的正式副本
- UI 自动化使用不嵌入 Finder 扩展的 `RightClickUITestHost`，其 Bundle ID 与正式
  App 隔离；显式测试环境只关闭 onboarding、诊断刷新和更新检查，不改变正式启动路径
- 发布脚本从只读 DMG 直接启动已完成 Ad-hoc 签名的正式 App。主视图 `onAppear`
  只在脚本提供的系统临时子目录内写入 ready 标记，验证完成后终止进程并清理标记
- CI 在当前构建机运行覆盖率、静态分析、UI smoke 与 Universal Release，并在 macOS 14
  runner 单独执行逻辑测试；失败时保存 xcresult。真实 Finder/权限/卷测试通过
  `create-validation-report.sh` 生成不含个人路径的可归档报告

## 安全边界

- 不把完整 shell 命令塞进 URL；可配置 CLI 的 URL 只携带配置 ID 与工作目录。
  宿主从权限为 `0600` 的配置文件查找可执行名和逐项参数
- `rightclick://open` 只接受白名单内的 App 标识（见 `ExternalApplication.known`），
  宿主不会被诱导去启动任意程序
- 打开目标必须全部是已存在的绝对路径，只要有一个不存在就整体拒绝；
  每次最多 128 个目标，超出时整体拒绝并上报可读错误，不静默截断
- 使用统一的 `DeepLinkComponents` 严格检查 scheme、host、凭据、fragment、查询项
  白名单与字段数量；认证字段 `v`、`ts`、`nonce`、`sig` 只有一份集中定义，避免
  五种 invocation 的规则漂移
- 工作目录必须是已存在的绝对目录；run、open、terminal、error 都校验 HMAC
  签名及其全部语义参数，协议版本 `v2` 也进入待签名串；时间戳只接受当前时间
  前后 30 秒
- 宿主用进程内 nonce 缓存拒绝同一签名重放。宿主重启会清空缓存，因此在原签名
  30 秒有效期内跨进程重放仍是已知边界；彻底消除需要持久化 nonce
  缓存只在达到规模阈值后批量清理，但每次消费仍单独检查目标 nonce 的时间窗，
  因而窗口内重放与过期淘汰语义不变
- v0.7.0 起只接受 v2 HMAC 签名；旧版 `token=` 与无签名 terminal/open 请求均拒绝，
  密钥不进入 URL
- Finder 始终以非激活方式唤起宿主，深链成功或失败都不会切到前台
- shell 命令作为 `osascript` 参数传递，不插入 AppleScript 源码
- 登录 shell、`osascript` 与旧系统的 `pluginkit` 检测共用有超时和输出上限的
  进程执行器；stdout/stderr 写入权限为 `0600` 的临时文件，避免管道缓冲区或
  子进程持有写端造成互锁。超时、取消或超限时先暂停并遍历整棵进程树，再按
  叶到根的顺序终止，避免 Shell 启动的后台后代成为孤儿
- 文件创建使用 `.withoutOverwriting`，自动生成 `Untitled 2.ext`；
  检查名称到落盘之间若发生并发冲突，最多重新选名 8 次，始终不覆盖已有文件
- 内置模板的文件名与编码覆盖保存在同一份菜单配置中；文件名必须通过安全校验，
  编码只接受 UTF-8、UTF-8 with BOM 与 UTF-16，非法值逐项回退内置默认值
- 菜单配置由宿主写入 Finder 扩展容器，目录权限 `0700`、文件权限 `0600`；
  扩展以文件修改时间与大小为戳缓存最近一次解码结果。宿主使用原子替换写入，
  因而设置保存后下一次右键仍会失效并重载；损坏或未知版本一律回退完整默认菜单
- 本地动作日志同样使用 `0700` 目录与 `0600` 文件，并通过封闭枚举从类型层阻止
  敏感字符串进入记录。未认证深链不会写入持久日志，避免网页刷满本地历史
- Finder 监控目录也保存在菜单配置中，但它是启动期例外：扩展只在 `init` 中解析
  绝对路径、跳过不存在的目录并设置 `directoryURLs`。空配置或全部不可用时回退
  `/`，防止菜单整体消失；修改监控范围后必须重启 Finder。Apple 文档要求扩展
  启动时设置该集合，没有把运行时热更新定义为受支持契约
- 自定义模板只从普通文件镜像，不跟随符号链接、不遍历子目录，单文件最大 10 MB；
  超限文件会单独跳过并记录可见警告，不阻断其他模板更新或过期镜像清理；
  镜像与菜单配置只在宿主界面呈现或用户手动刷新时对齐，Finder 扩展只读取自己
  容器里的 `0600` 镜像来构建菜单；点击后由宿主重新校验并读取模板源文件完成创建。
  同步以文件大小与修改
  时间跳过未变化文件；同步在 utility 后台任务执行，只有结果回到主 actor 提交，
  不允许模板目录 I/O 阻塞窗口呈现。这是避免读取全文的性能折中，镜像本身不是
  安全边界
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
  构建和 Release 工作流共同调用；本地安装通过 `read-marketing-version.sh` 读取
  `project.yml`，兼容带引号与不带引号的版本标量。Release 构建还会拒绝与源码
  版本不一致的 Tag，以及不高于历史发布标签的构建号
- 旧 App 压缩到 Application Support，避免同 Bundle ID 扩展并存

## 已知系统约束

- Finder Sync 只在 `directoryURLs` 覆盖的目录显示项目菜单
- 宿主仍是没有 Dock 图标的 `LSUIElement`；菜单栏入口默认关闭，启用状态保存在
  UserDefaults，由 AppKit `NSStatusItem` 单向管理，入口只转发现有的窗口、诊断、
  Finder 重启与退出动作。不要把设置直接绑定到 SwiftUI `MenuBarExtra` 的
  `isInserted`：macOS 26.6 会形成 Scene / `@Published` 写回反馈环，导致启动后
  AttributeGraph 持续重算、CPU 和内存无上限增长
- 默认监控 `/`；用户可以在设置中缩小到一个或多个目录及其子目录。由于
  `directoryURLs` 是 Finder Sync 启动期状态，设置页把重启 Finder 作为显式提交步骤
- Finder 扩展必须在系统设置中由用户显式启用
- Finder Sync 没有公开 API 触发内联重命名；新建后只能选中项目，不模拟键盘事件
- 用户通过“显示包内容”显式进入 package 的子目录后，子目录仍按普通目录处理；
  只有 package 本身会被视为 Finder 文件并上浮到父目录
- 「复制相对路径」的基准靠向上探测 `.git`。扩展是沙箱化的，任何一层都可能读不到，
  此时与「确实不在仓库里」无法区分，一律降级为 Finder 当前窗口目录，而不是让动作
  失败。探测只在点击时进行，最多向上 64 层；`menu(for:)` 里不做任何仓库判断，
  否则会变成每次右键的弹出延迟
- 扩展内绝不能用 `NSAlert.runModal()`：模态会占住扩展主线程，而 `menu(for:)`
  也在主线程上，一旦弹出右键菜单将永久不再出现
- 扩展的 `NSLog` 只写 stderr 且被丢弃，排查一律用 `os.Logger`，
  级别不低于 `notice`（`info` 默认不落盘）
- URL 事件先于 `applicationDidFinishLaunching` 到达。AppDelegate 与 SwiftUI
  场景共用按首次访问初始化的 `AppModel`，因此 URL 先到也可以直接处理；冷启动
  收到 URL 时由 `AppLaunchState` 立即把启动分类收紧为 headless 并隐藏整个应用，
  不能等 finish 回调才改标记，否则 SwiftUI `.task` 可能在竞态窗口里请求 onboarding
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
  已关闭时通过已注册的 `openWindow` 动作显式新建主窗口。设置/诊断窗口不能充当
  主窗口；即使它仍可见，双击 App 也必须恢复“检查更新”等主界面入口。不能因
  「本进程是无声启动」就拒绝 reopen，用户可能在宿主被深链唤起后才去双击 App。首次启动、窗口恢复、
  菜单栏入口统一调用 `AppModel.refreshForUserPresentation()`；onboarding、模板同步
  和诊断刷新不能绕开这条用户可见通道，后台更新检查沿用同一个呈现判定
- Terminal / iTerm2 自动化首次使用会触发 macOS 权限提示。iTerm2 原生支持创建
  标签页；Terminal 的脚本字典不允许创建 tab，需通过 System Events 发送 ⌘T，
  因而“新标签页”还需要辅助功能权限。拒绝时会停止而不会写入当前标签页，用户可改用新窗口
- Ad-hoc 签名版本首次下载运行时需要用户在“隐私与安全性”中允许
- 无 Developer ID 的版本不能通过 Apple 公证
- Homebrew 官方 cask 当前会审计 Apple 签名与公证，因此 F5 依赖 F6；在取得
  Developer ID 之前不提交一个无法通过官方审计的 cask，也不通过脚本绕过 quarantine
- 没有 Developer ID 就无法轮换 EdDSA 密钥（轮换需要证书建立信任链）。
  私钥丢失或泄露等于永久失去对存量用户的更新能力
- Sparkle 下载的更新包不带 quarantine（已实测：curl 下载同一 DMG 只有
  `com.apple.provenance`），因此只有首次安装需要放行一次
