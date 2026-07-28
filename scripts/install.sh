#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
derived_data="${project_dir}/.build/InstallDerivedData"
install_dir="${HOME}/Applications"
installed_app="${install_dir}/RightClick.app"

cd "${project_dir}"

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
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build

built_app="${derived_data}/Build/Products/Release/RightClick.app"
if [[ ! -d "${built_app}" ]]; then
    echo "未找到构建产物：${built_app}" >&2
    exit 1
fi

codesign --verify --deep --strict "${built_app}"
mkdir -p "${install_dir}"

if [[ -d "${installed_app}" ]]; then
    backup_app="${install_dir}/RightClick.backup-$(date +%Y%m%d-%H%M%S).app"
    echo "→ 备份现有版本到 ${backup_app}"
    mv "${installed_app}" "${backup_app}"
fi

echo "→ 安装到 ${installed_app}"
ditto "${built_app}" "${installed_app}"

launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"${launch_services}" -f "${installed_app}"
pluginkit -a "${installed_app}/Contents/PlugIns/RightClickFinderExtension.appex"

echo "→ 启动 RightClick"
open "${installed_app}"

echo
echo "安装完成。请在 RightClick 中点击“启用 Finder 扩展”。"
