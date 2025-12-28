#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p129_${TS}"
echo "[OK] backup: ${F}.bak_p129_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_c_common_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P129_FORCE_JSON_OBSERVER" in s:
    print("[OK] P129 already present")
    raise SystemExit(0)

patch = r"""
/* VSP_P129_FORCE_JSON_OBSERVER */
(function(){
  try{
    if (window.__VSP_P129_INSTALLED__) return;
    window.__VSP_P129_INSTALLED__ = true;

    const onTarget = /(?:^|\/)c\/(settings|rule_overrides)(?:$|[?#])/.test(location.pathname||"");

    function wrapPre(pre){
      if (!pre || pre.nodeType !== 1) return;
      if (pre.closest && pre.closest("details.vsp-details")) return;

      const txt = ((pre.textContent || "")).trim();
      if (!txt) return;

      const looksJson = (txt.startsWith("{") && txt.endsWith("}")) || (txt.startsWith("[") && txt.endsWith("]"));
      if (!looksJson) return;

      const lines = txt.split("\n").length;
      const minLines = onTarget ? 8 : 30;
      if (lines < minLines) return;

      const details = document.createElement("details");
      details.className = "vsp-details";
      details.open = false;

      const sum = document.createElement("summary");
      sum.textContent = "Raw JSON (click to expand)";
      details.appendChild(sum);

      const parent = pre.parentNode;
      if (!parent) return;

      parent.insertBefore(details, pre);
      details.appendChild(pre);

      pre.style.maxHeight = onTarget ? "260px" : "220px";
      pre.style.overflow = "auto";
      pre.style.marginTop = "10px";
    }

    function scan(){
      document.querySelectorAll("pre").forEach(wrapPre);
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", scan);
    else scan();

    const obs = new MutationObserver((mut)=>{
      for (const m of mut){
        for (const n of (m.addedNodes || [])){
          if (!n || n.nodeType !== 1) continue;
          if (n.tagName === "PRE") wrapPre(n);
          else if (n.querySelectorAll) n.querySelectorAll("pre").forEach(wrapPre);
        }
      }
    });

    obs.observe(document.documentElement || document.body, {subtree:true, childList:true});
    try{ console.log("[VSP] P129 installed (collapse JSON observer)"); }catch(_){}
  }catch(e){
    try{ console.warn("[VSP] P129 failed:", e); }catch(_){}
  }
})();
"""
p.write_text(s + "\n\n" + patch + "\n", encoding="utf-8")
print("[OK] appended P129 into static/js/vsp_c_common_v1.js")
PY

if command -v node >/dev/null 2>&1; then
  echo "== [CHECK] node --check =="
  node --check static/js/vsp_c_common_v1.js && echo "[OK] JS syntax OK"
fi

echo ""
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
