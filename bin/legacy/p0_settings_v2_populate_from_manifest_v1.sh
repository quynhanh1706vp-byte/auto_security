#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_p0_settingsv2_${TS}"
echo "[BACKUP] ${WSGI}.bak_p0_settingsv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_SETTINGS_V2_FROM_TOOLS_MANIFEST_WSGI_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r"""
# ===================== VSP_P0_SETTINGS_V2_FROM_TOOLS_MANIFEST_WSGI_V1 =====================
# Serve /api/ui/settings_v2 from SECURITY_BUNDLE/config/tools_manifest.json (fallback-safe).
# Works even when 'application' is not a Flask app (pure WSGI wrapper).
import os, json, time

_VSP_SB_ROOT = os.environ.get("VSP_SB_ROOT", "/home/test/Data/SECURITY_BUNDLE")
_VSP_TOOLS_MANIFEST = os.environ.get("VSP_TOOLS_MANIFEST", os.path.join(_VSP_SB_ROOT, "config", "tools_manifest.json"))

_VSP_TOOL_IDS = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"]

def _vsp_p0_load_tools_manifest():
    try:
        with open(_VSP_TOOLS_MANIFEST, "r", encoding="utf-8") as f:
            j = json.load(f)
        return j, None
    except Exception as e:
        return None, repr(e)

def _vsp_p0_norm_tools(j):
    # Accept many shapes:
    # - {"tools": {...}}  where keys are tool ids
    # - {"tools": [ {...}, ... ]} list with "id"/"name"
    # - {"BANDIT": {...}, ...}
    out = {}
    if not j:
        return out

    candidate = None
    if isinstance(j, dict) and "tools" in j:
        candidate = j.get("tools")
    else:
        candidate = j

    if isinstance(candidate, dict):
        for tid in _VSP_TOOL_IDS:
            v = candidate.get(tid) or candidate.get(tid.lower())
            if isinstance(v, dict):
                out[tid] = v
    elif isinstance(candidate, list):
        for it in candidate:
            if not isinstance(it, dict):
                continue
            tid = (it.get("id") or it.get("tool") or it.get("name") or "").strip()
            if not tid:
                continue
            tidu = tid.upper()
            if tidu in _VSP_TOOL_IDS:
                out[tidu] = it

    # ensure all tools exist (fallback defaults)
    for tid in _VSP_TOOL_IDS:
        if tid not in out:
            out[tid] = {}
    return out

def _vsp_p0_build_settings_payload():
    j, err = _vsp_p0_load_tools_manifest()
    tools_raw = _vsp_p0_norm_tools(j)
    tools = {}
    for tid, cfg in tools_raw.items():
        # heuristics for enabled/timeout/degrade:
        enabled = cfg.get("enabled")
        if enabled is None:
            enabled = cfg.get("on")
        if enabled is None:
            enabled = True

        timeout = cfg.get("timeout_sec") or cfg.get("timeout") or cfg.get("timeout_seconds")
        try:
            timeout = int(timeout) if timeout is not None else None
        except Exception:
            timeout = None

        degrade = cfg.get("degrade_on_fail")
        if degrade is None:
            degrade = cfg.get("degrade") or cfg.get("allow_fail")
        if degrade is None:
            degrade = True

        tools[tid] = {
            "enabled": bool(enabled),
            "timeout_sec": timeout,
            "degrade_on_fail": bool(degrade),
            "notes": cfg.get("notes") or cfg.get("desc") or "",
        }

    ui = {
        "severity_levels": ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"],
        "kpi_mode": "degraded" if os.environ.get("VSP_SAFE_DISABLE_KPI_V4","") == "1" else "normal",
        "build_ts": int(time.time()),
    }

    payload = {
        "ok": True,
        "source": "tools_manifest.json" if j is not None else "fallback",
        "tools": tools,
        "ui": ui,
        "notes": ("wsgi-mw; manifest_err=" + err) if err else "wsgi-mw",
        "__via__": "VSP_P0_SETTINGS_V2_FROM_TOOLS_MANIFEST_WSGI_V1",
    }
    return payload

def _vsp_p0_json_bytes(obj):
    b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    return b

def _vsp_p0_wrap_settings_v2_wsgi(app_callable):
    def _wsgi(environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            if path == "/api/ui/settings_v2":
                body = _vsp_p0_json_bytes(_vsp_p0_build_settings_payload())
                hdrs = [
                    ("Content-Type", "application/json; charset=utf-8"),
                    ("Cache-Control", "no-store"),
                    ("Content-Length", str(len(body))),
                ]
                start_response("200 OK", hdrs)
                return [body]
        except Exception:
            pass
        return app_callable(environ, start_response)
    return _wsgi

# Install wrapper around WSGI application/app if present
try:
    if "application" in globals() and callable(globals().get("application")):
        application = _vsp_p0_wrap_settings_v2_wsgi(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _vsp_p0_wrap_settings_v2_wsgi(app)
except Exception as _e:
    pass
# ===================== /VSP_P0_SETTINGS_V2_FROM_TOOLS_MANIFEST_WSGI_V1 =====================
"""

p.write_text(s + "\n\n" + textwrap.dedent(block).strip() + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo
echo "== RESTART =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
fi

echo
echo "== VERIFY settings_v2 now has tools =="
curl -fsS "$BASE/api/ui/settings_v2" | head -c 900; echo
