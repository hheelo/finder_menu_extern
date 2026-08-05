#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
destination="${1:?用法：$0 <安装目录>}"
version="$(tr -d '[:space:]' < "${project_dir}/.xcodegen-version")"
expected_sha256="$(tr -d '[:space:]' < "${project_dir}/.xcodegen-sha256")"
archive="${destination}/xcodegen.zip"
binary="${destination}/xcodegen/bin/xcodegen"

mkdir -p "${destination}"
curl --fail --location \
    --output "${archive}" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/${version}/xcodegen.zip"
printf '%s  %s\n' "${expected_sha256}" "${archive}" | shasum -a 256 --check
ditto -x -k "${archive}" "${destination}"

installed_version="$("${binary}" --version | sed -n 's/^Version: //p')"
if [[ "${installed_version}" != "${version}" ]]; then
    echo "下载的 XcodeGen 版本不一致：需要 ${version}，实际 ${installed_version:-未知}。" >&2
    exit 1
fi
