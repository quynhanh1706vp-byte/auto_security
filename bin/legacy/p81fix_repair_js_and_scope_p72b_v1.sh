#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need ls; need head; need date

TS="$(date +%Y%m%d_%H%M%S)"
ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
fail(){ echo "[FAIL] $*" >&2; exit 2; }

TABS="static/js/vsp_bundle_tabs5_v1.js"
DASH="static/js/vsp_dashboard_main_v1.js"
RUNS="static/js/vsp_runs_kpi_compact_v3.js"

restore_latest_bak(){
  local f="$1"
  local bak
  bak="$(ls -1t "${f}.bak_p81_"* 2>/dev/null | head -n 1 || true)"
  [ -n "$bak" ] || fail "No backup found for $f (expected ${f}.bak_p81_*)"
  cp -f "$bak" "$f"
  ok "restored $f <= $bak"
}

echo "== [1] restore broken files from latest .bak_p81_* =="
restore_latest_bak "$TABS"
restore_latest_bak "$DASH"

echo "== [2] patch tabs5: scope P72B safely (no try-mess) =="
python3 - <<'PY'
from pathlib import Path
import re

tabs = Path("static/js/vsp_bundle_tabs5_v1.js")
s = tabs.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P72B_LOAD_DASHBOARD_MAIN_V1"
TAG  = "VSP_P81FIX_P72B_SCOPE_DASH_ONLY_V2"

if MARK not in s:
    print("[WARN] P72B marker not found; skip tabs5 scope patch")
else:
    if TAG in s:
        print("[OK] tabs5 already patched (P81FIX)")
    else:
        pos = s.find(MARK)
        # Insert a flag right after the marker comment line
        # We do NOT use try{} without catch. We'll compute boolean with try/catch on one line safely.
        ins = (
            f"/* {TAG} */\n"
            "var __VSP_P81_DASH_OK=false;\n"
            "try{var __p=(location&&location.pathname)||\"\"; __VSP_P81_DASH_OK=(__p===\"/vsp5\"||__p===\"/c/dashboard\");}catch(e){}\n"
        )

        # Insert after the comment line containing the marker
        # Find end of that line
        line_end = s.find("\n", pos)
        if line_end == -1:
            line_end = pos + len(MARK)
        s2 = s[:line_end+1] + ins + s[line_end+1:]

        # Now, only append dashboard_main if __VSP_P81_DASH_OK.
        # We patch the FIRST appendChild(sc) AFTER the marker (so we don't affect other tabs).
        after = s2[line_end+1:]
        idx = after.find("appendChild(sc")
        if idx == -1:
            idx = after.find("appendChild(sc);")
        if idx == -1:
            print("[WARN] cannot find appendChild(sc) after P72B marker; tabs5 guard inserted but not enforced")
        else:
            # Replace the exact call with guarded call (single occurrence)
            # Find statement end ';'
            stmt_start = after.rfind("\n", 0, idx) + 1
            stmt_end = after.find(";", idx)
            if stmt_end == -1:
                stmt_end = after.find("\n", idx)
            stmt = after[stmt_start:stmt_end+1]
            guarded = f"if(__VSP_P81_DASH_OK){{ {stmt.strip()} }}\n"
            after2 = after[:stmt_start] + guarded + after[stmt_end+1:]
            s2 = s2[:line_end+1] + after2

        tabs.write_text(s2, encoding="utf-8")
        print("[OK] patched tabs5 P72B scope (P81FIX)")
PY

echo "== [3] patch dashboard_main: add scope guard without regex backrefs =="
python3 - <<'PY'
from pathlib import Path

dash = Path("static/js/vsp_dashboard_main_v1.js")
s = dash.read_text(encoding="utf-8", errors="replace")

TAG="VSP_P81FIX_DASH_MAIN_SCOPE_GUARD_V2"
if TAG in s:
    print("[OK] dashboard_main already patched (P81FIX)")
else:
    needle = '"use strict";'
    i = s.find(needle)
    if i == -1:
        needle = "'use strict';"
        i = s.find(needle)
    if i == -1:
        print("[WARN] cannot find use strict; inserting guard at top")
        insert_at = 0
    else:
        insert_at = i + len(needle)

    guard = (
        f"\n/* {TAG} */\n"
        "try{\n"
        "  var __p=(location&&location.pathname)||\"\";\n"
        "  if(!(__p===\"/vsp5\" || __p===\"/c/dashboard\")){\n"
        "    // not dashboard => do nothing\n"
        "    // IMPORTANT: do NOT execute dashboard renderer on other tabs\n"
        "    return;\n"
        "  }\n"
        "}catch(e){}\n"
    )

    # NOTE: return only valid if inside an IIFE/function. dashboard_main is an IIFE in your build.
    s2 = s[:insert_at] + guard + s[insert_at:]
    dash.write_text(s2, encoding="utf-8")
    print("[OK] patched dashboard_main scope guard (P81FIX)")
PY

echo "== [4] fix runs_kpi_compact_v3.js syntax =="
if [ -f "$RUNS" ]; then
  cp -f "$RUNS" "${RUNS}.bak_p81fix_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_kpi_compact_v3.js")
s=p.read_text(encoding="utf-8", errors="replace")

# Fix the broken order array: ... "INFO", trace:"TRACE" -> "INFO","TRACE"
s2 = re.sub(
    r'const\s+order\s*=\s*\[\s*"CRITICAL"\s*,\s*"HIGH"\s*,\s*"MEDIUM"\s*,\s*"LOW"\s*,\s*"INFO"\s*,\s*trace\s*:\s*"TRACE"\s*\]\s*;',
    'const order=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];',
    s
)

if s2 != s:
    p.write_text(s2, encoding="utf-8")
    print("[OK] fixed order[] syntax in vsp_runs_kpi_compact_v3.js")
else:
    print("[WARN] did not match the broken order[] pattern; file may have different bug")
PY
else
  warn "missing $RUNS, skip"
fi

echo "== [5] syntax check =="
node -c "$TABS" >/dev/null && ok "tabs5 syntax OK" || fail "tabs5 still broken"
node -c "$DASH" >/dev/null && ok "dashboard_main syntax OK" || fail "dashboard_main still broken"
[ -f "$RUNS" ] && (node -c "$RUNS" >/dev/null && ok "runs_kpi_compact_v3 syntax OK" || warn "runs_kpi_compact_v3 still broken")

echo "[DONE] P81FIX applied."
echo "[NEXT] Hard refresh (Ctrl+Shift+R). Then check:"
echo " - /vsp5: dashboard OK"
echo " - /data_source /settings /rule_overrides: NO duplicated dashboard section"
echo " - /runs: not blank, and console has no SyntaxError"
