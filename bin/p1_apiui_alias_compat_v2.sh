#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need ls; need head

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

# 0) nếu file đang lỗi syntax -> restore từ backup gần nhất (ưu tiên các bản “đang chạy OK”)
if ! python3 -m py_compile "$W" >/dev/null 2>&1; then
  echo "[WARN] $W currently has SyntaxError -> trying restore from backups..."
  BAK="$(ls -1t ${W}.bak_fix_postwrap_* 2>/dev/null | head -n1 || true)"
  [ -z "$BAK" ] && BAK="$(ls -1t ${W}.bak_apiui_shim_* 2>/dev/null | head -n1 || true)"
  [ -z "$BAK" ] && BAK="$(ls -1t ${W}.bak_tabs3_bundle_fix1_* 2>/dev/null | head -n1 || true)"
  [ -z "$BAK" ] && BAK="$(ls -1t ${W}.bak_tabs3_bundle_* 2>/dev/null | head -n1 || true)"
  [ -z "$BAK" ] && BAK="$(ls -1t ${W}.bak_* 2>/dev/null | head -n1 || true)"
  [ -n "$BAK" ] || { echo "[ERR] no backup found to restore"; exit 2; }
  echo "[RESTORE] $BAK -> $W"
  cp -f "$BAK" "$W"
fi

cp -f "$W" "${W}.bak_apiui_alias_v2_${TS}"
echo "[BACKUP] ${W}.bak_apiui_alias_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_APIUI_ALIAS_COMPAT_P1_V2"
if marker in s:
    print("[OK] alias compat already present")
else:
    block = f"""

# --- {marker} ---
# Legacy endpoint compat for older JS/bundles calling /api/ui/runs (no _v2), etc.
try:
    __vsp_apiui_alias_prev = app.wsgi_app  # type: ignore[name-defined]
    def __vsp_apiui_alias_wrap(environ, start_response):
        try:
            path = (environ or {{}}).get("PATH_INFO", "") or ""
            alias = {{
                "/api/ui/runs": "/api/ui/runs_v2",
                "/api/ui/findings": "/api/ui/findings_v2",
                "/api/ui/settings": "/api/ui/settings_v2",
                "/api/ui/rule_overrides": "/api/ui/rule_overrides_v2",
                "/api/ui/rule_overrides_apply": "/api/ui/rule_overrides_apply_v2",
            }}
            if path in alias:
                environ["PATH_INFO"] = alias[path]
        except Exception:
            pass
        return __vsp_apiui_alias_prev(environ, start_response)
    app.wsgi_app = __vsp_apiui_alias_wrap  # type: ignore[name-defined]
except Exception:
    pass
# --- /{marker} ---

"""
    p.write_text(s + block, encoding="utf-8")
    print("[OK] appended alias compat wrapper")
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || true
fi
sudo -n systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true

echo "== verify legacy + v2 endpoints =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
for u in \
  "$BASE/api/ui/runs?limit=1" \
  "$BASE/api/ui/runs_v2?limit=1" \
  "$BASE/api/ui/findings?limit=1&offset=0" \
  "$BASE/api/ui/findings_v2?limit=1&offset=0" \
  "$BASE/api/ui/settings" \
  "$BASE/api/ui/settings_v2" \
  "$BASE/api/ui/rule_overrides" \
  "$BASE/api/ui/rule_overrides_v2"
do
  echo "--- $u"
  curl -fsS "$u" | head -c 220; echo
done

echo "[DONE] alias compat v2 installed"
