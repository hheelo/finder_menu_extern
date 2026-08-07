#!/bin/zsh

set -euo pipefail

version="${1#v}"
if [[ "${version}" != <->.<->.<-> ]]; then
    echo "版本号必须是 major.minor.patch：${version}" >&2
    exit 2
fi

major="${version%%.*}"
remainder="${version#*.}"
minor="${remainder%%.*}"
patch="${remainder#*.}"
for part in "${major}" "${minor}" "${patch}"; do
    if [[ "${part}" != "0" && "${part}" == 0* ]]; then
        echo "版本号不能包含前导零：${version}" >&2
        exit 2
    fi
done
if (( major >= 100 || minor >= 100 || patch >= 100 )); then
    echo "版本号每一段必须小于 100：${version}" >&2
    exit 2
fi

build_number="$((major * 10000 + minor * 100 + patch))"
if (( build_number <= 0 )); then
    echo "构建号必须大于零：${version}" >&2
    exit 2
fi
printf '%d' "${build_number}"
