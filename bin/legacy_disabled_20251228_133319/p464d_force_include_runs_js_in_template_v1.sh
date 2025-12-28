#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p464d_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep; need head
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

ok(){ echo "[OK] $*" | tee -a "$OUT/log.txt"; }
err(){ echo "[ERR] $*" | tee -a "$OUT/log.txt"; exit 2; }

T="templates/vsp_runs_reports_v1.html"
[ -f "$T" ] || err "missing $T (expected from your last output)"

cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
ok "backup => $OUT/$(basename "$T").bak_${TS}"

python3 - "$T" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P464D_FORCE_INCLUDE_RUNS_JS_V1"
if MARK in s:
    print("[OK] already patched template include")
    raise SystemExit(0)

# Script tag with cache bust: uses window.__VSP_ASSET_V if available, else Date.now
inject = r'''
<!-- VSP_P464D_FORCE_INCLUDE_RUNS_JS_V1 -->
<script>
(function(){
  try{
    var v = (window.__VSP_ASSET_V || (Date.now()+""));
    var src = "/static/js/vsp_runs_tab_resolved_v1.js?v=" + encodeURIComponent(v);
    if(!document.querySelector('script[data-vsp-p464d="1"]')){
      var sc = document.createElement('script');
      sc.src = src;
      sc.defer = true;
      sc.setAttribute("data-vsp-p464d","1");
      document.body.appendChild(sc);
    }
  }catch(e){}
})();
</script>
<!-- /VSP_P464D_FORCE_INCLUDE_RUNS_JS_V1 -->
'''.strip("\n")

# Insert before </body> if present, else append end
if re.search(r"</body\s*>", s, flags=re.I):
    s2 = re.sub(r"</body\s*>", inject + "\n</body>", s, count=1, flags=re.I)
else:
    s2 = s.rstrip() + "\n" + inject + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] injected forced script include")
PY

if command -v systemctl >/dev/null 2>&1; then
  ok "restart ${SVC}"
  sudo systemctl restart "${SVC}" || true
  sudo systemctl is-active "${SVC}" || true
fi

ok "Verify HTML contains P464d marker + mount:"
curl -fsS http://127.0.0.1:8910/runs | grep -n "VSP_P464D_FORCE_INCLUDE_RUNS_JS_V1\|vsp_p464c_exports_mount" | head -n 6 | tee -a "$OUT/log.txt" || true
ok "DONE. Hard refresh browser (Ctrl+Shift+R) then open /runs."
