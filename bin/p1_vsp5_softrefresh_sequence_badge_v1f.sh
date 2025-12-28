#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_v1f_${TS}"
echo "[BACKUP] ${JS}.bak_v1f_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_VSP5_SOFTREFRESH_SEQ_BADGE_V1F"
if MARK in s:
  print("[SKIP] already installed v1f")
  raise SystemExit(0)

# Ensure the functions exist; otherwise we still install but will fallback safely at runtime
has_gate = "refreshFromGateSummary" in s
has_top  = "loadTopFindings" in s
has_rend = re.search(r"\brender\s*\(", s) is not None

inject = textwrap.dedent(f"""
/* ===================== {MARK} ===================== */
(()=>{{
  if (window.__vsp_p1_vsp5_softrefresh_seq_badge_v1f) return;
  window.__vsp_p1_vsp5_softrefresh_seq_badge_v1f = true;

  function followOn(){{
    try {{
      return (localStorage.getItem("vsp_follow_latest") ?? "on") !== "off";
    }} catch(e) {{
      return true;
    }}
  }}

  function ensureBadge(){{
    let el = document.getElementById("vsp_refresh_badge_v1f");
    if (el) return el;
    el = document.createElement("div");
    el.id = "vsp_refresh_badge_v1f";
    el.style.cssText = "position:fixed;z-index:99998;top:52px;right:12px;display:none;background:rgba(10,18,32,.82);border:1px solid rgba(255,255,255,.10);backdrop-filter: blur(10px);padding:6px 10px;border-radius:999px;font:12px/1.2 system-ui,Segoe UI,Roboto;color:#cfe3ff;box-shadow:0 10px 30px rgba(0,0,0,.35)";
    el.textContent = "Updating…";
    document.body.appendChild(el);
    return el;
  }}

  function showBadge(msg){{
    try {{
      const el = ensureBadge();
      el.textContent = msg || "Updating…";
      el.style.display = "block";
    }} catch(e) {{}}
  }}
  function hideBadge(){{
    try {{
      const el = document.getElementById("vsp_refresh_badge_v1f");
      if (el) el.style.display = "none";
    }} catch(e) {{}}
  }}

  async function doRefreshSequence(newRid, prevRid){{
    // best effort: call known functions if present
    { "try { await refreshFromGateSummary(); } catch(e) {}" if has_gate else "/* refreshFromGateSummary not found */" }
    { "try { await loadTopFindings(); } catch(e) {}" if has_top else "/* loadTopFindings not found */" }
    { "try { render(); } catch(e) {}" if has_rend else "/* render() not found */" }
  }}

  // Override soft refresh apply with explicit sequence for /vsp5
  const __old = window.__vsp_soft_refresh_apply;
  window.__vsp_soft_refresh_apply = function(newRid, prevRid){{
    try {{
      if (!followOn()) return false; // when OFF -> allow fallback behavior (or pinned mode in P2)
      if (!newRid) return false;
      if (newRid === prevRid) return true;

      // update state/global
      try {{ window.__vsp_rid_prev = prevRid || window.__vsp_rid_prev || null; }} catch(e) {{}}
      try {{ window.__vsp_rid_latest = newRid; }} catch(e) {{}}
      try {{ if (typeof state === "object" && state) state.rid = newRid; }} catch(e) {{}}

      // update rid labels if any
      try {{
        const ids = ["rid_txt","rid_val","rid_text","rid_label"];
        for (const id of ids) {{
          const el = document.getElementById(id);
          if (el) el.textContent = newRid;
        }}
      }} catch(e) {{}}

      // fire refresh async
      showBadge("Updating: " + newRid);
      Promise.resolve(doRefreshSequence(newRid, prevRid))
        .catch(()=>{{}})
        .finally(()=>{{ setTimeout(hideBadge, 350); }});
      return true;
    }} catch(e) {{
      // fallback to old handler if present
      try {{ return __old ? __old(newRid, prevRid) : false; }} catch(_) {{ return false; }}
    }}
  }};

  // Also respond to rid_changed events without recursion
  window.addEventListener("vsp:rid_changed", (ev)=>{{
    try {{
      const d = ev && ev.detail ? ev.detail : null;
      const rid = d && d.rid ? d.rid : (window.__vsp_rid_latest||null);
      const prev = d && d.prev ? d.prev : (window.__vsp_rid_prev||null);
      window.__vsp_soft_refresh_apply && window.__vsp_soft_refresh_apply(rid, prev);
    }} catch(e) {{}}
  }}, {{passive:true}});
}})();
/* ===================== /{MARK} ===================== */
""")

# Place near end of file for minimal interference
p.write_text(s + "\n\n" + inject + "\n", encoding="utf-8")
print("[OK] appended v1f soft refresh sequence + badge")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check passed"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] v1f applied"
