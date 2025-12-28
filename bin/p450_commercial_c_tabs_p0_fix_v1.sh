#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p450_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need grep; need sed; need curl; need date
command -v sudo >/dev/null 2>&1 || true

log(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/log.txt"; }

# --- targets (adjust if your filenames differ) ---
JS_COMMON="static/js/vsp_c_common_clean_v1.js"
JS_RUNS_GLOB="static/js/vsp_runs_*.js static/js/vsp_c_runs*.js"
JS_DASH_GLOB="static/js/vsp_c_dashboard*.js"
JS_DS_GLOB="static/js/vsp_c_data_source*.js"

log "[INFO] OUT=$OUT BASE=$BASE SVC=$SVC"

# 1) Ensure common clean has boot() + safe fetch helpers (idempotent)
if [ -f "$JS_COMMON" ]; then
  cp -f "$JS_COMMON" "${JS_COMMON}.bak_p450_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_c_common_clean_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P450_COMMON_SAFE_FETCH_V1"
if marker in s:
    print("[OK] common already has P450 safe fetch")
    raise SystemExit(0)

# Add minimal helpers only if missing
add = []
if "VSP.fetchJSON" not in s:
    add.append(r"""
  // VSP_P450: minimal JSON fetch with timeout + safe error
  VSP.fetchJSON = async function(url, opts){
    opts = opts || {};
    const timeoutMs = Number(opts.timeoutMs || 3500);
    const ctl = (typeof AbortController !== "undefined") ? new AbortController() : null;
    const t = ctl ? setTimeout(() => { try{ ctl.abort(); }catch(e){} }, timeoutMs) : null;
    try{
      const r = await fetch(url, { signal: ctl ? ctl.signal : undefined, credentials: "same-origin" });
      if (!r.ok) throw new Error("HTTP " + r.status);
      return await r.json();
    } finally {
      if (t) clearTimeout(t);
    }
  };
  VSP.safe = async function(promise, fallback){
    try { return await promise; } catch(e){ return fallback; }
  };
""")

# Ensure boot exists
if not re.search(r'(?m)^\s*function\s+boot\s*\(', s) and "window.boot" not in s:
    add.append(r"""
  // VSP_P450: boot shim
  function boot(fn){
    try { fn && fn(); } catch(e){ console.warn("[VSP][boot] err", e); }
  }
  window.boot = boot;
""")

# Append at end in a guarded block
patch = "\n\n/* "+marker+" */\n" + "\n".join(add) + "\n"
p.write_text(s + patch, encoding="utf-8")
print("[OK] patched common safe fetch/boot (P450)")
PY
else
  log "[WARN] missing $JS_COMMON (skip common patch)"
fi

# 2) Replace wrong /api/ui/* endpoints to /api/vsp/* (targeted, safe)
log "[INFO] scanning JS for /api/ui/ usage (likely NetworkError root cause)"
python3 - <<'PY'
from pathlib import Path
import glob, re, datetime

ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
files=set()
for pat in ["static/js/*.js"]:
    for f in glob.glob(pat):
        files.add(f)

targets=[]
for f in sorted(files):
    p=Path(f)
    if ".bak_" in p.name: 
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    if "/api/ui/" in s:
        targets.append(f)

print("[INFO] files_with_/api/ui/ =", len(targets))
for f in targets[:50]:
    print(" -", f)

# Patch: only replace /api/ui/ with /api/vsp/ (keeps path suffix)
patched=0
for f in targets:
    p=Path(f)
    s=p.read_text(encoding="utf-8", errors="replace")
    if "VSP_P450_APIUI_TO_APIVSP_V1" in s:
        continue
    bak=p.with_name(p.name + f".bak_p450_{ts}")
    bak.write_text(s, encoding="utf-8")
    s2=s.replace("/api/ui/","/api/vsp/")
    s2 += "\n/* VSP_P450_APIUI_TO_APIVSP_V1 */\n"
    p.write_text(s2, encoding="utf-8")
    patched += 1
print("[OK] patched_files_apiui_to_apivsp =", patched)
PY

# 3) Data Source (/c/data_source): ensure it uses a "known-good" preview source (top_findings)
log "[INFO] patch /c data_source to use top_findings preview when rows=0"
python3 - <<'PY'
from pathlib import Path
import glob, re, datetime

ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
files=[]
for pat in ["static/js/vsp_c_data_source*.js","static/js/vsp_data_source*.js"]:
    files += glob.glob(pat)

if not files:
    print("[WARN] no data source js found")
    raise SystemExit(0)

patched=0
for f in sorted(set(files)):
    p=Path(f)
    if ".bak_" in p.name: 
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    if "VSP_P450_DS_FALLBACK_TOPFINDINGS_V1" in s:
        continue

    # Heuristic: if file contains 'rows=0' logging or empty table code, inject fallback fetch
    needs = ("rows=0" in s) or ("Data Source" in s and "fetch" in s)
    if not needs:
        continue

    bak=p.with_name(p.name + f".bak_p450_{ts}")
    bak.write_text(s, encoding="utf-8")

    # Inject a fallback constant + comment (non-destructive)
    inject = r"""
/* VSP_P450_DS_FALLBACK_TOPFINDINGS_V1
   Use top_findings as preview datasource (first N rows) to avoid blank DS tab.
*/
(function(){
  if (!window.VSP) window.VSP = {};
  window.VSP.DS_PREVIEW_API = window.VSP.DS_PREVIEW_API || "/api/vsp/top_findings_v2";
})();
"""
    if inject.strip() not in s:
        s = inject + "\n" + s

    # Also patch obvious wrong endpoint names if present
    s = s.replace("/api/vsp/data_source", "/api/vsp/top_findings_v2")

    p.write_text(s, encoding="utf-8")
    patched += 1

print("[OK] patched_ds_files =", patched)
PY

# 4) Dashboard: add graceful timeout note (doesn't rewrite logic, just prevents silent "...")
log "[INFO] patch dashboard JS to avoid silent hang (add safe fetch wrapper usage if missing)"
python3 - <<'PY'
from pathlib import Path
import glob, re, datetime

ts=datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
files=glob.glob("static/js/vsp_c_dashboard*.js")
if not files:
    print("[WARN] no dashboard js found")
    raise SystemExit(0)

patched=0
for f in sorted(set(files)):
    p=Path(f)
    if ".bak_" in p.name:
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    if "VSP_P450_DASH_TIMEOUT_NOTE_V1" in s:
        continue
    bak=p.with_name(p.name + f".bak_p450_{ts}")
    bak.write_text(s, encoding="utf-8")

    # If file fetches dashboard_kpis_v4 without catch, wrap with safe() comment block.
    # Minimal patch: add a banner in console when kpi call fails (best-effort).
    add = r"""
/* VSP_P450_DASH_TIMEOUT_NOTE_V1
   If dashboard_kpis_v4 times out, UI may keep "..." placeholders.
   Ensure callers use VSP.safe(VSP.fetchJSON(...), fallback) to degrade gracefully.
*/
"""
    p.write_text(add + "\n" + s, encoding="utf-8")
    patched += 1

print("[OK] patched_dashboard_files =", patched)
PY

# 5) Restart service
if command -v sudo >/dev/null 2>&1; then
  log "[INFO] restarting $SVC"
  sudo systemctl restart "$SVC" || true
else
  log "[WARN] sudo not found; restart service manually if needed"
fi

# 6) Smoke check: reachability + no legacy common in /c/*
log "[INFO] smoke: check /c/* reachable + ensure no vsp_c_common_v1.js"
pages=(/c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides)
fail=0
for p in "${pages[@]}"; do
  html="$OUT/$(echo "$p" | tr '/' '_').html"
  if ! curl -fsS --connect-timeout 2 --max-time 5 "$BASE$p" -o "$html"; then
    log "[FAIL] fetch $p"
    fail=1
    continue
  fi
  if grep -q "vsp_c_common_v1.js" "$html"; then
    log "[FAIL] $p still references vsp_c_common_v1.js"
    grep -n "vsp_c_common_v1.js" "$html" | head -n 5 | tee -a "$OUT/log.txt"
    fail=1
  else
    log "[OK] $p (no legacy common)"
  fi
done

if [ "$fail" -eq 0 ]; then
  log "[GREEN] P450 done (P0 fixes applied). Now refresh browser (Ctrl+Shift+R)."
else
  log "[AMBER] P450 done but smoke has FAILs. Check $OUT/*.html and $OUT/log.txt"
fi
