#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import re

# Find template that likely serves /vsp5 by searching for known strings
tpls = list(Path("templates").glob("*.html"))
hits = []
for t in tpls:
    s = t.read_text(encoding="utf-8", errors="replace")
    if "/vsp5" in s or "vsp_bundle_commercial_v2.js" in s or "VSP • Dashboard" in s or "vsp_p0_fetch_shim_v1.js" in s:
        hits.append(t)

if not hits:
    raise SystemExit("[ERR] cannot find dashboard template in templates/*.html")

# pick the best candidate: contains vsp_bundle_commercial_v2.js or vsp_p0_fetch_shim_v1.js
hits.sort(key=lambda p: (
    ("vsp_p0_fetch_shim_v1.js" in p.read_text(encoding="utf-8", errors="replace")) +
    ("vsp_bundle_commercial_v2.js" in p.read_text(encoding="utf-8", errors="replace")) * 2
), reverse=True)

tpl = hits[0]
s = tpl.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_VSP5_BOOT_FLAGS_V1"
if MARK not in s:
    boot = r"""
<!-- VSP_P1_VSP5_BOOT_FLAGS_V1 -->
<script>
(()=>{try{
  // Lock commercial behavior BEFORE any bundle loads
  window.__vsp_disable_legacy_dash_v1 = true;
  window.__vsp_disable_interceptors_v1 = true;
  window.__vsp_disable_fetch_shim_v1 = true;
  window.__vsp_disable_probe_sarif_v1 = true;
  window.__vsp_latest_rid_url_v1 = "/api/vsp/rid_latest_gate_root";

  // Clear any pinned RUN_* RID values
  for (let i=localStorage.length-1;i>=0;i--){
    const k = localStorage.key(i);
    const v = (localStorage.getItem(k)||"");
    if (/^RUN_/.test(v) || /rid/i.test(k) && /vsp/i.test(k)) {
      try { localStorage.removeItem(k); } catch(_){}
    }
  }
}catch(_){}})();
</script>
<!-- /VSP_P1_VSP5_BOOT_FLAGS_V1 -->
"""
    # inject right after <head> tag
    s = re.sub(r'(<head[^>]*>)', r'\1\n' + boot, s, count=1, flags=re.I)

# Remove legacy script includes (keep files on disk, just stop loading on /vsp5)
def drop_script(src_fragment: str, text: str) -> str:
    # remove <script ...src="...fragment..."></script> (various formats)
    text2 = re.sub(rf'\s*<script[^>]+src="[^"]*{re.escape(src_fragment)}[^"]*"[^>]*>\s*</script>\s*',
                   "\n", text, flags=re.I)
    return text2

s2 = s
s2 = drop_script("vsp_p0_fetch_shim_v1.js", s2)
s2 = drop_script("vsp_rid_autofix_v1.js", s2)

if s2 != s:
    s = s2

# write back with backup
bak = tpl.with_suffix(tpl.suffix + f".bak_bootflags_{TS}")
bak.write_text(tpl.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
tpl.write_text(s, encoding="utf-8")
print("[OK] patched template:", tpl)
print("[BACKUP]", bak)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
