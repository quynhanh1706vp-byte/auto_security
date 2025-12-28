#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_FIX_UI_SETTINGS_RULE_OVERRIDES_500_BYTESLIKE_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_ui500_${TS}"
echo "[BACKUP] ${F}.bak_ui500_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

MARK = "VSP_P2_FIX_UI_SETTINGS_RULE_OVERRIDES_500_BYTESLIKE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    sys.exit(0)

# ---------------------------
# 0) Remove dangerous after_request injectors (if previously appended)
# ---------------------------
for bad in ("VSP_P2_AFTERREQ_VSP5_ANCHOR_V1", "VSP_P2_AFTERREQ_RUNFILEALLOW_META_V1"):
    if bad in s:
        # remove a whole marked block if exists
        s2 = re.sub(rf"(?s)(#\s*={3,}.*?{re.escape(bad)}.*?#\s*={3,}.*?/.*?{re.escape(bad)}.*?)(\n|$)", "\n", s)
        if s2 != s:
            s = s2
        # else: just drop lines containing marker as a safe fallback
        s = "\n".join([ln for ln in s.splitlines() if bad not in ln]) + "\n"

# ---------------------------
# 1) Ensure json import exists
# ---------------------------
if not re.search(r"^\s*import\s+json\s*$", s, flags=re.M):
    m = re.search(r"(?m)^\s*import\s+[^\n]+\n", s)
    if m:
        ins = m.end()
        s = s[:ins] + "import json\n" + s[ins:]
    else:
        s = "import json\n" + s

# ---------------------------
# 2) Insert safe exporter: always returns Flask Response with bytes body
#    (fixes memoryview bytes-like errors even if callers pass dict)
# ---------------------------
helper = f"""
# ===================== {MARK} =====================
def wsgi_export_v4(obj, status=200, headers=None):
    \"\"\"Safe JSON exporter: always return Flask Response with bytes body.
    Accepts dict/list/str/bytes/bytearray/memoryview/Response.
    \"\"\"
    try:
        from flask import Response
    except Exception:
        Response = None

    # If it's already a Response-like object, return as-is
    if hasattr(obj, "get_data") and hasattr(obj, "status_code"):
        return obj

    body = obj
    if isinstance(obj, (dict, list)):
        body = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    if isinstance(body, str):
        body = body.encode("utf-8")
    if not isinstance(body, (bytes, bytearray, memoryview)):
        body = str(body).encode("utf-8")

    if Response is None:
        # ultra-fallback: return bytes (WSGI might accept)
        return body

    resp = Response(body, status=status, mimetype="application/json; charset=utf-8")
    resp.headers["Cache-Control"] = "no-store"
    if headers:
        for k, v in dict(headers).items():
            resp.headers[k] = v
    return resp
# ===================== /{MARK} =====================
"""

# place helper before first @app.route
pos = s.find("@app.route")
if pos != -1:
    s = s[:pos] + helper + s[pos:]
else:
    s = s + "\n" + helper

# ---------------------------
# 3) Wrap returns inside the 2 handlers (settings_v2 / rule_overrides_v2)
#    to ensure they return Response(bytes)
# ---------------------------
def patch_handler(s: str, route: str) -> str:
    # grab block from decorator to next decorator or EOF
    pat = re.compile(rf"(?s)(@app\.route\(\s*['\"]{re.escape(route)}['\"][^\n]*\)\s*\n\s*def\s+\w+\s*\([^\)]*\)\s*:\s*\n)(.*?)(\n(?=@app\.route\()|$)")
    m = pat.search(s)
    if not m:
        return s

    head, body, tail = m.group(1), m.group(2), m.group(3)

    out = []
    for ln in body.splitlines(True):
        mret = re.match(r"^(\s*)return\s+(.+)\s*$", ln)
        if not mret:
            out.append(ln); continue
        indent, expr = mret.group(1), mret.group(2)
        # leave common safe returns untouched
        if any(x in expr for x in ("wsgi_export_v4(", "jsonify(", "Response(", "send_file(", "redirect(", "render_template(")):
            out.append(ln); continue
        out.append(f"{indent}return wsgi_export_v4({expr})\n")
    new_body = "".join(out)

    return s[:m.start()] + head + new_body + tail + s[m.end():]

s = patch_handler(s, "/api/ui/settings_v2")
s = patch_handler(s, "/api/ui/rule_overrides_v2")

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile: $F" || { echo "[ERR] py_compile failed: $F"; exit 2; }

echo "== restart service (if exists) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
fi

echo "== verify endpoints =="
curl -s -o /dev/null -w "settings_v2=%{http_code}\n" "$BASE/api/ui/settings_v2"
curl -s -o /dev/null -w "rule_overrides_v2=%{http_code}\n" "$BASE/api/ui/rule_overrides_v2"

echo "[DONE] Now hard refresh browser: Ctrl+Shift+R (Settings + Rule Overrides)."
