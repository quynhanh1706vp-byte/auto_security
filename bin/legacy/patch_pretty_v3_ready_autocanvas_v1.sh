#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_charts_pretty_v3.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_ready_autocanvas_${TS}"
echo "[BACKUP] $F.bak_ready_autocanvas_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("static/js/vsp_dashboard_charts_pretty_v3.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_PRETTY_V3_READY_AUTOCANVAS_V1 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) Patch helper find-canvas candidates: if not found -> create canvas inside known placeholders
# Anchor: the loop line you already grepped: document.getElementById(candidates[i])
anchor = r"var\s+el\s*=\s*document\.getElementById\(candidates\[i\]\)\s*;"
m = re.search(anchor, t)
if not m:
    print("[ERR] cannot find candidates loop anchor in pretty_v3")
    raise SystemExit(2)

# Insert autocanvas fallback near the end of that helper function by finding the next "return null" after the anchor.
# We do a conservative replace: first 'return null;' after anchor gets expanded.
idx = t.find(m.group(0))
tail = t[idx:]
m2 = re.search(r"\breturn\s+null\s*;\s*", tail)
if not m2:
    print("[ERR] cannot find 'return null' after candidates loop")
    raise SystemExit(3)

insert = r"""
%s

%s
  // === VSP_PRETTY_V3_READY_AUTOCANVAS_V1 ===
  // Fallback: if canvas not found, try auto-create it under known placeholders
  try {
    var guessHost = function(id){
      var s = String(id||"").toLowerCase();
      if (s.includes("severity")) return "vsp-chart-severity";
      if (s.includes("trend")) return "vsp-chart-trend";
      if (s.includes("bytool") || s.includes("tool")) return "vsp-chart-bytool";
      if (s.includes("topcwe") || s.includes("cwe")) return "vsp-chart-topcwe";
      return null;
    };
    for (var k=0; k<candidates.length; k++){
      var cid = candidates[k];
      var hostId = guessHost(cid);
      if (!hostId) continue;
      var host = document.getElementById(hostId);
      if (!host) continue;
      // prevent duplicates
      if (document.getElementById(cid)) return document.getElementById(cid);

      var cv = document.createElement("canvas");
      cv.id = cid;
      cv.style.width = "100%%";
      cv.style.height = "100%%";
      cv.style.display = "block";
      host.innerHTML = "";
      host.appendChild(cv);
      console.log("[VSP_CHARTS_V3] autocreated canvas:", cid, "in", hostId);
      return cv;
    }
  } catch(e) {
    console.warn("[VSP_CHARTS_V3] autocanvas failed:", e);
  }
  // === END VSP_PRETTY_V3_READY_AUTOCANVAS_V1 ===

""" % (m.group(0), "")

# replace first return null; after anchor
start = idx + m2.start()
end = idx + m2.end()
t = t[:start] + insert + "return null;\n" + t[end:]

# 2) After engine export, dispatch charts-ready event
# Anchor: window.VSP_CHARTS_ENGINE_V3 = {
m3 = re.search(r"window\.VSP_CHARTS_ENGINE_V3\s*=\s*\{", t)
if not m3:
    print("[ERR] cannot find window.VSP_CHARTS_ENGINE_V3 export")
    raise SystemExit(4)

if "vsp:charts-ready" not in t:
    hook = r"""
// === VSP_PRETTY_V3_READY_AUTOCANVAS_V1 ===
try {
  window.dispatchEvent(new CustomEvent('vsp:charts-ready', { detail: { engine: 'V3' } }));
  console.log('[VSP_CHARTS_V3] dispatched vsp:charts-ready');
} catch(e) {}
// === END VSP_PRETTY_V3_READY_AUTOCANVAS_V1 ===
"""
    # insert right after the first "window.VSP_CHARTS_ENGINE_V3 = {" line's next newline
    pos = t.find("\n", m3.start())
    t = t[:pos+1] + hook + t[pos+1:]

p.write_text(t, encoding="utf-8")
print("[OK] patched pretty_v3: autocanvas + charts-ready event")
PY

echo "== node --check =="
node --check "$F"
echo "[OK] done"
