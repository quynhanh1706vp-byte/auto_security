#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v node >/dev/null 2>&1 || { echo "[WARN] node not found -> skip node --check"; }

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p2_6e_fix_${TS}"
echo "[BACKUP] ${JS}.bak_p2_6e_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P2_6E_LUXE_JGET_UNWRAP_RUN_FILE_ALLOW_V1"
if MARK in s:
    print("[OK] already patched (marker found)")
    raise SystemExit(0)

def make_block(varname: str) -> str:
    # keep indentation similar to a typical `return await r.json();`
    return f"""/* {MARK} */
      let j = null;
      try {{ j = await {varname}.json(); }} catch(e) {{ j = null; }}

      try {{
        // unwrap wrapper payload for run_file_allow findings_unified.json
        var u = (typeof url !== 'undefined') ? String(url || "") : "";
        if (u.indexOf("/api/vsp/run_file_allow") >= 0 && u.indexOf("path=findings_unified.json") >= 0) {{
          if (j && j.ok === true && Array.isArray(j.findings)) {{
            return {{ meta: (j.meta || {{}}), findings: (j.findings || []) }};
          }}
          if (j && j.ok === false) {{
            return {{ meta: (j.meta || {{ rid: (j.rid || null) }}), findings: [], _err: (j.err || "blocked"), _raw: j }};
          }}
        }}
      }} catch(e) {{}}

      return j;"""

replaced = False

token1 = "return await r.json();"
token2 = "return await res.json();"

if token1 in s:
    s = s.replace(token1, make_block("r"), 1)
    replaced = True
elif token2 in s:
    s = s.replace(token2, make_block("res"), 1)
    replaced = True

if not replaced:
    print("[ERR] cannot find token to replace: 'return await r.json();' or 'return await res.json();'", file=sys.stderr)
    raise SystemExit(2)

# add marker at top too (easy grep)
s = f"/* {MARK} */\\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] patched jget() unwrap (string replace)")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS"
  echo "[OK] node --check: $JS"
fi

echo
echo "[NEXT] Ctrl+Shift+R /vsp5"
echo "Expect: 'Findings payload mismatch' banner disappears + counts populate."
