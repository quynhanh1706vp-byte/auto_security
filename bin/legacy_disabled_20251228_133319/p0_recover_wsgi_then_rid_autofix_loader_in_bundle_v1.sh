#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need grep; need sed
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
BUNDLE="static/js/vsp_bundle_commercial_v2.js"
AUTOJS="static/js/vsp_rid_autofix_v1.js"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }
[ -f "$AUTOJS" ] || { echo "[ERR] missing $AUTOJS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [1/4] recover WSGI to last good backup that py_compile OK =="
python3 - <<'PY'
from pathlib import Path
import py_compile, sys

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

good = None
for p in baks[:200]:
    try:
        py_compile.compile(str(p), doraise=True)
        good = p
        break
    except Exception:
        continue

if not good:
    print("[ERR] no compiling backup found (searched up to 200 newest).")
    sys.exit(2)

ts = __import__("time").strftime("%Y%m%d_%H%M%S")
snap = w.with_name(w.name + f".bak_before_recover_{ts}")
snap.write_text(w.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
w.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")

print("[OK] restored WSGI from:", good.name)
print("[BACKUP] current broken snapshot saved as:", snap.name)
PY

echo "== py_compile recovered WSGI =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo
echo "== [2/4] add RID autofix loader into bundle (NO WSGI injection) =="
cp -f "$BUNDLE" "${BUNDLE}.bak_rid_loader_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_rid_loader_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_RID_AUTOFIX_LOADER_V1"
if marker in s:
    print("[OK] loader already present, skip patch")
    raise SystemExit(0)

loader = r"""
/* VSP_P0_RID_AUTOFIX_LOADER_V1 */
(()=> {
  try{
    if (window.__vsp_p0_rid_autofix_loader_v1) return;
    window.__vsp_p0_rid_autofix_loader_v1 = true;

    // already loaded?
    if (document.querySelector('script[src*="vsp_rid_autofix_v1.js"]')) return;

    // reuse asset_v from current bundle query (?v=...)
    let v = "";
    try{
      const srcs = Array.from(document.scripts).map(x=>x && x.src ? x.src : "");
      const me = srcs.find(u => u.includes("vsp_bundle_commercial_v2.js"));
      const m = me && me.match(/[?&]v=([^&]+)/);
      v = (m && m[1]) ? m[1] : "";
    }catch(e){}

    if (!v) v = String(Date.now());

    const sc = document.createElement("script");
    sc.src = "/static/js/vsp_rid_autofix_v1.js?v=" + encodeURIComponent(v);
    sc.defer = true;
    document.head.appendChild(sc);
  }catch(e){}
})();
"""

# Put loader near the very top, after any leading comments/usestrict wrappers.
# We keep it super safe: inject at start of file.
s2 = loader.lstrip("\n") + "\n" + s
p.write_text(s2, encoding="utf-8")
print("[OK] inserted rid autofix loader at top of bundle")
PY

if [ "$node_ok" = "1" ]; then
  node --check "$BUNDLE" && echo "[OK] node --check bundle OK"
fi

echo
echo "== [3/4] restart service =="
systemctl restart "$SVC" || true
systemctl --no-pager --full status "$SVC" | sed -n '1,22p' || true

echo
echo "== [4/4] verify endpoints and script tags =="
curl -fsS -I http://127.0.0.1:8910/vsp5 | head -n 8 || true
curl -fsS http://127.0.0.1:8910/vsp5 | grep -nE 'vsp_bundle_commercial_v2|vsp_rid_autofix_v1|gate_story_v1' || true
curl -fsS http://127.0.0.1:8910/api/vsp/runs?limit=3 | head -c 260; echo || true

echo
echo "[DONE] If /vsp5 loads, hard refresh: Ctrl+Shift+R"
