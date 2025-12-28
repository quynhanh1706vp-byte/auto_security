#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_afterreq_kics_tail_${TS}"
echo "[BACKUP] $F.bak_afterreq_kics_tail_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_AFTER_REQUEST_KICS_TAIL_V1 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# find app = Flask(...)
m = re.search(r"(?m)^(?P<ind>[ \t]*)app\s*=\s*Flask\s*\(", t)
if not m:
    raise SystemExit("[ERR] cannot find `app = Flask(`")

# insert right after that line (end of line containing app = Flask(...))
line_start = t.rfind("\n", 0, m.start()) + 1
line_end = t.find("\n", m.start())
if line_end < 0:
    line_end = len(t)

insert_at = line_end + 1
ind = m.group("ind")

snip = f"""{ind}{TAG}
{ind}@app.after_request
{ind}def _vsp_after_request_kics_tail_v1(resp):
{ind}    \"\"\"Ensure run_status_v1 JSON always carries kics_tail when kics.log exists.\"\"\"
{ind}    try:
{ind}        import json, os
{ind}        from pathlib import Path
{ind}        from flask import request
{ind}        path = getattr(request, 'path', '') or ''
{ind}        if not path.startswith('/api/vsp/run_status_v1/'):
{ind}            return resp
{ind}        ct = (resp.headers.get('Content-Type') or '').lower()
{ind}        if 'application/json' not in ct:
{ind}            return resp
{ind}        data = resp.get_data(as_text=True) or ''
{ind}        data_s = data.strip()
{ind}        if not data_s.startswith('{{'):
{ind}            return resp
{ind}        obj = json.loads(data_s)
{ind}        if not isinstance(obj, dict):
{ind}            return resp
{ind}        # keep existing if already set
{ind}        if obj.get('kics_tail'):
{ind}            return resp
{ind}        # derive ci_run_dir (fallback to statefiles)
{ind}        req_id = path.rsplit('/', 1)[-1]
{ind}        ci = str(obj.get('ci_run_dir') or '')
{ind}        if not ci:
{ind}            try:
{ind}                root = Path(__file__).resolve().parent
{ind}                cands = [
{ind}                    root / 'out_ci' / 'uireq_v1' / (req_id + '.json'),
{ind}                    root / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),
{ind}                    root / 'ui' / 'ui' / 'out_ci' / 'uireq_v1' / (req_id + '.json'),
{ind}                ]
{ind}                for st in cands:
{ind}                    if st.exists():
{ind}                        txt = st.read_text(encoding='utf-8', errors='ignore') or ''
{ind}                        j = json.loads(txt) if txt.strip() else {{}}
{ind}                        ci = str(j.get('ci_run_dir') or '')
{ind}                        if ci:
{ind}                            break
{ind}            except Exception:
{ind}                pass
{ind}        if not ci:
{ind}            return resp
{ind}        klog = os.path.join(ci, 'kics', 'kics.log')
{ind}        if not os.path.exists(klog):
{ind}            return resp
{ind}        NL = chr(10)
{ind}        rawb = Path(klog).read_bytes()
{ind}        if len(rawb) > 65536:
{ind}            rawb = rawb[-65536:]
{ind}        raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)
{ind}        hb = ''
{ind}        for ln in reversed(raw.splitlines()):
{ind}            if '][HB]' in ln and '[KICS_V' in ln:
{ind}                hb = ln.strip()
{ind}                break
{ind}        lines2 = [x for x in raw.splitlines() if x.strip()]
{ind}        tail = NL.join(lines2[-60:])
{ind}        if hb and hb not in tail:
{ind}            tail = hb + NL + tail
{ind}        obj['kics_tail'] = tail[-4096:]
{ind}        # write back response
{ind}        resp.set_data(json.dumps(obj, ensure_ascii=False))
{ind}        resp.headers['Content-Length'] = str(len(resp.get_data()))
{ind}        return resp
{ind}    except Exception:
{ind}        return resp
{ind}# === END VSP_AFTER_REQUEST_KICS_TAIL_V1 ===

"""

t2 = t[:insert_at] + snip + t[insert_at:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted after_request hook")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart 8910 =="
PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
echo "[OK] done"
