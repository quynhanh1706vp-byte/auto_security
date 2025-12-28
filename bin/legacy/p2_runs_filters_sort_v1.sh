#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need head
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [1] detect runs JS =="
CAND="$(grep -RIn --line-number -E 'vsp-tab-runs|/runs\b|Runs & Reports' static/js \
  --exclude='*.bak_*' --exclude='*.disabled_*' 2>/dev/null \
  | head -n 1 | awk -F: '{print $1}' || true)"

[ -n "${CAND:-}" ] || { echo "[ERR] cannot find runs js candidate"; exit 2; }
echo "[OK] candidate=$CAND"

cp -f "$CAND" "${CAND}.bak_runsfilters_${TS}"
echo "[BACKUP] ${CAND}.bak_runsfilters_${TS}"

python3 - "$CAND" <<'PY'
import sys, textwrap
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_RUNS_FILTERS_SORT_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=textwrap.dedent(r"""
/* VSP_P2_RUNS_FILTERS_SORT_V1 */
(function(){
  function esc(s){ return String(s??"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c])); }
  function el(tag, attrs, html){
    const e=document.createElement(tag);
    if(attrs){ for(const k of Object.keys(attrs)) e.setAttribute(k, attrs[k]); }
    if(html!==undefined) e.innerHTML=html;
    return e;
  }
  async function jget(url){
    const r=await fetch(url, {credentials:"same-origin"});
    const t=await r.text();
    try { return {ok:true, json: JSON.parse(t)}; } catch(e){ return {ok:false, text:t}; }
  }

  function findRunsRoot(){
    return document.querySelector('[data-testid="vsp-runs-main"]') || document.body;
  }

  function mountFilterBar(root, onChange){
    let bar=root.querySelector('[data-testid="runs-filterbar"]');
    if(bar) return bar;

    bar=el('div', {'data-testid':'runs-filterbar'});
    bar.style.cssText="max-width:1200px;margin:12px auto 8px auto;padding:0 12px;display:flex;gap:10px;flex-wrap:wrap;align-items:center";

    const q=el('input', {'data-testid':'runs-q', 'placeholder':'Search RID…'});
    q.style.cssText="flex:1;min-width:220px;padding:9px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);color:inherit";

    const sort=el('select', {'data-testid':'runs-sort'});
    sort.style.cssText="padding:9px 10px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);color:inherit";
    sort.innerHTML = `
      <option value="ts_desc">Newest</option>
      <option value="ts_asc">Oldest</option>
      <option value="rid_asc">RID A→Z</option>
      <option value="rid_desc">RID Z→A</option>
    `;

    const lim=el('select', {'data-testid':'runs-limit'});
    lim.style.cssText=sort.style.cssText;
    lim.innerHTML = `<option>20</option><option>50</option><option>100</option>`;

    const btn=el('button', {'data-testid':'runs-refresh'}, 'Refresh');
    btn.style.cssText="padding:9px 12px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);color:inherit;cursor:pointer";
    btn.onmouseenter=()=>btn.style.background="rgba(255,255,255,0.06)";
    btn.onmouseleave=()=>btn.style.background="rgba(255,255,255,0.04)";

    bar.appendChild(q); bar.appendChild(sort); bar.appendChild(lim); bar.appendChild(btn);
    root.prepend(bar);

    function fire(){ onChange({q:q.value||"", sort:sort.value, limit:+lim.value}); }
    q.addEventListener("input", ()=>fire());
    sort.addEventListener("change", ()=>fire());
    lim.addEventListener("change", ()=>fire());
    btn.addEventListener("click", ()=>fire());

    return bar;
  }

  function renderTable(root, runs){
    let host=document.querySelector('[data-testid="runs-table-host"]');
    if(!host){
      host=el('div', {'data-testid':'runs-table-host'});
      host.style.cssText="max-width:1200px;margin:0 auto;padding:0 12px 18px 12px;";
      root.appendChild(host);
    }

    if(!runs || !runs.length){
      host.innerHTML = `<div style="opacity:.8;padding:14px;border:1px solid rgba(255,255,255,0.10);border-radius:14px;background:rgba(255,255,255,0.03)">No runs</div>`;
      return;
    }

    const rows=runs.map(r=>{
      const rid=esc(r.rid||r.run_id||"");
      const ts=esc(r.ts||r.created_ts||"");
      const rootDir=esc(r.root||"");
      return `<tr data-rid="${rid}">
        <td style="padding:10px 12px;font-weight:700;white-space:nowrap">${rid}</td>
        <td style="padding:10px 12px;opacity:.85;white-space:nowrap">${ts}</td>
        <td style="padding:10px 12px;opacity:.75;max-width:520px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${rootDir}</td>
      </tr>`;
    }).join("");

    host.innerHTML = `
      <div style="border:1px solid rgba(255,255,255,0.10);border-radius:14px;overflow:hidden;background:rgba(255,255,255,0.03)">
        <table style="width:100%;border-collapse:separate;border-spacing:0;font-size:13px">
          <thead>
            <tr style="text-align:left;opacity:.75;background:rgba(15,18,24,0.92)">
              <th style="padding:10px 12px;border-bottom:1px solid rgba(255,255,255,0.10)">RID</th>
              <th style="padding:10px 12px;border-bottom:1px solid rgba(255,255,255,0.10)">Time</th>
              <th style="padding:10px 12px;border-bottom:1px solid rgba(255,255,255,0.10)">Root</th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
      </div>
      <div data-testid="runs-hint" style="opacity:.7;margin-top:8px">Tip: click a RID row to copy RID.</div>
    `;

    host.querySelectorAll("tbody tr").forEach(tr=>{
      tr.style.cursor="pointer";
      tr.style.transition="background 120ms ease";
      tr.onmouseenter=()=>tr.style.background="rgba(255,255,255,0.05)";
      tr.onmouseleave=()=>tr.style.background="transparent";
      tr.onclick=()=>{
        const rid=tr.getAttribute("data-rid")||"";
        if(rid) navigator.clipboard?.writeText(rid).catch(()=>{});
      };
    });
  }

  async function run(){
    const root=findRunsRoot();
    mountFilterBar(root, async (st)=>{
      const lim=st.limit||50;
      const res=await jget(`/api/vsp/runs?limit=${encodeURIComponent(lim)}&offset=0`);
      const runs=(res.ok && res.json && res.json.runs) ? res.json.runs : [];
      const q=(st.q||"").toLowerCase().trim();

      let out=runs;
      if(q) out=out.filter(r=>String(r.rid||r.run_id||"").toLowerCase().includes(q));

      const sort=st.sort||"ts_desc";
      out=[...out].sort((a,b)=>{
        const ar=String(a.rid||a.run_id||"");
        const br=String(b.rid||b.run_id||"");
        const at=String(a.ts||a.created_ts||"");
        const bt=String(b.ts||b.created_ts||"");
        if(sort==="rid_asc") return ar.localeCompare(br);
        if(sort==="rid_desc") return br.localeCompare(ar);
        if(sort==="ts_asc") return at.localeCompare(bt);
        return bt.localeCompare(at);
      });

      renderTable(root, out);
    });

    // initial render
    const bar=root.querySelector('[data-testid="runs-filterbar"]');
    const q=bar?.querySelector('[data-testid="runs-q"]');
    const sort=bar?.querySelector('[data-testid="runs-sort"]');
    const lim=bar?.querySelector('[data-testid="runs-limit"]');
    const st={q:q?.value||"", sort:sort?.value||"ts_desc", limit:+(lim?.value||50)};
    bar?.querySelector('[data-testid="runs-refresh"]')?.click();
  }

  // Only run on /runs (avoid affecting other tabs)
  if(String(location.pathname||"").includes("/runs")){
    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", run);
    else run();
  }
})();
""")

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] patched runs js")
PY

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

echo "== verify served /runs contains filterbar testid (HTML) =="
curl -fsS "$BASE/runs" | grep -o 'runs-filterbar' | head -n 1 || echo "[WARN] filterbar marker not in HTML (it is injected by JS at runtime)"
