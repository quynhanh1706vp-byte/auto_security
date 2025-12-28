#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_auditbtn_${TS}"
echo "[BACKUP] ${JS}.bak_auditbtn_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RUNS_AUDIT_PACK_BTN_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = textwrap.dedent(r"""
/* ===================== VSP_P1_RUNS_AUDIT_PACK_BTN_V1 ===================== */
(function(){
  if (window.__vsp_p1_runs_audit_pack_btn_v1) return;
  window.__vsp_p1_runs_audit_pack_btn_v1 = true;

  function qs(sel, root){ try { return (root||document).querySelector(sel); } catch(e){ return null; } }
  function qsa(sel, root){ try { return Array.from((root||document).querySelectorAll(sel)); } catch(e){ return []; } }

  function ridFromHref(href){
    if (!href) return "";
    try {
      // match ?rid=... or &rid=...
      const m = href.match(/[?&]rid=([^&]+)/i);
      if (m && m[1]) return decodeURIComponent(m[1]);
    } catch(e){}
    return "";
  }

  function makeBtn(rid){
    const a = document.createElement("a");
    a.className = "vsp-btn vsp-btn-mini vsp-btn-ghost";
    a.textContent = "Audit Pack";
    a.href = "/api/vsp/audit_pack?rid=" + encodeURIComponent(rid);
    a.target = "_blank";
    a.rel = "noopener";
    a.style.marginLeft = "8px";
    a.title = "Download audit evidence pack for RID=" + rid;
    return a;
  }

  function alreadyHasAudit(container, rid){
    const links = qsa('a[href*="/api/vsp/audit_pack?rid="]', container);
    for (const x of links){
      const r = ridFromHref(x.getAttribute("href")||"");
      if (r === rid) return true;
    }
    return false;
  }

  function attachAuditButtons(){
    // Strategy: find existing export links and attach next to them
    const exportLinks = qsa('a[href*="/api/vsp/export_tgz?rid="],a[href*="/api/vsp/export_csv?rid="],a[href*="/api/vsp/export_html?rid="]');
    for (const a of exportLinks){
      const href = a.getAttribute("href") || "";
      const rid = ridFromHref(href);
      if (!rid) continue;

      const parent = a.parentElement || a.closest("td") || a.closest("div") || document.body;
      if (!parent) continue;
      if (alreadyHasAudit(parent, rid)) continue;

      // attach after the tgz link if possible
      parent.appendChild(makeBtn(rid));
    }
  }

  // run now + re-run a few times (table may render async)
  let tries = 0;
  const timer = setInterval(()=>{
    tries++;
    try { attachAuditButtons(); } catch(e){}
    if (tries >= 15) clearInterval(timer);
  }, 600);

  // also rerun on user clicks in runs area (pagination/filter)
  document.addEventListener("click", (ev)=>{
    const t = ev.target;
    if (!t) return;
    const root = t.closest ? (t.closest("#runs") || t.closest("[data-tab='runs']") || t.closest("main") ) : null;
    if (root) { setTimeout(()=>{ try{ attachAuditButtons(); }catch(e){} }, 250); }
  }, true);
})();
 /* ===================== /VSP_P1_RUNS_AUDIT_PACK_BTN_V1 ===================== */
""")

# Append at end (safe)
s2 = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended marker:", MARK)
PY

# quick js sanity: node --check if available
if command -v node >/dev/null 2>&1; then
  node --check "$JS"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] audit pack button patch installed."
