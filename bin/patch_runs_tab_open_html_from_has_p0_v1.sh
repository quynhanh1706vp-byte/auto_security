#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# auto-pick runs JS
JS=""
for f in \
  static/js/vsp_runs_tab_resolved_v1.js \
  static/js/vsp_runs_tab_v1.js \
  static/js/vsp_runs_tab.js \
; do
  [ -f "$f" ] && JS="$f" && break
done
if [ -z "${JS:-}" ]; then
  JS="$(ls -1 static/js/*runs* 2>/dev/null | head -n1 || true)"
fi
[ -n "${JS:-}" ] || { echo "[ERR] cannot find runs tab js under static/js/*runs*"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_openhtml_${TS}"
echo "[BACKUP] ${JS}.bak_openhtml_${TS}"
echo "[JS]=$JS"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("""'"$JS"'""")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_RUNS_OPEN_HTML_FROM_HAS_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Heuristic: ensure we have a helper that resolves report URL from item.has + run_id
# We'll inject a small helper and patch the table row render: look for 'Open' / 'HTML' patterns,
# else add a new column in actions cell if exists.
helper = r"""
// VSP_RUNS_OPEN_HTML_FROM_HAS_P0_V1
function vspRunsReportUrl(it){
  try{
    const rid = (it && (it.run_id || it.rid || it.id)) ? String(it.run_id || it.rid || it.id) : "";
    const has = (it && it.has && typeof it.has === 'object') ? it.has : {};
    const hp = (has && typeof has.html_path === 'string') ? has.html_path : "";
    if (hp && hp.startsWith("/api/vsp/run_file")) return hp;
    if (rid && (has.html === true || has.html === 1 || has.html === "true")) {
      return "/api/vsp/run_file?rid=" + encodeURIComponent(rid) + "&name=" + encodeURIComponent("reports/index.html");
    }
  }catch(e){}
  return "";
}
"""

# Insert helper after 'use strict' / top IIFE open
if re.search(r"VSP_RUNS_OPEN_HTML_FROM_HAS_P0_V1", s):
    pass
else:
    m = re.search(r"(['\"]use strict['\"];?)", s)
    if m:
        ins_at = m.end()
        s = s[:ins_at] + "\n" + helper + "\n" + s[ins_at:]
    else:
        # fallback: prepend
        s = helper + "\n" + s

# Now patch rendering:
# We look for patterns building action links; common pattern: actions cell with innerHTML.
# We'll inject a small snippet that appends an <a>Open HTML</a> when url exists.
append_snip = r"""
    // VSP_RUNS_OPEN_HTML_FROM_HAS_P0_V1: add Open HTML report link (safe URL)
    try{
      const url = vspRunsReportUrl(it);
      if (url){
        const a = document.createElement('a');
        a.href = url;
        a.target = '_blank';
        a.rel = 'noopener';
        a.className = 'btn btn-sm';
        a.textContent = 'Open HTML';
        actions.appendChild(a);
      }
    }catch(e){}
"""

# Strategy: find "actions" element creation in row loop:
# - const actions = document.createElement('div') OR td
# We'll insert after first occurrence of "actions" creation and before append to row.
patterns = [
    r"(const\s+actions\s*=\s*document\.createElement\(['\"]div['\"]\)\s*;)",
    r"(let\s+actions\s*=\s*document\.createElement\(['\"]div['\"]\)\s*;)",
    r"(var\s+actions\s*=\s*document\.createElement\(['\"]div['\"]\)\s*;)",
]
done = False
for pat in patterns:
    m = re.search(pat, s)
    if m:
        insert_pos = m.end()
        s = s[:insert_pos] + "\n" + append_snip + "\n" + s[insert_pos:]
        done = True
        break

if not done:
    # fallback: find "actionsCell" or "tdActions" keyword
    m = re.search(r"(actionsCell|tdActions|td_action|tdActions)\s*=\s*document\.createElement\(['\"]td['\"]\)", s)
    if m:
        # insert helper creation of actions div
        insert_pos = m.end()
        s = s[:insert_pos] + "\n" + "    const actions = document.createElement('div');\n" + append_snip + "\n" + s[insert_pos:]
        done = True

if not done:
    print("[WARN] could not auto-hook actions div; leaving helper only.")
else:
    print("[OK] injected Open HTML link into actions area")

p.write_text(s, encoding="utf-8")
print("[OK] wrote:", p)
PY

echo "== node --check =="
node --check "$JS"
echo "[OK] node --check OK"

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service
sleep 0.6

echo "== smoke /runs + api/vsp/runs =="
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,15p'
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | python3 - <<'PY'
import sys, json
d=json.load(sys.stdin)
it=(d.get("items") or [{}])[0]
print("run_id=", it.get("run_id"))
print("has=", it.get("has"))
PY

echo "[NEXT] open http://127.0.0.1:8910/runs and check each row shows 'Open HTML' when has.html true."
