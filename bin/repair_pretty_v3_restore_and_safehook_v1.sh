#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_charts_pretty_v3.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [1] Find newest backup that passes node --check =="
BEST=""
for b in $(ls -1t "${F}.bak_"* 2>/dev/null || true); do
  if node --check "$b" >/dev/null 2>&1; then
    BEST="$b"
    break
  fi
done

if [ -z "$BEST" ]; then
  echo "[ERR] no parse-ok backup found for $F"
  echo "Hints:"
  echo "  ls -1t ${F}.bak_* | head"
  echo "  node --check <backup>"
  exit 2
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.broken_${TS}" || true
cp -f "$BEST" "$F"
echo "[OK] restored from: $BEST"
echo "[BACKUP] saved broken copy -> ${F}.broken_${TS}"

echo "== [2] Append SAFE hook (idempotent) for autocanvas + charts-ready dispatch =="
python3 - <<'PY'
import re, json
from pathlib import Path

p = Path("static/js/vsp_dashboard_charts_pretty_v3.js")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "// === VSP_PRETTY_V3_SAFE_HOOK_V1 ==="
if TAG in t:
    print("[OK] safe hook already present -> skip")
    raise SystemExit(0)

# Extract candidate canvas ids from the file (best-effort)
ids = set()

# 1) candidates = [ ... ]
m = re.search(r"\bcandidates\s*=\s*\[(.*?)\]", t, flags=re.S)
if m:
    inner = m.group(1)
    for s in re.findall(r"['\"]([^'\"]+)['\"]", inner):
        if s.strip():
            ids.add(s.strip())

# 2) direct getElementById('...')
for s in re.findall(r"getElementById\(\s*['\"]([^'\"]+)['\"]\s*\)", t):
    if s.strip():
        ids.add(s.strip())

# 3) include known placeholders (your template has these)
for s in ["vsp-chart-severity","vsp-chart-trend","vsp-chart-bytool","vsp-chart-topcwe"]:
    ids.add(s)

# keep it reasonable
ids_list = sorted(list(ids))[:40]
js_ids = json.dumps(ids_list, ensure_ascii=False)

hook = f"""
{TAG}
(function () {{
  try {{
    if (window.__VSP_PRETTY_V3_SAFE_HOOK_V1) return;
    window.__VSP_PRETTY_V3_SAFE_HOOK_V1 = true;

    var IDS = {js_ids};
    var HOLDERS = ["vsp-chart-severity","vsp-chart-trend","vsp-chart-bytool","vsp-chart-topcwe"];

    function findHolder() {{
      for (var i=0;i<HOLDERS.length;i++) {{
        var h = document.getElementById(HOLDERS[i]);
        if (h) return h;
      }}
      return null;
    }}

    function ensureCanvas(id) {{
      try {{
        var el = document.getElementById(id);
        if (el && el.tagName && el.tagName.toLowerCase() === 'canvas') return el;

        // If element exists but it's a DIV placeholder with same id -> create a canvas inside
        if (el && el.tagName && el.tagName.toLowerCase() !== 'canvas') {{
          // don't destroy if already has canvas
          var c0 = el.querySelector && el.querySelector("canvas");
          if (c0) return c0;
          var c = document.createElement('canvas');
          c.id = id + "__canvas";
          c.style.width = "100%";
          c.style.height = "100%";
          el.appendChild(c);
          return c;
        }}

        // If no element with that id, try to create it inside a known holder
        var holder = findHolder();
        if (!holder) return null;

        var c2 = document.createElement('canvas');
        c2.id = id;
        c2.style.width = "100%";
        c2.style.height = "100%";
        holder.appendChild(c2);
        return c2;
      }} catch (e) {{
        return null;
      }}
    }}

    // Create canvases best-effort
    for (var k=0;k<IDS.length;k++) ensureCanvas(IDS[k]);

    // Dispatch charts-ready so dashboard can re-init after late load
    function dispatchReady() {{
      try {{
        var eng = (window.VSP_CHARTS_ENGINE_V3 ? "V3" : (window.VSP_CHARTS_ENGINE_V2 ? "V2" : "UNKNOWN"));
        window.dispatchEvent(new CustomEvent("vsp:charts-ready", {{ detail: {{ engine: eng, ts: Date.now() }} }}));
      }} catch (e) {{
        try {{
          var ev = document.createEvent("Event");
          ev.initEvent("vsp:charts-ready", true, true);
          window.dispatchEvent(ev);
        }} catch (_) {{}}
      }}
    }}

    dispatchReady();
    console.log("[VSP_CHARTS_SAFEHOOK] autocanvas + charts-ready dispatched");
  }} catch (e) {{
    console.warn("[VSP_CHARTS_SAFEHOOK] failed", e);
  }}
}})();
"""

p.write_text(t.rstrip() + "\n" + hook + "\n", encoding="utf-8")
print("[OK] appended safe hook to pretty_v3")
PY

echo "== [3] node --check =="
node --check "$F"
echo "[OK] pretty_v3 is parseable now"
