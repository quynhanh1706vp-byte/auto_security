#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE_URL="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp; need grep
command -v node >/dev/null 2>&1 || { echo "[ERR] missing: node (need node --check)"; exit 2; }
command -v systemctl >/dev/null 2>&1 || true
command -v sudo >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

[ -f "$JS" ]  || { echo "[ERR] missing $JS"; exit 2; }
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$JS"  "${JS}.bak_p0_v3_${TS}"
cp -f "$APP" "${APP}.bak_p0_v3_${TS}"
echo "[BACKUP] $JS  -> ${JS}.bak_p0_v3_${TS}"
echo "[BACKUP] $APP -> ${APP}.bak_p0_v3_${TS}"

echo "== [1] Fix JS: BASE + rid decl + run_file_allow =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

changed = 0

# (A) Ensure BASE exists (avoid duplicate)
if not re.search(r'(?m)^\s*const\s+BASE\s*=\s*', s):
    base_decl = (
        "  // [P0_V3] commercial-safe base (avoid ReferenceError: BASE is not defined)\n"
        "  const BASE = (window.VSP_UI_BASE && String(window.VSP_UI_BASE).trim())\n"
        "    ? String(window.VSP_UI_BASE).replace(/\\/+$/,'')\n"
        "    : (location.origin);\n\n"
    )
    # insert after "use strict" if present, else after first line
    m = re.search(r'(?m)^[ \t]*[\'"]use strict[\'"]\s*;\s*$', s)
    if m:
        insert_at = m.end()
        s = s[:insert_at] + "\n" + base_decl + s[insert_at:]
    else:
        # try after first IIFE open line, else top
        lines = s.splitlines(True)
        if lines:
            s = lines[0] + "\n" + base_decl + "".join(lines[1:])
        else:
            s = base_decl + s
    changed += 1

# (B) Fix broken declarations:
#  - "const = (...rid...)"  -> "const rid = (..."
#  - "rid = (...)"          -> "const rid = (..."
s2 = re.sub(r'(?m)^\s*const\s*=\s*\(', '    const rid = (', s)
if s2 != s:
    s = s2; changed += 1

s2 = re.sub(r'(?m)^\s*rid\s*=\s*\(', '    const rid = (', s)
if s2 != s:
    s = s2; changed += 1

# (C) Make sure UI uses commercial endpoint (avoid 404 /api/vsp/run_file)
# Replace literal path usage
s2 = re.sub(r'(/api/vsp/)run_file(\b)', r'\1run_file_allow\2', s)
if s2 != s:
    s = s2; changed += 1

# (D) Hard-guard: if any remaining "const =" exists, make it obvious (syntax-safe)
# (should not happen, but keep script resilient)
if re.search(r'(?m)^\s*const\s*=\s*', s):
    s = re.sub(r'(?m)^\s*const\s*=\s*', '    // [P0_V3] BAD_DECL_REMOVED const = ', s)
    changed += 1

p.write_text(s, encoding="utf-8")
print("[OK] js_patch_changed_steps=", changed)
PY

echo "== [2] node --check JS =="
if node --check "$JS" >/dev/null 2>&1; then
  echo "[OK] node syntax: PASS"
else
  echo "[ERR] node syntax: FAIL"
  node --check "$JS" 2>&1 | head -n 60
  exit 2
fi

echo "== [3] Fix backend: /api/vsp/rule_overrides_v1 must be always-200 (default on missing/invalid) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Implementation: safe GET/POST with atomic write, never 500 for missing file.
block = textwrap.dedent(r'''
    @app.route("/api/vsp/rule_overrides_v1", methods=["GET","POST"])
    def vsp_rule_overrides_v1():
        import os, json, time, tempfile
        path = os.environ.get("VSP_RULE_OVERRIDES_PATH", "/home/test/Data/SECURITY_BUNDLE/out_ci/rule_overrides.json")
        now_ts = int(time.time())

        def _default():
            return {
                "enabled": True,
                "overrides": [],
                "updated_at": now_ts,
                "updated_by": "system"
            }

        def _read():
            try:
                if not os.path.exists(path):
                    return _default()
                with open(path, "r", encoding="utf-8") as f:
                    j = json.load(f)
                # accept either {"data":{...}} or raw {...}
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

        def _write(data: dict):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            tmp_fd, tmp_path = tempfile.mkstemp(prefix=".rule_overrides_", suffix=".json", dir=os.path.dirname(path))
            try:
                with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
                    json.dump({"data": data}, f, ensure_ascii=False, indent=2)
                os.replace(tmp_path, path)
                return True
            except Exception:
                try:
                    os.unlink(tmp_path)
                except Exception:
                    pass
                return False

        if request.method == "POST":
            payload = request.get_json(silent=True) or {}
            data = payload.get("data") if isinstance(payload, dict) else None
            if not isinstance(data, dict):
                # allow posting raw dict too
                data = payload if isinstance(payload, dict) else {}
            data.setdefault("enabled", True)
            data.setdefault("overrides", [])
            data["updated_at"] = int(time.time())
            data["updated_by"] = payload.get("updated_by") or "ui"
            ok_write = _write(data)
            return jsonify({
                "ok": True,
                "saved": bool(ok_write),
                "data": data,
                "path": path,
                "ts": int(time.time()),
                "who": "VSP_RULE_OVERRIDES_EDITOR_P0_V1"
            })

        data = _read()
        return jsonify({
            "ok": True,
            "data": data,
            "path": path,
            "ts": int(time.time()),
            "who": "VSP_RULE_OVERRIDES_EDITOR_P0_V1"
        })
''').rstrip() + "\n"

# Replace existing route if present
pat = r'(?s)@app\.route\("/api/vsp/rule_overrides_v1".*?\)\n(?:def\s+vsp_rule_overrides_v1\(\):.*?)(?=\n@app\.route\(|\nif __name__ ==|\Z)'
if re.search(pat, s):
    s = re.sub(pat, block, s)
    replaced = True
else:
    # Insert near other /api/vsp routes: after any /api/vsp/runs route if possible, else append before __main__
    ins_pt = None
    m = re.search(r'(?s)(@app\.route\("/api/vsp/runs".*?\)\n.*?\n)(?=@app\.route\(|\nif __name__ ==|\Z)', s)
    if m:
        ins_pt = m.end(1)
        s = s[:ins_pt] + "\n" + block + "\n" + s[ins_pt:]
    else:
        m2 = re.search(r'(?m)^if __name__ == .__main__.:', s)
        if m2:
            ins_pt = m2.start()
            s = s[:ins_pt] + "\n" + block + "\n" + s[ins_pt:]
        else:
            s = s + "\n\n" + block
    replaced = False

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] rule_overrides_v1 patched. replaced_existing=", replaced)
PY

echo "== [4] Restart service (best-effort) =="
if command -v systemctl >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl restart "$SVC" || true
    sudo systemctl --no-pager --full status "$SVC" | sed -n '1,18p' || true
  else
    systemctl restart "$SVC" || true
    systemctl --no-pager --full status "$SVC" | sed -n '1,18p' || true
  fi
else
  echo "[WARN] systemctl not found; please restart UI process manually"
fi

echo "== [5] Quick API smoke (best-effort) =="
if command -v curl >/dev/null 2>&1; then
  echo "-- rule_overrides_v1 --"
  curl -fsS "$BASE_URL/api/vsp/rule_overrides_v1" | head -c 220; echo
fi

echo "[DONE] P0_V3 applied."
