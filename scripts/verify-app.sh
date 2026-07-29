#!/bin/zsh

set -euo pipefail

app_path="${1:-}"
if [[ -z "${app_path}" || ! -d "${app_path}" ]]; then
    echo "用法：$0 /path/to/RightClick.app" >&2
    exit 2
fi

extension_path="${app_path}/Contents/PlugIns/RightClickFinderExtension.appex"
core_path="${app_path}/Contents/Frameworks/RightClickCore.framework"

if [[ ! -d "${extension_path}" || ! -d "${core_path}" ]]; then
    echo "App 缺少 Finder 扩展或 RightClickCore.framework" >&2
    exit 1
fi

codesign --verify --deep --strict "${app_path}"

app_id="$(plutil -extract CFBundleIdentifier raw -o - "${app_path}/Contents/Info.plist")"
extension_id="$(plutil -extract CFBundleIdentifier raw -o - "${extension_path}/Contents/Info.plist")"
app_version="$(plutil -extract CFBundleShortVersionString raw -o - "${app_path}/Contents/Info.plist")"
extension_version="$(plutil -extract CFBundleShortVersionString raw -o - "${extension_path}/Contents/Info.plist")"

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

binaries=(
    "${app_path}/Contents/MacOS/RightClick"
    "${extension_path}/Contents/MacOS/RightClickFinderExtension"
    "${core_path}/Versions/A/RightClickCore"
)

for binary in "${binaries[@]}"; do
    architectures="$(lipo -archs "${binary}")"
    if [[ " ${architectures} " != *" arm64 "* ||
          " ${architectures} " != *" x86_64 "* ]]; then
        echo "二进制不是 Universal 2：${binary} (${architectures})" >&2
        exit 1
    fi
done

echo "✓ App 验证通过：${app_version}，Universal 2，Ad-hoc 签名有效"
