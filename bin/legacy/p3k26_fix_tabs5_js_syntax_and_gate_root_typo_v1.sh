#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F1="static/js/vsp_bundle_tabs5_v1.js"
F2="static/js/vsp_dashboard_commercial_panels_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
need node
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

[ -f "$F1" ] || { echo "[ERR] missing $F1"; exit 2; }
cp -f "$F1" "${F1}.bak_p3k26_${TS}"
echo "[BACKUP] ${F1}.bak_p3k26_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Fix common bad injection artifact: literal "\n" at end-of-line (outside strings)
# Example broken line becomes: "})();\n" -> "})();"
s2 = re.sub(r'(?m)\\n\s*$', '', s)

# Also clean stray "\r" just in case
s2 = s2.replace('\r\n', '\n').replace('\r', '\n')

if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched tabs5: removed literal \\\\n at EOL / CR cleanup")
else:
    print("[OK] tabs5: no EOL \\\\n artifact found (no-op)")
PY

echo "== node -c tabs5 =="
node -c "$F1"
echo "[OK] tabs5 syntax OK"

if [ -f "$F2" ]; then
  cp -f "$F2" "${F2}.bak_p3k26_${TS}"
  echo "[BACKUP] ${F2}.bak_p3k26_${TS}"

  python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_commercial_panels_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
s2 = s.replace("rid_latest_gate_root_gate_root", "rid_latest_gate_root")
if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched commercial panels: gate_root typo fixed")
else:
    print("[OK] commercial panels: no typo found (no-op)")
PY

  echo "== node -c commercial panels =="
  node -c "$F2"
  echo "[OK] commercial panels syntax OK"
else
  echo "[WARN] missing $F2 (skip gate_root typo fix)"
fi

echo "== restart service (if available) =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== quick smoke (optional) =="
if command -v curl >/dev/null 2>&1; then
  BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
  curl -fsS --connect-timeout 1 --max-time 4 "$BASE/vsp5" >/dev/null && echo "[OK] /vsp5" || echo "[WARN] /vsp5"
  curl -fsS --connect-timeout 1 --max-time 4 "$BASE/runs" >/dev/null && echo "[OK] /runs" || echo "[WARN] /runs"
  curl -fsS --connect-timeout 1 --max-time 4 "$BASE/data_source" >/dev/null && echo "[OK] /data_source" || echo "[WARN] /data_source"
  curl -fsS --connect-timeout 1 --max-time 4 "$BASE/settings" >/dev/null && echo "[OK] /settings" || echo "[WARN] /settings"
  curl -fsS --connect-timeout 1 --max-time 4 "$BASE/rule_overrides" >/dev/null && echo "[OK] /rule_overrides" || echo "[WARN] /rule_overrides"
fi

echo "[DONE] p3k26_fix_tabs5_js_syntax_and_gate_root_typo_v1"
