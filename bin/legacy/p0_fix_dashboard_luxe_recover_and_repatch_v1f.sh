#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need ls; need head

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || err "missing $F"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_pre_v1f_${TS}"
ok "backup current: ${F}.bak_pre_v1f_${TS}"

# Pick latest backup that is NOT the current pre_v1f backup
B="$(ls -1t "${F}".bak_* 2>/dev/null | grep -v "bak_pre_v1f_${TS}$" | head -n 1 || true)"
[ -n "$B" ] || err "no backup found for $F (need ${F}.bak_*)"
ok "restore from: $B"
cp -f "$B" "$F"

# Apply minimal SAFE patch set, then node --check. If fail -> rollback to pre_v1f.
python3 - <<'PY'
from pathlib import Path
import re, sys

F = Path("static/js/vsp_dashboard_luxe_v1.js")
s = F.read_text(encoding="utf-8", errors="ignore")

def replace_esc_block(src: str) -> str:
  needle = "function esc("
  i = src.find(needle)
  if i < 0:
    return src
  j = src.find("{", i)
  if j < 0:
    return src
  depth = 0
  k = j
  while k < len(src):
    ch = src[k]
    if ch == "{":
      depth += 1
    elif ch == "}":
      depth -= 1
      if depth == 0:
        k += 1
        break
    k += 1
  if depth != 0:
    # Don't risk corrupting file if brace parse fails
    return src

  safe_esc = (
    'function esc(s){\n'
    '  try{\n'
    '    return (s==null ? "" : String(s))\n'
    '      .replace(/&/g,"&amp;")\n'
    '      .replace(/</g,"&lt;")\n'
    '      .replace(/>/g,"&gt;")\n'
    '      .replace(/"/g,"&quot;");\n'
    '  }catch(e){\n'
    '    return "";\n'
    '  }\n'
    '}\n'
  )
  return src[:i] + safe_esc + src[k:]

def rep(src: str) -> str:
  x = src

  # 1) Always fix esc() to a safe version (prevents the exact crash you hit)
  x = replace_esc_block(x)

  # 2) Stateless contract: never call run_file_allow from FE
  x = x.replace('`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`',
                '`/api/vsp/run_gate_summary_v1?rid=${encodeURIComponent(rid)}`')
  x = x.replace('/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json',
                '/api/vsp/run_gate_summary_v1?rid=" + encodeURIComponent(rid)')
  x = x.replace('`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_manifest.json`',
                '`/api/vsp/run_manifest_v1?rid=${encodeURIComponent(rid)}`')

  # Unified findings paging (no file coupling)
  x = x.replace('`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&limit=25`',
                '`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=25&offset=0`')

  # 3) Commercial: remove debug/dev labels leaking internal file names
  x = x.replace("UNIFIED FROM findings_unified.json", "Unified Findings (8 tools)")
  x = x.replace("UNIFIED FROM", "Unified Findings")
  x = x.replace("reports/findings_unified.json", "unified")
  x = x.replace("findings_unified.json", "unified")

  # 4) Commercial wording: avoid “not available” phrasing
  x = x.replace("KPI data not available.", "No KPI data for this run.")
  x = x.replace("Charts data not available.", "No charts data for this run.")
  x = x.replace("KPI & charts data not available.", "No KPI/charts data for this run.")
  x = x.replace("not available", "—")

  return x

ns = rep(s)
F.write_text(ns, encoding="utf-8")
print("[OK] repatch applied to", str(F))
PY

if node --check "$F"; then
  ok "node --check OK: $F"
else
  warn "node --check FAIL: rolling back to pre_v1f"
  cp -f "${F}.bak_pre_v1f_${TS}" "$F"
  node --check "$F" >/dev/null 2>&1 || true
  err "rolled back; please paste the first 30 lines around the error location from node output"
fi

# Restart
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
fi

echo "== [SMOKE] ensure no real caller remains in luxe =="
grep -n '/api/vsp/run_file_allow\?rid=' -n "$F" || true

echo "== [DONE] Reload /vsp5 and confirm console has no SyntaxError =="
