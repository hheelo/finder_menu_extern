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

VERSION=0.7.0 ./scripts/build-release.sh
```

第二条命令会验证 App、Finder 扩展、通用架构、Ad-hoc 签名与 DMG 内容。

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
- 分别测试 Warp、Ghostty、WezTerm、Kitty；Warp/Ghostty 的 AI CLI 菜单应置灰，
  WezTerm/Kitty 应能在所选目录运行命令。再逐一测试新增编辑器与默认应用
- 添加带参数的自定义 CLI，确认 URL 中只有配置 ID、没有命令或参数，并测试含空格、
  单引号的参数按单个参数传递
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

## 存储位置

- Apple Silicon：至少一台当前正式版 macOS
- Intel：至少一台仍受支持的 macOS
- 可选：外置磁盘、网络卷和 iCloud Drive

把验证日期、macOS 版本、CPU 架构以及失败项记录在对应 GitHub Release 或 Issue
中。Intel 与外部卷未验证时，不应在 Release Notes 中声明已全面支持。
