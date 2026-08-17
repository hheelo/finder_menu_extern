# 发布验证清单

单元测试和签名验证不能替代 Finder 扩展的真实系统测试。每个正式版本发布前，
至少在一台没有安装过 RightClick 的 Mac 上完成以下检查。

## 自动验证

```sh
xcodebuild -project RightClick.xcodeproj \
  -scheme RightClick \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test

VERSION=1.0.2 ./scripts/build-release.sh
```

第二条命令会验证 App、Finder 扩展、双语资源、通用架构、Ad-hoc 签名与 DMG 内容。

`RightClickAppTests` 是无宿主逻辑测试：被测文件直接编入测试包，不启动
`LSUIElement` App，也不依赖已安装的同 Bundle ID 副本或 Sparkle。装有
`/Applications/RightClick.app` 时应同样能在数秒内跑完两个测试 bundle。

## 干净机器

- 从 GitHub Release 下载 DMG，而不是使用本地构建产物
- 验证 SHA-256 文件
- 将 RightClick 拖入 Applications
- 确认 Finder、Dock 和系统设置中显示正式 App 图标
- 确认 Gatekeeper 首次阻止时，可以通过“隐私与安全性 → 仍要打开”放行
- 在 App 中打开扩展设置并启用 RightClick Finder Extension
- 在桌面文件、桌面空白处、Finder 文件、窗口空白处、侧边栏，以及一个
  含空格/中文/单引号的目录中检查右键菜单
- 保持 Finder 窗口中另一个文件处于选中状态，再右键窗口空白处和侧边栏目录，
  确认复制、打开、新建及终端动作都作用于右键目录而不是残留选区
- 测试复制路径、复制文件名、file URL、Shell 引用路径、父目录和多选；确认多选
  每行一项，Shell 路径中的单引号被正确转义
- 在 git 仓库的子目录里选中若干文件并「复制相对路径」，确认结果相对仓库根；
  在非 git 目录（如 `~/Downloads`）里重复，确认基准退到当前 Finder 窗口目录
- 同时选中两个不同仓库里的文件后复制相对路径，确认不在基准之下的项输出绝对
  路径，且结果里没有 `../`
- 在设置里把「多选复制时分隔符」依次切成换行 / 空格 / 逗号，每次改完立即右键
  多选复制，确认下一次右键就生效且没有重启 Finder
- 自定义 CLI 加 3 个参数，删除中间一个，确认不崩溃、剩余内容和 `menu.json`
  都正确
- 先让宿主与扩展动作日志各达到 200 条，再连续执行 20 次右键动作，确认菜单与
  动作响应没有可感知的日志写入延迟
- 在自定义模板目录放入 50 个文件，反复切换到 RightClick 或打开设置，确认窗口
  呈现期间不因模板扫描而卡顿
- 修改任一菜单设置后不重启 Finder，确认下一次右键立即使用新配置
- 逐一创建七种文件，确认同名文件不会覆盖
- 分别把内置 JSON 模板改名为 `package.json`、设为 UTF-8 with BOM，把 Python
  模板设为 UTF-16；确认文件名、BOM 与内容正确。输入 `../escape` 时应显示警告，
  Finder 创建结果必须回退内置文件名且不能写出目标目录
- 快速连续创建同一种文件，确认并发占用名称时会重选名且不会覆盖
- 测试 VS Code / ChatGPT 存在与缺失两种状态，确认菜单与诊断显示 ChatGPT
- 测试 Codex CLI / Claude Code 存在与缺失两种状态
- 分别将登录 Shell 设为 zsh/bash、fish 和 Nushell，刷新诊断，确认
  面板显示真实 Shell 路径且能找到该 Shell 环境中的 CLI
- `chsh` 后不注销，确认诊断面板显示的登录 Shell 与 WezTerm/kitty 实际执行
  CLI 所用的 Shell 一致；让 `SHELL` 指向不存在路径时应回退到用户记录中的 Shell
- 把 `codex` 临时移出登录 Shell 的 PATH 并强制刷新诊断，再从 Finder
  运行 Codex CLI，确认收到可读提示且不打开终端；清空诊断缓存后则应放行
- 选中 129 个以上的项目并点「用 VS Code 打开」，确认收到「一次最多
  打开 128 个项目」提示，不打开不完整的目标集合
- 造一个含数千文件的目录（`mkdir -p /tmp/rc-bulk && cd /tmp/rc-bulk &&
  touch file{1..5000}.txt`），全选后点「用 VS Code 打开」，确认得到同一条可读
  提示而不是无反应——深链在这个量级本会超出 LaunchServices 的 URL 长度上限
- 测试 Terminal 与 iTerm2，并检查首次自动化权限提示；Terminal 新标签页首次
  使用还应提示辅助功能权限，拒绝后不得把命令写进原标签页
