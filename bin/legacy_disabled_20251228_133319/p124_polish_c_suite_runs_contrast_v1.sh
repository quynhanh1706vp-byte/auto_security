#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p124_${TS}"
echo "[OK] backup: ${F}.bak_p124_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P124_C_SUITE_RUNS_CONTRAST_V1"
if MARK in s:
    print("[OK] P124 already present, skip.")
    raise SystemExit(0)

inject = r"""
/* === VSP_P124_C_SUITE_RUNS_CONTRAST_V1 ===
   Goals:
   - Fix low-contrast visited links in Runs table
   - Make buttons (esp. Use RID) dark-theme instead of white
   - Clamp huge JSON <pre> blocks in Settings/Rule Overrides
*/
(function(){
  try{
    if (window.__VSP_P124_CSUITE__) return;
    window.__VSP_P124_CSUITE__ = 1;

    var css = `
/* --- palette knobs --- */
:root{
  --vspc-link: #86c5ff;
  --vspc-link-hover: #b7dcff;
  --vspc-btn-bg: rgba(255,255,255,0.06);
  --vspc-btn-bg-hover: rgba(255,255,255,0.10);
  --vspc-btn-bd: rgba(255,255,255,0.14);
  --vspc-btn-bd-hover: rgba(255,255,255,0.22);
  --vspc-text: rgba(255,255,255,0.88);
  --vspc-muted: rgba(255,255,255,0.68);
}

/* --- links: unify normal/visited to avoid purple shock --- */
.vsp-c a, .vspc a{
  color: var(--vspc-link) !important;
  text-decoration: none;
}
.vsp-c a:visited, .vspc a:visited{
  color: var(--vspc-link) !important;
}
.vsp-c a:hover, .vspc a:hover{
  color: var(--vspc-link-hover) !important;
  text-decoration: underline;
}

/* --- buttons: kill white default buttons --- */
.vsp-c button, .vspc button,
.vsp-c .btn, .vspc .btn{
  background: var(--vspc-btn-bg) !important;
  border: 1px solid var(--vspc-btn-bd) !important;
  color: var(--vspc-text) !important;
  border-radius: 10px !important;
  padding: 6px 10px !important;
  font-size: 12px !important;
  line-height: 1 !important;
  box-shadow: none !important;
}
.vsp-c button:hover, .vspc button:hover,
.vsp-c .btn:hover, .vspc .btn:hover{
  background: var(--vspc-btn-bg-hover) !important;
  border-color: var(--vspc-btn-bd-hover) !important;
}

/* --- Runs table: tighten actions look like pills --- */
.vsp-c table td a, .vsp-c table th a{
  display: inline-block;
  padding: 2px 8px;
  border-radius: 999px;
  background: rgba(255,255,255,0.04);
  border: 1px solid rgba(255,255,255,0.10);
  margin-right: 6px;
}
.vsp-c table td a:hover{
  background: rgba(255,255,255,0.08);
  border-color: rgba(255,255,255,0.18);
}

/* --- clamp huge JSON blocks --- */
.vsp-c pre, .vspc pre{
  max-height: 280px;
  overflow: auto;
  color: var(--vspc-text);
}
.vsp-c pre, .vspc pre{
  scrollbar-width: thin;
}

/* --- subtle table readability --- */
.vsp-c table{
  color: var(--vspc-text);
}
.vsp-c table tr{
  border-bottom: 1px solid rgba(255,255,255,0.06);
}
.vsp-c table tr:hover{
  background: rgba(255,255,255,0.03);
}
`;

    var st = document.getElementById("VSP_P124_STYLE");
    if(!st){
      st = document.createElement("style");
      st.id = "VSP_P124_STYLE";
      st.type = "text/css";
      st.appendChild(document.createTextNode(css));
      (document.head || document.documentElement).appendChild(st);
    }
  }catch(e){
    try{ console.warn("[VSPC] P124 inject failed:", e); }catch(_){}
  }
})();
"""
p.write_text(s + "\n" + inject + "\n", encoding="utf-8")
print("[OK] appended P124 into", p)
PY

echo "[OK] P124 applied."
echo ""
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/runs"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
