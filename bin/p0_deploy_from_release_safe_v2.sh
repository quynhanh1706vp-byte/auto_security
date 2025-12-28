#!/usr/bin/env bash
# Deploy VSP UI from a release tgz safely (backup + compile + optional sudo restart + smoke + rollback)
# Usage:
#   RID=VSP_CI_... bash bin/p0_deploy_from_release_safe_v2.sh /path/to/VSP_UI_COMMERCIAL_xxx.tgz
set -u
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "[ERR] Do NOT source this script."
  echo "Run: bash ${BASH_SOURCE[0]} /path/to/release.tgz"
  return 2
fi
set -euo pipefail

REL_TGZ="${1:-}"
[ -n "$REL_TGZ" ] || { echo "[ERR] missing release tgz path"; exit 2; }
[ -f "$REL_TGZ" ] || { echo "[ERR] not found: $REL_TGZ"; exit 2; }

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
OUT="$ROOT/out_ci"
TS="$(date +%Y%m%d_%H%M%S)"

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need tar; need cp; need mkdir; need date; need python3; need curl; need grep; need head
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl"; exit 2; }
command -v sudo >/dev/null 2>&1 || true

STAGE="$OUT/DEPLOY_STAGE_${TS}"
BKP="$OUT/DEPLOY_BACKUP_${TS}"
PENDING="$OUT/DEPLOY_PENDING_RESTART_${TS}.txt"

mkdir -p "$STAGE" "$BKP"

echo "[INFO] REL_TGZ=$REL_TGZ"
echo "[INFO] BASE=$BASE SVC=$SVC RID=$RID"
echo "== [0] locate payload paths inside tgz =="

pick_in_tgz(){
  local pat="$1"
  tar -tzf "$REL_TGZ" | grep -E "$pat" | head -n 1 || true
}

P_W="$(pick_in_tgz '/code/wsgi_vsp_ui_gateway\.py$')"
P_A="$(pick_in_tgz '/code/vsp_demo_app\.py$')"
P_J="$(pick_in_tgz '/code/vsp_fill_real_data_5tabs_p1_v1\.js$')"

[ -n "$P_W" ] || { echo "[ERR] cannot find wsgi_vsp_ui_gateway.py in tgz"; exit 2; }
[ -n "$P_A" ] || { echo "[ERR] cannot find vsp_demo_app.py in tgz"; exit 2; }
[ -n "$P_J" ] || { echo "[ERR] cannot find vsp_fill_real_data_5tabs_p1_v1.js in tgz"; exit 2; }

echo "[OK] wsgi: $P_W"
echo "[OK] app : $P_A"
echo "[OK] js  : $P_J"

echo "== [1] extract to stage =="
tar -xzf "$REL_TGZ" -C "$STAGE" "$P_W" "$P_A" "$P_J"

W_NEW="$STAGE/$P_W"
A_NEW="$STAGE/$P_A"
J_NEW="$STAGE/$P_J"

[ -f "$W_NEW" ] || { echo "[ERR] stage missing wsgi"; exit 2; }
[ -f "$A_NEW" ] || { echo "[ERR] stage missing app"; exit 2; }
[ -f "$J_NEW" ] || { echo "[ERR] stage missing js"; exit 2; }

echo "== [2] backup current working files =="
cp -f "$ROOT/wsgi_vsp_ui_gateway.py" "$BKP/" || true
cp -f "$ROOT/vsp_demo_app.py" "$BKP/" || true
cp -f "$ROOT/static/js/vsp_fill_real_data_5tabs_p1_v1.js" "$BKP/" || true
echo "[OK] backup dir: $BKP"

restore(){
  echo "[RESTORE] rollback from $BKP"
  [ -f "$BKP/wsgi_vsp_ui_gateway.py" ] && cp -f "$BKP/wsgi_vsp_ui_gateway.py" "$ROOT/wsgi_vsp_ui_gateway.py" || true
  [ -f "$BKP/vsp_demo_app.py" ] && cp -f "$BKP/vsp_demo_app.py" "$ROOT/vsp_demo_app.py" || true
  [ -f "$BKP/vsp_fill_real_data_5tabs_p1_v1.js" ] && cp -f "$BKP/vsp_fill_real_data_5tabs_p1_v1.js" "$ROOT/static/js/vsp_fill_real_data_5tabs_p1_v1.js" || true
}

echo "== [3] sanitize gateway (avoid tail @app.* after application=) =="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("out_ci") / Path("DEPLOY_STAGE_PLACEHOLDER")
PY
# Replace placeholder via env-free trick:
python3 - <<PY
from pathlib import Path
import re, sys

