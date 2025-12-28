#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
export TS

# target templates: ưu tiên file có marker VSP_RID_STATE, fallback list
mapfile -t TPLS < <(grep -RIl "VSP_RID_STATE" templates 2>/dev/null || true)
if [ "${#TPLS[@]}" -eq 0 ]; then
  TPLS=(templates/vsp_4tabs_commercial_v1.html templates/vsp_dashboard_2025.html)
fi

echo "== RIDSTATE TEMPLATE HARDFIX V9 =="
echo "[TS] $TS"
printf "[TPL] %s\n" "${TPLS[@]}"

python3 - <<'PY'
import os, re
from pathlib import Path

TS=os.environ["TS"]
rid_tag = f'<script src="/static/js/vsp_rid_state_v1.js?v={TS}"></script>'

def patch_one(fp: Path):
    s = fp.read_text(encoding="utf-8", errors="replace")
    orig = s

    # 1) remove any bad script like <script src="P251216_160318"></script> (or similar)
    s = re.sub(r'^\s*<script\s+src=["\']P\d{6}_\d{6}["\']\s*>\s*</script>\s*$\n?', '', s, flags=re.M)

    # 2) normalize existing rid_state include to new cache param
    s = re.sub(r'<script\s+src=["\']/static/js/vsp_rid_state_v1\.js(?:\?v=[^"\']*)?["\']\s*>\s*</script>',
               rid_tag, s)

    # 3) ensure there is exactly ONE rid_state include
    hits = list(re.finditer(r'<script\s+src=["\']/static/js/vsp_rid_state_v1\.js\?v=[^"\']*["\']\s*>\s*</script>', s))
    if len(hits) == 0:
        # insert after marker if exists; else before tabs router; else before </body>
        if "<!-- VSP_RID_STATE_V1" in s:
            s = re.sub(r'(<!--\s*VSP_RID_STATE_V1\s*-->[\s\S]*?\n)', r'\1'+rid_tag+'\n', s, count=1)
        elif "/static/js/vsp_tabs_hash_router_v1.js" in s:
            s = re.sub(r'(\s*<script\s+src=["\']/static/js/vsp_tabs_hash_router_v1\.js[^>]*>\s*</script>\s*)',
                       rid_tag+'\n\\1', s, count=1)
        else:
            s = re.sub(r'(</body>)', rid_tag+'\n\\1', s, count=1)
    else:
        # keep first, remove others
        first = hits[0].group(0)
        s = re.sub(r'<script\s+src=["\']/static/js/vsp_rid_state_v1\.js\?v=[^"\']*["\']\s*>\s*</script>',
                   '', s)
        # put back one copy near marker/router
        if "<!-- VSP_RID_STATE_V1" in s:
            s = re.sub(r'(<!--\s*VSP_RID_STATE_V1\s*-->[\s\S]*?\n)', r'\1'+first+'\n', s, count=1)
        elif "/static/js/vsp_tabs_hash_router_v1.js" in s:
            s = re.sub(r'(\s*<script\s+src=["\']/static/js/vsp_tabs_hash_router_v1\.js[^>]*>\s*</script>\s*)',
                       first+'\n\\1', s, count=1)
        else:
            s = s.replace("</body>", first+"\n</body>")

    if s != orig:
        fp.write_text(s, encoding="utf-8")
        return True
    return False

changed=0
for t in os.environ.get("TPLS","").splitlines():
    if not t.strip(): 
        continue
PY
# feed template list to python via env (simple)
TPLS_JOINED="$(printf "%s\n" "${TPLS[@]}")"
export TPLS="$TPLS_JOINED"
python3 - <<'PY'
import os
from pathlib import Path
import re

TS=os.environ["TS"]
rid_tag = f'<script src="/static/js/vsp_rid_state_v1.js?v={TS}"></script>'

def patch_one(fp: Path):
    s = fp.read_text(encoding="utf-8", errors="replace")
    orig = s
    s = re.sub(r'^\s*<script\s+src=["\']P\d{6}_\d{6}["\']\s*>\s*</script>\s*$\n?', '', s, flags=re.M)
    s = re.sub(r'<script\s+src=["\']/static/js/vsp_rid_state_v1\.js(?:\?v=[^"\']*)?["\']\s*>\s*</script>',
               rid_tag, s)
    # ensure single
    allm = list(re.finditer(r'<script\s+src=["\']/static/js/vsp_rid_state_v1\.js\?v=[^"\']*["\']\s*>\s*</script>', s))
    if len(allm) == 0:
        if "<!-- VSP_RID_STATE_V1" in s:
            s = re.sub(r'(<!--\s*VSP_RID_STATE_V1\s*-->[\s\S]*?\n)', r'\1'+rid_tag+'\n', s, count=1)
        elif "/static/js/vsp_tabs_hash_router_v1.js" in s:
            s = re.sub(r'(\s*<script\s+src=["\']/static/js/vsp_tabs_hash_router_v1\.js[^>]*>\s*</script>\s*)',
                       rid_tag+'\n\\1', s, count=1)
        else:
            s = re.sub(r'(</body>)', rid_tag+'\n\\1', s, count=1)
    elif len(allm) > 1:
        first = allm[0].group(0)
        s = re.sub(r'<script\s+src=["\']/static/js/vsp_rid_state_v1\.js\?v=[^"\']*["\']\s*>\s*</script>\s*\n?', '', s)
        if "<!-- VSP_RID_STATE_V1" in s:
            s = re.sub(r'(<!--\s*VSP_RID_STATE_V1\s*-->[\s\S]*?\n)', r'\1'+first+'\n', s, count=1)
        elif "/static/js/vsp_tabs_hash_router_v1.js" in s:
            s = re.sub(r'(\s*<script\s+src=["\']/static/js/vsp_tabs_hash_router_v1\.js[^>]*>\s*</script>\s*)',
                       first+'\n\\1', s, count=1)
        else:
            s = s.replace("</body>", first+"\n</body>")

    if s != orig:
        fp.write_text(s, encoding="utf-8")
        return True
    return False

changed=[]
for t in os.environ["TPLS"].splitlines():
    fp=Path(t.strip())
    if fp.exists() and patch_one(fp):
        changed.append(str(fp))

print("[OK] changed_n=", len(changed))
for c in changed: print(" -", c)
PY

echo "[DONE] Restart 8910 + hard refresh Ctrl+Shift+R"
