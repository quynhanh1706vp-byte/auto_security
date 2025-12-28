#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need find

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 1) Ensure topbar JS exists (keep same file name)
JS="static/js/vsp_topbar_commercial_v1.js"
mkdir -p "$(dirname "$JS")"
if [ ! -s "$JS" ]; then
  echo "[INFO] $JS missing/empty -> writing"
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

  async function getJson(url, timeoutMs=7000){
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
    if (!summary || typeof summary !== "object") return false;
    if (summary.degraded === true) return true;
    if (summary.degraded_tools && Number(summary.degraded_tools) > 0) return true;
    if (summary.degraded_count && Number(summary.degraded_count) > 0) return true;
    const tools = summary.tools || summary.by_tool || null;
    if (tools && typeof tools === "object") {
      return Object.values(tools).some(t => t && (t.degraded === true || String(t.status||"").toUpperCase()==="DEGRADED"));
    }
    return false;
  }

  function detectVerdict(summary){
    const cand = [
      summary.overall,          // <-- your summary has this: "RED"
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

    let rid = null;
    try{
      const runs = await getJson("/api/vsp/runs?limit=1", 8000);
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

    try{
      const summary = await getJson(`/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/run_gate_summary.json")}`, 9000);
      const verdict = detectVerdict(summary);
      const degraded = detectDegraded(summary);
      setPill("vspVerdictPill", verdict, verdictClass(verdict));
      setPill("vspDegradedPill", degraded ? "DEGRADED" : "OK", degraded ? "warn" : "ok");
    } catch(_) {
      setPill("vspVerdictPill", "UNKNOWN", "muted");
      setPill("vspDegradedPill", "UNKNOWN", "muted");
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
JS
fi
echo "[OK] ensured $JS"

python3 - <<'PY'
from pathlib import Path
import re, time

ts = time.strftime("%Y%m%d_%H%M%S")

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

js_tag = '<script src="/static/js/vsp_topbar_commercial_v1.js?v={{ asset_v }}"></script>'

def patch_guard(s: str) -> str:
  s = s.replace(GUARD_OLD, GUARD_NEW)
  s = s.replace("__vsp_p1_netguard_global_v7b", "__vsp_commercial_global_guard_v1")
  # scrub any leaked word
  s = re.sub(r'netguard', 'commercial_guard', s, flags=re.I)
  return s

def inject_topbar(s: str) -> str:
  if TOPBAR_MARK in s:
    return s
  m = re.search(r"<body[^>]*>", s, flags=re.I)
  if not m:
    return s
  ins = m.end()
  return s[:ins] + topbar_html + s[ins:]

def ensure_js(s: str) -> str:
  if "vsp_topbar_commercial_v1.js" in s:
    return s
  if "</body>" in s:
    return s.replace("</body>", f"  {js_tag}\n</body>", 1)
  return s + "\n" + js_tag + "\n"

tpl_root = Path("templates")
htmls = sorted(tpl_root.rglob("*.html"))

patched = 0
touched = []

for p in htmls:
  orig = p.read_text(encoding="utf-8", errors="replace")
  s = ensure_js(inject_topbar(patch_guard(orig)))
  if s != orig:
    bak = p.with_name(p.name + f".bak_commercial_shell_v2_{ts}")
    bak.write_text(orig, encoding="utf-8")
    p.write_text(s, encoding="utf-8")
    patched += 1
    touched.append(str(p))

print(f"[OK] patched html templates: {patched}/{len(htmls)}")
for x in touched[:30]:
  print(" -", x)
if len(touched) > 30:
  print(" ... +", len(touched)-30, "more")
PY

# 3) Best-effort scrub any netguard marker in static/js
# (some older builds may still have it)
for f in static/js/*.js; do
  [ -f "$f" ] || continue
  if grep -qi "netguard\|VSP_P1_NETGUARD_GLOBAL_V7B" "$f"; then
    cp -f "$f" "$f.bak_scrub_shell_v2_${TS}"
    python3 - <<PY
from pathlib import Path
import re
p=Path("$f")
s=p.read_text(encoding="utf-8", errors="replace")
s2=s.replace("VSP_P1_NETGUARD_GLOBAL_V7B","VSP_COMMERCIAL_GLOBAL_GUARD_V1")\
     .replace("__vsp_p1_netguard_global_v7b","__vsp_commercial_global_guard_v1")
s2=re.sub(r'netguard', 'commercial_guard', s2, flags=re.I)
if s2!=s:
  p.write_text(s2, encoding="utf-8")
  print("[OK] scrubbed:", p)
PY
  fi
done

echo "== grep should show NO netguard/NETGUARD in served assets =="
grep -RIn --exclude='*.bak_*' "VSP_P1_NETGUARD_GLOBAL_V7B\|netguard\|NETGUARD" templates static/js | head -n 30 || true

echo "[DONE] v2 patch applied. RESTART gunicorn to reload templates."
