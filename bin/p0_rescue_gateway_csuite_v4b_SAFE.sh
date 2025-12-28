#!/usr/bin/env bash
set -u
cd /home/test/Data/SECURITY_BUNDLE/ui || exit 2

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
info(){ echo "[INFO] $*"; }
fail(){ echo "[FAIL] $*" >&2; }

[ -f "$W" ] || { fail "missing $W"; exit 2; }

compile_ok(){
  python3 - <<PY >/dev/null 2>&1
import py_compile
py_compile.compile("$1", doraise=True)
PY
}

info "== [0] check current compile =="
if compile_ok "$W"; then
  ok "current gateway compiles"
else
  warn "current gateway BROKEN. trying restore from backups..."
  cand="$(ls -1t ${W}.bak_* 2>/dev/null | head -n 120 || true)"
  if [ -z "${cand:-}" ]; then
    fail "no backups found to restore"
  else
    restored=""
    while read -r b; do
      [ -f "$b" ] || continue
      if compile_ok "$b"; then
        cp -f "$b" "$W"
        restored="$b"
        ok "restored from: $b"
        break
      fi
    done <<<"$cand"
    [ -n "${restored:-}" ] || fail "no compiling backup found (need manual fix)"
  fi
fi

cp -f "$W" "${W}.bak_csuite_v4b_${TS}"
ok "backup: ${W}.bak_csuite_v4b_${TS}"

info "== [1] patch: before_request redirect /c/* -> canonical tabs (no route collisions) =="
python3 - <<'PY'
from pathlib import Path
import re, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="# VSP_CSUITE_BEFORE_REQUEST_REDIRECT_V4B"
if MARK not in s:
    block = r'''

%s
# Redirect /c/* to canonical HTML tabs. Avoid JSON/proxy collisions.
try:
    from flask import request, redirect
except Exception:
    request = None
    redirect = None

@app.before_request
def vsp_csuite_redirect_v4b():
    try:
        if request is None or redirect is None:
            return None
        path = (request.path or "")
        if not path.startswith("/c"):
            return None

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
    s = s.rstrip() + "\n" + block + "\n"

# ensure gunicorn app binding exists
if not re.search(r'(?m)^\s*application\s*=\s*app\s*$', s):
    s = s.rstrip() + "\n\n# VSP_APPLICATION_BIND_V4B\napplication = app\n"

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile OK")
PY
ok "gateway patch applied"

info "== [2] restart (NO sudo prompt; restart failure will NOT exit) =="
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  sudo systemctl daemon-reload || true
  if sudo systemctl restart "$SVC"; then
    ok "restarted $SVC"
  else
    warn "restart failed (kept CLI alive). Showing diagnostics..."
    sudo systemctl status "$SVC" -l --no-pager || true
    sudo journalctl -u "$SVC" -n 220 --no-pager || true
    [ -f "$ERRLOG" ] && { echo "---- tail error log ----"; tail -n 160 "$ERRLOG" || true; }
  fi
else
  warn "no passwordless sudo. Run these manually (1 lần sudo -v rồi chạy tiếp):"
  echo "  sudo -v"
  echo "  sudo systemctl daemon-reload"
  echo "  sudo systemctl restart $SVC"
  echo "  sudo systemctl status $SVC -l --no-pager | sed -n '1,140p'"
  echo "  sudo journalctl -u $SVC -n 220 --no-pager"
fi

info "== [3] smoke redirect (best-effort) =="
for pth in /c /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE$pth" || true)"
  echo "$pth => $code"
done

ok "DONE (SAFE). Ctrl+F5 once if UI up."
exit 0
