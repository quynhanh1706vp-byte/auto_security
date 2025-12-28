#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need curl

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

CSS="static/css/vsp_polish_p2_v1.css"
JS="static/js/vsp_polish_apply_p2_v1.js"

mkdir -p static/css static/js

# 1) Write CSS (safe: new file)
cat > "$CSS" <<'CSS'
/* VSP_P2_POLISH_V1 (safe add-on) */
:root{
  --vsp-card-bg: rgba(255,255,255,0.035);
  --vsp-card-br: rgba(255,255,255,0.085);
  --vsp-card-br2: rgba(255,255,255,0.12);
  --vsp-card-shadow: 0 10px 28px rgba(0,0,0,0.35);
  --vsp-radius: 18px;
  --vsp-pad: 14px;
  --vsp-gap: 12px;
}

.vsp-panel{
  background: linear-gradient(180deg, rgba(255,255,255,0.04), rgba(255,255,255,0.02));
  border: 1px solid var(--vsp-card-br);
  border-radius: var(--vsp-radius);
  box-shadow: var(--vsp-card-shadow);
  padding: var(--vsp-pad);
  backdrop-filter: blur(8px);
}

.vsp-card{
  background: var(--vsp-card-bg);
  border: 1px solid var(--vsp-card-br);
  border-radius: calc(var(--vsp-radius) - 2px);
  padding: var(--vsp-pad);
  box-shadow: 0 6px 18px rgba(0,0,0,0.25);
}

.vsp-card:hover{
  border-color: var(--vsp-card-br2);
  transform: translateY(-1px);
  transition: 140ms ease;
}

.vsp-kpi-grid{
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: var(--vsp-gap);
  align-items: stretch;
}

@media (max-width: 1300px){
  .vsp-kpi-grid{ grid-template-columns: repeat(2, minmax(0, 1fr)); }
}
@media (max-width: 700px){
  .vsp-kpi-grid{ grid-template-columns: 1fr; }
}

.vsp-kpi-card{
  min-height: 92px;
  display:flex;
  flex-direction:column;
  justify-content:space-between;
  gap: 8px;
}

.vsp-kpi-title{
  font-size: 12px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  opacity: 0.85;
}

.vsp-kpi-value{
  font-size: 28px;
  font-weight: 760;
  line-height: 1.05;
}

.vsp-kpi-sub{
  font-size: 12px;
  opacity: 0.7;
}

.vsp-chip{
  display:inline-flex;
  align-items:center;
  gap:8px;
  padding: 6px 10px;
  border-radius: 999px;
  border: 1px solid var(--vsp-card-br);
  background: rgba(255,255,255,0.03);
  font-size: 12px;
}

.vsp-section-title{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap: 10px;
  margin: 2px 0 10px 0;
}
.vsp-section-title h2,
.vsp-section-title h3{
  margin: 0;
}

.vsp-table-tight table{
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
}
.vsp-table-tight th,
.vsp-table-tight td{
  padding: 10px 10px;
  border-bottom: 1px solid rgba(255,255,255,0.06);
  vertical-align: top;
}
.vsp-table-tight thead th{
  position: sticky;
  top: 0;
  background: rgba(15,17,22,0.92);
  backdrop-filter: blur(6px);
  z-index: 2;
}

CSS
ok "write CSS: $CSS"

