#!/bin/zsh

set -euo pipefail

# 生成并签名 Sparkle 的 appcast.xml。
#
# 私钥只经标准输入传入（GitHub Secret），不落盘、不出现在命令行参数里
# （命令行参数对同机其他进程可见）。
#
# 用法：
#   echo "$SPARKLE_PRIVATE_KEY" | ./scripts/generate-appcast.sh <dmg> <版本> <构建号> <输出路径>

dmg_path="${1:-}"
version="${2:-}"
build="${3:-}"
output="${4:-}"

if [[ -z "${dmg_path}" || -z "${version}" || -z "${build}" || -z "${output}" ]]; then
    echo "用法：echo \"\$KEY\" | $0 <dmg> <版本> <构建号> <输出路径>" >&2
    exit 2
fi
if [[ ! -f "${dmg_path}" ]]; then
    echo "找不到 DMG：${dmg_path}" >&2
    exit 1
fi

private_key="$(cat)"
if [[ -z "${private_key}" ]]; then
    echo "标准输入没有读到私钥；请确认 SPARKLE_PRIVATE_KEY 已配置" >&2
    exit 1
fi

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
tools_dir="${SPARKLE_TOOLS_DIR:-}"

# 固定版本与校验和：签名工具决定了更新的可信度，不能拉到被篡改的二进制。
sparkle_version="2.9.4"
sparkle_sha256="ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9"

if [[ -z "${tools_dir}" ]]; then
    tools_dir="${project_dir}/.build/sparkle-tools"
    if [[ ! -x "${tools_dir}/bin/sign_update" ]]; then
        echo "→ 下载 Sparkle ${sparkle_version} 工具"
        rm -rf "${tools_dir}"
        mkdir -p "${tools_dir}"
        archive="${tools_dir}/sparkle.tar.xz"
        curl -fsSL -o "${archive}" \
            "https://github.com/sparkle-project/Sparkle/releases/download/${sparkle_version}/Sparkle-${sparkle_version}.tar.xz"
        actual="$(shasum -a 256 "${archive}" | cut -d' ' -f1)"
        if [[ "${actual}" != "${sparkle_sha256}" ]]; then
            echo "Sparkle 工具包校验和不匹配：${actual}" >&2
            exit 1
        fi
        tar -xf "${archive}" -C "${tools_dir}"
    fi
fi

sign_update="${tools_dir}/bin/sign_update"
if [[ ! -x "${sign_update}" ]]; then
    echo "找不到 sign_update：${sign_update}" >&2
    exit 1
fi

echo "→ 签名 $(basename "${dmg_path}")"
signature_attributes="$(
    printf '%s' "${private_key}" | "${sign_update}" --ed-key-file - "${dmg_path}"
)"
if [[ "${signature_attributes}" != *edSignature=* ]]; then
    echo "签名失败：${signature_attributes}" >&2
    exit 1
fi

# 发布前自证：签名必须能被同一把钥匙验回来。
# 实测 sign_update 会用畸形私钥产出「能签但验不过」的签名，只有这一步能拦住；
# 验证成功时它不输出任何内容，所以判据是退出码而不是文本。
signature_value="$(
    printf '%s' "${signature_attributes}" \
        | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p'
)"
if [[ -z "${signature_value}" ]]; then
    echo "无法从签名输出中提取 edSignature：${signature_attributes}" >&2
    exit 1
fi
echo "→ 验证签名"
if ! printf '%s' "${private_key}" \
    | "${sign_update}" --verify "${dmg_path}" "${signature_value}" \
        --ed-key-file -; then
    echo "签名自校验失败：私钥与产出的签名不匹配，不能发布" >&2
    exit 1
fi
echo "  签名有效"

download_url="https://github.com/hheelo/finder_menu_extern/releases/download/v${version}/$(basename "${dmg_path}")"
pub_date="$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")"

mkdir -p "$(dirname "${output}")"
cat > "${output}" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>RightClick</title>
        <link>https://github.com/hheelo/finder_menu_extern</link>
        <description>RightClick 的更新源</description>
        <language>zh</language>
        <item>
            <title>${version}</title>
            <pubDate>${pub_date}</pubDate>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>https://github.com/hheelo/finder_menu_extern/releases/tag/v${version}</sparkle:releaseNotesLink>
            <enclosure url="${download_url}"
                sparkle:version="${build}"
                sparkle:shortVersionString="${version}"
                type="application/octet-stream"
                ${signature_attributes} />
        </item>
    </channel>
</rss>
XML

# XML 坏掉的 appcast 会让所有客户端静默停止更新，发布前必须确认可解析。
xmllint --noout "${output}"

echo "→ appcast 已生成：${output}"