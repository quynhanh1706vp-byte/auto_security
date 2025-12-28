#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TPL="templates/vsp_runs_reports_v1.html"
JS="static/js/vsp_scan_panel_v1.js"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "${TPL}.bak_scanpanel_${TS}"
echo "[BACKUP] ${TPL}.bak_scanpanel_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time, textwrap

tpl = Path("templates/vsp_runs_reports_v1.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_SCAN_PANEL_RUNS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

panel = textwrap.dedent(f"""
<!-- {MARK} -->
<section class="card" id="vspScanPanel" style="margin:14px 0; padding:14px; border:1px solid rgba(255,255,255,.10); border-radius:14px;">
  <div style="display:flex; align-items:center; justify-content:space-between; gap:12px; flex-wrap:wrap;">
    <div>
      <div style="font-weight:700; font-size:14px; letter-spacing:.2px;">Scan / Start Run</div>
      <div style="opacity:.75; font-size:12px; margin-top:4px;">
        Kick off a new scan via <code>/api/vsp/run_v1</code> and poll status via <code>/api/vsp/run_status_v1/&lt;REQ_ID&gt;</code>.
      </div>
    </div>
    <div style="display:flex; gap:10px; flex-wrap:wrap;">
      <button class="btn" id="vspScanStartBtn" type="button">Start scan</button>
      <button class="btn" id="vspScanRefreshBtn" type="button" style="opacity:.9;">Refresh runs</button>
    </div>
  </div>

  <div style="display:grid; grid-template-columns: 1.4fr .8fr; gap:12px; margin-top:12px;">
    <div>
      <label style="display:block; font-size:12px; opacity:.8; margin-bottom:6px;">Target path (repo/workdir)</label>
      <input id="vspScanTarget" class="inp" style="width:100%; padding:10px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.18); color:inherit;"
             value="/home/test/Data/SECURITY_BUNDLE" />
      <div style="opacity:.65; font-size:12px; margin-top:6px;">Gợi ý: trỏ vào workspace chứa runner/tool config.</div>
    </div>
    <div>
      <label style="display:block; font-size:12px; opacity:.8; margin-bottom:6px;">Mode</label>
      <select id="vspScanMode" class="inp" style="width:100%; padding:10px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.18); color:inherit;">
        <option value="FULL">FULL (8 tools)</option>
        <option value="FAST">FAST (smoke)</option>
      </select>
      <label style="display:block; font-size:12px; opacity:.8; margin:10px 0 6px;">Note</label>
      <input id="vspScanNote" class="inp" style="width:100%; padding:10px 12px; border-radius:12px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.18); color:inherit;"
             placeholder="optional note for audit trail" />
    </div>
  </div>

  <pre id="vspScanLog" style="margin-top:12px; padding:12px; border-radius:14px; background:rgba(0,0,0,.28); border:1px solid rgba(255,255,255,.08); max-height:220px; overflow:auto; font-size:12px; line-height:1.35;">Ready.</pre>
</section>
<!-- /{MARK} -->
""").strip()

# inject before closing body
if "</body>" in s:
    s = s.replace("</body>", panel + "\n\n</body>")
else:
    s += "\n\n" + panel + "\n"

# ensure JS included once
if "vsp_scan_panel_v1.js" not in s:
    ins = "</body>"
    tag = '\n<script src="/static/js/vsp_scan_panel_v1.js?v={{ asset_v }}"></script>\n'
    s = s.replace(ins, tag + ins)

tpl.write_text(s, encoding="utf-8")
print("[OK] injected scan panel + JS include")
PY

# write JS
cat > static/js/vsp_scan_panel_v1.js <<'JS'
/* VSP_P1_SCAN_PANEL_V1 - commercial-safe scan trigger + status poll */
(()=> {
  if (window.__vsp_scan_panel_v1) return;
  window.__vsp_scan_panel_v1 = true;

  const $ = (id)=> document.getElementById(id);

  function log(msg){
    const el = $("vspScanLog");
    if(!el) return;
    const ts = new Date().toISOString().replace('T',' ').replace('Z','');
    el.textContent = `[${ts}] ${msg}\n` + el.textContent;
  }

  async function postJSON(url, obj){
    const r = await fetch(url, {
      method: "POST",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify(obj || {})
    });
    const ct = (r.headers.get("content-type")||"");
    let data = null;
    try{
      data = ct.includes("application/json") ? await r.json() : await r.text();
    }catch(e){
      data = await r.text().catch(()=> "");
    }
    return {ok: r.ok, status: r.status, data};
  }

  async function getJSON(url){
    const r = await fetch(url, {method:"GET"});
    const ct = (r.headers.get("content-type")||"");
    let data = null;
    try{
      data = ct.includes("application/json") ? await r.json() : await r.text();
    }catch(e){
      data = await r.text().catch(()=> "");
    }
    return {ok: r.ok, status: r.status, data};
  }

  function pickReqId(resp){
    if(!resp) return null;
    const d = resp.data;
    if(!d || typeof d !== "object") return null;
    return d.req_id || d.request_id || d.id || d.rid || null;
  }

  async function pollStatus(reqId){
    // If backend uses req_id, poll; if only rid returned, we still try (won't break).
    const url = `/api/vsp/run_status_v1/${encodeURIComponent(reqId)}`;
    for(let i=0;i<90;i++){
      const r = await getJSON(url);
      if(!r.ok){
        log(`status poll: HTTP ${r.status} (endpoint may not exist for id=${reqId}).`);
        return;
      }
      const d = r.data;
      log(`status: ${JSON.stringify(d).slice(0,240)}${JSON.stringify(d).length>240?"...":""}`);
      // heuristic stop
      if(d && typeof d === "object"){
        const st = (d.status || d.state || d.overall || "").toString().toUpperCase();
        if(["DONE","FINISHED","OK","PASS","FAIL","ERROR","GREEN","AMBER","RED"].includes(st)) return;
        if(d.done === true) return;
      }
      await new Promise(res=>setTimeout(res, 2000));
    }
    log("status poll: timeout (still running?)");
  }

  async function startScan(){
    const target = ($("vspScanTarget")?.value || "").trim();
    const mode = ($("vspScanMode")?.value || "FULL").trim();
    const note = ($("vspScanNote")?.value || "").trim();

    if(!target){
      log("missing target path.");
      return;
    }

    const payload = {
      target_path: target,
      mode: mode,
      note: note,
      source: "UI_SCAN_PANEL_V1"
    };

    log(`POST /api/vsp/run_v1 => ${JSON.stringify(payload)}`);
    const r = await postJSON("/api/vsp/run_v1", payload);

    if(!r.ok){
      log(`run_v1 failed: HTTP ${r.status}. Response: ${typeof r.data==="string"?r.data:JSON.stringify(r.data)}`);
      log("Hint: backend may not wire run_v1 yet, or expects different fields.");
      return;
    }

    log(`run_v1 ok: ${typeof r.data==="string"?r.data:JSON.stringify(r.data)}`);

    const reqId = pickReqId(r);
    if(reqId){
      log(`polling status for id=${reqId}`);
      await pollStatus(reqId);
    }else{
      log("No req_id in response; cannot poll. (Still OK — backend contract may differ.)");
    }
  }

  function wire(){
    const startBtn = $("vspScanStartBtn");
    const refBtn = $("vspScanRefreshBtn");
    if(startBtn){
      startBtn.addEventListener("click", ()=> startScan().catch(e=>log("startScan error: "+e)));
    }
    if(refBtn){
      refBtn.addEventListener("click", ()=> location.reload());
    }
  }

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", wire);
  } else {
    wire();
  }
})();
JS

python3 -m py_compile wsgi_vsp_ui_gateway.py >/dev/null || true
echo "[OK] wrote $JS"
echo "[DONE] restart UI:"
echo "  rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.*; bin/p1_ui_8910_single_owner_start_v2.sh"
