#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head; need sudo; need systemctl; need journalctl; need ss; need curl

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

SVC="vsp-ui-8910.service"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || err "missing $F"

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] capture failure context (if any) =="
sudo systemctl status "$SVC" --no-pager || true
sudo journalctl -u "$SVC" -n 80 --no-pager -o cat || true

echo
echo "== [1] restore gateway from latest backup made by v1p3b (pre-crash) =="
BK="$(ls -1t ${F}.bak_runfilegw_v1p3b_* 2>/dev/null | head -n 1 || true)"
if [ -n "$BK" ]; then
  cp -f "$BK" "$F"
  ok "restored: $F <= $BK"
else
  warn "no ${F}.bak_runfilegw_v1p3b_* found; continuing with current $F"
fi

cp -f "$F" "${F}.bak_before_wsgirewrite_v1p3c_${TS}"
ok "backup: ${F}.bak_before_wsgirewrite_v1p3c_${TS}"

echo
echo "== [2] inject WSGI rewrite middleware (NO @app decorator) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_RUN_FILE_WSGI_REWRITE_V1P3C"

if MARK in s:
    print("[OK] marker exists, skip")
else:
    inject = textwrap.dedent(r'''
# ==================== VSP_P0_RUN_FILE_WSGI_REWRITE_V1P3C ====================
# Commercial contract: FE calls /api/vsp/run_file?rid=...&name=...
# We rewrite environ to existing /api/vsp/run_file_allow?rid=...&path=...
# This avoids any dependency on Flask app globals and cannot break imports.
try:
    import urllib.parse as _vsp_up
except Exception:
    _vsp_up = None

def _vsp_map_name_to_path_v1p3c(name: str) -> str:
    m = {
      "gate_summary": "run_gate_summary.json",
      "gate_json": "run_gate.json",
      "findings_unified": "findings_unified.json",
      "findings_html": "reports/findings_unified.html",
      "run_manifest": "run_manifest.json",
      "run_evidence_index": "run_evidence_index.json",
    }
    return m.get(name, "")

def _vsp_rewrite_run_file_environ_v1p3c(environ):
    try:
        if not _vsp_up:
            return environ
        path = environ.get("PATH_INFO") or ""
        if path != "/api/vsp/run_file":
            return environ
        qs = environ.get("QUERY_STRING") or ""
        q = _vsp_up.parse_qs(qs, keep_blank_values=True)
        rid = (q.get("rid", [""])[0] or "").strip()
        name = (q.get("name", [""])[0] or "").strip()
        if not rid or not name:
            return environ
        mapped = _vsp_map_name_to_path_v1p3c(name)
        if not mapped:
            # allow raw safe filenames (no slash) as escape hatch
            if ("/" in name) or ("\\" in name) or (len(name) > 120):
                return environ
            if not re.match(r'^[a-zA-Z0-9_.-]{1,120}$', name):
                return environ
            mapped = name

        environ["PATH_INFO"] = "/api/vsp/run_file_allow"
        # rebuild query: rid + path (do not leak internal names in FE; only gateway sees it)
        environ["QUERY_STRING"] = _vsp_up.urlencode({"rid": rid, "path": mapped})
        return environ
    except Exception:
        return environ

# Wrap the WSGI callable safely (works whether variable is named application or app)
try:
    _vsp__old_application = application  # noqa: F821
    def application(environ, start_response):  # type: ignore
        environ = _vsp_rewrite_run_file_environ_v1p3c(environ)
        return _vsp__old_application(environ, start_response)
except Exception:
    try:
        _vsp__old_app_wsg = app.wsgi_app  # noqa: F821
        def _vsp_wrapped_wsgi_app(environ, start_response):
            environ = _vsp_rewrite_run_file_environ_v1p3c(environ)
            return _vsp__old_app_wsg(environ, start_response)
        app.wsgi_app = _vsp_wrapped_wsgi_app  # type: ignore
    except Exception:
        pass
# ==================== /VSP_P0_RUN_FILE_WSGI_REWRITE_V1P3C ====================
''')

    # Ensure "import re" exists for regex used in escape hatch
    if "import re" not in s:
        s = "import re\n" + s

    # Append near end (safe), before any "if __name__" block if present
    m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s, flags=re.M)
    if m:
        s2 = s[:m.start()] + "\n" + inject + "\n" + s[m.start():]
    else:
        s2 = s + "\n\n" + inject + "\n"

    p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] injected + py_compile OK")
PY

echo
echo "== [3] restart service safely =="
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC" || {
  warn "restart failed, showing logs and exiting"
  sudo systemctl status "$SVC" --no-pager || true
  sudo journalctl -xeu "$SVC" --no-pager -o cat | tail -n 160 || true
  err "service restart failed"
}
ok "restarted: $SVC"

echo "== [4] wait for port 8910 =="
for i in $(seq 1 50); do
  if ss -ltn | grep -q ':8910'; then ok "port 8910 LISTEN"; break; fi
  sleep 0.2
done
ss -ltn | grep ':8910' >/dev/null || err "8910 not listening"

echo "== [5] smoke endpoints =="
curl -fsS "http://127.0.0.1:8910/runs" >/dev/null && ok "/runs OK" || err "/runs FAIL"
curl -fsS "http://127.0.0.1:8910/api/vsp/runs?limit=1" >/dev/null && ok "/api/vsp/runs OK" || err "/api/vsp/runs FAIL"

echo "== [6] run_file contract should NOT 404 (will be 200 JSON or 302) =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/run_file?rid=VSP_CI_20251218_114312&name=gate_summary" | head -n 12 || true