w_new = Path(r"$W_NEW")
s = w_new.read_text(encoding="utf-8", errors="replace").splitlines(True)

# Find last "application =" assignment
app_idx = -1
for i,line in enumerate(s):
    if re.match(r'^\s*application\s*=\s*', line):
        app_idx = i

changed = 0
if app_idx != -1:
    for i in range(app_idx+1, len(s)):
        if re.match(r'^\s*@\s*app\.', s[i]) or re.match(r'^\s*@\s*application\.', s[i]):
            if not s[i].lstrip().startswith("#"):
                s[i] = "# DISABLED_BY_DEPLOY_V2 " + s[i]
                changed += 1

marker = "VSP_CSUITE_WSGI_REDIRECT_DEPLOY_V2"
txt = "".join(s)
if marker not in txt:
    block = r'''
# {marker}
def _vsp_csuite_redirect_app(_app):
    def _w(environ, start_response):
        try:
            p = environ.get("PATH_INFO","") or ""
            if p == "/c": p = "/c/"
            if p.startswith("/c/"):
                m = {{
                    "/c/": "/vsp5",
                    "/c/dashboard": "/vsp5",
                    "/c/runs": "/runs",
                    "/c/data_source": "/data_source",
                    "/c/settings": "/settings",
                    "/c/rule_overrides": "/rule_overrides",
                }}
                target = m.get(p, "/vsp5")
                qs = environ.get("QUERY_STRING","") or ""
                loc = target + (("?" + qs) if qs else "")
                start_response("302 Found", [
                    ("Location", loc),
                    ("Cache-Control","no-store"),
                    ("X-VSP-CSUITE-REDIRECT","deploy_v2"),
                ])
                return [b""]
        except Exception:
            pass
        return _app(environ, start_response)
    return _w

try:
    application = _vsp_csuite_redirect_app(application)
except Exception:
    pass
'''.replace("{marker}", marker)

    s.append("\n")
    s.append(block)
    txt2 = "".join(s)
    w_new.write_text(txt2, encoding="utf-8")
else:
    w_new.write_text(txt, encoding="utf-8")

print("[OK] sanitized gateway: disabled_tail_decorators=", changed, "marker_added=", (marker in ("".join(s))))
PY

echo "== [4] install release files =="
cp -f "$W_NEW" "$ROOT/wsgi_vsp_ui_gateway.py"
cp -f "$A_NEW" "$ROOT/vsp_demo_app.py"
cp -f "$J_NEW" "$ROOT/static/js/vsp_fill_real_data_5tabs_p1_v1.js"

echo "== [5] compile/syntax check (fail => restore) =="
python3 -m py_compile "$ROOT/wsgi_vsp_ui_gateway.py" "$ROOT/vsp_demo_app.py" || { echo "[ERR] py_compile failed"; restore; exit 3; }
if command -v node >/dev/null 2>&1; then
  node --check "$ROOT/static/js/vsp_fill_real_data_5tabs_p1_v1.js" || { echo "[ERR] node --check failed"; restore; exit 3; }
fi
echo "[OK] compile check OK"

restart_with_sudo(){
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo -n systemctl daemon-reload || true
    sudo -n systemctl restart "$SVC"
    return 0
  fi
  return 1
}

echo "== [6] restart service (sudo -n if possible) =="
if restart_with_sudo; then
  echo "[OK] restarted: $SVC"
else
  echo "[WARN] cannot restart without sudo. No rollback performed."
  echo "Please run:"
  echo "  sudo systemctl daemon-reload"
  echo "  sudo systemctl restart $SVC"
  echo "Then smoke:"
  echo "  RID=$RID bash $ROOT/bin/p0_go_live_smoke_v1.sh"
  {
    echo "PENDING_RESTART ts=$TS"
    echo "svc=$SVC"
    echo "base=$BASE"
    echo "rid=$RID"
    echo "release=$REL_TGZ"
  } > "$PENDING"
  echo "[OK] wrote pending file: $PENDING"
  exit 0
fi

echo "== [7] wait port + smoke (fail => restore + restart) =="
for i in $(seq 1 120); do
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1 && break
  sleep 0.25
  [ "$i" -eq 120 ] && { echo "[ERR] UI not reachable after restart"; restore; restart_with_sudo || true; exit 4; }
done

code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE/api/vsp/runs?limit=1&offset=0" || true)"
[ "$code" = "200" ] || { echo "[ERR] API runs not OK: $code"; restore; restart_with_sudo || true; exit 4; }

echo "[OK] DEPLOY SUCCESS ✅"
echo "[INFO] backup kept at: $BKP"
