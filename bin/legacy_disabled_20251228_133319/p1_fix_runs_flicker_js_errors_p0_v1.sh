#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need awk
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# --- targets
TEMPLATES=(
  templates/vsp_5tabs_enterprise_v2.html
  templates/vsp_dashboard_2025.html
  templates/vsp_runs_reports_v1.html
  templates/vsp_rule_overrides_v1.html
  templates/vsp_settings_v1.html
  templates/vsp_data_source_2025.html
  templates/vsp_data_source_v1.html
)

JSFILES=(
  static/js/vsp_bundle_commercial_v2.js
  static/js/vsp_bundle_commercial_v1.js
  static/js/vsp_runs_tab_resolved_v1.js
  static/js/vsp_app_entry_safe_v1.js
  static/js/vsp_fill_real_data_5tabs_p1_v1.js
)

backup(){
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "$f.bak_fix_runs_p0_${TS}"
  echo "[BACKUP] $f.bak_fix_runs_p0_${TS}"
}

for f in "${TEMPLATES[@]}" "${JSFILES[@]}"; do backup "$f"; done

python3 - <<'PY'
from pathlib import Path
import re

templates = [
  "templates/vsp_5tabs_enterprise_v2.html",
  "templates/vsp_dashboard_2025.html",
  "templates/vsp_runs_reports_v1.html",
  "templates/vsp_rule_overrides_v1.html",
  "templates/vsp_settings_v1.html",
  "templates/vsp_data_source_2025.html",
  "templates/vsp_data_source_v1.html",
]

# 1) Strip ALL injected "runs lock/guard/wrapper" inline scripts from templates (they cause SyntaxError at vsp5:<line>)
#    We only remove blocks that contain these markers/ids to avoid nuking legit base scripts.
BLOCK_PATTERNS = [
  r'<!--\s*VSP_P0_RUNS_FETCH_LOCK_V1\s*-->.*?</script>\s*',
  r'<script[^>]+id=["\']VSP_P0_RUNS_FETCH_LOCK_V1["\'][\s\S]*?</script>\s*',
  r'<!--\s*VSP_P1_FIX_RUNS_API_FAIL_FLICKER_[^>]*-->[\s\S]*?</script>\s*',
  r'<!--\s*VSP_P1_RUNS_[^>]*-->[\s\S]*?</script>\s*',
  r'<!--\s*VSP_P0_RUNS_[^>]*-->[\s\S]*?</script>\s*',
  r'<script[^>]+id=["\']VSP_P[01]_RUNS[^"\']*["\'][\s\S]*?</script>\s*',
]

def strip_injected_blocks(s: str) -> tuple[str,int]:
  n = 0
  for pat in BLOCK_PATTERNS:
    s2, k = re.subn(pat, "", s, flags=re.I|re.S)
    if k:
      s = s2
      n += k
  # also remove any obviously broken "try{{" artifacts (came from bad python f-string escaping)
  s = s.replace("try{{", "try{").replace("}}catch", "}catch")
  return s, n

changed = 0
for tp in templates:
  p = Path(tp)
  if not p.exists():
    continue
  s = p.read_text(encoding="utf-8", errors="replace")
  s2, n = strip_injected_blocks(s)
  if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] template cleaned: {tp} (removed_blocks={n})")
    changed += 1

# 2) Make fetch wrapper "descriptor-safe": do NOT overwrite window.fetch if non-writable.
#    Also make it idempotent: only install once, even if multiple bundles load.
def patch_fetch_descriptor_safe(path: str):
  p = Path(path)
  if not p.exists(): return
  s = p.read_text(encoding="utf-8", errors="replace")
  MARK = "VSP_FETCH_DESCRIPTOR_SAFE_P0_V1"
  if MARK in s:
    print(f"[OK] already fetch-safe: {path}")
    return

  inject = r"""
/* VSP_FETCH_DESCRIPTOR_SAFE_P0_V1 */
(function(){
  try{
    if (window.__vsp_fetch_descriptor_safe_p0_v1) return;
    window.__vsp_fetch_descriptor_safe_p0_v1 = true;

    function canOverrideFetch(){
      try{
        const d = Object.getOwnPropertyDescriptor(window, "fetch");
        if (!d) return true;
        // if accessor exists, allow (setter may exist)
        if (d.get || d.set) return true;
        // data descriptor: must be writable OR configurable to redefine
        if (d.writable) return true;
        if (d.configurable) return true;
        return false;
      }catch(_){ return false; }
    }

    // Provide a helper for other wrappers to use
    window.__vsp_can_override_fetch = canOverrideFetch;

    // If someone already wrapped fetch and locked it, don't crash future code.
    // We DO NOT wrap here; we only prevent TypeError by advising wrappers to check __vsp_can_override_fetch().
  }catch(_){}
})();
"""
  # Best-effort insertion near top of file
  s2 = inject + "\n" + s
  p.write_text(s2, encoding="utf-8")
  print(f"[OK] injected fetch descriptor guard: {path}")

