#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_apiui_alias_${TS}"
echo "[BACKUP] ${W}.bak_apiui_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Insert alias mapping inside the WSGI shim block (best-effort by markers /api/ui/)
marker_candidates = [
    "VSP_APIUI_WSGI_SHIM_P1_V1",
    "VSP_APIUI_SHIM_P1_V1",
]
pos = -1
for mk in marker_candidates:
    pos = s.find(mk)
    if pos != -1:
        break

if pos == -1:
    # fallback: find first occurrence of '/api/ui/' in shim code
    pos = s.find("/api/ui/")
    if pos == -1:
        raise SystemExit("[ERR] cannot find api/ui shim marker to patch")

# We will inject after a line that sets __path (common in shim)
# Try regex locate "__path = " after pos
m = re.search(r"(?m)^\s*__path\s*=\s*[^#\n]+$", s[pos:])
if not m:
    # fallback inject right after marker line
    m2 = re.search(r"(?m)^.*(" + re.escape(marker_candidates[0]) + r"|" + re.escape(marker_candidates[1]) + r").*$", s)
    if not m2:
        raise SystemExit("[ERR] cannot locate insertion point")
    ins_at = m2.end()
else:
    ins_at = pos + m.end()

inject = r'''
    # --- VSP_APIUI_ALIAS_COMPAT_P1_V1 ---
    # Compat for older JS that still calls /api/ui/runs (no _v2) etc.
    __alias = {
      "/api/ui/runs": "/api/ui/runs_v2",
      "/api/ui/findings": "/api/ui/findings_v2",
      "/api/ui/settings": "/api/ui/settings_v2",
      "/api/ui/rule_overrides": "/api/ui/rule_overrides_v2",
      "/api/ui/rule_overrides_apply": "/api/ui/rule_overrides_apply_v2",
    }
    if __path in __alias:
      __path = __alias[__path]
    # --- /VSP_APIUI_ALIAS_COMPAT_P1_V1 ---
'''

# avoid double insert
if "VSP_APIUI_ALIAS_COMPAT_P1_V1" in s:
    print("[OK] alias compat already present")
else:
    s = s[:ins_at] + inject + s[ins_at:]
    p.write_text(s, encoding="utf-8")
    print("[OK] injected alias compat block")

PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
# prefer existing stable starter (no sudo prompt)
if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || true
fi
# if you run via systemd in your env, keep it (non-fatal)
sudo -n systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true

echo "== verify legacy + v2 endpoints =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

for u in \
  "$BASE/api/ui/runs?limit=1" \
  "$BASE/api/ui/runs_v2?limit=1" \
  "$BASE/api/ui/findings?limit=1&offset=0" \
  "$BASE/api/ui/findings_v2?limit=1&offset=0" \
  "$BASE/api/ui/settings" \
  "$BASE/api/ui/settings_v2" \
  "$BASE/api/ui/rule_overrides" \
  "$BASE/api/ui/rule_overrides_v2"
do
  echo "--- $u"
  curl -fsS "$u" | head -c 220; echo
done

echo "[DONE] alias compat installed"
