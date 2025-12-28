#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

echo "== verify HEAD /runs =="
H="$(curl -sS -I "$BASE/runs" || true)"
echo "$H" | sed -n '1,30p'
echo
if echo "$H" | grep -qi 'content-security-policy-report-only'; then
  echo "[OK] CSP-Report-Only present"
  exit 0
fi
echo "[WARN] CSP-Report-Only missing -> force attach via header wrapper"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_cspforce_${TS}"
echo "[BACKUP] ${W}.bak_cspforce_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# We will inject CSP-RO into the existing header wrapper block:
# Marker installed earlier: VSP_P0_TABS_COMMERCIAL_HEADERS_V1
if "VSP_P0_TABS_COMMERCIAL_HEADERS_V1" not in s:
    print("[ERR] missing VSP_P0_TABS_COMMERCIAL_HEADERS_V1 block; cannot force safely")
    raise SystemExit(2)

if "VSP_P1_CSP_REPORT_ONLY_V2_FORCE" in s:
    print("[SKIP] already forced")
    raise SystemExit(0)

# Find function _add_hdrs(...) inside that block and append header for HTML pages.
m = re.search(r"def _add_hdrs\(path, status, headers\):.*?return h", s, flags=re.S)
if not m:
    print("[ERR] cannot locate _add_hdrs()")
    raise SystemExit(2)

inject = r"""
        # CSP Report-Only (safe, non-breaking; for HTML tabs only)
        # VSP_P1_CSP_REPORT_ONLY_V2_FORCE
        if (path or "") in ("/runs","/data_source","/settings","/vsp5"):
            if "content-security-policy-report-only" not in keys:
                h.append(("Content-Security-Policy-Report-Only",
                          "default-src 'self'; img-src 'self' data:; "
                          "style-src 'self' 'unsafe-inline'; "
                          "script-src 'self' 'unsafe-inline'; "
                          "connect-src 'self'; font-src 'self' data:; "
                          "frame-ancestors 'none'; base-uri 'self'; form-action 'self'"))
                keys.add("content-security-policy-report-only")
"""

# Insert inject right before the "return h" within the matched function
func = m.group(0)
func2 = func.replace("        return h", inject + "\n        return h", 1)
s2 = s[:m.start()] + func2 + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] forced CSP-RO into header wrapper")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo
echo "== verify again HEAD /runs =="
curl -sS -I "$BASE/runs" | egrep -i 'HTTP/|cache-control|content-security-policy-report-only' || true
echo "[DONE]"
