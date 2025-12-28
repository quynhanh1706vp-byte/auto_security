#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need curl; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] ensure run_file_allow allows findings_unified.json (patch allowlist) =="
PYFILES=(vsp_demo_app.py wsgi_vsp_ui_gateway.py)
FOUND=0
for f in "${PYFILES[@]}"; do
  if [ -f "$f" ]; then FOUND=1; break; fi
done
[ "$FOUND" -eq 1 ] || { echo "[ERR] cannot find vsp_demo_app.py or wsgi_vsp_ui_gateway.py in ui/"; exit 2; }

python3 - <<'PY'
from pathlib import Path
import time

cands = [Path("vsp_demo_app.py"), Path("wsgi_vsp_ui_gateway.py")]
cands = [p for p in cands if p.exists()]
MARK="VSP_P0_ALLOW_FINDINGS_UNIFIED_JSON_V1B"

for p in cands:
    s = p.read_text(encoding="utf-8", errors="replace")
    if "run_file_allow" not in s:
        continue
    if "findings_unified.json" in s:
        print("[OK] already contains findings_unified.json:", p)
        continue

    if "run_gate_summary.json" in s:
        bk = Path(str(p) + f".bak_allowjson_{int(time.time())}")
        bk.write_text(s, encoding="utf-8")
        # inject paths right after run_gate_summary.json (robust simple replace)
        s2 = s
        s2 = s2.replace('"run_gate_summary.json"', '"run_gate_summary.json","findings_unified.json","reports/findings_unified.csv","reports/findings_unified.sarif"')
        s2 = s2.replace("'run_gate_summary.json'", "'run_gate_summary.json','findings_unified.json','reports/findings_unified.csv','reports/findings_unified.sarif'")
        if s2 == s:
            print("[WARN] replace did not change file (unexpected) -> skip:", p)
            continue
        # add marker comment once
        if MARK not in s2:
            s2 = s2 + f"\n# {MARK}\n"
        p.write_text(s2, encoding="utf-8")
        print("[OK] patched allowlist in:", p, "backup:", bk)
    else:
        print("[WARN] no run_gate_summary.json token to anchor allowlist patch in:", p)
PY

python3 -m py_compile vsp_demo_app.py 2>/dev/null || true
python3 -m py_compile wsgi_vsp_ui_gateway.py 2>/dev/null || true

