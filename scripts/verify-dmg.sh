#!/bin/zsh

set -euo pipefail

dmg_path="${1:-}"
if [[ -z "${dmg_path}" || ! -f "${dmg_path}" ]]; then
    echo "用法：$0 /path/to/RightClick.dmg" >&2
    exit 2
fi

mount_point="$(mktemp -d "${TMPDIR:-/tmp}/rightclick-dmg.XXXXXX")"
attached=false

cleanup() {
    mounted_extension="${mount_point}/RightClick.app/Contents/PlugIns/RightClickFinderExtension.appex"
    if [[ -d "${mounted_extension}" ]]; then
        pluginkit -r "${mounted_extension}" >/dev/null 2>&1 || true
    fi
    if [[ "${attached}" == true ]]; then
        hdiutil detach "${mount_point}" -quiet || true
    fi
    rmdir "${mount_point}" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach \
    -nobrowse \
    -readonly \
    -mountpoint "${mount_point}" \
    "${dmg_path}" \
    -quiet
attached=true

"${0:A:h}/verify-app.sh" "${mount_point}/RightClick.app"

if [[ ! -L "${mount_point}/Applications" ]]; then
    echo "DMG 缺少 Applications 快捷方式" >&2
    exit 1
fi

echo "✓ DMG 挂载与内容验证通过"
