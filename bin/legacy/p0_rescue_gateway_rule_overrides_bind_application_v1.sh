#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl"; exit 2; }
command -v sudo >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || { echo "[ERR] need curl"; exit 2; }

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

latest_bak="$(ls -1t ${W}.bak_ro500_* 2>/dev/null | head -n 1 || true)"
echo "[INFO] latest_bak=$latest_bak"

cp -f "$W" "${W}.bak_bindapp_${TS}"
echo "[BACKUP] ${W}.bak_bindapp_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove any previous broken decorator-based route blocks that reference @app.route for rule_overrides_v1
# (avoid NameError: app not defined)
pat = r'(?s)@app\.route\("/api/vsp/rule_overrides_v1".*?\)\n\s*def\s+vsp_rule_overrides_v1\(\):.*?(?=\n@\w|^\s*def\s|\nif __name__ ==|\Z)'
s2 = re.sub(pat, "", s)

# Also remove any duplicate binder blocks if re-run
pat2 = r'(?s)#\s*\[P0_BIND_RULE_OVERRIDES_V1\].*?#\s*\[P0_BIND_RULE_OVERRIDES_V1_END\]\n?'
s2 = re.sub(pat2, "", s2)

block = textwrap.dedent(r'''
# [P0_BIND_RULE_OVERRIDES_V1]
def _vsp_p0_bind_rule_overrides_v1(_app):
    # Bind into the exported Flask app (gateway exports `application`)
    try:
        from flask import request, jsonify
    except Exception as _e:
        # If Flask isn't importable at import-time, don't crash gunicorn
        return False

    import os, json, time, tempfile

    @_app.route("/api/vsp/rule_overrides_v1", methods=["GET","POST"])
    def vsp_rule_overrides_v1():
        # Always-200 contract: never throw 500 to UI.
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

    return True

try:
    _a = globals().get("application") or globals().get("app")
    if _a is not None:
        _vsp_p0_bind_rule_overrides_v1(_a)
except Exception:
    # Never crash import-time
    pass
# [P0_BIND_RULE_OVERRIDES_V1_END]
''').strip() + "\n"

# Append binder block near end (safe)
s3 = s2.rstrip() + "\n\n" + block

p.write_text(s3, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] gateway patched + py_compile OK")
PY

echo "== [daemon-reload + restart] =="
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl daemon-reload
  sudo systemctl restart "$SVC" || true
else
  systemctl daemon-reload
  systemctl restart "$SVC" || true
fi

echo "== [wait port] =="
ok=0
for i in $(seq 1 80); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/settings" >/dev/null 2>&1; then ok=1; break; fi
  sleep 0.2
done

if [ "$ok" != "1" ]; then
  echo "[ERR] still not reachable: $BASE"
  echo "---- systemctl status ----"
  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl --no-pager --full status "$SVC" | sed -n '1,140p' || true
    echo "---- journalctl ----"
    sudo journalctl -u "$SVC" -n 220 --no-pager || true
  else
    systemctl --no-pager --full status "$SVC" | sed -n '1,140p' || true
    journalctl -u "$SVC" -n 220 --no-pager || true
  fi
  echo "---- error log tail ----"
  tail -n 220 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null || true

  # optional rollback to last bak_ro500 if exists
  if [ -n "${latest_bak:-}" ] && [ -f "$latest_bak" ]; then
    echo "[ROLLBACK] restoring gateway from $latest_bak"
    cp -f "$latest_bak" "$W"
    python3 -m py_compile "$W" || true
    if command -v sudo >/dev/null 2>&1; then
      sudo systemctl daemon-reload
      sudo systemctl restart "$SVC" || true
    else
      systemctl daemon-reload
      systemctl restart "$SVC" || true
    fi
  fi
  exit 2
fi

echo "[OK] UI up: $BASE"

echo "== [smoke rule_overrides_v1] =="
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | head -c 300; echo
echo "[DONE]"
