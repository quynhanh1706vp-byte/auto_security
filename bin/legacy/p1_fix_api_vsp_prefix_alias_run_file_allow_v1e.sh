#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_apivspalias_${TS}"
echo "[BACKUP] ${APP}.bak_apivspalias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_API_VSP_PREFIX_ALIAS_V1E"
if MARK in s:
    print("[SKIP] already installed")
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_API_VSP_PREFIX_ALIAS_V1E =====================
# Alias endpoints that some legacy JS still calls with /api/vsp/ prefix.

@app.get("/api/vsp/run_file_allow")
def vsp_api_vsp_run_file_allow_alias():
    # reuse existing handler if present; else proxy via internal call to query param logic
    try:
        return api_vsp_run_file_allow()
    except Exception:
        # fallback: call the real endpoint via requests would be overkill; return same-style JSON error
        return {"ok": False, "err": "alias failed: api_vsp_run_file_allow not found"}, 404

@app.get("/api/vsp/run_file")
def vsp_api_vsp_run_file_alias():
    try:
        return api_vsp_run_file()
    except Exception:
        return {"ok": False, "err": "alias failed: api_vsp_run_file not found"}, 404
# ===================== /VSP_P1_API_VSP_PREFIX_ALIAS_V1E =====================
""").strip() + "\n"

m = re.search(r'\nif\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if m:
    s2 = s[:m.start()] + "\n\n" + block + "\n\n" + s[m.start():]
else:
    s2 = s + "\n\n" + block + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] inserted /api/vsp/* alias block")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile passed"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] restarted $SVC"
