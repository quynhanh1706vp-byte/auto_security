#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PYF" "$PYF.bak_log_once_${TS}"
echo "[BACKUP] $PYF.bak_log_once_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

# Nếu đã có guard thì thôi
if "_VSP_RUN_API_LOG_ONCE" in txt:
    print("[INFO] log-once guard already present; skip")
else:
    # Bọc mọi print chứa "[VSP_RUN_API] OK registered"
    pat = r'(^[ \t]*print\(\s*[\'"]\[VSP_RUN_API\]\s+OK registered:.*?\)\s*$)'
    def repl(m):
        line = m.group(1)
        return (
            "  # === VSP_RUN_API_LOG_ONCE_GUARD ===\n"
            "  if not globals().get('_VSP_RUN_API_LOG_ONCE'):\n"
            "    globals()['_VSP_RUN_API_LOG_ONCE'] = True\n"
            f"    {line.strip()}\n"
            "  # === END VSP_RUN_API_LOG_ONCE_GUARD ==="
        )

    new, n = re.subn(pat, repl, txt, flags=re.MULTILINE)
    if n == 0:
        print("[WARN] cannot find VSP_RUN_API OK registered print line to guard (pattern miss)")
    else:
        txt = new
        # đặt biến “seen” ở top (an toàn)
        if "globals()['_VSP_RUN_API_LOG_ONCE']" not in txt:
            pass
        p.write_text(txt, encoding="utf-8")
        print(f"[OK] guarded {n} print(s) with log-once")
PY

python3 -m py_compile "$PYF" && echo "[OK] py_compile OK"
