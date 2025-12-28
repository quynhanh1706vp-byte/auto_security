#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_fix_findings_api_${TS}"
echo "[BACKUP] ${APP}.bak_fix_findings_api_${TS}"

python3 - <<'PY'
import re, json
from pathlib import Path

APP = Path("vsp_demo_app.py")
s = APP.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_FINDINGS_API_SOURCE_P0_V1"

# ensure imports (Path, json, jsonify, Response are common; we'll soft-add only if missing)
def ensure_import(module_line_pat, add_line):
    global s
    if re.search(module_line_pat, s, flags=re.M):
        return
    s = add_line + "\n" + s

# Path/json helpers
if "from pathlib import Path" not in s:
    ensure_import(r"^from\s+pathlib\s+import\s+Path", "from pathlib import Path")
if "import json" not in s:
    ensure_import(r"^import\s+json\b", "import json")

# jsonify import
if "jsonify" not in s:
    m = re.search(r"^from\s+flask\s+import\s+(.+)$", s, flags=re.M)
    if m:
        line = m.group(0)
        if "jsonify" not in line:
            # append jsonify
            newline = line.rstrip()
            if newline.endswith(")"):
                newline = newline[:-1]
                if not newline.endswith(","):
                    newline += ", "
                newline += "jsonify)"
            else:
                if not newline.endswith(","):
                    newline += ", "
                newline += "jsonify"
            s = s.replace(line, newline, 1)
    else:
        ensure_import(r"^from\s+flask\s+import\s+jsonify", "from flask import jsonify")

# avoid duplicate injection
if MARK not in s:
    inject = f"""

# === {MARK} ===
def _vsp_sb_root_p0_v1():
    # ui/ is under SECURITY_BUNDLE/ui; SECURITY_BUNDLE is parent dir
    try:
        return Path(__file__).resolve().parent.parent
    except Exception:
        return Path.cwd().parent

def _vsp_pick_latest_findings_unified_json_p0_v1():
    \"\"\"Pick best findings_unified.json source.
    Priority:
      1) latest RUN_*/reports/findings_unified.json
      2) latest RUN_*/findings_unified.json
      3) ui/out_ci/findings_unified.json
      4) ui/findings_unified.json (legacy)
    \"\"\"
    ui_dir = Path(__file__).resolve().parent
    sb = _vsp_sb_root_p0_v1()
    out_dir = sb / "out"

    candidates = []

    # (1)(2) from out/RUN_*
    try:
        if out_dir.is_dir():
            runs = [p for p in out_dir.iterdir() if p.is_dir() and p.name.startswith("RUN_")]
            runs.sort(key=lambda p: p.stat().st_mtime, reverse=True)
            for rd in runs[:50]:
                a = rd / "reports" / "findings_unified.json"
                b = rd / "findings_unified.json"
                if a.is_file():
                    return a
                if b.is_file():
                    return b
    except Exception:
        pass

    # (3)(4) local fallbacks
    c = ui_dir / "out_ci" / "findings_unified.json"
    if c.is_file():
        return c
    d = ui_dir / "findings_unified.json"
    if d.is_file():
        return d

    return None

def _vsp_load_findings_unified_p0_v1():
    p = _vsp_pick_latest_findings_unified_json_p0_v1()
    if not p:
        return {{"ok": True, "items": [], "findings": [], "total": 0, "notes": ["missing findings_unified.json"], "src": None}}
    try:
        data = json.loads(p.read_text(encoding="utf-8", errors="replace") or "{{}}")
    except Exception as e:
        return {{"ok": False, "items": [], "findings": [], "total": 0, "notes": [f"parse error: {{e}}"], "src": str(p)}}

    # normalize items
    items = []
    if isinstance(data, dict):
        if isinstance(data.get("items"), list):
            items = data.get("items") or []
        elif isinstance(data.get("findings"), list):
            items = data.get("findings") or []
        else:
            # sometimes nested
            x = data.get("data") or {{}}
            if isinstance(x, dict) and isinstance(x.get("items"), list):
                items = x.get("items") or []
    elif isinstance(data, list):
        items = data

    if isinstance(data, dict):
        data["items"] = items
        data["items_len"] = len(items)
        data["total"] = int(data.get("total") or len(items) or 0)
        data["src"] = str(p)
        data.setdefault("ok", True)
        return data

    return {{"ok": True, "items": items, "items_len": len(items), "total": len(items), "src": str(p)}}

# Explicit endpoint to stop fallback shadowing
@app.get("/api/vsp/findings")
def vsp_findings_api_p0_v1():
    d = _vsp_load_findings_unified_p0_v1()
    items = d.get("items") if isinstance(d, dict) else []
    return jsonify({{
        "ok": bool(d.get("ok", True)) if isinstance(d, dict) else True,
        "items": items if isinstance(items, list) else [],
        "items_len": int(d.get("items_len") or (len(items) if isinstance(items, list) else 0)),
        "src": d.get("src") if isinstance(d, dict) else None,
        "run_dir": d.get("run_dir") if isinstance(d, dict) else None,
        "notes": d.get("notes", []) if isinstance(d, dict) else [],
    }})

# Make /findings_unified.json consistent (commercial): always serve latest source, not stale local file
@app.get("/findings_unified.json")
def findings_unified_json_p0_v1():
    return jsonify(_vsp_load_findings_unified_p0_v1())
# === /{MARK} ===
"""
    # Insert before __main__ if possible
    mm = re.search(r"^if\s+__name__\s*==\s*['\\\"]__main__['\\\"]\s*:", s, flags=re.M)
    if mm:
        s = s[:mm.start()] + inject + "\n" + s[mm.start():]
    else:
        s = s.rstrip() + "\n" + inject + "\n"

APP.write_text(s, encoding="utf-8")
print("[OK] injected explicit /api/vsp/findings and refreshed /findings_unified.json")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile: $APP"

echo
echo "[NEXT] restart 8910 (no sudo) then verify:"
echo "  pkill -f 'gunicorn .*8910' 2>/dev/null || true; sleep 0.8"
echo "  nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \\"
echo "    --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \\"
echo "    --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \\"
echo "    --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \\"
echo "    --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \\"
echo "    > out_ci/ui_8910.boot.log 2>&1 &"
echo "  curl -sS http://127.0.0.1:8910/api/vsp/findings | jq 'keys, .items_len, .src' -C"
echo "  curl -sS http://127.0.0.1:8910/findings_unified.json | jq '.items_len // (.items|length) // (.findings|length)' -C"
