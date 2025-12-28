#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 1) Write topbar JS (commercial, no noisy logs)
JS="static/js/vsp_topbar_commercial_v1.js"
mkdir -p "$(dirname "$JS")"
cat > "$JS" <<'JS'
/* VSP_TOPBAR_COMMERCIAL_V1 */
(() => {
  if (window.__vsp_topbar_commercial_v1) return;
  window.__vsp_topbar_commercial_v1 = true;

  const $ = (sel, root=document) => root.querySelector(sel);

  function envLabel(){
    const h = String(window.location.hostname || "");
    if (h.includes("staging")) return "STAGING";
    if (h.includes("localhost") || h.includes("127.0.0.1")) return "LOCAL";
    return "PROD";
  }

  function setText(id, v){
    const el = document.getElementById(id);
    if (el) el.textContent = (v == null ? "" : String(v));
  }

  function setPill(id, text, klass){
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = text;
    el.classList.remove("ok","warn","bad","muted");
    if (klass) el.classList.add(klass);
  }

  async function getJson(url, timeoutMs=6000){
    const c = new AbortController();
    const t = setTimeout(() => c.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal: c.signal, credentials: "same-origin"});
      if (!r.ok) throw new Error("HTTP " + r.status);
      return await r.json();
    } finally {
      clearTimeout(t);
    }
  }

  function wireExport(rid){
    const aCsv = $("#vspExportCsv");
    const aTgz = $("#vspExportTgz");
    if (aCsv) aCsv.href = `/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`;
    if (aTgz) aTgz.href = `/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}&scope=reports`;
  }

  function detectDegraded(summary){
    // Robust heuristics across versions
    if (!summary || typeof summary !== "object") return false;

    if (summary.degraded === true) return true;
    if (summary.degraded_tools && Number(summary.degraded_tools) > 0) return true;
    if (summary.degraded_count && Number(summary.degraded_count) > 0) return true;

    const tools = summary.tools || summary.by_tool || null;
    if (Array.isArray(tools)) {
      return tools.some(t => (t && (t.degraded === true || String(t.status||"").toUpperCase()==="DEGRADED")));
    }
    if (tools && typeof tools === "object") {
      return Object.values(tools).some(t => t && (t.degraded === true || String(t.status||"").toUpperCase()==="DEGRADED"));
    }
    return false;
  }

  function detectVerdict(summary){
    const cand = [
      summary.overall,
      summary.overall_status,
      summary.verdict,
      summary.gate,
      summary.gate_verdict,
    ].filter(Boolean)[0];
    return cand ? String(cand).toUpperCase() : "UNKNOWN";
  }

  function verdictClass(v){
    const x = String(v||"").toUpperCase();
    if (x.includes("GREEN") || x==="OK" || x==="PASS") return "ok";
    if (x.includes("AMBER") || x==="WARN") return "warn";
    if (x.includes("RED") || x==="FAIL" || x==="BLOCK") return "bad";
    return "muted";
  }

  async function main(){
    setText("vspEnv", envLabel());
    setText("vspLatestRid", "…");
    setPill("vspVerdictPill", "…", "muted");
    setPill("vspDegradedPill", "…", "muted");

    // Latest RID
    let rid = null;
    try{
      const runs = await getJson("/api/vsp/runs?limit=1", 7000);
      rid = (runs && runs.items && runs.items[0] && runs.items[0].run_id) ? runs.items[0].run_id : null;
    } catch(_) {}

    if (!rid){
      setText("vspLatestRid", "N/A");
      wireExport("N/A");
      setPill("vspVerdictPill", "UNKNOWN", "muted");
      setPill("vspDegradedPill", "UNKNOWN", "muted");
      return;
    }

    setText("vspLatestRid", rid);
    wireExport(rid);

    // Summary for verdict/degraded
    try{
      // Prefer run_file if gateway serves it
      const summary = await getJson(`/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/run_gate_summary.json")}`, 8000);
      const verdict = detectVerdict(summary);
      const degraded = detectDegraded(summary);

      setPill("vspVerdictPill", verdict, verdictClass(verdict));
      setPill("vspDegradedPill", degraded ? "DEGRADED" : "OK", degraded ? "warn" : "ok");
    } catch(_) {
      setPill("vspVerdictPill", "UNKNOWN", "muted");
      setPill("vspDegradedPill", "UNKNOWN", "muted");
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", main);
  } else {
    main();
  }
})();
JS
echo "[OK] wrote $JS"

# 2) Patch templates: rename Netguard marker + inject topbar + include JS
python3 - <<'PY'
from pathlib import Path
import re, time

ts = time.strftime("%Y%m%d_%H%M%S")

tpl_candidates = [
  "templates/vsp_5tabs_enterprise_v2.html",
  "templates/vsp_dashboard_2025.html",
  "templates/vsp_runs_reports_v1.html",
  "templates/vsp_data_source_2025.html",
  "templates/vsp_settings_2025.html",
  "templates/vsp_rule_overrides_2025.html",
  "templates/vsp_4tabs_commercial_v1.html",
]
tpls = [Path(p) for p in tpl_candidates if Path(p).exists()]

if not tpls:
  print("[WARN] no known templates found from candidates; please check your templates/ names.")
  raise SystemExit(0)

TOPBAR_MARK = "VSP_COMMERCIAL_TOPBAR_V1"
GUARD_OLD = "VSP_P1_NETGUARD_GLOBAL_V7B"
GUARD_NEW = "VSP_COMMERCIAL_GLOBAL_GUARD_V1"

