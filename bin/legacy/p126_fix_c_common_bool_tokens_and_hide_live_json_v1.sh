#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p126_${TS}"
echo "[OK] backup: ${F}.bak_p126_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

path = Path("static/js/vsp_c_common_v1.js")
s = path.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P126_FIX_BOOL_TOKENS_V1"
if MARK in s:
    print("[OK] P126 already applied (marker found). Still re-checking syntax...")
else:
    out = []
    i = 0
    n = len(s)
    rep_and = 0
    rep_or = 0

    CODE = 0
    SQ = 1
    DQ = 2
    TPL = 3
    LINEC = 4
    BLOCKC = 5

    st = CODE
    while i < n:
        c = s[i]
        nxt = s[i+1] if i+1 < n else ""

        if st == CODE:
            # comments
            if c == "/" and nxt == "/":
                out.append("//"); i += 2; st = LINEC; continue
            if c == "/" and nxt == "*":
                out.append("/*"); i += 2; st = BLOCKC; continue

            # strings
            if c == "'":
                out.append(c); i += 1; st = SQ; continue
            if c == '"':
                out.append(c); i += 1; st = DQ; continue
            if c == "`":
                out.append(c); i += 1; st = TPL; continue

            # identifiers / keywords
            if c.isalpha() or c == "_" or c == "$":
                j = i + 1
                while j < n and (s[j].isalnum() or s[j] in "_$"):
                    j += 1
                tok = s[i:j]
                if tok == "and":
                    out.append("&&"); rep_and += 1
                elif tok == "or":
                    out.append("||"); rep_or += 1
                else:
                    out.append(tok)
                i = j
                continue

            out.append(c); i += 1
            continue

        if st == LINEC:
            out.append(c); i += 1
            if c == "\n":
                st = CODE
            continue

        if st == BLOCKC:
            if c == "*" and nxt == "/":
                out.append("*/"); i += 2; st = CODE; continue
            out.append(c); i += 1
            continue

        if st in (SQ, DQ):
            out.append(c); i += 1
            if c == "\\" and i < n:
                # escape next char
                out.append(s[i]); i += 1
                continue
            if (st == SQ and c == "'") or (st == DQ and c == '"'):
                st = CODE
            continue

        if st == TPL:
            out.append(c); i += 1
            if c == "\\" and i < n:
                out.append(s[i]); i += 1
                continue
            if c == "`":
                st = CODE
            continue

    fixed = "".join(out)

    # append cleanup (idempotent)
    addon = r"""
/* VSP_P126_FIX_BOOL_TOKENS_V1
   - replace bare 'and'/'or' tokens to JS '&&'/'||' safely
   - hide legacy live JSON debug panels on Settings / Rule Overrides
*/
(function(){
  try{
    const p = (location && location.pathname) ? location.pathname : "";
    const isSettings = /\/c\/settings\/?$/.test(p);
    const isOverrides = /\/c\/rule_overrides\/?$/.test(p);
    if(!(isSettings || isOverrides)) return;

    // Hide big "live JSON" panels (legacy debug)
    const needles = [
      "live links",
      "live from /api",
      "Rule Overrides (live",
      "Settings (live"
    ];

    const all = Array.from(document.querySelectorAll("h1,h2,h3,div,span"));
    for(const el of all){
      const t = (el.textContent || "").trim();
      if(!t) continue;
      const hit = needles.some(k => t.toLowerCase().includes(k.toLowerCase()));
      if(!hit) continue;

      // climb up to a reasonable panel container
      let box = el;
      for(let k=0;k<8;k++){
        if(!box || !box.parentElement) break;
        const cls = box.className || "";
        if(typeof cls === "string" && (cls.includes("panel") || cls.includes("card") || cls.includes("box") || cls.includes("container"))){
          break;
        }
        box = box.parentElement;
      }
      if(box && box.style){
        box.style.display = "none";
      }
    }

    // Also hide any large PRE blocks near top area (defensive)
    const pres = Array.from(document.querySelectorAll("pre"));
    for(const pre of pres){
      const txt = (pre.textContent || "");
      if(txt.includes('"updated_by"') || txt.includes('"overrides"') || txt.includes('"evidence"')){
        // heuristic: only hide if it is not inside the editor area
        const par = pre.closest(".rule-editor,.editor,.override-editor");
        if(!par){
          pre.style.display = "none";
          const wrap = pre.parentElement;
          if(wrap && wrap.style) wrap.style.display = "none";
        }
      }
    }
  }catch(_){}
})();
"""
    if "VSP_P126_FIX_BOOL_TOKENS_V1" not in fixed:
        fixed = fixed.rstrip() + "\n" + addon + "\n"

    path.write_text(fixed, encoding="utf-8")
    print(f"[OK] replaced tokens: and={rep_and} or={rep_or}")
PY

# sanity: show around error area
echo "== [INFO] head/tail around line 330-370 =="
nl -ba "$F" | sed -n '330,370p' || true

if command -v node >/dev/null 2>&1; then
  echo "== [CHECK] node --check =="
  node --check "$F" && echo "[OK] JS syntax OK"
else
  echo "[WARN] node not found; skip node --check"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/runs"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
