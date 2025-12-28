#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need grep
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_BOOT_CONTEXT_GUARDS_V1"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_bootguard_${TS}"
echo "[BACKUP] ${F}.bak_bootguard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

MARK = "VSP_P2_BOOT_CONTEXT_GUARDS_V1"
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

# 1) Insert helpers near top (after imports if possible)
helpers = textwrap.dedent("""
# ===================== VSP_P2_BOOT_CONTEXT_GUARDS_V1 =====================
try:
    from flask import has_request_context as __vsp_hrc, has_app_context as __vsp_hac
except Exception:
    def __vsp_hrc(): return False
    def __vsp_hac(): return False

def __vsp_req_args(key, default=""):
    \"\"\"Safe request.args.get usable even at import-time.\"\"\"
    try:
        if not __vsp_hrc():
            return default
        from flask import request
        return request.args.get(key, default)
    except Exception:
        return default

def __vsp_req_path(default=""):
    try:
        if not __vsp_hrc():
            return default
        from flask import request
        return request.path or default
    except Exception:
        return default

def __vsp_req_method(default="GET"):
    try:
        if not __vsp_hrc():
            return default
        from flask import request
        return request.method or default
    except Exception:
        return default

# define app_obj defensively (fixes: name 'app_obj' is not defined)
try:
    app_obj = app
except Exception:
    try:
        app_obj = application
    except Exception:
        app_obj = None
# ===================== /VSP_P2_BOOT_CONTEXT_GUARDS_V1 =====================
""").strip("\n")

# put helpers after import block if found
m = re.search(r'(?ms)\A((?:\s*(?:from\s+\S+\s+import\s+.*|import\s+\S+).*\n)+)', s)
if m:
    ins = m.end(1)
    s = s[:ins] + "\n" + helpers + "\n\n" + s[ins:]
else:
    s = helpers + "\n\n" + s

# 2) Replace dangerous patterns that cause "working outside request context" at import-time
#    (a) "if request" -> "if __vsp_hrc()"
s = re.sub(r'(\n\s*)if\s+request\s*:', r'\1if __vsp_hrc():', s)

#    (b) "request.args.get(" -> "__vsp_req_args("
s = re.sub(r'\brequest\.args\.get\s*\(', '__vsp_req_args(', s)

#    (c) "request.path" and "request.method" used outside handlers -> use safe wrappers
s = re.sub(r'\brequest\.path\b', '__vsp_req_path("")', s)
s = re.sub(r'\brequest\.method\b', '__vsp_req_method("GET")', s)

p.write_text(s, encoding="utf-8")
print("[OK] boot guards patched:", MARK)
PY

echo "== [1] py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== [2] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || {
    echo "[ERR] restart failed; status:"
    systemctl --no-pager --full status "$SVC" | sed -n '1,120p' || true
    echo "---- journal tail ----"
    journalctl -u "$SVC" -n 220 --no-pager | tail -n 140 || true
    exit 2
  }
  systemctl --no-pager --full status "$SVC" | sed -n '1,60p' || true
fi

echo "== [3] verify port =="
curl -fsS "$BASE/vsp5" | head -n 3 >/dev/null && echo "[OK] /vsp5 reachable" || echo "[WARN] /vsp5 not reachable yet"

echo "== [4] verify ui apis =="
curl -s -o /dev/null -w "settings_v2=%{http_code}\n" "$BASE/api/ui/settings_v2" || true
curl -s -o /dev/null -w "rule_overrides_v2=%{http_code}\n" "$BASE/api/ui/rule_overrides_v2" || true

echo "[DONE] If still boot-fail, paste: journalctl -u $SVC -n 80 --no-pager"
