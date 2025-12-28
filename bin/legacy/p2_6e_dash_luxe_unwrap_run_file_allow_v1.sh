#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v node >/dev/null 2>&1 || { echo "[WARN] node not found -> skip node --check"; }

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p2_6e_${TS}"
echo "[BACKUP] ${JS}.bak_p2_6e_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys, time

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P2_6E_LUXE_JGET_UNWRAP_RUN_FILE_ALLOW_V1"
if MARK in s:
    print("[OK] already patched (marker found)")
    raise SystemExit(0)

# Try to patch inside jget() by replacing `return await r.json();` OR `return await res.json();`
# with a safer parse + unwrap for findings_unified.json
inject = r"""
/* VSP_P2_6E_LUXE_JGET_UNWRAP_RUN_FILE_ALLOW_V1 */
      let j = null;
      try{ j = await r.json(); }catch(e){ j = null; }
      try{
        const u = String(url || "");
        if(u.includes("/api/vsp/run_file_allow") && u.includes("path=findings_unified.json")){
          // ok:true wrapper -> unwrap to {meta,findings}
          if(j && j.ok === true && Array.isArray(j.findings)){
            return { meta: (j.meta || {}), findings: (j.findings || []) };
          }
          // blocked/error -> return empty findings but keep err for banner/debug
          if(j && j.ok === false){
            return { meta: (j.meta || { rid: j.rid || null }), findings: [], _err: (j.err || "blocked"), _raw: j };
          }
        }
      }catch(e){}
      return j;
"""

# We need to find a jget function that has `const r = await fetch(url...` then `return await r.json()`
# We'll replace FIRST occurrence of "return await r.json();" inside that function.
pat1 = re.compile(r"return\s+await\s+r\.json\(\s*\)\s*;\s*", re.M)
pat2 = re.compile(r"return\s+await\s+res\.json\(\s*\)\s*;\s*", re.M)

# But injection uses `r` variable; if function uses `res`, we'll rewrite injection accordingly.
def apply_for_var(varname: str, text: str) -> str:
    inj = inject.replace("await r.json()", f"await {varname}.json()")
    return inj

# locate jget block region to reduce chance of replacing random return
jget_idx = s.find("function jget")
if jget_idx < 0:
    jget_idx = s.find("async function jget")
if jget_idx < 0:
    jget_idx = s.find("const jget")
if jget_idx < 0:
    print("[ERR] cannot locate jget() in luxe file", file=sys.stderr)
    sys.exit(2)

# attempt replace near jget body first
sub = s[jget_idx:jget_idx+20000]  # slice around jget
if pat1.search(sub):
    sub2 = pat1.sub(apply_for_var("r", sub), count=1)
    s2 = s[:jget_idx] + sub2 + s[jget_idx+20000:]
elif pat2.search(sub):
    sub2 = pat2.sub(apply_for_var("res", sub), count=1)
    s2 = s[:jget_idx] + sub2 + s[jget_idx+20000:]
else:
    # fallback: whole-file replace first return await r.json()
    if pat1.search(s):
        s2 = pat1.sub(apply_for_var("r", s), count=1)
    elif pat2.search(s):
        s2 = pat2.sub(apply_for_var("res", s), count=1)
    else:
        print("[ERR] cannot find 'return await r.json()' or 'return await res.json()' to patch", file=sys.stderr)
        sys.exit(2)

# Add marker at top
s2 = "/* " + MARK + " */\n" + s2

p.write_text(s2, encoding="utf-8")
print("[OK] patched jget() unwrap for run_file_allow findings_unified.json")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS"
  echo "[OK] node --check: $JS"
fi

echo
echo "[NEXT] Ctrl+Shift+R /vsp5"
echo "Expect: payload mismatch banner should disappear, findings counts should populate."
