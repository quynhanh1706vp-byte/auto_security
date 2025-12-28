#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

TS="$(date +%Y%m%d_%H%M%S)"
JS_NEW="static/js/vsp_data_source_charts_v1.js"
TPL_DIR="templates"

mkdir -p static/js

# Create JS file if missing (idempotent)
if [ ! -f "$JS_NEW" ]; then
cat > "$JS_NEW" <<'JS'
/* VSP_P2_DATA_SOURCE_CHARTS_V1 (safe agg via /api/ui/findings_agg_v1; no big DOM render) */
(()=> {
  const esc = (s)=> String(s||"").replace(/</g,"&lt;");
  function fmt(n){ try{ return (Number(n)||0).toLocaleString(); }catch(_){ return String(n||0); } }

  async function getLatestRid(){
    try{
      const r = await fetch("/api/vsp/runs?limit=1", {cache:"no-store"});
      const j = await r.json();
      if(Array.isArray(j?.runs) && j.runs[0]?.rid) return j.runs[0].rid;
      if(Array.isArray(j) && j[0]?.rid) return j[0].rid;
    }catch(e){}
    return null;
  }

  function ridFromUrl(){
    try{
      const u = new URL(location.href);
      return (u.searchParams.get("rid")||"").trim() || null;
    }catch(e){ return null; }
  }

  function setText(id, v){
    const el = document.getElementById(id);
    if(el) el.textContent = v;
  }

  function renderBars(container, items, keyName){
    if(!container) return;
    container.innerHTML = "";
    const max = Math.max(1, ...items.map(x=> Number(x.count)||0));
    for(const it of items){
      const row = document.createElement("div");
      row.style.display="grid";
      row.style.gridTemplateColumns="180px 1fr 70px";
      row.style.gap="10px";
      row.style.alignItems="center";
      row.style.margin="6px 0";

      const name = document.createElement("div");
      name.style.fontSize="12px";
      name.style.opacity="0.92";
      name.style.whiteSpace="nowrap";
      name.style.overflow="hidden";
      name.style.textOverflow="ellipsis";
      name.textContent = it[keyName] || "—";

      const barWrap = document.createElement("div");
      barWrap.style.height="10px";
      barWrap.style.borderRadius="10px";
      barWrap.style.background="rgba(159,176,199,0.12)";
      barWrap.style.position="relative";
      barWrap.style.overflow="hidden";

      const bar = document.createElement("div");
      bar.style.height="100%";
      bar.style.width = (Math.round((Number(it.count)||0)/max*1000)/10)+"%";
      bar.style.background="rgba(159,176,199,0.45)";
      barWrap.appendChild(bar);

      const cnt = document.createElement("div");
      cnt.style.fontSize="12px";
      cnt.style.opacity="0.85";
      cnt.style.textAlign="right";
      cnt.textContent = fmt(it.count||0);

      row.appendChild(name);
      row.appendChild(barWrap);
      row.appendChild(cnt);
      container.appendChild(row);
    }
  }

  function renderSeverity(container, bySev){
    const levels = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    const items = levels.map(k=>({sev:k, count:Number(bySev?.[k]||0)}));
    renderBars(container, items, "sev");
  }

  async function loadAgg(){
    const ridBox = document.getElementById("vsp_ds_rid");
    let rid = ridFromUrl() || (ridBox ? (ridBox.value||"").trim() : null) || null;
    if(!rid) rid = await getLatestRid();
    if(ridBox && rid) ridBox.value = rid;

    if(!rid){
      setText("vsp_ds_status", "No RID found");
      return;
    }

    setText("vsp_ds_status", "Loading…");
    try{
      const r = await fetch(`/api/ui/findings_agg_v1?rid=${encodeURIComponent(rid)}`, {cache:"no-store"});
      const j = await r.json();
      if(!j?.ok) throw new Error(j?.err || "agg failed");

      setText("vsp_ds_status", `RID: ${rid} • source: ${j.source||"unknown"}`);

      renderSeverity(document.getElementById("vsp_ds_sev"), j.by_severity || {});
      renderBars(document.getElementById("vsp_ds_tools"), (j.by_tool||[]).map(x=>({tool:x.tool, count:x.count})), "tool");
      renderBars(document.getElementById("vsp_ds_rules"), (j.top_rules||[]).map(x=>({rule_id:x.rule_id, count:x.count})), "rule_id");
      renderBars(document.getElementById("vsp_ds_paths"), (j.top_paths||[]).map(x=>({path:x.path, count:x.count})), "path");

      const hint = document.getElementById("vsp_ds_hint");
      if(hint){
        hint.innerHTML = `Tip: click-to-filter can be wired later by passing filters into existing table loader (tool/severity/rule/path).`;
      }
    }catch(e){
      console.warn("[DS_AGG] failed:", e);
      setText("vsp_ds_status", "Agg load failed. Check safe API patch / restart.");
    }
  }

  function hook(){
    const btn = document.getElementById("vsp_ds_reload");
    if(btn && !btn.__hooked){
      btn.__hooked = true;
      btn.addEventListener("click", loadAgg);
    }
    setTimeout(loadAgg, 120);
  }

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", hook);
  else hook();
})();
JS
echo "[OK] created $JS_NEW"
else
echo "[OK] exists $JS_NEW"
fi

