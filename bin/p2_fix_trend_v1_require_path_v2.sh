#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

echo "== [0] Locate trend_v1 python route =="
PYFILES="$(grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' --exclude-dir=.venv --exclude-dir=out --exclude-dir=out_ci \
  '/api/vsp/trend_v1' . | grep -E '\.py$' || true)"
echo "$PYFILES" | sed 's/^/[PY] /' || true

echo "== [1] Patch JS callers to always include path=run_gate_summary.json =="
JSFILES="$(grep -RIl --exclude='*.bak_*' --exclude='*.disabled_*' --exclude-dir=.venv --exclude-dir=out --exclude-dir=out_ci \
  '/api/vsp/trend_v1' static my_flask_app 2>/dev/null | grep -E '\.js$' || true)"

if [ -z "${JSFILES:-}" ]; then
  warn "No JS files reference /api/vsp/trend_v1 (maybe already migrated)."
else
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    cp -f "$f" "${f}.bak_trendpath_${TS}"
    python3 - "$f" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

# Skip if already has path= in the trend url
# We'll only rewrite occurrences that don't already include 'path=' nearby.
# 1) "/api/vsp/trend_v1"   -> "/api/vsp/trend_v1?path=run_gate_summary.json"
# 2) "/api/vsp/trend_v1?X" -> "/api/vsp/trend_v1?path=run_gate_summary.json&X"
def repl(m):
    url=m.group(0)
    if "path=" in url:
        return url
    if url.endswith("/api/vsp/trend_v1?"):
        return "/api/vsp/trend_v1?path=run_gate_summary.json&"
    if url.endswith("/api/vsp/trend_v1"):
        return "/api/vsp/trend_v1?path=run_gate_summary.json"
    # "/api/vsp/trend_v1?<something>"
    if "/api/vsp/trend_v1?" in url:
        return url.replace("/api/vsp/trend_v1?","/api/vsp/trend_v1?path=run_gate_summary.json&",1)
    return url

# match both single/double quote contexts by just matching the path substring region
pattern=re.compile(r'/api/vsp/trend_v1\?(?![^"\']*path=)|/api/vsp/trend_v1(?!\?)')
s2=pattern.sub(lambda m: repl(m), s)

changed = (s2 != s)
if changed:
    s2 = "/* VSP_P2_TREND_PATH_FORCE_V2 */\n" + s2 if "VSP_P2_TREND_PATH_FORCE_V2" not in s2 else s2
    p.write_text(s2, encoding="utf-8")
print("changed=", changed, "file=", str(p))
PY
    ok "patched: $f (backup: ${f}.bak_trendpath_${TS})"
  done <<<"$JSFILES"
fi

echo "== [2] Patch python: default path if missing (best-effort) =="
if [ -n "${PYFILES:-}" ]; then
  while IFS= read -r py; do
    [ -f "$py" ] || continue
    cp -f "$py" "${py}.bak_trendpath_${TS}"
    python3 - "$py" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P2_TREND_DEFAULT_PATH_V2" in s:
    print("skip(already):", p)
    raise SystemExit(0)

# Try to replace common patterns:
# path = request.args.get("path", "")
# path = request.args.get('path') or ''
# -> path = (request.args.get("path") or request.args.get("rel") or "run_gate_summary.json")
pat = re.compile(
    r'(?m)^(?P<i>\s*)path\s*=\s*request\.args\.get\(\s*[\'"]path[\'"]\s*(?:,\s*[^)]*)?\)\s*(?:or\s*[^#\n]+)?\s*$'
)

def sub(m):
    i=m.group("i")
    return (
        f'{i}# VSP_P2_TREND_DEFAULT_PATH_V2\n'
        f'{i}path = (request.args.get("path") or request.args.get("rel") or "run_gate_summary.json")'
    )

s2, n = pat.subn(sub, s, count=1)

# If we couldn't find a 'path = request.args.get("path"...' line, do nothing.
if n == 0:
    print("no-match:", p)
else:
    p.write_text(s2, encoding="utf-8")
    print("patched:", p)
PY
  done <<<"$PYFILES"
else
  warn "No python file found with '/api/vsp/trend_v1' route."
fi

echo "== [3] Restart service (if you have sudo rights) =="
echo "[CMD] sudo systemctl restart ${SVC}"

echo "== [4] Smoke after restart: trend_v1 MUST be ok/usable now =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"
echo "[SMOKE] curl '$BASE/api/vsp/trend_v1?rid=$RID&limit=5&path=run_gate_summary.json'"
curl -sS "$BASE/api/vsp/trend_v1?rid=$RID&limit=5&path=run_gate_summary.json" | head -c 400; echo
