#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed
command -v node >/dev/null 2>&1 && node_ok=1 || node_ok=0
command -v systemctl >/dev/null 2>&1 && svc_ok=1 || svc_ok=0

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] backup templates =="
mkdir -p /tmp/vsp_fix_tabs3_${TS}
cp -a templates /tmp/vsp_fix_tabs3_${TS}/templates.bak 2>/dev/null || true

echo "== [1] fix %22 in script src/href inside templates (data_source + rule_overrides + settings) =="
python3 - <<'PY'
from pathlib import Path
import re

tpl_dir = Path("templates")
targets = []
for pat in ("vsp_data_source*.html", "vsp_rule_overrides*.html", "vsp_settings*.html"):
    targets += list(tpl_dir.glob(pat))

if not targets:
    print("[WARN] no templates matched")
    raise SystemExit(0)

changed = 0
for p in targets:
    s = p.read_text(encoding="utf-8", errors="replace")
    s0 = s

    # remove literal %22 in URLs
    s = s.replace("/%22/static/js/", "/static/js/")
    s = s.replace("%22/static/js/", "/static/js/")

    # fix common bad patterns: src="%22/static/js/..." or src="\"/static/js/..."
    s = re.sub(r'src\s*=\s*"(%22|\\")\s*/static/js/', 'src="/static/js/', s)
    s = re.sub(r'href\s*=\s*"(%22|\\")\s*/static/', 'href="/static/', s)

    if s != s0:
        p.write_text(s, encoding="utf-8")
        changed += 1
        print("[OK] patched:", p)

print("[DONE] templates patched:", changed)
PY

echo "== [2] make dashboard preview fetch safe (avoid 404 spam when rid missing / url incomplete) =="
# Try to locate the dashboard preview JS used on non-dashboard tabs
JS_CAND="$(ls -1 static/js/vsp_dashboard_luxe*.js 2>/dev/null | head -n1 || true)"
if [ -z "${JS_CAND:-}" ]; then
  JS_CAND="$(ls -1 static/js/vsp_dashboard_*luxe*.js 2>/dev/null | head -n1 || true)"
fi

if [ -n "${JS_CAND:-}" ] && [ -f "$JS_CAND" ]; then
  cp -f "$JS_CAND" "${JS_CAND}.bak_${TS}"
  echo "[BACKUP] $JS_CAND.bak_${TS}"

  python3 - <<PY
from pathlib import Path
import re

p = Path("$JS_CAND")
s = p.read_text(encoding="utf-8", errors="replace")
s0 = s

# (a) if code has fetch('/api/vsp/run_file_allow?rid='+rid) without path => add safe default path
def add_path(m):
    chunk = m.group(0)
    if "&path=" in chunk:
        return chunk
    # append + '&path=run_gate_summary.json'
    return chunk + " + '&path=run_gate_summary.json'"

s = re.sub(r"('/api/vsp/run_file_allow\\?rid='\\s*\\+\\s*rid)", add_path, s)

# (b) guard: if rid falsy -> do not fetch
# Insert a minimal guard near first occurrence of 'rid' resolution patterns
if "if (!rid)" not in s:
    s = re.sub(
        r"(const\\s+rid\\s*=\\s*[^;]+;)",
        r"\\1\\n  if (!rid) { console.debug('[VSP] preview: no rid, skip fetch'); return; }",
        s,
        count=1
    )

if s != s0:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched preview JS:", p)
else:
    print("[WARN] preview JS unchanged (pattern not found)")

PY

  if [ "$node_ok" = "1" ]; then
    node --check "$JS_CAND" >/dev/null && echo "[OK] node --check passed: $JS_CAND"
  fi
else
  echo "[WARN] no vsp_dashboard_luxe*.js found; skip preview JS patch"
fi

echo "== [3] restart service (best effort) =="
if [ "$svc_ok" = "1" ]; then
  systemctl restart "$SVC" || true
fi

echo "== [4] smoke: ensure /data_source HTML does NOT contain %22/static/js =="
curl -fsS "$BASE/data_source" | grep -nE '%22/static/js|/%22/static/js' && { echo "[ERR] still has %22"; exit 2; } || true
echo "[OK] no %22/static/js in /data_source HTML"

echo "== [5] smoke: check JS served as javascript =="
# pick the data source JS file you wrote earlier
DS_JS="/static/js/vsp_data_source_lazy_v1.js"
curl -fsS -I "$BASE$DS_JS" | sed -n '1,12p' || true

echo "[DONE] Now reload /data_source and /rule_overrides with Ctrl+F5."
