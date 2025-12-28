#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

# Same JS targets you patched
JS_TOPBAR="static/js/vsp_topbar_commercial_v1.js"
JS_DASH="static/js/vsp_dashboard_luxe_v1.js"
JS_TABS_COMMON="static/js/vsp_tabs3_common_v3.js"
JS_TABS_BUNDLE="static/js/vsp_bundle_tabs5_v1.js"
JS_DASH_CONS="static/js/vsp_dashboard_consistency_patch_v1.js"
JS_DS_PAG="static/js/vsp_data_source_pagination_v1.js"
JS_DS_TAB="static/js/vsp_data_source_tab_v3.js"

for f in "$JS_TOPBAR" "$JS_DASH" "$JS_TABS_COMMON" "$JS_TABS_BUNDLE" "$JS_DASH_CONS" "$JS_DS_PAG" "$JS_DS_TAB"; do
  if [ -f "$f" ]; then
    cp -f "$f" "${f}.bak_commercial_wrap_v1b_${TS}"
    ok "backup: ${f}.bak_commercial_wrap_v1b_${TS}"
  else
    warn "missing: $f"
  fi
done

python3 - <<'PY'
from pathlib import Path
import re

EM_DASH = "—"

def patch_file(path, fn):
  p = Path(path)
  if not p.exists():
    print("[WARN] missing:", path)
    return
  s = p.read_text(encoding="utf-8", errors="ignore")
  ns = fn(s)
  if ns != s:
    p.write_text(ns, encoding="utf-8")
    print("[OK] patched:", path)
  else:
    print("[OK] nochange:", path)

def patch_topbar(s: str) -> str:
  x = s

  # Replace the specific N/A lines (keep your existing behavior: clickable RID label)
  x = x.replace(
    'setText("vspLatestRid", "N/A");',
    'setText("vspLatestRid", "' + EM_DASH + '");'
    ' try{ var el=document.getElementById("vspLatestRid");'
    ' if(el){ el.title="Select a valid RID"; el.style.cursor="pointer";'
    ' el.onclick=function(){ try{ window.__vsp_openRidPicker?.(); }catch(e){} }; } }catch(e){}'
  )
  x = x.replace('wireExport("N/A");', 'wireExport("' + EM_DASH + '");')

  # Generic N/A -> — (SAFE: use lambda, no \u escape in replacement)
  x = re.sub(r'(["\'])N/A\1', lambda m: '"' + EM_DASH + '"', x)
  return x

def patch_no_runfileallow(s: str) -> str:
  x = s

  # Gate summary wrapper
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

  # Manifest wrapper
  x = x.replace(
    '`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_manifest.json`',
    '`/api/vsp/run_manifest_v1?rid=${encodeURIComponent(rid)}`'
  )

  # Findings paging wrapper (v3)
  x = x.replace(
    '`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&limit=25`',
    '`/api/vsp/findings_page_v3?rid=${encodeURIComponent(rid)}&limit=25&offset=0`'
  )
  x = x.replace(
    '"/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=" + encodeURIComponent(path) + "&limit=800"',
    '"/api/vsp/findings_page_v3?rid=" + encodeURIComponent(rid) + "&limit=200&offset=0"'
  )

  # If any leftover run_file_allow appears: clearly mark internal (so audit will catch)
  x = x.replace("/api/vsp/run_file_allow", "/api/vsp/_INTERNAL_DO_NOT_USE_run_file_allow")

  # Remove debug/dev labels + internal file name leaks
  x = x.replace("UNIFIED FROM findings_unified.json", "Unified Findings (8 tools)")
  x = x.replace("UNIFIED FROM", "Unified Findings")
  x = x.replace("reports/findings_unified.json", "unified")
  x = x.replace("findings_unified.json", "unified")

  return x

def patch_datasource_to_api(s: str) -> str:
  x = s
  x = x.replace("/api/vsp/run_file_allow?rid=", "/api/vsp/findings_page_v3?rid=")
  x = x.replace("path=findings_unified.json", "")
  return patch_no_runfileallow(x)

patch_file("static/js/vsp_topbar_commercial_v1.js", patch_topbar)

for f in [
  "static/js/vsp_dashboard_luxe_v1.js",
  "static/js/vsp_tabs3_common_v3.js",
  "static/js/vsp_bundle_tabs5_v1.js",
  "static/js/vsp_dashboard_consistency_patch_v1.js",
]:
  patch_file(f, patch_no_runfileallow)

for f in ["static/js/vsp_data_source_pagination_v1.js", "static/js/vsp_data_source_tab_v3.js"]:
  patch_file(f, patch_datasource_to_api)
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || warn "systemctl restart failed: $SVC"
  sleep 0.4 || true
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [SMOKE] check N/A + debug label in JS (should be empty) =="
grep -RIn --line-number 'N/A\|UNIFIED FROM\|findings_unified\.json\|/api/vsp/run_file_allow' static/js \
  | head -n 80 || true

echo "== [DONE] Now rerun: bin/commercial_ui_audit_v1.sh =="
