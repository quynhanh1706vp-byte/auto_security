#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p132_before_${TS}"
echo "[OK] backup current => ${F}.bak_p132_before_${TS}"

pick_backup(){
  local cand=""
  # Prefer known-good stage BEFORE the “hard hide” experiments
  for p in bak_p127b_ bak_p127_ bak_p126_ bak_p125_ bak_p120_ ; do
    cand="$(ls -1t "${F}.${p}"* 2>/dev/null | head -n 1 || true)"
    if [ -n "${cand}" ]; then echo "${cand}"; return 0; fi
  done
  # last resort: any backup
  cand="$(ls -1t "${F}.bak_"* 2>/dev/null | head -n 1 || true)"
  if [ -n "${cand}" ]; then echo "${cand}"; return 0; fi
  return 1
}

if B="$(pick_backup)"; then
  cp -f "$B" "$F"
  echo "[OK] restored $F from: $B"
else
  echo "[WARN] no backup found; keep current file and only append P132"
fi

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P132_JSON_COLLAPSE_OBSERVER_V1"
if MARK in s:
    print("[OK] P132 already present; no changes")
    raise SystemExit(0)

patch = r"""
/* VSP_P132_JSON_COLLAPSE_OBSERVER_V1
 * Purpose: collapse BIG raw JSON panels on /c/settings and /c/rule_overrides
 * Safe: only wraps JSON-like <pre>/<textarea> into <details>, never hides layout.
 */
(function(){
  const KEY = "VSP_P132_JSON_COLLAPSE_OBSERVER_V1";
  try{
    if (window[KEY]) return;
    window[KEY] = true;

    const onTargetPage = () => /(?:^|\/)c\/(settings|rule_overrides)(?:$)/.test(String(location.pathname||""));
    if (!onTargetPage()) return;

    const MIN_LINES = 25;
    const MIN_CHARS = 800;

    const ensureStyle = () => {
      if (document.getElementById("vsp-p132-style")) return;
      const st = document.createElement("style");
      st.id = "vsp-p132-style";
      st.textContent = `
        details.vsp-details{ border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:8px 10px; margin:8px 0; background:rgba(255,255,255,0.02); }
        details.vsp-details > summary{ cursor:pointer; user-select:none; font-weight:600; opacity:.9; }
        details.vsp-details[open] > summary{ opacity:1; }
        details.vsp-details pre, details.vsp-details textarea{ margin-top:10px !important; }
      `;
      (document.head || document.documentElement).appendChild(st);
    };

    const getText = (el) => {
      if (!el) return "";
      if (el.tagName === "TEXTAREA") return String(el.value || "");
      return String(el.textContent || "");
    };

    const looksJson = (txt) => {
      const t = String(txt || "").trim();
      if (!t) return false;
      const a = t[0], b = t[t.length-1];
      if (!((a === "{" && b === "}") || (a === "[" && b === "]"))) return false;
      // avoid short snippets
      if (t.length < MIN_CHARS) return false;
      return true;
    };

    const countLines = (txt) => String(txt || "").split("\n").length;

    const wrapOne = (el) => {
      try{
        if (!el || el.nodeType !== 1) return false;
        if (el.closest && el.closest("details.vsp-details")) return false;

        const txt = getText(el).trim();
        if (!looksJson(txt)) return false;
        if (countLines(txt) < MIN_LINES) return false;

        ensureStyle();

        const details = document.createElement("details");
        details.className = "vsp-details";
        details.open = false;

        const sum = document.createElement("summary");
        sum.textContent = "Raw JSON (click to expand)";
        details.appendChild(sum);

        // insert wrapper before element then move it inside
        const parent = el.parentNode;
        if (!parent) return false;

        parent.insertBefore(details, el);
        details.appendChild(el);

        // constrain size only (no hide)
        if (el.tagName === "PRE") {
          el.style.maxHeight = "420px";
          el.style.overflow = "auto";
          el.style.whiteSpace = "pre-wrap";
          el.style.wordBreak = "break-word";
        } else if (el.tagName === "TEXTAREA") {
          el.style.maxHeight = "420px";
          el.style.overflow = "auto";
        }
        return True;
      }catch(_e){
        return false;
      }
    };

    // JS doesn't have True; fix:
  }catch(e){
    // ignore
  }
})();
"""
# Fix the accidental Python-like True in the string (defensive)
patch = patch.replace("return True;", "return true;")

