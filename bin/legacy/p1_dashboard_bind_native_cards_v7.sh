#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_bind_${TS}"
echo "[BACKUP] ${JS}.bak_dash_bind_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_DASH_BIND_NATIVE_CARDS_V7"
if marker in s:
    print("[OK] marker already present, skip")
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* VSP_P1_DASH_BIND_NATIVE_CARDS_V7
   - non-invasive: try to locate existing KPI cards by label text and update values/colors
   - if not found: do nothing (overlay KPI strip remains)
*/
(()=> {
  if (window.__vsp_p1_dash_bind_native_cards_v7) return;
  window.__vsp_p1_dash_bind_native_cards_v7 = true;

  function isDash(){
    try{
      const p = (location && location.pathname) ? location.pathname : "";
      return (p === "/vsp5" || p === "/dashboard" || /\/vsp5\/?$/.test(p) || /\/dashboard\/?$/.test(p));
    }catch(e){ return false; }
  }
  if (!isDash()) return;

  function norm(s){ return (s||"").toString().trim().toUpperCase(); }

  function badgeColors(ov){
    const s = norm(ov) || "UNKNOWN";
    let bg="rgba(255,255,255,0.06)", bd="rgba(255,255,255,0.10)";
    if (s==="GREEN"||s==="OK"||s==="PASS"){ bg="rgba(46,204,113,0.12)"; bd="rgba(46,204,113,0.25)"; }
    else if (s==="AMBER"||s==="WARN"){ bg="rgba(241,196,15,0.12)"; bd="rgba(241,196,15,0.25)"; }
    else if (s==="RED"||s==="FAIL"||s==="BLOCK"){ bg="rgba(231,76,60,0.12)"; bd="rgba(231,76,60,0.25)"; }
    else if (s==="DEGRADED"){ bg="rgba(155,89,182,0.12)"; bd="rgba(155,89,182,0.25)"; }
    return {bg, bd, s};
  }

  // Find a KPI "card" that contains a label text (e.g., HIGH) and has a number element
  function findCardByLabel(label){
    label = norm(label);
    const all = Array.from(document.querySelectorAll("div,section,article"));
    // prefer smaller cards: limit by text length
    for (const el of all){
      const t = norm(el.textContent || "");
      if (!t) continue;
      if (!t.includes(label)) continue;
      // heuristics: must be relatively short and contain digits placeholder
      if (t.length > 120) continue;
      // look for a big-number element inside
      const candidates = Array.from(el.querySelectorAll("div,span,p,h1,h2,h3"))
        .filter(x => /\d|--/.test((x.textContent||"").trim()) && (x.textContent||"").trim().length <= 10);
      if (candidates.length){
        return {card: el, valueEl: candidates.sort((a,b)=> (b.clientHeight||0)-(a.clientHeight||0))[0]};
      }
    }
    return null;
  }

  function setCard(label, val){
    const hit = findCardByLabel(label);
    if (!hit) return false;
    hit.valueEl.textContent = (val===undefined || val===null) ? "--" : String(val);
    return true;
  }

  function setOverall(ov){
    // try badge element first
    const b = badgeColors(ov);
    const nodes = Array.from(document.querySelectorAll("span,div"))
      .filter(x => /OVERALL/i.test(x.textContent||"") && (x.textContent||"").length < 40);
    if (nodes.length){
      const n = nodes[0];
      n.textContent = `OVERALL: ${b.s}`;
      n.style.background = b.bg;
      n.style.border = `1px solid ${b.bd}`;
      n.style.borderRadius = "999px";
      n.style.padding = "4px 10px";
      return true;
    }
    // fallback: overall card
    const hit = findCardByLabel("OVERALL");
    if (hit){
      hit.valueEl.textContent = b.s;
      hit.card.style.background = b.bg;
      hit.card.style.borderColor = b.bd;
      return true;
    }
    return false;
  }

  // Expose binder for the live module (V6) to call if present
  window.__vsp_dash_bind_native_cards_v7_apply = (gate)=>{
    try{
      const ct = (gate && (gate.counts_total || gate.counts || gate.totals)) ? (gate.counts_total || gate.counts || gate.totals) : {};
      const total = (ct.HIGH||0)+(ct.MEDIUM||0)+(ct.LOW||0)+(ct.INFO||0)+(ct.CRITICAL||0)+(ct.TRACE||0);

      // attempt set numbers
      setCard("TOTAL", total);
      setCard("HIGH", ct.HIGH);
      setCard("MEDIUM", ct.MEDIUM);
      setCard("LOW", ct.LOW);
      setCard("INFO", ct.INFO);
      setCard("CRITICAL", ct.CRITICAL);

      setOverall(gate && (gate.overall || gate.overall_status));

      return true;
    }catch(e){
      return false;
    }
  };
})();
""").rstrip() + "\n"

p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended", marker)
PY

sudo systemctl restart vsp-ui-8910.service || true
sleep 1.2
echo "[DONE] Native KPI binder installed. Open /vsp5 and refresh once."
