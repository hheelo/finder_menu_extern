#!/bin/zsh

set -euo pipefail

report_path="${1:-}"
artifact_path="${2:-}"

if [[ -z "${report_path}" ]]; then
    echo "用法：$0 /path/to/report.md [/path/to/RightClick.app-or-dmg]" >&2
    exit 2
fi
if [[ -e "${report_path}" ]]; then
    echo "报告已存在，不会覆盖：${report_path}" >&2
    exit 1
fi
if [[ -n "${artifact_path}" && ! -e "${artifact_path}" ]]; then
    echo "构建产物不存在：${artifact_path}" >&2
    exit 1
fi

report_directory="${report_path:h}"
mkdir -p "${report_directory}"
temporary_report="$(mktemp "${TMPDIR:-/tmp}/rightclick-validation.XXXXXX")"
trap 'rm -f "${temporary_report}"' EXIT

validation_date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
macos_version="$(sw_vers -productVersion)"
macos_build="$(sw_vers -buildVersion)"
architecture="$(uname -m)"
machine_model="$(sysctl -n hw.model 2>/dev/null || echo unknown)"
artifact_name="未提供（请在提交报告前补充）"
artifact_sha256="未提供"
app_version="未提供"
app_build="未提供"
signature_result="未检查"

if [[ -n "${artifact_path}" ]]; then
    artifact_name="${artifact_path:t}"
    if [[ -f "${artifact_path}" ]]; then
        artifact_sha256="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
    elif [[ -d "${artifact_path}" && "${artifact_path:e}" == "app" ]]; then
        info_plist="${artifact_path}/Contents/Info.plist"
        if [[ -f "${info_plist}" ]]; then
            app_version="$(plutil -extract CFBundleShortVersionString raw -o - "${info_plist}" 2>/dev/null || echo unknown)"
            app_build="$(plutil -extract CFBundleVersion raw -o - "${info_plist}" 2>/dev/null || echo unknown)"
        fi
        if codesign --verify --deep --strict "${artifact_path}" >/dev/null 2>&1; then
            signature_result="通过 codesign --verify（不代表 Developer ID 或公证）"
        else
            signature_result="未通过 codesign --verify"
        fi
    fi
fi

cat > "${temporary_report}" <<EOF
# RightClick 真实环境验证报告

> 这份报告只采集系统版本、硬件型号与构建元数据，不采集用户名、主机名、文件路径或菜单内容。

## 环境与产物

| 字段 | 值 |
| --- | --- |
| 验证时间（UTC） | ${validation_date} |
| macOS | ${macos_version} (${macos_build}) |
| CPU 架构 | ${architecture} |
| 机型标识 | ${machine_model} |
| 产物 | ${artifact_name} |
| App 版本 | ${app_version} (${app_build}) |
| SHA-256 | ${artifact_sha256} |
| 本地签名检查 | ${signature_result} |
| 测试者 | 待填写 |
| 安装来源 | GitHub Release DMG / 本地候选包（删除不适用项） |
| 账户状态 | 全新标准用户 / 已有用户（删除不适用项） |

## 核心验收

- [ ] 校验下载 SHA-256，从 DMG 拖入 Applications；首次启动的 Gatekeeper 行为与发布说明一致
- [ ] 手动启用 Finder 扩展；桌面、Finder 项目、窗口空白处和侧边栏均出现正确菜单
- [ ] 保留旧选区后右键空白处/侧边栏，动作仍作用于右键目标而不是残留选区
- [ ] 复制路径、文件名、file URL、Shell 路径、父目录和多选分隔符结果正确
- [ ] 菜单启用、排序、子菜单、终端、CLI 与模板设置在下一次右键立即生效
- [ ] 七种内置模板、自定义模板、新建文件夹及剪贴板新建均不覆盖同名文件
- [ ] 配置导出/导入成功；损坏配置进入恢复状态、生成备份，且不会被默认配置静默覆盖
- [ ] Terminal/iTerm2 和已安装的编辑器可用；缺失应用与权限拒绝均给出可读提示且不抢焦点
- [ ] 首次 Finder 深链冷启动不闪现窗口；随后双击 App 才显示向导/主窗口
- [ ] 设置、菜单栏、窗口恢复、更新检查与 Finder 重启确认流程正常
- [ ] 简体中文与英文下 App 文案、Finder 菜单、模板默认内容和错误提示完整且无明显裁切
- [ ] VoiceOver 标签、仅键盘操作、最大系统字号和最小窗口尺寸可用
- [ ] 50 个自定义模板、200 条日志、128 个目标时无可感知菜单卡顿；129 个目标被完整拒绝
- [ ] 正常退出不产生异常终止记录；强制结束后只记录 unexpected-termination

## 存储位置专项

| 位置 | 状态 | 备注 |
| --- | --- | --- |
| 本地 APFS | 未验证 | |
| iCloud Drive | 未验证 / 不适用 | |
| 外置磁盘 | 未验证 / 不适用 | 记录格式与连接方式 |
| 网络卷 | 未验证 / 不适用 | 记录协议，不记录服务器地址 |

## 权限专项

| 场景 | 允许 | 拒绝 | 结果/备注 |
| --- | --- | --- | --- |
| Finder 扩展 | 未验证 | 未验证 | |
| Terminal 自动化 | 未验证 | 未验证 | |
| 辅助功能（Terminal 新标签页） | 未验证 | 未验证 | |
| 通知 | 未验证 | 未验证 | |

## 问题记录

| 严重级别 | 步骤 | 预期 | 实际 | 附件/Issue |
| --- | --- | --- | --- | --- |
| | | | | |

## 结论

- [ ] 通过：没有阻断发布的问题
- [ ] 有条件通过：仅存在已记录且不阻断发布的问题
- [ ] 不通过：存在阻断问题

未验证的环境不得在 Release Notes 中声明为已全面支持。完整长清单见 \`docs/TESTING.md\`。
EOF

chmod 600 "${temporary_report}"
mv "${temporary_report}" "${report_path}"
trap - EXIT
echo "✓ 已创建验证报告：${report_path}"
