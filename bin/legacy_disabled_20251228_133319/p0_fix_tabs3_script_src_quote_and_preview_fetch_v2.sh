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

echo "== [0] backup templates + js =="
mkdir -p /tmp/vsp_fix_tabs3_v2_${TS}
cp -a templates /tmp/vsp_fix_tabs3_v2_${TS}/templates.bak 2>/dev/null || true
cp -a static/js /tmp/vsp_fix_tabs3_v2_${TS}/js.bak 2>/dev/null || true

echo "== [1] sweep ALL templates: remove %22 in static src/href =="
python3 - <<'PY'
from pathlib import Path
import re

tpl_dir = Path("templates")
targets = list(tpl_dir.rglob("*.html"))
changed = 0

for p in targets:
    s = p.read_text(encoding="utf-8", errors="replace")
    s0 = s

    # Fix encoded quote injected into path
    s = s.replace("/%22/static/", "/static/")
    s = s.replace("%22/static/", "/static/")

    # Fix common bad patterns
    s = re.sub(r'(src|href)\s*=\s*"(%22|\\")\s*/static/', r'\1="/static/', s)
    s = re.sub(r'(src|href)\s*=\s*"(?:%22|\\")\s*/static/js/', r'\1="/static/js/', s)

    # Also fix accidental double slashes after replacement
    s = s.replace('="/static//', '="/static/')

    if s != s0:
        p.write_text(s, encoding="utf-8")
        changed += 1
        print("[OK] patched:", p)

print("[DONE] templates patched:", changed, "/", len(targets))
PY

echo "== [2] detect JS actually included by tabs (from templates) =="
python3 - <<'PY' > /tmp/vsp_tabs3_js_list_${TS}.txt
from pathlib import Path
import re

tabs = ("vsp_data_source", "vsp_rule_overrides", "vsp_settings")
tpl_dir = Path("templates")
js = set()

for t in tabs:
    # find any html whose name contains the tab key
    for p in tpl_dir.rglob("*.html"):
        if t in p.name:
            s = p.read_text(encoding="utf-8", errors="replace")
            for m in re.finditer(r'src\s*=\s*"(/static/js/[^"]+)"', s):
                js.add(m.group(1))

for x in sorted(js):
    print(x)
PY
echo "[INFO] js list => /tmp/vsp_tabs3_js_list_${TS}.txt"
cat /tmp/vsp_tabs3_js_list_${TS}.txt || true

echo "== [3] patch preview fetch in those JS (guard rid + ensure default path) =="
python3 - <<'PY'
from pathlib import Path
import re

lst = Path("/tmp").glob("vsp_tabs3_js_list_*.txt")
lst = sorted(lst, key=lambda p: p.stat().st_mtime, reverse=True)
if not lst:
    print("[WARN] no js list file found, skip")
    raise SystemExit(0)

js_list = [x.strip() for x in lst[0].read_text().splitlines() if x.strip().startswith("/static/js/")]
if not js_list:
    print("[WARN] no /static/js entries, skip")
    raise SystemExit(0)

patched = 0
for web_path in js_list:
    local = Path(web_path.lstrip("/"))
    if not local.exists():
        print("[WARN] missing local:", local)
        continue

    s = local.read_text(encoding="utf-8", errors="replace")
    s0 = s

    # A) Ensure any run_file_allow rid-only URL also has a safe default path
    # Handles: "/api/vsp/run_file_allow?rid="+rid
    s = re.sub(
        r'(["\']\/api\/vsp\/run_file_allow\?rid=["\']\s*\+\s*rid)(?!\s*\+\s*["\']\s*&path=)',
        r'\1 + "&path=run_gate_summary.json"',
        s
    )

    # Handles template literal: `/api/vsp/run_file_allow?rid=${rid}`
    s = re.sub(
        r'(`\/api\/vsp\/run_file_allow\?rid=\$\{rid\}`)(?![^`]*&path=)',
        r'`/api/vsp/run_file_allow?rid=${rid}&path=run_gate_summary.json`',
        s
    )

    # B) Guard rid before any run_file_allow fetch (best-effort; non-invasive)
    # Insert a small guard helper only once
    if "VSP_PREVIEW_GUARD_V2" not in s:
        inject = """
/* VSP_PREVIEW_GUARD_V2 */
function __vsp_hasRid(rid){
  if(!rid) return false;
  if(typeof rid !== "string") return false;
  if(rid.length < 6) return false;
  return /^[A-Za-z0-9_\\-]+$/.test(rid);
}
"""
        # put near top of IIFE
        s = re.sub(r'(\(\s*\)\s*=>\s*\{\s*)', r'\1\n' + inject + '\n', s, count=1)

    # Replace fetch(run_file_allow...) with guarded fetch that won't spam when rid invalid.
    # This keeps promise chain intact by returning a fake response-like object.
    def guard_fetch(m):
        inner = m.group(1)
        return (
            f"(__vsp_hasRid(rid) ? fetch({inner}) : Promise.resolve({{"
            f"ok:false, status:200, json:()=>Promise.resolve({{ok:false, skipped:true, reason:'no rid'}})"
            f"}}))"
        )

    s = re.sub(r'fetch\(\s*([^)]*run_file_allow[^)]*)\)', guard_fetch, s)

    if s != s0:
        local.write_text(s, encoding="utf-8")
        patched += 1
        print("[OK] patched JS:", local)
    else:
        print("[INFO] JS unchanged:", local)

print("[DONE] js patched:", patched, "/", len(js_list))
PY

if [ "$node_ok" = "1" ]; then
  echo "== [4] node --check affected JS (best-effort) =="
  while read -r p; do
    [ -z "$p" ] && continue
    f="${p#/}"
    [ -f "$f" ] || continue
    node --check "$f" >/dev/null && echo "[OK] node --check: $f" || { echo "[ERR] node check fail: $f"; exit 2; }
  done < /tmp/vsp_tabs3_js_list_${TS}.txt
fi

echo "== [5] restart service (best effort) =="
if [ "$svc_ok" = "1" ]; then
  systemctl restart "$SVC" || true
fi

echo "== [6] smoke: pages must not contain %22/static =="
for path in /data_source /rule_overrides /settings; do
  echo "-- $path --"
  curl -fsS "$BASE$path" | grep -nE '%22/static|/%22/static' && { echo "[ERR] still has %22 in $path"; exit 2; } || true
done
echo "[OK] no %22/static on 3 tabs"

echo "[DONE] Now reload /data_source, /rule_overrides, /settings with Ctrl+F5."
