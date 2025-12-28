#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need ss; need awk; need sed; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, datetime

root = Path("templates")
files = list(root.rglob("*.html"))
targets = []

# dấu hiệu inline V6E đang chạy (theo console: vsp5:32)
needles = [
  "[VSP][DASH][V6E]",
  "VSP_P1_DASH_RID_RESOLVER_CANVAS_V6E",
  "gave up (Chart/container missing)",
  "containers/rid missing",
]

for f in files:
    s = f.read_text(encoding="utf-8", errors="replace")
    if any(n in s for n in needles):
        targets.append(f)

print("[INFO] templates hit:", len(targets))
patched = 0
for f in targets:
    s = f.read_text(encoding="utf-8", errors="replace")
    bak = f.with_suffix(f".html.bak_disable_v6e_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}")
    bak.write_text(s, encoding="utf-8")
    # wrap mọi <script> block có chứa V6E needle để nó KHÔNG chạy mặc định
    def repl(m):
        head, body, tail = m.group(1), m.group(2), m.group(3)
        if any(n in body for n in needles):
            # bảo đảm không double-wrap
            if "VSP_INLINE_V6E_DISABLED_WRAP" in body:
                return m.group(0)
            wrapped = (
                "\n// VSP_INLINE_V6E_DISABLED_WRAP\n"
                "if (window.__VSP_DISABLE_INLINE_V6E !== false) {\n"
                "  console.warn('[VSP][DASH] inline V6E disabled (use bundle renderer)');\n"
                "} else {\n"
                + body +
                "\n}\n"
            )
            return head + wrapped + tail
        return m.group(0)

    s2 = re.sub(r"(<script[^>]*>)(.*?)(</script>)", repl, s, flags=re.S|re.I)
    if s2 != s:
        f.write_text(s2, encoding="utf-8")
        patched += 1
        print("[OK] patched:", f)

print("[DONE] patched_templates:", patched)
PY

echo "== restart clean :8910 (nohup only) =="
rm -f /tmp/vsp_ui_8910.lock || true
PID="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1)"
[ -n "${PID:-}" ] && kill -9 "$PID" || true

: > out_ci/ui_8910.boot.log || true
: > out_ci/ui_8910.error.log || true
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 1.2
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p'
