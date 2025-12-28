#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p34_csp_ro_${TS}"
echo "[BACKUP] ${W}.bak_p34_csp_ro_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P34_CSP_RO_ENSURE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Ensure we can reference request safely
if "from flask import" in s and "request" not in re.search(r"from flask import ([^\n]+)", s).group(1):
    s = re.sub(r"(from flask import [^\n]+)\n", lambda m: m.group(1).rstrip()+" , request\n", s, count=1)

block = f"""
# --- {MARK} ---
# Commercial: ensure CSP-Report-Only exists even on cached HTML responses (HIT-RAM/HIT-DISK).
try:
    @app.after_request
    def __vsp_p34_ensure_csp_ro(resp):
        try:
            # Only touch successful HTML (tabs like /vsp5, /runs, /data_source, /settings, /rule_overrides, /c/*)
            ct = (resp.headers.get("Content-Type","") or "").lower()
            path = getattr(request, "path", "") or ""
            if resp.status_code == 200 and "text/html" in ct and not path.startswith("/static/"):
                if "Content-Security-Policy-Report-Only" not in resp.headers:
                    # Safe baseline (allows inline since UI bundle may use it)
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
except Exception:
    pass
# --- /{MARK} ---
"""

# Inject after app is created (app = Flask(...)) so decorator is valid
m = re.search(r"(?m)^\s*app\s*=\s*Flask\([^\n]*\)\s*$", s)
if not m:
    # fallback: first occurrence of "app = Flask(" (less strict)
    m = re.search(r"app\s*=\s*Flask\(", s)
    if not m:
        raise SystemExit("[ERR] cannot find app = Flask(...) to inject after_request CSP block")

ins_at = m.end()
# Put block right after that line (next newline)
nl = s.find("\n", ins_at)
if nl == -1:
    nl = ins_at
s = s[:nl+1] + block + s[nl+1:]

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q "^${SVC}"; then
  echo "[INFO] restarting: $SVC"
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active"
else
  echo "[WARN] systemd service not found: $SVC (skip restart)"
fi

echo "== [CHECK] header on /vsp5 =="
curl -fsSI "$BASE/vsp5" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Security-Policy-Report-Only:|^Content-Type:/{print}'

echo "== [RUN] commercial_ui_audit_v2 =="
BASE="$BASE" bash bin/commercial_ui_audit_v2.sh | tail -n 90
