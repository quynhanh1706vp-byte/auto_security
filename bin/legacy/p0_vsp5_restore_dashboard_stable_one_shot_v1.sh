#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
WSGI="wsgi_vsp_ui_gateway.py"
PJS="static/js/vsp_dashboard_commercial_panels_v1.js"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

cp -f "$JS"   "${JS}.bak_restore_${TS}"
cp -f "$WSGI" "${WSGI}.bak_restore_${TS}"
echo "[BACKUP] ${JS}.bak_restore_${TS}"
echo "[BACKUP] ${WSGI}.bak_restore_${TS}"

echo "== [1/3] Restore GateStory to a CLEAN backup (no DashP1 / no P1 panels injections) =="
python3 - <<'PY'
from pathlib import Path
import re

js = Path("static/js/vsp_dashboard_gate_story_v1.js")
baks = sorted(js.parent.glob(js.name + ".bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

def is_clean(txt: str) -> bool:
    bad = [
        "VSP_P1_DASHBOARD_P1_PANELS_",
        "DashP1V",
        "__vspP1_",
        "P1PanelsExt",
        "commercial_panels_v1",
    ]
    return not any(x in txt for x in bad)

picked = None
for p in baks:
    try:
        t = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if is_clean(t):
        picked = p
        break

if picked:
    js.write_text(picked.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print(f"[OK] restored GateStory from clean backup: {picked.name}")
else:
    # fallback: strip any injected P1 panel blocks by markers + aggressive DashP1 removal
    t = js.read_text(encoding="utf-8", errors="replace")
    t0 = t

    # Remove marker blocks: /* ==== VSP_P1_DASHBOARD_P1_PANELS_* ==== */ ... /* ==== /VSP_P1_DASHBOARD_P1_PANELS_* ==== */
    t = re.sub(
        r"/\*\s*={5,}\s*VSP_P1_DASHBOARD_P1_PANELS_[\s\S]*?/\*\s*={5,}\s*/VSP_P1_DASHBOARD_P1_PANELS_[\s\S]*?\*/\s*",
        "",
        t,
        flags=re.M
    )

    # Remove any functions/sections that mention DashP1 / __vspP1_
    lines = t.splitlines(True)
    out = []
    drop = False
    brace = 0

    def start_drop(line: str) -> bool:
        return ("DashP1" in line) or ("__vspP1_" in line) or ("P1_PANELS" in line)

    for line in lines:
        if not drop and start_drop(line):
            drop = True
            brace = line.count("{") - line.count("}")
            continue
        if drop:
            brace += line.count("{") - line.count("}")
            if brace <= 0 and ("}" in line or ";" in line):
                drop = False
            continue
        out.append(line)

    t2 = "".join(out)
    js.write_text(t2, encoding="utf-8")
    removed = (len(t0) - len(t2))
    print(f"[WARN] no clean backup found. Applied fallback strip. removed_bytes≈{removed}")
PY

if [ "$node_ok" -eq 1 ]; then
  node --check "$JS" && echo "[OK] node --check GateStory OK"
else
  python3 -m py_compile "$WSGI" >/dev/null 2>&1 || true
fi

echo "== [2/3] Write External Commercial Panels JS (safe + contract-flexible) =="
cat > "$PJS" <<'JS'
/* VSP_P1_COMMERCIAL_PANELS_EXT_V1 (safe external panels; never break UI) */
(() => {
  if (window.__vsp_p1_panels_ext_v1) return;
  window.__vsp_p1_panels_ext_v1 = true;

  const log = (...a)=>console.log("[P1PanelsExtV1]", ...a);
  const warn = (...a)=>console.warn("[P1PanelsExtV1]", ...a);

  function sleep(ms){ return new Promise(r=>setTimeout(r,ms)); }

  function el(tag, attrs={}, children=[]){
    const e=document.createElement(tag);
    for (const [k,v] of Object.entries(attrs||{})){
      if (k==="style") Object.assign(e.style, v||{});
      else if (k==="class") e.className = v;
      else e.setAttribute(k, String(v));
    }
    for (const c of (children||[])){
      if (c==null) continue;
      e.appendChild(typeof c==="string" ? document.createTextNode(c) : c);
    }
    return e;
  }

  function ensureHost(){
    let host = document.getElementById("vsp_p1_ext_panels_host");
    if (host) return host;

    // attach under main root if exists
    const root = document.getElementById("vsp5_root") || document.body;

    host = el("div", { id:"vsp_p1_ext_panels_host", class:"vsp_p1_ext_panels_host" });
    host.style.margin = "14px";
    host.style.paddingBottom = "18px";

    const title = el("div", { class:"vsp_p1_ext_title" }, ["Commercial Panels"]);
    title.style.opacity = "0.75";
    title.style.fontSize = "12px";
    title.style.margin = "8px 2px";

    const grid = el("div", { class:"vsp_p1_ext_grid" });
    grid.style.display = "grid";
    grid.style.gridTemplateColumns = "repeat(12, 1fr)";
    grid.style.gap = "12px";

    host.appendChild(title);
    host.appendChild(grid);
    root.appendChild(host);
    return host;
  }

  function card(title){
    const c = el("div", { class:"vsp_p1_ext_card" });
    c.style.gridColumn = "span 6";
    c.style.border = "1px solid rgba(255,255,255,.10)";
    c.style.borderRadius = "16px";
    c.style.background = "rgba(255,255,255,.03)";
    c.style.boxShadow = "0 12px 30px rgba(0,0,0,.35)";
    c.style.padding = "12px 12px 10px";

    const h = el("div", { class:"vsp_p1_ext_card_title" }, [title]);
    h.style.fontSize = "12px";
    h.style.fontWeight = "700";
    h.style.opacity = "0.9";
    h.style.marginBottom = "8px";

    const body = el("div", { class:"vsp_p1_ext_card_body" });
    body.style.fontSize = "12px";
    body.style.opacity = "0.92";

    c.appendChild(h);
    c.appendChild(body);
    return { c, body };
  }

  async function fetchJSON(url){
    // IMPORTANT: read body only once; handle both {ok:true,data:...} and direct payload
    const r = await fetch(url, { credentials:"same-origin", cache:"no-store" });
    const txt = await r.text();
    let j;
    try { j = JSON.parse(txt); } catch(e){ throw new Error("bad_json"); }
    if (j && typeof j==="object" && j.ok===true && j.data!=null) return j.data;
    return j;
  }

  function pickLatestRID(runsPayload){
    // support: {runs:[{rid/run_id/id}]} OR {items:[...]} OR [...]
    const arr =
      (runsPayload && Array.isArray(runsPayload.runs) && runsPayload.runs) ||
      (runsPayload && Array.isArray(runsPayload.items) && runsPayload.items) ||
      (Array.isArray(runsPayload) && runsPayload) ||
      [];
    const o = arr[0] || {};
    return o.rid || o.run_id || o.id || o.RID || null;
  }

  function normalizeFindingsPayload(p){
    // expected: {meta:{counts_by_severity}, findings:[...]} but accept variations
    if (!p || typeof p!=="object") return { meta:{}, findings:[] };

    // sometimes wrapped {meta:{ok,counts_by_severity}, findings:[...]} already ok
    const meta = (p.meta && typeof p.meta==="object") ? p.meta : {};
    const findings = Array.isArray(p.findings) ? p.findings : (Array.isArray(p.items) ? p.items : []);
    return { meta, findings };
  }

  function countsFrom(meta, findings){
    const c = (meta && meta.counts_by_severity && typeof meta.counts_by_severity==="object") ? meta.counts_by_severity : null;
    if (c) return c;

    // fallback derive from findings
    const out = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
    for (const f of (findings||[])){
      const s = (f && (f.severity||f.sev||f.level||"")).toString().toUpperCase();
      if (out[s] != null) out[s] += 1;
      else out.INFO += 1;
    }
    return out;
  }

  function renderCounts(body, c){
    const row = el("div");
    row.style.display = "flex";
    row.style.flexWrap = "wrap";
    row.style.gap = "8px";

    const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    for (const k of order){
      const v = (c && c[k]!=null) ? c[k] : 0;
      const pill = el("div", {}, [`${k}: ${v}`]);
      pill.style.padding = "6px 10px";
      pill.style.borderRadius = "999px";
      pill.style.border = "1px solid rgba(255,255,255,.14)";
      pill.style.background = "rgba(0,0,0,.20)";
      pill.style.fontSize = "12px";
      row.appendChild(pill);
    }
    body.innerHTML = "";
    body.appendChild(row);
  }

  function renderTopFindings(body, findings){
    const top = (findings||[]).slice(0, 10);
    const box = el("div");
    box.style.display="grid";
    box.style.gap="6px";

    if (!top.length){
      box.appendChild(el("div", {}, ["No findings (or not available)."]));
      body.innerHTML=""; body.appendChild(box);
      return;
    }

    for (const f of top){
      const sev = (f.severity||f.sev||"INFO").toString().toUpperCase();
      const title = (f.title||f.rule||f.check_id||f.id||"Finding").toString();
      const where = (f.location||f.path||f.file||"").toString();
      const line = (f.line!=null ? `:${f.line}` : "");
      const item = el("div", {}, [
        `${sev} • ${title}${where?` • ${where}${line}`:""}`
      ]);
      item.style.padding="6px 10px";
      item.style.border="1px solid rgba(255,255,255,.10)";
      item.style.borderRadius="12px";
      item.style.background="rgba(255,255,255,.02)";
      item.style.whiteSpace="nowrap";
      item.style.overflow="hidden";
      item.style.textOverflow="ellipsis";
      box.appendChild(item);
    }
    body.innerHTML=""; body.appendChild(box);
  }

  async function main(){
    const host = ensureHost();
    const grid = host.querySelector(".vsp_p1_ext_grid");
    if (!grid) return;

    const c1 = card("Findings Summary");
    const c2 = card("Top Findings (sample)");

    grid.innerHTML = "";
    grid.appendChild(c1.c);
    grid.appendChild(c2.c);

    // loading state
    c1.body.textContent = "Loading…";
    c2.body.textContent = "Loading…";

    try{
      const runs = await fetchJSON("/api/vsp/runs?limit=1");
      const rid = pickLatestRID(runs);
      if (!rid) throw new Error("no_rid");
      log("rid=", rid);

      const fp = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`);
      const { meta, findings } = normalizeFindingsPayload(fp);
      const c = countsFrom(meta, findings);

      renderCounts(c1.body, c);
      renderTopFindings(c2.body, findings);

      log("rendered ok");
    } catch(e){
      warn("degraded:", e && (e.message||e));
      c1.body.textContent = "DEGRADED: cannot load findings (see console).";
      c2.body.textContent = "DEGRADED: cannot load findings (see console).";
    }
  }

  // start when DOM ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ()=>main());
  } else {
    main();
  }
})();
JS

if [ "$node_ok" -eq 1 ]; then
  node --check "$PJS" && echo "[OK] node --check panels OK"
fi

echo "== [3/3] Patch WSGI to include external panels script on /vsp5 =="
python3 - <<'PY'
from pathlib import Path
import re

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

if "vsp_dashboard_commercial_panels_v1.js" in s:
    print("[OK] WSGI already includes panels script.")
    raise SystemExit(0)

# Heuristic: insert after any mention of gate_story js in HTML builder
idx = s.find("vsp_dashboard_gate_story_v1.js")
if idx != -1:
    # if file uses {asset_v}, reuse it; else include without version
    use_asset = "{asset_v}" if "{asset_v}" in s or "asset_v" in s else ""
    if use_asset:
        inject = f'  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js?v={use_asset}"></script>\\n'
    else:
        inject = '  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js"></script>\\n'

    # Try to inject into the same HTML string block: after the gate_story script line (best effort)
    # Replace first occurrence of the script tag that loads gate_story
    pat = r'(<script[^>]+vsp_dashboard_gate_story_v1\\.js[^>]*></script>\\s*)'
    s2, n = re.subn(pat, r'\\1' + inject, s, count=1, flags=re.I)
    if n == 0:
        # fallback: insert before </body> in HTML literal
        s2, n2 = re.subn(r'(</body>)', inject + r'\\1', s, count=1, flags=re.I)
        if n2 == 0:
            print("[WARN] could not patch WSGI automatically (no script tag / no </body> literal).")
            raise SystemExit(0)
        s = s2
        print("[OK] inserted panels before </body> (fallback).")
    else:
        s = s2
        print("[OK] inserted panels after gate_story script tag.")
else:
    # fallback: insert before </body> if present
    use_asset = "{asset_v}" if "{asset_v}" in s or "asset_v" in s else ""
    inject = f'  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js?v={use_asset}"></script>\\n' if use_asset else \
             '  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js"></script>\\n'
    s2, n = re.subn(r'(</body>)', inject + r'\\1', s, count=1, flags=re.I)
    if n:
        s = s2
        print("[OK] inserted panels before </body>.")
    else:
        print("[WARN] cannot find insertion point in WSGI.")
        raise SystemExit(0)

w.write_text(s, encoding="utf-8")
print("[OK] wrote WSGI with panels include.")
PY

python3 -m py_compile "$WSGI" && echo "[OK] py_compile WSGI OK"

echo
echo "[DONE] Now do EXACTLY 2 steps:"
echo "  1) restart UI service (systemd/gunicorn) that serves :8910"
echo "  2) HARD refresh /vsp5 (Ctrl+Shift+R)"
echo
echo "[VERIFY] HTML includes both scripts:"
echo "  curl -fsS $BASE/vsp5 | grep -nE 'gate_story_v1|commercial_panels_v1' || true"
echo
echo "[VERIFY] Console should show:"
echo "  [P1PanelsExtV1] rid= ...  and  rendered ok"
