#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
if [[ -z "${VERSION:-}" ]]; then
    echo "缺少 VERSION；用法：VERSION=0.5.3 $0" >&2
    exit 2
fi
version="${VERSION}"
version="${version#v}"

# Tag 必须与源码声明一致，且构建号高于所有既有发布标签。否则 Sparkle 会
# 忽略回退版本，而源码与二进制版本漂移也会让下一次发布难以恢复。
"${script_dir}/verify-release-version.sh" "${version}"

# CFBundleVersion 必须逐次发布单调递增：宿主 App 用「短版本号 + 构建号」
# 判断升级后是否需要重新加载 Finder，而 LaunchServices 也依赖它区分版本。
# 从 semver 推导，例如 0.2.5 → 205、1.0.0 → 10000（要求各段小于 100）。
build_number="$("${script_dir}/derive-build-number.sh" "${version}")"

release_root="${project_dir}/.build/release"
derived_data="${project_dir}/.build/ReleaseDerivedData"
staging_dir="${release_root}/staging"
output_dir="${release_root}/output"
dmg_name="RightClick-${version}.dmg"
built_app="${derived_data}/Build/Products/Release/RightClick.app"
built_extension="${built_app}/Contents/PlugIns/RightClickFinderExtension.appex"
staged_app="${staging_dir}/RightClick.app"
staged_extension="${staged_app}/Contents/PlugIns/RightClickFinderExtension.appex"

unregister_build_extensions() {
    if [[ -d "${built_extension}" ]]; then
        pluginkit -r "${built_extension}" >/dev/null 2>&1 || true
    fi
    if [[ -d "${staged_extension}" ]]; then
        pluginkit -r "${staged_extension}" >/dev/null 2>&1 || true
    fi
}
trap unregister_build_extensions EXIT

if [[ "${release_root}" != "${project_dir}/.build/release" ]]; then
    echo "拒绝清理非预期目录：${release_root}" >&2
    exit 1
fi

cd "${project_dir}"

rm -rf "${release_root}" "${derived_data}"
mkdir -p "${staging_dir}" "${output_dir}"

xcodebuild \
    -quiet \
    -project RightClick.xcodeproj \
    -scheme RightClick \
    -configuration Release \
    -derivedDataPath "${derived_data}" \
    MARKETING_VERSION="${version}" \
    CURRENT_PROJECT_VERSION="${build_number}" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build

EXPECT_VERSION="${version}" EXPECT_BUILD="${build_number}" \
    "${project_dir}/scripts/verify-app.sh" "${built_app}"

ditto "${built_app}" "${staged_app}"
ln -s /Applications "${staging_dir}/Applications"

hdiutil create \
    -volname "RightClick" \
    -srcfolder "${staging_dir}" \
    -ov \
    -format UDZO \
    "${output_dir}/${dmg_name}"

(
    cd "${output_dir}"
    shasum -a 256 "${dmg_name}" > "${dmg_name}.sha256"
)

"${project_dir}/scripts/verify-dmg.sh" "${output_dir}/${dmg_name}"

unregister_build_extensions
if [[ "${derived_data}" != "${project_dir}/.build/ReleaseDerivedData" ||
      "${staging_dir}" != "${project_dir}/.build/release/staging" ]]; then
    echo "拒绝清理非预期构建目录" >&2
    exit 1
fi
rm -rf "${derived_data}" "${staging_dir}"
trap - EXIT

echo "Release 产物："
echo "  ${output_dir}/${dmg_name}"
echo "  ${output_dir}/${dmg_name}.sha256"
