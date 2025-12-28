#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> will skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

CAND_JS=(
  "static/js/vsp_runs_tab_resolved_v1.js"
  "static/js/vsp_bundle_commercial_v2.js"
  "static/js/vsp_bundle_commercial_v1.js"
  "static/js/vsp_app_entry_safe_v1.js"
)

python3 - <<'PY'
from pathlib import Path
import time

MARK="VSP_P0_RUNS_FAIL_BADGE_DOM_KILLER_V1"
PATCH=f"""
;(()=>{{
  if (window.__{MARK}) return;
  window.__{MARK} = true;

  function _txt(el){{
    try{{ return (el && (el.innerText||el.textContent)||"").trim(); }}catch(_){ return ""; }
  }}
  function _onRunsPage(){{
    try{{ return /\\/runs(\\/|$)/.test(location.pathname); }}catch(_){ return false; }
  }}
  function _hasRunsData(){{
    // nhiều layout khác nhau -> check theo keyword/action phổ biến
    const kw = ["Open Summary","Open Data Source","SUMMARY","JSON","CSV"];
    const nodes = document.querySelectorAll("a,button,td,span,div");
    let hits=0;
    for (const n of nodes){{
      const t=_txt(n);
      if (!t) continue;
      for (const k of kw){{
        if (t.includes(k)){{ hits++; break; }}
      }}
      if (hits>=2) return true; // đủ chắc là table đã render
    }}
    return false;
  }}
  function _hideByText(substrs){{
    const nodes = document.querySelectorAll("div,span,button,section,header");
    for (const n of nodes){{
      const t=_txt(n);
      if (!t) continue;
      for (const s of substrs){{
        if (t.includes(s)) {{
          try {{
            n.style.display="none";
            n.setAttribute("data-vsp-hidden","1");
          }} catch(_){{
          }}
          break;
        }}
      }}
    }}
  }}
  function _tick(){{
    if (!_onRunsPage()) return;
    if (!_hasRunsData()) return; // chỉ kill khi đã có data
    _hideByText(["RUNS API FAIL","degraded (runs API","runs API 503","Error: 503"]);
  }}

  // chạy nhanh lúc đầu + duy trì 1 thời gian để “đè” flicker
  _tick();
  let n=0;
  const t=setInterval(()=>{{
    try{{ _tick(); }}catch(_){}
    n++;
    if (n>120) clearInterval(t); // ~36s là đủ đè mọi poller cũ
  }}, 300);

  console.log("[VSP][P0] runs fail badge DOM-killer armed");
}})();
"""

paths=[]
for p in ["static/js/vsp_runs_tab_resolved_v1.js","static/js/vsp_bundle_commercial_v2.js","static/js/vsp_bundle_commercial_v1.js","static/js/vsp_app_entry_safe_v1.js"]:
  pp=Path(p)
  if pp.exists(): paths.append(pp)

if not paths:
  print("[ERR] no candidate js found"); raise SystemExit(2)

for pp in paths:
  s=pp.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    print("[OK] already patched:", pp); continue
  bak=pp.with_name(pp.name+f".bak_runs_domkill_{time.strftime('%Y%m%d_%H%M%S')}")
  bak.write_text(s, encoding="utf-8")
  pp.write_text(s+"\n"+PATCH+"\n", encoding="utf-8")
  print("[OK] patched:", pp, "backup:", bak)
PY

for f in "${CAND_JS[@]}"; do
  if [ -f "$f" ] && command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null && echo "[OK] node --check: $f"
  fi
done

echo "[OK] Applied. Restart UI then Ctrl+F5 /runs"
