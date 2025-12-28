#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_force_ui_inject_${TS}"
echo "[BACKUP] ${JS}.bak_force_ui_inject_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_DASH_FORCE_INJECT_AND_GATE_ROOT_HOOK_V1"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P0_DASH_FORCE_INJECT_AND_GATE_ROOT_HOOK_V1
   Purpose:
   1) Global fetch hook: any /api/vsp/runs json will be mutated to prefer rid_latest_gate_root
      by forcing rid_last_good/rid_latest => rid_latest_gate_root. This fixes GateStory picking last_good.
   2) Force inject Dashboard shell on /vsp5 even if backend serves minimal HTML (gate-only).
   3) Render KPI + Audit evidence probes from gate_root.
*/
(()=> {
  try{
    if (window.__vsp_p0_dash_force_inject_v1) return;
    window.__vsp_p0_dash_force_inject_v1 = true;

    // ---------- (1) Global fetch hook for /api/vsp/runs ----------
    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (_fetch && !window.__vsp_p0_runs_fetch_hooked_v1){
      window.__vsp_p0_runs_fetch_hooked_v1 = true;
      window.fetch = async (input, init) => {
        const res = await _fetch(input, init);
        try{
          const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          if (url && url.indexOf("/api/vsp/runs") !== -1 && res && res.ok && typeof res.json === "function"){
            const _json = res.json.bind(res);
            res.json = async () => {
              const j = await _json();
              try{
                if (j && j.rid_latest_gate_root){
                  j.__vsp_prefer_gate_root = true;
                  j.__vsp_gate_root = j.rid_latest_gate_root;
                  // force any picker that uses last_good/latest to land on gate_root
                  j.rid_last_good = j.rid_latest_gate_root;
                  j.rid_latest    = j.rid_latest_gate_root;
                  console.log("[VSP][runs_hook] prefer gate_root:", j.rid_latest_gate_root);
                }
              }catch(e){
                console.warn("[VSP][runs_hook] mutate err", e);
              }
              return j;
            };
          }
        }catch(e){
          // ignore
        }
        return res;
      };
      console.log("[VSP][runs_hook] installed");
    }

    // ---------- Helpers ----------
    const $ = (id)=> document.getElementById(id);
    const setText = (id, v)=> { const el=$(id); if(el) el.textContent = (v==null? "—": String(v)); };

    async function fetchJSON(url){
      const r = await fetch(url, { cache:"no-store" });
      if (!r.ok) throw new Error("http "+r.status+" "+url);
      return await r.json();
    }
    async function probeText(url){
      const r = await fetch(url, { cache:"no-store" });
      if (!r.ok) return { ok:false, status:r.status, size:0 };
      const t = await r.text();
      return { ok: !!t && t.length>1, status:200, size:(t||"").length, text:t||"" };
    }

    function isDash(){
      const p = (location && location.pathname) ? location.pathname : "";
      return (p === "/vsp5" || p === "/vsp5/" || p.indexOf("/vsp5") === 0);
    }

    function ensureDashShell(){
      if (!isDash()) return false;
      if ($("vsp_dash_p1_wrap")) return true;

      const wrap = document.createElement("div");
      wrap.id = "vsp_dash_p1_wrap";
      wrap.style.padding = "14px 14px 10px 14px";

      wrap.innerHTML = `
        <div style="display:flex;align-items:flex-start;justify-content:space-between;gap:12px;flex-wrap:wrap;">
          <div style="min-width:260px;">
            <div style="font-size:18px;font-weight:700;letter-spacing:.2px;">VSP • Dashboard</div>
            <div style="opacity:.78;font-size:12px;margin-top:4px;">
              Tool truth (gate_root): <span id="vsp_dash_gate_root" style="font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;">—</span>
              • Updated: <span id="vsp_dash_updated_at">—</span>
            </div>
          </div>

          <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center;justify-content:flex-end;">
            <a class="vsp_btn" href="/runs" style="text-decoration:none;">Runs &amp; Reports</a>
            <a class="vsp_btn" href="/data_source" style="text-decoration:none;">Data Source</a>
            <a class="vsp_btn" href="/settings" style="text-decoration:none;">Settings</a>
            <a class="vsp_btn" href="/rule_overrides" style="text-decoration:none;">Rule Overrides</a>
            <span style="width:1px;height:22px;background:rgba(255,255,255,.10);display:inline-block;"></span>
            <a class="vsp_btn" id="vsp_dash_export_zip" href="#" style="text-decoration:none;">Export ZIP</a>
            <a class="vsp_btn" id="vsp_dash_export_pdf" href="#" style="text-decoration:none;">Export PDF</a>
          </div>
        </div>

        <div id="vsp_dash_grid" style="display:grid;grid-template-columns:repeat(12, 1fr);gap:10px;margin-top:12px;">
          <div style="grid-column:span 3;min-width:220px;" class="vsp_card">
            <div style="opacity:.75;font-size:12px;">Overall</div>
            <div id="vsp_dash_overall" style="margin-top:6px;font-size:20px;font-weight:800;">—</div>
            <div style="margin-top:6px;opacity:.75;font-size:12px;">Degraded: <span id="vsp_dash_degraded">—</span></div>
          </div>

          <div style="grid-column:span 3;min-width:220px;" class="vsp_card">
            <div style="opacity:.75;font-size:12px;">Findings (counts)</div>
            <div style="margin-top:8px;display:flex;flex-wrap:wrap;gap:8px;">
              <span class="vsp_pill" id="vsp_dash_c_critical">CRIT: —</span>
              <span class="vsp_pill" id="vsp_dash_c_high">HIGH: —</span>
              <span class="vsp_pill" id="vsp_dash_c_medium">MED: —</span>
              <span class="vsp_pill" id="vsp_dash_c_low">LOW: —</span>
            </div>
            <div style="margin-top:8px;display:flex;flex-wrap:wrap;gap:8px;">
              <span class="vsp_pill" id="vsp_dash_c_info">INFO: —</span>
              <span class="vsp_pill" id="vsp_dash_c_trace">TRACE: —</span>
            </div>
          </div>

          <div style="grid-column:span 6;min-width:320px;" class="vsp_card">
            <div style="opacity:.75;font-size:12px;display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;">
              <span>Severity bar</span>
              <span style="opacity:.75">RID: <span id="vsp_dash_rid_short" style="font-family:ui-monospace, monospace;">—</span></span>
            </div>
            <div id="vsp_dash_sev_bar" style="margin-top:10px;display:flex;gap:8px;align-items:flex-end;min-height:44px;"></div>
            <div style="opacity:.7;font-size:12px;margin-top:8px;">Dashboard auto-reloads when gate_root changes (tool truth).</div>
          </div>

          <div id="vsp_dash_audit_card" style="grid-column:span 12;min-width:320px;" class="vsp_card">
            <div style="display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;align-items:center;">
              <div style="opacity:.82;font-size:12px;">Evidence &amp; Audit Readiness</div>
              <div style="opacity:.75;font-size:12px;">Status: <span id="vsp_dash_audit_status" class="vsp_pill">—</span></div>
            </div>
            <div style="margin-top:10px;display:flex;gap:8px;flex-wrap:wrap;align-items:center;" id="vsp_dash_audit_pills"></div>
            <div style="margin-top:10px;display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;align-items:flex-start;">
              <div style="min-width:280px;flex:1;">
                <div style="opacity:.75;font-size:12px;">ISO / DepSecOps hint</div>
                <div style="margin-top:6px;opacity:.9;font-size:12px;line-height:1.4" id="vsp_dash_iso_hint">—</div>
              </div>
              <div style="min-width:280px;flex:1;">
                <div style="opacity:.75;font-size:12px;">Tool lane (8 tools)</div>
                <div style="margin-top:6px;display:flex;gap:8px;flex-wrap:wrap;align-items:center;" id="vsp_dash_tool_lane"></div>
              </div>
            </div>
          </div>
        </div>

        <style>
          .vsp_card{background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:12px;box-shadow:0 8px 24px rgba(0,0,0,.35);}
          .vsp_btn{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.10);padding:8px 10px;border-radius:12px;font-size:12px;opacity:.9}
          .vsp_btn:hover{opacity:1;filter:brightness(1.08)}
          .vsp_pill{background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.10);padding:6px 8px;border-radius:999px;font-size:12px}
        </style>
      `;

      // Insert right after the first block (usually Gate Story bar exists above)
      const b = document.body;
      if (!b) return false;
      if (b.children && b.children.length > 0) b.insertBefore(wrap, b.children[1] || null);
      else b.appendChild(wrap);

      return true;
    }

    function paintOverall(overall){
      const el = $("vsp_dash_overall");
      if (!el) return;
      el.textContent = overall || "—";
      el.style.padding = "4px 10px";
      el.style.borderRadius = "999px";
      el.style.display = "inline-block";
      el.style.border = "1px solid rgba(255,255,255,.12)";
      let bg = "rgba(255,255,255,.05)";
      if (overall === "RED") bg = "rgba(255, 72, 72, .18)";
      if (overall === "AMBER") bg = "rgba(255, 190, 64, .18)";
      if (overall === "GREEN") bg = "rgba(80, 220, 140, .16)";
      el.style.background = bg;
    }

    function normalizeCounts(j){
      const out = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      const c = j?.counts_by_severity || j?.by_severity || j?.severity_counts || j?.summary?.counts_by_severity || null;
      if (c && typeof c === "object"){
        for (const k of Object.keys(out)) if (c[k] != null) out[k] = Number(c[k])||0;
      }
      return out;
    }

    function renderBar(counts){
      const el = $("vsp_dash_sev_bar");
      if (!el) return;
      el.innerHTML = "";
      const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      const max = Math.max(1, ...order.map(k=>counts[k]||0));
      for (const k of order){
        const v = counts[k]||0;
        const h = Math.round((v/max)*38)+6;
        const col = document.createElement("div");
        col.style.flex="1"; col.style.minWidth="34px";
        col.style.display="flex"; col.style.flexDirection="column"; col.style.alignItems="center";
        const bar = document.createElement("div");
        bar.style.width="100%"; bar.style.height=h+"px";
        bar.style.borderRadius="10px";
        bar.style.border="1px solid rgba(255,255,255,.10)";
        bar.style.background="rgba(255,255,255,.06)";
        const lab = document.createElement("div");
        lab.style.marginTop="6px"; lab.style.fontSize="11px"; lab.style.opacity=".78";
        lab.textContent = `${k.replace("MEDIUM","MED")}:${v}`;
        col.appendChild(bar); col.appendChild(lab);
        el.appendChild(col);
      }
    }

    function pill(text, ok){
      const el = document.createElement("span");
      el.className = "vsp_pill";
      el.style.borderColor = ok ? "rgba(80,220,140,.28)" : "rgba(255,72,72,.28)";
      el.style.background = ok ? "rgba(80,220,140,.10)" : "rgba(255,72,72,.10)";
      el.textContent = text;
      return el;
    }
    function badge(text){
      const el = document.createElement("span");
      el.className = "vsp_pill";
      el.style.background="rgba(255,255,255,.04)";
      el.style.borderColor="rgba(255,255,255,.10)";
      el.textContent=text;
      return el;
    }

    async function renderDash(){
      if (!ensureDashShell()) return;

      // meta -> gate_root
      const meta = await fetchJSON("/api/vsp/runs?_ts=" + Date.now());
      const gateRoot = meta?.rid_latest_gate_root || meta?.rid_latest || meta?.rid_last_good || meta?.rid_latest_findings || "";
      if (!gateRoot) return;

      setText("vsp_dash_gate_root", gateRoot);
      setText("vsp_dash_rid_short", gateRoot.slice(0, 24));
      setText("vsp_dash_updated_at", new Date().toLocaleString());
      const aZip = $("vsp_dash_export_zip"), aPdf = $("vsp_dash_export_pdf");
      if (aZip) aZip.href = `/api/vsp/run_export_zip?rid=${encodeURIComponent(gateRoot)}`;
      if (aPdf) aPdf.href = `/api/vsp/run_export_pdf?rid=${encodeURIComponent(gateRoot)}`;

      // summary: prefer run_gate_summary
      let sum = null;
      try{
        sum = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(gateRoot)}&path=run_gate_summary.json&_ts=${Date.now()}`);
      }catch(e1){
        sum = await fetchJSON(`/api/vsp/run_file_allow?rid=${encodeURIComponent(gateRoot)}&path=run_gate.json&_ts=${Date.now()}`);
      }

      const overall = (sum?.overall_status || sum?.overall || sum?.status || "—").toString().toUpperCase();
      paintOverall(["RED","AMBER","GREEN"].includes(overall) ? overall : overall || "—");
      setText("vsp_dash_degraded", (sum?.degraded!=null)? sum.degraded : "—");

      const counts = normalizeCounts(sum);
      setText("vsp_dash_c_critical", `CRIT: ${counts.CRITICAL}`);
      setText("vsp_dash_c_high",     `HIGH: ${counts.HIGH}`);
      setText("vsp_dash_c_medium",   `MED: ${counts.MEDIUM}`);
      setText("vsp_dash_c_low",      `LOW: ${counts.LOW}`);
      setText("vsp_dash_c_info",     `INFO: ${counts.INFO}`);
      setText("vsp_dash_c_trace",    `TRACE: ${counts.TRACE}`);
      renderBar(counts);

      // audit probes
      const req = [
        "run_manifest.json",
        "run_evidence_index.json",
        "run_gate.json",
        "run_gate_summary.json",
        "findings_unified.json",
        "reports/findings_unified.csv",
        "reports/findings_unified.sarif",
      ];
      const pillsEl = $("vsp_dash_audit_pills");
      if (pillsEl) pillsEl.innerHTML = "";
      let okAll = true;

      for (const f of req){
        const u = `/api/vsp/run_file_allow?rid=${encodeURIComponent(gateRoot)}&path=${encodeURIComponent(f)}&_ts=${Date.now()}`;
        const r = await probeText(u);
        if (!r.ok) okAll = false;
        if (pillsEl) pillsEl.appendChild(pill(`${f}${r.ok?"":" ✗"}`, r.ok));
      }
      const st = $("vsp_dash_audit_status");
      if (st){
        st.textContent = okAll ? "AUDIT READY" : "MISSING EVIDENCE";
        st.style.borderColor = okAll ? "rgba(80,220,140,.28)" : "rgba(255,72,72,.28)";
        st.style.background  = okAll ? "rgba(80,220,140,.10)" : "rgba(255,72,72,.10)";
      }

      // ISO hint + tool lane
      const isoEl = $("vsp_dash_iso_hint");
      if (isoEl){
        const iso = sum?.iso27001 || sum?.iso_map || sum?.iso || sum?.compliance || null;
        if (iso && typeof iso === "object"){
          const keys = Object.keys(iso);
          isoEl.textContent = `ISO mapping present (${keys.length} keys).`;
        } else {
          isoEl.textContent = "ISO mapping not found in gate summary. (P0) Recommend mapping findings to ISO 27001 controls and keep manifest + evidence_index for audit traceability.";
        }
      }
      const lane = $("vsp_dash_tool_lane");
      if (lane){
        lane.innerHTML = "";
        const byTool = sum?.by_tool || sum?.tools || sum?.tool_status || sum?.summary?.by_tool || null;
        const prefer = ["Bandit","Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","CodeQL"];
        if (byTool && typeof byTool === "object"){
          for (const t of prefer){
            const v = byTool[t] || byTool[t.toLowerCase()] || null;
            const st = (v?.status || v?.state || v || "—").toString().toUpperCase();
            lane.appendChild(badge(`${t}:${st||"—"}`));
          }
        } else {
          for (const t of prefer) lane.appendChild(badge(`${t}:—`));
        }
      }

      console.log("[VSP][DashForce] rendered dashboard from gate_root:", gateRoot);
    }

    // Run after DOM ready
    const kick = ()=> { renderDash().catch(e=>console.warn("[VSP][DashForce] render err", e)); };
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ()=> setTimeout(kick, 200));
    else setTimeout(kick, 200);

    // refresh timestamp / light update
    setInterval(()=> {
      if (!isDash()) return;
      if (document.visibilityState && document.visibilityState !== "visible") return;
      setText("vsp_dash_updated_at", new Date().toLocaleString());
    }, 15000);

  }catch(e){
    console.warn("[VSP][DashForce] init failed", e);
  }
})();
"""

p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended force-inject + gate_root hook block")
PY

echo "== node --check bundle =="
node --check static/js/vsp_bundle_commercial_v2.js
echo "[OK] syntax OK"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== HEAD /vsp5 =="
curl -sS -I "$BASE/vsp5" | sed -n '1,12p'
echo "[NEXT] Open $BASE/vsp5 and HARD reload (Ctrl+Shift+R)."
