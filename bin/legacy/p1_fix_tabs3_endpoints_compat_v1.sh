#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

# backups
cp -f "$W" "${W}.bak_tabs3_ep_${TS}"
for f in static/js/vsp_tabs3_common_v3.js static/js/vsp_settings_tab_v3.js static/js/vsp_rule_overrides_tab_v3.js; do
  [ -f "$f" ] && cp -f "$f" "${f}.bak_ep_${TS}" || true
done
echo "[BACKUP] done"

python3 - <<'PY'
from pathlib import Path
import re, time

def patch_js(p: Path):
    if not p.exists(): return
    s = p.read_text(encoding="utf-8", errors="replace")

    # Only upgrade legacy endpoints (avoid double _v2)
    rep = [
      (r"/api/ui/runs(?!_v2)", "/api/ui/runs_v2"),
      (r"/api/ui/findings(?!_v2)", "/api/ui/findings_v2"),
      (r"/api/ui/settings(?!_v2)", "/api/ui/settings_v2"),
      (r"/api/ui/rule_overrides(?!_v2)", "/api/ui/rule_overrides_v2"),
      (r"/api/ui/settings_save(?!_v2)", "/api/ui/settings_save_v2"),
      (r"/api/ui/rule_overrides_save(?!_v2)", "/api/ui/rule_overrides_save_v2"),
      (r"/api/ui/rules_apply(?!_v2)", "/api/ui/rules_apply_v2"),
    ]
    n_total = 0
    for pat, to in rep:
        s2, n = re.subn(pat, to, s)
        if n:
            s = s2
            n_total += n
    if n_total:
        p.write_text(s, encoding="utf-8")
        print(f"[OK] patched {p} replacements={n_total}")
    else:
        print(f"[OK] no change {p}")

for js in [
  Path("static/js/vsp_tabs3_common_v3.js"),
  Path("static/js/vsp_settings_tab_v3.js"),
  Path("static/js/vsp_rule_overrides_tab_v3.js"),
]:
    patch_js(js)

# ---- WSGI alias wrapper: /api/ui/runs -> /api/ui/runs_v2 (and friends) ----
W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")
marker = "VSP_APIUI_LEGACY_ALIAS_WRAPPER_P1_V1"
if marker in s:
    print("[OK] alias wrapper already present")
else:
    alias_block = r'''
# ''' + marker + r'''
try:
    import time as __time
    if not globals().get("__vsp_apiui_legacy_alias_installed", False):
        __vsp_apiui_legacy_alias_installed = True

        __VSP_APIUI_ALIAS_MAP = {
            "/api/ui/runs": "/api/ui/runs_v2",
            "/api/ui/findings": "/api/ui/findings_v2",
            "/api/ui/settings": "/api/ui/settings_v2",
            "/api/ui/rule_overrides": "/api/ui/rule_overrides_v2",
            # POST aliases (just in case)
            "/api/ui/settings_save": "/api/ui/settings_save_v2",
            "/api/ui/rule_overrides_save": "/api/ui/rule_overrides_save_v2",
            "/api/ui/rules_apply": "/api/ui/rules_apply_v2",
        }

        def __vsp_apiui_legacy_alias_wrapper(app):
            def _w(environ, start_response):
                try:
                    p = environ.get("PATH_INFO", "") or ""
                    newp = __VSP_APIUI_ALIAS_MAP.get(p)
                    if newp:
                        env2 = dict(environ)
                        env2["PATH_INFO"] = newp
                        return app(env2, start_response)
                except Exception:
                    pass
                return app(environ, start_response)
            return _w

        # gunicorn usually uses "application"
        if "application" in globals():
            application = __vsp_apiui_legacy_alias_wrapper(application)
except Exception:
    pass
# /''' + marker + r'''
'''
    s = s + "\n" + alias_block
    W.write_text(s, encoding="utf-8")
    print("[OK] appended alias wrapper into wsgi")
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart (no sudo) =="
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh || true
else
  echo "[WARN] missing bin/p1_ui_8910_single_owner_start_v2.sh (restart manually)"
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify legacy + v2 endpoints (must ok:true) =="
for u in \
  "$BASE/api/ui/runs?limit=1" \
  "$BASE/api/ui/runs_v2?limit=1" \
  "$BASE/api/ui/findings_v2?limit=1&offset=0" \
  "$BASE/api/ui/settings_v2" \
  "$BASE/api/ui/rule_overrides_v2"
do
  echo "--- $u"
  curl -fsS "$u" | head -c 160; echo
done

echo "== smoke selfcheck =="
if [ -x bin/p1_ui_5tabs_smoke_selfcheck_v2.sh ]; then
  bash bin/p1_ui_5tabs_smoke_selfcheck_v2.sh
else
  echo "[WARN] missing bin/p1_ui_5tabs_smoke_selfcheck_v2.sh"
fi

echo "[DONE] tabs3 endpoints compat applied"
