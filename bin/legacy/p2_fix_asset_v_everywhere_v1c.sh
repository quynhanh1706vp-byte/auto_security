#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
APP="vsp_demo_app.py"
TEMPL_DIR="templates"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need find; need head; need sort; need uniq; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "== [P2] fix asset_v everywhere v1c ts=$TS =="

backup(){
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "${f}.bak_assetv_all_${TS}"
  echo "[BACKUP] ${f}.bak_assetv_all_${TS}"
}

backup "$W"
backup "$APP"

# -------- 1) Patch templates: normalize any static js/css v=xxx into v={{ asset_v }} --------
if [ -d "$TEMPL_DIR" ]; then
  echo "== [1] patch templates/ (*.html) =="
  python3 - <<'PY'
from pathlib import Path
import re, time

root=Path("templates")
changed=[]

# a) normalize any jinja v={{ ... }} that isn't asset_v
pat_jinja = re.compile(r'\?v=\{\{\s*([^}]+?)\s*\}\}')
# b) normalize any literal v=digits/_ (hardcode) on static assets
pat_lit = re.compile(r'(/static/[^"\']+\.(?:js|css))\?v=([0-9_]+)')

for fp in sorted(root.rglob("*.html")):
    s=fp.read_text(encoding="utf-8", errors="replace")
    orig=s

    def repl_j(m):
        expr=m.group(1).strip()
        return m.group(0) if expr=="asset_v" else "?v={{ asset_v }}"

    s = pat_jinja.sub(repl_j, s)
    s = pat_lit.sub(r"\1?v={{ asset_v }}", s)

    if s != orig:
        bak = fp.with_suffix(fp.suffix + f".bak_assetv_{int(time.time())}")
        bak.write_text(orig, encoding="utf-8")
        fp.write_text(s, encoding="utf-8")
        changed.append(str(fp))

print("[OK] templates changed:", len(changed))
for f in changed[:200]:
    print(" -", f)
PY
else
  echo "[WARN] templates/ not found; skip"
fi

# -------- 2) Ensure both python modules have stable _VSP_ASSET_V, and replace ?v=...time.time() usages --------
echo "== [2] patch python files for ?v= + time.time() builders =="

python3 - <<'PY'
from pathlib import Path
import re, time, sys

files=["wsgi_vsp_ui_gateway.py","vsp_demo_app.py"]
marker="VSP_P2_ASSET_V_EVERYWHERE_V1C"

def ensure_block(s):
    if marker in s:
        return s, 0
    block = f'''
# --- {marker} ---
import os as _os, time as _time
_VSP_ASSET_V = _os.environ.get("VSP_ASSET_V") or _os.environ.get("VSP_RELEASE_TS")
if not _VSP_ASSET_V:
    _VSP_ASSET_V = str(int(_time.time()))
# --- end {marker} ---
'''.lstrip("\n")
    # insert after first import block if possible
    m=re.search(r'(?m)^(import|from)\s+[^\n]+\n', s)
    if m:
        idx=m.end()
        return s[:idx] + block + "\n" + s[idx:], 1
    return block + "\n" + s, 1

def patch_time_v_lines(s):
    # Only touch lines that contain '?v=' and time.time()
    out=[]
    changed=0
    for line in s.splitlines(True):
        l=line
        if "?v=" in l and "time.time" in l:
            # replace common patterns int(time.time()) or str(int(time.time()))
            l2=re.sub(r'str\s*\(\s*int\s*\(\s*time\.time\s*\(\s*\)\s*\)\s*\)', "_VSP_ASSET_V", l)
            l2=re.sub(r'int\s*\(\s*time\.time\s*\(\s*\)\s*\)', "_VSP_ASSET_V", l2)
            if l2 != l:
                l=l2
                changed += 1
        out.append(l)
    return "".join(out), changed

for fn in files:
    p=Path(fn)
    if not p.exists():
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    s1, ins = ensure_block(s)
    s2, ch = patch_time_v_lines(s1)
    if ins or ch:
        p.write_text(s2, encoding="utf-8")
        print(f"[OK] patched {fn}: inserted_block={ins} changed_lines={ch}")
    else:
        print(f"[OK] no change needed {fn}")
PY

python3 -m py_compile "$W"
python3 -m py_compile "$APP"
echo "[OK] py_compile OK: $W + $APP"

# -------- 3) Restart service --------
echo "== [3] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }
else
  echo "[WARN] systemctl not found; restart manually"
fi

# -------- 4) Verify: all tabs should share ONE v value --------
echo "== [4] verify v= across tabs =="
tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
for pth in "${tabs[@]}"; do
  echo "-- $pth --"
  curl -sS "$BASE$pth" | grep -oE '(/static/[^"]+\.(js|css)\?v=[^"&]+)' | head -n 30 || true
done

echo "== unique v values (should be 1) =="
( for pth in "${tabs[@]}"; do curl -sS "$BASE$pth" | grep -oE 'v=[0-9_]+' || true; done ) \
  | sed 's/^v=//' | sort -u | sed 's/^/[V] /'

echo "[OK] done"
