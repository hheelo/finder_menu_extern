#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
required_version="$(tr -d '[:space:]' < "${project_dir}/.xcodegen-version")"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "缺少 XcodeGen ${required_version}。" >&2
    exit 1
fi

installed_version="$(xcodegen --version | sed -n 's/^Version: //p')"
if [[ "${installed_version}" != "${required_version}" ]]; then
    echo "XcodeGen 版本不一致：需要 ${required_version}，当前 ${installed_version:-未知}。" >&2
    exit 1
fi

cd "${project_dir}"
xcodegen generate --quiet

generated_paths=(
    RightClick.xcodeproj
    Configuration/RightClick-Info.plist
    Configuration/RightClickFinderExtension-Info.plist
    Configuration/RightClickFinderExtension.entitlements
)

if ! git diff --quiet -- "${generated_paths[@]}"; then
    echo "Xcode 工程与 project.yml 不一致。" >&2
    echo "请使用 XcodeGen ${required_version} 运行 xcodegen generate 并提交结果。" >&2
    git diff --stat -- "${generated_paths[@]}" >&2
    exit 1
fi
