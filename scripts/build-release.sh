#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
version="${VERSION:-0.1.0}"
version="${version#v}"
release_root="${project_dir}/.build/release"
derived_data="${project_dir}/.build/ReleaseDerivedData"
staging_dir="${release_root}/staging"
output_dir="${release_root}/output"
dmg_name="RightClick-${version}.dmg"

if [[ "${release_root}" != "${project_dir}/.build/release" ]]; then
    echo "拒绝清理非预期目录：${release_root}" >&2
    exit 1
fi

cd "${project_dir}"

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
fi

rm -rf "${release_root}" "${derived_data}"
mkdir -p "${staging_dir}" "${output_dir}"

xcodebuild \
    -quiet \
    -project RightClick.xcodeproj \
    -scheme RightClick \
    -configuration Release \
    -derivedDataPath "${derived_data}" \
    MARKETING_VERSION="${version}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build

built_app="${derived_data}/Build/Products/Release/RightClick.app"
codesign --verify --deep --strict "${built_app}"

ditto "${built_app}" "${staging_dir}/RightClick.app"
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

echo "Release 产物："
echo "  ${output_dir}/${dmg_name}"
echo "  ${output_dir}/${dmg_name}.sha256"
