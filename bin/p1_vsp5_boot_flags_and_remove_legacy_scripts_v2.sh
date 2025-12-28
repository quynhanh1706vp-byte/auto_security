#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<PY
from pathlib import Path
import re

TS = "${TS}"  # <-- injected from bash
MARK = "VSP_P1_VSP5_BOOT_FLAGS_V2"

tpl_dir = Path("templates")
tpls = list(tpl_dir.glob("*.html"))
if not tpls:
    raise SystemExit("[ERR] no templates/*.html found")

def score(path: Path) -> int:
    s = path.read_text(encoding="utf-8", errors="replace")
    sc = 0
    if "vsp_bundle_commercial_v2.js" in s: sc += 5
    if "/vsp5" in s: sc += 3
    if "vsp_p0_fetch_shim_v1.js" in s: sc += 3
    if "vsp_rid_autofix_v1.js" in s: sc += 2
    if "VSP • Dashboard" in s or "VSP - Dashboard" in s: sc += 1
    return sc

tpls.sort(key=score, reverse=True)
tpl = tpls[0]
s = tpl.read_text(encoding="utf-8", errors="replace")

if score(tpl) == 0:
    raise SystemExit(f"[ERR] cannot confidently pick vsp5 template. Top candidate: {tpl}")

bak = tpl.with_suffix(tpl.suffix + f".bak_bootflags_{TS}")
bak.write_text(s, encoding="utf-8")

boot = r"""
<!-- VSP_P1_VSP5_BOOT_FLAGS_V2 -->
<script>
(()=>{try{
  // Lock commercial behavior BEFORE any bundle loads
  window.__vsp_disable_legacy_dash_v1 = true;
  window.__vsp_disable_interceptors_v1 = true;
  window.__vsp_disable_fetch_shim_v1 = true;
  window.__vsp_disable_probe_sarif_v1 = true;
  window.__vsp_latest_rid_url_v1 = "/api/vsp/rid_latest_gate_root";

  // Clear pinned RID values that start with RUN_
  try{
    for (let i=localStorage.length-1;i>=0;i--){
      const k = localStorage.key(i);
      const v = (localStorage.getItem(k)||"");
      if (/^RUN_/.test(v)) { localStorage.removeItem(k); }
    }
  }catch(_){}
}catch(_){}})();
</script>
<!-- /VSP_P1_VSP5_BOOT_FLAGS_V2 -->
"""

if MARK not in s:
    s = re.sub(r'(<head[^>]*>)', r'\1\n' + boot, s, count=1, flags=re.I)

# Remove legacy script includes on /vsp5 page
def drop_script(fragment: str, text: str) -> str:
    return re.sub(
        rf'\s*<script[^>]+src="[^"]*{re.escape(fragment)}[^"]*"[^>]*>\s*</script>\s*',
        "\n",
        text,
        flags=re.I
    )

s2 = drop_script("vsp_p0_fetch_shim_v1.js", s)
s2 = drop_script("vsp_rid_autofix_v1.js", s2)

tpl.write_text(s2, encoding="utf-8")
print("[OK] patched template:", tpl)
print("[BACKUP]", bak)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
