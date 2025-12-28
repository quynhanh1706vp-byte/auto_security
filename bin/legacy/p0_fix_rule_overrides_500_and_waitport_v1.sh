#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl"; exit 2; }
command -v sudo >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || { echo "[ERR] need curl"; exit 2; }

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$W" ]   || { echo "[ERR] missing $W"; exit 2; }

cp -f "$APP" "${APP}.bak_ro500_${TS}"
cp -f "$W"   "${W}.bak_ro500_${TS}"
echo "[BACKUP] ${APP}.bak_ro500_${TS}"
echo "[BACKUP] ${W}.bak_ro500_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

block = textwrap.dedent(r'''
    @app.route("/api/vsp/rule_overrides_v1", methods=["GET","POST"])
    def vsp_rule_overrides_v1():
        # [P0] Always-200 contract. No 500 for missing/invalid file.
        from flask import request, jsonify
        import os, json, time, tempfile

        path = os.environ.get("VSP_RULE_OVERRIDES_PATH", "/home/test/Data/SECURITY_BUNDLE/out_ci/rule_overrides.json")
        now_ts = int(time.time())

        def _default():
            return {"enabled": True, "overrides": [], "updated_at": now_ts, "updated_by": "system"}

        def _read():
            try:
                if not os.path.exists(path):
                    return _default()
                with open(path, "r", encoding="utf-8") as f:
                    j = json.load(f)
                if isinstance(j, dict) and "data" in j and isinstance(j["data"], dict):
                    j = j["data"]
                if not isinstance(j, dict):
                    return _default()
                j.setdefault("enabled", True)
                j.setdefault("overrides", [])
                j.setdefault("updated_at", now_ts)
                j.setdefault("updated_by", "system")
                return j
            except Exception:
                return _default()

        def _write(data: dict) -> bool:
            try:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                fd, tmp = tempfile.mkstemp(prefix=".rule_overrides_", suffix=".json", dir=os.path.dirname(path))
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump({"data": data}, f, ensure_ascii=False, indent=2)
                os.replace(tmp, path)
                return True
            except Exception:
                try:
                    os.unlink(tmp)
                except Exception:
                    pass
                return False

        if request.method == "POST":
            payload = request.get_json(silent=True) or {}
            data = payload.get("data") if isinstance(payload, dict) else None
            if not isinstance(data, dict):
                data = payload if isinstance(payload, dict) else {}
            data.setdefault("enabled", True)
            data.setdefault("overrides", [])
            data["updated_at"] = int(time.time())
            data["updated_by"] = (payload.get("updated_by") if isinstance(payload, dict) else None) or "ui"
            saved = _write(data)
            return jsonify({"ok": True, "saved": bool(saved), "data": data, "path": path, "ts": int(time.time()), "who": "VSP_RULE_OVERRIDES_P0"})

        data = _read()
        return jsonify({"ok": True, "data": data, "path": path, "ts": int(time.time()), "who": "VSP_RULE_OVERRIDES_P0"})
''').rstrip() + "\n"

def patch_file(fname: str):
    p = Path(fname)
    s = p.read_text(encoding="utf-8", errors="replace")

    # replace existing endpoint if any
    pat = r'(?s)@app\.route\("/api/vsp/rule_overrides_v1".*?\)\n\s*def\s+vsp_rule_overrides_v1\(\):.*?(?=\n@app\.route\(|\nif __name__ ==|\Z)'
    if re.search(pat, s):
        s = re.sub(pat, block, s)
        replaced = True
    else:
        # insert before __main__ or at end
        m = re.search(r'(?m)^if __name__ == .__main__.:', s)
        if m:
            s = s[:m.start()] + "\n" + block + "\n" + s[m.start():]
        else:
            s = s + "\n\n" + block
        replaced = False

    p.write_text(s, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    return replaced

r1 = patch_file("vsp_demo_app.py")
r2 = patch_file("wsgi_vsp_ui_gateway.py")
print("[OK] patched vsp_demo_app replaced_existing=", r1)
print("[OK] patched wsgi_vsp_ui_gateway replaced_existing=", r2)
PY

echo "== [Restart] $SVC =="
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
else
  systemctl restart "$SVC"
fi

echo "== [Wait port 8910] =="
ok=0
for i in $(seq 1 60); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/settings" >/dev/null 2>&1; then
    ok=1; break
  fi
  sleep 0.2
done
if [ "$ok" != "1" ]; then
  echo "[ERR] UI not reachable at $BASE after restart"
  echo "---- systemctl status ----"
  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl --no-pager --full status "$SVC" | sed -n '1,120p' || true
    echo "---- journalctl ----"
    sudo journalctl -u "$SVC" -n 200 --no-pager || true
  else
    systemctl --no-pager --full status "$SVC" | sed -n '1,120p' || true
    journalctl -u "$SVC" -n 200 --no-pager || true
  fi
  echo "---- error log tail ----"
  tail -n 200 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null || true
  exit 2
fi
echo "[OK] UI reachable: $BASE"

echo "== [Smoke] rule_overrides_v1 must be 200 =="
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | head -c 300; echo
echo "[DONE]"
