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

VERSION=0.8.1 ./scripts/build-release.sh
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
- 逐一创建七种文件，确认同名文件不会覆盖
- 快速连续创建同一种文件，确认并发占用名称时会重选名且不会覆盖
- 测试 VS Code / ChatGPT 存在与缺失两种状态，确认菜单与诊断显示 ChatGPT
- 测试 Codex CLI / Claude Code 存在与缺失两种状态
- 分别将登录 Shell 设为 zsh/bash、fish 和 Nushell，刷新诊断，确认
  面板显示真实 Shell 路径且能找到该 Shell 环境中的 CLI
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
- 触发 CLI 动作，确认终端在正确目录启动，RightClick 不切到前台、不增加窗口，
  界面也不会短暂闪现
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
- 在设置里禁用、排序菜单项并切换 RightClick 子菜单，确认下一次右键立即生效
- 确认所有内置、自定义 CLI 和自定义模板菜单项都带有可读的
  SF Symbols 图标，置灰时图标与文字状态一致
- 分别测试 Warp、Ghostty、WezTerm、Kitty；Warp/Ghostty 的 AI CLI 菜单应置灰，
  WezTerm/Kitty 应能在所选目录运行命令。再逐一测试新增编辑器与默认应用
- 添加带参数的自定义 CLI，分别测试 PATH 命令名与含空格的绝对路径；确认 URL 中
  只有配置 ID、没有命令或参数，并测试含空格、单引号的参数按单个参数传递
- 向 `~/Library/Application Support/RightClick/Templates/` 放入普通文件、子目录和
  符号链接，刷新后确认只出现普通文件；创建结果保留内容且不覆盖同名文件
- 测试新建文件夹与从文本剪贴板新建文件；空剪贴板不得写入空文件
- 卸载 VS Code 后触发“用 VS Code 打开”，确认收到本地通知、错误进入最近 10 条
  历史，并且 RightClick 不抢焦点；拒绝通知权限时仍应保留错误历史
- 右键 `/Applications` 中的 App 新建 TXT，确认目标是 App 的父目录（或收到权限
  错误），绝不能写入 `.app` 包内部
- 右键 `.xcodeproj` 后“在终端中打开”，确认终端目录是工程包的父目录
- 升级旧版本，确认 Applications 中只留下一个 RightClick.app
- 保持 Finder 运行并升级旧版本；启动新 App 后确认 Finder 自动退出并重新打开，
  且右键菜单加载的是新扩展
- 运行 `pluginkit -m -A -D -v -i com.hheelo.RightClick.FinderExtension`，
  确认只列出 Applications 中的一份扩展

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
