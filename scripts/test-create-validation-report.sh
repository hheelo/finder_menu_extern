#!/bin/zsh

set -euo pipefail

test_directory="$(mktemp -d "${TMPDIR:-/tmp}/rightclick-validation-test.XXXXXX")"
trap 'rm -rf "${test_directory}"' EXIT
report_path="${test_directory}/report.md"

./scripts/create-validation-report.sh "${report_path}"

required_text=(
    "# RightClick 真实环境验证报告"
    "macOS"
    "CPU 架构"
    "配置导出/导入成功"
    "iCloud Drive"
    "未验证的环境不得"
)
for text in "${required_text[@]}"; do
    if ! grep -Fq "${text}" "${report_path}"; then
        echo "验证报告缺少内容：${text}" >&2
        exit 1
    fi
done

if ./scripts/create-validation-report.sh "${report_path}" >/dev/null 2>&1; then
    echo "报告生成器不应覆盖已有文件" >&2
    exit 1
fi

permissions="$(stat -f '%Lp' "${report_path}")"
if [[ "${permissions}" != "600" ]]; then
    echo "验证报告权限不是 600：${permissions}" >&2
    exit 1
fi

echo "✓ 验证报告生成器测试通过"
