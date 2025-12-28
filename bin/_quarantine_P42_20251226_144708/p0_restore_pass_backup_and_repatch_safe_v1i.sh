#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date; need ls; need head

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

pick_pass(){
  local f="$1"
  local c
  # Search all backups, newest first
  for c in $(ls -1t "${f}".bak_* 2>/dev/null); do
    if node --check "$c" >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
  done
  echo ""
  return 0
}

restore_pass_or_die(){
  local f="$1"
  [ -f "$f" ] || err "missing $f"
  cp -f "$f" "${f}.bak_pre_v1i_${TS}"
  ok "backup current: ${f}.bak_pre_v1i_${TS}"

  local b
  b="$(pick_pass "$f")"
  if [ -z "$b" ]; then
    echo "== [DIAG] No PASS backup found for $f. Showing last 10 backups + status:"
    for c in $(ls -1t "${f}".bak_* 2>/dev/null | head -n 10); do
      if node --check "$c" >/dev/null 2>&1; then
        echo "PASS $c"
      else
        echo "FAIL $c"
      fi
    done
    err "No PASS backup available for $f. Do NOT patch this file further until we have a good baseline."
  fi

  ok "restore PASS: $b -> $f"
  cp -f "$b" "$f"
  node --check "$f" >/dev/null 2>&1 || err "restored PASS backup but current FAIL? (unexpected)"
}

SAFE_PATCH_PY='
from pathlib import Path
import re

def patch_text(s: str) -> str:
  x = s

  # 1) kill real run_file_allow callers (rid-based only)
  x = x.replace("`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`",
                "`/api/vsp/run_gate_summary_v1?rid=${encodeURIComponent(rid)}`")
  x = x.replace(\'"/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json"\',
                \'/api/vsp/run_gate_summary_v1?rid=" + encodeURIComponent(rid)\'.join(["\\\"", "\\\""]))
  x = x.replace("`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_manifest.json`",
                "`/api/vsp/run_manifest_v1?rid=${encodeURIComponent(rid)}`")
  x = x.replace("`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&limit=25`",
                "`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=25&offset=0`")

  # run_gate.json -> dashboard_v3
  x = x.replace("`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate.json`",
                "`/api/vsp/dashboard_v3?rid=${encodeURIComponent(rid)}`")

  # 2) remove internal filename leaks + debug labels
  x = x.replace("UNIFIED FROM findings_unified.json", "Unified Findings (8 tools)")
  x = x.replace("UNIFIED FROM", "Unified Findings")
  x = x.replace("reports/findings_unified.json", "unified")
  x = x.replace("findings_unified.json", "unified")

  # 3) commercial wording (no \"not available\")
  x = x.replace("KPI data not available.", "No KPI data for this run.")
  x = x.replace("Charts data not available.", "No charts data for this run.")
  x = x.replace("KPI & charts data not available.", "No KPI/charts data for this run.")
  x = x.replace("not available", "—")

  return x

def safe_replace_esc_block(src: str) -> str:
  if "function esc(" not in src:
    return src
  # only replace esc if it contains suspicious replaceAll usage or broken quoting patterns
  if "replaceAll" not in src and ".replace(/&/g" in src:
    return src

  i = src.find("function esc(")
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
    "function esc(s){\\n"
    "  try{\\n"
    "    return (s==null ? \\"\\" : String(s))\\n"
    "      .replace(/&/g,\\"&amp;\\")\\n"
    "      .replace(/</g,\\"&lt;\\")\\n"
    "      .replace(/>/g,\\"&gt;\\")\\n"
    "      .replace(/\\\\"/g,\\"&quot;\\");\\n"
    "  }catch(e){\\n"
    "    return \\"\\";\\n"
    "  }\\n"
    "}\\n"
  )
  return src[:i] + safe + src[k:]

def run(path: str, do_esc: bool=False):
  p = Path(path)
  s = p.read_text(encoding="utf-8", errors="ignore")
  s2 = patch_text(s)
  if do_esc:
    s2 = safe_replace_esc_block(s2)
  if s2 != s:
    p.write_text(s2, encoding="utf-8")

files = [
  ("static/js/vsp_dashboard_luxe_v1.js", True),
  ("static/js/vsp_tabs4_autorid_v1.js", False),
  ("static/js/vsp_dash_only_v1.js", False),
  ("static/js/vsp_dashboard_consistency_patch_v1.js", False),
]
for f, esc in files:
  if Path(f).exists():
    run(f, esc)
print("[OK] safe repatch done")
'

FILES_TO_FIX=(
  static/js/vsp_dashboard_luxe_v1.js
  static/js/vsp_tabs4_autorid_v1.js
  static/js/vsp_dash_only_v1.js
  static/js/vsp_dashboard_consistency_patch_v1.js
)

echo "== [1] restore PASS baseline for critical JS =="
for f in "${FILES_TO_FIX[@]}"; do
  restore_pass_or_die "$f"
done

echo "== [2] apply safe repatch =="
python3 - <<PY
${SAFE_PATCH_PY}
PY

echo "== [3] node --check gate (rollback to PASS baseline if any FAIL) =="
for f in "${FILES_TO_FIX[@]}"; do
  if node --check "$f" >/dev/null 2>&1; then
    ok "PASS: $f"
  else
    warn "FAIL: $f -> rollback to PASS baseline"
    # rollback to the restored PASS baseline backup we just restored from:
    # easiest: rollback to pre_v1i backup and then restore PASS again
    cp -f "${f}.bak_pre_v1i_${TS}" "$f" || true
    b="$(pick_pass "$f")"
    [ -n "$b" ] && cp -f "$b" "$f" || true
    node --check "$f" >/dev/null 2>&1 || warn "still FAIL after rollback: $f"
  fi
done

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
fi

echo "== [SMOKE] real callers should be 0 =="
grep -RIn --line-number '/api/vsp/run_file_allow\?rid=' static/js | head -n 40 || true

echo "== [DONE] Hard refresh browser (Ctrl+F5) and re-check console =="
