#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# pick runs JS
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
cp -f "$JS" "${JS}.bak_openhtml_v2_${TS}"
echo "[BACKUP] ${JS}.bak_openhtml_v2_${TS}"
echo "[JS]=$JS"

export JSF="$JS"

python3 - <<'PY'
import os, re
from pathlib import Path

jsf = os.environ.get("JSF","").strip()
if not jsf:
    raise SystemExit("[ERR] missing JSF env")
p = Path(jsf)
if not p.exists():
    raise SystemExit(f"[ERR] JS file not found: {p}")

s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_RUNS_OPEN_HTML_FROM_HAS_P0_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

helper = r"""
// VSP_RUNS_OPEN_HTML_FROM_HAS_P0_V2
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

# insert helper after "use strict" if possible
m = re.search(r"(['\"]use strict['\"];?)", s)
if m:
    ins = m.end()
    s = s[:ins] + "\n" + helper + "\n" + s[ins:]
else:
    s = helper + "\n" + s

append_snip = r"""
    // VSP_RUNS_OPEN_HTML_FROM_HAS_P0_V2: add Open HTML report link (safe URL)
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

done = False

# Strategy A: find actions div creation
for pat in [
    r"(const\s+actions\s*=\s*document\.createElement\(['\"]div['\"]\)\s*;)",
    r"(let\s+actions\s*=\s*document\.createElement\(['\"]div['\"]\)\s*;)",
    r"(var\s+actions\s*=\s*document\.createElement\(['\"]div['\"]\)\s*;)",
]:
    mm = re.search(pat, s)
    if mm:
        s = s[:mm.end()] + "\n" + append_snip + "\n" + s[mm.end():]
        done = True
        break

# Strategy B: actions = document.createElement('td') and then inner container
if not done:
    mm = re.search(r"(const\s+actions\s*=\s*document\.createElement\(['\"]td['\"]\)\s*;)", s)
    if mm:
        inject2 = "\n" + "    const actionsDiv = document.createElement('div');\n" \
                  + "    const actions = actionsDiv;\n" + append_snip + "\n"
        s = s[:mm.end()] + inject2 + s[mm.end():]
        done = True

# Strategy C: template-string actions HTML: look for 'Open' 'Report' anchors
if not done:
    # If code uses `actions.innerHTML = ...`, append a link by string.
    mm = re.search(r"(actions\.innerHTML\s*=\s*[^;]+;)", s)
    if mm:
        add = r"""
    try{
      const url = vspRunsReportUrl(it);
      if (url){
        actions.innerHTML += ' <a class="btn btn-sm" target="_blank" rel="noopener" href="'+url+'">Open HTML</a>';
      }
    }catch(e){}
"""
        s = s[:mm.end()] + add + s[mm.end():]
        done = True

if done:
    print("[OK] injected Open HTML render logic")
else:
    print("[WARN] could not find a good hook; helper inserted only (need manual hook).")

p.write_text(s, encoding="utf-8")
print("[OK] wrote:", p)
PY

echo "== node --check =="
node --check "$JS"
echo "[OK] node --check OK"

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service
sleep 0.8

echo "== smoke /runs + api/vsp/runs =="
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,15p'
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | python3 - <<'PY'
import sys, json
d=json.load(sys.stdin)
it=(d.get("items") or [{}])[0]
print("run_id=", it.get("run_id"))
print("has=", it.get("has"))
PY

echo "[NEXT] Mở http://127.0.0.1:8910/runs và nhìn row nào has.html=true sẽ có nút 'Open HTML'."
