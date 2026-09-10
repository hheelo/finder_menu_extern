#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "用法: $0 <result.xcresult>" >&2
  exit 2
fi

result_bundle="$1"
if [ ! -d "${result_bundle}" ]; then
  echo "覆盖率结果不存在：${result_bundle}" >&2
  exit 2
fi

report_file="$(mktemp "${TMPDIR:-/tmp}/rightclick-coverage.XXXXXX")"
trap 'rm -f "${report_file}"' EXIT
xcrun xccov view --report --json "${result_bundle}" > "${report_file}"

/usr/bin/python3 - "${report_file}" <<'PY'
import json
import sys

thresholds = {
    "RightClickCore.framework": 92.0,
    "RightClickAppLogic.framework": 88.0,
    "RightClickAppServices.framework": 70.0,
    "RightClickFinderAdapter.framework": 92.0,
}

with open(sys.argv[1], encoding="utf-8") as report:
    payload = json.load(report)

targets = {target["name"]: target for target in payload.get("targets", [])}
failures = []
for name, minimum in thresholds.items():
    target = targets.get(name)
    if target is None:
        failures.append(f"{name}: 覆盖率结果缺失")
        continue
    percentage = float(target.get("lineCoverage", 0)) * 100
    print(f"{name}: {percentage:.2f}%（门槛 {minimum:.2f}%）")
    if percentage + 1e-9 < minimum:
        failures.append(
            f"{name}: {percentage:.2f}% 低于 {minimum:.2f}%"
        )

if failures:
    print("\n覆盖率门禁失败：", file=sys.stderr)
    for failure in failures:
        print(f"- {failure}", file=sys.stderr)
    raise SystemExit(1)

print("覆盖率门禁通过")
PY
