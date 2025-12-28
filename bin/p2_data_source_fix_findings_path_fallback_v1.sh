#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_data_source_lazy_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_ds_pathfix_${TS}"
echo "[BACKUP] ${JS}.bak_ds_pathfix_${TS}"

python3 - "$JS" <<'PY'
import sys,re
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_DS_FINDINGS_PATH_FALLBACK_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Replace the single hardcoded findings_unified.json with a small candidate list
# We only patch inside the appended V2 block to avoid touching older code.
pat=r'loadFindings\(rid,\s*([^)]+)\)\s*\{\s*const u=new URL\("/api/vsp/run_file_allow", location\.origin\);\s*u\.searchParams\.set\("rid", rid\);\s*u\.searchParams\.set\("path","findings_unified\.json"\);'
m=re.search(pat, s)
if not m:
    print("[ERR] cannot locate loadFindings() block for v2")
    raise SystemExit(2)

rep = (
'loadFindings(rid, limit){\n'
'    const candidates=["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"];\n'
'    return (async ()=>{\n'
'      for(const path of candidates){\n'
'        const u=new URL("/api/vsp/run_file_allow", location.origin);\n'
'        u.searchParams.set("rid", rid);\n'
'        u.searchParams.set("path", path);\n'
'        u.searchParams.set("limit", String(limit||300));\n'
'        const j=await jget(u.toString());\n'
'        const arr=(j && (j.findings||j.items||j.data))||[];\n'
'        if(Array.isArray(arr) && arr.length){ j.__chosen_path=path; return j; }\n'
'      }\n'
'      // last try: return first response even if empty (keeps keys like error/from)\n'
'      const u=new URL("/api/vsp/run_file_allow", location.origin);\n'
'      u.searchParams.set("rid", rid);\n'
'      u.searchParams.set("path", candidates[0]);\n'
'      u.searchParams.set("limit", String(limit||300));\n'
'      const j=await jget(u.toString());\n'
'      j.__chosen_path=candidates[0];\n'
'      return j;\n'
'    })();\n'
'  } /* '+marker+' */\n'
'  async function loadFindings__dead(){'
)

s2=re.sub(pat, rep, s, count=1)
# Disable old signature if any accidental leftover
s2=s2.replace("async function loadFindings__dead(){", "async function loadFindings__dead(){ return null; } /* dead */\n  async function loadFindings__dead2(){")
p.write_text(s2, encoding="utf-8")
print("[OK] patched findings path fallback v1")
PY

node -c "$JS"
echo "[OK] node -c OK"
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

grep -n "VSP_P2_DS_FINDINGS_PATH_FALLBACK_V1" "$JS" | head -n 3 || true
