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
cp -f "$JS" "${JS}.bak_runsdrawer_v1b2_${TS}"
echo "[BACKUP] ${JS}.bak_runsdrawer_v1b2_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

need_marker="VSP_P2_RUNS_DRILLDOWN_DRAWER_V1"
if need_marker not in s:
    print("[ERR] drawer v1 marker not found; abort to avoid patching wrong file")
    raise SystemExit(2)

marker="VSP_P2_RUNS_DRILLDOWN_DRAWER_V1B_PATHS_V2"
if marker in s:
    print("[OK] already patched v1b_paths_v2")
    raise SystemExit(0)

# We patch INSIDE loadRunDetail() by using comment anchors we inserted in V1:
#   "// Gate summary"
#   "// Findings json"
#   "// set action hrefs"
gate_anchor = "    // Gate summary"
find_anchor = "    // Findings json"
href_anchor = "    // set action hrefs"

i_gate = s.find(gate_anchor)
i_find = s.find(find_anchor)
i_href = s.find(href_anchor)

if min(i_gate, i_find, i_href) < 0 or not (i_gate < i_find < i_href):
    print("[ERR] cannot locate anchors in expected order (Gate -> Findings -> hrefs).")
    print("      found:", i_gate, i_find, i_href)
    raise SystemExit(2)

# Insert path arrays right BEFORE gate_anchor (so they live in same scope)
insert_block = (
    "    const gatePaths=[\n"
    "      \"run_gate_summary.json\",\n"
    "      \"reports/run_gate_summary.json\",\n"
    "      \"report/run_gate_summary.json\",\n"
    "      \"run_gate.json\",\n"
    "      \"reports/run_gate.json\",\n"
    "      \"report/run_gate.json\"\n"
    "    ];\n"
    "    const findPaths=[\n"
    "      \"findings_unified.json\",\n"
    "      \"reports/findings_unified.json\",\n"
    "      \"report/findings_unified.json\"\n"
    "    ];\n\n"
)

# Only insert if not already present
if "const gatePaths" not in s[i_gate-400:i_gate+200]:
    s = s[:i_gate] + insert_block + s[i_gate:]
    # anchors shift after insertion; re-find
    i_gate = s.find(gate_anchor)
    i_find = s.find(find_anchor)
    i_href = s.find(href_anchor)

# Replace Gate block: from gate_anchor up to just before find_anchor
gate_new = (
    "    // Gate summary (try multiple paths)\n"
    "    let gatePath=\"\";\n"
    "    let gate=null;\n"
    "    for(const gp of gatePaths){\n"
    "      const g=await rf(gp);\n"
    "      // wrapper style: {ok:true, ...}\n"
    "      if(g && g.ok && g.json && g.json.ok){ gatePath=gp; gate=g; break; }\n"
    "      // direct style: gate summary JSON\n"
    "      if(g && g.ok && g.json && (g.json.by_severity || g.json.counts_total || g.json.by_tool)){\n"
    "        gatePath=gp; gate=g; break;\n"
    "      }\n"
    "    }\n"
    "    if(!gate){ gatePath=\"run_gate_summary.json\"; gate=await rf(gatePath); }\n\n"
)

s = s[:i_gate] + gate_new + s[i_find:]

# Recompute anchors after replacement
i_find = s.find(find_anchor)
i_href = s.find(href_anchor)
if min(i_find, i_href) < 0 or not (i_find < i_href):
    print("[ERR] anchors lost after gate replacement")
    raise SystemExit(2)

# Replace Findings block: from find_anchor up to just before href_anchor
find_new = (
    "    // Findings json (try multiple paths)\n"
    "    let findPath=\"\";\n"
    "    let fj=null;\n"
    "    for(const fp of findPaths){\n"
    "      const f=await rf(fp);\n"
    "      if(f && f.ok && f.json && f.json.ok){ findPath=fp; fj=f; break; }\n"
    "      if(f && f.ok && f.json && (f.json.findings || f.json.items || Array.isArray(f.json))){ findPath=fp; fj=f; break; }\n"
    "    }\n"
    "    if(!fj){ findPath=\"findings_unified.json\"; fj=await rf(findPath); }\n\n"
)

s = s[:i_find] + find_new + s[i_href:]

# Append marker
s += f"\n/* {marker} */\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched v1 -> v1b_paths_v2")
PY

node -c "$JS"
echo "[OK] node -c OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

grep -n "VSP_P2_RUNS_DRILLDOWN_DRAWER_V1B_PATHS_V2" -n "$JS" | head -n 3
