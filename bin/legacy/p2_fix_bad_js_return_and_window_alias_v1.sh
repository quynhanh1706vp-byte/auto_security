#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node; need grep; need head

F_BAD="static/js/vsp_runs_tab_force_v3.js"
F_TABS="static/js/vsp_tabs4_autorid_v1.js"

[ -f "$F_BAD" ] || { echo "[ERR] missing $F_BAD"; exit 2; }
[ -f "$F_TABS" ] || { echo "[ERR] missing $F_TABS"; exit 2; }

echo "== [0] Backup =="
cp -f "$F_BAD"  "${F_BAD}.bak_fixreturn_${TS}"
cp -f "$F_TABS" "${F_TABS}.bak_windowalias_${TS}"
echo "[BACKUP] $F_BAD.bak_fixreturn_${TS}"
echo "[BACKUP] $F_TABS.bak_windowalias_${TS}"

echo "== [1] Fix parse: wrap vsp_runs_tab_force_v3.js in IIFE if needed (makes top-level 'return' legal) =="
python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_runs_tab_force_v3.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_IIFE_WRAP_FOR_RETURN_V1"
if marker in s:
    print("[SKIP] already wrapped")
else:
    wrapped = "/* %s */\n;(function(){\n%s\n})();\n" % (marker, s)
    p.write_text(wrapped, encoding="utf-8")
    print("[OK] wrapped with IIFE:", marker)
PY

echo "== [2] Fix runtime: ensure _window alias exists in vsp_tabs4_autorid_v1.js =="
python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_tabs4_autorid_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP__WINDOW_ALIAS_V1"
if marker in s:
    print("[SKIP] _window alias already present")
else:
    # insert right after the first line (your file already begins with VSP_NATIVE_TIMER_SNAPSHOT_V1 marker)
    lines=s.splitlines(True)
    ins = "/* %s */\nvar _window = (typeof window!=='undefined'?window:this);\n" % marker
    if lines:
        lines.insert(1, ins)
    else:
        lines=[ins]
    p.write_text("".join(lines), encoding="utf-8")
    print("[OK] inserted _window alias:", marker)
PY

echo "== [3] Parse check (node) on the two files =="
node - <<'NODE'
const fs=require('fs'), vm=require('vm');
function parse(p){ try{ new vm.Script(fs.readFileSync(p,'utf8'),{filename:p}); console.log("[OK]",p); }
catch(e){ console.log("[BAD]",p, String(e).split("\n")[0]); process.exit(1); } }
parse("static/js/vsp_runs_tab_force_v3.js");
parse("static/js/vsp_tabs4_autorid_v1.js");
NODE

echo "== [4] Restart service best-effort =="
if command -v systemctl >/dev/null 2>&1; then
  (sudo systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted $SVC") || echo "[WARN] restart failed or svc not found: $SVC"
else
  echo "[WARN] systemctl not found; skip"
fi

echo "== [5] Quick grep: _window should not cause issues now =="
grep -n "_window" static/js/vsp_tabs4_autorid_v1.js | head -n 10 || true

echo "[DONE] Ctrl+Shift+R on /vsp5, then re-run JS parse scan if needed."
