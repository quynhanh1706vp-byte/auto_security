#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need date; need grep; need head
command -v node >/dev/null 2>&1 || { echo "[ERR] missing node"; exit 2; }
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
tmp="$(mktemp -d /tmp/vsp_ds_patch_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

echo "== [1] fetch /data_source HTML and extract served JS assets =="
curl -fsS "$BASE/data_source" -o "$tmp/page.html"
grep -oE '/static/js/[^"'"'"']+\.js' "$tmp/page.html" | sort -u > "$tmp/js.txt" || true
echo "[INFO] JS assets:"
sed 's/^/  - /' "$tmp/js.txt" || true

echo "== [2] choose best candidate (prefer data_source/findings/table) =="
best=""
while read -r u; do
  [ -z "$u" ] && continue
  if echo "$u" | grep -qiE 'data|source|findings|table|grid|ds'; then
    best="$u"; break
  fi
done < "$tmp/js.txt"
if [ -z "$best" ]; then best="$(head -n 1 "$tmp/js.txt" || true)"; fi
[ -n "$best" ] || { echo "[ERR] no JS asset found on /data_source"; exit 2; }
echo "[OK] selected asset URL: $best"

echo "== [3] map URL -> local file =="
local="static/js/$(basename "$best")"
[ -f "$local" ] || { echo "[ERR] local file not found: $local"; exit 2; }
echo "[OK] local file: $local"

echo "== [4] backup + patch (marker protected) =="
cp -f "$local" "${local}.bak_dsdeep_${TS}"
echo "[BACKUP] ${local}.bak_dsdeep_${TS}"

python3 - "$local" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P2_DATA_SOURCE_DEEP_DIVE_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=r'''
/* VSP_P2_DATA_SOURCE_DEEP_DIVE_V1 */
(function(){
  function el(tag, attrs, html){
    const e=document.createElement(tag);
    if(attrs){ for(const k of Object.keys(attrs)) e.setAttribute(k, attrs[k]); }
    if(html!==undefined) e.innerHTML=html;
    return e;
  }
  async function jget(url){
    const r=await fetch(url, {credentials:"same-origin"});
    return await r.json();
  }
  async function ensureRid(){
    const qp=new URLSearchParams(location.search);
    let rid=qp.get("rid");
    if(rid) return rid;
    try{
      const j=await jget("/api/vsp/rid_latest");
      if(j && j.rid){
        qp.set("rid", j.rid);
        history.replaceState({}, "", location.pathname + "?" + qp.toString());
        return j.rid;
      }
    }catch(e){}
    return "";
  }
  function rawUrl(rid, path, download){
    const u=new URL("/api/vsp/run_file_raw_v4", location.origin);
    u.searchParams.set("rid", rid);
    u.searchParams.set("path", path);
    if(download) u.searchParams.set("download", "1");
    return u.toString();
  }
  async function loadFindings(rid, limit){
    const u=new URL("/api/vsp/run_file_allow", location.origin);
    u.searchParams.set("rid", rid);
    u.searchParams.set("path", "findings_unified.json");
    u.searchParams.set("limit", String(limit||300));
    return await jget(u.toString());
  }
  function applyFilter(all, q){
    q=(q||"").trim().toLowerCase();
    if(!q) return all;
    return (all||[]).filter(it=>{
      const s=[it.tool,it.severity,it.title,it.file,it.rule,it.cwe].filter(Boolean).join(" ").toLowerCase();
      return s.includes(q);
    });
  }
  function render(host, rows){
    host.innerHTML="";
    const table=el("table", {class:"vsp-table vsp-table-ds", "data-testid":"vsp-ds-table"});
    const thead=el("thead", null, "<tr><th>Tool</th><th>Sev</th><th>Title</th><th>File</th></tr>");
    const tbody=el("tbody");
    (rows||[]).forEach((it, idx)=>{
      const tr=el("tr", {"data-idx":String(idx)});
      tr.style.cursor="pointer";
      tr.appendChild(el("td", null, (it.tool||"")));
      tr.appendChild(el("td", null, (it.severity||"")));
      tr.appendChild(el("td", null, (it.title||"")));
      tr.appendChild(el("td", null, (it.file||"")));
      tr.onclick=()=>{ alert((it.title||"(no title)") + "\n\n" + (it.file||"") ); };
      tbody.appendChild(tr);
    });
    table.appendChild(thead); table.appendChild(tbody);
    host.appendChild(table);
  }

  document.addEventListener("DOMContentLoaded", async ()=>{
    if(!location.pathname.includes("data_source")) return;
    const rid=await ensureRid();

    const root=document.querySelector('[data-testid="vsp-datasource-main"]') || document.body;
    const bar=el("div", {"data-testid":"vsp-ds-toolbar", class:"vsp-ds-toolbar"});
    const stat=el("div", {"data-testid":"vsp-ds-stat", class:"vsp-ds-stat"}, rid?("RID: "+rid):"RID: (none)");
    const q=el("input", {type:"search", placeholder:"Search findings…", "data-testid":"vsp-ds-search"});
    const btnLoad=el("button", {"data-testid":"vsp-ds-load"}, "Load");
    const btnOpen=el("button", {"data-testid":"vsp-ds-open-raw"}, "Open raw findings_unified.json");
    const btnDl=el("button", {"data-testid":"vsp-ds-dl-raw"}, "Download raw findings_unified.json");
    bar.appendChild(stat); bar.appendChild(q); bar.appendChild(btnLoad); bar.appendChild(btnOpen); bar.appendChild(btnDl);

    const host=el("div", {"data-testid":"vsp-ds-host", class:"vsp-ds-host"});
    root.prepend(host);
    root.prepend(bar);

    let allRows=[];
    async function refresh(){
      render(host, applyFilter(allRows, q.value));
    }

    btnOpen.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      window.open(rawUrl(r, "findings_unified.json", false), "_blank", "noopener");
    };
    btnDl.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      window.open(rawUrl(r, "findings_unified.json", true), "_blank", "noopener");
    };
    btnLoad.onclick=async ()=>{
      const r=await ensureRid();
      if(!r) return alert("RID missing");
      host.textContent="Loading…";
      try{
        const j=await loadFindings(r, 300);
        const arr=(j && (j.findings||j.items||j.data)) || [];
        allRows=Array.isArray(arr)?arr:[];
        await refresh();
      }catch(e){
        host.textContent="Load failed";
      }
    };
    q.addEventListener("input", refresh);
  });
})();
'''
p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended deep-dive v1")
PY

node -c "$local"
echo "[OK] node -c OK"
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"
echo "== done =="