- 分别选择“新标签页”和“新窗口”。连续触发三次 CLI 时，前者应增加三个标签页
  而非三个窗口；完全退出终端后触发一次，应只出现一个窗口
- 不安装 Ghostty，把默认终端选成 Ghostty，确认诊断立即显示“未找到，将回退到
  Terminal”而不沿用 24 小时缓存；卸载 Cursor 后应出现缺失项，重装后应消失
- 触发 CLI 动作，确认终端在正确目录启动，RightClick 不切到前台、不增加窗口，
  界面也不会短暂闪现
- 在全新用户账户尚未完成首次向导时，先从 Finder 触发一次宿主型动作，确认向导和
  主窗口都不会因深链冷启动而闪现；随后双击 App，向导才应正常出现
- 快速触发两个 CLI 动作，确认两个终端请求都执行且始终没有 RightClick 窗口
- 关闭 RightClick 的最后一个窗口但不退出进程，再双击 App，确认会新建并显示窗口
- 将 RightClick 窗口最小化或隐藏后再双击 App，确认只恢复原窗口而不重复创建
- 先用 Finder 右键动作无声唤起宿主，再双击 App，确认日志出现
  「后台检查更新」；单纯右键唤起时不应有 Sparkle 初始化日志
- 从浏览器打开格式合法但没有 v2 签名的
  `rightclick://run?tool=codex&cwd=/tmp`，确认不开终端且不显示 RightClick 窗口
- 从浏览器打开无令牌的 `rightclick://error?message=...`，确认不显示通知、不写入
  错误历史，也不显示 RightClick 窗口
- 从浏览器分别打开签名缺失/损坏的 run、terminal、open、error 和未知
  `rightclick://` 链接，确认不会执行动作或显示通知
- 对扩展生成的 v2 请求分别篡改工具、路径、参数顺序、时间戳和签名，确认全部拒绝；
  同一 URL 连续提交两次，第二次必须因 nonce 重放被拒绝
- 安装 v0.6.x 后升级到 v0.7.0，确认 App 自动刷新 Finder 会话；旧版 `token=` 与
  无签名 terminal/open 链接必须被拒绝，重启 Finder 后所有新动作恢复正常
- 从 v0.9.0 升级到 v0.9.1 时保持旧 Finder 会话，确认旧扩展生成的签名被拒绝；
  App 自动刷新 Finder 后，新请求恢复正常且签名已绑定协议版本
- 在设置里禁用、排序菜单项并切换 RightClick 子菜单，确认下一次右键立即生效
- 把 Finder 监控目录限制为 `~/Projects`，重启 Finder 后确认该目录及其子目录有
  RightClick 菜单、`~/Downloads` 没有；添加一个不存在的路径时其他有效目录仍工作，
  移除最后一项并重启后恢复全盘菜单
- 在设置页连续输入一个长命令名并同时反复右键，确认动态 CLI 不会随半成品配置
  闪烁；输入到一半直接按 ⌘Q，重开 App 后确认最后输入仍然保留
- 确认所有内置、自定义 CLI 和自定义模板菜单项都带有可读的
  SF Symbols 图标，置灰时图标与文字状态一致
- 分别测试 Warp、Ghostty、WezTerm、Kitty；Warp/Ghostty 的 AI CLI 菜单应置灰，
  WezTerm/Kitty 应能在所选目录运行命令。再逐一测试新增编辑器与默认应用
- 添加带参数的自定义 CLI，分别测试 PATH 命令名与含空格的绝对路径；确认 URL 中
  只有配置 ID、没有命令或参数，并测试含空格、单引号的参数按单个参数传递
- 向 `~/Library/Application Support/RightClick/Templates/` 放入普通文件、子目录和
  符号链接，不进设置页，只关窗口后再次双击 App，确认只出现普通文件；删除模板
  后用同样方式确认菜单项与扩展容器镜像都消失，创建结果仍保留内容且不覆盖同名文件
- 保持 Finder 右键菜单打开，在设置里删除对应的自定义 CLI；对模板则先删除源文件
  并重新呈现宿主完成同步。回到旧菜单点击，确认收到“配置已被修改”通知而非无反应
- 主窗口版本号应可选中复制，并与“复制诊断信息”首行及 Finder“显示简介”一致；
  VoiceOver 应读出版本号和构建号，而不是逐字念数字
- 菜单栏图标默认不出现；在设置中启用后确认可显示主窗口、打开设置、复制诊断、
  重启 Finder 与退出。关闭主窗口后入口仍可用，关闭设置开关后图标立即消失，
  重启 App 后保持上次选择。分别在开关关闭和开启时冷启动 App，空闲至少 60 秒，
  确认窗口始终可响应、CPU 回落到空闲且内存不持续增长
