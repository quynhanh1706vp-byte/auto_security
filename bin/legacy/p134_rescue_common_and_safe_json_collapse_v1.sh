#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p134_before_${TS}"
echo "[OK] backup current => ${F}.bak_p134_before_${TS}"

pick_restore(){
  local cand=""
  # Prefer: backup right before p127 (cleanest)
  cand="$(ls -1 ${F}.bak_p127_* 2>/dev/null | sort | tail -n 1 || true)"
  if [ -n "$cand" ]; then echo "$cand"; return 0; fi

  # Otherwise pick newest backup that DOES NOT contain our messy P128..P133 markers
  local x
  for x in $(ls -1 ${F}.bak_* 2>/dev/null | sort -r); do
    if grep -Eq 'P12(8|9)|P13(0|1|2|3)|VSP_P127|collapse_JSON|hide live JSON' "$x"; then
      continue
    fi
    # If node exists, ensure syntax ok
    if command -v node >/dev/null 2>&1; then
      if node --check "$x" >/dev/null 2>&1; then echo "$x"; return 0; fi
    else
      echo "$x"; return 0
    fi
  done
  return 1
}

RESTORE="$(pick_restore || true)"
if [ -z "$RESTORE" ]; then
  echo "[ERR] cannot find a suitable backup to restore."
  echo "HINT: ls -1 ${F}.bak_* | tail -n 50"
  exit 3
fi

cp -f "$RESTORE" "$F"
echo "[OK] restored $F from: $RESTORE"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P134_JSON_COLLAPSE_SAFE_V1"
if MARK in s:
    print("[OK] P134 already installed")
    sys.exit(0)

patch = r"""
// --- VSP_P134_JSON_COLLAPSE_SAFE_V1 ---
// Purpose: safely collapse huge JSON <pre> blocks on /c/settings and /c/rule_overrides
// Strategy: DO NOT re-parent or remove nodes. Only inject a small toolbar before <pre> + set maxHeight.
(function(){
  try{
    const path = (location && location.pathname) ? location.pathname : "";
    const onTarget = (path === "/c/settings" || path === "/c/rule_overrides");
    if (!onTarget) return;

    const CSS_ID = "vsp_json_collapse_css_p134";
    function ensureCss(){
      if (document.getElementById(CSS_ID)) return;
      const st = document.createElement("style");
      st.id = CSS_ID;
      st.textContent = `
        .vsp-json-toolbar{display:flex;gap:8px;align-items:center;margin:6px 0 6px 0;}
        .vsp-json-btn{cursor:pointer;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);
          color:inherit;border-radius:10px;padding:4px 10px;font-size:12px;line-height:16px;}
        .vsp-json-meta{opacity:.75;font-size:12px}
        .vsp-json-pre-collapsed{max-height:120px !important; overflow:auto !important;}
      `;
      document.head.appendChild(st);
    }

    function looksLikeJson(txt){
      txt = (txt || "").trim();
      if (!txt) return False;
      const a = (txt.startsWith("{") && txt.endsWith("}"));
      const b = (txt.startsWith("[") && txt.endsWith("]"));
      return a || b;
    }

    function scan(){
      ensureCss();
      const pres = Array.from(document.querySelectorAll("pre"));
      for (const pre of pres){
        if (!pre || pre.dataset.vspJsonCollapse === "1") continue;

        const txt = (pre.textContent || "").trim();
        if (!txt) continue;

        const isJson = ((txt.startsWith("{") && txt.endsWith("}")) || (txt.startsWith("[") && txt.endsWith("]")));
        if (!isJson) continue;

        const lines = txt.split("\n").length;
        const longEnough = (lines >= 18) || (txt.length >= 1200);
        if (!longEnough) continue;

        // mark processed
        pre.dataset.vspJsonCollapse = "1";

        // toolbar
        const bar = document.createElement("div");
        bar.className = "vsp-json-toolbar";

        const btn = document.createElement("button");
        btn.className = "vsp-json-btn";
        btn.type = "button";

        const meta = document.createElement("span");
        meta.className = "vsp-json-meta";
        meta.textContent = `JSON • ${lines} lines`;

        // collapsed by default
        let collapsed = true;
        pre.classList.add("vsp-json-pre-collapsed");
        btn.textContent = "Expand";

        btn.addEventListener("click", function(){
          collapsed = !collapsed;
          if (collapsed){
            pre.classList.add("vsp-json-pre-collapsed");
            btn.textContent = "Expand";
          }else{
            pre.classList.remove("vsp-json-pre-collapsed");
            btn.textContent = "Collapse";
          }
        });

        bar.appendChild(btn);
        bar.appendChild(meta);

        // insert toolbar right before <pre> without moving <pre>
        const parent = pre.parentElement;
        if (parent){
          parent.insertBefore(bar, pre);
        }
      }
    }

    // throttle scan to avoid mutation storms
    let scheduled = false;
    function scheduleScan(){
      if (scheduled) return;
      scheduled = true;
      requestAnimationFrame(() => {
        scheduled = false;
        scan();
      });
    }

    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", scheduleScan, {once:true});
    }else{
      scheduleScan();
    }

    const mo = new MutationObserver(() => scheduleScan());
    mo.observe(document.documentElement || document.body, {childList:true, subtree:true});

    console.log("[VSP] installed P134 (safe JSON pre collapse)");
  }catch(e){
    console.warn("[VSP] P134 error", e);
  }
})();
"""
# Fix a Python-to-JS typo: "False" -> "false" (keep patch robust)
patch = patch.replace("return False;", "return false;")

p.write_text(s + "\n" + patch + "\n", encoding="utf-8")
print("[OK] appended P134 into vsp_c_common_v1.js")
PY

echo "== [CHECK] node --check =="
if command -v node >/dev/null 2>&1; then
  node --check "$F" && echo "[OK] JS syntax OK"
else
  echo "[WARN] node not found, skipped syntax check"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
