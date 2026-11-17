#!/bin/bash
# 預設僅做低負擔建置與安全檢查；--snapshots 再產生三語、深淺色與 695pt 小螢幕快照。
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--snapshots" ) ]]; then
    echo "Usage: $0 [--snapshots]" >&2
    exit 2
fi
swift build --jobs "${JOBS:-2}" -Xswiftc -warnings-as-errors
MEMORYBUTLER_SELFTEST=checks .build/debug/MemoryButler
if [[ "${1:-}" == "--snapshots" ]]; then
    OUT="$(mktemp -d "${TMPDIR:-/tmp}/memorybutler-verify.XXXXXX")"
    for LANG in en zh-Hans zh-Hant; do
        for DARK in 0 1; do
            SHOTS="$OUT/$LANG-$DARK"
            mkdir -p "$SHOTS"
            MEMORYBUTLER_SELFTEST=1 \
            MEMORYBUTLER_SNAPSHOT_DIR="$SHOTS" \
            MEMORYBUTLER_SNAPSHOT_LANGUAGE="$LANG" \
            MEMORYBUTLER_SNAPSHOT_DARK="$DARK" \
            MEMORYBUTLER_SNAPSHOT_SCREEN_HEIGHT=695 \
            MEMORYBUTLER_SNAPSHOT_DEMO=2 \
            .build/debug/MemoryButler > "$SHOTS/run.log" 2>&1
            test "$(find "$SHOTS" -name '*.png' | wc -l | tr -d ' ')" -eq 9
            echo "✓ $LANG dark=$DARK: 9 snapshots and all tab layouts checked"
        done
    done
    echo "Snapshots: $OUT"
fi
