#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"
JS_GS="static/js/vsp_dashboard_gate_story_v1.js"
JS_P="static/js/vsp_dashboard_commercial_panels_v1.js"
WSGI="wsgi_vsp_ui_gateway.py"

[ -f "$JS_GS" ] || { echo "[ERR] missing $JS_GS"; exit 2; }
[ -f "$WSGI"  ] || { echo "[ERR] missing $WSGI"; exit 2; }

# 0) Backup
cp -f "$JS_GS" "${JS_GS}.bak_clean_${TS}"
cp -f "$WSGI"  "${WSGI}.bak_panels_${TS}"
echo "[BACKUP] ${JS_GS}.bak_clean_${TS}"
echo "[BACKUP] ${WSGI}.bak_panels_${TS}"

# 1) HARD disable all previous injected "DashP1" blocks inside GateStory (giữ GateStory ổn định)
python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# remove any big appended blocks we previously injected (DashP1 / P1 panels markers)
patterns = [
    r"/\*\s*====================\s*VSP_P1_DASHBOARD_P1_PANELS_.*?====================\s*\*/.*?/\\*\\s*====================\\s*/VSP_P1_DASHBOARD_P1_PANELS_.*?====================\\s*\\*/",
    r"/\*\s*====================\s*VSP_P1_DASHBOARD_P1_PANELS_.*?\\*/.*?/\\*\\s*====================\\s*/VSP_P1_DASHBOARD_P1_PANELS_.*?\\*/",
]
removed = 0
for pat in patterns:
    s2, n = re.subn(pat, "", s, flags=re.S)
    if n:
        removed += n
        s = s2

# also remove stray labels like [DashP1V3]/[DashP1V6] blocks if any (best effort)
s2, n2 = re.subn(r"/\*[^*]*DashP1[^*]*\*/.*?(?=/\*|$)", "", s, flags=re.S)
if n2:
    removed += n2
    s = s2

p.write_text(s, encoding="utf-8")
print(f"[OK] GateStory cleaned. removed_blocks={removed}")
PY

# 2) Write external panels JS (standalone, robust, always renders SOMETHING so bạn nhìn thấy ngay)
python3 - <<'PY'
from pathlib import Path
import textwrap

