#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need curl; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] fetch /vsp5 HTML and detect JS files =="
HTML="/tmp/vsp5_${TS}.html"
curl -fsS "$BASE/vsp5" > "$HTML"

python3 - <<'PY'
import re, pathlib
html = pathlib.Path(__import__("os").environ["HTML"]).read_text(encoding="utf-8", errors="replace")
srcs = re.findall(r'<script[^>]+src=["\']([^"\']+)["\']', html, flags=re.I)
# keep only /static/js/*.js
js = [s for s in srcs if "/static/js/" in s and s.endswith(".js")]
print("JS_IN_VSP5:")
for s in js: print(" -", s)
print("COUNT=", len(js))
PY

echo "== [1] choose candidate JS to patch (prefer dash_only / dashboard / bundle) =="
CANDS="$(python3 - <<'PY'
import re, pathlib, os
html = pathlib.Path(os.environ["HTML"]).read_text(encoding="utf-8", errors="replace")
srcs = re.findall(r'<script[^>]+src=["\']([^"\']+)["\']', html, flags=re.I)
js = [s for s in srcs if "/static/js/" in s and s.endswith(".js")]
# prefer ones that likely own dashboard behavior
prefer = []
for s in js:
  low=s.lower()
  if "dash_only" in low or "dashboard" in low or "bundle" in low or "vsp5" in low:
    prefer.append(s)
# fallback: all js
out = prefer if prefer else js
print("\n".join(out))
PY
)"
[ -n "${CANDS:-}" ] || { echo "[ERR] no /static/js/*.js found in /vsp5 HTML"; exit 2; }

echo "[INFO] will patch these JS (in order):"
printf '%s\n' "$CANDS" | sed 's/^/ - /'

echo "== [2] patch JS: inject TOPFIND FINAL v6 block (CSV->SARIF->JSON) and force button clone-bind =="
PATCHED=0
while IFS= read -r SRC; do
  [ -n "$SRC" ] || continue
  # strip query string ?v=...
  PATH_JS="${SRC%%\?*}"
  # convert to local path (remove leading /)
  LOCAL="${PATH_JS#/}"
  [ -f "$LOCAL" ] || { echo "[WARN] missing local file for $SRC => $LOCAL (skip)"; continue; }

  cp -f "$LOCAL" "${LOCAL}.bak_topfind_v6_${TS}"
  echo "[BACKUP] ${LOCAL}.bak_topfind_v6_${TS}"

  python3 - <<'PY'
from pathlib import Path
import textwrap, os

local = Path(os.environ["LOCAL"])
s = local.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P0_TOPFIND_FINAL_V6_AUTO_JS_PATCH"

if MARK in s:
  print("[SKIP] already patched:", local)
