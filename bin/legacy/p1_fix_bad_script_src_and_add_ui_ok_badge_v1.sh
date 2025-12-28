#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [1] fix templates bad src/href (%22 / \\\" / trailing \\) =="

python3 - <<'PY'
from pathlib import Path
import re, datetime

tpl_root = Path("templates")
if not tpl_root.exists():
    print("[SKIP] templates/ not found")
    raise SystemExit(0)

files = sorted([p for p in tpl_root.rglob("*.html")])
changed = 0

def fix_text(s: str) -> str:
    # 1) remove leading \" or "" before /static/ inside attributes
    s = s.replace('\\"/static/', '/static/')
    s = s.replace('""/static/', '/static/')
    s = s.replace("'\"/static/", '/static/')
    # 2) remove literal %22 that got into templates (rare but seen)
    s = s.replace('%22/static/', '/static/')
    # 3) fix trailing backslash after .js in src/href (e.g. vsp_data_source_lazy_v1.js\)
    s = re.sub(r'(/static/[^"\'>\s]+\.js)\\', r'\1', s)
    # 4) fix weird src="/%22/static/..." (quote encoded in path)
    s = s.replace('/%22/static/', '/static/')
    return s

for p in files:
    raw = p.read_text(encoding="utf-8", errors="replace")
    new = fix_text(raw)
    if new != raw:
        bak = p.with_suffix(p.suffix + f".bak_srcfix_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}")
        bak.write_text(raw, encoding="utf-8")
        p.write_text(new, encoding="utf-8")
        changed += 1
        print("[OK] fixed:", p)

print("[DONE] templates fixed files =", changed)
PY

echo "== [2] add UI OK badge to common dashboard js (commercial + vsp5) =="

python3 - <<'PY'
from pathlib import Path
import textwrap

targets = [
  Path("static/js/vsp_dashboard_commercial_v1.js"),
  Path("static/js/vsp_dash_only_v1.js"),
]

MARK="VSP_P1_UI_OK_BADGE_V1"
addon = textwrap.dedent(r"""
/* ===================== VSP_P1_UI_OK_BADGE_V1 ===================== */
(()=> {
  if (window.__vsp_p1_ui_ok_badge_v1) return;
  window.__vsp_p1_ui_ok_badge_v1 = true;

  async function ping(){
    try{
      const r = await fetch("/api/vsp/rid_latest_gate_root", {credentials:"same-origin"});
      if(!r.ok) return {ok:false, status:r.status};
      const j = await r.json().catch(()=>null);
      return {ok: !!(j && (j.ok || j.rid)), status:200};
    }catch(e){
      return {ok:false, status:0};
    }
  }

  function mount(){
    if (document.getElementById("vsp_ui_ok_badge_v1")) return;

    const host =
      document.querySelector("header") ||
      document.querySelector(".topbar") ||
      document.querySelector("#topbar") ||
      document.body;

    const b = document.createElement("span");
    b.id = "vsp_ui_ok_badge_v1";
    b.textContent = "UI: …";
    b.style.cssText =
      "display:inline-flex;align-items:center;gap:6px;" +
      "padding:4px 10px;border-radius:999px;" +
      "border:1px solid rgba(255,255,255,.12);" +
      "background:rgba(255,255,255,.06);" +
      "color:#d8ecff;font:12px/1.2 system-ui,Segoe UI,Roboto;" +
      "margin-left:10px;";

    // If host is body (fallback), make fixed
    if (host === document.body){
      b.style.cssText += "position:fixed;z-index:99998;top:10px;right:12px;";
      document.body.appendChild(b);
    } else {
      host.appendChild(b);
    }

    async function refresh(){
      const res = await ping();
      if(res.ok){
        b.textContent = "UI: OK";
        b.style.borderColor = "rgba(90,255,170,.35)";
        b.style.background = "rgba(20,80,40,.35)";
        b.style.color = "#c9ffe0";
      } else {
        b.textContent = "UI: DEGRADED";
        b.style.borderColor = "rgba(255,210,120,.35)";
        b.style.background = "rgba(80,60,20,.35)";
        b.style.color = "#ffe7b7";
      }
    }

    refresh();
    setInterval(refresh, 30000);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
/* ===================== /VSP_P1_UI_OK_BADGE_V1 ===================== */
""")

for js in targets:
    if not js.exists():
        continue
    s = js.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        print("[SKIP] badge already in", js)
        continue
    js.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
    print("[OK] appended badge =>", js)
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] srcfix + UI OK badge applied; restarted $SVC"
