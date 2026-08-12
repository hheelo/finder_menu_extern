#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_file="${1:-${script_dir:h}/project.yml}"

marketing_version="$(sed -n \
    's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*//p' \
    "${project_file}" | head -n 1)"
marketing_version="${marketing_version#\"}"
marketing_version="${marketing_version%\"}"
marketing_version="${marketing_version#\'}"
marketing_version="${marketing_version%\'}"

if [[ -z "${marketing_version}" ]]; then
    echo "无法从 ${project_file} 读取 MARKETING_VERSION" >&2
    exit 1
fi

print -r -- "${marketing_version}"