Path("static/js/vsp_dashboard_commercial_panels_v1.js").write_text(textwrap.dedent(r"""
/* VSP_P1_EXTERNAL_PANELS_V2 (standalone; do NOT modify GateStory) */
(() => {
  if (window.__vsp_p1_external_panels_v2) return;
  window.__vsp_p1_external_panels_v2 = true;

  const log = (...a)=>console.log("[P1PanelsExtV2]", ...a);
  const warn = (...a)=>console.warn("[P1PanelsExtV2]", ...a);

  const sleep = (ms)=>new Promise(r=>setTimeout(r,ms));
  const esc = (s)=>String(s??"").replace(/[&<>"']/g,m=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[m]));

  function ensureRoot(){
    // attach under main page area
    const host = document.querySelector("body") || document.documentElement;
    let root = document.getElementById("vsp-commercial-panels-root");
    if (!root){
      root = document.createElement("div");
      root.id = "vsp-commercial-panels-root";
      root.style.margin = "14px 14px 0 14px";
      root.style.paddingBottom = "18px";
      host.appendChild(root);
    }
    return root;
  }

  function mkCard(title, bodyHtml){
    return `
      <div style="
        background: rgba(255,255,255,0.04);
        border: 1px solid rgba(255,255,255,0.06);
        border-radius: 14px;
        padding: 12px 12px;
        box-shadow: 0 10px 30px rgba(0,0,0,0.25);
        margin-top: 12px;
      ">
        <div style="font-weight:700; letter-spacing:.2px; margin-bottom:8px;">${esc(title)}</div>
        <div style="color: rgba(255,255,255,0.82); font-size: 13px; line-height: 1.45;">
          ${bodyHtml}
        </div>
      </div>
    `;
  }

  function pickRIDFromPage(){
    // try common globals / text
    const t = (document.body && (document.body.innerText || "")) || "";
    const m = t.match(/\b(VSP_CI_RUN_\d{8}_\d{6})\b/);
    if (m) return m[1];
    const m2 = t.match(/\b(RUN_\d{8}_\d{6})\b/);
    if (m2) return m2[1];
    // also try known global used by your logs
    if (typeof window.__vsp_gate_root === "string" && window.__vsp_gate_root) return window.__vsp_gate_root;
    if (typeof window.__VSP_GATE_ROOT__ === "string" && window.__VSP_GATE_ROOT__) return window.__VSP_GATE_ROOT__;
    return null;
  }

  async function fetchJSON(url){
    const r = await fetch(url, { credentials: "same-origin", cache: "no-store" });
    const txt = await r.text();
    let j = null;
    try { j = JSON.parse(txt); } catch(e){ /* ignore */ }
    if (!r.ok) throw new Error(`HTTP ${r.status} ${url} body=${txt.slice(0,180)}`);
    // unwrap common wrappers
    if (j && typeof j === "object"){
      if (j.data && typeof j.data === "object") return j.data;
      if (j.ok === true && j.result && typeof j.result === "object") return j.result;
    }
    return j;
  }

  async function getRIDFallback(){
    // prefer page parse first (fast)
    const rid0 = pickRIDFromPage();
    if (rid0) return rid0;

    // fallback: latest run via /api/vsp/runs
    try{
      const runs = await fetchJSON("/api/vsp/runs?limit=1&offset=0");
      // try multiple shapes
      const arr = Array.isArray(runs) ? runs
        : Array.isArray(runs?.runs) ? runs.runs
        : Array.isArray(runs?.items) ? runs.items
        : [];
      const one = arr[0] || null;
      const rid = one?.rid || one?.run_id || one?.id || null;
      if (rid) return rid;
    }catch(e){
      warn("runs fallback failed", e);
    }
    return null;
  }

  function sevWeight(s){
    s = String(s||"").toUpperCase();
    return ({CRITICAL:5,HIGH:4,MEDIUM:3,LOW:2,INFO:1,TRACE:0}[s] ?? -1);
  }

  function topFindings(list, n){
    const a = Array.isArray(list) ? list.slice() : [];
    a.sort((x,y)=>{
      const sx = sevWeight(x?.severity), sy = sevWeight(y?.severity);
      if (sy !== sx) return sy - sx;
      const tx = String(x?.tool||""), ty = String(y?.tool||"");
      if (tx !== ty) return tx.localeCompare(ty);
      return String(x?.rule_id||"").localeCompare(String(y?.rule_id||""));
    });
    return a.slice(0,n);
  }

  async function main(){
    const root = ensureRoot();
    // always show "loaded" card so bạn biết script chạy
    root.innerHTML = mkCard("Commercial Panels (external)", `Status: <b>loaded</b>. Waiting data…`);

    const rid = await getRIDFallback();
    if (!rid){
      root.innerHTML = mkCard("Commercial Panels (external)", `Status: <b>no RID</b>. Không resolve được RID từ page + /api/vsp/runs.`);
      return;
    }

    // fetch findings_unified.json via allow endpoint
    let fu = null;
    try{
      fu = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`);
    }catch(e){
      root.innerHTML = mkCard("Commercial Panels (external)", `RID=<b>${esc(rid)}</b><br>Status: <b>fetch findings failed</b><br><code>${esc(String(e))}</code>`);
      return;
    }

    const meta = fu?.meta || {};
    const counts = meta?.counts_by_severity || meta?.counts || {};
    const findings = fu?.findings || fu?.items || fu?.data?.findings || [];

    const cHtml = Object.keys(counts).length
      ? Object.entries(counts).map(([k,v])=>`<span style="display:inline-block;margin-right:10px;"><b>${esc(k)}</b>: ${esc(v)}</span>`).join("")
      : `<span style="opacity:.8">(no counts_by_severity)</span>`;

    const top = topFindings(findings, 12);
    const rows = top.map(f=>{
      const sev = esc(f?.severity || "");
      const tool = esc(f?.tool || "");
      const rule = esc(f?.rule_id || f?.rule || "");
      const title = esc(f?.title || f?.message || f?.name || "");
      const loc = esc(f?.location || f?.path || f?.file || "");
      return `<div style="padding:6px 0;border-top:1px solid rgba(255,255,255,0.06)">
        <span style="display:inline-block;min-width:70px;font-weight:700;">${sev}</span>
        <span style="display:inline-block;min-width:90px;opacity:.9">${tool}</span>
        <span style="display:inline-block;min-width:210px;opacity:.9">${rule}</span>
        <span style="opacity:.95">${title}</span>
        <div style="opacity:.75;margin-left:160px;margin-top:2px;font-size:12px;">${loc}</div>
      </div>`;
    }).join("");

    root.innerHTML =
      mkCard("Commercial Panels (external)", `RID: <b>${esc(rid)}</b><br>Counts: ${cHtml}`) +
      mkCard("Top Findings", rows || "<i>(no findings)</i>");

    log("rendered", { rid, findings_len: Array.isArray(findings)?findings.length:0, has_counts: !!Object.keys(counts||{}).length });
  }

  (async()=>{
    try{
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => main(), { once: true });
      } else {
        await main();
      }
    }catch(e){
      warn("fatal", e);
      const root = ensureRoot();
      root.innerHTML = mkCard("Commercial Panels (external)", `fatal: <code>${esc(String(e))}</code>`);
    }
  })();
})();
""").strip()+"\n", encoding="utf-8")
print("[OK] wrote static/js/vsp_dashboard_commercial_panels_v1.js")
PY

# 3) Patch /vsp5 HTML generator to include panels JS right after GateStory JS
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_EXTERNAL_PANELS_INCLUDE_V2"
if marker in s:
    print("[OK] include marker already present (skip)")
    raise SystemExit(0)

# insert after gate_story include (works even if inside triple-quoted HTML string)
pat = r'(<script\s+src="/static/js/vsp_dashboard_gate_story_v1\.js\?v=\{\{\s*asset_v\s*\}\}"></script>\s*\n)'
ins = r'\1  <!-- '+marker+' -->\n  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js?v={{ asset_v }}"></script>\n'
s2, n = re.subn(pat, ins, s, count=1, flags=re.M)

if n == 0:
    # fallback: looser match (any querystring)
    pat2 = r'(<script\s+src="/static/js/vsp_dashboard_gate_story_v1\.js\?v=[^"]+"></script>\s*\n)'
    s2, n2 = re.subn(pat2, ins, s, count=1, flags=re.M)
    n = n2

if n == 0:
    print("[WARN] cannot find GateStory include line in WSGI -> no include inserted")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] inserted panels include into WSGI")

PY

# Verify quick via curl (should show BOTH lines)
echo "== VERIFY HTML includes scripts =="
curl -fsS "$BASE/vsp5" | grep -nE "vsp_dashboard_gate_story_v1\.js|vsp_dashboard_commercial_panels_v1\.js|VSP_P1_EXTERNAL_PANELS_INCLUDE_V2" || true

echo
echo "[DONE] Next:"
echo "  1) restart UI service (systemd/gunicorn)"
echo "  2) Ctrl+Shift+R /vsp5"
echo "Expected: Console has [P1PanelsExtV2] rendered ... and page shows 2 cards at bottom."
