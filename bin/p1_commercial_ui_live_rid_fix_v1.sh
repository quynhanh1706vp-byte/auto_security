#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need grep; need find

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 0) (optional) ingest data thật nếu script có sẵn
if [ -x bin/p0_data_first_ingest_latest_v1.sh ]; then
  echo "[STEP 0] data-first ingest latest (optional)"
  MAX_ITEMS="${MAX_ITEMS:-2500}" bin/p0_data_first_ingest_latest_v1.sh || true
fi

# 1) Patch JS boot: thêm live poll /api/vsp/runs để:
#    - clear sticky RUNS API FAIL
#    - luôn lấy rid_latest thật
#    - update link Open Data Source / Open Summary theo rid_latest
JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_livefix_${TS}"
echo "[BACKUP] ${JS}.bak_livefix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("static/js/vsp_p1_page_boot_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_LIVE_RID_AND_RUNS_HEALTH_V1"
if MARK in s:
    print("[SKIP] marker already present:", MARK)
    raise SystemExit(0)

inject = r"""
;(()=>{ 
  const MARK="VSP_P1_LIVE_RID_AND_RUNS_HEALTH_V1";
  if (window[MARK]) return; window[MARK]=1;

  const POLL_MS = 2500;

  function setPill(ok, msg){
    let pill = document.getElementById("vsp_live_runs_pill");
    if(!pill){
      pill = document.createElement("div");
      pill.id = "vsp_live_runs_pill";
      pill.style.cssText = [
        "position:fixed","top:10px","right:12px","z-index:99999",
        "padding:6px 10px","border-radius:999px",
        "font:12px/1.2 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Arial",
        "background:rgba(0,0,0,.55)","border:1px solid rgba(255,255,255,.12)",
        "color:#e5e7eb","backdrop-filter: blur(8px)",
        "box-shadow: 0 10px 30px rgba(0,0,0,.35)"
      ].join(";");
      document.body.appendChild(pill);
    }
    pill.textContent = msg || "";
    pill.style.borderColor = ok ? "rgba(34,197,94,.45)" : "rgba(239,68,68,.45)";
  }

  function clearStickyBanners(){
    // cố gắng dọn các banner "RUNS API FAIL" bị sticky
    const all = Array.from(document.querySelectorAll("div,span,a,button"));
    for (const el of all){
      const t = (el.textContent || "").trim();
      if (!t) continue;
      if (t.includes("RUNS API FAIL") || (t.includes("RUNS API") && t.includes("Error:"))){
        el.textContent = "RUNS API OK";
      }
    }
  }

  function setTopLinks(rid){
    if(!rid) return;
    // update các link “Open Data Source / Open Summary” nếu có
    const anchors = Array.from(document.querySelectorAll("a"));
    for (const a of anchors){
      const t = (a.textContent || "").trim().toLowerCase();
      if (t === "open data source"){
        a.href = "/data_source?rid=" + encodeURIComponent(rid);
        a.target = "_blank";
      } else if (t === "open summary"){
        a.href = "/api/vsp/run_file?rid=" + encodeURIComponent(rid) + "&name=" + encodeURIComponent("reports/run_gate_summary.json");
        a.target = "_blank";
      }
    }
  }

  function setLatestRidText(rid){
    if(!rid) return;
    // best-effort: update any small label that contains "Latest RID"
    const els = Array.from(document.querySelectorAll("div,span"));
    for (const el of els){
      const t = (el.textContent || "").trim();
      if (t === "Latest RID" || t.toLowerCase() === "latest rid"){
        // try next sibling text node / element
        const parent = el.parentElement;
        if (parent){
          // look for something that looks like a run id under same parent
          const kids = Array.from(parent.querySelectorAll("div,span"));
          for (const k of kids){
            if (k === el) continue;
            const kt = (k.textContent||"").strip();
            if ("_RUN_" in kt or kt.startswith("RUN_") or kt.startswith("VSP_") or "_CI_" in kt or "_CI_RUN_" in kt):
              k.textContent = rid
              return
          }
        }
      }
    }
  }

  async function poll(){
    const url = "/api/vsp/runs?limit=1&_=" + Date.now();
    try{
      const r = await fetch(url, { cache: "no-store", credentials: "same-origin" });
      if(!r.ok) throw new Error("HTTP " + r.status);
      const j = await r.json();
      if(!j || j.ok !== true) throw new Error("bad_json");
      const rid = j.rid_latest || (j.items && j.items[0] && j.items[0].run_id) || null;

      window.__VSP_RID_LATEST__ = rid;
      try{ localStorage.setItem("vsp_rid_latest", rid || ""); }catch(_){}

      clearStickyBanners();
      setTopLinks(rid);

      const tag = (j.degraded ? "DEGRADED" : "OK");
      setPill(true, `RUNS ${tag} • rid_latest=${rid || "N/A"}`);

    }catch(e){
      setPill(false, `RUNS FAIL • ${String(e)}`);
    }
  }

  // dọn cache key cũ (không phá cấu hình khác)
  try{
    ["vsp_last_rid","vsp_selected_rid","vsp_rid_latest_old"].forEach(k=>localStorage.removeItem(k));
  }catch(_){}

  poll();
  setInterval(poll, POLL_MS);
})();
"""

# NOTE: keep injection append-only (safe)
s2 = s + "\n\n// " + MARK + "\n" + inject + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

# 2) Cache-bust templates: đảm bảo browser tải JS mới
TPL_DIR="templates"
python3 - <<PY
from pathlib import Path
import re
ts="${TS}"

tpl_dir = Path("${TPL_DIR}")
if not tpl_dir.is_dir():
    print("[WARN] no templates/ folder; skip cache-bust")
    raise SystemExit(0)

targets = [
  "static/js/vsp_p1_page_boot_v1.js",
  "static/js/vsp_runs_tab_resolved_v1.js",
  "static/js/vsp_bundle_commercial_v2.js",
  "static/js/vsp_bundle_commercial_v1.js",
]

patched = []
for f in tpl_dir.rglob("*.html"):
    s = f.read_text(encoding="utf-8", errors="replace")
    s0 = s
    for t in targets:
        # replace "...t" with "...t?v=ts" if no query already
        s = re.sub(r'(' + re.escape(t) + r')(?!"|\'|\?)', r'\1?v=' + ts, s)
        s = re.sub(r'(' + re.escape(t) + r')("|\')', r'\1?v=' + ts + r'\2', s)
    if s != s0:
        f.write_text(s, encoding="utf-8")
        patched.append(str(f))

print("[OK] cache-bust patched templates:", len(patched))
for x in patched[:20]:
    print(" -", x)
PY

echo "[OK] patch done. Restart UI now."

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh || true
sleep 1

echo "== verify =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=1" | sed -n '1,18p' || true
echo
curl -sS "http://127.0.0.1:8910/api/vsp/runs?limit=1" | jq -r '.ok,.rid_latest,.items[0].run_id,.degraded?' || true

echo
echo "[NEXT] Browser: Ctrl+F5 (hard refresh) /vsp5, hoặc mở Incognito để chắc chắn hết cache."
