#!/bin/zsh

set -euo pipefail

app_path="${1:-}"
if [[ -z "${app_path}" || ! -d "${app_path}" ]]; then
    echo "用法：$0 /path/to/RightClick.app" >&2
    exit 2
fi

extension_path="${app_path}/Contents/PlugIns/RightClickFinderExtension.appex"
core_path="${app_path}/Contents/Frameworks/RightClickCore.framework"
sparkle_path="${app_path}/Contents/Frameworks/Sparkle.framework"
icon_path="${app_path}/Contents/Resources/AppIcon.icns"
extension_core_path="${extension_path}/Contents/Frameworks/RightClickCore.framework"

if [[ ! -d "${extension_path}" ||
      ! -d "${core_path}" ||
      ! -d "${extension_core_path}" ||
      ! -d "${sparkle_path}" ||
      ! -f "${icon_path}" ]]; then
    echo "App 缺少 Finder 扩展、RightClickCore/Sparkle.framework 或 AppIcon" >&2
    exit 1
fi

# 本地化资源必须同时存在于宿主和扩展各自嵌入的 Core framework 中。
# 只检查宿主副本会漏掉 Finder 菜单退回硬编码文案的打包回归。
localized_resources=(
    "${app_path}/Contents/Resources/en.lproj/InfoPlist.strings"
    "${app_path}/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
    "${core_path}/Resources/en.lproj/Localizable.strings"
    "${core_path}/Resources/zh-Hans.lproj/Localizable.strings"
    "${extension_core_path}/Resources/en.lproj/Localizable.strings"
    "${extension_core_path}/Resources/zh-Hans.lproj/Localizable.strings"
)
for resource in "${localized_resources[@]}"; do
    if [[ ! -f "${resource}" ]]; then
        echo "App 缺少本地化资源：${resource}" >&2
        exit 1
    fi
done

codesign --verify --deep --strict "${app_path}"

app_id="$(plutil -extract CFBundleIdentifier raw -o - "${app_path}/Contents/Info.plist")"
extension_id="$(plutil -extract CFBundleIdentifier raw -o - "${extension_path}/Contents/Info.plist")"
app_version="$(plutil -extract CFBundleShortVersionString raw -o - "${app_path}/Contents/Info.plist")"
extension_version="$(plutil -extract CFBundleShortVersionString raw -o - "${extension_path}/Contents/Info.plist")"
app_build="$(plutil -extract CFBundleVersion raw -o - "${app_path}/Contents/Info.plist")"
extension_build="$(plutil -extract CFBundleVersion raw -o - "${extension_path}/Contents/Info.plist")"
icon_name="$(plutil -extract CFBundleIconName raw -o - "${app_path}/Contents/Info.plist")"
apple_events_usage="$(plutil -extract NSAppleEventsUsageDescription raw -o - "${app_path}/Contents/Info.plist" 2>/dev/null || true)"
feed_url="$(plutil -extract SUFeedURL raw -o - "${app_path}/Contents/Info.plist" 2>/dev/null || true)"
public_key="$(plutil -extract SUPublicEDKey raw -o - "${app_path}/Contents/Info.plist" 2>/dev/null || true)"

if [[ "${app_id}" != "com.hheelo.RightClick" ]]; then
    echo "宿主 Bundle ID 不正确：${app_id}" >&2
    exit 1
fi
if [[ "${extension_id}" != "com.hheelo.RightClick.FinderExtension" ]]; then
    echo "扩展 Bundle ID 不正确：${extension_id}" >&2
    exit 1
fi
if [[ "${app_version}" != "${extension_version}" ]]; then
    echo "宿主与扩展版本不一致：${app_version} / ${extension_version}" >&2
    exit 1
fi
if [[ "${app_build}" != "${extension_build}" ]]; then
    echo "宿主与扩展构建号不一致：${app_build} / ${extension_build}" >&2
    exit 1
fi
# 构建号必须随发布递增，否则升级后宿主不会重新加载 Finder。
if [[ ! "${app_build}" =~ ^[0-9]+$ ]] || (( app_build <= 0 )); then
    echo "构建号不是正整数：${app_build}" >&2
    exit 1
fi
if [[ -n "${EXPECT_VERSION:-}" && "${app_version}" != "${EXPECT_VERSION}" ]]; then
    echo "版本号与预期不符：${app_version}，预期 ${EXPECT_VERSION}" >&2
    exit 1
fi
if [[ -n "${EXPECT_BUILD:-}" && "${app_build}" != "${EXPECT_BUILD}" ]]; then
    echo "构建号与预期不符：${app_build}，预期 ${EXPECT_BUILD}" >&2
    exit 1
fi
# App 通过 osascript 控制 Terminal / iTerm2，缺少用途说明时授权弹窗没有理由，
# 且启用硬化运行时后会被系统拒绝。
if [[ -z "${apple_events_usage}" ]]; then
    echo "Info.plist 缺少 NSAppleEventsUsageDescription" >&2
    exit 1
fi
# 更新源与公钥缺一不可：公钥缺失时 Sparkle 会拒绝一切更新，
# 而占位或错误的公钥会让所有已安装用户永久卡在当前版本。
if [[ -z "${feed_url}" ]]; then
    echo "Info.plist 缺少 SUFeedURL" >&2
    exit 1
fi
if [[ "${public_key}" != "zSS8u0opcEchcZsZKN37gHgs60sOf+c/bOiwyejzX9I=" ]]; then
    echo "SUPublicEDKey 不是预期的公钥：${public_key}" >&2
    exit 1
fi
if [[ "${icon_name}" != "AppIcon" ]]; then
    echo "AppIcon 配置不正确：${icon_name}" >&2
    exit 1
fi

binaries=(
    "${app_path}/Contents/MacOS/RightClick"
    "${extension_path}/Contents/MacOS/RightClickFinderExtension"
    "${core_path}/Versions/A/RightClickCore"
    "${sparkle_path}/Sparkle"
    # 真正执行更新安装的助手；单架构会让另一半用户的更新失败
    "${sparkle_path}/Autoupdate"
)

for binary in "${binaries[@]}"; do
    architectures="$(lipo -archs "${binary}")"
    if [[ " ${architectures} " != *" arm64 "* ||
          " ${architectures} " != *" x86_64 "* ]]; then
        echo "二进制不是 Universal 2：${binary} (${architectures})" >&2
        exit 1
    fi
done

echo "✓ App 验证通过：${app_version} (${app_build})，Universal 2，Ad-hoc 签名有效"
