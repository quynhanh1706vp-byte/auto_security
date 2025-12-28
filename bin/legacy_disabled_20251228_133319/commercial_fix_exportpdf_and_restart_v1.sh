#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

TS="$(date +%Y%m%d_%H%M%S)"
echo "== COMMERCIAL FIX v1 =="

# 1) Create hard WSGI entry for exportpdf preempt
cat > "$ROOT/wsgi_vsp_ui_gateway_exportpdf_only.py" <<'PY'
import os, glob, json
from urllib.parse import parse_qs
import wsgi_vsp_ui_gateway as base

def _norm_rid(rid: str) -> str:
    rid = (rid or "").strip()
    return rid[4:] if rid.startswith("RUN_") else rid

def _resolve_ci_dir(rid: str) -> str:
    rn = _norm_rid(rid)
    root = os.environ.get("VSP_CI_OUT_ROOT") or "/home/test/Data/SECURITY-10-10-v4/out_ci"
    cand = os.path.join(root, rn)
    if os.path.isdir(cand):
        return cand
    for d in sorted(glob.glob(os.path.join(root, "VSP_CI_*")), reverse=True):
        if rn in os.path.basename(d):
            return d
    return ""

def _pick_pdf(ci_dir: str) -> str:
    best = ""
    best_m = -1.0
    for pat in (os.path.join(ci_dir, "reports", "*.pdf"), os.path.join(ci_dir, "*.pdf")):
        for f in glob.glob(pat):
            try:
                m = os.path.getmtime(f)
            except Exception:
                continue
            if m > best_m:
                best_m = m
                best = f
    return best

class ExportPdfPreemptApp:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "").strip()

        # Preempt ONLY exportpdf
        if path.startswith("/api/vsp/run_export_v3/"):
            q = parse_qs(environ.get("QUERY_STRING", "") or "")
            fmt = (q.get("fmt", ["html"])[0] or "html").lower().strip()
            if fmt == "pdf":
                rid = path.split("/api/vsp/run_export_v3/", 1)[1].strip("/")
                ci_dir = _resolve_ci_dir(rid)
                pdf = _pick_pdf(ci_dir) if ci_dir else ""

                if pdf and os.path.isfile(pdf):
                    size = os.path.getsize(pdf)
                    start_response("200 OK", [
                        ("Content-Type", "application/pdf"),
                        ("Content-Disposition", f'attachment; filename="{os.path.basename(pdf)}"'),
                        ("Content-Length", str(size)),
                        ("X-VSP-EXPORT-AVAILABLE", "1"),
                        ("X-VSP-EXPORT-FILE", os.path.basename(pdf)),
                        ("X-VSP-WSGI-LAYER", "EXPORTPDF_ONLY"),
                    ])
                    return open(pdf, "rb")

                body = json.dumps({
                    "ok": False, "http_code": 404, "error": "PDF_NOT_FOUND",
                    "rid": rid, "rid_norm": _norm_rid(rid),
                    "ci_run_dir": ci_dir or None
                }).encode("utf-8")
                start_response("404 NOT FOUND", [
                    ("Content-Type", "application/json"),
                    ("Content-Length", str(len(body))),
                    ("X-VSP-EXPORT-AVAILABLE", "0"),
                    ("X-VSP-WSGI-LAYER", "EXPORTPDF_ONLY"),
                ])
                return [body]

        return self.inner(environ, start_response)

_inner = getattr(base, "application", None) or getattr(base, "app", None)
application = ExportPdfPreemptApp(_inner)

try:
    print("[VSP_WSGI_EXPORTPDF_ONLY] installed")
except Exception:
    pass
PY

python3 -m py_compile "$ROOT/wsgi_vsp_ui_gateway_exportpdf_only.py"
echo "[OK] wsgi_vsp_ui_gateway_exportpdf_only.py ready"

# 2) Rebuild restart script clean (NO syntax errors)
S="$ROOT/bin/restart_8910_gunicorn_commercial_v5.sh"
if [ -f "$S" ]; then
  cp -f "$S" "$S.bak_rebuild_${TS}"
  echo "[BACKUP] $S.bak_rebuild_${TS}"
fi

cat > "$S" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

mkdir -p out_ci

LOCK="out_ci/ui_8910.lock"
PIDFILE="out_ci/ui_8910.pid"
NOHUP="out_ci/ui_8910.nohup.log"
ACCESS="out_ci/ui_8910.access.log"
ERROR="out_ci/ui_8910.error.log"

HOST="127.0.0.1"
PORT="8910"
APP_MODULE="wsgi_vsp_ui_gateway_exportpdf_only:application"

# clear stale lock
rm -f "$LOCK"
: > "$LOCK"

# stop old pid
if [ -f "$PIDFILE" ]; then
  OLD="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "${OLD:-}" ] && kill -0 "$OLD" 2>/dev/null; then
    echo "[STOP] pid=$OLD"
    kill "$OLD" 2>/dev/null || true
    sleep 1
    kill -9 "$OLD" 2>/dev/null || true
  fi
  rm -f "$PIDFILE" || true
fi

# free port
if command -v lsof >/dev/null 2>&1; then
  P="$(lsof -ti tcp:${PORT} 2>/dev/null || true)"
  if [ -n "${P:-}" ]; then
    echo "[KILL] port ${PORT} pid=$P"
    kill -9 $P 2>/dev/null || true
  fi
fi

# clean caches so module reloads
rm -rf __pycache__ 2>/dev/null || true
rm -rf "$ROOT"/__pycache__ 2>/dev/null || true

echo "== start gunicorn ${APP_MODULE} ${PORT} =="

nohup gunicorn "${APP_MODULE}" \
  --workers 2 \
  --worker-class gthread \
  --threads 4 \
  --timeout 60 \
  --graceful-timeout 15 \
  --chdir "$ROOT" \
  --pythonpath "$ROOT" \
  --bind "${HOST}:${PORT}" \
  --pid "$PIDFILE" \
  --access-logfile "$ROOT/$ACCESS" \
  --error-logfile "$ROOT/$ERROR" \
  >> "$ROOT/$NOHUP" 2>&1 &

sleep 1

if command -v ss >/dev/null 2>&1; then
  if ss -lntp | grep -q ":${PORT}"; then
    echo "[OK] ${PORT} listening"
  else
    echo "[ERR] ${PORT} not listening"
    echo "== last nohup =="; tail -n 120 "$ROOT/$NOHUP" || true
    echo "== last error =="; tail -n 120 "$ROOT/$ERROR" || true
    rm -f "$LOCK" || true
    exit 1
  fi
fi

curl -sS "http://${HOST}:${PORT}/healthz" >/dev/null 2>&1 && echo "[OK] healthz reachable" || echo "[WARN] healthz not reachable yet"
rm -f "$LOCK" || true
BASH

chmod +x "$S"
echo "[OK] rebuilt restart script"

# 3) Restart now
rm -f "$ROOT/out_ci/ui_8910.lock"
"$S"

# 4) Verify export headers
RID="$(curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1" | jq -er '.items[0].run_id' 2>/dev/null || true)"
echo "RID=${RID:-<empty>}"

if [ -n "${RID:-}" ]; then
  echo "== export headers =="
  curl -sS -D- -o /dev/null "http://127.0.0.1:8910/api/vsp/run_export_v3/${RID}?fmt=pdf" \
    | grep -iE '^(http/|content-type:|x-vsp-wsgi-layer:|x-vsp-export-available:|x-vsp-export-file:)'
else
  echo "[WARN] cannot fetch RID (runs_index issue?)"
fi

echo "== DONE =="