echo "== [1] patch JS (emergency JSON-only override handler) =="
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
cp -f "$JS" "${JS}.bak_topfind_emgjson_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_emgjson_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P0_TOPFIND_EMERGENCY_JSON_ONLY_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block = textwrap.dedent(r"""
    /* VSP_P0_TOPFIND_EMERGENCY_JSON_ONLY_V1
       Force override click handler (clone button) + load ONLY from findings_unified.json
       This bypasses CSV/SARIF exporter issues completely.
    */
    (()=> {
      if (window.__vsp_topfind_emg_json_only_v1) return;
      window.__vsp_topfind_emg_json_only_v1 = true;

      const RID_LATEST = "/api/vsp/rid_latest_gate_root";
      const PATH_JSON  = "findings_unified.json";
      const SEV_W = {CRITICAL:600,HIGH:500,MEDIUM:400,LOW:300,INFO:200,TRACE:100};
      const norm  = (v)=> (v==null ? "" : String(v)).trim();
      const upper = (v)=> norm(v).toUpperCase();

      function normSev(v){
        const x = upper(v);
        if (SEV_W[x]) return x;
        if (x==="ERROR") return "HIGH";
        if (x==="WARNING"||x==="WARN") return "MEDIUM";
        if (x==="NOTE") return "LOW";
        if (x==="DEBUG") return "TRACE";
        return x || "INFO";
      }

      async function getRidLatest(){
        const r = await fetch(RID_LATEST, {cache:"no-store"});
        if (!r.ok) throw new Error("rid_latest_gate_root http " + r.status);
        const j = await r.json();
        return j && j.rid ? String(j.rid) : "";
      }
      function rfUrl(rid, path){
        return `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
      }

      function findTopCard(){
        const nodes = Array.from(document.querySelectorAll("div,section,article"));
        for (const n of nodes){
          const t = (n.textContent || "").toLowerCase();
          if (t.includes("top findings")) return n;
        }
        return null;
      }
      function findButton(){
        const btns = Array.from(document.querySelectorAll("button"));
        for (const b of btns){
          const t = (b.textContent || "").toLowerCase().replace(/\s+/g," ").trim();
          if (t.includes("load top findings")) return b;
        }
        return null;
      }
      function findTbody(){
        const card = findTopCard();
        if (card){
          const tb = card.querySelector("tbody");
          if (tb) return tb;
        }
        return document.querySelector("tbody");
      }
      function setStatus(msg){
        const card = findTopCard();
        if (!card) return;
        const cells = Array.from(card.querySelectorAll("td,div,span,p"));
        for (const c of cells){
          const t = (c.textContent || "").toLowerCase().trim();
          if (t === "not loaded" || t === "loading..." || t === "loading…" || t.startsWith("load failed") || t.startsWith("loaded:")){
            c.textContent = msg;
            return;
          }
        }
      }
      function renderRows(items){
        const tb = findTbody();
        if (!tb) throw new Error("cannot find <tbody>");
        tb.innerHTML = "";
        for (const it of items){
          const tr = document.createElement("tr");
          const tdSev = document.createElement("td");
          const tdTool = document.createElement("td");
          const tdTitle = document.createElement("td");
          const tdLoc = document.createElement("td");
          tdSev.textContent = it.severity || "";
          tdTool.textContent = it.tool || "";
          tdTitle.textContent = it.title || "";
          tdLoc.textContent = (it.file ? it.file : "") + (it.line ? (":" + it.line) : "");
          tr.appendChild(tdSev); tr.appendChild(tdTool); tr.appendChild(tdTitle); tr.appendChild(tdLoc);
          tb.appendChild(tr);
        }
      }

      function takeTopN(items, n){
        items.sort((a,b)=> (SEV_W[upper(b.severity)]||0) - (SEV_W[upper(a.severity)]||0));
        if (items.length>n) items.length=n;
        return items;
      }

      function pick(obj, keys){
        for (const k of keys){
          const v = obj?.[k];
          if (v!=null && String(v).trim()!=="") return v;
        }
        return "";
      }

      async function loadFromUnifiedJson(rid, limit){
        const r = await fetch(rfUrl(rid, PATH_JSON), {cache:"no-store"});
        if (!r.ok) throw new Error("JSON http " + r.status);
        const j = await r.json();

        // if backend returns {"ok":false,"err":"not allowed"} -> treat as error
        if (j && j.ok === False) {
          throw new Error("not allowed: findings_unified.json");
        }

        const arr = Array.isArray(j) ? j : (Array.isArray(j?.findings) ? j.findings : []);
        if (!arr.length) throw new Error("JSON findings empty");

        const items=[];
        for (const f of arr){
          const sev = normSev(pick(f, ["severity","normalized_severity"]) || pick(f?.meta, ["severity"]) || pick(f?.properties, ["severity"]));
          const tool = norm(pick(f, ["tool","source","engine"]) || pick(f?.meta, ["tool"]) || pick(f?.properties, ["tool"]));
          const title = norm(pick(f, ["title","message","rule_id","ruleId","id"]) || pick(f?.meta, ["title","message"])) || "Finding";
          const file = norm(pick(f, ["file","path"]) || pick(f?.location, ["file","path"]) || pick(f?.meta, ["file","path"]));
          const line = norm(pick(f, ["line"]) || pick(f?.location, ["line","startLine"]) || pick(f?.meta, ["line","startLine"]));
          if (!title && !file) continue;
          items.push({severity: sev || "INFO", tool, title, file, line});
        }
        if (!items.length) throw new Error("JSON yielded 0 items");
        return takeTopN(items, limit);
      }

      async function runLoad(limit=25){
        const rid = await getRidLatest();
        if (!rid) throw new Error("RID empty");
        setStatus("Loading…");
        console.log("[VSP][TOPFIND_EMG_JSON] start rid=", rid);
        const items = await loadFromUnifiedJson(rid, limit);
        renderRows(items);
        setStatus("Loaded: " + items.length + " (JSON)");
        console.log("[VSP][TOPFIND_EMG_JSON] OK items=", items.length);
      }

      function bind(){
        const btn = findButton();
        if (!btn || !btn.parentNode) return false;

        const b2 = btn.cloneNode(true);
        btn.parentNode.replaceChild(b2, btn);

        b2.addEventListener("click", async (ev)=> {
          ev.preventDefault();
          ev.stopPropagation();
          ev.stopImmediatePropagation?.();
          const old = b2.textContent;
          b2.disabled = true;
          b2.textContent = "Loading…";
          try{
            await runLoad(25);
          }catch(e){
            console.warn("[VSP][TOPFIND_EMG_JSON] failed:", e);
            setStatus("Load failed: " + (e?.message || String(e)));
          }finally{
            b2.disabled = false;
            b2.textContent = old || "Load top findings (25)";
          }
        }, {capture:true});

        console.log("[VSP][TOPFIND_EMG_JSON] bound (button cloned last)");
        return true;
      }

      function start(){
        bind();
        let tries=0;
        const t=setInterval(()=>{ tries++; bind(); if (tries>=15) clearInterval(t); }, 600);
        const obs = new MutationObserver(()=> bind());
        obs.observe(document.documentElement, {subtree:true, childList:true});
      }

      if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
      else setTimeout(start, 0);

      // manual trigger from console:
      window.vspTopFindEmgJsonLoad = ()=> runLoad(25);
    })();
    """)
    p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
    print("[OK] appended:", MARK)
PY

node --check "$JS"
echo "== [2] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [3] quick probe JSON allow + bytes =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin)["rid"])')"
echo "[INFO] RID=$RID"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json" | head -c 220; echo
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json" | wc -c

echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R), click Load top findings (25)."
echo "       Console log should include: [VSP][TOPFIND_EMG_JSON]"
echo "       Or run in console: vspTopFindEmgJsonLoad()"
