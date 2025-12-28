#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need ss; need curl
command -v node >/dev/null 2>&1 && HAVE_NODE=1 || HAVE_NODE=0

TS="$(date +%Y%m%d_%H%M%S)"

# -------------------- 1) Template: early console filter (V3) - SAFE replace (no bad \s) --------------------
TPL="templates/vsp_5tabs_enterprise_v2.html"
if [ -f "$TPL" ]; then
  cp -f "$TPL" "${TPL}.bak_console_v3b_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re

p = Path("templates/vsp_5tabs_enterprise_v2.html")
s = p.read_text(encoding="utf-8", errors="replace")

MARK_V2 = "VSP_P1_EARLY_CONSOLE_FILTER_V2"
MARK_V3 = "VSP_P1_EARLY_CONSOLE_FILTER_V3"

block = """<!-- VSP_P1_EARLY_CONSOLE_FILTER_V3 -->
<script id="VSP_P1_EARLY_CONSOLE_FILTER_V3">
(()=> {
  if (window.__vsp_p1_early_console_filter_v3) return;
  window.__vsp_p1_early_console_filter_v3 = true;

  // drop ONLY our noisy diagnostics (keep real errors)
  const DROP_ANY = [
    /\\[VSP\\]\\[P1\\]\\s*(fetch wrapper enabled|runs-fail banner auto-clear enabled|fetch limit patched|nav dedupe applied|rule overrides metrics\\/table synced)/i,
    /\\[VSP\\]\\[P1\\]\\s*(cleared stale RUNS API FAIL banner)/i,
    /\\[VSP\\]\\[DASH\\].*(check ids|ids=)/i,
    /\\bgave up\\b.*\\(chart\\/container missing\\)/i,
    /\\bchart\\/container missing\\b/i,
    /\\bcanvas-rendered\\b/i,
    /\\bChartJs\\s*=\\s*false\\b/i
  ];

  function s0(args){
    try{
      if (!args || !args.length) return "";
      if (typeof args[0] === "string") return args[0];
      return String(args[0] ?? "");
    }catch(_){ return ""; }
  }
  function shouldDrop(args){
    const t = s0(args);
    return DROP_ANY.some(rx => rx.test(t));
  }

  const wrap = (k) => {
    const orig = console[k] ? console[k].bind(console) : null;
    if (!orig) return;
    console[k] = (...a) => shouldDrop(a) ? void 0 : orig(...a);
  };

  ["log","info","warn","error","debug"].forEach(wrap);
})();
</script>
"""

if MARK_V3 in s:
    print("[OK] template already has", MARK_V3)
    raise SystemExit(0)

# Replace V2 block if exists (IMPORTANT: repl is a function => no replacement-escape parsing)
if MARK_V2 in s:
    pat = r'<!--\s*VSP_P1_EARLY_CONSOLE_FILTER_V2\s*-->.*?<script[^>]*id="VSP_P1_EARLY_CONSOLE_FILTER_V2"[^>]*>.*?</script>\s*'
    s2, n = re.subn(pat, lambda m: block + "\n", s, count=1, flags=re.I|re.S)
    if n == 0:
        # fallback: just remove the V2 script tag by id
        pat2 = r'<script[^>]*id="VSP_P1_EARLY_CONSOLE_FILTER_V2"[^>]*>.*?</script>\s*'
        s3, n2 = re.subn(pat2, lambda m: "", s, count=1, flags=re.I|re.S)
        s2 = s3
    # insert V3 after <head>
    m = re.search(r"<head[^>]*>", s2, flags=re.I)
    if not m:
        raise SystemExit("[ERR] <head> not found")
    pos = m.end()
    out = s2[:pos] + "\n" + block + "\n" + s2[pos:]
    p.write_text(out, encoding="utf-8")
    print("[OK] replaced V2 -> injected V3 early console filter")
else:
    m = re.search(r"<head[^>]*>", s, flags=re.I)
    if not m:
        raise SystemExit("[ERR] <head> not found")
    pos = m.end()
    out = s[:pos] + "\n" + block + "\n" + s[pos:]
    p.write_text(out, encoding="utf-8")
    print("[OK] injected V3 early console filter")
PY
else
  echo "[WARN] missing $TPL (skip template patch)"
fi

# -------------------- 2) Bundle: donut overlay + clear degraded (V3B) --------------------
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
cp -f "$JS" "${JS}.bak_polish_v3b_${TS}"
echo "[BACKUP] ${JS}.bak_polish_v3b_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_commercial_v2.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_POLISH_FINAL_V3B"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

