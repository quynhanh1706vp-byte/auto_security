#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p125_${TS}"
echo "[OK] backup: ${F}.bak_p125_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

def replace_or_operator_outside_strings_and_comments(src: str) -> str:
    out = []
    i = 0
    n = len(src)

    in_sq = in_dq = in_bt = False
    in_line = in_block = False

    def is_ws(c): return c in " \t\r\n"
    def is_ident_char(c): return c.isalnum() or c in "_$"

    while i < n:
        c = src[i]
        nxt = src[i+1] if i+1 < n else ""

        # end line comment
        if in_line:
            out.append(c)
            if c == "\n":
                in_line = False
            i += 1
            continue

        # end block comment
        if in_block:
            out.append(c)
            if c == "*" and nxt == "/":
                out.append(nxt)
                in_block = False
                i += 2
            else:
                i += 1
            continue

        # handle strings
        if in_sq:
            out.append(c)
            if c == "\\" and i+1 < n:
                out.append(src[i+1]); i += 2; continue
            if c == "'":
                in_sq = False
            i += 1
            continue

        if in_dq:
            out.append(c)
            if c == "\\" and i+1 < n:
                out.append(src[i+1]); i += 2; continue
            if c == '"':
                in_dq = False
            i += 1
            continue

        if in_bt:
            out.append(c)
            if c == "\\" and i+1 < n:
                out.append(src[i+1]); i += 2; continue
            if c == "`":
                in_bt = False
            i += 1
            continue

        # start comments
        if c == "/" and nxt == "/":
            out.append(c); out.append(nxt)
            in_line = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            out.append(c); out.append(nxt)
            in_block = True
            i += 2
            continue

        # start strings
        if c == "'":
            in_sq = True; out.append(c); i += 1; continue
        if c == '"':
            in_dq = True; out.append(c); i += 1; continue
        if c == "`":
            in_bt = True; out.append(c); i += 1; continue

        # replace bare token: <ws>or<ws> (outside strings/comments)
        if c == "o" and src[i:i+2] == "or":
            prev = src[i-1] if i-1 >= 0 else ""
            after = src[i+2] if i+2 < n else ""

            # ensure token boundary: not part of "border"/"color"/etc
            if (not is_ident_char(prev)) and (not is_ident_char(after)):
                # require whitespace around (common wrong "a or b")
                # allow: ") or (" or "or (" or ") or"
                # We'll convert to JS logical OR operator.
                # Keep spacing reasonable: " || "
                # If there isn't whitespace, still convert safely.
                # But avoid "for" (won't match due boundary) etc.
                out.append("||")
                i += 2
                continue

        out.append(c)
        i += 1

    return "".join(out)

s2 = replace_or_operator_outside_strings_and_comments(s)

# If the file had many accidental "or", normalize common spaced patterns too (outside strings/comments already handled).
# Ensure we don't create "||||" etc
s2 = re.sub(r"\|\|\s*\|\|", "||", s2)

# Append cleanup hook (idempotent)
MARK = "/* VSP_P125_C_SUITE_CLEANUP_V1 */"
if MARK not in s2:
    s2 += "\n\n" + MARK + r"""
(function(){
  try{
    if(!location.pathname.startsWith('/c/')) return;

    function hidePanelByNeedles(needles){
      const els = Array.from(document.querySelectorAll('div,section,article'));
      for(const el of els){
        const t = (el.innerText || '').trim();
        if(!t) continue;
        const hit = needles.every(nd => t.includes(nd));
        if(hit){
          // if it contains the big JSON block, hide the whole container
          if(el.querySelector('pre, textarea')){
            el.style.display = 'none';
            return true;
          }
        }
      }
      return false;
    }

    function p125(){
      const path = location.pathname;

      // Remove the "live JSON" top panels (rác) but keep the editor panels below.
      if(path === '/c/settings' || path.startsWith('/c/settings')){
        hidePanelByNeedles(['Settings (live links', 'tool legend']);
        // fallback: hide panel that shows lots of JSON and has "Tools (8)" + "Exports:"
        hidePanelByNeedles(['Tools (8)', 'Exports:']);
      }

      if(path === '/c/rule_overrides' || path.startsWith('/c/rule_overrides')){
        hidePanelByNeedles(['Rule Overrides (live from', '/api/vsp/rule_overrides']);
        // fallback: hide panel with "Open JSON"
        hidePanelByNeedles(['Open JSON']);
      }
    }

    if(document.readyState === 'loading'){
      document.addEventListener('DOMContentLoaded', p125);
    } else {
      p125();
    }
  }catch(e){
    console.warn('[VSP][P125] cleanup failed', e);
  }
})();
"""
    # minimal contrast polish for links in runs (safe CSS, no DOM dependency)
    s2 += r"""
/* VSP_P125_C_SUITE_CONTRAST_V1 */
(function(){
  try{
    if(!location.pathname.startsWith('/c/')) return;
    const css = `
      .vsp-card a, a.vsp-link, .vsp-table a { text-decoration: none; }
      .vsp-card a:hover, a.vsp-link:hover, .vsp-table a:hover { text-decoration: underline; }
    `;
    const st = document.createElement('style');
    st.setAttribute('data-vsp', 'p125');
    st.textContent = css;
    document.head.appendChild(st);
  }catch(_){}
})();
"""
p.write_text(s2, encoding="utf-8")
print("[OK] patched:", p)
print("[OK] P125: fixed bare token 'or' + hide live JSON panels in settings/rule_overrides")
PY

echo "[OK] P125 applied."

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/runs"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