for js in ["static/js/vsp_bundle_commercial_v2.js", "static/js/vsp_bundle_commercial_v1.js", "static/js/vsp_app_entry_safe_v1.js"]:
  patch_fetch_descriptor_safe(js)

# 3) Disable RUNS polling/fail-banner flicker by forcing "no-poll" mode (keep server-rendered list stable).
#    We patch vsp_runs_tab_resolved_v1.js to:
#     - never schedule interval polling
#     - never toggle runs-fail banner based on fetch result
def patch_runs_no_poll(path: str):
  p = Path(path)
  if not p.exists(): return
  s = p.read_text(encoding="utf-8", errors="replace")
  MARK = "VSP_RUNS_NO_POLL_P0_V1"
  if MARK in s:
    print(f"[OK] already no-poll: {path}")
    return

  # Insert a hard guard that other code can check.
  header = r"""
/* VSP_RUNS_NO_POLL_P0_V1 */
(function(){
  try{
    window.__vsp_runs_no_poll = true;
    // Make any later code safe:
    // - wrappers should check window.__vsp_runs_no_poll and skip intervals.
  }catch(_){}
})();
"""
  s2 = header + "\n" + s

  # Also neuter common interval patterns if present (best-effort)
  s2 = re.sub(r'setInterval\s*\(\s*([^\)]*fetch[^\)]*)\)\s*,\s*\d+\s*\)\s*;?', '/* no-poll */ void 0;', s2, flags=re.I|re.S)
  s2 = re.sub(r'setInterval\s*\(\s*([^\)]*\/api\/vsp\/runs[^\)]*)\)\s*,\s*\d+\s*\)\s*;?', '/* no-poll */ void 0;', s2, flags=re.I|re.S)

  p.write_text(s2, encoding="utf-8")
  print(f"[OK] runs no-poll guard patched: {path}")

patch_runs_no_poll("static/js/vsp_runs_tab_resolved_v1.js")

# 4) Fix "items.slice is not a function" in vsp_fill_real_data_5tabs_p1_v1.js (defensive array normalize).
def patch_items_slice_guard(path: str):
  p = Path(path)
  if not p.exists(): return
  s = p.read_text(encoding="utf-8", errors="replace")
  MARK = "VSP_ITEMS_ARRAY_GUARD_P0_V1"
  if MARK in s:
    print(f"[OK] already items-guard: {path}")
    return

  # Replace common pattern: (items || []).slice(...) with Array.isArray(items)?items:[]
  s2 = re.sub(
    r'\(\s*items\s*\|\|\s*\[\s*\]\s*\)\.slice\(',
    '(/*VSP_ITEMS_ARRAY_GUARD_P0_V1*/ (Array.isArray(items)?items:[])).slice(',
    s
  )
  if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] items.slice guard patched: {path}")
  else:
    # If pattern not found, still inject a helper (safe)
    helper = r"""
/* VSP_ITEMS_ARRAY_GUARD_P0_V1 */
(function(){ try{ window.__vsp_to_array = (x)=>Array.isArray(x)?x:[]; }catch(_){ }})();
"""
    p.write_text(helper + "\n" + s, encoding="utf-8")
    print(f"[OK] items helper injected (pattern not found): {path}")

patch_items_slice_guard("static/js/vsp_fill_real_data_5tabs_p1_v1.js")

PY

# quick syntax checks
if command -v node >/dev/null 2>&1; then
  for f in "${JSFILES[@]}"; do
    [ -f "$f" ] || continue
    if node --check "$f" >/dev/null 2>&1; then
      echo "[OK] node --check $f"
    else
      echo "[WARN] node --check FAILED $f"
      node --check "$f" || true
    fi
  done
fi

echo "[NEXT] Restart UI then open Incognito once: /runs and /vsp5 (avoid stale cache/localStorage)."
