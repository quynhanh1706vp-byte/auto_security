#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p464c2_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep; need head; need find
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

ok(){ echo "[OK] $*" | tee -a "$OUT/log.txt"; }
err(){ echo "[ERR] $*" | tee -a "$OUT/log.txt"; exit 2; }

# 1) find runs template by title
T="$(grep -Rsl --include='*.html' '<title>VSP Runs & Reports</title>' templates 2>/dev/null | head -n1 || true)"
[ -n "$T" ] && [ -f "$T" ] || err "cannot find runs template by title under templates/"

cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
ok "template => $T (backup saved)"

python3 - "$T" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P464C2_RUNS_EXPORTS_MOUNT_V1"
if MARK in s:
    print("[OK] template already has mount")
    raise SystemExit(0)

mount = r'''
<!-- VSP_P464C2_RUNS_EXPORTS_MOUNT_V1 -->
<div id="vsp_p464c_exports_mount"></div>
<!-- /VSP_P464C2_RUNS_EXPORTS_MOUNT_V1 -->
'''.strip("\n")

# Inject right after <body ...> if present
s2 = re.sub(r"(<body[^>]*>)", r"\1\n"+mount+"\n", s, count=1, flags=re.I)
if s2 == s:
    # fallback: after <main ...> if exists
    s2 = re.sub(r"(<main[^>]*>)", r"\1\n"+mount+"\n", s, count=1, flags=re.I)

p.write_text(s2, encoding="utf-8")
print("[OK] injected mount into template")
PY

# 2) Ensure runs JS exists; we will just make P464b addon prefer mount when present
F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || err "missing $F"

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
ok "js => $F (backup saved)"

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P464C2_FORCE_MOUNT_NODE_V1"
if MARK in s:
    print("[OK] JS already patched for mount")
    raise SystemExit(0)

shim = r'''
/* --- VSP_P464C2_FORCE_MOUNT_NODE_V1 --- */
(function(){
  try{
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
/* --- /VSP_P464C2_FORCE_MOUNT_NODE_V1 --- */
'''

# Put shim at top so later addons can use it
s2 = shim + "\n" + s

# If P464b addon exists, patch its root-selection block once (best-effort)
s2 = re.sub(
    r"const root\s*=\s*[\s\S]*?\n\s*if\s*\(root\)\s*vspRender\(root\);\n",
    "const root = (window.__VSP_P464C_EXPORTS_MOUNT ? window.__VSP_P464C_EXPORTS_MOUNT() : document.body);\n    if (root) vspRender(root);\n",
    s2, count=1
)

p.write_text(s2, encoding="utf-8")
print("[OK] patched JS to prefer mount node")
PY

if command -v systemctl >/dev/null 2>&1; then
  ok "restart ${SVC}"
  sudo systemctl restart "${SVC}" || true
  sudo systemctl is-active "${SVC}" || true
fi

ok "DONE. Verify mount exists in HTML:"
curl -fsS http://127.0.0.1:8910/runs | grep -n "vsp_p464c_exports_mount" | head -n 3 | tee -a "$OUT/log.txt" || true
