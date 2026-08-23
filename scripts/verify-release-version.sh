#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
candidate="${1:-}"
project_file="${2:-${project_dir}/project.yml}"

if [[ -z "${candidate}" ]]; then
    echo "用法：$0 <版本> [project.yml] [已发布标签…]" >&2
    exit 2
fi
candidate="${candidate#v}"
candidate_build="$(
    "${script_dir}/derive-build-number.sh" "${candidate}"
)"
project_version="$(
    "${script_dir}/read-marketing-version.sh" "${project_file}"
)"

if [[ "${candidate}" != "${project_version}" ]]; then
    echo "发布版本与源码不一致：Tag=${candidate}，project.yml=${project_version}" >&2
    exit 1
fi

# 测试可从第三个参数开始注入标签；正式发布默认读取完整 Git 历史。
if (( $# > 2 )); then
    known_tags=("${@:3}")
else
    known_tags=("${(@f)$(git -C "${project_dir}" tag --list 'v*')}")
fi

latest_build=0
latest_version=""
for tag in "${known_tags[@]}"; do
    version="${tag#v}"
    # 当前 Tag 会出现在 checkout 的标签集合中，不拿自己与自己比较。
    if [[ "${version}" == "${candidate}" ]]; then
        continue
    fi
    if ! build="$(
        "${script_dir}/derive-build-number.sh" "${version}" 2>/dev/null
    )"; then
        continue
    fi
    if (( build > latest_build )); then
        latest_build="${build}"
        latest_version="${version}"
    fi
done

if (( candidate_build <= latest_build )); then
    echo "发布构建号必须递增：${candidate} (${candidate_build}) 不高于 ${latest_version} (${latest_build})" >&2
    exit 1
fi

echo "✓ 发布版本有效：${candidate} (${candidate_build})"
