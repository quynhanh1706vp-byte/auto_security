#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_move_allow2_${TS}"
echo "[BACKUP] ${W}.bak_move_allow2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

START = "VSP_P2_RUN_FILE_ALLOW2_NO403_V1"
END   = "/VSP_P2_RUN_FILE_ALLOW2_NO403_V1"
wrap_marker = "VSP_FIX_RUNS_V3_WRAPAPP_V2"

# 1) remove old allow2 block (the one appended at end)
s2, n_rm = re.subn(
    rf"(?s)\n\s*#\s*====================\s*{START}\s*====================.*?#\s*====================\s*{END}\s*====================\s*\n",
    "\n",
    s
)

# Also remove any stray route decorator for allow2 if block markers were missing
s2, n_rm2 = re.subn(r'^\s*@(?:app|application)\.(?:get|route)\(\s*"/api/vsp/run_file_allow2".*?\n', '', s2, flags=re.M)

# 2) find insertion point BEFORE wrap
idx = s2.find(wrap_marker)
if idx < 0:
    raise SystemExit(f"[ERR] cannot find wrap marker '{wrap_marker}'")

insert_at = s2.rfind("\n", 0, idx)
if insert_at < 0: insert_at = idx

block = textwrap.dedent(rf"""
# ===================== {START} =====================
# NOTE: must be defined BEFORE {wrap_marker} wraps app/application into WSGI callables.
try:
    from flask import request, Response
except Exception:
    request = None
    Response = None

def _vsp_allow2_resolve_run_dir(rid: str):
    # try reuse existing helpers if present
    for name in ("vsp_find_run_dir","_vsp_find_run_dir","resolve_run_dir","vsp_resolve_run_dir","_vsp_resolve_run_dir"):
        fn = globals().get(name)
        if callable(fn):
            try:
                d = fn(rid)
                if d:
                    return str(d)
            except Exception:
                pass
    # fallback: common roots used by UI
    from pathlib import Path as _P
    roots = [
      _P("/home/test/Data/SECURITY_BUNDLE/out"),
      _P("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
      _P("/home/test/Data/SECURITY_BUNDLE/out_ci"),
    ]
    for r in roots:
        d = r / rid
        if d.is_dir():
            return str(d)
    return None

def _vsp_allow2_mime(path: str) -> str:
    path = (path or "").lower()
    if path.endswith(".json") or path.endswith(".sarif"):
        return "application/json; charset=utf-8"
    if path.endswith(".html") or path.endswith(".htm"):
        return "text/html; charset=utf-8"
    if path.endswith(".csv"):
        return "text/csv; charset=utf-8"
    if path.endswith(".tgz") or path.endswith(".tar.gz"):
        return "application/gzip"
    if path.endswith(".zip"):
        return "application/zip"
    return "application/octet-stream"

def _vsp_allow2_read_bytes(fp):
    with open(fp, "rb") as f:
        return f.read()

def _vsp_allow2_err(msg: str, code: int = 200):
    # IMPORTANT: return 200 to avoid console "403 spam"
    try:
        import json
        payload = json.dumps({{"ok": False, "err": msg}}, ensure_ascii=False).encode("utf-8")
        return Response(payload, status=code, mimetype="application/json")
    except Exception:
        return ("", code)

def _vsp_allow2_ok_bytes(b: bytes, mime: str):
    return Response(b, status=200, mimetype=mime)

# Flask instance must exist here (BEFORE wrap)
@app.route("/api/vsp/run_file_allow2", methods=["GET"])
def _api_vsp_run_file_allow2_v1():
    if request is None or Response is None:
        return ("", 500)
    rid = (request.args.get("rid") or "").strip()
    rel = (request.args.get("path") or "").strip()
    if not rid or not rel:
        return _vsp_allow2_err("missing rid/path", 200)

    # normalize rel path
    rel = rel.lstrip("/").replace("\\", "/")
    if ".." in rel or rel.startswith(("/", "~")):
        return _vsp_allow2_err("bad path", 200)

    # allowlist for UI files (extend as needed)
    allow = set([
      "SUMMARY.txt",
      "findings_unified.json",
      "findings_unified.sarif",
      "reports/findings_unified.csv",
      "reports/findings_unified.html",
      "reports/findings_unified.tgz",
      "reports/findings_unified.zip",
      "run_gate.json",
      "run_gate_summary.json",
      "reports/run_gate_summary.json",   # <-- key fix
      "reports/run_gate_summary.json".replace("reports/", "reports/"),  # no-op, keep explicit
    ])
    if rel not in allow:
        return _vsp_allow2_err("not allowed", 200)

    run_dir = _vsp_allow2_resolve_run_dir(rid)
    if not run_dir:
        return _vsp_allow2_err("rid not found", 200)

    from pathlib import Path as _P
    fp = _P(run_dir) / rel
    if not fp.is_file():
        return _vsp_allow2_err("file missing", 200)

    b = _vsp_allow2_read_bytes(str(fp))
    return _vsp_allow2_ok_bytes(b, _vsp_allow2_mime(rel))

print("[VSP_RUN_FILE_ALLOW2] mounted /api/vsp/run_file_allow2 (pre-wrap)")
# ===================== /{END} =====================
""")

s3 = s2[:insert_at+1] + block + s2[insert_at+1:]
p.write_text(s3, encoding="utf-8")

print(f"[OK] removed old allow2 block: markers_rm={n_rm} decorator_rm={n_rm2}")
print("[OK] inserted allow2 block BEFORE wrap marker")
PY

echo "== py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 1.0

echo "== sanity =="
curl -sS -I "$BASE/" | sed -n '1,12p' || true
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 220; echo || true

RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 - <<'PY'
import sys, json
j=json.load(sys.stdin)
print(j["items"][0]["run_id"])
PY
)"
echo "[RID]=$RID"
echo "== allow2 (gate summary, should be 200 and NOT 403) =="
curl -sS -i "$BASE/api/vsp/run_file_allow2?rid=$RID&path=reports/run_gate_summary.json" | head -n 25 || true

echo "[DONE] Now hard reload /runs (Ctrl+Shift+R). Console 403 spam should drop if JS is rewired to allow2."