else:
  block = textwrap.dedent(r"""
  /* VSP_P0_TOPFIND_FINAL_V6_AUTO_JS_PATCH
     FINAL v6:
       - Kill old handlers by clone button
       - Robust tbody lookup under "Top findings" card (fallback to first tbody)
       - Data fallback: CSV -> SARIF -> findings_unified.json
  */
  (()=> {
    if (window.__vsp_p0_topfind_final_v6_auto) return;
    window.__vsp_p0_topfind_final_v6_auto = true;

    const RID_LATEST = "/api/vsp/rid_latest_gate_root";
    const PATH_CSV   = "reports/findings_unified.csv";
    const PATH_SARIF = "reports/findings_unified.sarif";
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

    // --- DOM helpers ---
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
      // find the first cell showing "Not loaded"/"Loading..."
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

    // --- CSV (quotes supported) ---
    function parseCSV(text, maxRows=8000){
      text = String(text || "").replace(/\r\n/g,"\n").replace(/\r/g,"\n");
      const rows = [];
      let row = [], cur = "", inQ=false;
      for (let i=0;i<text.length;i++){
        const ch = text[i];
        if (inQ){
          if (ch === '"'){
            if (text[i+1] === '"'){ cur += '"'; i++; continue; }
            inQ = false; continue;
          }
          cur += ch; continue;
        }
        if (ch === '"'){ inQ=true; continue; }
        if (ch === ','){ row.push(cur); cur=""; continue; }
        if (ch === '\n'){
          row.push(cur); cur="";
          if (!(row.length===1 && row[0]==="")) rows.push(row);
          row=[];
          if (rows.length>=maxRows) break;
          continue;
        }
        cur += ch;
      }
      if (cur.length || row.length){
        row.push(cur);
        if (!(row.length===1 && row[0]==="")) rows.push(row);
      }
      return rows;
    }

    async function loadFromCSV(rid, limit){
      const r = await fetch(rfUrl(rid, PATH_CSV), {cache:"no-store"});
      if (!r.ok) throw new Error("CSV http " + r.status);
      const text = await r.text();
      const logical = text.replace(/\r\n/g,"\n").replace(/\r/g,"\n").split("\n").filter(x=>x.trim()!=="");
      if (logical.length <= 1) throw new Error("CSV header only");

      const rows = parseCSV(text);
      if (rows.length <= 1) throw new Error("CSV rows empty");

      const header = rows[0].map(x=>norm(x));
      const idx = {};
      for (let i=0;i<header.length;i++) idx[header[i].toLowerCase()] = i;
      const get = (row, name)=> {
        const i = idx[name];
        if (i==null) return "";
        return row[i]==null ? "" : String(row[i]);
      };

      const items=[];
      for (let i=1;i<rows.length;i++){
        const row=rows[i];
        if (!row || row.length<2) continue;
        items.push({
          severity: normSev(get(row,"severity")),
          tool: norm(get(row,"tool")),
          title: norm(get(row,"title")) || norm(get(row,"message")) || norm(get(row,"rule_id")) || "Finding",
          file: norm(get(row,"file")),
          line: norm(get(row,"line")),
        });
      }
      if (!items.length) throw new Error("CSV yielded 0 items");
      return takeTopN(items, limit);
    }

    // --- SARIF ---
    function mapSarifLevelToSev(level){
      const lv = (level||"").toLowerCase();
      if (lv === "error") return "HIGH";
      if (lv === "warning") return "MEDIUM";
      if (lv === "note") return "LOW";
      return "INFO";
    }

    async function loadFromSarif(rid, limit){
      const r = await fetch(rfUrl(rid, PATH_SARIF), {cache:"no-store"});
      if (!r.ok) throw new Error("SARIF http " + r.status);
      const j = await r.json();

      const items=[];
      const runs = (j && j.runs) ? j.runs : [];
      for (const run of runs){
        const toolName = norm(run?.tool?.driver?.name) || "";
        const results = run?.results || [];
        for (const res of results){
          const sev = normSev(res?.properties?.severity) || mapSarifLevelToSev(res?.level);
          const msg = norm(res?.message?.text) || norm(res?.message?.markdown) || norm(res?.ruleId) || "Finding";
          const loc0 = res?.locations?.[0]?.physicalLocation;
          const file = norm(loc0?.artifactLocation?.uri) || "";
          const line = String(loc0?.region?.startLine || "").trim();
          items.push({severity: sev, tool: norm(res?.properties?.tool) || toolName || "", title: msg, file, line});
        }
      }
      if (!items.length) throw new Error("SARIF yielded 0 items");
      return takeTopN(items, limit);
    }

    // --- JSON unified ---
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

    async function loadTop(limit=25){
      const rid = await getRidLatest();
      if (!rid) throw new Error("RID empty");
      setStatus("Loading…");
      console.log("[VSP][TOPFIND_V6] start rid=", rid);

      try{
        const a = await loadFromCSV(rid, limit);
        renderRows(a); setStatus("Loaded: "+a.length+" (CSV)");
        console.log("[VSP][TOPFIND_V6] ok via CSV", a.length);
        return;
      }catch(e1){
        console.warn("[VSP][TOPFIND_V6] CSV failed:", e1?.message||e1);
      }

      try{
        const b = await loadFromSarif(rid, limit);
        renderRows(b); setStatus("Loaded: "+b.length+" (SARIF)");
        console.log("[VSP][TOPFIND_V6] ok via SARIF", b.length);
        return;
      }catch(e2){
        console.warn("[VSP][TOPFIND_V6] SARIF failed:", e2?.message||e2);
      }

      const c = await loadFromUnifiedJson(rid, limit);
      renderRows(c); setStatus("Loaded: "+c.length+" (JSON)");
      console.log("[VSP][TOPFIND_V6] ok via JSON", c.length);
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
          await loadTop(25);
        }catch(e){
          console.warn("[VSP][TOPFIND_V6] failed:", e);
          setStatus("Load failed: " + (e?.message || String(e)));
        }finally{
          b2.disabled = false;
          b2.textContent = old || "Load top findings (25)";
        }
      }, {capture:true});

      console.log("[VSP][TOPFIND_V6] bound (button cloned last)");
      return true;
    }

    function start(){
      bind();
      let tries=0;
      const t=setInterval(()=>{ tries++; bind(); if (tries>=12) clearInterval(t); }, 700);
      const obs = new MutationObserver(()=> bind());
      obs.observe(document.documentElement, {subtree:true, childList:true});
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
    else setTimeout(start, 0);
  })();
  """)

  local.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
  print("[OK] appended:", local, "marker=", MARK)