topbar_html = f"""
<!-- {TOPBAR_MARK} -->
<style>
  .vsp-topbar {{
    position: sticky; top: 0; z-index: 999;
    display: flex; align-items: center; justify-content: space-between;
    padding: 10px 14px;
    background: rgba(12,16,22,0.92);
    border-bottom: 1px solid rgba(255,255,255,0.08);
    backdrop-filter: blur(10px);
  }}
  .vsp-topbar .left {{ display:flex; align-items:center; gap:12px; }}
  .vsp-topbar .brand {{ font-weight:700; letter-spacing:0.4px; }}
  .vsp-topbar .meta {{ display:flex; align-items:center; gap:10px; opacity:0.92; font-size: 12px; }}
  .vsp-pill {{
    display:inline-flex; align-items:center; gap:6px;
    padding: 2px 10px; border-radius: 999px;
    border: 1px solid rgba(255,255,255,0.14);
    font-size: 12px; line-height: 18px;
    background: rgba(255,255,255,0.04);
  }}
  .vsp-pill.ok {{ border-color: rgba(40,200,120,0.55); }}
  .vsp-pill.warn {{ border-color: rgba(240,180,40,0.65); }}
  .vsp-pill.bad {{ border-color: rgba(240,80,80,0.65); }}
  .vsp-pill.muted {{ opacity:0.75; }}
  .vsp-topbar .actions {{ display:flex; gap:10px; align-items:center; }}
  .vsp-btn {{
    display:inline-flex; align-items:center; gap:8px;
    padding: 7px 10px; border-radius: 10px;
    border: 1px solid rgba(255,255,255,0.12);
    text-decoration: none;
    font-size: 12px;
    background: rgba(255,255,255,0.04);
  }}
  .vsp-btn:hover {{ background: rgba(255,255,255,0.07); }}
  .vsp-mono {{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; }}
</style>

<div class="vsp-topbar">
  <div class="left">
    <div class="brand">VSP</div>
    <div class="meta">
      <span class="vsp-pill muted">ENV: <span id="vspEnv" class="vsp-mono">…</span></span>
      <span class="vsp-pill muted">RID: <span id="vspLatestRid" class="vsp-mono">…</span></span>
      <span id="vspVerdictPill" class="vsp-pill muted">…</span>
      <span id="vspDegradedPill" class="vsp-pill muted">…</span>
    </div>
  </div>
  <div class="actions">
    <a id="vspExportCsv" class="vsp-btn" href="/api/vsp/export_csv">Export CSV</a>
    <a id="vspExportTgz" class="vsp-btn" href="/api/vsp/export_tgz">Export TGZ</a>
  </div>
</div>
"""

def backup(p: Path):
  bak = p.with_name(p.name + f".bak_commercial_shell_{ts}")
  bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
  return bak

def patch_guard(s: str) -> str:
  # Rename visible marker strings (and avoid leaking "netguard")
  s = s.replace(GUARD_OLD, GUARD_NEW)
  s = s.replace("__vsp_p1_netguard_global_v7b", "__vsp_commercial_global_guard_v1")
  s = s.replace("netguard", "commercial_guard")
  return s

def inject_topbar(s: str) -> str:
  if TOPBAR_MARK in s:
    return s
  # Insert right after <body ...>
  m = re.search(r"<body[^>]*>", s, flags=re.I)
  if not m:
    return s + "\n" + topbar_html + "\n"
  ins_at = m.end()
  return s[:ins_at] + topbar_html + s[ins_at:]

def ensure_js_include(s: str) -> str:
  tag = '<script src="/static/js/vsp_topbar_commercial_v1.js?v={{ asset_v }}"></script>'
  if "vsp_topbar_commercial_v1.js" in s:
    return s
  # Insert before </body>
  if "</body>" in s:
    return s.replace("</body>", f"  {tag}\n</body>", 1)
  return s + "\n" + tag + "\n"

patched = []
for p in tpls:
  orig = p.read_text(encoding="utf-8", errors="replace")
  bak = backup(p)
  s = orig
  s2 = ensure_js_include(inject_topbar(patch_guard(s)))
  if s2 != orig:
    p.write_text(s2, encoding="utf-8")
    patched.append((str(p), str(bak)))

print("[OK] patched templates:", len(patched))
for a,b in patched:
  print(" -", a)
  print("   backup:", b)
PY

# 3) Optional: also scrub netguard marker from the main bundle if present (best-effort)
BUNDLE="static/js/vsp_bundle_commercial_v2.js"
if [ -f "$BUNDLE" ]; then
  cp -f "$BUNDLE" "${BUNDLE}.bak_scrub_guard_${TS}"
  python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")
s2=s.replace("VSP_P1_NETGUARD_GLOBAL_V7B","VSP_COMMERCIAL_GLOBAL_GUARD_V1")\
     .replace("__vsp_p1_netguard_global_v7b","__vsp_commercial_global_guard_v1")\
     .replace("netguard","commercial_guard")
if s2!=s:
  p.write_text(s2, encoding="utf-8")
  print("[OK] scrubbed bundle markers")
else:
  print("[OK] bundle had no netguard markers (no change)")
PY
else
  echo "[INFO] no $BUNDLE (skip bundle scrub)"
fi

echo "== quick greps (should be empty) =="
grep -RIn --exclude='*.bak_*' "NETGUARD\|netguard" templates static/js | head -n 20 || true

echo "[DONE] Commercial shell + topbar + guard applied."
