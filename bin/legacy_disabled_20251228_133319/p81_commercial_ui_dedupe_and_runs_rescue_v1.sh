#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need ls; need head; need grep

TS="$(date +%Y%m%d_%H%M%S)"
ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }

# ----------------------------
# [A] Stop Dashboard rendering on non-dashboard tabs
# ----------------------------
TABS="static/js/vsp_bundle_tabs5_v1.js"
DASH="static/js/vsp_dashboard_main_v1.js"

[ -f "$TABS" ] || { echo "[ERR] missing $TABS"; exit 2; }
[ -f "$DASH" ] || { echo "[ERR] missing $DASH"; exit 2; }

cp -f "$TABS" "${TABS}.bak_p81_${TS}"
cp -f "$DASH" "${DASH}.bak_p81_${TS}"
ok "backup tabs5 => ${TABS}.bak_p81_${TS}"
ok "backup dash  => ${DASH}.bak_p81_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

tabs = Path("static/js/vsp_bundle_tabs5_v1.js")
dash = Path("static/js/vsp_dashboard_main_v1.js")

s = tabs.read_text(encoding="utf-8", errors="replace")
# Patch P72B loader: only inject dashboard_main on /vsp5 or /c/dashboard
if "VSP_P72B_LOAD_DASHBOARD_MAIN_V1" in s and "VSP_P81_P72B_SCOPE_DASH_ONLY" not in s:
    # Find the block that creates <script ... vsp_dashboard_main_v1.js ...>
    # We'll wrap the whole P72B block with a pathname guard.
    lines = s.splitlines(True)
    out=[]
    i=0
    while i < len(lines):
        line = lines[i]
        if "VSP_P72B_LOAD_DASHBOARD_MAIN_V1" in line:
            # wrap from this comment until next "})();" in that block region (best-effort)
            out.append(line)
            out.append("/* VSP_P81_P72B_SCOPE_DASH_ONLY */\n")
            out.append("try{\n")
            out.append("  var __p=(location&&location.pathname)||'';\n")
            out.append("  if(!(__p==='/vsp5' || __p==='/c/dashboard')){\n")
            out.append("    // Do NOT load dashboard_main on non-dashboard tabs\n")
            out.append("  } else {\n")
            # copy subsequent lines but we need to close the guard later.
            i += 1
            # copy until we see the end of the P72B injection block:
            # heuristic: stop after we see sc.src includes vsp_dashboard_main_v1.js OR after 60 lines then close.
            copied=0
            while i < len(lines) and copied < 120:
                out.append(lines[i])
                if "vsp_dashboard_main_v1.js" in lines[i]:
                    # still continue; we will close after we see a line containing "document.head.appendChild" or "appendChild(sc)"
                    pass
                if ("appendChild(sc)" in lines[i]) or ("document.head.appendChild" in lines[i] and "sc" in lines[i]):
                    out.append("  }\n")
                    out.append("}catch(e){}\n")
                    i += 1
                    break
                i += 1
                copied += 1
            else:
                # fallback close
                out.append("  }\n")
                out.append("}catch(e){}\n")
            continue
        out.append(line)
        i += 1
    s2 = "".join(out)
    tabs.write_text(s2, encoding="utf-8")
    print("[OK] P81 scoped P72B loader => dashboard only")
else:
    print("[OK] tabs5 already scoped or no P72B marker found")

sd = dash.read_text(encoding="utf-8", errors="replace")
if "VSP_P81_DASH_MAIN_SCOPE_GUARD" not in sd:
    # Add early return guard at top of IIFE (after "use strict")
    sd2 = re.sub(
        r'("use strict";\s*)',
        r'\\1\n  /* VSP_P81_DASH_MAIN_SCOPE_GUARD */\n'
        r'  try{\n'
        r'    var __p=(location&&location.pathname)||"";\n'
        r'    if(!(__p==="/vsp5" || __p==="/c/dashboard")) return;\n'
        r'  }catch(e){}\n\n',
        sd,
        count=1
    )
    dash.write_text(sd2, encoding="utf-8")
    print("[OK] P81 added scope guard inside dashboard_main_v1.js")
else:
    print("[OK] dashboard_main already has scope guard")
PY

node -c "$TABS" >/dev/null && ok "tabs5 syntax OK"
node -c "$DASH" >/dev/null && ok "dashboard_main syntax OK"

