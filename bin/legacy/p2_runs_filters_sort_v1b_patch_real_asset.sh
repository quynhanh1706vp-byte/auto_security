#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need grep; need head
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

tmp="$(mktemp -d /tmp/vsp_runs_patch_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

echo "== [1] fetch /runs HTML and extract served JS assets =="
curl -fsS "$BASE/runs" -o "$tmp/runs.html"

python3 - "$tmp/runs.html" > "$tmp/assets.txt" <<'PY'
import re,sys
h=open(sys.argv[1],'r',encoding='utf-8',errors='replace').read()
assets=sorted(set(re.findall(r'(/static/js/[^"\']+?\.js)(?:\?[^"\']*)?', h)))
for a in assets:
    print(a)
PY

echo "[INFO] JS assets:"
sed 's/^/  - /' "$tmp/assets.txt" || true
echo

echo "== [2] choose best candidate (contains 'runs' in filename OR contains runs markers in content) =="
CAND_URL=""
while read -r a; do
  [ -z "${a:-}" ] && continue
  b="$(basename "$a")"
  if echo "$b" | grep -qiE 'runs'; then
    CAND_URL="$a"
    break
  fi
done < "$tmp/assets.txt"

if [ -z "${CAND_URL:-}" ]; then
  # fallback: download each and find marker
  while read -r a; do
    [ -z "${a:-}" ] && continue
    curl -fsS "$BASE$a" -o "$tmp/asset.js" || continue
    if grep -qE 'location\.pathname.*runs|/runs\?limit|vsp-tab-runs|Runs & Reports' "$tmp/asset.js"; then
      CAND_URL="$a"
      break
    fi
  done < "$tmp/assets.txt"
fi

[ -n "${CAND_URL:-}" ] || { echo "[ERR] cannot find served runs-related JS from /runs"; exit 2; }

echo "[OK] selected asset URL: $CAND_URL"

echo "== [3] map URL -> local file path =="
# most setups serve from ./static/js/<name>.js
CAND_FILE="static/js/$(basename "$CAND_URL")"
[ -f "$CAND_FILE" ] || {
  echo "[WARN] $CAND_FILE not found locally; searching by basename..."
  found="$(find static/js -maxdepth 2 -type f -name "$(basename "$CAND_URL")" ! -name '*.bak_*' | head -n 1 || true)"
  [ -n "${found:-}" ] || { echo "[ERR] cannot locate local file for $(basename "$CAND_URL")"; exit 2; }
  CAND_FILE="$found"
}
echo "[OK] local file: $CAND_FILE"

echo "== [4] backup + patch inject filters/sort/search (marker protected) =="
cp -f "$CAND_FILE" "${CAND_FILE}.bak_runsfilters_real_${TS}"
echo "[BACKUP] ${CAND_FILE}.bak_runsfilters_real_${TS}"

python3 - "$CAND_FILE" <<'PY'
import sys, textwrap
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_RUNS_FILTERS_SORT_V1B"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=textwrap.dedent(r"""
/* VSP_P2_RUNS_FILTERS_SORT_V1B (real asset) */
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
  function isRuns(){ return String(location.pathname||"").includes("/runs"); }

  function findRoot(){
    return document.querySelector('[data-testid="vsp-runs-main"]') || document.body;
  }

  function mount(root, onChange){
    let bar=document.querySelector('[data-testid="runs-filterbar"]');
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
    lim.innerHTML = `<option>20</option><option selected>50</option><option>100</option>`;

    const btn=el('button', {'data-testid':'runs-refresh'}, 'Refresh');
    btn.style.cssText="padding:9px 12px;border-radius:12px;border:1px solid rgba(255,255,255,0.12);background:rgba(255,255,255,0.04);color:inherit;cursor:pointer";
    btn.onmouseenter=()=>btn.style.background="rgba(255,255,255,0.06)";
    btn.onmouseleave=()=>btn.style.background="rgba(255,255,255,0.04)";

    bar.appendChild(q); bar.appendChild(sort); bar.appendChild(lim); bar.appendChild(btn);
    root.prepend(bar);

    function fire(){ onChange({q:q.value||"", sort:sort.value, limit:+lim.value}); }
    q.addEventListener("input", fire);
    sort.addEventListener("change", fire);
    lim.addEventListener("change", fire);
    btn.addEventListener("click", fire);
    return bar;
  }

  function render(root, runs){
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
      <div style="opacity:.7;margin-top:8px">Tip: click a RID row to copy RID.</div>
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

  async function main(){
    const root=findRoot();
    mount(root, async (st)=>{
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
      render(root, out);
    });
    document.querySelector('[data-testid="runs-refresh"]')?.click();
  }

  if(isRuns()){
    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", main);
    else main();
  }
})();
""")

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] injected runs filterbar into REAL served JS")
PY

echo "== [5] restart service =="
if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

echo "== [6] runtime check: served JS contains marker =="
curl -fsS "$BASE$CAND_URL" | grep -n "VSP_P2_RUNS_FILTERS_SORT_V1B" | head -n 2 || echo "[ERR] marker not found in served JS"
