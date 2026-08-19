#!/bin/zsh

set -euo pipefail

app_path="${1:-}"
if [[ -z "${app_path}" || ! -d "${app_path}" ]]; then
    echo "用法：$0 /path/to/RightClick.app" >&2
    exit 2
fi

executable="${app_path}/Contents/MacOS/RightClick"
if [[ ! -x "${executable}" ]]; then
    echo "App 缺少可执行文件：${executable}" >&2
    exit 1
fi

smoke_directory="$(mktemp -d "${TMPDIR:-/tmp}/rightclick-smoke.XXXXXX")"
ready_file="${smoke_directory}/ready"
log_file="${smoke_directory}/launch.log"
process_id=""

cleanup() {
    if [[ -n "${process_id}" ]] && kill -0 "${process_id}" 2>/dev/null; then
        kill -TERM "${process_id}" 2>/dev/null || true
        for _ in {1..30}; do
            if ! kill -0 "${process_id}" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        if kill -0 "${process_id}" 2>/dev/null; then
            kill -KILL "${process_id}" 2>/dev/null || true
        fi
        wait "${process_id}" 2>/dev/null || true
    fi
    rm -f "${ready_file}" "${log_file}"
    rmdir "${smoke_directory}" 2>/dev/null || true
}
trap cleanup EXIT

RIGHTCLICK_UI_TESTING=1 \
RIGHTCLICK_SMOKE_TEST_DIRECTORY="${smoke_directory}" \
    "${executable}" >"${log_file}" 2>&1 &
process_id=$!

for _ in {1..100}; do
    if [[ -f "${ready_file}" ]]; then
        echo "✓ 签名 App 启动并完成首屏呈现"
        exit 0
    fi
    if ! kill -0 "${process_id}" 2>/dev/null; then
        wait "${process_id}" 2>/dev/null || true
        process_id=""
        echo "App 在首屏呈现前退出" >&2
        sed -n '1,120p' "${log_file}" >&2
        exit 1
    fi
    sleep 0.1
done

echo "App 启动后 10 秒内未完成首屏呈现" >&2
sed -n '1,120p' "${log_file}" >&2
exit 1
