#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TO="$(command -v timeout || true)"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need curl

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

JS1="static/js/vsp_polish_apply_p2_v1.js"
CSS1="static/css/vsp_polish_p2_v1.css"

# 0) quick fetch check (prove hang)
fetch(){
  local url="$1"
  if [ -n "$TO" ]; then
    $TO 4s curl -fsS --connect-timeout 1 --max-time 3 "$url" >/dev/null
  else
    curl -fsS --connect-timeout 1 --max-time 3 "$url" >/dev/null
  fi
}

# 1) If JS exists, replace with NO-OP immediately (rescue)
if [ -f "$JS1" ]; then
  cp -f "$JS1" "${JS1}.bak_hang_${TS}"
  ok "backup: ${JS1}.bak_hang_${TS}"

  cat > "$JS1" <<'JS'
/* RESCUE: disable heavy polish to prevent browser hang */
(function(){
  window.__VSP_P2_POLISH_V1__ = { disabled:true, ts: Date.now() };
  // Do nothing.
  return;
})();
JS
  ok "patched NO-OP: $JS1"
else
  warn "missing $JS1 (skip rescue no-op)"
fi

# 2) Install SAFE polish v2 (new file name) - scoped + capped + no getBoundingClientRect
JS2="static/js/vsp_polish_apply_p2_safe_v2.js"
cp -f "$JS2" "${JS2}.bak_${TS}" 2>/dev/null || true

cat > "$JS2" <<'JS'
/* VSP_P2_POLISH_SAFE_V2: scoped, capped, no layout-thrash */
(function(){
  if (window.__VSP_P2_POLISH_SAFE_V2__) return;
  window.__VSP_P2_POLISH_SAFE_V2__ = { ok:true, ts: Date.now() };

  function onReady(fn){
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fn, {once:true});
    else fn();
  }
  function add(el, cls){
    if (!el || !el.classList) return;
    cls.split(/\s+/).filter(Boolean).forEach(c => el.classList.add(c));
  }
  function q(root, sel){ try{ return root.querySelector(sel); }catch(_){ return null; } }
  function qa(root, sel){ try{ return Array.from(root.querySelectorAll(sel)); }catch(_){ return []; } }

  function apply(){
    try{
      // Only polish /vsp5 (dashboard). Others skip to avoid any risk.
      var p = (location && location.pathname) ? location.pathname : "";
      if (p !== "/vsp5") { window.__VSP_P2_POLISH_SAFE_V2__.skip = p; return; }

      var root = document.getElementById("vsp-dashboard-main") || document.body;
      if (!root) return;

      // KPI grid: prefer explicit ids/classes only
      var kpiGrid = q(root, "#vsp-kpi-grid") || q(root, ".vsp-kpi-grid") || q(root, "[data-kpi-grid]");
      if (kpiGrid) add(kpiGrid, "vsp-kpi-grid");

      // KPI cards: cap to avoid huge loops
      var kpiCards = qa(root, ".kpi-card, [data-kpi-card], .vsp-kpi-card");
      if (kpiCards.length > 80) kpiCards = kpiCards.slice(0, 80);
      kpiCards.forEach(function(card){
        add(card, "vsp-card vsp-kpi-card");
        var title = q(card, ".title, .kpi-title, h4, h5"); if (title) add(title, "vsp-kpi-title");
        var val   = q(card, ".value, .kpi-value, .num, .number, strong"); if (val) add(val, "vsp-kpi-value");
        var sub   = q(card, ".sub, .hint, .desc, small"); if (sub) add(sub, "vsp-kpi-sub");
      });

      // Panels: ONLY known dashboard sections (cap)
      var panels = qa(root, ".vsp-panel, [data-panel], .vsp-section");
      if (panels.length > 40) panels = panels.slice(0, 40);
      panels.forEach(function(el){ add(el, "vsp-panel"); });

      // Tables: cap
      var tables = qa(root, "table");
      if (tables.length > 12) tables = tables.slice(0, 12);
      tables.forEach(function(tbl){
        var host = tbl.closest(".vsp-table-tight") || tbl.parentElement;
        if (host) add(host, "vsp-table-tight");
      });

      window.__VSP_P2_POLISH_SAFE_V2__.applied = true;
    }catch(e){
      window.__VSP_P2_POLISH_SAFE_V2__.err = String(e && e.message ? e.message : e);
    }
  }

  // Defer to idle to avoid blocking first paint
  onReady(function(){
    if ("requestIdleCallback" in window) requestIdleCallback(apply, {timeout: 800});
    else setTimeout(apply, 120);
  });
})();
JS
ok "write safe JS: $JS2"

# 3) Inject SAFE v2 into templates (idempotent), and REMOVE old v1 injection if present
python3 - <<'PY'
from pathlib import Path
import re

tpl_dir = Path("templates")
if not tpl_dir.exists():
    print("[WARN] templates/ not found; skip")
    raise SystemExit(0)

JS_SAFE = "vsp_polish_apply_p2_safe_v2.js"
JS_OLD  = "vsp_polish_apply_p2_v1.js"

files = sorted(tpl_dir.rglob("*.html"))
patched = 0
for p in files:
    s = p.read_text(encoding="utf-8", errors="replace")
    if "vsp_cio_shell_apply_v1.js" not in s:
        continue
    orig = s

    # remove old v1 script tag if any
    s = re.sub(r'\s*<script[^>]+/static/js/' + re.escape(JS_OLD) + r'[^>]*></script>\s*', '\n', s)

    # ensure safe v2 is included once (near CIO apply)
    if JS_SAFE not in s:
        m = re.search(r'(<script[^>]+vsp_cio_shell_apply_v1\.js[^>]*></script>)', s)
        if m:
            s = s.replace(m.group(1), m.group(1) + f'\n  <script src="/static/js/{JS_SAFE}?v=p2_safe"></script>', 1)
        else:
            s = re.sub(r'(</body>)', f'  <script src="/static/js/{JS_SAFE}?v=p2_safe"></script>\n\\1', s, count=1)

    if s != orig:
        b = p.with_suffix(p.suffix + ".bak_p2safe")
        if not b.exists():
            b.write_text(orig, encoding="utf-8")
        p.write_text(s, encoding="utf-8")
        patched += 1

print(f"[OK] templates_patched={patched}")
PY

# 4) Restart service
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.4
  systemctl is-active "$SVC" >/dev/null 2>&1 && ok "service active: $SVC" || warn "service not active; check systemctl status $SVC"
else
  warn "no systemctl; skip restart"
fi

# 5) Quick smoke (server side)
fetch "$BASE/vsp5" && ok "GET /vsp5 OK" || err "GET /vsp5 FAIL"
fetch "$BASE/static/js/vsp_polish_apply_p2_safe_v2.js" && ok "SAFE JS served" || err "SAFE JS not served"
[ -f "$CSS1" ] && ok "CSS exists: $CSS1" || warn "missing CSS: $CSS1"

ok "RESCUE DONE. Now refresh browser (Ctrl+F5) on /vsp5."