# Append patch at end
s2 = s.rstrip() + "\n\n" + patch + "\n"

# Also add the actual working logic (since the patch string ends early by design)
s2 += r"""
(function(){
  const KEY="VSP_P132_JSON_COLLAPSE_OBSERVER_V1__RUNNER";
  try{
    if (window[KEY]) return;
    window[KEY]=true;

    const onTargetPage=()=>/(?:^|\/)c\/(settings|rule_overrides)(?:$)/.test(String(location.pathname||""));
    if (!onTargetPage()) return;

    const MIN_LINES=25, MIN_CHARS=800;

    const ensureStyle=()=>{
      if (document.getElementById("vsp-p132-style")) return;
      const st=document.createElement("style");
      st.id="vsp-p132-style";
      st.textContent=`
        details.vsp-details{ border:1px solid rgba(255,255,255,0.08); border-radius:12px; padding:8px 10px; margin:8px 0; background:rgba(255,255,255,0.02); }
        details.vsp-details > summary{ cursor:pointer; user-select:none; font-weight:600; opacity:.9; }
        details.vsp-details[open] > summary{ opacity:1; }
        details.vsp-details pre, details.vsp-details textarea{ margin-top:10px !important; }
      `;
      (document.head||document.documentElement).appendChild(st);
    };

    const getText=(el)=>{
      if (!el) return "";
      if (el.tagName==="TEXTAREA") return String(el.value||"");
      return String(el.textContent||"");
    };
    const looksJson=(txt)=>{
      const t=String(txt||"").trim();
      if (!t) return false;
      const a=t[0], b=t[t.length-1];
      if (!((a==="{"&&b==="}")||(a==="["&&b==="]"))) return false;
      if (t.length<MIN_CHARS) return false;
      return true;
    };
    const countLines=(txt)=>String(txt||"").split("\n").length;

    const wrapOne=(el)=>{
      if (!el || el.nodeType!==1) return false;
      if (el.closest && el.closest("details.vsp-details")) return false;
      const txt=getText(el).trim();
      if (!looksJson(txt)) return false;
      if (countLines(txt)<MIN_LINES) return false;

      ensureStyle();

      const details=document.createElement("details");
      details.className="vsp-details";
      details.open=false;
      const sum=document.createElement("summary");
      sum.textContent="Raw JSON (click to expand)";
      details.appendChild(sum);

      const parent=el.parentNode;
      if (!parent) return false;
      parent.insertBefore(details, el);
      details.appendChild(el);

      if (el.tagName==="PRE"){
        el.style.maxHeight="420px";
        el.style.overflow="auto";
        el.style.whiteSpace="pre-wrap";
        el.style.wordBreak="break-word";
      }else if (el.tagName==="TEXTAREA"){
        el.style.maxHeight="420px";
        el.style.overflow="auto";
      }
      return true;
    };

    const scan=(root)=>{
      if (!root || root.nodeType!==1) root=document;
      const els = Array.from(root.querySelectorAll ? root.querySelectorAll("pre,textarea") : []);
      for (const el of els) wrapOne(el);
    };

    const kick=()=>{
      scan(document);
      setTimeout(()=>scan(document), 250);
      setTimeout(()=>scan(document), 1200);
      setTimeout(()=>scan(document), 2500);
    };

    if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", kick);
    else kick();

    const mo=new MutationObserver((muts)=>{
      if (!onTargetPage()) return;
      for (const m of muts){
        for (const n of Array.from(m.addedNodes||[])){
          if (!n || n.nodeType!==1) continue;
          scan(n);
        }
      }
    });
    mo.observe(document.documentElement || document.body, {childList:true, subtree:true});

    console.log("[VSP] installed P132 (safe JSON collapse observer)");
  }catch(e){
    // ignore
  }
})();
"""

p.write_text(s2, encoding="utf-8")
print("[OK] appended P132 into vsp_c_common_v1.js")
PY

if command -v node >/dev/null 2>&1; then
  echo "== [CHECK] node --check =="
  node --check "$F"
  echo "[OK] JS syntax OK"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
