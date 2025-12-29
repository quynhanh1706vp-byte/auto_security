#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [P910H] stop service =="
sudo systemctl stop "$SVC" || true
sudo systemctl reset-failed "$SVC" || true

echo "== [P910H] rollback vsp_demo_app.py to known-good (p910d) =="
BK="$(ls -1t vsp_demo_app.py.bak_p910d_* 2>/dev/null | head -n1 || true)"
[ -n "$BK" ] || { echo "[FAIL] missing vsp_demo_app.py.bak_p910d_*"; exit 2; }
cp -f "$BK" vsp_demo_app.py
python3 -m py_compile vsp_demo_app.py
echo "[OK] rollback OK => $BK"

echo "== [P910H] write WSGI wrapper (intercept /api/* safely) =="
python3 - <<'PY'
from pathlib import Path
import json, datetime, os

root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
p = root / "wsgi_vsp_p910h.py"

code = r'''# WSGI wrapper to avoid touching vsp_demo_app.py indentation
# P910H_WSGI_WRAPPER

import json, datetime
from pathlib import Path
from werkzeug.wrappers import Response

# import the real Flask app (unchanged)
from vsp_demo_app import app as _flask_app

def _pick_latest_release_dir():
    root = Path(__file__).resolve().parent
    relroot = root / "out_ci" / "releases"
    if not relroot.exists():
        return None
    dirs = sorted([d for d in relroot.glob("RELEASE_UI_*") if d.is_dir()],
                  key=lambda p: p.stat().st_mtime, reverse=True)
    return dirs[0] if dirs else None

def _read_text(p, limit=200000):
    try:
        return Path(p).read_text(encoding="utf-8", errors="replace")[:limit]
    except Exception:
        return ""

def _read_json(p):
    try:
        return json.loads(Path(p).read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return None

def _resp(obj, status=200):
    body = json.dumps(obj, ensure_ascii=False)
    return Response(body, status=status, mimetype="application/json; charset=utf-8")

class _Middleware:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO", "") or ""
        qs   = environ.get("QUERY_STRING", "") or ""

        # 1) stop 400 spam: /api/vsp/run_status_v1 without rid => 200 NO_RID
        if path == "/api/vsp/run_status_v1":
            if ("rid=" not in qs) or (qs.strip() == ""):
                return _resp({"ok": False, "rid": None, "state": "NO_RID"}, 200)(environ, start_response)

        # 2) ops_latest must ALWAYS be JSON and MUST NOT go through Flask after_request strip
        if path == "/api/vsp/ops_latest_v1":
            out = {
                "ok": False,
                "source": {"release_dir": "", "ops_dir": "", "ts": datetime.datetime.now().isoformat()},
                "stamp": None,
                "journal_tail": "",
                "errors": []
            }
            try:
                rel = _pick_latest_release_dir()
                if not rel:
                    out["errors"].append("no_release_dir")
                    return _resp(out, 200)(environ, start_response)

                ops = rel / "evidence" / "ops"
                out["source"]["release_dir"] = str(rel)
                out["source"]["ops_dir"] = str(ops)

                stamp_p = ops / "stamp" / "OPS_STAMP.json"
                proof_p = ops / "proof" / "PROOF.txt"
                health_dir = ops / "healthcheck"

                stamp = _read_json(stamp_p) if stamp_p.exists() else None
                out["stamp"] = stamp

                # journal tail: prefer embedded, else any file
                journal_txt = ""
                if isinstance(stamp, dict) and stamp.get("journal_tail"):
                    journal_txt = str(stamp.get("journal_tail"))
                else:
                    cand = []
                    for n in ["journal_tail.txt","JOURNAL_TAIL.txt","journal.txt"]:
                        fp = ops / "stamp" / n
                        if fp.exists():
                            cand.append(fp)
                    if cand:
                        cand.sort(key=lambda p: p.stat().st_mtime, reverse=True)
                        journal_txt = _read_text(cand[0], limit=20000)
                out["journal_tail"] = journal_txt

                if health_dir.exists():
                    files = [p for p in health_dir.rglob("*") if p.is_file()]
                    if files:
                        files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
                        best = files[0]
                        out["source"]["health_file"] = str(best)
                        if best.suffix.lower()==".json":
                            out["healthcheck"] = _read_json(best)
                        else:
                            out["healthcheck_text"] = _read_text(best, limit=20000)

                if proof_p.exists():
                    out["proof"] = _read_text(proof_p, limit=20000)

                ok = False
                if isinstance(stamp, dict):
                    http = stamp.get("http_code")
                    listen = stamp.get("listen")
                    ok = (str(http)=="200") and (str(listen) in ("1","true","True"))
                out["ok"] = bool(ok)

            except Exception as e:
                out["errors"].append("exception:" + str(e))

            return _resp(out, 200)(environ, start_response)

        # default: forward to Flask app
        return self.app(environ, start_response)

# gunicorn entrypoint
app = _Middleware(_flask_app.wsgi_app)
'''
p.write_text(code, encoding="utf-8")
print("[OK] wrote", p)
PY

python3 -m py_compile wsgi_vsp_p910h.py
echo "[OK] wsgi wrapper syntax OK"

echo "== [P910H] patch vsp_ui_start.sh to use wsgi_vsp_p910h:app =="
F="bin/vsp_ui_start.sh"
[ -f "$F" ] || { echo "[FAIL] missing $F"; exit 3; }

cp -f "$F" "${F}.bak_p910h_${TS}"
python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/vsp_ui_start.sh")
s=p.read_text(encoding="utf-8", errors="replace")

# replace common module forms
s2=s
s2=re.sub(r'\bvsp_demo_app:app\b', 'wsgi_vsp_p910h:app', s2)
s2=re.sub(r'\bvsp_demo_app\.py\b', 'wsgi_vsp_p910h.py', s2)

if s2==s:
    # last resort: if gunicorn command has a module arg at end, replace it
    s2=re.sub(r'(gunicorn\b[^\n]*\s)([A-Za-z0-9_\.]+:app)\s*$', r'\1wsgi_vsp_p910h:app', s2, flags=re.M)

p.write_text(s2, encoding="utf-8")
print("[OK] patched vsp_ui_start.sh")
PY

bash -n bin/vsp_ui_start.sh
echo "[OK] start script bash -n OK"

echo "== [P910H] start service =="
sudo systemctl start "$SVC"
bash bin/ops/ops_restart_wait_ui_v1.sh

echo "== [P910H] verify ops_latest MUST be non-empty JSON =="
curl -sS -D /tmp/ops.hdr -o /tmp/ops.json "$BASE/api/vsp/ops_latest_v1"
head -n 5 /tmp/ops.hdr
wc -c /tmp/ops.json
python3 - <<'PY'
import json
t=open("/tmp/ops.json","r",encoding="utf-8",errors="replace").read().strip()
j=json.loads(t) if t else {}
print("body_len=",len(t))
print("has_source=", "source" in j, "ok=", j.get("ok"), "release_dir=", (j.get("source") or {}).get("release_dir"))
PY

echo "== [P910H] verify run_status NO_RID MUST be 200 =="
curl -sS -D- -o /dev/null "$BASE/api/vsp/run_status_v1" | head -n 5

echo "Open: $BASE/c/settings  (Ctrl+Shift+R)"
