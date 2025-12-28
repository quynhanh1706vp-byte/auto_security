#!/usr/bin/env bash
set -euo pipefail
LOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log"

echo "[INFO] Last 200 lines: $LOG"
echo "------------------------------------------------------------"
tail -n 200 "$LOG" || true
echo "------------------------------------------------------------"
echo "[INFO] Quick grep (Traceback / SyntaxError / ImportError):"
grep -nE "Traceback|SyntaxError|IndentationError|ImportError|ModuleNotFoundError" "$LOG" | tail -n 30 || true