# find a template to patch (contains '/data_source')
TPL=""
if [ -d "$TPL_DIR" ]; then
  TPL="$(grep -RIl --exclude='*.bak_*' '/data_source' "$TPL_DIR" | head -n1 || true)"
fi

if [ -z "${TPL:-}" ]; then
  echo "[WARN] cannot auto-detect data_source template (no /data_source string)."
  echo "[HINT] Provide the template file used for /data_source, then patch that file."
  exit 0
fi

cp -f "$TPL" "${TPL}.bak_p2_ds_strip_fix_${TS}"
echo "[BACKUP] ${TPL}.bak_p2_ds_strip_fix_${TS}"

python3 - <<PY
from pathlib import Path
import re, textwrap

tpl_path = Path("$TPL")
s = tpl_path.read_text(encoding="utf-8", errors="replace")

strip = textwrap.dedent(r"""
<!-- ===================== VSP_P2_DATA_SOURCE_STRIP_V1 ===================== -->
<section class="vsp-card" id="vsp_ds_strip" style="margin:14px 0 10px 0;">
  <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
    <div style="display:flex;flex-direction:column;gap:2px;">
      <div style="font-weight:700;font-size:16px;letter-spacing:.2px;">Data Source — Triage Overview</div>
      <div style="opacity:.75;font-size:12px;" id="vsp_ds_status">RID: —</div>
    </div>
    <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;">
      <label style="font-size:12px;opacity:.8;">RID</label>
      <input id="vsp_ds_rid" class="vsp-input" placeholder="RUN_YYYYmmdd_HHMMSS" style="min-width:260px;"/>
      <button id="vsp_ds_reload" class="vsp-btn" type="button">Reload</button>
    </div>
  </div>

  <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:10px;">
    <div class="vsp-card" style="padding:10px;">
      <div style="font-weight:700;font-size:13px;margin-bottom:6px;">Severity distribution (6 levels)</div>
      <div id="vsp_ds_sev"></div>
    </div>
    <div class="vsp-card" style="padding:10px;">
      <div style="font-weight:700;font-size:13px;margin-bottom:6px;">Findings by tool (top)</div>
      <div id="vsp_ds_tools"></div>
    </div>
  </div>

  <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:10px;">
    <div class="vsp-card" style="padding:10px;">
      <div style="font-weight:700;font-size:13px;margin-bottom:6px;">Top rules</div>
      <div id="vsp_ds_rules"></div>
    </div>
    <div class="vsp-card" style="padding:10px;">
      <div style="font-weight:700;font-size:13px;margin-bottom:6px;">Hot paths</div>
      <div id="vsp_ds_paths"></div>
    </div>
  </div>

  <div style="opacity:.75;font-size:12px;margin-top:8px;" id="vsp_ds_hint"></div>
</section>
<!-- ===================== /VSP_P2_DATA_SOURCE_STRIP_V1 ===================== -->
""").strip()

# 1) Insert strip if missing
if "VSP_P2_DATA_SOURCE_STRIP_V1" not in s:
    if re.search(r"(?is)<main[^>]*>", s):
        s = re.sub(r"(?is)(<main[^>]*>)", r"\1\n"+strip+"\n", s, count=1)
    else:
        s = strip + "\n" + s

# 2) Ensure script include
inc = '<script src="/static/js/vsp_data_source_charts_v1.js"></script>'
if "vsp_data_source_charts_v1.js" not in s:
    if "</body>" in s.lower():
        s = re.sub(r"(?is)</body>", "\n"+inc+"\n</body>", s, count=1)
    else:
        s = s + "\n" + inc + "\n"

tpl_path.write_text(s, encoding="utf-8")
print("[OK] patched template:", tpl_path)
PY

node --check "$JS_NEW" && echo "[OK] node --check OK"

echo "[DONE] p2_data_source_charts_strip_v1_fix_v1"
