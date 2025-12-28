#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_bindcall_${TS}"
echo "[BACKUP] ${JS}.bak_dash_bindcall_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_DASH_V6_CALL_BIND_V7" in s:
    print("[OK] already patched")
    raise SystemExit(0)

# inject right after `if (g) render(g);`
pat = r"if\s*\(g\)\s*render\(g\);\s*"
rep = "if (g) render(g);\n      try{ if (g && window.__vsp_dash_bind_native_cards_v7_apply) window.__vsp_dash_bind_native_cards_v7_apply(g); }catch(e){}\n      /* VSP_P1_DASH_V6_CALL_BIND_V7 */\n"
s2, n = re.subn(pat, rep, s, count=1)
if n!=1:
    print("[WARN] inject point not found; no change")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] injected bind-call into V6 tick")
PY

sudo systemctl restart vsp-ui-8910.service || true
sleep 1.2
echo "[DONE] V6 now also updates native KPI cards (if present)."
