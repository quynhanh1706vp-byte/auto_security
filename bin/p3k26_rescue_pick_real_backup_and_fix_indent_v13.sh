#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v ls >/dev/null 2>&1 || true
command -v head >/dev/null 2>&1 || true
command -v tail >/dev/null 2>&1 || true
command -v sed >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_p3k26_v13_before_${TS}"
echo "[BACKUP] ${APP}.bak_p3k26_v13_before_${TS}"

echo "== [1] pick REAL older backup (exclude recent patch backups) =="
python3 - <<'PY'
from pathlib import Path
import ast, glob, os, re, sys, time

APP = Path("vsp_demo_app.py")

# Exclude any backups created by recent rescue scripts to avoid selecting broken "before/preroute" files
exclude_re = re.compile(r'\.bak_p3k26_v(1[0-3]|9|8|12|11b|11)_|\.bak_p3k26_v12_|\.bak_p3k26_v11|\.bak_p3k26_v10|\.bak_p3k26_v9_|\.bak_p3k26_v8_|_before_|_preroute_', re.I)

cands = []
for p in glob.glob(str(APP) + ".bak_*"):
    if exclude_re.search(p):
        continue
    try:
        cands.append((os.path.getmtime(p), p))
    except Exception:
        pass

cands.sort(reverse=True)

def clean(path: str) -> bool:
    s = Path(path).read_text(encoding="utf-8", errors="replace")
    try:
        compile(s, path, "exec")
        ast.parse(s)
        return True
    except Exception:
        return False

good = None
for _, p in cands[:400]:
    if clean(p):
        good = p
        break

if not good:
    print("[ERR] no clean backup found among excluded set.")
    print("Hint: show top 30 candidates with status:")
    shown=0
    for _, p in cands[:80]:
        shown += 1
        ok = clean(p)
        print(("OK " if ok else "BAD"), os.path.basename(p))
        if shown>=30: break
    sys.exit(2)

# restore by copying (keep backups intact)
Path(good).write_text(Path(good).read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
APP.write_text(Path(good).read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[OK] restored from:", os.path.basename(good))
PY

echo "== [2] sanity py_compile =="
set +e
python3 -m py_compile "$APP"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "[FAIL] still syntax/indent error. Showing context around error line:"
  python3 - <<'PY'
import traceback, sys, py_compile, re
try:
    py_compile.compile("vsp_demo_app.py", doraise=True)
except Exception as e:
    msg=str(e)
    print("compile_error:", msg)
    m=re.search(r'line (\d+)', msg)
    ln=int(m.group(1)) if m else None
    if ln:
        s=open("vsp_demo_app.py","r",encoding="utf-8",errors="replace").read().splitlines()
        a=max(0, ln-25); b=min(len(s), ln+25)
        for i in range(a,b):
            pref=">>" if (i+1)==ln else "  "
            print(f"{pref}{i+1:6d}  {s[i]}")
PY
  exit 2
fi
echo "[OK] py_compile OK"

echo "== [3] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== [4] smoke /vsp5 (3s) =="
curl -sv --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html 2>&1 | sed -n '1,80p'
echo "== head /tmp/vsp5.html =="
head -n 20 /tmp/vsp5.html || true

echo "[DONE] p3k26_rescue_pick_real_backup_and_fix_indent_v13"