patch = r"""
/* === VSP_P1_POLISH_FINAL_V3B === */
(()=> {
  if (window.__vsp_p1_polish_final_v3b) return;
  window.__vsp_p1_polish_final_v3b = true;

  // A) Clear degraded toast/state once /api/vsp/runs is OK again
  try{
    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (_fetch && !window.__vsp_p1_fetchhook_clear_degraded_v3b){
      window.__vsp_p1_fetchhook_clear_degraded_v3b = true;
      window.fetch = async (...args) => {
        const res = await _fetch(...args);
        try{
          const u = (args && args[0] && args[0].url) ? String(args[0].url) : String(args[0]||"");
          if (u.includes("/api/vsp/runs") && res && res.ok){
            window.__vsp_runs_last_ok = Date.now();
            if (typeof window.__vsp_set_degraded === "function") window.__vsp_set_degraded(false, "");
            if (window.VSP && typeof window.VSP.setDegraded === "function") window.VSP.setDegraded(false, "");
            // remove any toast-like node containing "degraded" + "runs"
            const cand = Array.from(document.querySelectorAll("div,span")).find(el => {
              const t=(el.textContent||"").toLowerCase();
              return t.includes("degraded") && t.includes("runs");
            });
            if (cand) cand.remove();
          }
        }catch(_){}
        return res;
      };
    }
  }catch(_){}

  // B) Donut overlay: robust attach + z-index above canvas + observer
  function findTotal(){
    try{
      const hit = Array.from(document.querySelectorAll("*")).find(el => (el.textContent||"").trim()==="TOTAL FINDINGS");
      if (!hit) return "";
      const box = hit.closest("div") || hit.parentElement;
      if (!box) return "";
      const t = (box.textContent||"").replace(/\s+/g," ");
      const m = t.match(/TOTAL FINDINGS\s*([0-9][0-9,]*)/i);
      return m ? m[1].replace(/,/g,"") : "";
    }catch(_){ return ""; }
  }

  function getSeverityCard(){
    try{
      const h = Array.from(document.querySelectorAll("*")).find(el => (el.textContent||"").trim()==="SEVERITY DISTRIBUTION");
      if (!h) return null;
      return h.closest("div") || h.parentElement || null;
    }catch(_){ return null; }
  }

  function findSample(card){
    try{
      const leaf = Array.from(card.querySelectorAll("*")).filter(el => el.children.length===0);
      for (const el of leaf){
        const tx = (el.textContent||"").trim();
        const m = tx.match(/^(\d[\d,]*)\s*total$/i);
        if (m) return {el, n:m[1].replace(/,/g,"")};
      }
    }catch(_){}
    return {el:null, n:""};
  }

  function ensureOverlay(card, sample, total){
    const id="vsp_donut_overlay_sample_total_v3b";
    let ov=document.getElementById(id);

    const canvas = card.querySelector("canvas");
    const host = (canvas && canvas.parentElement) ? canvas.parentElement : card;
    if (!host) return;

    const st = getComputedStyle(host);
    if (st.position==="static") host.style.position="relative";

    if (!ov){
      ov=document.createElement("div");
      ov.id=id;
      ov.style.position="absolute";
      ov.style.inset="0";
      ov.style.display="flex";
      ov.style.alignItems="center";
      ov.style.justifyContent="center";
      ov.style.pointerEvents="none";
      ov.style.fontWeight="700";
      ov.style.fontSize="14px";
      ov.style.lineHeight="1.2";
      ov.style.opacity="0.95";
      ov.style.zIndex="999"; // MUST be above canvas
      ov.style.textAlign="center";
      host.appendChild(ov);
    } else {
      if (ov.parentElement !== host) host.appendChild(ov);
      ov.style.zIndex="999";
    }

    ov.textContent = `${sample} sample / ${total} total`;
  }

  function apply(){
    try{
      const total = findTotal();
      const card = getSeverityCard();
      if (!total || !card) return;
      const {el:oldLabel, n:sample} = findSample(card);
      if (!sample) return;

      ensureOverlay(card, sample, total);

      if (oldLabel){
        oldLabel.style.opacity="0";
        oldLabel.style.height="0";
      }
    }catch(_){}
  }

  setTimeout(apply, 300);
  setTimeout(apply, 900);
  setTimeout(apply, 1800);
  setTimeout(apply, 3200);

  try{
    const card = getSeverityCard();
    if (card && !window.__vsp_p1_donut_observer_v3b){
      window.__vsp_p1_donut_observer_v3b=true;
      const mo = new MutationObserver(()=>apply());
      mo.observe(card, {subtree:true, childList:true, characterData:true});
    }
  }catch(_){}
})();
"""
p.write_text(s.rstrip()+"\n\n"+patch+"\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

if [ "$HAVE_NODE" = "1" ]; then
  node --check "$JS" >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 3; }
fi

# -------------------- 3) Restart :8910 (strict-ish) --------------------
echo "== restart :8910 =="
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910/ {gsub(/users:\(\(\"/,""); print $0}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[INFO] killing pids: $PIDS"
  kill -9 $PIDS || true
fi

if [ -x "bin/p1_ui_8910_single_owner_start_v2.sh" ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh || true
fi

echo "DONE. Ctrl+F5 /vsp5 then check: donut shows 'sample / total' + console cleaner + degraded toast clears."