# 2) Write JS applier (defensive: no DOM assumptions, no crashes)
cat > "$JS" <<'JS'
/* VSP_P2_POLISH_V1 (safe applier) */
(function(){
  if (window.__VSP_P2_POLISH_V1__) return;
  window.__VSP_P2_POLISH_V1__ = { ok: true, ts: Date.now() };

  function onReady(fn){
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fn);
    else fn();
  }

  function addClass(el, cls){
    if (!el) return;
    cls.split(/\s+/).filter(Boolean).forEach(c => el.classList.add(c));
  }

  function polish(){
    try{
      var path = (location && location.pathname) ? location.pathname : "";
      // Apply mainly for /vsp5, but harmless elsewhere
      var root = document.getElementById("vsp-dashboard-main") || document.body;
      if (!root) return;

      // KPI grid heuristics
      var kpiGrid =
        document.querySelector("#vsp-kpi-grid") ||
        document.querySelector(".vsp-kpi-grid") ||
        document.querySelector(".kpi-grid") ||
        document.querySelector("[data-kpi-grid]");

      if (kpiGrid) addClass(kpiGrid, "vsp-kpi-grid");

      // KPI cards heuristics
      var kpiCards = [];
      [
        ".kpi-card",
        ".vsp-kpi-card",
        "[data-kpi-card]",
        ".kpi",
        ".kpiItem",
        ".kpi-item"
      ].forEach(sel => {
        document.querySelectorAll(sel).forEach(el => kpiCards.push(el));
      });

      // De-dup
      kpiCards = Array.from(new Set(kpiCards));

      kpiCards.forEach(function(card){
        addClass(card, "vsp-card vsp-kpi-card");

        // Try to tag inner text nodes if structure is simple
        // Title
        var title = card.querySelector(".title, .kpi-title, h4, h5");
        if (title) addClass(title, "vsp-kpi-title");
        // Value
        var val = card.querySelector(".value, .kpi-value, .num, .number, strong");
        if (val) addClass(val, "vsp-kpi-value");
        // Sub
        var sub = card.querySelector(".sub, .hint, .desc, small");
        if (sub) addClass(sub, "vsp-kpi-sub");
      });

      // Section panels: wrap common blocks
      var sections = [];
      [
        ".vsp-section",
        ".section",
        ".panel",
        ".box",
        ".card"
      ].forEach(sel => {
        document.querySelectorAll(sel).forEach(el => sections.push(el));
      });
      sections = Array.from(new Set(sections));

      sections.forEach(function(el){
        // Skip KPI cards already styled
        if (el.classList && el.classList.contains("vsp-kpi-card")) return;

        // Make bigger containers look like panels
        var rect = el.getBoundingClientRect ? el.getBoundingClientRect() : null;
        var big = rect ? (rect.width > 420 && rect.height > 120) : true;
        if (big) addClass(el, "vsp-panel");
      });

      // Tables tighten (for data_source / runs too, safe)
      document.querySelectorAll("table").forEach(function(tbl){
        var host = tbl.closest(".vsp-table-tight") || tbl.parentElement;
        if (host) addClass(host, "vsp-table-tight");
      });

      // Optional: add a clean section title wrapper if header exists
      document.querySelectorAll("h2, h3").forEach(function(h){
        if (!h || !h.parentElement) return;
        // already wrapped?
        if (h.parentElement.classList && h.parentElement.classList.contains("vsp-section-title")) return;
        // if next sibling is actions (buttons/links), wrap
        var next = h.nextElementSibling;
        if (next && (next.matches("div") || next.matches("nav"))){
          var wrap = document.createElement("div");
          wrap.className = "vsp-section-title";
          h.parentElement.insertBefore(wrap, h);
          wrap.appendChild(h);
          wrap.appendChild(next);
        }
      });

      // Mark
      window.__VSP_P2_POLISH_V1__.applied = true;
      window.__VSP_P2_POLISH_V1__.path = path;
    }catch(e){
      window.__VSP_P2_POLISH_V1__.err = String(e && e.message ? e.message : e);
    }
  }

  onReady(polish);
})();
JS
ok "write JS: $JS"

# 3) Inject into templates (idempotent)
python3 - <<'PY'
from pathlib import Path
import re, sys

css = "vsp_polish_p2_v1.css"
js  = "vsp_polish_apply_p2_v1.js"

tpl_dir = Path("templates")
if not tpl_dir.exists():
    print("[WARN] templates/ not found; skipping injection")
    sys.exit(0)

files = sorted([p for p in tpl_dir.rglob("*.html")])
hit = 0
patched = 0

for p in files:
    s = p.read_text(encoding="utf-8", errors="replace")
    if "vsp_cio_shell_v1.css" not in s and "vsp_cio_shell_apply_v1.js" not in s:
        continue
    hit += 1
    orig = s

    # CSS link insert after cio css (or before </head>)
    if css not in s:
        m = re.search(r'(<link[^>]+vsp_cio_shell_v1\.css[^>]*>)', s)
        if m:
            ins = m.group(1) + f'\n  <link rel="stylesheet" href="/static/css/{css}?v=p2_polish">'
            s = s.replace(m.group(1), ins, 1)
        else:
            s = re.sub(r'(</head>)', f'  <link rel="stylesheet" href="/static/css/{css}?v=p2_polish">\\n\\1', s, count=1)

    # JS insert after cio apply (or before </body>)
    if js not in s:
        m = re.search(r'(<script[^>]+vsp_cio_shell_apply_v1\.js[^>]*></script>)', s)
        if m:
            ins = m.group(1) + f'\n  <script src="/static/js/{js}?v=p2_polish"></script>'
            s = s.replace(m.group(1), ins, 1)
        else:
            s = re.sub(r'(</body>)', f'  <script src="/static/js/{js}?v=p2_polish"></script>\\n\\1', s, count=1)

    if s != orig:
        b = p.with_suffix(p.suffix + ".bak_p2polish")
        if not b.exists():
            b.write_text(orig, encoding="utf-8")
        p.write_text(s, encoding="utf-8")
        patched += 1

print(f"[OK] templates_hit={hit} patched={patched}")
PY

# 4) Restart service (best-effort)
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.3
  systemctl is-active "$SVC" >/dev/null 2>&1 && ok "service active: $SVC" || warn "service not active? check: systemctl status $SVC"
else
  warn "systemctl not found; skip restart"
fi

# 5) Smoke: endpoints + assets
curl -fsS "$BASE/vsp5" >/dev/null && ok "GET /vsp5 OK" || err "GET /vsp5 FAIL"
curl -fsS "$BASE/static/css/vsp_polish_p2_v1.css" >/dev/null && ok "CSS served" || err "CSS not served"
curl -fsS "$BASE/static/js/vsp_polish_apply_p2_v1.js" >/dev/null && ok "JS served" || err "JS not served"

# 6) Re-run GateA if exists
GATE="bin/p0_gateA_luxe_only_vsp5_no_out_v1.sh"
if [ -f "$GATE" ]; then
  ok "run GateA: $GATE"
  bash "$GATE"
else
  warn "GateA script not found: $GATE (skip)"
fi

ok "DONE P2 polish v1"
