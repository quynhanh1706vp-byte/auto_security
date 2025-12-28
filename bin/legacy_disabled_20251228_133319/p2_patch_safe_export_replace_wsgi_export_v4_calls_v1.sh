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
MARK="VSP_P2_SAFE_EXPORT_REPLACE_V4CALLS_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_safeexport_${TS}"
echo "[BACKUP] ${F}.bak_safeexport_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")
MARK = "VSP_P2_SAFE_EXPORT_REPLACE_V4CALLS_V1"

if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

helper = textwrap.dedent(f"""
# ===================== {MARK} =====================
def _vsp_export_json_safe(payload=None, status=200, headers=None, content_type="application/json"):
    \"\"\"Return a Flask Response with bytes body. Safe for dict/list (JSON encoded).\"\"\"
    try:
        import json
        from flask import Response
        h = dict(headers or {{}})
        ct = content_type or h.get("Content-Type") or "application/json"
        h["Content-Type"] = ct

        if payload is None:
            body_b = b""
        elif isinstance(payload, (bytes, bytearray, memoryview)):
            body_b = bytes(payload)
        elif isinstance(payload, str):
            body_b = payload.encode("utf-8", errors="replace")
        else:
            body_b = json.dumps(payload, ensure_ascii=False).encode("utf-8")

        return Response(body_b, status=int(status), headers=h, mimetype=ct.split(";")[0])
    except Exception as e:
        try:
            from flask import Response
            return Response(str(e), status=500, mimetype="text/plain")
        except Exception:
            return payload
# ===================== /{MARK} =====================
""").strip("\n")

# Insert helper near top (after first block of imports if possible)
m = re.search(r'^(?:from\s+\w+.*\n|import\s+.*\n)+', s, flags=re.M)
if m:
    s = s[:m.end()] + "\n" + helper + "\n\n" + s[m.end():]
else:
    s = helper + "\n\n" + s

# Replace all calls wsgi_export_v4(...) -> _vsp_export_json_safe(...)
s2, n = re.subn(r'\bwsgi_export_v4\s*\(', '_vsp_export_json_safe(', s)
print(f"[OK] replaced calls: wsgi_export_v4 -> _vsp_export_json_safe count={n}")

p.write_text(s2)
PY

python3 -m py_compile "$F"

echo "== restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC"
fi

echo "== verify endpoints =="
curl -s -o /dev/null -w "settings_v2=%{http_code}\n" "$BASE/api/ui/settings_v2" || true
curl -s -o /dev/null -w "rule_overrides_v2=%{http_code}\n" "$BASE/api/ui/rule_overrides_v2" || true

echo "[DONE] If still 500, run journal tail below."
