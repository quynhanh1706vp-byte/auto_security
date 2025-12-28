#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date; need ls; need head; need grep

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

pick_pass_backup(){
  local f="$1"
  local cand
  for cand in $(ls -1t "${f}".bak_* 2>/dev/null || true); do
    if node --check "$cand" >/dev/null 2>&1; then
      echo "$cand"
      return 0
    fi
  done
  echo ""
  return 0
}

restore_pass_or_die(){
  local f="$1"
  [ -f "$f" ] || err "missing $f"
  cp -f "$f" "${f}.bak_pre_v1i2_${TS}"
  ok "backup current: ${f}.bak_pre_v1i2_${TS}"

  local b
  b="$(pick_pass_backup "$f")"
  if [ -z "$b" ]; then
    echo "== [DIAG] No PASS backup found for $f. Last 12 backups status =="
    local c
    for c in $(ls -1t "${f}".bak_* 2>/dev/null | head -n 12 || true); do
      if node --check "$c" >/dev/null 2>&1; then
        echo "PASS $c"
      else
        echo "FAIL $c"
      fi
    done
    err "No PASS backup available for $f. Need restore from git/source or switch away from this module."
  fi

  ok "restore PASS: $b -> $f"
  cp -f "$b" "$f"
  node --check "$f" >/dev/null 2>&1 || err "restored PASS backup but current FAIL? (unexpected)"
}

FILES_TO_FIX=(
  static/js/vsp_dashboard_luxe_v1.js
  static/js/vsp_tabs4_autorid_v1.js
  static/js/vsp_dash_only_v1.js
  static/js/vsp_dashboard_consistency_patch_v1.js
)

echo "== [1] restore PASS baselines =="
for f in "${FILES_TO_FIX[@]}"; do
  restore_pass_or_die "$f"
done

echo "== [2] apply SAFE commercial repatch (heredoc python) =="
python3 - <<'PY'
from pathlib import Path
import re

FILES = [
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_tabs4_autorid_v1.js",
  "static/js/vsp_dash_only_v1.js",
  "static/js/vsp_dashboard_consistency_patch_v1.js",
]

def replace_esc_block(src: str) -> str:
  # Replace esc() only if exists; safe brace-scan
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
    return src

  safe = (
    "function esc(s){\n"
    "  try{\n"
    "    return (s==null ? \"\" : String(s))\n"
    "      .replace(/&/g,\"&amp;\")\n"
    "      .replace(/</g,\"&lt;\")\n"
    "      .replace(/>/g,\"&gt;\")\n"
    "      .replace(/\\\"/g,\"&quot;\");\n"
    "  }catch(e){\n"
    "    return \"\";\n"
    "  }\n"
    "}\n"
  )
  return src[:i] + safe + src[k:]

def patch_runfileallow(src: str) -> str:
  x = src

  # gate summary
  x = x.replace(
    '/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json&ts=" + Date.now()',
    '/api/vsp/run_gate_summary_v1?rid=" + encodeURIComponent(rid)'
  )
  x = x.replace(
    '/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json',
    '/api/vsp/run_gate_summary_v1?rid=" + encodeURIComponent(rid)'
  )
  x = x.replace(
    '`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`',
    '`/api/vsp/run_gate_summary_v1?rid=${encodeURIComponent(rid)}`'
  )

  # manifest
  x = x.replace(
    '`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_manifest.json`',
    '`/api/vsp/run_manifest_v1?rid=${encodeURIComponent(rid)}`'
  )

  # run_gate.json -> dashboard_v3 (commercial contract)
  x = x.replace(
    '`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate.json`',
    '`/api/vsp/dashboard_v3?rid=${encodeURIComponent(rid)}`'
  )
  x = x.replace(
    '/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate.json',
    '/api/vsp/dashboard_v3?rid=" + encodeURIComponent(rid)'
  )

  # unified findings -> paging api
  x = x.replace(
    '`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&limit=25`',
    '`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=25&offset=0`'
  )

  return x

def patch_leaks_and_wording(src: str) -> str:
  x = src
  # remove internal file leaks + debug labels
  x = x.replace("UNIFIED FROM findings_unified.json", "Unified Findings (8 tools)")
  x = x.replace("UNIFIED FROM", "Unified Findings")
  x = x.replace("reports/findings_unified.json", "unified")
  x = x.replace("findings_unified.json", "unified")

  # remove "not available"
  x = x.replace("KPI data not available.", "No KPI data for this run.")
  x = x.replace("Charts data not available.", "No charts data for this run.")
  x = x.replace("KPI & charts data not available.", "No KPI/charts data for this run.")
  x = x.replace("not available", "—")

  return x

def patch_consistency(src: str) -> str:
  x = src
  # If earlier patch caused findings_page_v3 ... __path=run_gate_summary.json, kill that
  x = re.sub(r"__path=run_gate_summary\.json", "", x)
  # Ensure it never hits run_file_allow
  x = patch_runfileallow(x)
  return x

for f in FILES:
  p = Path(f)
  if not p.exists():
    continue
  s = p.read_text(encoding="utf-8", errors="ignore")
  s0 = s
  s = patch_runfileallow(s)
  s = patch_leaks_and_wording(s)
  if p.name == "vsp_dashboard_luxe_v1.js":
    s = replace_esc_block(s)
  if p.name == "vsp_dashboard_consistency_patch_v1.js":
    s = patch_consistency(s)
  if s != s0:
    p.write_text(s, encoding="utf-8")

print("[OK] repatch completed")
PY

echo "== [3] node --check gate (rollback to pre_v1i2 on FAIL) =="
for f in "${FILES_TO_FIX[@]}"; do
  if node --check "$f" >/dev/null 2>&1; then
    ok "PASS: $f"
  else
    warn "FAIL: $f -> rollback to pre_v1i2"
    cp -f "${f}.bak_pre_v1i2_${TS}" "$f"
    node --check "$f" >/dev/null 2>&1 || warn "still FAIL after rollback: $f"
  fi
done

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
fi

echo "== [SMOKE] real callers should be 0 =="
grep -RIn --line-number '/api/vsp/run_file_allow\?rid=' static/js | head -n 40 || true

echo "== [DONE] Hard refresh browser (Ctrl+F5) and re-check console =="