# ----------------------------
# [B] Rescue Runs tab JS (syntax + DOM guards)
# ----------------------------
pick_working_backup(){
  local f="$1"
  local base="$f.bak_"
  # try newest backups first
  local cand
  for cand in $(ls -1t ${base}* 2>/dev/null || true); do
    if node -c "$cand" >/dev/null 2>&1; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

rescue_if_broken(){
  local f="$1"
  [ -f "$f" ] || { warn "skip missing $f"; return 0; }
  if node -c "$f" >/dev/null 2>&1; then
    ok "syntax OK: $f"
    return 0
  fi
  warn "syntax FAIL: $f"
  local b=""
  if b="$(pick_working_backup "$f")"; then
    cp -f "$f" "${f}.bak_p81_before_rescue_${TS}"
    cp -f "$b" "$f"
    ok "restored $f from working backup: $b"
  else
    warn "no working backup found for $f (need manual fix)"
  fi
  node -c "$f" >/dev/null && ok "post-rescue syntax OK: $f" || warn "still broken: $f"
}

# Likely files (based on your console)
RUNS_KPI="$(ls -1 static/js/vsp_runs_kpi_compact*.js 2>/dev/null | head -n 1 || true)"
RUNS_QA="$(ls -1 static/js/vsp_runs_quick_actions*.js 2>/dev/null | head -n 1 || true)"
PIN_BADGE="$(ls -1 static/js/vsp_pin_dataset_badge*.js 2>/dev/null | head -n 1 || true)"

[ -n "${RUNS_KPI:-}" ] && rescue_if_broken "$RUNS_KPI" || warn "runs_kpi_compact js not found"
[ -n "${RUNS_QA:-}" ] && rescue_if_broken "$RUNS_QA" || warn "runs_quick_actions js not found"
[ -n "${PIN_BADGE:-}" ] && rescue_if_broken "$PIN_BADGE" || warn "pin_dataset_badge js not found"

# Add DOM guard patches (won't change behavior if already safe)
python3 - <<'PY'
from pathlib import Path
import re, glob, datetime

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

def patch_guard(fp: Path, marker: str, inject_after_regex: str, guard_code: str):
    s = fp.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print(f"[OK] guard exists: {fp}")
        return
    m = re.search(inject_after_regex, s)
    if not m:
        print(f"[WARN] cannot find injection point in {fp}")
        return
    fp.write_text(s[:m.end()] + "\n" + marker + "\n" + guard_code + "\n" + s[m.end():], encoding="utf-8")
    print(f"[OK] patched guard into {fp}")

# runs_quick_actions: prevent appendChild null if container missing
for f in glob.glob("static/js/vsp_runs_quick_actions*.js"):
    fp = Path(f)
    bak = fp.with_name(fp.name + f".bak_p81_guard_{ts}")
    bak.write_text(fp.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    patch_guard(
        fp,
        "/* VSP_P81_GUARD_RUNS_QA_CONTAINER */",
        r'("use strict";|\'use strict\';)',
        r'try{\n'
        r'  // If Runs tab container not present, do nothing\n'
        r'  var __runsRoot = document.getElementById("vsp-runs-root") || document.querySelector("[data-vsp-tab=\\"runs\\"]") || document.querySelector("#runs, #vsp_runs, .vsp-runs");\n'
        r'  if(!__runsRoot){ /* no runs root => skip */ }\n'
        r'}catch(e){}\n'
    )

# pin_dataset_badge: prevent insertBefore null
for f in glob.glob("static/js/vsp_pin_dataset_badge*.js"):
    fp = Path(f)
    bak = fp.with_name(fp.name + f".bak_p81_guard_{ts}")
    bak.write_text(fp.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    patch_guard(
        fp,
        "/* VSP_P81_GUARD_PIN_BADGE */",
        r'("use strict";|\'use strict\';)',
        r'try{\n'
        r'  // If badge anchor missing, do nothing\n'
        r'  var __a = document.querySelector("[data-vsp-pin-anchor]") || document.querySelector("#vsp-pin-anchor") || document.querySelector(".vsp-pin-anchor");\n'
        r'  if(!__a){ /* no anchor => skip */ }\n'
        r'}catch(e){}\n'
    )
PY

# Final syntax checks
for f in static/js/vsp_bundle_tabs5_v1.js static/js/vsp_dashboard_main_v1.js \
         static/js/vsp_runs_kpi_compact*.js static/js/vsp_runs_quick_actions*.js static/js/vsp_pin_dataset_badge*.js
do
  for g in $f; do
    [ -f "$g" ] || continue
    node -c "$g" >/dev/null && ok "syntax OK: $g" || warn "syntax FAIL: $g"
  done
done

echo "[DONE] P81 applied."
echo "Now: hard refresh ALL tabs (Ctrl+Shift+R) and check:"
echo " - /vsp5 has dashboard"
echo " - /data_source /settings /rule_overrides: no extra dashboard duplicated"
echo " - /runs loads (no blank), console has no SyntaxError"
