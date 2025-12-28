#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== RIDSTATE TEMPLATE HARDFIX V9B =="
echo "[TS] $TS"

python3 - <<PY
import re, glob
from pathlib import Path

TS="${TS}"
rid_tag = f'<script src="/static/js/vsp_rid_state_v1.js?v={TS}"></script>'

# Only patch real templates (exclude .bak_*)
cands = []
for p in glob.glob("templates/*.html"):
    if ".bak_" in p: 
        continue
    cands.append(p)

# prioritize ones containing vsp4 / rid markers
def score(p: str) -> int:
    s = Path(p).read_text(encoding="utf-8", errors="replace")
    sc = 0
    if "vsp_4tabs_commercial_v1" in p: sc += 100
    if "vsp_dashboard_2025" in p: sc += 90
    if "VSP_RID_STATE" in s: sc += 50
    if "vsp_tabs_hash_router_v1.js" in s: sc += 10
    if "/vsp4" in s: sc += 10
    return sc

cands = sorted(cands, key=score, reverse=True)
if not cands:
    raise SystemExit("[ERR] no templates/*.html found")

changed=[]
for t in cands:
    fp=Path(t)
    s=fp.read_text(encoding="utf-8", errors="replace")
    orig=s

    # 1) remove any bad Pxxxx script tag
    s = re.sub(r'^\s*<script\s+src=["\']P\d{6}_\d{6}["\']\s*>\s*</script>\s*$\n?', '', s, flags=re.M)

    # 2) normalize any rid_state include to cache-busted TS
    s = re.sub(r'<script\s+src=["\']/static/js/vsp_rid_state_v1\.js(?:\?v=[^"\']*)?["\']\s*>\s*</script>',
               rid_tag, s)

    # 3) ensure exactly one rid_state tag
    tags = re.findall(r'<script\s+src=["\']/static/js/vsp_rid_state_v1\.js\?v=[^"\']*["\']\s*>\s*</script>', s)
    if len(tags) == 0:
        if "<!-- VSP_RID_STATE_V1" in s:
            s = re.sub(r'(<!--\s*VSP_RID_STATE_V1\s*-->[^\n]*\n)', r'\\1'+rid_tag+'\\n', s, count=1)
        elif "vsp_tabs_hash_router_v1.js" in s:
            s = re.sub(r'(\s*<script\s+src=["\']/static/js/vsp_tabs_hash_router_v1\.js[^>]*>\s*</script>\s*)',
                       rid_tag+'\\n\\1', s, count=1)
        else:
            s = re.sub(r'(</body>)', rid_tag+'\\n\\1', s, count=1)
    elif len(tags) > 1:
        # keep first, remove the rest
        first = tags[0]: tags[0]
        # remove all then re-insert once
        s = re.sub(r'<script\s+src=["\']/static/js/vsp_rid_state_v1\.js\?v=[^"\']*["\']\s*>\s*</script>\s*', '', s)
        if "<!-- VSP_RID_STATE_V1" in s:
            s = re.sub(r'(<!--\s*VSP_RID_STATE_V1\s*-->[^\n]*\n)', r'\\1'+rid_tag+'\\n', s, count=1)
        elif "vsp_tabs_hash_router_v1.js" in s:
            s = re.sub(r'(\s*<script\s+src=["\']/static/js/vsp_tabs_hash_router_v1\.js[^>]*>\s*</script>\s*)',
                       rid_tag+'\\n\\1', s, count=1)
        else:
            s = s.replace("</body>", rid_tag+"\\n</body>")

    if s != orig:
        bak = fp.with_suffix(fp.suffix + f".bak_ridfix_{TS}")
        bak.write_text(orig, encoding="utf-8")
        fp.write_text(s_toggle:=s, encoding="utf-8")
        changed.append((t,str(bak)))

print("[OK] changed_n=", len(changed))
for t,b in changed:
    print(" -", t, "backup->", b)
PY

echo "[DONE] Now restart 8910 + hard refresh Ctrl+Shift+R"
