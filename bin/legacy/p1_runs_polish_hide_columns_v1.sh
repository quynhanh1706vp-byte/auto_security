#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sudo; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_runs_reports_v1.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

MARK="VSP_P1_RUNS_POLISH_HIDE_COLS_V1"
if grep -q "$MARK" "$TPL"; then
  echo "[OK] already patched: $TPL"
  exit 0
fi

cp -f "$TPL" "${TPL}.bak_polish_${TS}"
echo "[BACKUP] ${TPL}.bak_polish_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("templates/vsp_runs_reports_v1.html")
s=p.read_text(encoding="utf-8", errors="replace")

inject = r"""
<!-- VSP_P1_RUNS_POLISH_HIDE_COLS_V1 -->
<script>
(function(){
  // columns to hide by header text (case-insensitive)
  const HIDE = new Set(["json","csv","sarif","summary"]); // keep "Artifacts" + "Export"
  function norm(t){ return (t||"").trim().toLowerCase(); }

  function hideCols(){
    const table=document.querySelector('table');
    if(!table) return;
    const ths=[...table.querySelectorAll('thead th')];
    if(!ths.length) return;

    const idxToHide=[];
    ths.forEach((th,i)=>{
      const txt = norm(th.innerText);
      if(HIDE.has(txt)){
        idxToHide.push(i);
      }
    });

    if(!idxToHide.length) return;

    // hide headers
    idxToHide.forEach(i=>{
      if(ths[i]) ths[i].style.display='none';
    });

    // hide each row's corresponding td
    const rows=[...table.querySelectorAll('tbody tr')];
    rows.forEach(tr=>{
      const tds=[...tr.children];
      idxToHide.forEach(i=>{
        if(tds[i]) tds[i].style.display='none';
      });
    });
  }

  document.addEventListener('DOMContentLoaded', hideCols);
})();
</script>
<!-- /VSP_P1_RUNS_POLISH_HIDE_COLS_V1 -->
"""

if "</body>" in s:
  s = s.replace("</body>", inject + "\n</body>", 1)
else:
  s += "\n" + inject

p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

sudo systemctl restart vsp-ui-8910.service

curl -fsS http://127.0.0.1:8910/runs | grep -q "$MARK" && echo "[OK] /runs polish injected"
