#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_toollane_${TS}"
echo "[BACKUP] ${JS}.bak_toollane_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Patch KPI TOTAL fallback (sum severities if TOTAL missing)
# Find the section that defines setK and sets #k_total.. and replace with improved version.
pattern_kpi = re.compile(r"""
const\s+setK\s*=\s*\(id,val\)\s*=>\s*\{\s*const\s+el=\$\((id)\);\s*if\(el\)\s*el\.textContent\s*=\s*\(val==null\?\s*["']—["']:\s*String\(val\)\);\s*\};\s*
\s*
setK\(\s*["']#k_total["']\s*,\s*[^;]*\);\s*
setK\(\s*["']#k_crit["']\s*,\s*[^;]*\);\s*
setK\(\s*["']#k_high["']\s*,\s*[^;]*\);\s*
setK\(\s*["']#k_med["']\s*,\s*[^;]*\);\s*
setK\(\s*["']#k_low["']\s*,\s*[^;]*\);\s*
setK\(\s*["']#k_info["']\s*,\s*[^;]*\);\s*
setK\(\s*["']#k_trace["']\s*,\s*[^;]*\);\s*
""", re.X | re.S)

repl_kpi = r"""
    const setK = (id,val)=> { const el=$(id); if(el) el.textContent = (val==null? "—": String(val)); };

    const crit = (c.CRITICAL ?? c.critical);
    const high = (c.HIGH ?? c.high);
    const med  = (c.MEDIUM ?? c.medium);
    const low  = (c.LOW ?? c.low);
    const info = (c.INFO ?? c.info);
    const trace= (c.TRACE ?? c.trace);

    let total = (c.TOTAL ?? c.total ?? state.gate?.counts_total?.TOTAL);
    if (total == null){
      const nums = [crit,high,med,low,info,trace].map(x=> (x==null? 0 : Number(x)||0));
      total = nums.reduce((a,b)=>a+b,0);
    }

    setK("#k_total", total);
    setK("#k_crit",  crit);
    setK("#k_high",  high);
    setK("#k_med",   med);
    setK("#k_low",   low);
    setK("#k_info",  info);
    setK("#k_trace", trace);
"""

if pattern_kpi.search(s):
    s = pattern_kpi.sub(repl_kpi, s, count=1)
else:
    print("[WARN] KPI block not matched (skip)")

# 2) Patch Tool lane rendering to handle by_tool object + key variants
pattern_tools = re.compile(r"""
const\s+toolsBox\s*=\s*\$\(\s*["']#tools_box["']\s*\);\s*
if\s*\(toolsBox\)\s*\{\s*
const\s+tools\s*=\s*state\.tools\s*\|\|\s*\{\}\s*;\s*
const\s+order\s*=\s*\[[^\]]*\]\s*;\s*
toolsBox\.innerHTML\s*=\s*order\.map\(\s*t\s*=>\s*\{\s*
const\s+st\s*=\s*String\([^\)]*\)\.toUpperCase\(\);\s*
const\s+cls\s*=\s*\([^\n]*\);\s*
return\s+`<div class="tool">[\s\S]*?`;\s*
\}\)\.join\(["']["']\);\s*
\}\s*
""", re.X | re.S)

repl_tools = r"""
    const toolsBox = $("#tools_box");
    if (toolsBox){
      const raw = state.tools || {};
      // normalize keys: case-insensitive + strip non-alnum
      const normKey = (k)=> String(k||"").toLowerCase().replace(/[^a-z0-9]+/g,"");
      const normMap = {};
      try{
        for (const [k,v] of Object.entries(raw||{})){
          normMap[normKey(k)] = v;
        }
      }catch(_e){}

      const pick = (toolName)=>{
        const k1 = normKey(toolName);
        const k2 = normKey(toolName.replace("CodeQL","codeql").replace("Gitleaks","gitleaks"));
        // common variants
        const variants = [k1,k2,
          normKey(toolName+"Summary"),
          normKey(toolName+"_summary"),
          normKey(toolName+"Tool"),
        ];
        for (const k of variants){
          if (k && (k in normMap)) return normMap[k];
        }
        return null;
      };

      const statusOf = (v)=>{
        if (v == null) return "UNKNOWN";
        if (typeof v === "string") return v.toUpperCase();
        if (typeof v === "boolean") return v ? "OK" : "FAIL";
        if (typeof v === "object"){
          const cand = v.status ?? v.state ?? v.result ?? v.verdict ?? v.outcome;
          if (typeof cand === "string") return cand.toUpperCase();
          if (typeof cand === "boolean") return cand ? "OK" : "FAIL";
          if (v.ok === true) return "OK";
          if (v.missing === true) return "MISSING";
          if (v.degraded === true) return "DEGRADED";
        }
        return "UNKNOWN";
      };

      const order = ["Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","Bandit","CodeQL"];
      toolsBox.innerHTML = order.map(t=>{
        const v = pick(t);
        const st = statusOf(v);
        const cls = (st==="OK") ? "s-ok" : (st==="MISSING" || st==="DEGRADED") ? "s-miss" : (st==="FAIL" || st==="ERROR") ? "s-bad" : "";
        return `<div class="tool"><div class="t">${esc(t)}</div><div class="s ${cls}">${esc(st)}</div></div>`;
      }).join("");
    }
"""

if pattern_tools.search(s):
    s = pattern_tools.sub(repl_tools, s, count=1)
else:
    print("[WARN] tools block not matched (skip)")

p.write_text(s, encoding="utf-8")
print("[OK] patched vsp_dash_only_v1.js")
PY

echo "== restart service (best effort) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
fi

echo "== quick verify (rid_latest + run_gate_summary) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("rid",""))' 2>/dev/null || true)"
echo "[RID]=$RID"
if [ -n "$RID" ]; then
  curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | head -c 200; echo
fi

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Tool lane should show OK/MISSING, not UNKNOWN/[object Object]."
