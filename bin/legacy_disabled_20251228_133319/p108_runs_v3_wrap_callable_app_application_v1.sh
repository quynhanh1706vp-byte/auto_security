#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sed

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p108_${TS}"
echo "[BACKUP] ${W}.bak_p108_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P108_RUNS_V3_WRAP_CALLABLE_APP_APPLICATION_V1"
if marker in s:
    print("[OK] already patched")
    sys.exit(0)

addon = r'''
# VSP_P108_RUNS_V3_WRAP_CALLABLE_APP_APPLICATION_V1
# Deterministic WSGI middleware: intercept /api/ui/runs_v3 regardless of Flask routes/middlewares.
try:
    import os, time, json
    from urllib.parse import parse_qs
except Exception:
    os = None

_VSP_P108_CACHE = {"t": 0.0, "key": "", "val": None}

def _vsp_p108_json_bytes(obj):
    try:
        return json.dumps(obj, ensure_ascii=False).encode("utf-8")
    except Exception:
        return b'{"ok":false,"ver":"p108","err":"json_encode_failed"}'

def _vsp_p108_scan(include_ci: bool, limit: int):
    roots = ["/home/test/Data/SECURITY_BUNDLE/out"]
    if include_ci:
        roots += ["/home/test/Data/SECURITY_BUNDLE/out_ci", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]

    items=[]
    seen=set()
    now=time.time()

    if not os:
        return items

    for root in roots:
        try:
            if not os.path.isdir(root):
                continue
            for name in os.listdir(root):
                if not (name.startswith("RUN_") or name.startswith("VSP_CI_")):
                    continue
                full=os.path.join(root, name)
                try:
                    real=os.path.realpath(full)
                except Exception:
                    real=full

                # dedupe symlink aliases (e.g., VSP_CI_RUN_* -> VSP_CI_*)
                if real in seen:
                    continue
                if not os.path.isdir(real):
                    continue
                seen.add(real)

                try:
                    st=os.stat(real); mtime=float(st.st_mtime)
                except Exception:
                    mtime=now

                items.append({
                    "rid": name,
                    "run_id": name,
                    "name": name,
                    "path": real,
                    "root": root,
                    "ts": mtime,
                    "kind": ("ci" if name.startswith("VSP_CI_") and not name.startswith("VSP_CI_RUN_") else "run"),
                })
        except Exception:
            continue

    items.sort(key=lambda x: x.get("ts", 0.0), reverse=True)

    # Pin newest REAL CI folder (prefer VSP_CI_*, avoid alias VSP_CI_RUN_*)
    if include_ci:
        ci=[x for x in items if str(x.get("rid","")).startswith("VSP_CI_") and not str(x.get("rid","")).startswith("VSP_CI_RUN_")]
        if ci:
            newest_ci=ci[0]
            rest=[x for x in items if x is not newest_ci]
            items=[newest_ci]+rest

    return items[:max(1, min(int(limit), 500))]

class _VspRunsV3P108:
    def __init__(self, inner):
        self.inner = inner
        self._p108_wrapped = True

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            if path not in ("/api/ui/runs_v3", "/api/ui/runs_v3_p108"):
                return self.inner(environ, start_response)

            qs = environ.get("QUERY_STRING","") or ""
            q = parse_qs(qs, keep_blank_values=True)
            include_ci = (q.get("include_ci", ["1"])[0] or "1").lower() in ("1","true","yes","on")
            try:
                limit_req = int(q.get("limit", ["200"])[0] or "200")
            except Exception:
                limit_req = 200
            limit_req = max(1, min(limit_req, 500))

            key = f"ci={1 if include_ci else 0}&limit={limit_req}"
            now = time.time()

            if _VSP_P108_CACHE.get("val") is not None and _VSP_P108_CACHE.get("key")==key:
                if (now - float(_VSP_P108_CACHE.get("t",0.0))) < 15.0:
                    body=_vsp_p108_json_bytes(_VSP_P108_CACHE["val"])
                    start_response("200 OK", [
                        ("Content-Type","application/json; charset=utf-8"),
                        ("Cache-Control","no-store"),
                        ("X-VSP-RUNS-V3","p108-cache"),
                    ])
                    return [body]

            items = _vsp_p108_scan(include_ci=include_ci, limit=limit_req)
            out = {
                "ok": True,
                "ver": "p108",
                "include_ci": include_ci,
                "total": len(items),
                "items": items,
                "runs": items,
            }
            _VSP_P108_CACHE["t"]=now
            _VSP_P108_CACHE["key"]=key
            _VSP_P108_CACHE["val"]=out

            body=_vsp_p108_json_bytes(out)
            start_response("200 OK", [
                ("Content-Type","application/json; charset=utf-8"),
                ("Cache-Control","no-store"),
                ("X-VSP-RUNS-V3","p108"),
            ])
            return [body]
        except Exception as e:
            body=_vsp_p108_json_bytes({"ok":False,"ver":"p108","err":str(e)})
            start_response("500 Internal Server Error", [
                ("Content-Type","application/json; charset=utf-8"),
                ("Cache-Control","no-store"),
                ("X-VSP-RUNS-V3","p108-err"),
            ])
            return [body]

# Wrap callable globals safely (no Flask needed)
try:
    for _name in ("app","application"):
        _obj = globals().get(_name)
        if _obj is not None and callable(_obj) and not getattr(_obj, "_p108_wrapped", False):
            globals()[_name] = _VspRunsV3P108(_obj)
except Exception:
    pass
'''
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P108 WSGI middleware (wrap callable app/application)")
PY

