#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 && SYS_OK=1 || SYS_OK=0

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_VSP5_DASHONLY_FORCE_ASSETV_FSTRING_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_vsp5_assetv_${TS}"
echo "[BACKUP] ${W}.bak_vsp5_assetv_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_VSP5_DASHONLY_FORCE_ASSETV_FSTRING_V1"

if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

# locate function
m = re.search(r'(^\s*def\s+_vsp5_dash_only_html\s*\(\s*\)\s*:\s*$)', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def _vsp5_dash_only_html()")

start = m.start(1)
# take a safe window to patch within function body
win_start = start
win_end = min(len(s), start + 2000)
win = s[win_start:win_end]

# 1) ensure marker comment right after def line
if mark not in win:
    win = re.sub(r'(^\s*def\s+_vsp5_dash_only_html\s*\(\s*\)\s*:\s*$)',
                 r'\1\n    # ' + mark, win, count=1, flags=re.M)

# 2) ensure time import + asset_v assignment
# Insert after marker line (or after def) if not present in the next lines
if "asset_v = int(time.time())" not in win:
    # if there's already "import time" inside function, keep; else insert.
    ins = "    import time\n    asset_v = int(time.time())  # numeric cache-buster for /vsp5\n"
    # insert after marker comment line if present
    if re.search(r'^\s*#\s*' + re.escape(mark) + r'\s*$', win, flags=re.M):
        win = re.sub(r'^(\s*#\s*' + re.escape(mark) + r'\s*)$',
                     r'\1\n' + ins.rstrip(), win, count=1, flags=re.M)
    else:
        win = re.sub(r'(^\s*def\s+_vsp5_dash_only_html\s*\(\s*\)\s*:\s*$)',
                     r'\1\n' + ins.rstrip(), win, count=1, flags=re.M)

# 3) ensure the big HTML literal is an f-string so {asset_v} becomes digits
# Convert first occurrence of triple-quoted string assigned to html = """... or return """...
# Only if not already f""" / f'''
def make_f_triple(win: str) -> str:
    # html = """  -> html = f"""
    win2, n1 = re.subn(r'(\bhtml\s*=\s*)"""', r'\1f"""', win, count=1)
    if n1: return win2
    win2, n2 = re.subn(r"(\bhtml\s*=\s*)'''", r"\1f'''", win, count=1)
    if n2: return win2
    # return """ -> return f"""
    win2, n3 = re.subn(r'(\breturn\s*)"""', r'\1f"""', win, count=1)
    if n3: return win2
    win2, n4 = re.subn(r"(\breturn\s*)'''", r"\1f'''", win, count=1)
    if n4: return win2
    return win

win2 = make_f_triple(win)

# Write back patched window
s2 = s[:win_start] + win2 + s[win_end:]
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile ok:", mark)
PY

if [ "$SYS_OK" = "1" ]; then
  systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
fi

echo "[DONE] /vsp5 dash-only now renders asset_v digits via f-string."
