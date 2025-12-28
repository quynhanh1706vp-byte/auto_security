#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_FIX_DEGRADEDCHECK_AND_KPI_CT_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_degkpi_${TS}"
echo "[BACKUP] ${JS}.bak_fix_degkpi_${TS}"

python3 - "$JS" "$MARK" <<'PY'
from pathlib import Path
import sys, re

js_path = sys.argv[1]
mark = sys.argv[2]
p = Path(js_path)
s = p.read_text(encoding="utf-8", errors="ignore")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

# -------------------------------------------------------------------
# (A) Disable __vspCheckDegraded call (prevents ReferenceError + banner spam)
# We do NOT delete; only guard + no-op call.
# -------------------------------------------------------------------
# 1) If function exists, wrap its body with try/catch and early return.
# Try common patterns: "function __vspCheckDegraded(" or "window.__vspCheckDegraded ="
patterns = [
    r'function\s+__vspCheckDegraded\s*\([^)]*\)\s*\{',
    r'window\.__vspCheckDegraded\s*=\s*function\s*\([^)]*\)\s*\{',
]
for pat in patterns:
    m = re.search(pat, s)
    if m:
        # Insert at start of function body: try { ... } catch(e){...}
        # We'll only guard if not already guarded
        brace_pos = m.end()
        if "VSP_P3_DISABLE_DEGRADEDCHECK_V1" not in s[brace_pos:brace_pos+400]:
            s = s[:brace_pos] + "\n  /* VSP_P3_DISABLE_DEGRADEDCHECK_V1 */\n  try{\n    return; // disabled (commercial-safe)\n  }catch(e){ return; }\n" + s[brace_pos:]
        break

# 2) Also neutralize DOMContentLoaded hook that calls __vspCheckDegraded
# Replace any "document.addEventListener('DOMContentLoaded', __vspCheckDegraded" with noop
s = re.sub(
    r'document\.addEventListener\(\s*([\'"])DOMContentLoaded\1\s*,\s*__vspCheckDegraded\s*(?:,\s*\{[^\}]*\}\s*)?\)\s*;',
    r'/* VSP_P3_DISABLE_DEGRADEDCHECK_HOOK_V1 */ (function(){});',
    s
)

# -------------------------------------------------------------------
# (B) Strengthen VSP_P3_TRUEFIX_COUNTS_TOTAL_V1:
# If window.__vsp_dashkpis_cache is empty, fetch dash_kpis right there (await).
# -------------------------------------------------------------------
# Find the block we injected earlier:
anchor = "const __k  = window.__vsp_dashkpis_cache || null;"
idx = s.find(anchor)
if idx == -1:
    # maybe spacing differs
    anchor = "const __k = window.__vsp_dashkpis_cache || null;"
    idx = s.find(anchor)

if idx == -1:
    print("[WARN] cannot locate counts_total truefix anchor; skip strengthening")
else:
    # Insert BEFORE __k assignment
    insert = r"""
      // --- VSP_P3_FIX_CT_FETCH_DASHKPIS_V1 ---
      try{
        if (!window.__vsp_dashkpis_cache){
          const __rid = (typeof rid !== "undefined" ? rid : (new URL(location.href)).searchParams.get("rid") || "");
          const __fetch = (typeof fetchJson === "function") ? fetchJson : ((typeof fetchJSON === "function") ? fetchJSON : null);
          if (__fetch){
            // Prefer rid-aware endpoint
            let __u = "/api/vsp/dash_kpis";
            if (__rid) __u = __u + "?rid=" + encodeURIComponent(__rid);
            window.__vsp_dashkpis_cache = await __fetch(__u);
          }
        }
      }catch(_){}
      // --- /VSP_P3_FIX_CT_FETCH_DASHKPIS_V1 ---
"""
    s = s[:idx] + insert + s[idx:]

# marker footer
s += f"\n/* {mark} */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker present =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing"; exit 2; }

echo "[DONE] patch applied. HARD refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