echo "== [P108] py_compile =="
python3 -m py_compile "$W"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [P108] daemon-reload + restart =="
sudo systemctl daemon-reload
sudo systemctl restart "$SVC"
sudo systemctl is-active "$SVC" --quiet && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== [P108] wait LISTEN 8910 =="
ok=0
for i in $(seq 1 120); do
  if ss -lntp 2>/dev/null | grep -qE ':(8910)\b'; then ok=1; break; fi
  sleep 0.1
done
[ "$ok" -eq 1 ] || { echo "[ERR] no LISTEN 8910"; systemctl status "$SVC" --no-pager -n 80 | head -n 80; exit 2; }

echo "== [P108] wait /runs up =="
ok=0
for i in $(seq 1 180); do
  if curl -fsS --connect-timeout 1 --max-time 6 "$BASE/runs" -o /dev/null; then ok=1; break; fi
  sleep 0.2
done
[ "$ok" -eq 1 ] || { echo "[ERR] /runs not reachable"; journalctl -u "$SVC" -n 120 --no-pager | tail -n 120; exit 2; }

echo "== [P108] smoke runs_v3 (must ver=p108 + has VSP_CI + first=VSP_CI_*) =="
curl -fsS "$BASE/api/ui/runs_v3?limit=50&include_ci=1" -o /tmp/p108_runs_v3.json
python3 - <<'PY'
import json
j=json.load(open("/tmp/p108_runs_v3.json","r",encoding="utf-8",errors="replace"))
items=j.get("items",[])
txt=str(j)
print("ok=", j.get("ok"),
      "ver=", j.get("ver"),
      "items=", len(items),
      "first=", (items[0].get("rid") if items else None),
      "has_VSP_CI=", ("VSP_CI_" in txt))
PY

echo "== [P108] smoke debug endpoint /api/ui/runs_v3_p108 =="
curl -fsS "$BASE/api/ui/runs_v3_p108?limit=50&include_ci=1" -o /tmp/p108_runs_v3_dbg.json
python3 - <<'PY'
import json
j=json.load(open("/tmp/p108_runs_v3_dbg.json","r",encoding="utf-8",errors="replace"))
items=j.get("items",[])
txt=str(j)
print("ok=", j.get("ok"),
      "ver=", j.get("ver"),
      "items=", len(items),
      "first=", (items[0].get("rid") if items else None),
      "has_VSP_CI=", ("VSP_CI_" in txt))
PY

echo "[OK] P108 done"
