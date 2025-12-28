#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p205_before_${TS}"
echo "[OK] backup current => ${F}.bak_p205_before_${TS}"

# Prefer restore from p127b (known good baseline). Fallback: keep current.
BASE="$(ls -1 static/js/vsp_c_common_v1.js.bak_p127b_* 2>/dev/null | tail -n 1 || true)"
if [ -n "${BASE:-}" ] && [ -f "$BASE" ]; then
  cp -f "$BASE" "$F"
  echo "[OK] restored base from: $BASE"
else
  echo "[WARN] no bak_p127b_* found; keep current as base"
fi

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P205_JSON_COLLAPSE_GLOBAL_OBSERVER_V1"
if marker in s:
    print("[OK] P205 already present")
    raise SystemExit(0)

addon = r"""
/* VSP_P205_JSON_COLLAPSE_GLOBAL_OBSERVER_V1
 * Goal:
 * - Collapse ALL JSON <pre> blocks on /c/settings and /c/rule_overrides (and generally any /c/* pages),
 *   even if DOM is re-rendered later.
 * - Do NOT touch editable textarea editor.
 * - Persist expand/collapse in localStorage so it won't "snap back".
 */
(function(){
  try{
    if (window.__VSP_P205_INSTALLED) { console.log("[VSP] P205 already installed"); return; }
    window.__VSP_P205_INSTALLED = true;

    const PATH = (location && location.pathname) ? location.pathname : "";
    const ENABLE = (PATH.indexOf("/c/") === 0); // only UI suite pages

    function injectStyleOnce(){
      if (document.getElementById("vsp_p205_style")) return;
      const st = document.createElement("style");
      st.id = "vsp_p205_style";
      st.textContent = `
        .vsp-json-togglebar{
          display:flex; align-items:center; justify-content:space-between;
          gap:10px; padding:8px 10px; margin:6px 0 8px 0;
          border-radius:10px;
          background: rgba(255,255,255,0.04);
          border: 1px solid rgba(255,255,255,0.08);
          cursor:pointer;
          user-select:none;
          font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
          font-size: 12px;
          color: rgba(255,255,255,0.85);
        }
        .vsp-json-togglebar:hover{ border-color: rgba(255,255,255,0.16); }
        .vsp-json-togglebar .left{ opacity:0.95; }
        .vsp-json-togglebar .right{ opacity:0.65; font-size:11px; }
        .vsp-json-hidden{ display:none !important; }
      `;
      document.head.appendChild(st);
    }

    function normLines(txt){
      return (txt || "").replace(/\r\n/g,"\n").replace(/\r/g,"\n");
    }
    function looksLikeJson(txt){
      const t = (txt||"").trim();
      if (t.length < 2) return false;
      const a = t[0], b = t[t.length-1];
      if (!((a==="{" && b==="}") || (a==="[" && b==="]"))) return false;
      // avoid tiny JSON (still ok but not needed)
      return true;
    }
    function countLines(txt){
      const t = normLines(txt);
      if (!t) return 0;
      return t.split("\n").length;
    }
    function makeKeyForPre(pre, idx){
      // stable-ish key even if DOM rerenders
      const hint = (pre.id ? ("#"+pre.id) : "") + (pre.className ? ("."+String(pre.className).split(/\s+/).slice(0,3).join(".")) : "");
      return "vsp_p205|" + PATH + "|pre|" + idx + "|" + hint;
    }

    function bindPre(pre, idx){
      if (!pre || pre.nodeType !== 1) return;
      if (pre.dataset && pre.dataset.vspP205Bound === "1") return;

      // only <pre> that looks like JSON
      const txt = pre.textContent || "";
      if (!looksLikeJson(txt)) return;

      // Heuristic: only collapse if "big enough" to annoy
      const n = countLines(txt);
      if (n < 6) return;

      injectStyleOnce();

      const key = makeKeyForPre(pre, idx);
      const lsKey = "vsp_p205_open:" + key;
      const open = (localStorage.getItem(lsKey) === "1");

      const bar = document.createElement("div");
      bar.className = "vsp-json-togglebar";
      const left = document.createElement("div");
      left.className = "left";
      left.textContent = `JSON (${n} lines) — click to ${open ? "collapse" : "expand"}`;
      const right = document.createElement("div");
      right.className = "right";
      right.textContent = "P205";
      bar.appendChild(left);
      bar.appendChild(right);

      // Insert bar before <pre>
      pre.parentNode.insertBefore(bar, pre);

      function apply(openNow){
        if (openNow){
          pre.classList.remove("vsp-json-hidden");
          left.textContent = `JSON (${countLines(pre.textContent||"")} lines) — click to collapse`;
          localStorage.setItem(lsKey, "1");
        } else {
          pre.classList.add("vsp-json-hidden");
          left.textContent = `JSON (${countLines(pre.textContent||"")} lines) — click to expand`;
          localStorage.setItem(lsKey, "0");
        }
      }

      // default collapsed unless user opened
      apply(open);

      bar.addEventListener("click", function(){
        const isHidden = pre.classList.contains("vsp-json-hidden");
        apply(isHidden); // if hidden -> open, else collapse
      });

      // watch text changes (some code updates pre.textContent)
      const mo = new MutationObserver(function(){
        // keep current open/closed state, only refresh line count label
        const isHidden = pre.classList.contains("vsp-json-hidden");
        if (isHidden) left.textContent = `JSON (${countLines(pre.textContent||"")} lines) — click to expand`;
        else left.textContent = `JSON (${countLines(pre.textContent||"")} lines) — click to collapse`;
      });
      mo.observe(pre, {subtree:true, childList:true, characterData:true});

      pre.dataset.vspP205Bound = "1";
    }

    function scan(){
      if (!ENABLE) return;
      const pres = Array.from(document.querySelectorAll("pre"));
      for (let i=0;i<pres.length;i++){
        bindPre(pres[i], i);
      }
    }

    // initial
    setTimeout(scan, 50);
    setTimeout(scan, 400);
    setTimeout(scan, 1200);

    // re-apply on DOM changes (tab switch/render)
    let t = null;
    const body = document.body || document.documentElement;
    const mo = new MutationObserver(function(){
      if (t) clearTimeout(t);
      t = setTimeout(scan, 120);
    });
    if (body) mo.observe(body, {subtree:true, childList:true});

    console.log("[VSP] installed P205 (global JSON <pre> collapse observer)");
  }catch(e){
    console.warn("[VSP] P205 failed:", e);
  }
})();
"""
# Append safely
p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended P205 into vsp_c_common_v1.js")
PY

echo "== [CHECK] node --check =="
node --check "$F"
echo "[OK] JS syntax OK"

echo ""
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