- 在全新用户账户首次启动时确认三步向导出现：启用扩展后状态无需手动刷新即变绿，
  选择终端时诊断结果同步显示，完成后不再出现；确认向导没有提前请求通知或自动化
  权限。升级已有设置的旧版本时向导不应突然出现
- 在 macOS 15/26 把 50 MB 文本放入剪贴板后反复打开 Finder 右键菜单，确认无
  隐私提示、无可感知延迟，并用 pasteboard 子系统日志复核；只有真正点击创建时
  才读取内容
- 测试新建文件夹与从文本剪贴板新建文件；空剪贴板不得写入空文件
- 卸载 VS Code 后触发“用 VS Code 打开”，确认收到本地通知、错误进入最近 10 条
  历史，并且 RightClick 不抢焦点；拒绝通知权限时仍应保留错误历史
- 右键 `/Applications` 中的 App 新建 TXT，确认目标是 App 的父目录（或收到权限
  错误），绝不能写入 `.app` 包内部
- 右键 `.xcodeproj` 后“在终端中打开”，确认终端目录是工程包的父目录
- 升级旧版本，确认 Applications 中只留下一个 RightClick.app
- 将默认终端设为 Ghostty，删除扩展容器中的 `menu.json` 后重开 App，确认文件被
  重建且带有 `terminalProfileID: ghostty`，不支持 CLI 的菜单仍保持置灰
- 保持 Finder 运行并升级旧版本；启动新 App 后确认 Finder 自动退出并重新打开，
  且右键菜单加载的是新扩展
- 运行 `pluginkit -m -A -D -v -i com.hheelo.RightClick.FinderExtension`，
  确认只列出 Applications 中的一份扩展
- 分别执行一次扩展内复制、一次宿主 CLI 和一次失败动作，再从设置页导出本地日志；
  确认导出内容最多包含最近 200 条，能看到 extension/host 的动作名、结果和错误分类，且全文
  不包含所选文件路径、文件名、CLI 命令参数或 `rightclick://` URL
- 正常退出再启动一次，确认不会产生异常终止记录；随后用活动监视器强制结束宿主并
  重开，确认只增加 `unexpected-termination` 标记，不声称已确认发生崩溃

## 本地化

- 在“系统设置 → 通用 → 语言与地区 → 应用程序”中分别把
  RightClick 设为简体中文和英语，每次完全退出后重开，检查主窗口、
  设置、诊断报告和错误通知，确认没有中英混排或裁切
- Finder 扩展跟随 Finder 进程的语言环境，不得用宿主的 App 级语言
  替代验证。切换系统首选语言并重新登录后，分别检查英文和简体中文
  Finder 菜单，包括动态 CLI 标题和所有子菜单
- 在两种语言下各新建一个 HTML 文件，确认 `<html lang>` 分别为
  `en` 与 `zh-CN`；新建文件夹的默认名也应随语言变化
- 清空诊断缓存后用一种语言刷新，再切换语言重开 App；确认 24 小时
  缓存不会让旧语言的诊断标题继续显示

## 存储位置

- Apple Silicon：至少一台当前正式版 macOS
- Intel：至少一台仍受支持的 macOS
- 可选：外置磁盘、网络卷和 iCloud Drive

把验证日期、macOS 版本、CPU 架构以及失败项记录在对应 GitHub Release 或 Issue
中。Intel 与外部卷未验证时，不应在 Release Notes 中声明已全面支持。

## 全新用户环境验证（ROADMAP M1）

开发机上装过的旧版本、已授予的自动化与通知权限、已存在的令牌与配置文件都会
掩盖首次使用的问题。不需要另一台 Mac —— 新建一个 macOS 用户账户即可拿到干净的
容器和权限状态：

1. 系统设置 → 用户与群组 → 添加用户（标准用户即可），登录该账户
2. 从 Release 页面下载 DMG（**不要**用开发机构建产物，那会跳过 Gatekeeper 环节），
   按上面「安装」一节走一遍，包括「隐私与安全性 → 仍要打开」
3. 重点确认只在首次出现的行为：
   - 扩展默认未启用，需要在 App 里手动开
   - 第一次「运行 AI CLI」弹出自动化权限请求，**拒绝**后确认给出可读提示而不是静默
   - 第一次动作失败时弹出通知权限请求，**拒绝**后确认错误仍进入 App 内错误历史
   - `~/Library/Containers/com.hheelo.RightClick.FinderExtension/` 下的令牌与
     `menu.json` 是被创建出来的，不是从别处继承的
4. 记录结果后删除该用户账户及其个人文件夹

Intel 架构（M2）无法用这种方式替代，需要真机。
