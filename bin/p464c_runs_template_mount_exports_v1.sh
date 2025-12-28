#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p464c_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep; need ls; need head
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

ok(){ echo "[OK] $*" | tee -a "$OUT/log.txt"; }
err(){ echo "[ERR] $*" | tee -a "$OUT/log.txt"; exit 2; }

# 1) find runs template
T=""
for f in templates/*.html templates/**/*.html 2>/dev/null; do
  if grep -q "<title>VSP Runs & Reports</title>" "$f" 2>/dev/null; then
    T="$f"; break
  fi
done
[ -n "$T" ] && [ -f "$T" ] || err "cannot find runs template by title. Try: ls -1 templates | head"

cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
ok "template => $T (backup saved)"

python3 - "$T" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P464C_RUNS_EXPORTS_MOUNT_V1"
if MARK in s:
    print("[OK] template already has mount")
    raise SystemExit(0)

mount = r'''
<!-- VSP_P464C_RUNS_EXPORTS_MOUNT_V1 -->
<div id="vsp_p464c_exports_mount"></div>
<!-- /VSP_P464C_RUNS_EXPORTS_MOUNT_V1 -->
'''.strip("\n")

# Prefer inject after main header/KPI panel marker if present, else after <body>
if "VSP_P2_RUNS_KPI_PANEL" in s:
    s2 = re.sub(r"(<!--\s*====================\s*/VSP_P2_RUNS_KPI_PANEL_V1\s*====================\s*-->[\s\S]*?)",
                r"\1\n"+mount+"\n",
                s, count=1)
    if s2 == s:
        # fallback: after opening body
        s2 = re.sub(r"(<body[^>]*>)", r"\1\n"+mount+"\n", s, count=1, flags=re.I)
else:
    s2 = re.sub(r"(<body[^>]*>)", r"\1\n"+mount+"\n", s, count=1, flags=re.I)

p.write_text(s2, encoding="utf-8")
print("[OK] injected mount into template")
PY

# 2) patch JS to mount specifically into #vsp_p464c_exports_mount if present
F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || err "missing $F (expected runs js)"

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
ok "js => $F (backup saved)"

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

# If P464b exists, keep it; just ensure it prefers the mount node
MARK2="VSP_P464C_FORCE_MOUNT_NODE_V1"
if MARK2 in s:
    print("[OK] JS already force-mounts")
    raise SystemExit(0)

patch = r'''
/* --- VSP_P464C_FORCE_MOUNT_NODE_V1 --- */
(function(){
  try{
    // Prefer explicit mount in /runs template
    window.__VSP_P464C_EXPORTS_MOUNT = function(){
      return document.querySelector('#vsp_p464c_exports_mount')
        || document.querySelector('#vsp_runs_root')
        || document.querySelector('#vsp_runs')
        || document.querySelector('#runs_root')
        || document.querySelector('.vsp-runs-root')
        || document.querySelector('main')
        || document.body;
    };
  }catch(e){}
})();
/* --- /VSP_P464C_FORCE_MOUNT_NODE_V1 --- */
'''

# Inject near top (after first IIFE marker if present)
if "use strict" in s[:4000]:
    s2 = s.replace("use strict", "use strict\n"+patch, 1)
else:
    s2 = patch + "\n" + s

# Also patch existing root selection in P464b addon if present: replace its root chooser with mount helper
s2 = re.sub(r"const root\s*=\s*[\s\S]*?;\n\s*if\s*\(root\)\s*vspRender\(root\);",
            "const root = (window.__VSP_P464C_EXPORTS_MOUNT ? window.__VSP_P464C_EXPORTS_MOUNT() : (document.body));\n    if (root) vspRender(root);",
            s2, count=1)

p.write_text(s2, encoding="utf-8")
print("[OK] patched JS to prefer mount node")
PY

if command -v systemctl >/dev/null 2>&1; then
  ok "restart ${SVC}"
  sudo systemctl restart "${SVC}" || true
  sudo systemctl is-active "${SVC}" || true
fi

ok "DONE. Refresh /runs and you MUST see Exports panel now."
ok "Quick HTML check (mount present):"
curl -fsS http://127.0.0.1:8910/runs | grep -n "vsp_p464c_exports_mount" | head -n 3 | tee -a "$OUT/log.txt" || true
