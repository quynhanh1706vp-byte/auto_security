#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 1) find Data Source template (best-effort)
TPL="$(python3 - <<'PY'
from pathlib import Path
cands = []
for p in Path("templates").glob("*.html"):
    name = p.name.lower()
    if "data_source" in name:
        cands.append(p)
# fallback: grep content
if not cands:
    for p in Path("templates").glob("*.html"):
        try:
            s = p.read_text(encoding="utf-8", errors="replace").lower()
        except Exception:
            continue
        if "data_source" in s and ("findings" in s or "datasource" in s or "data source" in s):
            cands.append(p)
cands = sorted(set(cands), key=lambda x: x.name)
print(str(cands[0]) if cands else "")
PY
)"
[ -n "$TPL" ] || { echo "[ERR] cannot find data source template in templates/*.html"; exit 2; }
echo "[INFO] TPL=$TPL"
cp -f "$TPL" "${TPL}.bak_pagination_${TS}"
echo "[BACKUP] ${TPL}.bak_pagination_${TS}"

# 2) create JS file (new) for pagination overlay
JS_NEW="static/js/vsp_data_source_pagination_v1.js"
mkdir -p static/js
cat > "$JS_NEW" <<'JS'
/* VSP_P1_DATA_SOURCE_PAGINATION_V1 (limit/offset; avoid rendering 100k findings) */
(()=> {
  try{
    if (window.__vsp_p1_data_source_pagination_v1) return;
    window.__vsp_p1_data_source_pagination_v1 = true;

    const API_BASE = "/api/ui/findings_v3";
    const DEF_LIMIT = 200;

    function qs(k){
      try{ return new URLSearchParams(location.search).get(k) || ""; }catch(_){ return ""; }
    }
    function esc(s){
      return String(s??"").replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    }
    function pickTotal(d){
      return (d && (d.total ?? d.TOTAL ?? d.count ?? d.total_count ?? d.items_total)) ?? null;
    }
    function pickItems(d){
      const items = d && (d.items ?? d.findings ?? d.data ?? d.rows);
      return Array.isArray(items) ? items : [];
    }

    function pickRid(){
      // priority: query string
      const qrid = qs("rid");
      if (qrid) return qrid;

      // common DOM hooks
      const el = document.querySelector("[data-rid]") || document.querySelector("#rid") || document.querySelector("input[name='rid']") || document.querySelector("select[name='rid']");
      if (el){
        const v = el.getAttribute("data-rid") || el.value || el.textContent || "";
        return String(v||"").trim();
      }

      // try from page text: RUN_...
      const m = (document.body && document.body.textContent) ? document.body.textContent.match(/RUN_\d{8}_\d{6}/) : null;
      return m ? m[0] : "";
    }

    function ensureHost(){
      // find a reasonable container
      const host = document.querySelector("#data_source, [data-page='data_source'], [data-tab='data_source'], main, .main, body") || document.body;

      let box = document.getElementById("VSP_P1_DS_PAGER");
      if (!box){
        box = document.createElement("div");
        box.id = "VSP_P1_DS_PAGER";
        box.style.cssText = "margin:10px 0 14px 0; padding:10px; border:1px solid rgba(255,255,255,.10); border-radius:12px; background:rgba(255,255,255,.04);";
        box.innerHTML = `
          <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;justify-content:space-between;">
            <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;">
              <span style="opacity:.85;font-size:12px;">Data Source</span>
              <span style="font-size:12px;opacity:.85;">RID:</span>
              <input id="VSP_DS_RID" style="min-width:260px; padding:6px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.20); color:#eaeaea" placeholder="RUN_YYYYmmdd_HHMMSS" />
              <span style="font-size:12px;opacity:.85;">Page size:</span>
              <select id="VSP_DS_LIMIT" style="padding:6px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background:rgba(0,0,0,.20); color:#eaeaea">
                <option>100</option><option selected>200</option><option>500</option><option>1000</option>
              </select>
              <button id="VSP_DS_PREV" style="padding:6px 12px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background:rgba(255,255,255,.06); color:#eaeaea; cursor:pointer;">Prev</button>
              <button id="VSP_DS_NEXT" style="padding:6px 12px; border-radius:10px; border:1px solid rgba(255,255,255,.12); background:rgba(255,255,255,.06); color:#eaeaea; cursor:pointer;">Next</button>
              <button id="VSP_DS_LOAD" style="padding:6px 12px; border-radius:10px; border:1px solid rgba(120,200,255,.25); background:rgba(120,200,255,.10); color:#eaeaea; cursor:pointer;">Load</button>
            </div>
            <div id="VSP_DS_STAT" style="font-size:12px;opacity:.85;">offset=0 limit=${DEF_LIMIT} total=?</div>
          </div>
          <div style="height:10px"></div>
          <div style="overflow:auto; border-radius:12px; border:1px solid rgba(255,255,255,.08);">
            <table style="width:100%; border-collapse:collapse; font-size:12px;">
              <thead>
                <tr style="background:rgba(255,255,255,.04); text-align:left;">
                  <th style="padding:8px 10px; white-space:nowrap;">Severity</th>
                  <th style="padding:8px 10px; white-space:nowrap;">Tool</th>
                  <th style="padding:8px 10px; white-space:nowrap;">Rule</th>
                  <th style="padding:8px 10px;">File</th>
                  <th style="padding:8px 10px; white-space:nowrap;">Line</th>
                  <th style="padding:8px 10px;">Message</th>
                </tr>
              </thead>
              <tbody id="VSP_DS_TBODY"></tbody>
            </table>
          </div>
        `;
        // insert near top of host
        host.insertBefore(box, host.firstChild);
      }
      return box;
    }

    function render(items){
      const tb = document.getElementById("VSP_DS_TBODY");
      if (!tb) return;
      tb.innerHTML = "";
      for (const it of items){
        const sev = (it.severity ?? it.sev ?? it.level ?? it.norm_severity ?? it.severity_norm ?? "").toString();
        const tool = (it.tool ?? it.engine ?? it.scanner ?? "").toString();
        const rule = (it.rule_id ?? it.rule ?? it.check_id ?? it.id ?? it.cwe ?? "").toString();
        const file = (it.file ?? it.path ?? it.file_path ?? it.location?.path ?? it.artifact?.uri ?? "").toString();
        const line = (it.line ?? it.location?.line ?? it.start_line ?? it.region?.startLine ?? "").toString();
        const msg = (it.message ?? it.title ?? it.name ?? it.desc ?? it.description ?? it.snippet ?? "").toString();
        const tr = document.createElement("tr");
        tr.style.cssText = "border-top:1px solid rgba(255,255,255,.06);";
        tr.innerHTML = `
          <td style="padding:7px 10px; white-space:nowrap;">${esc(sev)}</td>
          <td style="padding:7px 10px; white-space:nowrap; opacity:.9;">${esc(tool)}</td>
          <td style="padding:7px 10px; white-space:nowrap; opacity:.9;">${esc(rule)}</td>
          <td style="padding:7px 10px; opacity:.9;">${esc(file)}</td>
          <td style="padding:7px 10px; white-space:nowrap; opacity:.9;">${esc(line)}</td>
          <td style="padding:7px 10px;">${esc(msg)}</td>
        `;
        tb.appendChild(tr);
      }
    }

    async function loadPage(offset){
      const box = ensureHost();
      const ridEl = document.getElementById("VSP_DS_RID");
      const limEl = document.getElementById("VSP_DS_LIMIT");
      const stat = document.getElementById("VSP_DS_STAT");

      const rid = String((ridEl && ridEl.value) ? ridEl.value : pickRid()).trim();
      const limit = parseInt((limEl && limEl.value) ? limEl.value : DEF_LIMIT, 10) || DEF_LIMIT;

      if (ridEl && !ridEl.value) ridEl.value = rid;

      if (!rid){
        if (stat) stat.textContent = "RID missing (add ?rid=RUN_... or paste into RID box)";
        return;
      }

      const url = `${API_BASE}?rid=${encodeURIComponent(rid)}&limit=${encodeURIComponent(limit)}&offset=${encodeURIComponent(offset)}`;
      if (stat) stat.textContent = `loading... rid=${rid} offset=${offset} limit=${limit}`;

      const resp = await fetch(url, { credentials: "same-origin" });
      if (!resp.ok){
        if (stat) stat.textContent = `HTTP ${resp.status} when GET ${url}`;
        return;
      }
      const d = await resp.json().catch(()=> ({}));
      const total = pickTotal(d);
      const items = pickItems(d);

      render(items);

      const totalTxt = (total===null || typeof total==="undefined") ? "?" : String(total);
      if (stat) stat.textContent = `rid=${rid} offset=${offset} limit=${limit} total=${totalTxt} showing=${items.length}`;

      // persist
      window.__vsp_ds_page_v1 = { rid, offset, limit, total };
    }

    function wire(){
      ensureHost();
      const ridEl = document.getElementById("VSP_DS_RID");
      const limEl = document.getElementById("VSP_DS_LIMIT");
      const prev = document.getElementById("VSP_DS_PREV");
      const next = document.getElementById("VSP_DS_NEXT");
      const load = document.getElementById("VSP_DS_LOAD");

      if (ridEl){
        const rid = pickRid();
        if (rid) ridEl.value = rid;
      }

      let st = window.__vsp_ds_page_v1 || { offset: 0, limit: DEF_LIMIT };

      function cur(){ return window.__vsp_ds_page_v1 || st; }

      prev && prev.addEventListener("click", ()=> {
        const c = cur();
        const off = Math.max(0, (c.offset||0) - (c.limit||DEF_LIMIT));
        loadPage(off);
      });
      next && next.addEventListener("click", ()=> {
        const c = cur();
        const off = (c.offset||0) + (c.limit||DEF_LIMIT);
        loadPage(off);
      });
      load && load.addEventListener("click", ()=> loadPage((cur().offset||0)));

      limEl && limEl.addEventListener("change", ()=> loadPage(0));
      ridEl && ridEl.addEventListener("keydown", (e)=> {
        if (e.key === "Enter") loadPage(0);
      });

      // initial
      loadPage(0);
    }

    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", wire);
    } else {
      wire();
    }
  }catch(e){
    console && console.warn && console.warn("VSP_P1_DATA_SOURCE_PAGINATION_V1 failed:", e);
  }
})();
JS

# 3) inject script include into template if not present
python3 - <<'PY'
from pathlib import Path
import re

tpl = Path(r"""'"$TPL"'''""")
s = tpl.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DATA_SOURCE_PAGINATION_V1"
if marker in s:
    print("[OK] template already patched (marker).")
    raise SystemExit(0)

# Try insert before </body>, else before </html>, else append
script_tag = '\n<!-- VSP_P1_DATA_SOURCE_PAGINATION_V1 -->\n<script src="/static/js/vsp_data_source_pagination_v1.js?v={{ asset_v }}"></script>\n'
if "</body>" in s:
    s = s.replace("</body>", script_tag + "\n</body>")
elif "</html>" in s:
    s = s.replace("</html>", script_tag + "\n</html>")
else:
    s += script_tag

tpl.write_text(s, encoding="utf-8")
print("[OK] patched template:", tpl)
PY

echo "[OK] wrote $JS_NEW"
echo "[OK] injected JS include into $TPL"
echo "== sanity grep =="
grep -n "VSP_P1_DATA_SOURCE_PAGINATION_V1" -n "$TPL" | head -n 5 || true

echo "[NEXT] restart UI then open /data_source?rid=RUN_... (or paste RID in the box)."
