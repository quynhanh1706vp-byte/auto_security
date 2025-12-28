#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need ls; need head

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

# nếu file đang lỗi syntax -> restore backup gần nhất
if ! python3 -m py_compile "$W" >/dev/null 2>&1; then
  echo "[WARN] $W has SyntaxError -> restoring from backups..."
  BAK="$(ls -1t ${W}.bak_fix_postwrap_* 2>/dev/null | head -n1 || true)"
  [ -z "$BAK" ] && BAK="$(ls -1t ${W}.bak_apiui_shim_* 2>/dev/null | head -n1 || true)"
  [ -z "$BAK" ] && BAK="$(ls -1t ${W}.bak_tabs3_bundle_fix1_* 2>/dev/null | head -n1 || true)"
  [ -z "$BAK" ] && BAK="$(ls -1t ${W}.bak_* 2>/dev/null | head -n1 || true)"
  [ -n "$BAK" ] || { echo "[ERR] no backup found to restore"; exit 2; }
  echo "[RESTORE] $BAK -> $W"
  cp -f "$BAK" "$W"
fi

cp -f "$W" "${W}.bak_apiui_legacy_redirect_${TS}"
echo "[BACKUP] ${W}.bak_apiui_legacy_redirect_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_APIUI_LEGACY_REDIRECT_P1_V1"
if marker in s:
    print("[OK] legacy redirect block already present")
else:
    block = f"""

# --- {marker} ---
# Guarantee backward-compat endpoints exist (no 404) by redirecting to *_v2 with 307 (keeps method/body).
try:
    from flask import request as __vsp_req, redirect as __vsp_redirect

    def __vsp_qs():
        try:
            q = (__vsp_req.query_string or b"").decode("utf-8", "ignore")
            return ("?" + q) if q else ""
        except Exception:
            return ""

    def __vsp_r307(path: str):
        return __vsp_redirect(path, code=307)

    # GET legacy -> v2
    @app.route("/api/ui/runs", methods=["GET"])  # type: ignore[name-defined]
    def __vsp_legacy_runs():
        return __vsp_r307("/api/ui/runs_v2" + __vsp_qs())

    @app.route("/api/ui/findings", methods=["GET"])  # type: ignore[name-defined]
    def __vsp_legacy_findings():
        return __vsp_r307("/api/ui/findings_v2" + __vsp_qs())

    @app.route("/api/ui/settings", methods=["GET"])  # type: ignore[name-defined]
    def __vsp_legacy_settings():
        return __vsp_r307("/api/ui/settings_v2" + __vsp_qs())

    @app.route("/api/ui/rule_overrides", methods=["GET"])  # type: ignore[name-defined]
    def __vsp_legacy_rule_overrides():
        return __vsp_r307("/api/ui/rule_overrides_v2" + __vsp_qs())

    # POST legacy -> v2 (giữ body)
    @app.route("/api/ui/settings_save", methods=["POST"])  # type: ignore[name-defined]
    def __vsp_legacy_settings_save():
        return __vsp_r307("/api/ui/settings_save_v2")

    @app.route("/api/ui/rule_overrides_save", methods=["POST"])  # type: ignore[name-defined]
    def __vsp_legacy_rule_overrides_save():
        return __vsp_r307("/api/ui/rule_overrides_save_v2")

    @app.route("/api/ui/rule_overrides_apply", methods=["POST"])  # type: ignore[name-defined]
    def __vsp_legacy_rule_overrides_apply():
        return __vsp_r307("/api/ui/rule_overrides_apply_v2")

except Exception:
    pass
# --- /{marker} ---

"""
    p.write_text(s + block, encoding="utf-8")
    print("[OK] appended legacy redirect routes (307)")
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || true
fi
sudo -n systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify legacy endpoints (follow redirects) =="
for u in \
  "$BASE/api/ui/runs?limit=1" \
  "$BASE/api/ui/findings?limit=1&offset=0" \
  "$BASE/api/ui/settings" \
  "$BASE/api/ui/rule_overrides"
do
  echo "--- $u"
  curl -fsSL "$u" | head -c 220; echo
done

echo "[DONE] legacy redirect routes installed"
