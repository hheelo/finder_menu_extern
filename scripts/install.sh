#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
derived_data="${project_dir}/.build/InstallDerivedData"
install_dir="${HOME}/Applications"
installed_app="${install_dir}/RightClick.app"
system_installed_app="/Applications/RightClick.app"
installed_extension="${installed_app}/Contents/PlugIns/RightClickFinderExtension.appex"
built_app="${derived_data}/Build/Products/Release/RightClick.app"
built_extension="${built_app}/Contents/PlugIns/RightClickFinderExtension.appex"
backup_dir="${HOME}/Library/Application Support/RightClick/Backups"
launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
marketing_version="$(sed -n \
    's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*//p' \
    "${project_dir}/project.yml" | head -n 1)"
if [[ -z "${marketing_version}" ]]; then
    echo "无法从 project.yml 读取 MARKETING_VERSION" >&2
    exit 1
fi
build_number="$(
    "${script_dir}/derive-build-number.sh" "${marketing_version}"
)"

unregister_build_extension() {
    if [[ -d "${built_extension}" ]]; then
        pluginkit -r "${built_extension}" >/dev/null 2>&1 || true
    fi
}
trap unregister_build_extension EXIT

cd "${project_dir}"

# DMG 通常安装到 /Applications，而本脚本安装到 ~/Applications。两份相同
# Bundle ID 的 Finder 扩展并存时，Finder 可能继续加载旧副本。不要擅自删除
# 系统 Applications 中的 App；在耗时构建开始前中止并让用户明确选择一种方式。
if [[ -d "${system_installed_app}" &&
      "${system_installed_app}" != "${installed_app}" ]]; then
    echo "检测到另一份 RightClick：${system_installed_app}" >&2
    echo "为避免 Finder 扩展冲突，请先移除该版本，或继续使用 DMG/Sparkle 更新。" >&2
    exit 1
fi

if command -v xcodegen >/dev/null 2>&1; then
    echo "→ 生成 Xcode 工程"
    xcodegen generate
else
    echo "→ 未安装 XcodeGen，使用仓库中已生成的工程"
fi

echo "→ 构建并进行 Ad-hoc 签名"
xcodebuild \
    -quiet \
    -project RightClick.xcodeproj \
    -scheme RightClick \
    -configuration Release \
    -derivedDataPath "${derived_data}" \
    MARKETING_VERSION="${marketing_version}" \
    CURRENT_PROJECT_VERSION="${build_number}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build

if [[ ! -d "${built_app}" ]]; then
    echo "未找到构建产物：${built_app}" >&2
    exit 1
fi

codesign --verify --deep --strict "${built_app}"
mkdir -p "${install_dir}"

if [[ -d "${installed_app}" ]]; then
    mkdir -p "${backup_dir}"
    backup_zip="${backup_dir}/RightClick-$(date +%Y%m%d-%H%M%S).zip"
    echo "→ 注销并归档现有版本"
    pluginkit -r "${installed_extension}" >/dev/null 2>&1 || true
    "${launch_services}" -u "${installed_app}" >/dev/null 2>&1 || true
    ditto -c -k --sequesterRsrc --keepParent \
        "${installed_app}" \
        "${backup_zip}"
    unzip -tq "${backup_zip}"

    if [[ "${installed_app}" != "${HOME}/Applications/RightClick.app" ]]; then
        echo "拒绝移除非预期路径：${installed_app}" >&2
        exit 1
    fi
    rm -rf "${installed_app}"
    echo "  旧版本备份：${backup_zip}"
fi

echo "→ 安装到 ${installed_app}"
ditto "${built_app}" "${installed_app}"

"${launch_services}" -f "${installed_app}"
pluginkit -a "${installed_app}/Contents/PlugIns/RightClickFinderExtension.appex"

echo "→ 启动 RightClick"
open "${installed_app}"

unregister_build_extension
if [[ "${derived_data}" != "${project_dir}/.build/InstallDerivedData" ]]; then
    echo "拒绝清理非预期构建目录：${derived_data}" >&2
    exit 1
fi
rm -rf "${derived_data}"
trap - EXIT

echo
echo "安装完成。请在 RightClick 中点击“启用 Finder 扩展”。"
echo "如果 Finder 仍显示旧菜单，请在 App 中点击“重启 Finder”。"
