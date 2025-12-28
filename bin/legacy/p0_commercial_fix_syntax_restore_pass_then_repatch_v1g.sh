#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date; need ls; need head; need grep

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

FILES=(
  static/js/vsp_dashboard_luxe_v1.js
  static/js/vsp_tabs4_autorid_v1.js
  static/js/vsp_dash_only_v1.js
  static/js/vsp_dashboard_consistency_patch_v1.js
  static/js/vsp_bundle_tabs5_v1.js
)

pick_pass_backup(){
  local f="$1"
  local cand
  for cand in $(ls -1t "${f}".bak_* 2>/dev/null); do
    if node --check "$cand" >/dev/null 2>&1; then
      echo "$cand"
      return 0
    fi
  done
  echo ""
}

restore_with_gate(){
  local f="$1"
  if [ ! -f "$f" ]; then warn "missing: $f"; return 0; fi
  cp -f "$f" "${f}.bak_pre_v1g_${TS}"
  local b
  b="$(pick_pass_backup "$f")"
  if [ -z "$b" ]; then
    warn "NO PASS backup for $f (keep current)."
    return 0
  fi
  ok "restore PASS backup: $b -> $f"
  cp -f "$b" "$f"
  node --check "$f" >/dev/null 2>&1 || { warn "restored but still FAIL? keeping pre_v1g"; cp -f "${f}.bak_pre_v1g_${TS}" "$f"; }
}

echo "== [1] restore PASS backups (syntax-gated) =="
for f in "${FILES[@]}"; do restore_with_gate "$f"; done

echo "== [2] apply SAFE commercial repatch (no risky regex replacements) =="
python3 - <<'PY'
from pathlib import Path
import re

FILES = [
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_tabs4_autorid_v1.js",
  "static/js/vsp_dash_only_v1.js",
  "static/js/vsp_dashboard_consistency_patch_v1.js",
  "static/js/vsp_bundle_tabs5_v1.js",
]

def safe_replace_runfileallow(src: str) -> str:
  x = src

  # Replace callsites that include ?rid=... (real callers)
  x = re.sub(r"/api/vsp/run_file_allow\?rid=([\"`])\s*\+\s*encodeURIComponent\(rid\)\s*\+\s*([\"`])\s*\+\s*\"&path=run_gate_summary\.json\"",
             r"/api/vsp/run_gate_summary_v1?rid=\" + encodeURIComponent(rid) + \"", x)
  x = x.replace("`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`",
                "`/api/vsp/run_gate_summary_v1?rid=${encodeURIComponent(rid)}`")
  x = x.replace('"/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json"',
                '"/api/vsp/run_gate_summary_v1?rid=" + encodeURIComponent(rid)')

  x = x.replace("`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_manifest.json`",
                "`/api/vsp/run_manifest_v1?rid=${encodeURIComponent(rid)}`")

  # run_gate.json → dashboard_v3 (contract)
  x = x.replace("`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate.json`",
                "`/api/vsp/dashboard_v3?rid=${encodeURIComponent(rid)}`")
  x = x.replace('"/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate.json"',
                '"/api/vsp/dashboard_v3?rid=" + encodeURIComponent(rid)')

  # unified findings paging
  x = x.replace("`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&limit=25`",
                "`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=25&offset=0`")

  return x

def safe_remove_leaks(src: str) -> str:
  x = src
  x = x.replace("UNIFIED FROM findings_unified.json", "Unified Findings (8 tools)")
  x = x.replace("UNIFIED FROM", "Unified Findings")
  x = x.replace("reports/findings_unified.json", "unified")
  x = x.replace("findings_unified.json", "unified")
  return x

def safe_remove_not_available(src: str) -> str:
  x = src
  x = x.replace("KPI data not available.", "No KPI data for this run.")
  x = x.replace("Charts data not available.", "No charts data for this run.")
  x = x.replace("KPI & charts data not available.", "No KPI/charts data for this run.")
  x = x.replace("not available", "—")
  return x

def safe_fix_consistency(src: str) -> str:
  # IMPORTANT: avoid the wrong call you saw:
  # /api/vsp/findings_page_v3?...&__path=run_gate_summary.json
  # Consistency patch must use run_gate_summary_v1 directly.
  x = src

  # If it constructs __path=run_gate_summary.json or mentions run_gate_summary.json in a URL, force wrapper.
  x = re.sub(r"/api/vsp/findings_page_v3\?rid=\$\{encodeURIComponent\(rid\)\}[^`]*__path=run_gate_summary\.json",
             "/api/vsp/run_gate_summary_v1?rid=${encodeURIComponent(rid)}", x)

  x = x.replace("/api/vsp/findings_page_v3?rid=",
                "/api/vsp/findings_page_v3?rid=")  # keep, but stop passing __path=gate_summary
  x = x.replace("__path=run_gate_summary.json", "");  # hard drop if present

  # also kill any run_file_allow caller inside
  x = safe_replace_runfileallow(x)
  return x

def replace_esc_block_only_if_present(src: str) -> str:
  # If esc exists and contains replaceAll('"',...), swap to safe version.
  if "function esc(" not in src:
    return src
  if "replaceAll" not in src and ".replace(/&/g" in src:
    return src  # already safe
  # brace-scan to replace esc block safely
  i = src.find("function esc(")
  j = src.find("{", i)
  if j < 0: return src
  depth = 0
  k = j
  while k < len(src):
    ch = src[k]
    if ch == "{": depth += 1
    elif ch == "}":
      depth -= 1
      if depth == 0:
        k += 1
        break
    k += 1
  if depth != 0: return src

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

def patch_one(path: str):
  p = Path(path)
  if not p.exists():
    return
  s = p.read_text(encoding="utf-8", errors="ignore")
  s0 = s
  s = safe_replace_runfileallow(s)
  s = safe_remove_leaks(s)
  s = safe_remove_not_available(s)
  if p.name == "vsp_dashboard_consistency_patch_v1.js":
    s = safe_fix_consistency(s)
  if p.name == "vsp_dashboard_luxe_v1.js":
    s = replace_esc_block_only_if_present(s)
  if s != s0:
    p.write_text(s, encoding="utf-8")

for f in FILES:
  patch_one(f)

print("[OK] safe repatch done")
PY

echo "== [3] node --check gate (rollback file-by-file if FAIL) =="
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  if node --check "$f" >/dev/null 2>&1; then
    ok "PASS: $f"
  else
    warn "FAIL: $f -> rollback to pre_v1g"
    cp -f "${f}.bak_pre_v1g_${TS}" "$f"
    node --check "$f" >/dev/null 2>&1 || warn "still FAIL after rollback: $f (need manual inspect)"
  fi
done

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
fi

echo "== [4] smoke: real callers should be 0 =="
grep -RIn --line-number '/api/vsp/run_file_allow\?rid=' static/js | head -n 40 || true

echo "== [DONE] Hard refresh browser (Ctrl+F5) and re-check console =="
