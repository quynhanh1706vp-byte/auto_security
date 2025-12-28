#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p65_dom_alias_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need node; need grep; need sed; need head; need sort; need uniq

RID="$(curl -fsS "$BASE/api/vsp/top_findings_v2?limit=1" | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("rid") or j.get("run_id") or "")')"
echo "[INFO] RID=$RID" | tee "$EVID/summary.txt"
[ -n "$RID" ] || { echo "[ERR] RID empty"; exit 2; }

HTML="$EVID/vsp5.html"
curl -fsS "$BASE/vsp5?rid=$RID" -o "$HTML"
echo "[OK] fetched $HTML" | tee -a "$EVID/summary.txt"

# Extract existing ids in HTML
python3 - "$HTML" > "$EVID/html_ids.txt" <<'PY'
import re,sys
s=open(sys.argv[1],'r',encoding='utf-8',errors='replace').read()
ids=set(re.findall(r'\bid="([^"]+)"', s))
for x in sorted(ids): print(x)
PY
echo "[INFO] html_ids_count=$(wc -l < "$EVID/html_ids.txt")" | tee -a "$EVID/summary.txt"

# Extract loaded JS paths from HTML
grep -oE '/static/js/[^"]+\.js[^"]*' "$HTML" | sed 's/[?].*$//' | sort -u > "$EVID/loaded_js.txt"
echo "[INFO] loaded_js=$(wc -l < "$EVID/loaded_js.txt")" | tee -a "$EVID/summary.txt"
head -n 50 "$EVID/loaded_js.txt" > "$EVID/loaded_js.head.txt"

# Scan JS for ids used in getElementById / querySelector('#id')
python3 - "$EVID/loaded_js.txt" > "$EVID/js_ids.txt" <<'PY'
import re,sys,os
ids=set()
for line in open(sys.argv[1],'r',encoding='utf-8',errors='replace'):
    p=line.strip()
    if not p: continue
    fp=p.lstrip('/')
    if not os.path.exists(fp): 
        continue
    s=open(fp,'r',encoding='utf-8',errors='replace').read()
    ids.update(re.findall(r'getElementById\(\s*[\'"]([^\'"]+)[\'"]\s*\)', s))
    ids.update(re.findall(r'querySelector\(\s*[\'"]#([^\'"]+)[\'"]\s*\)', s))
# keep only likely container ids
keep=[]
for x in sorted(ids):
    lx=x.lower()
    if any(k in lx for k in ["root","dash","vsp","app","main","kpi","tab","content","panel"]):
        keep.append(x)
for x in keep: print(x)
PY
echo "[INFO] js_ids_count=$(wc -l < "$EVID/js_ids.txt")" | tee -a "$EVID/summary.txt"

# Missing ids = js_ids - html_ids
python3 - "$EVID/html_ids.txt" "$EVID/js_ids.txt" > "$EVID/missing_ids.txt" <<'PY'
import sys
html=set([x.strip() for x in open(sys.argv[1]) if x.strip()])
js=set([x.strip() for x in open(sys.argv[2]) if x.strip()])
miss=sorted([x for x in js if x not in html])
for x in miss: print(x)
PY
echo "[INFO] missing_ids=$(wc -l < "$EVID/missing_ids.txt")" | tee -a "$EVID/summary.txt"
head -n 80 "$EVID/missing_ids.txt" | sed 's/^/ - /' | tee -a "$EVID/summary.txt"

B="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

# Patch bundle: create missing containers early
TS2="$(date +%Y%m%d_%H%M%S)"
cp -f "$B" "${B}.bak_p65_${TS2}"
python3 - "$EVID/missing_ids.txt" <<'PY'
from pathlib import Path
import re, json, sys, time

missing=[x.strip() for x in open(sys.argv[1],'r',encoding='utf-8',errors='replace') if x.strip()]
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="P65_DOM_ALIAS_CONTAINERS_V1"
if MARK in s:
    print("[OK] already patched", MARK)
    raise SystemExit(0)

# limit to avoid crazy spam
missing = missing[:40]

snippet = "/* %s */\n(function(){\ntry{\n" % MARK
snippet += "var host=document.getElementById('vsp5_root')||document.getElementById('vsp-dashboard-main')||document.body;\n"
snippet += "var ids=%s;\n" % json.dumps(missing)
snippet += "for(var i=0;i<ids.length;i++){\n"
snippet += "  var id=ids[i];\n"
snippet += "  if(!id) continue;\n"
snippet += "  if(document.getElementById(id)) continue;\n"
snippet += "  var d=document.createElement('div'); d.id=id;\n"
snippet += "  d.style.cssText='display:contents';\n"
snippet += "  host.appendChild(d);\n"
snippet += "}\n"
snippet += "}catch(_){}}\n)();\n"

m=re.search(r'^[ \t]*["\']use strict["\'];\s*$', s, re.M)
if m:
    insert_at=m.end()
    s=s[:insert_at]+"\n"+snippet+"\n"+s[insert_at:]
else:
    s=snippet+"\n"+s

p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

echo "== node --check bundle =="
node --check "$B"
echo "[OK] node --check OK"
echo "[DONE] P65 applied. Hard refresh browser (Ctrl+Shift+R) and open: $BASE/vsp5?rid=$RID"
echo "[EVID] $EVID"
