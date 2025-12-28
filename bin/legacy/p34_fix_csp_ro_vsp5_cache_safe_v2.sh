#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p34_csp_ro_v2_${TS}"
echo "[BACKUP] ${W}.bak_p34_csp_ro_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Remove the bad V1 block if present
m1 = "VSP_P34_CSP_RO_ENSURE_V1"
pat_v1 = re.compile(r"(?s)\n# --- "+re.escape(m1)+r" ---.*?\n# --- /"+re.escape(m1)+r" ---\n")
s2, n = pat_v1.subn("\n", s)
if n:
    print(f"[OK] removed {m1} blocks:", n)
    s = s2

# 2) Append safe V2 hook at end-of-file (no try/except interleaving risk)
m2 = "VSP_P34_CSP_RO_ENSURE_V2"
if m2 in s:
    print("[OK] already present:", m2)
else:
    block = f"""
# --- {m2} ---
# Commercial: ensure CSP-Report-Only exists even on cached HTML responses (HIT-RAM/HIT-DISK).
def __vsp_p34_ensure_csp_ro(resp):
    try:
        # Import inside function to avoid touching upstream imports
        try:
            from flask import request
        except Exception:
            request = None

        ct = (resp.headers.get("Content-Type","") or "").lower()
        path = getattr(request, "path", "") if request is not None else ""
        if resp.status_code == 200 and "text/html" in ct and not str(path or "").startswith("/static/"):
            if "Content-Security-Policy-Report-Only" not in resp.headers:
                resp.headers["Content-Security-Policy-Report-Only"] = (
                    "default-src 'self'; "
                    "base-uri 'self'; "
                    "form-action 'self'; "
                    "frame-ancestors 'self'; "
                    "img-src 'self' data:; "
                    "font-src 'self' data:; "
                    "style-src 'self' 'unsafe-inline'; "
                    "script-src 'self' 'unsafe-inline'; "
                    "connect-src 'self'; "
                    "object-src 'none';"
                )
        return resp
    except Exception:
        return resp

try:
    _app = globals().get("app", None)
    if _app is not None:
        _app.after_request(__vsp_p34_ensure_csp_ro)
except Exception:
    pass
# --- /{m2} ---
"""
    s = s.rstrip() + "\n" + block + "\n"
    print("[OK] appended:", m2)

p.write_text(s, encoding="utf-8")
print("[OK] write file done")
PY

# 3) Compile check; if fails -> rollback
if python3 -m py_compile "$W"; then
  echo "[OK] py_compile OK"
else
  echo "[ERR] py_compile FAILED -> rollback" >&2
  cp -f "${W}.bak_p34_csp_ro_v2_${TS}" "$W"
  exit 2
fi

# 4) Restart service if exists
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^${SVC}"; then
  echo "[INFO] restarting: $SVC"
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"
else
  echo "[WARN] systemd service not found: $SVC (skip restart)"
fi

echo "== [CHECK] CSP_RO header on /vsp5 =="
curl -fsSI "$BASE/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Security-Policy-Report-Only:|^Content-Type:/{print}'

echo "== [RUN] commercial_ui_audit_v2 =="
BASE="$BASE" bash bin/commercial_ui_audit_v2.sh | tail -n 90
