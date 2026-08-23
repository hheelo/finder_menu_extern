#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
temporary_project="$(mktemp "${TMPDIR:-/tmp}/rightclick-version.XXXXXX")"
trap 'rm -f "${temporary_project}"' EXIT

printf 'MARKETING_VERSION: 1.0.10\n' > "${temporary_project}"
"${script_dir}/verify-release-version.sh" \
    1.0.10 "${temporary_project}" v1.0.9 >/dev/null

if "${script_dir}/verify-release-version.sh" \
    1.0.9 "${temporary_project}" v1.0.8 >/dev/null 2>&1; then
    echo "版本与源码不一致时本应失败" >&2
    exit 1
fi

printf 'MARKETING_VERSION: 1.0.9\n' > "${temporary_project}"
if "${script_dir}/verify-release-version.sh" \
    1.0.9 "${temporary_project}" v1.0.10 >/dev/null 2>&1; then
    echo "构建号回退时本应失败" >&2
    exit 1
fi

printf 'MARKETING_VERSION: 1.0.11\n' > "${temporary_project}"
"${script_dir}/verify-release-version.sh" \
    1.0.11 "${temporary_project}" v1.0.10 >/dev/null

echo "Release version validation verified."
