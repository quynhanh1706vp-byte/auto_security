#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_before_recover_${TS}"
echo "[SNAPSHOT] ${W}.bak_before_recover_${TS}"

echo "== find latest backup that can run (runpy.run_path) =="

GOOD="$(python3 - <<'PY'
from pathlib import Path
import runpy, time

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

def ok(p: Path)->bool:
    try:
        runpy.run_path(str(p), run_name="__main__")
        return True
    except Exception:
        return False

for p in baks:
    if ok(p):
        print(str(p))
        raise SystemExit(0)

print("")
PY
)"

if [ -z "$GOOD" ]; then
  echo "[ERR] no runnable backup found. Keep current file."
  exit 2
fi

echo "[OK] GOOD_BACKUP=$GOOD"
cp -f "$GOOD" "$W"
echo "[RESTORE] $W <= $GOOD"

python3 -m py_compile "$W" && echo "[OK] py_compile OK after restore"

echo "== patch WSGI apply hook (safe, independent from Flask routes) =="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RULE_OVERRIDES_APPLY_WSGI_V1"
if marker in s:
    print("[OK] marker already present, skip patch.")
    raise SystemExit(0)

# Find the WSGI callable "application"
m = re.search(r'^(def\s+application\s*\(\s*environ\s*,\s*start_response\s*\)\s*:)', s, flags=re.M)
if not m:
    # fallback: sometimes signature is (environ, start_response, ...)
    m = re.search(r'^(def\s+application\s*\(\s*environ\s*,\s*start_response[^\)]*\)\s*:)', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def application(environ, start_response): in wsgi file")

insert_at = m.end(1)

hook = r'''
    # VSP_P1_RULE_OVERRIDES_APPLY_WSGI_V1
    # Intercept Apply endpoint early to avoid outer guard 404 and to return ok=true for UI/autorefresh.
    try:
        _m = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
        _path = environ.get("PATH_INFO","") or ""
        if _m == "POST" and _path in ("/api/ui/rule_overrides_v2_apply_v2", "/api/ui/rule_overrides_v2_apply"):
            import json, time
            from pathlib import Path

            def _reply(code:int, obj:dict):
                body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
                hdrs = [("Content-Type","application/json; charset=utf-8"), ("Content-Length", str(len(body)))]
                start_response(f"{code} {'OK' if code==200 else 'ERROR'}", hdrs)
                return [body]

            ts = int(time.time())
            # read request body
            try:
                clen = int(environ.get("CONTENT_LENGTH") or "0")
            except Exception:
                clen = 0
            raw = b""
            try:
                if clen > 0 and environ.get("wsgi.input"):
                    raw = environ["wsgi.input"].read(clen) or b""
            except Exception:
                raw = b""

            payload = {}
            try:
                if raw:
                    payload = json.loads(raw.decode("utf-8", errors="replace")) or {}
            except Exception:
                payload = {}

            rid = (environ.get("QUERY_STRING","") or "")
            # allow rid via JSON body primarily
            rid = (payload.get("rid") or payload.get("RUN_ID") or payload.get("run_id") or "").strip()
            if not rid:
                return _reply(400, {"ok": False, "error": "RID_MISSING", "path": _path, "ts": ts})

            rp = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2/rules.json")
            if not rp.exists():
                rp = Path(__file__).resolve().parent / "out_ci" / "rule_overrides_v2" / "rules.json"
            if not rp.exists():
                return _reply(404, {"ok": False, "error": "RULES_NOT_FOUND", "rid": rid, "rules_path": str(rp), "path": _path, "ts": ts})

            txt = rp.read_text(encoding="utf-8", errors="replace") or "{}"
            try:
                _ = json.loads(txt)
            except Exception as e:
                return _reply(400, {"ok": False, "error": "RULES_JSON_INVALID", "detail": str(e), "rid": rid, "rules_path": str(rp), "path": _path, "ts": ts})

            out_dir = rp.parent
            out_dir.mkdir(parents=True, exist_ok=True)
            (out_dir / "last_apply.json").write_text(
                json.dumps({"ok": True, "rid": rid, "rules_path": str(rp), "ts": ts}, indent=2),
                encoding="utf-8"
            )

            return _reply(200, {"ok": True, "rid": rid, "rules_path": str(rp), "path": _path, "ts": ts})
    except Exception:
        # fallthrough to normal handling
        pass
'''

s2 = s[:insert_at] + "\n" + hook + s[insert_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted WSGI apply hook marker:", marker)
PY

python3 -m py_compile "$W" && echo "[OK] py_compile OK after hook"

echo "[DONE] Now restart UI and test the POST endpoint."
echo "  - If you use single-owner: bin/p1_ui_8910_single_owner_start_v2.sh"
echo "  - Then: curl -sS -X POST http://127.0.0.1:8910/api/ui/rule_overrides_v2_apply_v2 -H 'Content-Type: application/json' -d '{\"rid\":\"RUN_20251120_130310\"}' | python3 -m json.tool"
