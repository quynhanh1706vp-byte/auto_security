#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need head

echo "== [1] Gate all occurrences of vsp_dashboard_luxe_v1.js to /vsp5 only (templates + vsp_demo_app.py) =="

python3 - <<'PY'
from pathlib import Path
import time

ts=time.strftime("%Y%m%d_%H%M%S")

targets=[]
tpl_root=Path("templates")
if tpl_root.exists():
    targets += [p for p in tpl_root.rglob("*.html")]

app_py=Path("vsp_demo_app.py")
if app_py.exists():
    targets.append(app_py)

def gate_blocks(text:str)->tuple[str,int]:
    lines=text.splitlines(True)
    out=[]
    i=0
    changes=0

    def has_gate_near(idx:int)->bool:
        # look around for a gate already
        lo=max(0, idx-5)
        hi=min(len(lines), idx+6)
        chunk="".join(lines[lo:hi])
        return ('{% if request.path == "/vsp5" %}' in chunk) and ('{% endif %}' in chunk)

    while i < len(lines):
        if "vsp_dashboard_luxe_v1.js" not in lines[i]:
            out.append(lines[i]); i += 1; continue

        # find script block boundaries (start at nearest <script, end at </script>)
        start=i
        while start>0 and "<script" not in lines[start]:
            start -= 1
        end=i
        while end < len(lines) and "</script>" not in lines[end]:
            end += 1
        if end < len(lines):
            end += 1  # include closing line

        block="".join(lines[start:end])

        # If already gated nearby, keep as-is
        if has_gate_near(start):
            out.append(lines[i]); i += 1
            continue

        # Wrap the whole script block
        out.append('{% if request.path == "/vsp5" %}\n')
        out.append(block)
        out.append('{% endif %}\n')
        changes += 1

        i = end  # skip consumed block

    return "".join(out), changes

patched=0
for p in targets:
    s=p.read_text(encoding="utf-8", errors="replace")
    if "vsp_dashboard_luxe_v1.js" not in s:
        continue
    s2, ch = gate_blocks(s)
    if ch>0 and s2!=s:
        bak=p.with_name(p.name+f".bak_gate_luxe_all_{ts}")
        bak.write_text(s, encoding="utf-8")
        p.write_text(s2, encoding="utf-8")
        print("[OK] patched", p, "changes=", ch, "backup=", bak.name)
        patched += 1
    else:
        print("[SKIP] already gated or no safe block match:", p)

print("[DONE] files_patched=", patched)
PY

echo
echo "== [2] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo
echo "== [3] Verify: /data_source must NOT contain luxe script tag =="
if curl -fsS --max-time 3 "$BASE/data_source" | grep -n "vsp_dashboard_luxe_v1.js" | head -n 3; then
  echo "[ERR] still found luxe in /data_source HTML"
  exit 4
else
  echo "[OK] no luxe in /data_source HTML"
fi

echo
echo "== [4] Quick JS list per tab (sanity) =="
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "== $p =="
  curl -fsS --max-time 3 --range 0-200000 "$BASE$p" \
    | grep -oE '/static/js/[^"]+\.js\?v=[0-9_]+' \
    | head -n 40
done

echo
echo "[DONE] Ctrl+Shift+R in browser."
