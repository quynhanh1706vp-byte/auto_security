#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need cp; need head; need curl
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl"; exit 2; }
command -v sudo >/dev/null 2>&1 || true

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

compile_ok(){
  python3 - <<PY >/dev/null 2>&1
import py_compile
py_compile.compile("$1", doraise=True)
PY
}

echo "== [0] check current compile =="
if compile_ok "$W"; then
  echo "[OK] current gateway compiles"
else
  echo "[WARN] current gateway BROKEN. trying restore from backups..."
  # pick latest backup that compiles
  cand="$(ls -1t ${W}.bak_* 2>/dev/null | head -n 80 || true)"
  [ -n "$cand" ] || { echo "[ERR] no backups found to restore"; exit 2; }

  restored=""
  while read -r b; do
    [ -f "$b" ] || continue
    if compile_ok "$b"; then
      cp -f "$b" "$W"
      restored="$b"
      echo "[OK] restored from: $b"
      break
    fi
  done <<<"$cand"

  [ -n "$restored" ] || { echo "[ERR] no compiling backup found"; exit 2; }
fi

cp -f "$W" "${W}.bak_csuite_v4_${TS}"
echo "[BACKUP] ${W}.bak_csuite_v4_${TS}"

echo "== [1] patch: before_request redirect /c/* -> canonical tabs (NO route collisions) =="
python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "# VSP_CSUITE_BEFORE_REQUEST_REDIRECT_V4"
if MARK not in s:
    block = r'''

%s
# Redirect /c/* to canonical HTML tabs. Avoids JSON "not allowed" and route conflicts.
try:
    from flask import request, redirect
except Exception:
    request = None
    redirect = None

@app.before_request
def vsp_csuite_redirect_v4():
    try:
        if request is None or redirect is None:
            return None
        path = (request.path or "")
        if not path.startswith("/c"):
            return None

        # Map /c pages to canonical tabs
        if path in ("/c", "/c/", "/c/dashboard"):
            target = "/vsp5"
        elif path == "/c/runs":
            target = "/runs"
        elif path == "/c/data_source":
            target = "/data_source"
        elif path == "/c/settings":
            target = "/settings"
        elif path == "/c/rule_overrides":
            target = "/rule_overrides"
        else:
            target = "/vsp5"

        rid = (request.args.get("rid") or "").strip()
        qs = ("?rid=" + rid) if rid else ""
        return redirect(target + qs, code=302)
    except Exception:
        return None
''' % MARK

    # Append at EOF (safe: not between try/except blocks)
    s = s.rstrip() + "\n" + block + "\n"

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile OK")
PY

echo "== [2] restart best-effort (no password prompt) =="
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  sudo systemctl daemon-reload || true
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
else
  echo "[WARN] no passwordless sudo. Run manually:"
  echo "  sudo systemctl daemon-reload && sudo systemctl restart $SVC"
fi

echo "== [3] smoke: /c/* should 302 => canonical, and HTML after -L =="
for pth in /c /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE$pth" || true)"
  echo "$pth => $code"
done

echo "-- follow redirects (first char should be '<') --"
for pth in /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides; do
  first="$(curl -fsSL --connect-timeout 1 --max-time 8 "$BASE$pth" | head -c 1 || true)"
  if [ "$first" != "<" ]; then
    echo "[FAIL] $pth after -L not HTML (first_char='${first:-?}')"
    exit 1
  fi
  echo "[OK] $pth => HTML"
done

echo "[DONE] CSuite redirect fixed safely. Ctrl+F5 once."
