#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sudo; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_runs_reports_v1.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

MARK="VSP_P1_RUNS_POLISH_BADGES_V1"
if grep -q "$MARK" "$TPL"; then
  echo "[OK] already patched: $TPL"
  exit 0
fi

cp -f "$TPL" "${TPL}.bak_badges_${TS}"
echo "[BACKUP] ${TPL}.bak_badges_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("templates/vsp_runs_reports_v1.html")
s=p.read_text(encoding="utf-8", errors="replace")

inject = r"""
<!-- VSP_P1_RUNS_POLISH_BADGES_V1 -->
<style>
.vsp-badge{ display:inline-flex; align-items:center; gap:6px; padding:3px 10px; border-radius:999px;
  font-size:12px; border:1px solid rgba(148,163,184,.25); background:rgba(15,23,42,.45); color:#e2e8f0; }
.vsp-badge-ok{ border-color:rgba(34,197,94,.35); background:rgba(34,197,94,.12); color:#86efac; }
.vsp-badge-no{ border-color:rgba(239,68,68,.25); background:rgba(239,68,68,.10); color:#fca5a5; }
.vsp-badge small{ font-size:11px; opacity:.9; }
</style>
<script>
(function(){
  function norm(t){ return (t||'').trim().toLowerCase(); }
  function toBadge(val){
    const v = norm(val);
    if(v==='true'){
      return '<span class="vsp-badge vsp-badge-ok">✅ <small>HAS</small></span>';
    }
    if(v==='false'){
      return '<span class="vsp-badge vsp-badge-no">❌ <small>MISS</small></span>';
    }
    return null;
  }
  function run(){
    const table=document.querySelector('table');
    if(!table) return;
    const cells=[...table.querySelectorAll('tbody td')];
    for(const td of cells){
      // only convert plain text true/false
      if(td.children.length>0) continue;
      const rep = toBadge(td.textContent);
      if(rep) td.innerHTML = rep;
    }
  }
  document.addEventListener('DOMContentLoaded', run);
})();
</script>
<!-- /VSP_P1_RUNS_POLISH_BADGES_V1 -->
"""

if "</body>" in s:
  s = s.replace("</body>", inject + "\n</body>", 1)
else:
  s += "\n" + inject

p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

sudo systemctl restart vsp-ui-8910.service
curl -fsS http://127.0.0.1:8910/runs | grep -q "$MARK" && echo "[OK] /runs badges injected"
