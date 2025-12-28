#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_runs_kpi_compact_v3.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_runsdrawer_v1b_${TS}"
echo "[BACKUP] ${JS}.bak_runsdrawer_v1b_${TS}"

python3 - "$JS" <<'PY'
import sys, re
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_P2_RUNS_DRILLDOWN_DRAWER_V1B_PATHS" in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Replace inside V1 drawer: extend candidate paths lists and render debug
def sub_once(pattern, repl):
    global s
    s2=re.sub(pattern, repl, s, count=1, flags=re.S)
    if s2==s: 
        raise SystemExit(f"[ERR] cannot locate pattern for patch: {pattern[:60]}...")
    s=s2

# 1) insert path arrays after rf() helper
sub_once(
    r'(async function rf\(path\)\{\s*return await jget\(`\/api\/vsp\/run_file_allow\?\$\{encodeURIComponent\(rid\)\}[^`]*`\);\s*\}\s*)',
    r'''\1
    const gatePaths=["run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json","run_gate.json","reports/run_gate.json","report/run_gate.json"];
    const findPaths=["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"];
'''
)

# 2) replace gate lookup block
sub_once(
    r'// Gate summary\s+let gatePath="run_gate_summary\.json";\s+let gate=await rf\(gatePath\);\s+if\(!\(gate\.ok[\s\S]*?\)\)\{\s+gatePath="reports\/run_gate_summary\.json";\s+gate=await rf\(gatePath\);\s*\}\s*',
    r'''// Gate summary (try multiple paths)
    let gatePath="";
    let gate=null;
    for(const gp of gatePaths){
      const g=await rf(gp);
      if(g && g.ok && g.json && g.json.ok){ gatePath=gp; gate=g; break; }
      // sometimes backend returns ok without wrapper; accept if has counts/points
      if(g && g.ok && g.json && (g.json.by_severity || g.json.counts_total || g.json.by_tool)){ gatePath=gp; gate=g; break; }
    }
    if(!gate){ gate=await rf("run_gate_summary.json"); gatePath="run_gate_summary.json"; }
'''
)

# 3) replace findings lookup block
sub_once(
    r'// Findings json\s+let findPath="findings_unified\.json";\s+let fj=await rf\(findPath\);\s+if\(!\(fj\.ok[\s\S]*?\)\)\{\s+findPath="reports\/findings_unified\.json";\s+fj=await rf\(findPath\);\s*\}\s*',
    r'''// Findings json (try multiple paths)
    let findPath="";
    let fj=null;
    for(const fp of findPaths){
      const f=await rf(fp);
      if(f && f.ok && f.json && f.json.ok){ findPath=fp; fj=f; break; }
      if(f && f.ok && f.json && (f.json.findings || f.json.items || Array.isArray(f.json))){ findPath=fp; fj=f; break; }
    }
    if(!fj){ fj=await rf("findings_unified.json"); findPath="findings_unified.json"; }
'''
)

# 4) make action hrefs robust + show debug
sub_once(
    r'body\.innerHTML = `([\s\S]*?)Tip: Use “Open Dashboard”',
    r'''body.innerHTML = `
      <div style="font-size:12px;opacity:.75;letter-spacing:.08em;text-transform:uppercase;margin-bottom:10px">Severity</div>
      ${sevBadgeRow(counts)}
      <div style="height:12px"></div>
      <div style="font-size:12px;opacity:.75;letter-spacing:.08em;text-transform:uppercase;margin-bottom:8px">Resolved paths</div>
      <div style="padding:10px 12px;border-radius:14px;border:1px solid rgba(255,255,255,0.10);background:rgba(255,255,255,0.03)">
        <div style="opacity:.85">Gate: <span style="font-family:ui-monospace, SFMono-Regular, Menlo, monospace">${esc(gatePath||"—")}</span></div>
        <div style="opacity:.85;margin-top:6px">Findings: <span style="font-family:ui-monospace, SFMono-Regular, Menlo, monospace">${esc(findPath||"—")}</span></div>
      </div>
      <div style="height:10px"></div>
      <div style="opacity:.7;font-size:12px">Tip: Use “Open Dashboard”'''
)

# Tag marker
s += "\n/* VSP_P2_RUNS_DRILLDOWN_DRAWER_V1B_PATHS */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched v1 -> v1b paths")
PY

node -c "$JS"
echo "[OK] node -c OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

grep -n "VSP_P2_RUNS_DRILLDOWN_DRAWER_V1B_PATHS" -n "$JS" | head -n 3
