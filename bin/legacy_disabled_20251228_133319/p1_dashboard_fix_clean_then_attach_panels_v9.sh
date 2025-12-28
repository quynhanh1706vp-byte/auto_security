#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
PANELS="static/js/vsp_dashboard_commercial_panels_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

echo "[1/4] Backup current GateStory"
cp -f "$JS" "${JS}.bak_before_clean_${TS}"
echo "[BACKUP] ${JS}.bak_before_clean_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

ts = time.strftime("%Y%m%d_%H%M%S")
js = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = js.read_text(encoding="utf-8", errors="replace")

# Try to restore a clean backup automatically:
baks = sorted(Path("static/js").glob("vsp_dashboard_gate_story_v1.js.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

def looks_clean(txt: str) -> bool:
    # Must contain the core marker, and must NOT contain any DashP1 injections
    if "VSP_P1_GATE_ROOT_PICK_V1" not in txt:
        return False
    bad = [
        "VSP_P1_DASHBOARD_P1_PANELS_",
        "DashP1V",
        "__vspP1_",
        "commercial_panels",
        "Findings payload mismatch",
        "contract mismatch",
    ]
    return not any(b in txt for b in bad)

chosen = None
for p in baks:
    try:
        t = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if looks_clean(t):
        chosen = p
        break

if chosen:
    js.write_text(chosen.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print(f"[OK] restored GateStory from clean backup: {chosen.name}")
else:
    # No clean backup found: sanitize current file by removing injected blocks
    s2 = s

    # remove any block delimited by our markers
    s2, n1 = re.subn(
        r"/\*\s*=+\s*VSP_P1_DASHBOARD_P1_PANELS_[\s\S]*?/\*\s*=+\s*/VSP_P1_DASHBOARD_P1_PANELS_[\s\S]*?\*/\s*",
        "",
        s2,
        flags=re.M
    )

    # remove stray functions/vars starting with __vspP1_
    s2, n2 = re.subn(r"^[^\n]*__vspP1_[^\n]*\n", "", s2, flags=re.M)

    # if a block mentions DashP1V*, remove the whole function block (best-effort)
    s2, n3 = re.subn(
        r"(function\s+DashP1V[\s\S]*?\n\})\s*\n",
        "",
        s2,
        flags=re.M
    )

    # As a last guard: if still referencing __vspP1_normFindingsPayload, neutralize call-sites
    s2 = s2.replace("__vspP1_normFindingsPayload", "null /* disabled */")

    js.write_text(s2, encoding="utf-8")
    print(f"[WARN] no clean backup found; sanitized GateStory: removed marker_blocks={n1}, removed__vspP1_lines={n2}, removed_DashP1_funcs={n3}")

print("[OK] GateStory written")
PY

echo "[2/4] Write Commercial Panels JS (robust unwrap; NO /api/vsp/rid_latest_gate_root)"
cat > "$PANELS" <<'JS'
/* VSP_P1_COMMERCIAL_PANELS_V1 (standalone; robust unwrap; no rid_latest_gate_root) */
(()=> {
  if (window.__vsp_p1_commercial_panels_v1) return;
  window.__vsp_p1_commercial_panels_v1 = true;

  const log = (...a)=>console.log("[PanelsV1]", ...a);
  const warn = (...a)=>console.warn("[PanelsV1]", ...a);

  function qs(sel, root=document){ return root.querySelector(sel); }
  function el(tag, cls, html){
    const n=document.createElement(tag);
    if (cls) n.className=cls;
    if (html!=null) n.innerHTML=html;
    return n;
  }

  async function fetchJSON(url, opt){
    const r = await fetch(url, Object.assign({credentials:"same-origin"}, opt||{}));
    const ct = (r.headers.get("content-type")||"").toLowerCase();
    let data = null;
    if (ct.includes("application/json")) data = await r.json();
    else data = await r.text();
    if (!r.ok) throw new Error(`HTTP ${r.status} ${url} :: ${(typeof data==="string")?data.slice(0,200):JSON.stringify(data).slice(0,200)}`);
    return data;
  }

  function unwrapRunFileAllow(j){
    // run_file_allow usually returns: {ok:true, data:<payload>} OR <payload>
    if (!j) return null;
    if (typeof j === "object" && j.ok === true && j.data != null) return j.data;
    return j;
  }

  async function getLatestRid(){
    // Prefer GateStory's chosen RID if it exposed one (best-effort)
    const g = window.__vsp_gate_root_rid || window.__vsp_gate_root_current || window.__vsp_rid;
    if (typeof g === "string" && g.length > 6) return g;

    // Try scrape from DOM text (your page shows "gate_root: VSP_CI_RUN_..." or "RID:RUN_...")
    const t = (document.body && document.body.innerText) ? document.body.innerText : "";
    const m = t.match(/\b(VSP_[A-Z0-9_]*RUN_\d{8}_\d{6}|RUN_\d{8}_\d{6})\b/);
    if (m && m[1]) return m[1];

    // Fallback to /api/vsp/runs?limit=1
    const runs = await fetchJSON("/api/vsp/runs?limit=1&offset=0");
    const arr = Array.isArray(runs) ? runs : (runs && Array.isArray(runs.runs) ? runs.runs : []);
    const rid = arr && arr[0] && (arr[0].rid || arr[0].run_id || arr[0].id);
    if (!rid) throw new Error("Cannot resolve RID from DOM or /api/vsp/runs");
    return rid;
  }

  function ensureMount(){
    // Put panels near bottom, but visible
    let mount = qs("#vspCommercialPanelsMount");
    if (mount) return mount;

    // Try to attach under main dashboard container if exists, else body
    const host = qs("#vsp5Root") || qs("#app") || qs("main") || document.body;
    mount = el("div", "vsp-commercial-panels-mount");
    mount.id = "vspCommercialPanelsMount";
    mount.style.margin = "14px 18px";
    mount.style.padding = "12px";
    mount.style.borderRadius = "12px";
    mount.style.border = "1px solid rgba(255,255,255,0.06)";
    mount.style.background = "rgba(0,0,0,0.10)";
    mount.innerHTML = `
      <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;">
        <div style="font-weight:700;opacity:.95">Commercial Panels</div>
        <div id="vspPanelsRid" style="font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;opacity:.75"></div>
      </div>
      <div id="vspPanelsBody" style="margin-top:10px;display:grid;grid-template-columns:repeat(3,minmax(220px,1fr));gap:10px;"></div>
      <div id="vspPanelsErr" style="margin-top:10px;color:#ff8080;display:none"></div>
    `;
    host.appendChild(mount);
    return mount;
  }

  function card(title, value, sub){
    const c = el("div", "");
    c.style.border = "1px solid rgba(255,255,255,0.06)";
    c.style.borderRadius = "12px";
    c.style.padding = "10px 12px";
    c.style.background = "rgba(255,255,255,0.03)";
    c.innerHTML = `
      <div style="font-size:12px;opacity:.75">${title}</div>
      <div style="font-size:20px;font-weight:800;letter-spacing:.2px;margin-top:4px">${value}</div>
      <div style="font-size:12px;opacity:.70;margin-top:2px">${sub||""}</div>
    `;
    return c;
  }

  function showErr(msg){
    const mount = ensureMount();
    const e = qs("#vspPanelsErr", mount);
    if (e){
      e.style.display="block";
      e.textContent = msg;
    }
  }

  async function main(){
    const mount = ensureMount();
    const body = qs("#vspPanelsBody", mount);
    const ridBox = qs("#vspPanelsRid", mount);

    try{
      const rid = await getLatestRid();
      ridBox.textContent = `RID: ${rid}`;
      log("rid=", rid);

      // Fetch run_gate_summary + findings_unified
      const gateRaw = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`);
      const findRaw = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json`);
      const gate = unwrapRunFileAllow(gateRaw) || {};
      const fu = unwrapRunFileAllow(findRaw) || {};

      const overall = (gate.overall_status || gate.overall || (gate.meta && gate.meta.overall) || "UNKNOWN") + "";
      const degradedN = (gate.degraded_tools && Array.isArray(gate.degraded_tools) ? gate.degraded_tools.length : (gate.degraded_count||0));
      const toolsTotal = (gate.tools_total||8);

      const meta = (fu && fu.meta) || {};
      const counts = (meta && meta.counts_by_severity) || null;
      const findingsList = Array.isArray(fu.findings) ? fu.findings : (Array.isArray(fu) ? fu : []);

      let crit=0, high=0, med=0, low=0, info=0, trace=0, total=0;
      if (counts){
        crit = +counts.CRITICAL||0; high=+counts.HIGH||0; med=+counts.MEDIUM||0; low=+counts.LOW||0; info=+counts.INFO||0; trace=+counts.TRACE||0;
        total = crit+high+med+low+info+trace;
      } else if (findingsList.length){
        total = findingsList.length;
        for (const f of findingsList){
          const sev = (f && (f.severity||f.sev||f.level||"")).toString().toUpperCase();
          if (sev==="CRITICAL") crit++;
          else if (sev==="HIGH") high++;
          else if (sev==="MEDIUM") med++;
          else if (sev==="LOW") low++;
          else if (sev==="INFO") info++;
          else if (sev==="TRACE") trace++;
        }
      }

      body.innerHTML = "";
      body.appendChild(card("Overall", overall, `Degraded ${degradedN}/${toolsTotal}`));
      body.appendChild(card("Findings (total)", total, `CRIT ${crit} • HIGH ${high} • MED ${med}`));
      body.appendChild(card("Info/Trace", (info+trace), `INFO ${info} • TRACE ${trace}`));

      log("rendered ok", {overall, degradedN, toolsTotal, total});
    }catch(e){
      warn(e);
      showErr(String(e && e.message ? e.message : e));
    }
  }

  // Run after DOM ready + after GateStory has a chance
  const kick = ()=>setTimeout(main, 60);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", kick);
  else kick();
})();
JS
echo "[OK] wrote $PANELS"

if [ "$node_ok" = "1" ]; then
  node --check "$JS" && echo "[OK] node --check GateStory OK"
  node --check "$PANELS" && echo "[OK] node --check Panels OK"
fi

echo "[3/4] Patch ALL sources that include gate_story_v1.js to also include commercial_panels_v1.js"
python3 - <<'PY'
from pathlib import Path
import re, time

ts = time.strftime("%Y%m%d_%H%M%S")
needle = "/static/js/vsp_dashboard_gate_story_v1.js"
insert = '/static/js/vsp_dashboard_commercial_panels_v1.js'
insert_tag_re = re.compile(r'vsp_dashboard_commercial_panels_v1\.js')

cands = []
for p in list(Path("templates").rglob("*.html")) + list(Path(".").rglob("*.py")):
    # skip backups
    if ".bak_" in p.name: 
        continue
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if needle in s:
        cands.append((p, s))

if not cands:
    print("[ERR] cannot find any file containing gate_story include")
    raise SystemExit(2)

patched = 0
for p, s in cands:
    if insert_tag_re.search(s):
        # already included somewhere
        continue
    bak = p.with_name(p.name + f".bak_add_panels_{ts}")
    bak.write_text(s, encoding="utf-8")

    # Insert immediately after the gate_story script tag line (best-effort)
    s2, n = re.subn(
        r'(<script[^>]+vsp_dashboard_gate_story_v1\.js[^>]*></script>\s*)',
        r'\1<script src="/static/js/vsp_dashboard_commercial_panels_v1.js?v={{ asset_v }}"></script>\n',
        s,
        count=1,
        flags=re.I
    )
    if n == 0:
        # fallback: simple string-based insert
        s2 = s.replace(needle, needle)  # no-op, then append near end of head
        s2 = re.sub(r'(</head>)', r'  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js?v={{ asset_v }}"></script>\n\\1', s2, count=1, flags=re.I)
        n = 1

    p.write_text(s2, encoding="utf-8")
    print(f"[OK] patched {p} (backup {bak.name})")
    patched += 1

print(f"[DONE] include patched={patched} files (total candidates={len(cands)})")
PY

echo "[4/4] Verify HTML includes panels script"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS "$BASE/vsp5" | grep -nE "vsp_dashboard_gate_story_v1\\.js|vsp_dashboard_commercial_panels_v1\\.js" || true

echo
echo "[DONE] Next:"
echo "  1) restart UI (systemd/gunicorn)"
echo "  2) HARD refresh /vsp5 (Ctrl+Shift+R)"
echo
echo "[EXPECT] Console should show: [PanelsV1] rid=... and rendered ok"