PY

  node --check "$LOCAL" >/dev/null
  PATCHED=$((PATCHED+1))
done <<< "$CANDS"

[ "$PATCHED" -gt 0 ] || { echo "[ERR] no JS patched (all missing?)"; exit 2; }

echo "== [3] ensure backend allow run_file_allow path findings_unified.json (auto patch if needed) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin)["rid"])')"
echo "[INFO] RID=$RID"

ALLOW_JSON="$(curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json" || true)"
echo "$ALLOW_JSON" | head -c 240; echo

if echo "$ALLOW_JSON" | grep -q '"ok"[[:space:]]*:[[:space:]]*false' && echo "$ALLOW_JSON" | grep -qi 'not allowed'; then
  echo "[WARN] findings_unified.json not allowed -> patch allowlist"

  python3 - <<'PY'
from pathlib import Path
import re, time

root = Path(".")
# find python file that implements run_file_allow
cands = []
for p in root.rglob("*.py"):
  if "out" in p.parts or "bin" in p.parts: 
    continue
  s = p.read_text(encoding="utf-8", errors="replace")
  if "run_file_allow" in s and "not allowed" in s:
    cands.append(p)

if not cands:
  raise SystemExit("[ERR] cannot find python file containing run_file_allow + not allowed")

# prefer vsp_demo_app.py if present
cands.sort(key=lambda p: (0 if p.name=="vsp_demo_app.py" else 1, len(str(p))))
target = cands[0]
s = target.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_ALLOW_FINDINGS_UNIFIED_JSON_V1"
if MARK in s:
  print("[SKIP] already patched allowlist:", target)
else:
  # inject just before returning not allowed
  pat = r'(return\s+[^\\n]*not allowed[^\\n]*\n)'
  m = re.search(pat, s, flags=re.I)
  if not m:
    # fallback: find a line containing 'not allowed'
    m = re.search(r'^\s*return.*not allowed.*$', s, flags=re.I|re.M)
  if not m:
    raise SystemExit("[ERR] cannot find return not allowed line to patch")

  inject = f"""
# ===================== {MARK} =====================
try:
    _p = str(path or "").lstrip("/")
    if _p in ("findings_unified.json","reports/findings_unified.csv","reports/findings_unified.sarif"):
        allowed = True
except Exception:
    pass
# ===================== /{MARK} =====================
"""
  # place injection before the matched line
  if m.re.flags & re.M:
    start = m.start()
  else:
    start = m.start(1)

  s2 = s[:start] + inject + s[start:]
  bk = target.with_suffix(target.suffix + f".bak_allowjson_{int(time.time())}")
  bk.write_text(s, encoding="utf-8")
  target.write_text(s2, encoding="utf-8")
  print("[OK] patched allowlist:", target, "backup:", bk)
PY

else
  echo "[OK] findings_unified.json seems allowed (or endpoint returned non-notallowed)"
fi

echo "== [4] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [5] probe bytes (CSV/SARIF/JSON) =="
python3 - <<PY
import urllib.request, json
base="$BASE"; rid="$RID"
def read(path):
  u=f"{base}/api/vsp/run_file_allow?rid={rid}&path={path}"
  try:
    with urllib.request.urlopen(u) as r:
      b=r.read()
    return len(b), b[:180]
  except Exception as e:
    return -1, str(e).encode()

for p in ["reports/findings_unified.csv","reports/findings_unified.sarif","findings_unified.json"]:
  n, head = read(p)
  print("path=",p,"bytes=",n,"head=",head.decode("utf-8","replace").replace("\n","\\n")[:180])
PY

echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R), then click: Load top findings (25)."
echo "       Open DevTools Console -> expect logs: [VSP][TOPFIND_V6] ok via (CSV|SARIF|JSON)"
