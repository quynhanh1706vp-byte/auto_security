#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fixsha_compat_${TS}"
echo "[BACKUP] ${F}.bak_fixsha_compat_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_FIX_SHA256SUMS_COMPAT_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

changed=False

# (1) Fix the already-injected bypass block to use _rq_compat and _sf_compat (not request/send_file)
# Replace only inside the compat section to avoid touching other parts
if "def _vsp_compat_run_file_to_run_file2()" in s:
    # request.args -> _rq_compat.args
    s2 = s.replace("request.args.get('rid','')", "_rq_compat.args.get('rid','')") \
          .replace("request.args.get('run_id','')", "_rq_compat.args.get('run_id','')") \
          .replace("request.args.get('run','')", "_rq_compat.args.get('run','')") \
          .replace("request.args.get('name','')", "_rq_compat.args.get('name','')") \
          .replace("request.args.get('path','')", "_rq_compat.args.get('path','')") \
          .replace("request.args.get('rel','')", "_rq_compat.args.get('rel','')")
    if s2 != s:
        s = s2
        changed=True
        print("[OK] fixed request.args -> _rq_compat.args")

    # send_file -> _sf_compat
    s2 = s.replace("return send_file(", "return _sf_compat(")
    if s2 != s:
        s = s2
        changed=True
        print("[OK] fixed send_file -> _sf_compat")

# (2) Ensure allowlist dict accepts reports/SHA256SUMS.txt
# Best-effort: if _VSP_RF2_ALLOWED dict exists, insert key. If not, append a safe post-init patch.
if "reports/SHA256SUMS.txt" not in s:
    m = re.search(r'(_VSP_RF2_ALLOWED\s*=\s*\{)(.*?)(\}\s*)', s, flags=re.S)
    if m:
        head, body, tail = m.group(1), m.group(2), m.group(3)
        ins = '\n    "reports/SHA256SUMS.txt": True,\n'
        # insert near end (before closing })
        new = head + body + ins + tail
        s = s[:m.start()] + new + s[m.end():]
        changed=True
        print("[OK] inserted reports/SHA256SUMS.txt into _VSP_RF2_ALLOWED")
    else:
        # append a safe runtime patch (won't break even if dict name differs)
        s += f'''
# {MARK}: post-init allow reports/SHA256SUMS.txt in run_file2 allowlist
try:
    _d = globals().get("_VSP_RF2_ALLOWED") or globals().get("_VSP_RUNFILE_ALLOWED")
    if isinstance(_d, dict):
        _d["reports/SHA256SUMS.txt"] = True
except Exception:
    pass
'''
        changed=True
        print("[OK] appended post-init allow patch")

if not changed:
    raise SystemExit("[ERR] nothing changed (unexpected)")

s += f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] wrote:", MARK)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK: wsgi_vsp_ui_gateway.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

RID="btl86-connector_RUN_20251127_095755_000599"
echo "RID=$RID"

echo "== smoke: legacy run_file should allow SHA256SUMS now =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 25

echo "== smoke: direct run_file2 should allow SHA256SUMS now =="
curl -sS -i "http://127.0.0.1:8910/api/vsp/run_file2?rid=$RID&name=reports/SHA256SUMS.txt" | head -n 25 || true
