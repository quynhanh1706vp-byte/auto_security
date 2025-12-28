#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need curl; need grep

[ -f "$F" ] || { echo "[ERR] missing $F (check filename from console)"; exit 2; }
cp -f "$F" "${F}.bak_ridfix_${TS}"
echo "[BACKUP] ${F}.bak_ridfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_CSUITE_RID_GUARD_V1"
if MARK not in s:
    # Inject a robust RID resolver very early (freeze-safe)
    inj = r"""/* %s (commercial-safe) */
window.__vspGetRid = window.__vspGetRid || (function(){
  let _cache = "";
  function _fromUrl(){
    try{ return (new URLSearchParams(location.search).get("rid")||"").trim(); }catch(e){ return ""; }
  }
  function _fromLS(){
    try{ return (localStorage.getItem("vsp_rid_last")||"").trim(); }catch(e){ return ""; }
  }
  function get(){
    const u=_fromUrl();
    if(u){ _cache=u; try{ localStorage.setItem("vsp_rid_last", u);}catch(e){} return u; }
    if(_cache) return _cache;
    const ls=_fromLS();
    if(ls){ _cache=ls; return ls; }
    return "";
  }
  return get;
})();""" % MARK

    # Put injection near the top but after an IIFE header if any
    # Strategy: insert after first occurrence of "(function" header, else prepend.
    m=re.search(r'\(function\s*\(\)\s*\{', s)
    if m:
        ins_at = m.end()
        s = s[:ins_at] + "\n" + inj + "\n" + s[ins_at:]
    else:
        s = inj + "\n" + s

# 1) Replace rule_overrides_v1 calls to stable endpoint
s2 = s.replace("/api/vsp/rule_overrides_v1", "/api/vsp/rule_overrides")

# 2) Force any obvious rid derivation to use __vspGetRid() fallback
# Common patterns we’ve seen: qs.get('rid'), rid = ..., etc.
# We only patch “const/let rid = ...;” lines (light-touch).
def repl_rid_line(m):
    decl=m.group(1)
    return f"""{decl} = (window.__vspGetRid ? window.__vspGetRid() : ((new URLSearchParams(location.search).get("rid")||"").trim()));"""

s3 = re.sub(r'(?m)^\s*(const|let)\s+rid\s*=\s*[^;]*;', lambda m: repl_rid_line(m), s2, count=3)

# 3) Guard run_file/export_csv URL builders: if they concatenate rid directly, prefer __vspGetRid()
s3 = s3.replace('encodeURIComponent(rid)', 'encodeURIComponent((window.__vspGetRid?window.__vspGetRid():rid)||"")')

p.write_text(s3, encoding="utf-8")
print("[OK] patched:", p)
PY

echo "[PROBE] rule_overrides (stable) ..."
curl -fsS "$BASE/api/vsp/rule_overrides" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"keys=",list(j.keys())[:8])' || true

echo "[DONE] Ctrl+F5 on /c/* pages; check console must be clean."
