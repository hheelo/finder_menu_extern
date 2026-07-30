#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
source_image="${project_dir}/Resources/AppIcon/RightClick-AppIcon-transparent.png"
output_dir="${project_dir}/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "${source_image}" ]]; then
    echo "缺少图标源文件：${source_image}" >&2
    exit 1
fi

mkdir -p "${output_dir}"

sizes=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for entry in "${sizes[@]}"; do
    size="${entry%%:*}"
    filename="${entry#*:}"
    sips -s format png -z "${size}" "${size}" "${source_image}" \
        --out "${output_dir}/${filename}" >/dev/null
done

echo "✓ 已生成 macOS AppIcon 资源"
