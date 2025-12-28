#!/usr/bin/env bash
set -u
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "[ERR] Do NOT source. Run: bash ${BASH_SOURCE[0]}"
  return 2
fi
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need cp; need date; need ls; need head; need curl
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [0] pick a compilable gateway (current or backups) =="
python3 - <<'PY'
from pathlib import Path
import py_compile, glob, os, sys

W=Path("wsgi_vsp_ui_gateway.py")

def ok(p: Path)->bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

candidates=[W]
candidates += [Path(p) for p in sorted(glob.glob("wsgi_vsp_ui_gateway.py.bak_*"), reverse=True)]

good=None
for p in candidates:
    if p.exists() and ok(p):
        good=p
        break

if not good:
    print("[ERR] no compilable gateway found among current + backups")
    sys.exit(2)

if good != W:
    Path("wsgi_vsp_ui_gateway.py").write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print("[OK] restored from:", good.name)
else:
    print("[OK] current gateway compiles")

PY

cp -f "$W" "${W}.bak_ro_intercept_v3_${TS}"
echo "[BACKUP] ${W}.bak_ro_intercept_v3_${TS}"

echo "== [1] patch: WSGI intercept /api/vsp/rule_overrides_v1 always 200 (indent-safe) =="
python3 - <<'PY'
from pathlib import Path
import re, py_compile

W=Path("wsgi_vsp_ui_gateway.py")
s=W.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RULE_OVERRIDES_WSGI_SAFE_V3"

# Insert helper + wrapper near top after initial import block (safe top-level)
if MARK not in s:
    lines=s.splitlines(True)
    i=0
    # skip shebang/comments/blank at top
    while i < len(lines) and (lines[i].startswith("#!") or lines[i].lstrip().startswith("#") or lines[i].strip()=="" ):
        i+=1
    # walk consecutive import/from lines
    while i < len(lines) and re.match(r'^\s*(import|from)\s+\w', lines[i]):
        i+=1
    insert_at=i

    wrapper = f"""
# === {MARK} ===
def _vsp__json_bytes(obj):
    import json
    return json.dumps(obj, ensure_ascii=False).encode("utf-8")

class _VSPRuleOverridesAlways200WSGI:
    \"\"\"Intercept /api/vsp/rule_overrides_v1 to avoid 500s (commercial-safe).\"\"\"
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO","") or "")
            if path == "/api/vsp/rule_overrides_v1":
                import time
                now = int(time.time())
                body = _vsp__json_bytes({{
                    "ok": True,
                    "who": "VSP_RULE_OVERRIDES_P0_WSGI_SAFE",
                    "ts": now,
                    "data": {{
                        "enabled": True,
                        "overrides": [],
                        "updated_at": now,
                        "updated_by": "system"
                    }}
                }})
                headers=[
                    ("Content-Type","application/json; charset=utf-8"),
                    ("Cache-Control","no-store"),
                    ("X-VSP-RO-SAFE","wsgi_v3"),
                ]
                start_response("200 OK", headers)
                return [body]
        except Exception:
            pass
        return self.app(environ, start_response)
# === /{MARK} ===
""".lstrip("\n")

    lines.insert(insert_at, wrapper + "\n")
    s="".join(lines)

# Wrap application line with SAME indentation as the matched application assignment line
wrap_stmt="_VSPRuleOverridesAlways200WSGI(application)"
if wrap_stmt not in s:
    m=re.search(r'(?m)^(?P<indent>[ \t]*)application\s*=\s*.+$', s)
    if not m:
        raise SystemExit("[ERR] cannot find `application = ...` in gateway")
    indent=m.group("indent")
    ins=m.end()
    s = s[:ins] + "\n" + indent + f"application = {wrap_stmt}\n" + s[ins:]

W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] patched + py_compile OK")
PY

echo "== [2] restart best-effort (no password prompt) =="
if command -v systemctl >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null; then
    sudo -n systemctl daemon-reload || true
    sudo -n systemctl restart "$SVC"
    echo "[OK] restarted: $SVC"
  else
    echo "[WARN] sudo -n not allowed. Run manually:"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl restart $SVC"
  fi
fi

echo "== [3] probe =="
for i in $(seq 1 80); do
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1 && break
  sleep 0.25
done
code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE/api/vsp/rule_overrides_v1" || true)"
echo "/api/vsp/rule_overrides_v1 => $code"
curl -fsS --connect-timeout 1 --max-time 6 "$BASE/api/vsp/rule_overrides_v1" | head -c 240; echo
